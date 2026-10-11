from decimal import Decimal

from apps.catalog.models import Brand, Category, LensVariant, Product
from apps.core.testing import LabAPITestCase, make_lab, make_member, make_product, make_variant, stock_in
from apps.labs.models import LabUser

CATEGORIES = "/api/v1/catalog/categories/"
BRANDS = "/api/v1/catalog/brands/"
PRODUCTS = "/api/v1/catalog/products/"
VARIANTS = "/api/v1/catalog/variants/"


class CatalogBase(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab()
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.login_as(self.owner)


class CategoryBrandTests(CatalogBase):
    def test_category_tree(self):
        lenses = self.client.post(CATEGORIES, {"name": "عدسات"}).json()
        child = self.client.post(CATEGORIES, {"name": "طبية", "parent": lenses["id"]})
        self.assertEqual(child.status_code, 201, child.content)
        self.assertEqual(Category.objects.get(pk=child.json()["id"]).parent_id, lenses["id"])

    def test_category_cycle_rejected(self):
        a = Category.objects.create(lab=self.lab, name="A")
        b = Category.objects.create(lab=self.lab, name="B", parent=a)
        response = self.client.patch(f"{CATEGORIES}{a.id}/", {"parent": b.id})
        self.assertEqual(response.json()["code"], "category_cycle")

    def test_duplicate_names(self):
        self.client.post(BRANDS, {"name": "Ray-Ban"})
        self.assertEqual(self.client.post(BRANDS, {"name": "ray-ban"}).json()["code"], "duplicate_name")
        self.client.post(CATEGORIES, {"name": "Frames"})
        self.assertEqual(self.client.post(CATEGORIES, {"name": "frames"}).json()["code"], "duplicate_name")

    def test_staff_reads_but_cannot_write(self):
        Brand.objects.create(lab=self.lab, name="Essilor")
        self.login_as(self.staff)
        self.assertEqual(self.client.get(BRANDS).json()["count"], 1)
        response = self.client.post(BRANDS, {"name": "Zeiss"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "owner_required")

    def test_no_delete(self):
        brand = Brand.objects.create(lab=self.lab, name="Hoya")
        self.assertEqual(self.client.delete(f"{BRANDS}{brand.id}/").status_code, 405)

    def test_unauthenticated(self):
        self.client.credentials()
        self.assertEqual(self.client.get(PRODUCTS).status_code, 401)


class ProductTests(CatalogBase):
    def _frame(self, **extra):
        payload = {
            "kind": "frame", "name": "Ray-Ban 5154", "sale_price": "85000", "purchase_price": "50000",
            "attributes": {"model": "RB5154", "color": "Black", "size": "52-18-140", "gender": "unisex"},
            **extra,
        }
        return self.client.post(PRODUCTS, payload)

    def test_create_frame_with_attributes(self):
        response = self._frame(sku="RB-1")
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["attributes"]["size"], "52-18-140")
        self.assertEqual(body["quantity"], 0)
        self.assertEqual(body["purchase_price"], "50000.00")
        self.assertTrue(body["track_stock"])

    def test_invalid_attributes(self):
        response = self._frame(attributes={"size": "52/18"})
        self.assertEqual(response.status_code, 400)
        self.assertIn("size", response.json()["errors"]["attributes"])
        response = self._frame(attributes={"unknown": "x"})
        self.assertIn("unknown", response.json()["errors"]["attributes"])

    def test_lens_attributes(self):
        response = self.client.post(PRODUCTS, {
            "kind": "stock_lens", "name": "CR-39 1.56 HMC", "sale_price": "15000",
            "attributes": {"index": "1.56", "design": "single_vision", "coatings": ["blue_cut", "ar", "ar"]},
        })
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["attributes"]["coatings"], ["ar", "blue_cut"])
        self.assertTrue(response.json()["uses_variants"])
        bad = self.client.post(PRODUCTS, {"kind": "stock_lens", "name": "x", "sale_price": "1", "attributes": {"index": "1.55"}})
        self.assertIn("index", bad.json()["errors"]["attributes"])

    def test_rx_lens_and_service_never_track_stock(self):
        for kind in ("rx_lens", "service"):
            response = self.client.post(PRODUCTS, {"kind": kind, "name": kind, "sale_price": "1", "track_stock": True})
            self.assertFalse(response.json()["track_stock"])

    def test_sku_and_barcode_unique_per_lab(self):
        self._frame(sku="A1", barcode="123")
        self.assertIn("sku", self._frame(sku="A1").json()["errors"])
        self.assertIn("barcode", self._frame(barcode="123").json()["errors"])
        # Another lab may reuse them.
        make_product(make_lab(), sku="A2")
        self.assertEqual(self._frame(sku="A2").status_code, 201)

    def test_negative_price_rejected(self):
        self.assertEqual(self._frame(sale_price="-1").status_code, 400)

    def test_client_cannot_set_stock_or_cost(self):
        response = self._frame(quantity=50, average_cost="1")
        product = Product.objects.get(pk=response.json()["id"])
        self.assertEqual(product.quantity, 0)
        self.assertEqual(product.average_cost, Decimal("0"))

    def test_kind_locked_after_stock(self):
        product = make_product(self.lab)
        stock_in(product, 2)
        response = self.client.patch(f"{PRODUCTS}{product.id}/", {"kind": "accessory"})
        self.assertEqual(response.json()["code"], "kind_locked")

    def test_filters_and_search(self):
        brand = Brand.objects.create(lab=self.lab, name="Hoya")
        make_product(self.lab, "frame", name="Black frame")
        low = make_product(self.lab, "accessory", name="Case", reorder_level=5)
        stock_in(low, 2)
        make_product(self.lab, "stock_lens", name="Hoya 1.60", brand=brand)
        self.assertEqual(self.client.get(PRODUCTS, {"kind": "frame,accessory"}).json()["count"], 2)
        self.assertEqual(self.client.get(PRODUCTS, {"search": "hoya"}).json()["count"], 1)
        rows = self.client.get(PRODUCTS, {"low_stock": "true"}).json()["results"]
        self.assertEqual([r["name"] for r in rows], ["Case"])
        self.assertTrue(rows[0]["is_low_stock"])

    def test_lookup_by_barcode(self):
        product = make_product(self.lab, "stock_lens")
        variant = make_variant(product, barcode="999")
        frame = make_product(self.lab, barcode="111")
        body = self.client.get("/api/v1/catalog/lookup/", {"code": "999"}).json()
        self.assertEqual((body["product"]["id"], body["variant"]["id"]), (product.id, variant.id))
        self.assertEqual(self.client.get("/api/v1/catalog/lookup/", {"code": "111"}).json()["product"]["id"], frame.id)
        self.assertEqual(self.client.get("/api/v1/catalog/lookup/", {"code": "000"}).status_code, 400)

    def test_options(self):
        body = self.client.get("/api/v1/catalog/options/").json()
        self.assertIn("frame", body["kinds"])
        self.assertIn("1.67", body["choices"]["lens_index"])


class VariantTests(CatalogBase):
    def setUp(self):
        super().setUp()
        self.lens = make_product(self.lab, "stock_lens", name="1.56 HMC")

    def test_create_and_validate_powers(self):
        ok = self.client.post(VARIANTS, {"product": self.lens.id, "sph": "-2.25", "cyl": "-0.50"})
        self.assertEqual(ok.status_code, 201, ok.content)
        for bad in ({"sph": "-2.10"}, {"sph": "31"}, {"sph": "0", "cyl": "+0.50"}, {"sph": "0", "add": "0.25"}):
            response = self.client.post(VARIANTS, {"product": self.lens.id, **bad})
            self.assertEqual(response.status_code, 400, bad)

    def test_duplicate_variant(self):
        make_variant(self.lens, sph="-1.00")
        response = self.client.post(VARIANTS, {"product": self.lens.id, "sph": "-1.00", "cyl": "0"})
        self.assertEqual(response.json()["code"], "duplicate_variant")

    def test_variants_only_for_variant_kinds(self):
        frame = make_product(self.lab, "frame")
        response = self.client.post(VARIANTS, {"product": frame.id, "sph": "0"})
        self.assertIn("product", response.json()["errors"])

    def test_generate_grid_and_read_it(self):
        url = f"{PRODUCTS}{self.lens.id}/generate-variants/"
        response = self.client.post(url, {"sph_from": "-2", "sph_to": "0", "cyl_from": "-1", "cyl_to": "0"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json(), {"created": 9 * 5, "skipped": 0})
        again = self.client.post(url, {"sph_from": "-2", "sph_to": "-1", "cyl_from": "0", "cyl_to": "0"})
        self.assertEqual(again.json(), {"created": 0, "skipped": 5})
        grid = self.client.get(f"{PRODUCTS}{self.lens.id}/grid/").json()
        self.assertEqual(len(grid["variants"]), 45)
        self.assertEqual(grid["product"]["id"], self.lens.id)

    def test_generate_limits(self):
        url = f"{PRODUCTS}{self.lens.id}/generate-variants/"
        response = self.client.post(url, {"sph_from": "-30", "sph_to": "30", "cyl_from": "-10", "cyl_to": "0"})
        self.assertEqual(response.json()["code"], "too_many_variants")
        response = self.client.post(url, {"sph_from": "-1", "sph_to": "0", "cyl_from": "0", "cyl_to": "1"})
        self.assertEqual(response.json()["code"], "invalid_cyl")

    def test_power_locked_after_stock(self):
        variant = make_variant(self.lens)
        stock_in(variant, 3)
        response = self.client.patch(f"{VARIANTS}{variant.id}/", {"sph": "-1.25"})
        self.assertEqual(response.json()["code"], "variant_locked")
        # Price can still change.
        self.assertEqual(self.client.patch(f"{VARIANTS}{variant.id}/", {"sale_price": "20000"}).status_code, 200)

    def test_staff_cannot_generate(self):
        self.login_as(self.staff)
        response = self.client.post(f"{PRODUCTS}{self.lens.id}/generate-variants/", {"sph_from": "0", "sph_to": "0"})
        self.assertEqual(response.status_code, 403)
        self.assertFalse(LensVariant.objects.exists())


class CatalogIsolationTests(CatalogBase):
    def test_other_labs_rows_are_invisible_and_unusable(self):
        other = make_lab()
        other_brand = Brand.objects.create(lab=other, name="Other")
        other_cat = Category.objects.create(lab=other, name="Other")
        other_product = make_product(other, "stock_lens")
        other_variant = make_variant(other_product)

        self.assertEqual(self.client.get(PRODUCTS).json()["count"], 0)
        self.assertEqual(self.client.get(f"{PRODUCTS}{other_product.id}/").status_code, 404)
        self.assertEqual(self.client.get(f"{PRODUCTS}{other_product.id}/grid/").status_code, 404)
        self.assertEqual(self.client.get(f"{VARIANTS}{other_variant.id}/").status_code, 404)
        self.assertEqual(self.client.get(BRANDS).json()["count"], 0)
        response = self.client.post(PRODUCTS, {
            "kind": "frame", "name": "x", "sale_price": "1", "brand": other_brand.id, "category": other_cat.id,
        })
        self.assertEqual(set(response.json()["errors"]), {"brand", "category"})
        response = self.client.post(VARIANTS, {"product": other_product.id, "sph": "0"})
        self.assertIn("product", response.json()["errors"])
        self.assertEqual(self.client.post(f"{CATEGORIES}", {"name": "x", "parent": other_cat.id}).status_code, 400)
        other_product.barcode = "555"
        other_product.save()
        self.assertEqual(self.client.get("/api/v1/catalog/lookup/", {"code": "555"}).status_code, 400)
