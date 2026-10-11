"""Shared test helpers: build labs with plans/licenses, members, devices and API sessions."""

import datetime
import itertools

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.accounts.models import AuthToken, Device
from apps.billing.models import License, Plan
from apps.labs.models import Lab, LabUser

_seq = itertools.count(1)
PASSWORD = "Str0ng-Pass!word"


def make_plan(**fields):
    n = next(_seq)
    defaults = {"code": f"plan-{n}", "name": f"Plan {n}", "max_users": 10, "max_devices": 5}
    return Plan.objects.create(**{**defaults, **fields})


def make_lab(name=None, *, plan=None, license=True, expires_on=None, **fields):
    lab = Lab.objects.create(name=name or f"Lab {next(_seq)}", **fields)
    if license:
        License.objects.create(
            lab=lab,
            plan=plan or make_plan(),
            starts_on=timezone.localdate() - datetime.timedelta(days=1),
            expires_on=expires_on,
        )
    return lab


def make_member(lab, role=LabUser.Role.STAFF, *, username=None, **fields):
    user = get_user_model().objects.create_user(
        username=username or f"user{next(_seq)}", password=PASSWORD
    )
    return LabUser.objects.create(lab=lab, user=user, role=role, **fields)


def make_device(lab, **fields):
    device = Device(lab=lab, device_id=fields.pop("device_id", f"dev-{next(_seq)}"), **fields)
    key = device.rotate_key()
    device.save()
    return device, key


class LabAPITestCase(APITestCase):
    """Clears the throttle cache and offers `login_as(member)`."""

    def setUp(self):
        super().setUp()
        cache.clear()

    def login_as(self, member, device=None):
        if device is None:
            device, _ = make_device(member.lab)
        _, key = AuthToken.issue(member.user, device)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {key}")
        return key


# --- Catalog & inventory (P2) ---------------------------------------------------------


def make_product(lab, kind="frame", **fields):
    from apps.catalog.models import Product

    defaults = {"name": f"Item {next(_seq)}", "sale_price": "10000.00"}
    return Product.objects.create(lab=lab, kind=kind, **{**defaults, **fields})


def make_variant(product, sph="-1.00", cyl="0", add="0", **fields):
    from apps.catalog.models import LensVariant

    return LensVariant.objects.create(lab=product.lab, product=product, sph=sph, cyl=cyl, add=add, **fields)


def stock_in(item, qty, unit_cost="1000.00", movement_type="purchase", user=None):
    """Posts an incoming movement for a product or a lens variant through the real service."""
    from django.db import transaction

    from apps.catalog.models import LensVariant
    from apps.inventory.services import StockLine, record_movement

    variant = item if isinstance(item, LensVariant) else None
    product = item.product if variant else item
    with transaction.atomic():
        movement = record_movement(
            lab=product.lab,
            line=StockLine(product=product, variant=variant, qty=qty, unit_cost=unit_cost),
            movement_type=movement_type,
            user=user,
        )
    item.refresh_from_db()
    return movement
