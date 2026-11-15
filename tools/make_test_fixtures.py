#!/usr/bin/env python3
"""Builds binary fixtures for AppHubCoreTests. Run from the repository root."""
import io
import json
import pathlib
import plistlib
import struct
import zipfile
from datetime import datetime, timedelta, timezone

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "Core/Tests/AppHubCoreTests/Fixtures"
FIXTURES.mkdir(parents=True, exist_ok=True)

TEAM = "DBYTE12345"
BUNDLE = "com.dreambyte.testapp"


def macho(cryptid: int = 0) -> bytes:
    # 64-bit little-endian arm64 Mach-O with one LC_ENCRYPTION_INFO_64 command.
    header = struct.pack(
        "<IiiIIIII",
        0xFEEDFACF,
        0x0100000C,
        0,
        2,      # MH_EXECUTE
        1,      # ncmds
        24,     # sizeofcmds
        0,      # flags
        0,      # reserved
    )
    command = struct.pack("<IIIIII", 0x2C, 24, 0x4000, 0, cryptid, 0)
    return header + command + b"\x00" * 64


def icon_png() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGBA", (120, 120), (46, 125, 255, 255)).save(buffer, format="PNG")
    return buffer.getvalue()


def info_plist(binary: bool = False) -> bytes:
    payload = {
        "CFBundleIdentifier": BUNDLE,
        "CFBundleName": "TestApp",
        "CFBundleDisplayName": "Test App",
        "CFBundleExecutable": "TestApp",
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "42",
        "MinimumOSVersion": "18.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "CFBundleIcons": {
            "CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60"]}
        },
    }
    return plistlib.dumps(payload, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML)


def signing_certificate():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, "DreamByte Test Signing"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "DreamByte Studios"),
        ]
    )
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + timedelta(days=365))
        .sign(key, hashes.SHA256())
    )
    return cert.public_bytes(serialization.Encoding.DER)


def profile(certificate_der: bytes) -> bytes:
    payload = {
        "Name": "DreamByte Test Profile",
        "AppIDName": "DreamByte Test App",
        "TeamName": "DreamByte Studios",
        "TeamIdentifier": [TEAM],
        "CreationDate": datetime(2026, 1, 1, tzinfo=timezone.utc),
        "ExpirationDate": datetime(2027, 1, 1, tzinfo=timezone.utc),
        "ProvisionedDevices": ["00008110-001234567890001E"],
        "Entitlements": {
            "application-identifier": f"{TEAM}.{BUNDLE}",
            "get-task-allow": True,
            "com.apple.developer.team-identifier": TEAM,
        },
        "DeveloperCertificates": [certificate_der],
    }
    return b"-----BEGIN CMS-----\n" + plistlib.dumps(payload) + b"\n-----END CMS-----\n"


def write_ipa(path: pathlib.Path, *, cryptid=0, signed=True, binary_plist=False,
              stored=False, prefix="Payload/TestApp.app/"):
    compression = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
    with zipfile.ZipFile(path, "w", compression) as archive:
        archive.writestr(prefix + "Info.plist", info_plist(binary_plist))
        archive.writestr(prefix + "TestApp", macho(cryptid), compress_type=compression)
        archive.writestr(prefix + "AppIcon60x60@2x.png", icon_png())
        if signed:
            archive.writestr(prefix + "_CodeSignature/CodeResources", b"<plist/>")
            archive.writestr(prefix + "embedded.mobileprovision", PROFILE)


CERT = signing_certificate()
PROFILE = profile(CERT)
(FIXTURES / "cert.der").write_bytes(CERT)
(FIXTURES / "profile.mobileprovision").write_bytes(PROFILE)

write_ipa(FIXTURES / "valid.ipa")
write_ipa(FIXTURES / "encrypted.ipa", cryptid=1)
write_ipa(FIXTURES / "unsigned.ipa", signed=False)
write_ipa(FIXTURES / "binary_plist.ipa", binary_plist=True)
write_ipa(FIXTURES / "stored.ipa", stored=True)

with zipfile.ZipFile(FIXTURES / "traversal.ipa", "w") as archive:
    archive.writestr("Payload/TestApp.app/Info.plist", info_plist())
    archive.writestr("../evil.txt", b"escape attempt")

with zipfile.ZipFile(FIXTURES / "no_payload.ipa", "w") as archive:
    archive.writestr("README.txt", b"not an app")

# Stored ZIP whose payload no longer matches its CRC.
corrupt = FIXTURES / "corrupt_crc.ipa"
with zipfile.ZipFile(corrupt, "w", zipfile.ZIP_STORED) as archive:
    archive.writestr("Payload/TestApp.app/Info.plist", info_plist())
    archive.writestr("Payload/TestApp.app/broken.txt", b"HELLO-CONTENT")
raw = corrupt.read_bytes().replace(b"HELLO-CONTENT", b"HELLX-CONTENT")
corrupt.write_bytes(raw)

source = {
    "name": "DreamByte Test Source",
    "identifier": "com.dreambyte.testsource",
    "sourceURL": "https://example.com/apps.json",
    "apps": [
        {
            "name": "Test App",
            "bundleIdentifier": BUNDLE,
            "developerName": "DreamByte Studios",
            "subtitle": "Fixture application",
            "localizedDescription": "A fixture used by automated tests.",
            "iconURL": "https://example.com/icon.png",
            "tintColor": "2E7DFF",
            "versions": [
                {
                    "version": "1.2.3",
                    "date": "2026-01-01",
                    "localizedDescription": "Initial release.",
                    "downloadURL": "https://example.com/TestApp.ipa",
                    "size": 12345,
                    "minOSVersion": "18.0",
                }
            ],
            "beta": False,
        }
    ],
    "news": [],
}
(FIXTURES / "source_valid.json").write_text(json.dumps(source, indent=2), encoding="utf-8")

invalid = {
    "name": "Broken Source",
    "identifier": "com.dreambyte.broken",
    "apps": [
        {
            "name": "Broken App",
            "bundleIdentifier": "com.dreambyte.broken.app",
            "versions": [
                {
                    "version": "",
                    "downloadURL": "file:///etc/passwd",
                }
            ],
        }
    ],
}
(FIXTURES / "source_invalid.json").write_text(json.dumps(invalid, indent=2), encoding="utf-8")

legacy = {
    "name": "Legacy Source",
    "identifier": "com.dreambyte.legacy",
    "apps": [
        {
            "name": "Legacy App",
            "bundleIdentifier": "com.dreambyte.legacy.app",
            "version": "0.9",
            "versionDate": "2025-01-01",
            "versionDescription": "Legacy format.",
            "downloadURL": "https://example.com/legacy.ipa",
            "size": 99,
        }
    ],
}
(FIXTURES / "source_legacy.json").write_text(json.dumps(legacy, indent=2), encoding="utf-8")

print(f"fixtures written to {FIXTURES} ({len(list(FIXTURES.iterdir()))} files)")
