import json
from pathlib import Path
import sqlite3
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from test_bridge import bridge


def folder(path):
    entry = type('RepoFolder', (), {})()
    entry.path = path
    return entry


class CompareTests(unittest.TestCase):
    def args(self, *extra):
        return bridge.parser().parse_args(['compare', '--repo', 'alice/data', '--type', 'dataset', *extra])

    def test_exact_file_directory_and_ancestor_conflicts(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([folder('dest/folder.bin'), SimpleNamespace(path='dest/a/ü file.bin'), SimpleNamespace(path='dest/ancestor'), SimpleNamespace(path='dest/other.txt')])
        args = self.args('--destination', 'dest', '--file', 'a/ü file.bin', '--file', 'folder.bin', '--file', 'ancestor/nested.bin', '--file', 'missing')
        result = bridge.compare_paths(args, api)
        self.assertEqual(result['paths'], ['a/ü file.bin', 'folder.bin'])
        self.assertEqual({c['path'] for c in result['conflicts']}, {'folder.bin', 'ancestor/nested.bin'})
        self.assertTrue(result['complete'])
        self.assertIn('is a folder', next(c['reason'] for c in result['conflicts'] if c['path'] == 'folder.bin'))
        self.assertIn('is a file', next(c['reason'] for c in result['conflicts'] if c['path'] == 'ancestor/nested.bin'))
        api.list_repo_tree.assert_called_once_with(repo_id='alice/data', repo_type='dataset', path_in_repo=None, recursive=True)

    def test_file_at_destination_ancestor_blocks_every_staged_file(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path='models')])
        args = self.args('--destination', 'models/checkpoint', '--file', 'weights.bin', '--file', 'config/config.json')
        result = bridge.compare_paths(args, api)
        self.assertTrue(result['complete'])
        self.assertEqual(result['paths'], [])
        self.assertEqual({c['path'] for c in result['conflicts']}, {'weights.bin', 'config/config.json'})

    def test_prefix_wildcards_unicode_and_sibling_names_are_literal(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path='dest/a_%ü'), SimpleNamespace(path='dest/foo')])
        args = self.args('--destination', 'dest', '--file', 'a_%ü/yes.bin', '--file', 'a_OTHER/no.bin', '--file', 'foobar/no.bin')
        result = bridge.compare_paths(args, api)
        self.assertEqual([c['path'] for c in result['conflicts']], ['a_%ü/yes.bin'])
        self.assertTrue(result['complete'])

    def test_cap_marks_listing_incomplete_without_inventing_absence(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path='found'), SimpleNamespace(path='other'), SimpleNamespace(path='later')])
        self.assertEqual(bridge.compare_paths(self.args('--file', 'found', '--file', 'later'), api, entry_limit=2), {'paths': ['found'], 'conflicts': [], 'complete': False})

    def test_all_requested_found_is_complete_even_at_cap(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path='found')])
        self.assertEqual(bridge.compare_paths(self.args('--file', 'found'), api, entry_limit=1), {'paths': ['found'], 'conflicts': [], 'complete': True})

    def test_manifest_accepts_many_unicode_paths_without_argv_growth(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest.json'
            names = [f'nested/ü {index}.bin' for index in range(2000)]
            path.write_text(json.dumps(names))
            api = Mock()
            api.list_repo_tree.return_value = (SimpleNamespace(path=name) for name in names)
            result = bridge.compare_paths(self.args('--manifest', str(path)), api)
            self.assertTrue(result['complete'])
            self.assertEqual(set(result['paths']), set(names))
            self.assertEqual(result['conflicts'], [])

    def test_bad_manifest_and_excess_paths_rejected_before_network(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest.json'
            for value in ({'paths': []}, [12], ['../escape'], ['name'] * 2001):
                path.write_text(json.dumps(value))
                api = Mock()
                with self.assertRaises(ValueError):
                    bridge.compare_paths(self.args('--manifest', str(path)), api)
                api.list_repo_tree.assert_not_called()
        for name in ('/absolute', '', 'folder/', 'a/../bad'):
            with self.assertRaises(ValueError):
                bridge.compare_paths(self.args('--file', name), Mock())

    def test_empty_manifest_is_complete_without_network(self):
        api = Mock()
        self.assertEqual(bridge.compare_paths(self.args(), api), {'paths': [], 'conflicts': [], 'complete': True})
        api.list_repo_tree.assert_not_called()

    def test_missing_destination_is_absent_in_root_listing(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path='unrelated')])
        self.assertEqual(bridge.compare_paths(self.args('--destination', 'new', '--file', 'a.bin'), api), {'paths': [], 'conflicts': [], 'complete': True})

    def test_all_root_listing_errors_propagate_even_with_destination(self):
        class EntryNotFoundError(Exception):
            pass
        for error in (EntryNotFoundError('missing root'), ConnectionError('offline'), PermissionError('unauthorized')):
            api = Mock()
            api.list_repo_tree.side_effect = error
            with self.assertRaises(type(error)):
                bridge.compare_paths(self.args('--destination', 'new', '--file', 'a.bin'), api)

    def test_failure_after_partial_listing_is_not_reported_complete(self):
        def failing():
            yield SimpleNamespace(path='dest/found')
            raise ConnectionError('changed during listing')
        api = Mock()
        api.list_repo_tree.return_value = failing()
        with self.assertRaises(ConnectionError):
            bridge.compare_paths(self.args('--destination', 'dest', '--file', 'found', '--file', 'missing'), api)

    def test_upload_index_checks_all_paths_beyond_preview_limit(self):
        with sqlite3.connect(':memory:') as database:
            index = bridge.PathIndex(database, 'dest')
            for number in range(2501):
                index.add(f'file-{number:04}.bin')
            api = Mock()
            api.list_repo_tree.return_value = iter([folder('dest/file-2500.bin')])
            with self.assertRaisesRegex(ValueError, 'file-2500.bin'):
                bridge.validate_upload_paths(self.args(), api, index)


if __name__ == '__main__':
    unittest.main()
