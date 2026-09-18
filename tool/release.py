"""Validate a signed APK and publish its metadata only after its asset is accessible.

No third-party Python dependencies. The workflow owns authentication; this script
never receives GitHub credentials or keystore passwords.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.request
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "APASBAC/apasbac-app"
PACKAGE = "com.example.apasbac_app"


def version():
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$", text, re.M)
    if not match:
        raise ValueError("Use version: major.minor.patch+integer in pubspec.yaml")
    name, code = match.group(1), int(match.group(2))
    if code > 2100000000:
        raise ValueError("versionCode exceeds Android limit")
    return name, code


def settings():
    policy = json.loads((ROOT / "update/release-notes.json").read_text(encoding="utf-8"))
    minimum = policy["minimumSupportedVersionCode"]
    notes = policy["releaseNotes"]
    if type(minimum) is not int or minimum < 1 or type(policy["mandatory"]) is not bool:
        raise ValueError("Invalid release policy")
    if not isinstance(notes, list) or len(notes) > 50 or any(not isinstance(n, str) or len(n) > 1000 for n in notes):
        raise ValueError("Invalid release notes")
    # Release policy cannot override the version/package/signature metadata.
    return {"minimumSupportedVersionCode": minimum, "mandatory": policy["mandatory"], "releaseNotes": notes}


def validate_progression(name, code, policy, previous):
    if policy["minimumSupportedVersionCode"] > code:
        raise ValueError("Minimum cannot exceed released version")
    if previous and (code <= previous["versionCode"] or name == previous["versionName"]):
        raise ValueError("Use a new versionName/tag and a strictly larger versionCode")
    if previous and policy["minimumSupportedVersionCode"] < previous["minimumSupportedVersionCode"]:
        raise ValueError("The supported minimum cannot decrease (offline caches retain it)")


def prepare(apk, aapt, apksigner):
    name, code = version()
    policy = settings()
    previous_path = ROOT / "update/version.json"
    previous = json.loads(previous_path.read_text(encoding="utf-8")) if previous_path.exists() else None
    validate_progression(name, code, policy, previous)
    last_release = ROOT / 'build/previous-release/version.json'
    if last_release.exists():
        validate_progression(name, code, policy, json.loads(last_release.read_text(encoding='utf-8')))
    badging = subprocess.check_output([aapt, "dump", "badging", str(apk)], text=True)
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    if not package or package.groups() != (PACKAGE, str(code), name):
        raise ValueError("APK package/version differs from pubspec.yaml")
    certs = subprocess.check_output([apksigner, "verify", "--verbose", "--print-certs", str(apk)], text=True)
    certificate = re.search(r"Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]+)", certs)
    expected = os.environ.get("EXPECTED_CERT_SHA256", "").replace(":", "").lower()
    if not certificate or not re.fullmatch(r"[0-9a-f]{64}", expected) or certificate.group(1).lower() != expected:
        raise ValueError("Production signing certificate does not match ANDROID_SIGNING_CERT_SHA256")
    if "CN=Android Debug" in certs or "CN=Android Debug" in badging:
        raise ValueError("Debug signing is forbidden for production")
    if "application-debuggable" in badging:
        raise ValueError("Debuggable APK cannot be published")
    if previous and previous.get("certificateSha256", expected) != expected:
        raise ValueError("Do not change the production signing certificate")
    with apk.open('rb') as apk_file:
        digest = hashlib.file_digest(apk_file, 'sha256').hexdigest()
    manifest = {"schemaVersion": 1, "channel": "stable", "versionCode": code,
        "versionName": name, **policy,
        "apkUrl": f"https://github.com/{REPOSITORY}/releases/download/v{name}/app-release.apk",
        "sha256": digest,
        "sizeBytes": apk.stat().st_size,
        "publishedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "certificateSha256": expected}
    destination = ROOT / "build/release"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "version.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (destination / "notes.md").write_text("\n".join(f"- {note}" for note in policy["releaseNotes"]) + "\n", encoding="utf-8")
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as file:
            file.write(f"tag=v{name}\ncode={code}\n")


def verify_asset(manifest):
    url = manifest["apkUrl"]
    if not url.startswith(f"https://github.com/{REPOSITORY}/releases/download/"):
        raise ValueError("Unexpected release repository")
    for attempt in range(5):
        try:
            digest = hashlib.sha256()
            size = 0
            # Anonymous GET proves the APK can be downloaded by every client.
            with urllib.request.urlopen(url, timeout=30) as response:
                while chunk := response.read(65536):
                    size += len(chunk)
                    if size > manifest["sizeBytes"]:
                        raise ValueError("Asset size mismatch")
                    digest.update(chunk)
            if size != manifest["sizeBytes"] or digest.hexdigest() != manifest["sha256"]:
                raise ValueError("Published asset does not match the signed build")
            return
        except Exception:
            if attempt == 4:
                raise
            time.sleep(5)


def publish_manifest():
    source = ROOT / "build/release/version.json"
    manifest = json.loads(source.read_text(encoding="utf-8"))
    verify_asset(manifest)
    target = ROOT / "update/version.json"
    # Run after fetching source again: never overwrite a newer published release.
    if target.exists():
        previous = json.loads(target.read_text(encoding="utf-8"))
        if previous["versionCode"] >= manifest["versionCode"]:
            raise ValueError("A release of the same or a newer version is already published")
    target.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["prepare", "publish-manifest"])
    parser.add_argument("--apk", type=Path, default=ROOT / "build/app/outputs/flutter-apk/app-release.apk")
    parser.add_argument("--aapt", default="aapt")
    parser.add_argument("--apksigner", default="apksigner")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.apk, args.aapt, args.apksigner)
    else:
        publish_manifest()
