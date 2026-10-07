#!/usr/bin/env python3
"""Validate feed metadata and Ed25519 signatures against the embedded public key.

Uses CryptoKit through the bundled Swift toolchain, without reading a private key.
"""
import base64
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def verify(feed_path, archive_path):
    feed_path, archive_path = pathlib.Path(feed_path), pathlib.Path(archive_path)
    feed = feed_path.read_bytes()
    with zipfile.ZipFile(archive_path) as archive:
        app_info = [name for name in archive.namelist()
                    if name.endswith(".app/Contents/Info.plist") and name.count("/") == 2]
        if len(app_info) != 1:
            raise ValueError("Expected exactly one app in the update archive")
        info = plistlib.loads(archive.read(app_info[0]))
    public = info["SUPublicEDKey"]
    expected = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    for key in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString",
                "SUPublicEDKey", "SUFeedURL", "LSMinimumSystemVersion"):
        if info.get(key) != expected.get(key):
            raise ValueError(f"Packaged {key} differs from the release source")
    if len(base64.b64decode(public, validate=True)) != 32:
        raise ValueError("Invalid embedded update public key")
    if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        raise ValueError("Update bundle must require signed feeds and archives")
    # Sparkle appends a signature comment after the signed XML content.
    prefix = b"<!-- sparkle-signatures:\n"
    start = feed.rfind(prefix)
    if start < 0:
        raise ValueError("Appcast has no embedded signature")
    end = feed.index(b"-->", start) + 3
    header = feed[start:end].decode("ascii")
    signature = re.search(r"edSignature:\s*([^\s]+)", header)
    length = re.search(r"length:\s*(\d+)", header)
    if not signature or not length:
        raise ValueError("Malformed feed signature header")
    signed_feed = feed[:start]
    if len(signed_feed) != int(length.group(1)):
        raise ValueError("Signed appcast length mismatch")
    root = ET.fromstring(feed)
    items = root.findall("./channel/item")
    current = [item for item in items if item.findtext(SPARKLE + "version") == info["CFBundleVersion"]]
    if len(current) != 1:
        raise ValueError("Expected exactly one feed entry for the packaged build")
    item = current[0]
    if item.findtext(SPARKLE + "shortVersionString") != info["CFBundleShortVersionString"]:
        raise ValueError("Feed version differs from the packaged app")
    if item.findtext(SPARKLE + "minimumSystemVersion") != info["LSMinimumSystemVersion"]:
        raise ValueError("Feed minimum macOS differs from the packaged app")
    enclosure = item.find("enclosure")
    expected_url = ("https://github.com/thelordzeus/mac-monitor/releases/download/v"
                    + info["CFBundleShortVersionString"] + "/" + archive_path.name)
    if enclosure is None or enclosure.get("url") != expected_url:
        raise ValueError("Feed download URL differs from the release asset")
    if int(enclosure.get("length", "-1")) != archive_path.stat().st_size:
        raise ValueError("Feed archive length mismatch")
    archive_signature = enclosure.get(SPARKLE + "edSignature")
    if not archive_signature:
        raise ValueError("Update archive has no Ed25519 signature")
    with tempfile.TemporaryDirectory(prefix="mac-pulse-verify-") as directory:
        directory = pathlib.Path(directory)
        content = directory / "feed-content"
        content.write_bytes(signed_feed)
        swift = directory / "verify.swift"
        swift.write_text('''import CryptoKit
import Foundation
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: CommandLine.arguments[1])!)
for i in stride(from: 2, to: CommandLine.arguments.count, by: 2) {
  let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i]))
  guard let signature = Data(base64Encoded: CommandLine.arguments[i + 1]), key.isValidSignature(signature, for: data) else {
    fputs("Ed25519 signature verification failed\\n", stderr)
    exit(1)
  }
}
print("Verified appcast and update archive with the app's public key.")
''')
        environment = os.environ.copy()
        if pathlib.Path("/Applications/Xcode.app/Contents/Developer").is_dir():
            environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
        subprocess.run(["xcrun", "swift", "-module-cache-path", str(ROOT / ".build/module-cache"),
                        str(swift), public, str(content), signature.group(1),
                        str(archive_path), archive_signature], check=True, env=environment)
    print(f"Verified Mac Pulse {info['CFBundleShortVersionString']} (build {info['CFBundleVersion']}) release metadata.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: verify-appcast.py appcast.xml Mac-Pulse-arm64.zip")
    verify(sys.argv[1], sys.argv[2])
