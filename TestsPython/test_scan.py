"""Metadata scan tests; optional installed-SDK test verifies the production matcher."""
import fnmatch
import importlib.util
import os
from pathlib import Path
import tempfile
import io
import sys
import unittest
from unittest.mock import Mock, patch

from test_bridge import bridge

# Test double for the SDK collaborator; production always imports the SDK.
# Actual installed-SDK verification below uses no network or credentials.
DEFAULT_IGNORES = ['.git', '.git/*', '*/.git', '**/.git/**', '.cache/huggingface', '.cache/huggingface/*', '*/.cache/huggingface', '**/.cache/huggingface/**']


def test_filter(items, *, allow_patterns=None, ignore_patterns=None):
    def matches(path, patterns):
        return any(fnmatch.fnmatchcase(path.replace('\\', '/'), p.replace('\\', '/') + ('*' if p.endswith('/') else '')) for p in patterns)
    for item in items:
        if allow_patterns is not None and not matches(item, allow_patterns):
            continue
        if ignore_patterns is not None and matches(item, ignore_patterns):
            continue
        yield item


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def file(self, relative, contents=b'123'):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        return path

    def scan(self, *filters, **kwargs):
        args = bridge.parser().parse_args(['scan', '--source', str(self.root), *filters])
        return bridge.scan_folder(args, filter_objects=test_filter, default_ignores=DEFAULT_IGNORES, **kwargs)

    def test_root_nested_unicode_and_case_sensitive_patterns(self):
        self.file('root.json', b'12')
        self.file('nested/ü space.json', b'12345')
        self.file('nested/no.JSON', b'x')
        self.file('notes.txt', b'no')
        scan = self.scan('--include', '*.json')
        self.assertEqual(scan['total_count'], 4)
        self.assertEqual(scan['included_count'], 2)
        self.assertEqual(scan['included_bytes'], 7)
        self.assertEqual({r['path'] for r in scan['files'] if r['included']}, {'root.json', 'nested/ü space.json'})

    def test_trailing_slash_filter_and_star_crosses_directories(self):
        self.file('data/deep/yes.json')
        self.file('data/no.txt')
        self.file('other/yes.json')
        scan = self.scan('--include', 'data/', '--exclude', '*.txt')
        self.assertEqual([r['path'] for r in scan['files'] if r['included']], ['data/deep/yes.json'])
        self.assertEqual(self.scan('--include', 'data/*.json')['included_count'], 1)

    def test_internal_cache_and_git_are_omitted_at_any_depth(self):
        for name in ['.git/config', 'nested/.git/objects/abc', '.cache/huggingface/download/file', 'nested/.cache/huggingface/upload/file']:
            self.file(name)
        self.file('.cache/other/cache.txt', b'1234')
        self.file('normal.txt', b'12')
        scan = self.scan()
        self.assertEqual(scan['total_count'], 2)
        self.assertEqual(scan['included_bytes'], 6)
        self.assertEqual({r['path'] for r in scan['files']}, {'.cache/other/cache.txt', 'normal.txt'})

    def test_real_2000_row_cap_does_not_cap_totals(self):
        for index in range(2003):
            self.file(f'{index:04}.bin', b'12')
        scan = self.scan()
        self.assertEqual(len(scan['files']), 2000)
        self.assertEqual(scan['total_count'], 2003)
        self.assertEqual(scan['included_count'], 2003)
        self.assertEqual(scan['included_bytes'], 4006)
        self.assertTrue(scan['truncated'])

    def test_file_symlink_inside_counts_target_directory_symlink_not_followed(self):
        target = self.file('data/target.bin', b'12345')
        (self.root / 'alias.bin').symlink_to(target)
        (self.root / 'linked-directory').symlink_to(self.root / 'data', target_is_directory=True)
        scan = self.scan()
        self.assertEqual(scan['included_count'], 2)
        self.assertEqual(scan['included_bytes'], 10)

    def test_external_and_broken_links_fail_clearly(self):
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / 'external.bin'
            external.write_bytes(b'x')
            link = self.root / 'outside.bin'
            link.symlink_to(external)
            with self.assertRaisesRegex(ValueError, 'outside the selected folder'):
                self.scan()
            link.unlink()
        (self.root / 'broken.bin').symlink_to(self.root / 'missing')
        with self.assertRaisesRegex(ValueError, 'broken links'):
            self.scan()

    def test_traversal_permission_errors_are_not_silently_skipped(self):
        with patch.object(bridge.os, 'scandir', side_effect=PermissionError(13, 'Permission denied')):
            with self.assertRaisesRegex(ValueError, 'Cannot read folder'):
                self.scan()

    def test_unreadable_included_file_is_error(self):
        self.file('file.bin')
        with patch.object(bridge.os, 'access', return_value=False):
            with self.assertRaisesRegex(ValueError, 'Cannot read included file'):
                self.scan()

    def test_scan_never_opens_file_contents(self):
        self.file('file.bin')
        with patch('builtins.open', side_effect=AssertionError('Content read attempted')):
            self.assertEqual(self.scan()['included_bytes'], 3)

    def test_resume_rescans_source_and_rejects_new_external_link(self):
        self.file('original.bin')
        args = bridge.parser().parse_args(['upload', '--repo', 'alice/model', '--source', str(self.root)])
        real_scan = bridge.scan_folder
        def scan(args, **kwargs):
            return real_scan(args, filter_objects=test_filter, default_ignores=DEFAULT_IGNORES, **kwargs)
        bridge._STOPPING = False
        with patch.object(bridge, '_PROTOCOL', io.StringIO()), patch.object(bridge, 'scan_folder', side_effect=scan) as scanner, patch.object(bridge, 'upload_command', return_value=[sys.executable, '-c', 'pass']):
            api = Mock()
            api.list_repo_tree.return_value = []
            bridge.upload(args, api)
            with tempfile.TemporaryDirectory() as outside:
                target = Path(outside) / 'private.bin'
                target.write_bytes(b'synthetic')
                (self.root / 'new-link.bin').symlink_to(target)
                with patch.object(bridge.subprocess, 'Popen') as spawn:
                    with self.assertRaisesRegex(ValueError, 'outside the selected folder'):
                        bridge.upload(args, Mock())
                    spawn.assert_not_called()
            self.assertEqual(scanner.call_count, 2)

    def test_upload_blocks_conflict_beyond_preview_rows_before_cli_launch(self):
        for number in range(2003):
            self.file(f'{number:04}.bin', b'x')
        args = bridge.parser().parse_args(['upload', '--repo', 'alice/model', '--source', str(self.root), '--destination', 'dest'])
        real_scan = bridge.scan_folder
        def scan(args, **kwargs):
            return real_scan(args, filter_objects=test_filter, default_ignores=DEFAULT_IGNORES, **kwargs)
        remote_folder = type('RepoFolder', (), {})()
        remote_folder.path = 'dest/2002.bin'
        api = Mock()
        api.list_repo_tree.return_value = iter([remote_folder])
        bridge._STOPPING = False
        with patch.object(bridge, '_PROTOCOL', io.StringIO()), patch.object(bridge, 'scan_folder', side_effect=scan), patch.object(bridge, 'upload_command', return_value=['unused']), patch.object(bridge.subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(ValueError, '2002.bin'):
                bridge.upload(args, api)
            spawn.assert_not_called()

    def test_official_sdk_filter_when_installed(self):
        try:
            from huggingface_hub.utils import filter_repo_objects, DEFAULT_IGNORE_PATTERNS
        except ImportError:
            self.skipTest('Install pinned HF SDK to run the production matcher parity test.')
        for name in ['root.json', 'nested/ü space.json', 'nested/no.JSON', 'nested/deep/drop.json', '.git/config', '.cache/huggingface/hidden', 'nested/.cache/huggingface/hidden']:
            self.file(name)
        args = bridge.parser().parse_args(['scan', '--source', str(self.root), '--include', '*.json', '--exclude', 'nested/deep/'])
        actual = bridge.scan_folder(args)
        expected = set(filter_repo_objects(['root.json', 'nested/ü space.json', 'nested/no.JSON', 'nested/deep/drop.json', '.git/config', '.cache/huggingface/hidden', 'nested/.cache/huggingface/hidden'], allow_patterns=args.include, ignore_patterns=args.exclude + DEFAULT_IGNORE_PATTERNS))
        self.assertEqual({r['path'] for r in actual['files'] if r['included']}, expected)
        self.assertEqual(actual['included_count'], 2)


if __name__ == '__main__':
    unittest.main()
