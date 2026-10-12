from rest_framework import serializers

from apps.catalog.models import LensVariant, Product
from apps.core.exceptions import APIError
from apps.core.viewsets import LabScopedPrimaryKeyRelatedField
from apps.patients.models import Patient, Prescription
from apps.patients.serializers import PrescriptionSerializer
from apps.sales.models import Invoice

from .models import Job, JobStatusLog


def _name(user):
    return (user.get_full_name() or user.username) if user else ""


class JobStatusLogSerializer(serializers.ModelSerializer):
    changed_by_name = serializers.SerializerMethodField()

    class Meta:
        model = JobStatusLog
        fields = ["id", "from_status", "to_status", "note", "changed_by", "changed_by_name", "created_at"]
        read_only_fields = fields

    def get_changed_by_name(self, obj):
        return _name(obj.changed_by)


class JobSerializer(serializers.ModelSerializer):
    """`status` is read-only here: use `POST jobs/{id}/status/` (validated transitions + log)."""

    patient = LabScopedPrimaryKeyRelatedField(queryset=Patient.objects.all())
    prescription = LabScopedPrimaryKeyRelatedField(queryset=Prescription.objects.all(), required=False, allow_null=True)
    invoice = LabScopedPrimaryKeyRelatedField(queryset=Invoice.objects.all(), required=False, allow_null=True)
    frame = LabScopedPrimaryKeyRelatedField(queryset=Product.objects.all(), required=False, allow_null=True)
    lens = LabScopedPrimaryKeyRelatedField(queryset=Product.objects.all(), required=False, allow_null=True)
    lens_od = LabScopedPrimaryKeyRelatedField(queryset=LensVariant.objects.all(), required=False, allow_null=True)
    lens_os = LabScopedPrimaryKeyRelatedField(queryset=LensVariant.objects.all(), required=False, allow_null=True)

    patient_name = serializers.CharField(source="patient.full_name", read_only=True)
    patient_phone = serializers.CharField(source="patient.phone", read_only=True)
    invoice_number = serializers.IntegerField(source="invoice.number", read_only=True, default=None)
    invoice_balance = serializers.DecimalField(
        source="invoice.balance", max_digits=14, decimal_places=2, read_only=True, default=None
    )
    frame_name = serializers.CharField(source="frame.name", read_only=True, default="")
    lens_name = serializers.CharField(source="lens.name", read_only=True, default="")
    lens_od_label = serializers.SerializerMethodField()
    lens_os_label = serializers.SerializerMethodField()
    prescription_detail = PrescriptionSerializer(source="prescription", read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)
    status_logs = JobStatusLogSerializer(many=True, read_only=True)
    supplier_orders = serializers.SerializerMethodField()
    created_by_name = serializers.SerializerMethodField()

    class Meta:
        model = Job
        fields = [
            "id", "number", "patient", "patient_name", "patient_phone", "prescription", "prescription_detail",
            "invoice", "invoice_number", "invoice_balance", "frame_source", "frame", "frame_name", "frame_notes",
            "lens", "lens_name", "lens_od", "lens_od_label", "lens_os", "lens_os_label", "lens_notes", "status",
            "promised_date", "is_overdue", "delivered_at", "notes", "status_logs", "supplier_orders", "created_by_name",
            "created_at", "updated_at",
        ]
        read_only_fields = ["id", "number", "status", "delivered_at", "created_at", "updated_at"]

    def get_lens_od_label(self, obj):
        return obj.lens_od.power_label if obj.lens_od_id else ""

    def get_lens_os_label(self, obj):
        return obj.lens_os.power_label if obj.lens_os_id else ""

    def get_supplier_orders(self, obj):
        """Rx orders placed for this job (no costs: those live on the order, cost-gated)."""
        return [
            {"id": o.id, "number": o.number, "status": o.status, "supplier_name": o.supplier.name,
             "expected_date": o.expected_date}
            for o in obj.supplier_orders.all()
        ]

    def get_created_by_name(self, obj):
        return _name(obj.created_by)

    def validate(self, attrs):
        job = self.instance
        if job is not None:
            if job.status in Job.FINAL:
                raise APIError("A delivered or cancelled job cannot be edited.", code="job_closed")
            if "patient" in attrs and attrs["patient"] != job.patient:
                raise APIError("The patient of a job cannot change.", code="patient_locked")

        def value(name):
            return attrs[name] if name in attrs else getattr(job, name, None)

        patient = value("patient")
        prescription = value("prescription")
        if prescription is not None and prescription.patient_id != patient.id:
            raise APIError("The prescription belongs to another patient.", code="prescription_mismatch")
        if prescription is not None and prescription.is_void and "prescription" in attrs:
            raise APIError("The prescription is voided.", code="record_void")

        invoice = value("invoice")
        if invoice is not None and "invoice" in attrs:
            if invoice.status == Invoice.Status.CANCELLED:
                raise APIError("The invoice is cancelled.", code="invoice_cancelled")
            if invoice.patient_id is not None and invoice.patient_id != patient.id:
                raise APIError("The invoice belongs to another patient.", code="invoice_mismatch")

        frame_source = value("frame_source") or Job.FrameSource.LAB
        frame = value("frame")
        if frame_source != Job.FrameSource.LAB:
            if frame is not None:
                raise APIError("No lab frame when the frame is the customer's own.", code="invalid_frame")
        elif frame is not None and frame.kind != Product.Kind.FRAME:
            raise APIError("The frame must be a frame product.", code="invalid_frame")

        lens = value("lens")
        lens_kinds = (Product.Kind.STOCK_LENS, Product.Kind.RX_LENS, Product.Kind.CONTACT_LENS)
        if lens is not None and lens.kind not in lens_kinds:
            raise APIError("The lens must be a lens product.", code="invalid_lens")
        for eye in ("lens_od", "lens_os"):
            variant = value(eye)
            if variant is not None and (lens is None or variant.product_id != lens.id):
                raise APIError("The lens power must belong to the chosen lens.", code="invalid_lens")
        return attrs


class JobStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=Job.Status.choices)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")
