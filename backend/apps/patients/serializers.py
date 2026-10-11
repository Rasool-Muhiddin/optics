from decimal import Decimal

from django.db import transaction
from rest_framework import serializers
from rest_framework.exceptions import ErrorDetail

from apps.core.viewsets import LabScopedPrimaryKeyRelatedField

from .models import EyeExam, Patient, Prescription
from .rx import RxError, clean_rx


def _user_name(user):
    return (user.get_full_name() or user.username) if user else ""


class PatientSerializer(serializers.ModelSerializer):
    """`age` may be sent instead of `birth_date` (stored as an estimated birth date)."""

    age = serializers.IntegerField(min_value=0, max_value=130, required=False, allow_null=True)
    last_exam_date = serializers.DateField(read_only=True, allow_null=True, required=False)

    class Meta:
        model = Patient
        fields = [
            "id", "full_name", "birth_date", "birth_date_estimated", "age", "gender", "phone", "address",
            "notes", "status", "is_archived", "last_exam_date", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "birth_date_estimated", "created_at", "updated_at"]

    def validate_full_name(self, value):
        value = " ".join(value.split())
        if not value:
            raise serializers.ValidationError("Required.", code="required")
        return value

    def validate(self, attrs):
        age = attrs.pop("age", None)
        if attrs.get("birth_date"):
            attrs["birth_date_estimated"] = False
        elif age is not None:
            current = self.instance.age if self.instance else None
            if age != current:
                attrs["birth_date"] = Patient.birth_date_for_age(age)
                attrs["birth_date_estimated"] = True
        return attrs

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["age"] = instance.age
        return data


PRESCRIPTION_FIELDS = [
    "rx_date", "prescribed_by",
    "od_sph", "od_cyl", "od_axis", "od_add", "od_prism", "od_base", "od_va",
    "os_sph", "os_cyl", "os_axis", "os_add", "os_prism", "os_base", "os_va",
    "pd_distance", "pd_near", "pd_od", "pd_os",
    "usage", "lens_design", "lens_index", "lens_coatings", "frame_notes", "notes",
]
_RX_VALUE_FIELDS = [f for f in PRESCRIPTION_FIELDS if f not in ("rx_date", "prescribed_by", "usage", "notes", "frame_notes")]


class PrescriptionSerializer(serializers.ModelSerializer):
    patient = LabScopedPrimaryKeyRelatedField(queryset=Patient.objects.all())
    patient_name = serializers.CharField(source="patient.full_name", read_only=True)
    exam = serializers.PrimaryKeyRelatedField(read_only=True)
    created_by_name = serializers.SerializerMethodField()

    # Powers are validated by `clean_rx` (steps, ranges, transposition); accept them loosely here.
    od_sph = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    od_cyl = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    od_add = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    od_prism = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    od_axis = serializers.IntegerField(required=False, allow_null=True)
    os_sph = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    os_cyl = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    os_add = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    os_prism = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)
    os_axis = serializers.IntegerField(required=False, allow_null=True)
    pd_distance = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True)
    pd_near = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True)
    pd_od = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True)
    pd_os = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True)
    lens_coatings = serializers.ListField(child=serializers.CharField(), required=False)

    class Meta:
        model = Prescription
        fields = [
            "id", "patient", "patient_name", "exam", *PRESCRIPTION_FIELDS,
            "is_void", "void_reason", "voided_at", "created_by", "created_by_name", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "exam", "is_void", "void_reason", "voided_at", "created_by", "created_at", "updated_at"]

    def get_created_by_name(self, obj):
        return _user_name(obj.created_by)

    def validate(self, attrs):
        if self.instance is not None and self.instance.is_void:
            from apps.core.exceptions import APIError

            raise APIError("A voided record cannot be edited.", code="record_void")
        merged = {f: getattr(self.instance, f) for f in _RX_VALUE_FIELDS} if self.instance else {}
        merged.update({f: attrs[f] for f in _RX_VALUE_FIELDS if f in attrs})
        try:
            cleaned = clean_rx(merged)
        except RxError as exc:
            raise serializers.ValidationError(
                {field: [ErrorDetail(message, code=code)] for field, (message, code) in exc.errors.items()}
            ) from None
        attrs.update({f: cleaned[f] for f in _RX_VALUE_FIELDS if f in cleaned})
        return attrs


class NestedPrescriptionSerializer(PrescriptionSerializer):
    """Rx sent inside an exam: `patient` comes from the exam. Always send the complete Rx."""

    patient = serializers.PrimaryKeyRelatedField(read_only=True)


class EyeExamSerializer(serializers.ModelSerializer):
    patient = LabScopedPrimaryKeyRelatedField(queryset=Patient.objects.all())
    patient_name = serializers.CharField(source="patient.full_name", read_only=True)
    examined_by_name = serializers.SerializerMethodField()
    prescription = NestedPrescriptionSerializer(required=False, allow_null=True)
    iop_od = serializers.DecimalField(
        max_digits=4, decimal_places=1, min_value=Decimal("0"), max_value=Decimal("80"), required=False, allow_null=True
    )
    iop_os = serializers.DecimalField(
        max_digits=4, decimal_places=1, min_value=Decimal("0"), max_value=Decimal("80"), required=False, allow_null=True
    )

    class Meta:
        model = EyeExam
        fields = [
            "id", "patient", "patient_name", "exam_date", "examined_by", "examined_by_name", "examiner_name",
            "chief_complaint", "diagnosis", "diagnosis_details", "va_od", "va_os", "iop_od", "iop_os", "notes",
            "prescription", "is_void", "void_reason", "voided_at", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "examined_by", "is_void", "void_reason", "voided_at", "created_at", "updated_at"]

    def get_examined_by_name(self, obj):
        return obj.examiner_name or _user_name(obj.examined_by)

    def validate(self, attrs):
        if self.instance is not None:
            if self.instance.is_void:
                from apps.core.exceptions import APIError

                raise APIError("A voided record cannot be edited.", code="record_void")
            if "patient" in attrs and attrs["patient"] != self.instance.patient:
                from apps.core.exceptions import APIError

                raise APIError("The patient of an exam cannot change.", code="patient_locked")
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        rx_data = validated_data.pop("prescription", None)
        exam = EyeExam.objects.create(**validated_data)
        if rx_data:
            Prescription.objects.create(
                lab=exam.lab, patient=exam.patient, exam=exam, created_by=exam.created_by,
                **{"rx_date": exam.exam_date, "prescribed_by": exam.examiner_name, **rx_data},
            )
        return exam

    @transaction.atomic
    def update(self, instance, validated_data):
        rx_data = validated_data.pop("prescription", None)
        exam = super().update(instance, validated_data)
        if rx_data is not None:
            existing = getattr(exam, "prescription", None)
            if existing is None:
                Prescription.objects.create(
                    lab=exam.lab, patient=exam.patient, exam=exam,
                    created_by=self.context["request"].user, **{"rx_date": exam.exam_date, **rx_data},
                )
            else:
                for field, value in rx_data.items():
                    setattr(existing, field, value)
                existing.save()
        return exam


class VoidSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=300)


class TransposeSerializer(serializers.Serializer):
    sph = serializers.DecimalField(max_digits=5, decimal_places=2)
    cyl = serializers.DecimalField(max_digits=5, decimal_places=2)
    axis = serializers.IntegerField(required=False, allow_null=True)
