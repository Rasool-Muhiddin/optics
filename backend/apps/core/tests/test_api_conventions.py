from django.test import SimpleTestCase
from rest_framework import serializers
from rest_framework.exceptions import NotAuthenticated
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory
from rest_framework.views import APIView

from apps.core.exceptions import APIError
from apps.core.pagination import StandardPagination


class _QtySerializer(serializers.Serializer):
    qty = serializers.IntegerField(min_value=1)


class _ProtectedView(APIView):
    def get(self, request):
        return Response({"ok": True})


class _BusinessErrorView(APIView):
    authentication_classes = []
    permission_classes = []

    def get(self, request):
        raise APIError("Stock too low.", code="insufficient_stock")


class _ValidationView(APIView):
    authentication_classes = []
    permission_classes = []

    def post(self, request):
        serializer = _QtySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.data)


class ErrorFormatTests(SimpleTestCase):
    factory = APIRequestFactory()

    def test_default_permission_requires_authentication(self):
        response = _ProtectedView.as_view()(self.factory.get("/x/"))
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.data["code"], NotAuthenticated.default_code)
        self.assertIn("detail", response.data)

    def test_business_error_has_detail_and_code(self):
        response = _BusinessErrorView.as_view()(self.factory.get("/x/"))
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data, {"detail": "Stock too low.", "code": "insufficient_stock"})

    def test_validation_error_keeps_field_errors(self):
        response = _ValidationView.as_view()(self.factory.post("/x/", {"qty": 0}, format="json"))
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "validation_error")
        self.assertIn("qty", response.data["errors"])


class PaginationTests(SimpleTestCase):
    def test_page_size_is_capped(self):
        paginator = StandardPagination()
        request = APIRequestFactory().get("/x/", {"page_size": 100000})
        from rest_framework.request import Request

        self.assertEqual(paginator.get_page_size(Request(request)), StandardPagination.max_page_size)
