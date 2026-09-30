import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import sys
import unittest
from unittest.mock import Mock, patch

from test_bridge import bridge


class CompareTests(unittest.TestCase):
    def args(self, *extra):
        return bridge.parser().parse_args(['compare', '--repo', 'alice/data', '--type', 'dataset', *extra])

    def test_exact_files_and_directories_match_but_ancestor_conflicts_are_not_detected(self):
        folder = type('RepoFolder', (), {})()
        folder.path = 'dest/folder.bin'
        api = Mock()
        api.list_repo_tree.return_value = iter([folder, SimpleNamespace(path='dest/a/ü file.bin'), SimpleNamespace(path='dest/ancestor'), SimpleNamespace(path='dest/other.txt')])
        args = self.args('--destination', 'dest', '--file', 'a/ü file.bin', '--file', 'folder.bin', '--file', 'ancestor/nested.bin', '--file', 'missing')
        self.assertEqual(bridge.compare_paths(args, api), {'paths': ['a/ü file.bin', 'folder.bin'], 'complete': True})
        api.list_repo_tree.assert_called_once_with(repo_id='alice/data', repo_type='dataset', path_in_repo='dest', recursive=True)

    def test_cap_marks_listing_incomplete_without_inventing_absence(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path='found'), SimpleNamespace(path='other'), SimpleNamespace(path='later')])
        self.assertEqual(bridge.compare_paths(self.args('--file', 'found', '--file', 'later'), api, entry_limit=2), {'paths': ['found'], 'complete': False})

    def test_all_requested_found_is_complete_even_at_cap(self):
        api = Mock()
        api.list_repo_tree.return_value = iter([SimpleNamespace(path='found')])
        self.assertEqual(bridge.compare_paths(self.args('--file', 'found'), api, entry_limit=1), {'paths': ['found'], 'complete': True})

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
        self.assertEqual(bridge.compare_paths(self.args(), api), {'paths': [], 'complete': True})
        api.list_repo_tree.assert_not_called()

    def test_missing_destination_only_converts_entry_error(self):
        class EntryNotFoundError(Exception):
            pass
        class RepositoryNotFoundError(Exception):
            pass
        api = Mock()
        args = self.args('--destination', 'new', '--file', 'a.bin')
        with patch.dict(sys.modules, {'huggingface_hub.errors': SimpleNamespace(EntryNotFoundError=EntryNotFoundError)}):
            api.list_repo_tree.side_effect = EntryNotFoundError('missing folder')
            self.assertEqual(bridge.compare_paths(args, api), {'paths': [], 'complete': True})
            with self.assertRaises(EntryNotFoundError):
                bridge.compare_paths(self.args('--file', 'a.bin'), api)
            for error in (RepositoryNotFoundError('missing repo'), ConnectionError('offline'), PermissionError('unauthorized')):
                api.list_repo_tree.side_effect = error
                with self.assertRaises(type(error)):
                    bridge.compare_paths(args, api)

    def test_failure_after_partial_listing_is_not_reported_complete(self):
        class EntryNotFoundError(Exception):
            pass
        def failing():
            yield SimpleNamespace(path='dest/found')
            raise EntryNotFoundError('changed during listing')
        api = Mock()
        api.list_repo_tree.return_value = failing()
        with self.assertRaises(EntryNotFoundError):
            bridge.compare_paths(self.args('--destination', 'dest', '--file', 'found', '--file', 'missing'), api)


if __name__ == '__main__':
    unittest.main()
