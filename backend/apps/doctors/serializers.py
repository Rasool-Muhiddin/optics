from decimal import Decimal

from rest_framework import serializers
from rest_framework.exceptions import ErrorDetail

from apps.core.viewsets import LabScopedPrimaryKeyRelatedField
from apps.patients.models import Patient, Prescription
from apps.patients.rx import RxError, clean_rx

from .models import DoctorLabLink, DoctorProfile, Referral

# Rx keys a referral may carry (the lab sets rx_date / prescribed_by on accept).
REFERRAL_RX_FIELDS = [
    "od_sph", "od_cyl", "od_axis", "od_add", "od_prism", "od_base", "od_va",
    "os_sph", "os_cyl", "os_axis", "os_add", "os_prism", "os_base", "os_va",
    "pd_distance", "pd_near", "pd_od", "pd_os",
    "usage", "lens_design", "lens_index", "lens_coatings", "frame_notes", "notes",
]


def _name(user):
    return (user.get_full_name() or user.username) if user else ""


class DoctorProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = DoctorProfile
        fields = ["id", "full_name", "specialty", "clinic_name", "phone", "address", "link_code"]
        read_only_fields = fields


def doctor_session_payload(profile):
    user = profile.user
    return {
        "role": "doctor",
        "user": {
            "id": user.id, "username": user.username, "first_name": user.first_name,
            "last_name": user.last_name, "email": user.email,
        },
        "doctor": DoctorProfileSerializer(profile).data,
    }


# --- Doctor side ------------------------------------------------------------------------


class DoctorSideLinkSerializer(serializers.ModelSerializer):
    """What a doctor sees of a linked lab: its public contact details only."""

    lab_name = serializers.CharField(source="lab.name", read_only=True)
    lab_phone = serializers.CharField(source="lab.phone", read_only=True)
    lab_address = serializers.CharField(source="lab.address", read_only=True)

    class Meta:
        model = DoctorLabLink
        fields = [
            "id", "lab", "lab_name", "lab_phone", "lab_address", "status", "requested_by", "requested_at",
            "responded_at", "note",
        ]
        read_only_fields = fields


class LinkRequestSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=32)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


def _power():
    return serializers.DecimalField(max_digits=6, decimal_places=2, required=False, allow_null=True)


def _pd():
    return serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True)


class ReferralRxSerializer(serializers.Serializer):
    """The Rx inside a referral: same rules as a lab prescription (`clean_rx`), kept as entered."""

    od_sph, od_cyl, od_add, od_prism = _power(), _power(), _power(), _power()
    os_sph, os_cyl, os_add, os_prism = _power(), _power(), _power(), _power()
    od_axis = serializers.IntegerField(required=False, allow_null=True)
    os_axis = serializers.IntegerField(required=False, allow_null=True)
    od_base = serializers.ChoiceField(choices=["", *Prescription.Base.values], required=False, default="")
    os_base = serializers.ChoiceField(choices=["", *Prescription.Base.values], required=False, default="")
    od_va = serializers.CharField(max_length=20, required=False, allow_blank=True, default="")
    os_va = serializers.CharField(max_length=20, required=False, allow_blank=True, default="")
    pd_distance, pd_near, pd_od, pd_os = _pd(), _pd(), _pd(), _pd()
    usage = serializers.ChoiceField(choices=Prescription.Usage.values, required=False, default="distance")
    lens_design = serializers.CharField(max_length=20, required=False, allow_blank=True, default="")
    lens_index = serializers.CharField(max_length=5, required=False, allow_blank=True, default="")
    lens_coatings = serializers.ListField(child=serializers.CharField(), required=False, default=list)
    frame_notes = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")
    notes = serializers.CharField(required=False, allow_blank=True, default="")

    def validate(self, attrs):
        try:
            cleaned = clean_rx(attrs)
        except RxError as exc:
            raise serializers.ValidationError(
                {field: [ErrorDetail(message, code=code)] for field, (message, code) in exc.errors.items()}
            ) from None
        out = {f: cleaned.get(f) for f in REFERRAL_RX_FIELDS}
        # Stored as JSON: decimals as fixed strings, like the prescription API returns them.
        for field, value in out.items():
            if isinstance(value, Decimal):
                out[field] = f"{value:.1f}" if field.startswith("pd_") else f"{value:.2f}"
        return out


class DoctorReferralSerializer(serializers.ModelSerializer):
    """
    A doctor's referral. The doctor sees what they sent + status/timestamps and the lab's
    name — never the lab's patient file, exam, invoices or prices.
    """

    lab_name = serializers.CharField(source="lab.name", read_only=True)
    prescription = ReferralRxSerializer(source="prescription_data", required=False, allow_null=True)
    patient_age = serializers.IntegerField(min_value=0, max_value=130, required=False, allow_null=True)
    patient_gender = serializers.ChoiceField(choices=["", *Patient.Gender.values], required=False, default="")
    iop_od = serializers.DecimalField(
        max_digits=4, decimal_places=1, min_value=Decimal("0"), max_value=Decimal("80"), required=False, allow_null=True
    )
    iop_os = serializers.DecimalField(
        max_digits=4, decimal_places=1, min_value=Decimal("0"), max_value=Decimal("80"), required=False, allow_null=True
    )

    class Meta:
        model = Referral
        fields = [
            "id", "lab", "lab_name", "status", "patient_name", "patient_age", "patient_gender", "patient_phone",
            "exam_date", "chief_complaint", "diagnosis", "diagnosis_details", "va_od", "va_os", "iop_od", "iop_os",
            "prescription", "notes", "received_at", "accepted_at", "completed_at", "rejected_at", "reject_reason",
            "created_at",
        ]
        read_only_fields = [
            "id", "lab", "status", "received_at", "accepted_at", "completed_at", "rejected_at", "reject_reason",
            "created_at",
        ]

    def validate_patient_name(self, value):
        value = " ".join(value.split())
        if not value:
            raise serializers.ValidationError("Required.", code="required")
        return value

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["prescription"] = instance.prescription_data
        return data


class DoctorReferralCreateSerializer(DoctorReferralSerializer):
    """`lab` is chosen among the doctor's accepted links (checked in the service)."""

    lab = serializers.IntegerField()

    class Meta(DoctorReferralSerializer.Meta):
        read_only_fields = [f for f in DoctorReferralSerializer.Meta.read_only_fields if f != "lab"]


# --- Lab side ---------------------------------------------------------------------------


class LabSideLinkSerializer(serializers.ModelSerializer):
    """What a lab sees of a linked doctor."""

    doctor_name = serializers.CharField(source="doctor.full_name", read_only=True)
    doctor_specialty = serializers.CharField(source="doctor.specialty", read_only=True)
    doctor_clinic = serializers.CharField(source="doctor.clinic_name", read_only=True)
    doctor_phone = serializers.CharField(source="doctor.phone", read_only=True)

    class Meta:
        model = DoctorLabLink
        fields = [
            "id", "doctor", "doctor_name", "doctor_specialty", "doctor_clinic", "doctor_phone", "status",
            "requested_by", "requested_at", "responded_at", "note",
        ]
        read_only_fields = fields


class LabReferralSerializer(DoctorReferralSerializer):
    """The lab's inbox view: everything the doctor sent + where it landed in the lab."""

    doctor_name = serializers.CharField(source="doctor.full_name", read_only=True)
    doctor_clinic = serializers.CharField(source="doctor.clinic_name", read_only=True)
    doctor_phone = serializers.CharField(source="doctor.phone", read_only=True)
    patient_file_name = serializers.CharField(source="patient.full_name", read_only=True, default="")
    handled_by_name = serializers.SerializerMethodField()

    class Meta(DoctorReferralSerializer.Meta):
        fields = [
            *DoctorReferralSerializer.Meta.fields, "doctor", "doctor_name", "doctor_clinic", "doctor_phone",
            "patient", "patient_file_name", "exam", "handled_by_name",
        ]
        read_only_fields = fields

    def get_handled_by_name(self, obj):
        return _name(obj.handled_by)


class AcceptReferralSerializer(serializers.Serializer):
    """`patient` = an existing patient file to attach the exam to (else a new file is created)."""

    patient = LabScopedPrimaryKeyRelatedField(queryset=Patient.objects.all(), required=False, allow_null=True)
