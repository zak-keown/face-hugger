import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'notice_collector', Path(__file__).resolve().parents[1] / 'Scripts/collect-hf-xet-notices.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def archive(entries):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as tar:
        for name, data, kind in entries:
            item = tarfile.TarInfo(name)
            item.type = kind
            item.size = len(data) if kind == tarfile.REGTYPE else 0
            if kind == tarfile.SYMTYPE:
                item.linkname = '/tmp/outside'
            tar.addfile(item, io.BytesIO(data) if item.isfile() else None)
    return buffer.getvalue()


class NoticeCollectorTests(unittest.TestCase):
    def test_retains_nested_british_spelling_and_authors_without_source_or_links(self):
        data = archive([
            ('crate/LICENCE', b'license text', tarfile.REGTYPE),
            ('crate/vendor/AUTHORS.md', b'authors', tarfile.REGTYPE),
            ('crate/NOTICE', b'', tarfile.SYMTYPE),
            ('crate/build.rs', b'never executed', tarfile.REGTYPE)])
        with tempfile.TemporaryDirectory() as directory, patch.object(collector, 'DEST', Path(directory)):
            result = collector.notices(data, 'crate', Path(directory) / 'crate')
            self.assertEqual([entry['path'] for entry in result], ['crate/LICENCE', 'crate/vendor/AUTHORS.md'])
            self.assertFalse((Path(directory) / 'crate/build.rs').exists())
            self.assertFalse((Path(directory) / 'crate/NOTICE').exists())

    def test_rejects_traversal_before_writing(self):
        data = archive([('crate/../LICENSE', b'bad', tarfile.REGTYPE)])
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Unsafe archive path'):
                collector.notices(data, 'crate', Path(directory))

    def test_rejects_oversized_expansion(self):
        data = archive([('crate/source.rs', b'x' * 20, tarfile.REGTYPE)])
        with tempfile.TemporaryDirectory() as directory, patch.object(collector, 'MAX_TOTAL', 10):
            with self.assertRaisesRegex(ValueError, 'expansion limit'):
                collector.notices(data, 'crate', Path(directory))

    def test_rejects_binary_notice(self):
        data = archive([('crate/LICENSE', b'bad\0text', tarfile.REGTYPE)])
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Binary notice'):
                collector.notices(data, 'crate', Path(directory))


if __name__ == '__main__':
    unittest.main()
