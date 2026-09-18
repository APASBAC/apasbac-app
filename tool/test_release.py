import unittest
from unittest.mock import patch
import release


class ReleaseTests(unittest.TestCase):
    def test_monotonic_version(self):
        previous = {"versionCode": 11, "versionName": "1.3.0", "minimumSupportedVersionCode": 8}
        release.validate_progression("1.4.0", 12, {"minimumSupportedVersionCode": 8}, previous)
        for code in (10, 11):
            with self.assertRaises(ValueError):
                release.validate_progression("1.4.0", code, {"minimumSupportedVersionCode": 8}, previous)

    def test_cannot_lower_minimum(self):
        with self.assertRaises(ValueError):
            release.validate_progression("1.4.0", 12, {"minimumSupportedVersionCode": 7},
                {"versionCode": 11, "versionName": "1.3.0", "minimumSupportedVersionCode": 8})

    def test_missing_asset_prevents_manifest_publication(self):
        with patch('release.urllib.request.urlopen', side_effect=OSError('404')), patch('release.time.sleep'):
            with self.assertRaises(OSError):
                release.verify_asset({"apkUrl": "https://github.com/APASBAC/apasbac-app/releases/download/v1/a.apk",
                    "sizeBytes": 100, "sha256": "0" * 64})


if __name__ == '__main__':
    unittest.main()
