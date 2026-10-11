from django.contrib import admin

from .models import Brand, Category, LensVariant, Product


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ["name", "parent", "lab", "is_active"]
    list_filter = ["is_active", "lab"]
    search_fields = ["name"]
    list_select_related = ["parent", "lab"]


@admin.register(Brand)
class BrandAdmin(admin.ModelAdmin):
    list_display = ["name", "lab", "is_active"]
    list_filter = ["is_active", "lab"]
    search_fields = ["name"]


class LensVariantInline(admin.TabularInline):
    model = LensVariant
    extra = 0
    fields = ["sph", "cyl", "add", "sku", "barcode", "sale_price", "quantity", "average_cost", "is_active"]
    readonly_fields = ["quantity", "average_cost"]
    show_change_link = True


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ["name", "kind", "brand", "lab", "sale_price", "quantity", "average_cost", "is_active"]
    list_filter = ["kind", "is_active", "track_stock", "lab"]
    search_fields = ["name", "sku", "barcode"]
    readonly_fields = ["quantity", "average_cost", "created_by", "created_at", "updated_at"]
    list_select_related = ["brand", "lab"]
    inlines = [LensVariantInline]


@admin.register(LensVariant)
class LensVariantAdmin(admin.ModelAdmin):
    list_display = ["product", "sph", "cyl", "add", "quantity", "average_cost", "lab", "is_active"]
    list_filter = ["is_active", "lab"]
    search_fields = ["product__name", "sku", "barcode"]
    readonly_fields = ["quantity", "average_cost"]
    list_select_related = ["product", "lab"]
