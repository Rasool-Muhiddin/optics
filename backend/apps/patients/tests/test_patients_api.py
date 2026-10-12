import datetime
from decimal import Decimal

from django.utils import timezone

from apps.core.testing import LabAPITestCase, make_lab, make_member, make_patient, make_rx
from apps.labs.models import LabUser
from apps.patients.models import EyeExam, Patient, Prescription

PATIENTS = "/api/v1/patients/"
EXAMS = "/api/v1/patients/exams/"
RX = "/api/v1/patients/prescriptions/"


class PatientBase(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab()
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.login_as(self.staff)


class PatientTests(PatientBase):
    def test_staff_creates_patient_with_age(self):
        response = self.client.post(PATIENTS, {"full_name": "  علي   حسن ", "age": 40, "gender": "male", "phone": "0770"})
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual((body["full_name"], body["age"], body["birth_date_estimated"]), ("علي حسن", 40, True))
        self.assertEqual(body["status"], "new")
        self.assertEqual(Patient.objects.get().created_by, self.staff.user)

    def test_birth_date_wins_over_age(self):
        dob = (timezone.localdate() - datetime.timedelta(days=365 * 30 + 10)).isoformat()
        body = self.client.post(PATIENTS, {"full_name": "x", "birth_date": dob, "age": 5}).json()
        self.assertEqual((body["age"], body["birth_date_estimated"]), (30, False))

    def test_search_filter_and_last_exam(self):
        a = make_patient(self.lab, full_name="Zainab", phone="07801112222")
        make_patient(self.lab, full_name="Omar", status="delivered")
        EyeExam.objects.create(lab=self.lab, patient=a, exam_date=datetime.date(2026, 1, 5))
        EyeExam.objects.create(lab=self.lab, patient=a, exam_date=datetime.date(2026, 3, 5), is_void=True)
        rows = self.client.get(PATIENTS, {"search": "1112"}).json()["results"]
        self.assertEqual([r["full_name"] for r in rows], ["Zainab"])
        self.assertEqual(rows[0]["last_exam_date"], "2026-01-05")
        self.assertEqual(self.client.get(PATIENTS, {"status": "delivered"}).json()["count"], 1)

    def test_no_delete(self):
        patient = make_patient(self.lab)
        self.assertEqual(self.client.delete(f"{PATIENTS}{patient.id}/").status_code, 405)

    def test_name_required(self):
        self.assertEqual(self.client.post(PATIENTS, {"full_name": "  "}).status_code, 400)


class ExamTests(PatientBase):
    def setUp(self):
        super().setUp()
        self.patient = make_patient(self.lab)

    def _exam(self, **extra):
        payload = {
            "patient": self.patient.id, "diagnosis": "Myopia", "va_od": "6/12", "va_os": "6/9", "iop_od": "15",
            "prescription": {
                "od_sph": "-2.25", "od_cyl": "-0.50", "od_axis": 170, "os_sph": "-2.00",
                "pd_distance": "62", "usage": "distance", "lens_coatings": ["ar"],
            },
            **extra,
        }
        return self.client.post(EXAMS, payload)

    def test_exam_with_nested_rx(self):
        response = self._exam()
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["prescription"]["od_axis"], 170)
        self.assertEqual(body["prescription"]["patient"], self.patient.id)
        self.assertEqual(body["examined_by_name"], self.staff.user.username)
        rx = Prescription.objects.get()
        self.assertEqual((rx.exam_id, rx.created_by, rx.rx_date), (body["id"], self.staff.user, timezone.localdate()))
        self.patient.refresh_from_db()
        self.assertEqual(self.patient.status, "exam_done")

    def test_invalid_rx_rejects_whole_exam_with_codes(self):
        response = self._exam(prescription={"od_sph": "-2.10", "od_cyl": "-1"})
        self.assertEqual(response.status_code, 400)
        body = response.json()
        self.assertEqual(body["code"], "validation_error")
        self.assertEqual(body["error_codes"]["prescription"]["od_sph"], ["invalid_sph"])
        self.assertFalse(EyeExam.objects.exists())

    def test_exam_without_rx_and_external_examiner(self):
        response = self.client.post(EXAMS, {"patient": self.patient.id, "examiner_name": "د. سامر"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertIsNone(response.json()["prescription"])
        self.assertEqual(response.json()["examined_by_name"], "د. سامر")

    def test_update_exam_and_rx(self):
        exam_id = self._exam().json()["id"]
        response = self.client.patch(f"{EXAMS}{exam_id}/", {
            "diagnosis": "Myopic astigmatism",
            "prescription": {"od_sph": "-2.50", "od_cyl": "+0.50", "od_axis": 80, "os_sph": "-2.00"},
        })
        self.assertEqual(response.status_code, 200, response.content)
        rx = Prescription.objects.get()
        # Stored and returned exactly as entered…
        self.assertEqual((str(rx.od_sph), str(rx.od_cyl), rx.od_axis), ("-2.50", "0.50", 80))
        body = response.json()["prescription"]
        self.assertEqual((body["od_sph"], body["od_cyl"], body["od_axis"]), ("-2.50", "0.50", 80))
        # …with a normalized minus-cyl copy for internal use only (not in the API).
        self.assertEqual(rx.minus_cyl("od"), (Decimal("-2.00"), Decimal("-0.50"), 170))
        self.assertEqual(rx.minus_cyl("os"), (Decimal("-2.00"), Decimal("0.00"), None))
        self.assertNotIn("od_mc_sph", body)

    def test_void_by_author_and_owner_only(self):
        exam_id = self._exam().json()["id"]
        other_staff = make_member(self.lab)
        self.login_as(other_staff)
        response = self.client.post(f"{EXAMS}{exam_id}/void/", {"reason": "duplicate"})
        self.assertEqual(response.json()["code"], "owner_required")
        self.login_as(self.owner)
        response = self.client.post(f"{EXAMS}{exam_id}/void/", {"reason": "duplicate"})
        self.assertTrue(response.json()["is_void"])
        self.assertTrue(Prescription.objects.get().is_void)
        self.assertEqual(self.client.patch(f"{EXAMS}{exam_id}/", {"notes": "x"}).json()["code"], "record_void")
        self.assertEqual(self.client.post(f"{EXAMS}{exam_id}/void/", {"reason": "x"}).json()["code"], "record_void")

    def test_patient_of_exam_cannot_change(self):
        exam_id = self._exam().json()["id"]
        other = make_patient(self.lab)
        response = self.client.patch(f"{EXAMS}{exam_id}/", {"patient": other.id})
        self.assertEqual(response.json()["code"], "patient_locked")

    def test_history_filters(self):
        self._exam()
        make_rx(self.patient)
        make_rx(make_patient(self.lab))
        self.assertEqual(self.client.get(EXAMS, {"patient": self.patient.id}).json()["count"], 1)
        self.assertEqual(self.client.get(RX, {"patient": self.patient.id}).json()["count"], 2)


class StandaloneRxTests(PatientBase):
    def test_create_standalone_rx(self):
        patient = make_patient(self.lab)
        response = self.client.post(RX, {"patient": patient.id, "os_sph": "+1.75", "os_add": "2.25", "usage": "near",
                                         "prescribed_by": "Other clinic"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertIsNone(response.json()["exam"])
        self.assertIsNone(response.json()["od_sph"])

    def test_partial_update_revalidates_with_existing_values(self):
        rx = make_rx(make_patient(self.lab), od_cyl="-1.00", od_axis=90)
        response = self.client.patch(f"{RX}{rx.id}/", {"od_axis": None})
        self.assertEqual(response.json()["error_codes"]["od_axis"], ["axis_required"])
        response = self.client.patch(f"{RX}{rx.id}/", {"od_cyl": "0"})
        self.assertEqual(response.status_code, 200)
        rx.refresh_from_db()
        self.assertIsNone(rx.od_axis)
        self.assertEqual(rx.minus_cyl("od"), (Decimal("-1.00"), Decimal("0.00"), None))

    def test_minus_copy_follows_edits(self):
        rx = make_rx(make_patient(self.lab), od_sph="+1.00", od_cyl="+1.50", od_axis=30, os_sph=None)
        self.assertEqual(rx.minus_cyl("od"), (Decimal("2.50"), Decimal("-1.50"), 120))
        self.assertIsNone(rx.minus_cyl("os"))
        response = self.client.patch(f"{RX}{rx.id}/", {"od_cyl": "-0.75", "od_axis": 45})
        self.assertEqual(response.status_code, 200, response.content)
        rx.refresh_from_db()
        self.assertEqual(rx.minus_cyl("od"), (Decimal("1.00"), Decimal("-0.75"), 45))

    def test_transpose_helper(self):
        response = self.client.post("/api/v1/patients/transpose/", {"sph": "-1.00", "cyl": "+2.00", "axis": 90})
        self.assertEqual(response.json(), {"sph": "1.00", "cyl": "-2.00", "axis": 180})
        bad = self.client.post("/api/v1/patients/transpose/", {"sph": "-1.10", "cyl": "1", "axis": 90})
        self.assertEqual(bad.json()["code"], "invalid_sph")


class PatientIsolationTests(PatientBase):
    def test_lab_isolation(self):
        other_lab = make_lab()
        other = make_patient(other_lab, full_name="Secret")
        other_rx = make_rx(other)
        other_exam = EyeExam.objects.create(lab=other_lab, patient=other)
        self.assertEqual(self.client.get(PATIENTS, {"search": "Secret"}).json()["count"], 0)
        for url in (f"{PATIENTS}{other.id}/", f"{EXAMS}{other_exam.id}/", f"{RX}{other_rx.id}/"):
            self.assertEqual(self.client.get(url).status_code, 404, url)
        response = self.client.post(EXAMS, {"patient": other.id})
        self.assertIn("patient", response.json()["errors"])
        response = self.client.post(RX, {"patient": other.id, "od_sph": "0"})
        self.assertIn("patient", response.json()["errors"])
        self.assertEqual(self.client.post(f"{EXAMS}{other_exam.id}/void/", {"reason": "x"}).status_code, 404)

    def test_anonymous(self):
        self.client.credentials()
        self.assertEqual(self.client.get(PATIENTS).status_code, 401)
