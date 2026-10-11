import django_filters
from django.db.models import F

from .models import LensVariant, Product


class ProductFilter(django_filters.FilterSet):
    kind = django_filters.BaseInFilter(field_name="kind")
    low_stock = django_filters.BooleanFilter(method="filter_low_stock")
    in_stock = django_filters.BooleanFilter(method="filter_in_stock")

    class Meta:
        model = Product
        fields = ["kind", "brand", "category", "is_active", "track_stock"]

    def filter_low_stock(self, queryset, name, value):
        low = queryset.filter(track_stock=True, reorder_level__gt=0, quantity__lte=F("reorder_level"))
        return low if value else queryset.exclude(pk__in=low.values("pk"))

    def filter_in_stock(self, queryset, name, value):
        return queryset.filter(quantity__gt=0) if value else queryset.filter(quantity__lte=0)


class LensVariantFilter(django_filters.FilterSet):
    in_stock = django_filters.BooleanFilter(method="filter_in_stock")

    class Meta:
        model = LensVariant
        fields = ["product", "sph", "cyl", "add", "is_active"]

    def filter_in_stock(self, queryset, name, value):
        return queryset.filter(quantity__gt=0) if value else queryset.filter(quantity__lte=0)
