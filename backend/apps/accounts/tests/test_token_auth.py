from django.contrib.auth import get_user_model
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.serializers import UserSerializer


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


class TokenAuthTests(APITestCase):
    def test_token_authenticates_request(self):
        from rest_framework.permissions import IsAuthenticated
        from rest_framework.response import Response
        from rest_framework.test import APIRequestFactory
        from rest_framework.views import APIView

        class WhoAmI(APIView):
            permission_classes = [IsAuthenticated]

            def get(self, request):
                return Response({"username": request.user.username})

        user = get_user_model().objects.create_user(username="owner1", password="x-Pass-123")
        token = Token.objects.create(user=user)
        factory = APIRequestFactory()

        ok = WhoAmI.as_view()(factory.get("/x/", HTTP_AUTHORIZATION=f"Token {token.key}"))
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.data["username"], "owner1")

        bad = WhoAmI.as_view()(factory.get("/x/", HTTP_AUTHORIZATION="Token wrong"))
        self.assertEqual(bad.status_code, 401)
        self.assertEqual(bad.data["code"], "authentication_failed")
