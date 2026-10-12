from django.db import transaction
from django.utils import timezone

from apps.core.exceptions import APIError
from apps.patients.models import Patient

from .models import Job, JobCounter, JobStatusLog


def _advance_patient(patient, to_status):
    order = [s for s, _ in Patient.Status.choices]
    if order.index(to_status) > order.index(patient.status):
        patient.status = to_status
        patient.save(update_fields=["status", "updated_at"])


def next_job_number(lab):
    counter, _ = JobCounter.objects.select_for_update().get_or_create(lab=lab)
    counter.last_number += 1
    counter.save(update_fields=["last_number"])
    return counter.last_number


@transaction.atomic
def create_job(*, lab, user, data):
    job = Job.objects.create(lab=lab, number=next_job_number(lab), created_by=user, **data)
    JobStatusLog.objects.create(lab=lab, job=job, from_status="", to_status=job.status, changed_by=user)
    _advance_patient(job.patient, Patient.Status.IN_JOB)
    return job


@transaction.atomic
def change_status(*, job, to_status, user, note=""):
    job = Job.objects.select_for_update().get(pk=job.pk)
    if to_status == job.status:
        raise APIError("The job already has this status.", code="invalid_transition")
    if to_status not in Job.TRANSITIONS[job.status]:
        raise APIError(f"Cannot move a job from {job.status} to {to_status}.", code="invalid_transition")
    JobStatusLog.objects.create(
        lab=job.lab, job=job, from_status=job.status, to_status=to_status, note=note, changed_by=user
    )
    job.status = to_status
    job.delivered_at = timezone.now() if to_status == Job.Status.DELIVERED else None
    job.save(update_fields=["status", "delivered_at", "updated_at"])
    if to_status == Job.Status.DELIVERED:
        _advance_patient(job.patient, Patient.Status.DELIVERED)
    return job
