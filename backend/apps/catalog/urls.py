from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import BrandViewSet, CatalogOptionsView, CategoryViewSet, LensVariantViewSet, LookupView, ProductViewSet

router = SimpleRouter()
router.register("categories", CategoryViewSet, basename="category")
router.register("brands", BrandViewSet, basename="brand")
router.register("products", ProductViewSet, basename="product")
router.register("variants", LensVariantViewSet, basename="lens-variant")

urlpatterns = [
    path("lookup/", LookupView.as_view(), name="catalog-lookup"),
    path("options/", CatalogOptionsView.as_view(), name="catalog-options"),
    *router.urls,
]
