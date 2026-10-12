import datetime
import hashlib
import shutil
import tempfile

from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone

from apps.app_updates.models import DesktopAppVersion, version_key
from apps.core.testing import LabAPITestCase

URL = "/api/v1/desktop/latest-version/"
SHA = "a" * 64


def release(version, build=1, **fields):
    defaults = {"installer_url": f"https://downloads.example.com/optics-{version}.exe", "sha256": SHA}
    return DesktopAppVersion.objects.create(version=version, build_number=build, **{**defaults, **fields})


class LatestVersionTests(LabAPITestCase):
    def test_no_release(self):
        self.assertEqual(self.client.get(URL).json(), {"available": False, "update_available": False})

    def test_newest_active_release_is_offered_without_login(self):
        release("1.2.0")
        release("1.10.0")  # numeric, not text, comparison
        release("2.0.0", is_active=False)
        release("3.0.0", published_at=timezone.now() + datetime.timedelta(days=1))  # not yet published
        body = self.client.get(URL, {"version": "1.2.0"}).json()
        self.assertEqual((body["version"], body["update_available"], body["mandatory"]), ("1.10.0", True, False))
        self.assertEqual(body["url"], "https://downloads.example.com/optics-1.10.0.exe")
        self.assertEqual(body["sha256"], SHA)
        self.assertFalse(self.client.get(URL, {"version": "1.10.0"}).json()["update_available"])

    def test_mandatory_by_flag_or_minimum_version(self):
        release("1.5.0", min_supported_version="1.3.0")
        self.assertTrue(self.client.get(URL, {"version": "1.2.9"}).json()["mandatory"])
        self.assertFalse(self.client.get(URL, {"version": "1.4.0"}).json()["mandatory"])
        release("1.6.0", is_mandatory=True)
        self.assertTrue(self.client.get(URL, {"version": "1.4.0"}).json()["mandatory"])

    def test_validation(self):
        bad = DesktopAppVersion(version="1.x", installer_url="https://x/y.exe", sha256=SHA)
        with self.assertRaises(ValidationError):
            bad.full_clean()
        no_hash = DesktopAppVersion(version="1.0", installer_url="https://x/y.exe")
        with self.assertRaises(ValidationError):
            no_hash.full_clean()
        self.assertEqual(version_key("1.2"), (1, 2, 0, 0))

    def test_uploaded_installer_gets_sha256_and_absolute_url(self):
        media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, media, ignore_errors=True)
        content = b"MZ fake installer"
        with override_settings(MEDIA_ROOT=media):
            row = DesktopAppVersion.objects.create(
                version="1.0.1", installer=SimpleUploadedFile("optics-setup.exe", content)
            )
            self.assertEqual(row.sha256, hashlib.sha256(content).hexdigest())
            self.assertEqual(row.size, len(content))
            body = self.client.get(URL, {"version": "1.0.0"}).json()
            self.assertTrue(body["url"].startswith("http://testserver/media/installers/"))
