from django.db import transaction
from rest_framework import exceptions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.exceptions import APIError
from apps.core.permissions import IsLabOwnerOrReadOnly, LabAccess
from apps.core.viewsets import LabScopedNoDeleteViewSet

from .attributes import (
    CONTACT_REPLACEMENTS, FRAME_GENDERS, FRAME_TYPES, LENS_COATINGS, LENS_DESIGNS, LENS_INDEXES, SCHEMAS,
)
from .filters import LensVariantFilter, ProductFilter
from .models import Brand, Category, LensVariant, Product
from .serializers import (
    BrandSerializer, CategorySerializer, GenerateVariantsSerializer, LensVariantSerializer, ProductSerializer,
    lookup_code,
)


class CategoryViewSet(LabScopedNoDeleteViewSet):
    """`/api/v1/catalog/categories/` — tree via `parent`. Members read, owner edits."""

    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [IsLabOwnerOrReadOnly]
    filterset_fields = ["parent", "is_active"]
    search_fields = ["name"]
    ordering_fields = ["name", "id"]


class BrandViewSet(LabScopedNoDeleteViewSet):
    """`/api/v1/catalog/brands/`."""

    queryset = Brand.objects.all()
    serializer_class = BrandSerializer
    permission_classes = [IsLabOwnerOrReadOnly]
    filterset_fields = ["is_active"]
    search_fields = ["name"]
    ordering_fields = ["name", "id"]


class ProductViewSet(LabScopedNoDeleteViewSet):
    """
    `/api/v1/catalog/products/` — every kind. Filters: `kind` (comma list), `brand`,
    `category`, `is_active`, `track_stock`, `low_stock`, `in_stock`; `search` over
    name/sku/barcode/brand. Costs are hidden from staff without `can_view_costs`.
    """

    queryset = Product.objects.select_related("brand", "category")
    serializer_class = ProductSerializer
    permission_classes = [IsLabOwnerOrReadOnly]
    filterset_class = ProductFilter
    search_fields = ["name", "sku", "barcode", "brand__name", "notes"]
    # Never order by cost fields: that would leak them to staff.
    ordering_fields = ["name", "sale_price", "quantity", "created_at", "id"]

    @action(detail=True, methods=["get"], pagination_class=None)
    def grid(self, request, pk=None):
        """All variants of a lens product (unpaginated) for the SPH × CYL power grid."""
        product = self.get_object()
        if not product.uses_variants:
            raise APIError("This product has no power variants.", code="variant_not_allowed")
        rows = product.variants.select_related("product").order_by("add", "sph", "cyl")
        add = request.query_params.get("add")
        if add not in (None, ""):
            rows = rows.filter(add=add)
        data = LensVariantSerializer(rows, many=True, context=self.get_serializer_context()).data
        return Response({"product": self.get_serializer(product).data, "variants": data})

    @action(detail=True, methods=["post"], url_path="generate-variants")
    def generate_variants(self, request, pk=None):
        """Owner: create all powers of a range with zero stock. Existing powers are kept."""
        product = self.get_object()
        if not product.uses_variants:
            raise APIError("This product has no power variants.", code="variant_not_allowed")
        serializer = GenerateVariantsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        add = serializer.validated_data["add"]
        with transaction.atomic():
            existing = set(product.variants.filter(add=add).values_list("sph", "cyl"))
            new = [
                LensVariant(lab=request.lab, product=product, sph=sph, cyl=cyl, add=add)
                for sph, cyl in serializer.validated_data["powers"]
                if (sph, cyl) not in existing
            ]
            LensVariant.objects.bulk_create(new)
        return Response({"created": len(new), "skipped": len(serializer.validated_data["powers"]) - len(new)},
                        status=status.HTTP_201_CREATED)


class LensVariantViewSet(LabScopedNoDeleteViewSet):
    """`/api/v1/catalog/variants/?product=` — lens powers (stock per variant)."""

    queryset = LensVariant.objects.select_related("product")
    serializer_class = LensVariantSerializer
    permission_classes = [IsLabOwnerOrReadOnly]
    filterset_class = LensVariantFilter
    search_fields = ["product__name", "sku", "barcode"]
    ordering_fields = ["sph", "cyl", "add", "quantity", "id"]


class LookupView(APIView):
    """`GET /api/v1/catalog/lookup/?code=` — product (+ variant) by barcode or SKU."""

    permission_classes = [LabAccess]

    def get(self, request):
        product, variant = lookup_code(request.lab, request.query_params.get("code"))
        if product is None:
            raise exceptions.NotFound("No item with this code.", code="not_found")
        context = {"request": request}
        return Response({
            "product": ProductSerializer(product, context=context).data,
            "variant": LensVariantSerializer(variant, context=context).data if variant else None,
        })


class CatalogOptionsView(APIView):
    """`GET /api/v1/catalog/options/` — allowed kinds and attribute choices for the forms."""

    permission_classes = [LabAccess]

    def get(self, request):
        return Response({
            "kinds": [k for k, _ in Product.Kind.choices],
            "variant_kinds": list(Product.VARIANT_KINDS),
            "non_stock_kinds": list(Product.NON_STOCK_KINDS),
            "attributes": {kind: sorted(schema) for kind, schema in SCHEMAS.items()},
            "choices": {
                "lens_index": LENS_INDEXES,
                "lens_design": LENS_DESIGNS,
                "lens_coatings": LENS_COATINGS,
                "frame_gender": FRAME_GENDERS,
                "frame_type": FRAME_TYPES,
                "contact_replacement": CONTACT_REPLACEMENTS,
            },
        })
