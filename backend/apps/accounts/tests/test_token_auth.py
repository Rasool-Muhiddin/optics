from django.contrib.auth import get_user_model
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory, APITestCase
from rest_framework.views import APIView

from apps.accounts.models import AuthToken, hash_secret
from apps.accounts.serializers import UserSerializer
from apps.core.testing import make_device, make_lab


class UserModelTests(APITestCase):
    def test_custom_user_model_is_active(self):
        User = get_user_model()
        self.assertEqual(User._meta.label, "accounts.User")

    def test_create_user_hashes_password(self):
        user = get_user_model().objects.create_user(username="staff1", password="s3cret-pass!")
        self.assertNotEqual(user.password, "s3cret-pass!")
        self.assertTrue(user.check_password("s3cret-pass!"))

    def test_serializer_never_exposes_password(self):
        user = get_user_model().objects.create_user(username="staff1", password="s3cret-pass!")
        self.assertNotIn("password", UserSerializer(user).data)


class _WhoAmI(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({"username": request.user.username})


class DeviceTokenAuthTests(APITestCase):
    factory = APIRequestFactory()

    def _get(self, key):
        return _WhoAmI.as_view()(self.factory.get("/x/", HTTP_AUTHORIZATION=f"Token {key}"))

    def setUp(self):
        self.user = get_user_model().objects.create_user(username="owner1", password="x-Pass-123")

    def test_token_authenticates_request(self):
        _, key = AuthToken.issue(self.user)
        ok = self._get(key)
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.data["username"], "owner1")

    def test_wrong_token_is_rejected(self):
        bad = self._get("wrong")
        self.assertEqual(bad.status_code, 401)
        self.assertEqual(bad.data["code"], "authentication_failed")

    def test_only_digest_is_stored(self):
        token, key = AuthToken.issue(self.user)
        self.assertNotEqual(token.digest, key)
        self.assertEqual(token.digest, hash_secret(key))

    def test_inactive_user_is_rejected(self):
        _, key = AuthToken.issue(self.user)
        self.user.is_active = False
        self.user.save()
        self.assertEqual(self._get(key).status_code, 401)

    def test_deactivated_device_revokes_its_tokens(self):
        device, _ = make_device(make_lab())
        _, key = AuthToken.issue(self.user, device)
        device.is_active = False
        device.save()
        response = self._get(key)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.data["code"], "device_deactivated")
