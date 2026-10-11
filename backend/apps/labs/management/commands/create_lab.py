"""
`python manage.py create_lab "Al-Noor Optics" owner1 <password> [--plan basic]`

Creates a lab with a license, plus its owner, and prints the activation code. Handy for
local development; in production Tera can do the same in Django Admin.
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.billing.models import License, Plan
from apps.labs.models import Lab, LabUser


class Command(BaseCommand):
    help = "Create a lab + license + owner user and print the desktop activation code."

    def add_arguments(self, parser):
        parser.add_argument("name")
        parser.add_argument("owner_username")
        parser.add_argument("owner_password")
        parser.add_argument("--plan", default="basic", help="Plan code (created if missing).")

    @transaction.atomic
    def handle(self, name, owner_username, owner_password, plan, **options):
        User = get_user_model()
        if User.objects.filter(username__iexact=owner_username).exists():
            raise CommandError(f"Username '{owner_username}' already exists.")
        plan_obj, _ = Plan.objects.get_or_create(code=plan, defaults={"name": plan.title()})
        lab = Lab.objects.create(name=name)
        License.objects.create(lab=lab, plan=plan_obj)
        user = User.objects.create_user(username=owner_username, password=owner_password)
        LabUser.objects.create(lab=lab, user=user, role=LabUser.Role.OWNER)
        self.stdout.write(self.style.SUCCESS(f"Lab '{lab.name}' created (plan: {plan_obj.name})."))
        self.stdout.write(f"Activation code: {lab.activation_code}")
