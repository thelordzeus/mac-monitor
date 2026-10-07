"""Release acceptance checks; build/package/generate the feed before running."""
import importlib.util
import pathlib
import struct
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verify_appcast", ROOT / "scripts/verify-appcast.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class AppcastSignatureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mac-pulse-update-test-")
        self.addCleanup(self.directory.cleanup)
        self.folder = pathlib.Path(self.directory.name)
        self.feed = ROOT / "appcast.xml"
        self.archive = ROOT / "dist/Mac-Pulse-arm64.zip"
        self.assertTrue(self.feed.exists(), "Run scripts/make-appcast.sh first")
        self.assertTrue(self.archive.exists(), "Build and package the app first")

    def test_authentic_release_verifies_without_a_private_key(self):
        verifier.verify(self.feed, self.archive)

    def test_same_length_modified_feed_is_rejected(self):
        changed = self.folder / "appcast.xml"
        data = self.feed.read_bytes().replace(b"<title>Mac Pulse</title>", b"<title>Mac Pxlse</title>", 1)
        self.assertNotEqual(data, self.feed.read_bytes())
        self.assertEqual(len(data), self.feed.stat().st_size)
        changed.write_bytes(data)
        with self.assertRaises(subprocess.CalledProcessError):
            verifier.verify(changed, self.archive)

    def test_same_length_modified_executable_is_rejected(self):
        changed = self.folder / self.archive.name
        data = bytearray(self.archive.read_bytes())
        with zipfile.ZipFile(self.archive) as archive:
            binary = archive.getinfo("Mac Pulse.app/Contents/MacOS/MacMonitor")
        header = binary.header_offset
        name_length, extra_length = struct.unpack_from("<HH", data, header + 26)
        payload = header + 30 + name_length + extra_length
        data[payload + binary.compress_size // 2] ^= 1
        changed.write_bytes(data)
        self.assertEqual(len(data), self.archive.stat().st_size)
        with self.assertRaises(subprocess.CalledProcessError):
            verifier.verify(self.feed, changed)

    def test_unsigned_feed_is_rejected(self):
        changed = self.folder / "appcast.xml"
        changed.write_bytes(self.feed.read_bytes().split(b"<!-- sparkle-signatures:")[0])
        with self.assertRaisesRegex(ValueError, "no embedded signature"):
            verifier.verify(changed, self.archive)


if __name__ == "__main__":
    unittest.main()
