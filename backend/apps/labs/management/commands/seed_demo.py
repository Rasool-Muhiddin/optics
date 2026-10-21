"""
`python manage.py seed_demo [--noinput]`

**Deletes ALL data** in the database, then builds one realistic demo lab so every screen and list
has something to show: "مختبر عوينات الجامعة" (owner `ali` / `aasddff`, also a Django Admin
superuser), two staff members, three doctors (links + referrals in every status), a catalog of every
product kind (frames, stock lenses with power tables, made-to-order lenses, contact lenses,
accessories, solutions, services) with groups and brands, suppliers with orders of all three types
in every status, patients with exams and prescriptions, invoices (named / unnamed walk-ins, patients,
discounts, credit with later payments, one cancelled) and customer glasses in every status.

Everything goes through the same services as the API (stock ledger, weighted average, checkout,
receiving, job transitions…). Each scenario is a generator that yields the day (days ago) it moves
to; a small scheduler runs all of them in date order under a patched clock, so numbers, dates,
quantities, balances, costs and status histories stay consistent. Re-run it any time: it always
starts from an empty database. Refused when DEBUG is off unless `--allow-production` is given.
"""

import heapq
import random
from contextlib import contextmanager
from datetime import datetime, time, timedelta
from decimal import Decimal
from unittest import mock

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import F
from django.utils import timezone

from apps.billing.models import License, Plan
from apps.catalog.attributes import clean_attributes
from apps.catalog.models import Brand, Category, LensVariant, Product
from apps.doctors import services as doctor_services
from apps.doctors.models import DoctorLabLink, DoctorProfile
from apps.doctors.serializers import ReferralRxSerializer
from apps.jobs import services as job_services
from apps.jobs.models import Job
from apps.labs.models import Lab, LabUser
from apps.patients.models import EyeExam, Patient, Prescription
from apps.patients.rx import clean_rx
from apps.purchasing import services as po_services
from apps.purchasing.models import Supplier, SupplierOrder, SupplierPayment
from apps.sales import services as sales_services
from apps.sales.models import Invoice, Payment

PASSWORD = "aasddff"
LAB_NAME = "مختبر عوينات الجامعة"


def q(value):
    """Decimal from int, float, str or Decimal."""
    return Decimal(str(value))


def frange(start, stop, step=0.25):
    """Inclusive 0.25-step range from `start` to `stop` (either direction)."""
    start, stop, step = q(start), q(stop), abs(q(step))
    if stop < start:
        step = -step
    values, v = [], start
    while (v <= stop) if step > 0 else (v >= stop):
        values.append(v)
        v += step
    return values


class Command(BaseCommand):
    help = "Delete ALL data and load the demo lab (مختبر عوينات الجامعة, owner ali)."

    def add_arguments(self, parser):
        parser.add_argument("--noinput", action="store_true", help="Do not ask for confirmation.")
        parser.add_argument(
            "--allow-production", action="store_true", help="Allow running with DEBUG off (dangerous)."
        )

    def handle(self, *args, noinput=False, allow_production=False, **options):
        if not settings.DEBUG and not allow_production:
            raise CommandError("DEBUG is off: refusing to wipe this database (use --allow-production).")
        if not noinput:
            answer = input("This DELETES ALL DATA in the database and loads demo data. Type 'yes': ")
            if answer.strip().lower() != "yes":
                raise CommandError("Cancelled.")
        call_command("flush", interactive=False, verbosity=0)
        self.rng = random.Random(2026)
        self.today = timezone.localdate()
        self.real_now = timezone.localtime()
        self.cur = 75
        self._ticks = {}
        self.pt = {}
        with transaction.atomic():
            self.run(
                self.s_setup(), self.s_stock(), self.s_doctors(), self.s_yasser(), self.s_hussein(),
                self.s_zainab(), self.s_saif(), self.s_mustafa(), self.s_huda(), self.s_fatima(), self.s_saja(),
                self.s_ahmed(), self.s_karrar(), self.s_alireda(), self.s_abbas(), self.s_suad(), self.s_noor(),
                self.s_mohammed(), self.s_ruqaya(), self.s_exams_only(), self.s_today(), self.s_walk_ins(),
                self.s_referrals(), self.s_new_patients(),
            )
            # `paid_at` / `requested_at` defaults are bound to the real clock: align them with the
            # (patched) creation time.
            Payment.objects.update(paid_at=F("created_at"))
            SupplierPayment.objects.update(paid_at=F("created_at"))
            DoctorLabLink.objects.update(requested_at=F("created_at"))
        if options.get("verbosity", 1):
            self._report()

    # ------------------------------------------------------------------ scheduler & clock

    def run(self, *scenarios):
        """Runs the scenario generators interleaved by date (oldest first; ties keep their order)."""
        heap = []

        def advance(seq, gen):
            try:
                days_ago = next(gen)
            except StopIteration:
                return
            heapq.heappush(heap, (-days_ago, seq, gen))

        for seq, gen in enumerate(scenarios):
            advance(seq, gen)
        while heap:
            neg_days, seq, gen = heapq.heappop(heap)
            if -neg_days > self.cur:
                raise CommandError("A scenario went back in time.")
            self.cur = -neg_days
            advance(seq, gen)

    def day(self, days_ago=None):
        return self.today - timedelta(days=self.cur if days_ago is None else days_ago)

    def _moment(self):
        """Next moment of the current day: events of a day get increasing times."""
        n = self._ticks.get(self.cur, 0)
        self._ticks[self.cur] = n + 1
        if self.cur == 0:  # today: a few hours before now, so nothing is in the future
            start = max(
                self.real_now - timedelta(hours=4),
                timezone.make_aware(datetime.combine(self.today, time(0, 5))),
            )
            return start + timedelta(minutes=3 * n)
        start = timezone.make_aware(datetime.combine(self.day(), time(9, 0)))
        return start + timedelta(minutes=9 * n)

    @contextmanager
    def clock(self):
        """Everything created inside is dated now on the current day (auto timestamps, localdate…)."""
        with mock.patch("django.utils.timezone.now", return_value=self._moment()):
            yield

    def phone(self):
        return f"07{self.rng.choice('7859')}{self.rng.randint(0, 99999999):08d}"

    # ------------------------------------------------------------------ domain helpers

    def v(self, key, sph, cyl=0, add=0):
        return LensVariant.objects.get(product=self.p[key], sph=q(sph), cyl=q(cyl), add=q(add))

    def patient(self, key, name, age):
        with self.clock():
            self.pt[key] = Patient.objects.create(
                lab=self.lab, full_name=name, phone=self.phone(), birth_date=Patient.birth_date_for_age(age),
                birth_date_estimated=True, created_by=self.ali,
            )
        return self.pt[key]

    def exam(self, key, rx, *, diagnosis, va=("6/12", "6/12"), complaint="", design="single_vision", index="",
             coatings=(), usage="distance", pd="63.0", by=None, notes=""):
        """Exam + its prescription, validated like the API. `rx` = {"od_sph": "-1.25", …}."""
        patient, user = self.pt[key], by or self.ali
        with self.clock():
            exam = EyeExam.objects.create(
                lab=self.lab, patient=patient, exam_date=self.day(), examined_by=user,
                chief_complaint=complaint, diagnosis=diagnosis, va_od=va[0], va_os=va[1], notes=notes,
                created_by=user,
            )
            data = clean_rx({
                **{k: (q(val) if k.endswith(("sph", "cyl", "add")) else val) for k, val in rx.items()},
                "pd_distance": q(pd), "usage": usage, "lens_design": design, "lens_index": index,
                "lens_coatings": list(coatings), "od_va": "6/6", "os_va": "6/6",
            })
            prescription = Prescription.objects.create(
                lab=self.lab, patient=patient, exam=exam, rx_date=self.day(), created_by=user, **data,
            )
            if patient.status == Patient.Status.NEW:
                patient.status = Patient.Status.EXAM_DONE
                patient.save(update_fields=["status", "updated_at"])
        return prescription

    def sell(self, items, *, patient=None, name="", phone="", credit=False, down=0, method="cash",
             invoice_discount=0, percent=False, cashier=None, notes=""):
        """`items`: (product key | LensVariant, qty[, line discount amount])."""
        lines = []
        for item in items:
            target, qty = item[0], item[1]
            discount = q(item[2] if len(item) > 2 else 0)
            if isinstance(target, LensVariant):
                lines.append({"product": target.product, "variant": target, "qty": qty, "discount": discount})
            else:
                lines.append({"product": self.p[target], "variant": None, "qty": qty, "discount": discount})
        lab_user = cashier or self.owner
        with self.clock():
            return sales_services.checkout(lab_user=lab_user, user=lab_user.user, data={
                "patient": self.pt[patient] if patient else None,
                "customer_name": name, "customer_phone": phone,
                "payment_type": "credit" if credit else "cash",
                "lines": lines,
                "invoice_discount_type": "percent" if percent else "amount",
                "invoice_discount_value": q(invoice_discount),
                "payment": {"amount": q(down), "method": method},
                "notes": notes,
            })

    def pay(self, invoice, amount, method="cash"):
        invoice.refresh_from_db()
        with self.clock():
            sales_services.add_payment(
                invoice=invoice, amount=invoice.balance if amount == "all" else q(amount), method=method,
                user=self.ali,
            )

    def job(self, patient, *, rx=None, invoice=None, frame=None, frame_source="lab", frame_notes="", lens=None,
            od=None, os=None, promised_in=4, notes=""):
        with self.clock():
            return job_services.create_job(lab=self.lab, user=self.ali, data={
                "patient": self.pt[patient], "prescription": rx, "invoice": invoice,
                "frame_source": frame_source, "frame": self.p[frame] if frame else None, "frame_notes": frame_notes,
                "lens": self.p[lens] if lens else None, "lens_od": od, "lens_os": os,
                "promised_date": self.day(self.cur - promised_in), "notes": notes,
            })

    def move(self, job, status, note=""):
        with self.clock():
            return job_services.change_status(job=job, to_status=status, user=self.ali, note=note)

    def order(self, supplier, type_, lines, *, status="ordered", expected_in=None, job=None, ref="", notes=""):
        with self.clock():
            return po_services.create_order(lab=self.lab, user=self.ali, data={
                "supplier": self.s[supplier], "type": type_, "job": job, "status": status,
                "order_date": self.day(),
                "expected_date": None if expected_in is None else self.day(self.cur - expected_in),
                "supplier_ref": ref, "notes": notes, "lines": lines,
            })

    def rx_order(self, job, supplier, lens_key, rx, *, cost, expected_in=5):
        """One line per eye, described from the prescription (as the glasses screen does)."""
        def describe(eye):
            sph, cyl, axis, add = (getattr(rx, f"{eye}_{n}") for n in ("sph", "cyl", "axis", "add"))
            text = f"SPH {sph:+.2f}"
            if cyl:
                text += f" CYL {cyl:+.2f} × {axis}"
            if add:
                text += f" ADD {add:+.2f}"
            return text

        lines = [
            {"product": self.p[lens_key], "description": describe(eye), "eye": eye, "qty": 1, "unit_cost": str(cost)}
            for eye in ("od", "os") if getattr(rx, f"{eye}_sph") is not None
        ]
        return self.order(supplier, "rx_for_job", lines, job=job, expected_in=expected_in)

    def receive(self, order, lines=None, ref=""):
        with self.clock():
            if ref:
                SupplierOrder.objects.filter(pk=order.pk).update(supplier_ref=ref)
            return po_services.receive(order=order, user=self.ali, lines=lines)

    def pay_order(self, order, amount="all", method="cash"):
        order.refresh_from_db()
        with self.clock():
            po_services.add_payment(
                order=order, amount=order.balance if amount == "all" else q(amount), method=method, user=self.ali
            )

    # ------------------------------------------------------------------ setup: lab, users, catalog, suppliers

    def s_setup(self):
        yield 75
        User = get_user_model()
        with self.clock():
            plan = Plan.objects.create(
                code="premium", name="الباقة المميزة", price=q(75000),
                max_users=5, max_devices=3, doctor_linking=True, report_export=True,
            )
            self.lab = Lab.objects.create(
                name=LAB_NAME,
                phone="07801234567",
                address="بغداد - الجادرية، مقابل البوابة الرئيسية لجامعة بغداد",
                print_header="فحص النظر بالكمبيوتر • عدسات طبية ولاصقة • إطارات عالمية\n"
                             "هاتف: 07801234567 - 07709876543",
                print_footer="شكراً لزيارتكم — العدسات المفصّلة لا تُرد ولا تُستبدل بعد التصنيع",
                max_discount_percent=q(10),
            )
            License.objects.create(lab=self.lab, plan=plan, starts_on=self.day())
            self.ali = User.objects.create_user(
                username="ali", password=PASSWORD, first_name="علي", last_name="الجامعي",
                is_staff=True, is_superuser=True,
            )
            self.owner = LabUser.objects.create(lab=self.lab, user=self.ali, role=LabUser.Role.OWNER,
                                                phone="07801234567")
            self.zahraa = User.objects.create_user(username="zahraa", password=PASSWORD, first_name="زهراء",
                                                   last_name="كريم")
            self.staff = LabUser.objects.create(lab=self.lab, user=self.zahraa, role=LabUser.Role.STAFF,
                                                phone="07712345678")
            mustafa = User.objects.create_user(username="mustafa", password=PASSWORD, first_name="مصطفى",
                                               last_name="فاضل")
            LabUser.objects.create(lab=self.lab, user=mustafa, role=LabUser.Role.STAFF, phone="07823456789",
                                   can_manage_inventory=True)
        yield 72
        self._catalog()
        self._suppliers()

    def _catalog(self):
        lab = self.lab
        with self.clock():
            def cat(name, parent=None):
                return Category.objects.create(lab=lab, name=name, parent=parent)

            frames = cat("إطارات طبية")
            self.cat = {
                "men": cat("رجالي", frames), "women": cat("نسائي", frames), "kids": cat("أطفال", frames),
                "sun": cat("نظارات شمسية"), "lens": cat("عدسات طبية"), "contact": cat("عدسات لاصقة"),
                "acc": cat("إكسسوارات ومحاليل"), "service": cat("خدمات"),
            }
            self.brand = {
                name: Brand.objects.create(lab=lab, name=name)
                for name in ["Ray-Ban", "Oakley", "Vogue", "Carrera", "Police", "Essilor", "Hoya", "Zeiss",
                             "Acuvue", "Bausch & Lomb", "FreshLook", "Renu", "Opti-Free"]
            }
            self.p = {}
            barcodes = iter(range(6291001000017, 6291001999999, 10))

            def product(key, kind, name, sale, cost, *, brand=None, category=None, attrs=None, reorder=0,
                        barcode=True, sku=""):
                self.p[key] = Product.objects.create(
                    lab=lab, kind=kind, name=name, brand=self.brand.get(brand), category=self.cat.get(category),
                    sale_price=q(sale), purchase_price=q(cost), reorder_level=reorder,
                    barcode=str(next(barcodes)) if barcode else "", sku=sku,
                    track_stock=kind not in ("rx_lens", "service"),
                    attributes=clean_attributes(kind, attrs or {}), created_by=self.ali,
                )

            def frame(gender, size, material, shape, rim, color, model=""):
                return {"model": model, "color": color, "size": size, "material": material, "gender": gender,
                        "shape": shape, "frame_type": rim}

            # Frames
            product("clubmaster", "frame", "Ray-Ban RB5154 Clubmaster", 185000, 120000, brand="Ray-Ban",
                    category="men", reorder=2, sku="RB5154",
                    attrs=frame("unisex", "51-21-145", "أسيتات ومعدن", "كلوب ماستر", "full_rim", "أسود/ذهبي",
                                "RB5154"))
            product("aviator", "frame", "Ray-Ban RB3025 Aviator شمسية", 210000, 140000, brand="Ray-Ban",
                    category="sun", reorder=1, sku="RB3025",
                    attrs=frame("unisex", "58-14-135", "معدن", "طيار", "full_rim", "ذهبي", "RB3025"))
            product("oakley", "frame", "Oakley OX8156 Holbrook", 165000, 105000, brand="Oakley", category="men",
                    reorder=1, attrs=frame("men", "54-18-142", "O-Matter", "مستطيل", "full_rim", "أسود مطفي",
                                           "OX8156"))
            product("vogue", "frame", "Vogue VO5239 نسائي", 95000, 55000, brand="Vogue", category="women",
                    reorder=2, attrs=frame("women", "52-17-140", "أسيتات", "عين القطة", "full_rim", "بني هافانا",
                                           "VO5239"))
            product("carrera", "frame", "Carrera 8840 معدني", 120000, 75000, brand="Carrera", category="men",
                    reorder=2, attrs=frame("men", "54-17-145", "ستانلس ستيل", "مستطيل", "semi_rimless", "فضي",
                                           "8840"))
            product("police", "frame", "Police VPLD91 تيتانيوم", 135000, 80000, brand="Police", category="men",
                    reorder=2, attrs=frame("men", "55-18-145", "تيتانيوم", "مربع", "rimless", "رصاصي", "VPLD91"))
            product("kids", "frame", "إطار أطفال مرن TR90", 45000, 22000, category="kids", reorder=3,
                    attrs=frame("kids", "46-15-125", "TR90 مرن", "دائري", "full_rim", "أزرق"))
            product("economy", "frame", "إطار معدني اقتصادي", 35000, 15000, category="men", reorder=4,
                    attrs=frame("unisex", "53-18-140", "معدن", "مستطيل", "full_rim", "أسود"))
            # Stock lenses (stock per power)
            sv = {"design": "single_vision", "diameter": "70"}
            product("cr156", "stock_lens", "Hoya CR-39 1.56 مضاد للانعكاس", 25000, 9000, brand="Hoya",
                    category="lens", reorder=10, barcode=False,
                    attrs={**sv, "material": "CR-39", "index": "1.56", "coatings": ["ar", "hard_coat"]})
            product("blue160", "stock_lens", "Essilor 1.60 Blue Cut", 45000, 18000, brand="Essilor",
                    category="lens", reorder=6, barcode=False,
                    attrs={**sv, "material": "MR-8", "index": "1.60", "coatings": ["ar", "blue_cut", "uv"]})
            product("photo159", "stock_lens", "Hoya بولي كربونات 1.59 فوتوكروميك", 60000, 25000, brand="Hoya",
                    category="lens", reorder=4, barcode=False,
                    attrs={**sv, "material": "بولي كربونات", "index": "1.59",
                           "coatings": ["photochromic", "ar", "uv"]})
            # Made-to-order lenses (no stock: ordered per customer's glasses)
            product("varilux", "rx_lens", "Essilor Varilux Comfort 1.60 تدريجي", 175000, 80000, brand="Essilor",
                    category="lens", barcode=False,
                    attrs={"material": "MR-8", "index": "1.60", "design": "progressive",
                           "coatings": ["ar", "hard_coat", "uv"]})
            product("zeiss167", "rx_lens", "Zeiss SmartLife 1.67 أحادي البؤرة", 120000, 55000, brand="Zeiss",
                    category="lens", barcode=False,
                    attrs={"material": "MR-7", "index": "1.67", "design": "single_vision",
                           "coatings": ["ar", "blue_cut", "hydrophobic"]})
            product("bifocal", "rx_lens", "Hoya ثنائي البؤرة 1.56", 40000, 15000, brand="Hoya", category="lens",
                    barcode=False,
                    attrs={"material": "CR-39", "index": "1.56", "design": "bifocal", "coatings": ["hard_coat"]})
            product("hoya174", "rx_lens", "Hoya 1.74 عالي الانكسار", 150000, 70000, brand="Hoya", category="lens",
                    barcode=False,
                    attrs={"material": "MR-174", "index": "1.74", "design": "single_vision", "coatings": ["ar"]})
            # Contact lenses (stock per power)
            product("acuvue", "contact_lens", "Acuvue Oasys (أسبوعين) علبة 6", 45000, 28000, brand="Acuvue",
                    category="contact", reorder=6, barcode=False,
                    attrs={"replacement": "biweekly", "base_curve": "8.4", "diameter": "14.0",
                           "material": "سيليكون هيدروجيل", "pack_size": "6"})
            product("soflens", "contact_lens", "SofLens يومي علبة 30", 30000, 18000, brand="Bausch & Lomb",
                    category="contact", reorder=4, barcode=False,
                    attrs={"replacement": "daily", "base_curve": "8.6", "diameter": "14.2", "pack_size": "30"})
            product("freshlook", "contact_lens", "FreshLook ملونة شهرية (رمادي)", 25000, 12000, brand="FreshLook",
                    category="contact", reorder=2, barcode=False,
                    attrs={"replacement": "monthly", "base_curve": "8.6", "diameter": "14.5", "color": "رمادي",
                           "pack_size": "2"})
            # Accessories, solutions, services
            product("case", "accessory", "علبة نظارة جلد", 7000, 3000, category="acc", reorder=5,
                    attrs={"material": "جلد صناعي", "color": "أسود"})
            product("cloth", "accessory", "قطعة تنظيف مايكروفايبر", 2000, 500, category="acc", reorder=20,
                    attrs={"material": "مايكروفايبر"})
            product("chain", "accessory", "سلسلة نظارة", 5000, 2000, category="acc", reorder=3,
                    attrs={"material": "معدن", "color": "ذهبي"})
            product("lenscase", "accessory", "علبة عدسات لاصقة", 3000, 1000, category="acc", reorder=5)
            product("renu", "solution", "محلول Renu 360 مل", 12000, 7000, brand="Renu", category="acc", reorder=5,
                    attrs={"volume_ml": "360"})
            product("optifree", "solution", "محلول Opti-Free 300 مل", 15000, 9000, brand="Opti-Free",
                    category="acc", reorder=5, attrs={"volume_ml": "300"})
            product("spray", "solution", "بخاخ تنظيف العدسات 60 مل", 4000, 1500, category="acc", reorder=5,
                    attrs={"volume_ml": "60"})
            product("exam", "service", "فحص نظر بالكمبيوتر", 10000, 0, category="service", barcode=False)
            product("fitting", "service", "تركيب عدسات على إطار الزبون", 15000, 0, category="service",
                    barcode=False)
            product("repair", "service", "تصليح وتعديل إطار", 5000, 0, category="service", barcode=False)

            # Power tables (minus-cyl, as stock lenses are sold).
            def grid(key, sphs, cyls):
                LensVariant.objects.bulk_create(
                    [LensVariant(lab=lab, product=self.p[key], sph=s, cyl=c) for s in sphs for c in cyls]
                )

            grid("cr156", frange(-4, 3), frange(0, -2))
            grid("blue160", frange(-5, 2), frange(0, -1.5))
            grid("photo159", frange(-3, 2.5), frange(0, -1))
            grid("acuvue", frange(-0.5, -6), [q(0)])
            grid("soflens", frange(-0.75, -5), [q(0)])
            grid("freshlook", [q(0), q(-1), q(-2), q(-3)], [q(0)])
            # Contact lens boxes carry their own barcode per power (scanned at the POS).
            for i, variant in enumerate(self.p["acuvue"].variants.order_by("-sph")[:12]):
                variant.barcode = f"07339050{i:05d}"
                variant.save(update_fields=["barcode"])

    def _suppliers(self):
        self.s = {}
        with self.clock():
            for key, name, phone, address, notes in [
                ("golden", "شركة النظارات الذهبية", "07901112233", "بغداد - شارع السعدون",
                 "وكيل Ray-Ban و Oakley و Vogue"),
                ("essilor", "وكالة إيسيلور العراق", "07702223344", "بغداد - الكرادة داخل",
                 "عدسات تدريجية وتفصيل خلال 5 أيام"),
                ("hoya", "مختبر هويا للعدسات", "07803334455", "بغداد - الكرادة، ساحة كهرمانة", ""),
                ("rafidain", "شركة الرافدين للعدسات اللاصقة", "07504445566", "بغداد - المنصور", ""),
                ("amin", "مكتب الأمين للإكسسوارات", "07715556677", "بغداد - الشورجة", ""),
            ]:
                self.s[key] = Supplier.objects.create(
                    lab=self.lab, name=name, phone=phone, address=address, notes=notes, created_by=self.ali
                )

    # ------------------------------------------------------------------ stock & supplier orders

    def s_stock(self):
        def lens_lines(key, sphs, cyls, qty, cost):
            return [{"product": self.p[key], "variant": self.v(key, s, c), "qty": qty, "unit_cost": str(cost)}
                    for s in sphs for c in cyls]

        yield 66  # old debt from before the system: an "other" order with a free-text line
        p = self.p
        debt = self.order("golden", "other", [
            {"description": "رصيد سابق مستحق للمورد قبل استخدام النظام", "qty": 1, "unit_cost": "350000"},
        ], notes="دين قديم")
        self.receive(debt)

        yield 60
        frames = self.order("golden", "stock", [
            {"product": p["clubmaster"], "qty": 6, "unit_cost": "120000"},
            {"product": p["aviator"], "qty": 4, "unit_cost": "140000"},
            {"product": p["oakley"], "qty": 4, "unit_cost": "105000"},
            {"product": p["vogue"], "qty": 6, "unit_cost": "55000"},
            {"product": p["carrera"], "qty": 3, "unit_cost": "75000"},
            {"product": p["police"], "qty": 2, "unit_cost": "80000"},
            {"product": p["kids"], "qty": 8, "unit_cost": "22000"},
            {"product": p["economy"], "qty": 12, "unit_cost": "15000"},
        ], expected_in=2, ref="GF-2231")
        yield 59
        hoya = self.order("hoya", "stock",
                          lens_lines("cr156", frange(-3, 2.5), [0, -0.5, -1], 2, 9000)
                          + lens_lines("photo159", frange(-2, 2), [0, -0.5], 2, 25000), expected_in=2)
        essilor = self.order("essilor", "stock", lens_lines("blue160", frange(-4, 0), [0, -0.5, -1], 2, 18000),
                             expected_in=2)
        yield 58
        self.receive(frames, ref="GF-2231")
        yield 57
        self.receive(hoya, ref="HY-0912")
        self.receive(essilor, ref="ES-5521")
        yield 50
        self.pay_order(frames, method="transfer")
        yield 47
        contact = self.order("rafidain", "stock",
                             lens_lines("acuvue", frange(-1, -4), [0], 3, 28000)
                             + lens_lines("soflens", frange(-1, -3), [0], 2, 18000)
                             + lens_lines("freshlook", [0, -1, -2], [0], 3, 12000)
                             + [{"product": p["renu"], "qty": 12, "unit_cost": "7000"},
                                {"product": p["optifree"], "qty": 6, "unit_cost": "9000"},
                                {"product": p["spray"], "qty": 20, "unit_cost": "1500"}],
                             expected_in=3)
        yield 45
        self.receive(contact, ref="RF-118")  # left unpaid on purpose (supplier balance)
        self.pay_order(hoya, 600000)
        yield 42
        acc = self.order("amin", "stock", [
            {"product": p["case"], "qty": 25, "unit_cost": "3000"},
            {"product": p["cloth"], "qty": 80, "unit_cost": "500"},
            {"product": p["chain"], "qty": 10, "unit_cost": "2000"},
            {"product": p["lenscase"], "qty": 6, "unit_cost": "1000"},
        ], expected_in=1)
        yield 41
        self.receive(acc)
        self.pay_order(acc)
        yield 40
        self.pay_order(essilor, method="transfer")
        yield 30
        cancelled = self.order("golden", "stock", [{"product": p["oakley"], "qty": 5, "unit_cost": "105000"}],
                               expected_in=7)
        yield 27
        with self.clock():
            po_services.cancel(order=cancelled, user=self.ali, reason="المورد لا يملك الكمية المطلوبة حالياً")
        yield 20
        self.pay_order(debt, 150000)
        tools = self.order("amin", "other", [
            {"description": "أدوات ورشة: مفكات دقيقة وبراغي ووسادات أنف", "qty": 1, "unit_cost": "45000"},
        ])
        yield 19
        self.receive(tools)
        self.pay_order(tools)
        yield 12
        solutions = self.order("rafidain", "stock", [
            {"product": p["optifree"], "qty": 24, "unit_cost": "9000"},
            {"product": p["renu"], "qty": 12, "unit_cost": "7000"},
        ], expected_in=7)
        yield 6
        self.order("golden", "stock", [
            {"product": p["carrera"], "qty": 4, "unit_cost": "75000"},
            {"product": p["police"], "qty": 3, "unit_cost": "80000"},
        ], expected_in=9, ref="GF-2307")
        yield 3  # half of the solutions arrived; the rest is late
        self.receive(solutions, lines=[{"line": solutions.lines.get(product=p["optifree"]), "qty": 12}])
        self.pay_order(solutions, 50000)
        yield 0  # draft, not sent yet
        self.order("amin", "stock", [
            {"product": p["case"], "qty": 20, "unit_cost": "3000"},
            {"product": p["lenscase"], "qty": 15, "unit_cost": "1000"},
        ], status="pending", notes="بانتظار تأكيد الأسعار من المكتب")

    # ------------------------------------------------------------------ doctors

    def s_doctors(self):
        yield 65
        User = get_user_model()
        self.doc = {}
        with self.clock():
            for key, name, specialty, clinic, phone in [
                ("ahmed", "أحمد الربيعي", "طب وجراحة العيون", "عيادة النور التخصصية - الكرادة", "07709990011"),
                ("sara", "سارة الجبوري", "بصريات وعدسات لاصقة", "مركز رؤية للعيون - المنصور", "07809990022"),
                ("haider", "حيدر العبيدي", "طب عيون الأطفال", "عيادة الأمل - زيونة", "07509990033"),
            ]:
                user = User.objects.create_user(username=f"dr_{key}", password=PASSWORD)
                self.doc[key] = DoctorProfile.objects.create(
                    user=user, full_name=name, specialty=specialty, clinic_name=clinic, phone=phone, address="بغداد",
                )
        yield 64
        with self.clock():
            link = doctor_services.doctor_requests_link(doctor=self.doc["ahmed"], lab_code=self.lab.doctor_link_code)
        yield 63
        with self.clock():
            doctor_services.respond(link=link, side="lab", accept=True)
        yield 50
        with self.clock():
            link = doctor_services.lab_requests_link(lab=self.lab, doctor_code=self.doc["sara"].link_code)
        yield 49
        with self.clock():
            doctor_services.respond(link=link, side="doctor", accept=True)
        yield 1  # waiting for the owner's answer
        with self.clock():
            doctor_services.doctor_requests_link(
                doctor=self.doc["haider"], lab_code=self.lab.doctor_link_code, note="نرغب بإرسال مرضى الأطفال"
            )

    # ------------------------------------------------------------------ customers (one story each)

    def s_yasser(self):
        """Old credit sale, paid off in two payments; delivered long ago."""
        yield 52
        self.patient("yasser", "ياسر طالب الكعبي", 48)
        rx = self.exam("yasser", {"od_sph": "-1.75", "od_cyl": "-0.50", "od_axis": 175, "os_sph": "-1.50"},
                       diagnosis="قصر نظر مع لابؤرية خفيفة", index="1.56", coatings=["ar"])
        od, os = self.v("cr156", -1.75, -0.5), self.v("cr156", -1.5)
        inv = self.sell([("economy", 1), (od, 1), (os, 1)], patient="yasser", credit=True, down=40000)
        job = self.job("yasser", rx=rx, invoice=inv, frame="economy", lens="cr156", od=od, os=os, promised_in=2)
        yield 51
        self.move(job, "in_workshop")
        yield 50
        self.move(job, "ready", "تم التركيب والفحص")
        yield 49
        self.move(job, "delivered")
        yield 40
        self.pay(inv, 25000)
        yield 30
        self.pay(inv, "all", "card")

    def s_hussein(self):
        """Progressive lenses ordered from the supplier; delivered; still owes part of the invoice."""
        yield 42
        self.patient("hussein", "حسين علي كاظم", 46)
        rx = self.exam("hussein", {"od_sph": "-1.25", "od_cyl": "-0.50", "od_axis": 180, "od_add": "1.75",
                                   "os_sph": "-1.00", "os_add": "1.75"},
                       diagnosis="طول نظر شيخوخي مع قصر نظر", design="progressive", index="1.60",
                       coatings=["ar", "hard_coat"], usage="both", complaint="صعوبة في القراءة")
        inv = self.sell([("clubmaster", 1), ("varilux", 2), ("exam", 1)], patient="hussein", credit=True,
                        down=200000, invoice_discount=15000)
        job = self.job("hussein", rx=rx, invoice=inv, frame="clubmaster", lens="varilux", promised_in=7)
        po = self.rx_order(job, "essilor", "varilux", rx, cost=80000)
        yield 37
        self.receive(po)  # the glasses move to the workshop automatically
        yield 36
        self.move(job, "ready", "تم التركيب")
        yield 35
        self.move(job, "delivered")
        yield 30
        self.pay_order(po)
        yield 15
        self.pay(inv, 150000)

    def s_zainab(self):
        yield 36
        self.patient("zainab", "زينب محمد جاسم", 31)
        rx = self.exam("zainab", {"od_sph": "-2.25", "od_cyl": "-0.50", "od_axis": 10, "os_sph": "-2.00"},
                       diagnosis="قصر نظر", index="1.60", coatings=["blue_cut"],
                       complaint="إجهاد عند استخدام الحاسوب")
        od, os = self.v("blue160", -2.25, -0.5), self.v("blue160", -2)
        inv = self.sell([("vogue", 1, 5000), (od, 1), (os, 1)], patient="zainab", cashier=self.staff)
        job = self.job("zainab", rx=rx, invoice=inv, frame="vogue", lens="blue160", od=od, os=os, promised_in=1)
        self.move(job, "in_workshop")
        yield 35
        self.move(job, "ready")
        yield 34
        self.move(job, "delivered")

    def s_saif(self):
        yield 30
        self.patient("saif", "سيف الدين وليد", 36)
        rx = self.exam("saif", {"od_sph": "-3.00", "os_sph": "-2.75", "os_cyl": "-0.50", "os_axis": 165},
                       diagnosis="قصر نظر", index="1.60")
        od, os = self.v("blue160", -3), self.v("blue160", -2.75, -0.5)
        inv = self.sell([("oakley", 1), (od, 1), (os, 1)], patient="saif", credit=True, down=100000)
        job = self.job("saif", rx=rx, invoice=inv, frame="oakley", lens="blue160", od=od, os=os, promised_in=2)
        yield 29
        self.move(job, "ready")
        yield 27
        self.move(job, "delivered")
        yield 12
        self.pay(inv, "all", "transfer")

    def s_mustafa(self):
        """Bifocal lenses ordered from Hoya: the supplier is late, so the glasses are overdue."""
        yield 26
        self.patient("mustafa", "مصطفى عبد الأمير حسن", 54)
        rx = self.exam("mustafa", {"od_sph": "+1.00", "od_add": "2.25", "os_sph": "+1.25", "os_cyl": "-0.50",
                                   "os_axis": 90, "os_add": "2.25"},
                       diagnosis="طول نظر شيخوخي", design="bifocal", index="1.56", usage="both")
        inv = self.sell([("carrera", 1), ("bifocal", 2)], patient="mustafa", credit=True, down=50000)
        job = self.job("mustafa", rx=rx, invoice=inv, frame="carrera", lens="bifocal", promised_in=20,
                       notes="الزبون يتصل يومياً")
        yield 25
        self.rx_order(job, "hoya", "bifocal", rx, cost=15000, expected_in=21)

    def s_huda(self):
        yield 23
        self.patient("huda", "هدى عبد الرزاق", 57)
        rx = self.exam("huda", {"od_sph": "+2.00", "os_sph": "+2.00"}, diagnosis="طول نظر شيخوخي", usage="near",
                       index="1.56", pd="61.0")
        lens = self.v("cr156", 2)
        inv = self.sell([("economy", 1), (lens, 2)], patient="huda")
        job = self.job("huda", rx=rx, invoice=inv, frame="economy", lens="cr156", od=lens, os=lens, promised_in=1)
        yield 22
        self.move(job, "ready")
        yield 21
        self.move(job, "delivered")

    def s_fatima(self):
        """Contact lenses (no glasses); comes back for more."""
        yield 21
        self.patient("fatima", "فاطمة حيدر عباس", 24)
        self.exam("fatima", {"od_sph": "-2.50", "os_sph": "-2.50"}, diagnosis="قصر نظر — عدسات لاصقة", pd="60.0",
                  notes="تفضّل العدسات اللاصقة")
        self.sell([(self.v("acuvue", -2.5), 2), ("renu", 1), ("lenscase", 1)], patient="fatima",
                  cashier=self.staff)
        yield 2
        self.sell([(self.v("acuvue", -2.5), 1), ("optifree", 1)], patient="fatima")

    def s_saja(self):
        """Changed her mind: glasses cancelled, invoice cancelled (stock returns, money refunded)."""
        yield 19
        self.patient("saja", "سجى ناصر الدليمي", 29)
        rx = self.exam("saja", {"od_sph": "-1.00", "os_sph": "-1.25"}, diagnosis="قصر نظر بسيط")
        od, os = self.v("cr156", -1), self.v("cr156", -1.25)
        inv = self.sell([("vogue", 1), (od, 1), (os, 1)], patient="saja")
        job = self.job("saja", rx=rx, invoice=inv, frame="vogue", lens="cr156", od=od, os=os, promised_in=2)
        yield 18
        self.move(job, "cancelled", "الزبونة غيّرت رأيها وطلبت استرجاع المبلغ")
        with self.clock():
            sales_services.cancel_invoice(invoice=inv, user=self.ali, reason="إلغاء بطلب الزبونة قبل التركيب")

    def s_ahmed(self):
        """Credit sale with nothing paid: the glasses are ready and waiting (unpaid at delivery)."""
        yield 16
        self.patient("ahmed", "أحمد جبار التميمي", 41)
        rx = self.exam("ahmed", {"od_sph": "-0.75", "od_cyl": "-0.50", "od_axis": 95, "os_sph": "-1.00",
                                 "os_cyl": "-0.50", "os_axis": 80}, diagnosis="لابؤرية", index="1.56")
        od, os = self.v("cr156", -0.75, -0.5), self.v("cr156", -1, -0.5)
        inv = self.sell([("police", 1), (od, 1), (os, 1)], patient="ahmed", credit=True)
        job = self.job("ahmed", rx=rx, invoice=inv, frame="police", lens="cr156", od=od, os=os, promised_in=3)
        yield 15
        self.move(job, "in_workshop")
        yield 14
        self.move(job, "ready", "تم الاتصال بالزبون")

    def s_karrar(self):
        yield 13
        self.patient("karrar", "كرار حسين الشمري", 22)
        self.sell([("aviator", 1), ("case", 1)], patient="karrar", invoice_discount=10000, cashier=self.staff)

    def s_alireda(self):
        """High myopia, Zeiss 1.67 ordered → received → in the workshop (moved automatically)."""
        yield 11
        self.patient("alireda", "علي رضا الموسوي", 38)
        rx = self.exam("alireda", {"od_sph": "-6.50", "od_cyl": "-1.00", "od_axis": 5, "os_sph": "-6.00",
                                   "os_cyl": "-0.75", "os_axis": 170},
                       diagnosis="قصر نظر شديد", index="1.67", coatings=["ar", "blue_cut"])
        inv = self.sell([("oakley", 1), ("zeiss167", 2)], patient="alireda", credit=True, down=150000)
        job = self.job("alireda", rx=rx, invoice=inv, frame="oakley", lens="zeiss167", promised_in=13)
        yield 10
        po = self.rx_order(job, "essilor", "zeiss167", rx, cost=55000, expected_in=6)
        yield 4
        self.receive(po)
        self.pay(inv, 100000)

    def s_abbas(self):
        """Progressive on the customer's own frame: lens ordered, arriving tomorrow."""
        yield 8
        self.patient("abbas", "عباس فاضل الساعدي", 63)
        rx = self.exam("abbas", {"od_sph": "+1.50", "od_add": "2.50", "os_sph": "+1.75", "os_add": "2.50"},
                       diagnosis="طول نظر شيخوخي", design="progressive", index="1.60", usage="both")
        inv = self.sell([("varilux", 2), ("fitting", 1)], patient="abbas", credit=True, down=100000,
                        invoice_discount=5, percent=True)
        job = self.job("abbas", rx=rx, invoice=inv, frame_source="customer",
                       frame_notes="إطار الزبون: معدني ذهبي قديم، يحتاج شد براغي", lens="varilux", promised_in=9)
        yield 7
        self.rx_order(job, "essilor", "varilux", rx, cost=80000, expected_in=8)

    def s_suad(self):
        """Customer's frame + stock lenses: still pending and already late."""
        yield 9
        self.patient("suad", "سعاد جاسم (أم علي)", 50)
        rx = self.exam("suad", {"od_sph": "+0.75", "os_sph": "+1.00"}, diagnosis="طول نظر بسيط", usage="near")
        od, os = self.v("cr156", 0.75), self.v("cr156", 1)
        inv = self.sell([(od, 1), (os, 1), ("fitting", 1)], patient="suad", cashier=self.staff)
        self.job("suad", rx=rx, invoice=inv, frame_source="customer", frame_notes="إطار بلاستيك بني", lens="cr156",
                 od=od, os=os, promised_in=7)

    def s_noor(self):
        """Paid, with a % invoice discount; ready for pickup."""
        yield 6
        self.patient("noor", "نور الهدى سلمان", 19)
        rx = self.exam("noor", {"od_sph": "-1.50", "os_sph": "-1.50", "os_cyl": "-0.50", "os_axis": 180},
                       diagnosis="قصر نظر", index="1.56")
        od, os = self.v("cr156", -1.5), self.v("cr156", -1.5, -0.5)
        inv = self.sell([("vogue", 1), (od, 1), (os, 1)], patient="noor", invoice_discount=5, percent=True,
                        cashier=self.staff)
        job = self.job("noor", rx=rx, invoice=inv, frame="vogue", lens="cr156", od=od, os=os, promised_in=2)
        self.move(job, "in_workshop")
        yield 4
        self.move(job, "ready")

    def s_mohammed(self):
        """A child with photochromic lenses: in the workshop and late."""
        yield 5
        self.patient("mohammed", "محمد قاسم الزبيدي", 11)
        rx = self.exam("mohammed", {"od_sph": "+1.50", "os_sph": "+1.25", "os_cyl": "-0.50", "os_axis": 90},
                       diagnosis="طول نظر — طفل", index="1.59", coatings=["photochromic"], pd="54.0",
                       complaint="يقترب كثيراً من التلفاز")
        od, os = self.v("photo159", 1.5), self.v("photo159", 1.25, -0.5)
        inv = self.sell([("kids", 1, 5000), (od, 1), (os, 1)], patient="mohammed")
        job = self.job("mohammed", rx=rx, invoice=inv, frame="kids", lens="photo159", od=od, os=os, promised_in=3,
                       notes="إطار مرن للأطفال")
        yield 4
        self.move(job, "in_workshop")

    def s_ruqaya(self):
        """Chose a lab frame, pays on pickup (no invoice yet); the Zeiss lens is not ordered yet."""
        yield 1
        self.patient("ruqaya", "رقية صادق العامري", 35)
        rx = self.exam("ruqaya", {"od_sph": "-4.25", "od_cyl": "-0.75", "od_axis": 15, "os_sph": "-4.00",
                                  "os_cyl": "-1.00", "os_axis": 165}, diagnosis="قصر نظر مع لابؤرية", index="1.67")
        self.job("ruqaya", rx=rx, frame="clubmaster", lens="zeiss167", promised_in=6, notes="ستدفع عند الاستلام")

    def s_exams_only(self):
        yield 10
        self.patient("ayat", "آيات منذر العبيدي", 21)
        self.exam("ayat", {"od_sph": "-1.25", "os_sph": "-1.25"}, diagnosis="قصر نظر", by=self.zahraa)
        yield 3
        self.patient("maryam", "مريم كريم الخفاجي", 27)
        self.exam("maryam", {"od_sph": "-0.50", "os_sph": "-0.75"}, diagnosis="قصر نظر بسيط جداً",
                  notes="لا تحتاج نظارة دائمة حالياً")

    def s_today(self):
        yield 0
        self.patient("haider", "حيدر سعد الجبوري", 66)
        rx = self.exam("haider", {"od_sph": "+2.25", "od_cyl": "-0.75", "od_axis": 100, "od_add": "2.75",
                                  "os_sph": "+2.00", "os_add": "2.75"},
                       diagnosis="طول نظر شيخوخي متقدم", design="progressive", index="1.60", usage="both")
        inv = self.sell([("economy", 1), ("varilux", 2)], patient="haider", credit=True, down=100000)
        self.job("haider", rx=rx, invoice=inv, frame="economy", lens="varilux", promised_in=7)
        self.patient("duaa", "دعاء ماجد البياتي", 33)
        self.sell([(self.v("freshlook", 0), 1), ("lenscase", 1)], patient="duaa", cashier=self.staff)

    def s_new_patients(self):
        yield 2
        self.patient("tabarak", "تبارك رائد", 26)
        yield 0
        self.patient("jaafar", "جعفر عادل", 9)

    def s_walk_ins(self):
        for days_ago, items, kwargs in [
            (38, [("renu", 1), ("cloth", 2)], {"name": "أبو حسن", "phone": "07711122334"}),
            (33, [("aviator", 1)], {"name": "سارة عدنان", "phone": "07822233445", "invoice_discount": 10000}),
            (28, [("spray", 1)], {"cashier": "staff"}),  # unnamed walk-in
            (24, [("chain", 1), ("case", 1)], {"name": "كاظم الحسيني", "phone": "07533344556", "cashier": "staff"}),
            (17, [("repair", 1)], {"name": "مرتضى جواد"}),
            (14, [("cloth", 1)], {}),  # unnamed walk-in
            (7, [("soflens@-1.5", 1), ("lenscase", 1)], {"name": "ليلى عادل", "phone": "07744455667",
                                                          "method": "card"}),
            (3, [("renu", 1), ("spray", 1)], {"name": "أم زهراء", "cashier": "staff"}),
            (1, [("repair", 1), ("cloth", 1)], {"name": "عمر فاروق", "phone": "07855566778"}),
            (0, [("optifree", 1)], {"name": "بنين علي", "cashier": "staff"}),
            (0, [("cloth", 1)], {}),  # unnamed walk-in
        ]:
            yield days_ago
            if kwargs.get("cashier") == "staff":
                kwargs = {**kwargs, "cashier": self.staff}
            items = [
                (self.v(key.split("@")[0], q(key.split("@")[1])), qty) if "@" in key else (key, qty)
                for key, qty in items
            ]
            self.sell(items, **kwargs)

    # ------------------------------------------------------------------ referrals

    def referral(self, doctor, name, age, gender, rx, diagnosis, complaint="", notes=""):
        serializer = ReferralRxSerializer(data=rx)
        serializer.is_valid(raise_exception=True)
        with self.clock():
            return doctor_services.create_referral(doctor=self.doc[doctor], lab=self.lab, data={
                "patient_name": name, "patient_age": age, "patient_gender": gender, "patient_phone": self.phone(),
                "exam_date": self.day(), "chief_complaint": complaint, "diagnosis": diagnosis,
                "va_od": "6/18", "va_os": "6/12", "prescription_data": serializer.validated_data, "notes": notes,
            })

    def s_referrals(self):
        # Completed: accepted → patient + exam + Rx in the lab → sold and delivered.
        yield 20
        ref = self.referral("ahmed", "سلوى عبد الحسين", 44, "female",
                            {"od_sph": "-2.00", "os_sph": "-2.25", "pd_distance": "62"}, "قصر نظر",
                            notes="يرجى عدسات مضادة للانعكاس")
        with self.clock():
            ref = doctor_services.accept(referral=ref, user=self.ali)
        self.pt["salwa"] = ref.patient
        yield 19
        od, os = self.v("cr156", -2), self.v("cr156", -2.25)
        inv = self.sell([("economy", 1), (od, 1), (os, 1)], patient="salwa")
        job = self.job("salwa", rx=ref.patient.prescriptions.first(), invoice=inv, frame="economy", lens="cr156",
                       od=od, os=os, promised_in=2)
        yield 18
        self.move(job, "ready")
        yield 17
        self.move(job, "delivered")
        with self.clock():
            doctor_services.complete(referral=ref, user=self.ali)
        # Rejected (duplicate).
        yield 6
        ref = self.referral("sara", "لؤي كريم", 27, "male", {"od_sph": "-1.00", "os_sph": "-1.00"}, "قصر نظر بسيط")
        yield 5
        with self.clock():
            doctor_services.reject(referral=ref, user=self.ali, reason="إحالة مكررة — المريض مسجّل في إحالة سابقة")
        # In progress: accepted 3 days ago.
        yield 4
        ref = self.referral("sara", "ضحى مهدي", 30, "female",
                            {"od_sph": "-3.25", "os_sph": "-3.00", "pd_distance": "60"}, "قصر نظر — عدسات لاصقة",
                            complaint="ترغب بعدسات لاصقة")
        yield 3
        with self.clock():
            doctor_services.accept(referral=ref, user=self.zahraa)
        # Received yesterday, not handled yet.
        yield 2
        ref = self.referral("ahmed", "عمار ثامر", 52, "male",
                            {"od_sph": "+1.50", "od_add": "2.00", "os_sph": "+1.50", "os_add": "2.00",
                             "pd_distance": "64", "usage": "both", "lens_design": "progressive"},
                            "طول نظر شيخوخي")
        yield 1
        with self.clock():
            doctor_services.mark_received(referral=ref, user=self.ali)
        # New today.
        yield 0
        self.referral("ahmed", "بنين حسن", 17, "female",
                      {"od_sph": "-0.75", "od_cyl": "-0.50", "od_axis": 180, "os_sph": "-1.00", "pd_distance": "58"},
                      "قصر نظر مع لابؤرية", complaint="صداع عند الدراسة")
        self.referral("sara", "غدير سالم", 24, "female", {"od_sph": "-2.75", "os_sph": "-2.50"}, "قصر نظر",
                      notes="عدسات لاصقة شهرية إن أمكن")

    # ------------------------------------------------------------------ summary

    def _report(self):
        # ASCII only: Windows consoles (cp1252) cannot print the Arabic lab name.
        lab = Lab.objects.get(pk=self.lab.pk)
        self.stdout.write(self.style.SUCCESS(f"Demo lab #{lab.id} is ready."))
        self.stdout.write(f"  Activation code (desktop app): {lab.activation_code}")
        self.stdout.write(f"  Owner: ali / {PASSWORD}  (also a Django Admin superuser)")
        self.stdout.write(f"  Staff: zahraa, mustafa / {PASSWORD}")
        self.stdout.write(f"  Doctors: dr_ahmed, dr_sara, dr_haider / {PASSWORD}")
        self.stdout.write(
            f"  {Patient.objects.count()} patients, {Product.objects.count()} products "
            f"({LensVariant.objects.count()} lens powers), {Invoice.objects.count()} invoices, "
            f"{Job.objects.count()} glasses, {SupplierOrder.objects.count()} supplier orders."
        )
