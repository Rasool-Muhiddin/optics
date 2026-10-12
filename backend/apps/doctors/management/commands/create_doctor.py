"""
`python manage.py create_doctor "د. سامر علي" doctor1 <password> [--clinic "..."] [--specialty "..."]`

Creates a doctor account (no lab) and prints its link code. Tera can do the same in Django Admin.
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.doctors.models import DoctorProfile


class Command(BaseCommand):
    help = "Create a doctor account and print the doctor's link code."

    def add_arguments(self, parser):
        parser.add_argument("full_name")
        parser.add_argument("username")
        parser.add_argument("password")
        parser.add_argument("--clinic", default="")
        parser.add_argument("--specialty", default="")

    @transaction.atomic
    def handle(self, full_name, username, password, clinic, specialty, **options):
        User = get_user_model()
        if User.objects.filter(username__iexact=username).exists():
            raise CommandError(f"Username '{username}' already exists.")
        user = User.objects.create_user(username=username, password=password)
        doctor = DoctorProfile.objects.create(user=user, full_name=full_name, clinic_name=clinic, specialty=specialty)
        self.stdout.write(self.style.SUCCESS(f"Doctor '{doctor.full_name}' created."))
        self.stdout.write(f"Doctor link code: {doctor.link_code}")
