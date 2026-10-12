"""
Prescription validation (CLAUDE.md §5):
SPH −30..+30, CYL −10..+10, ADD +0.50..+4.00 (0.25 steps); AXIS 1..180 required iff CYL ≠ 0;
prism 0.25..20 needs a base; PD within human ranges.

The Rx is kept exactly as entered (plus-cyl stays plus-cyl); `Prescription.save()` keeps a
normalized minus-cyl copy (`od_mc_*` / `os_mc_*`) for internal use (stock matching, comparisons).
"""

from decimal import Decimal

from apps.catalog.attributes import LENS_COATINGS, LENS_DESIGNS, LENS_INDEXES
from apps.core.optics import PowerError, check_add, check_axis, check_cyl, check_sph, check_step, to_decimal

PRISM_RANGE = (Decimal("0.25"), Decimal("20"))
PD_RANGE = (Decimal("40"), Decimal("85"))
MONO_PD_RANGE = (Decimal("20"), Decimal("45"))
HALF = Decimal("0.5")


class RxError(Exception):
    """`errors` = {field: (message, code)}."""

    def __init__(self, errors):
        super().__init__("Invalid prescription.")
        self.errors = errors


def clean_rx(data):
    """Validates/normalizes the Rx fields present in `data` (a dict of the full Rx). Returns a new dict."""
    out = dict(data)
    errors = {}

    def run(field, func):
        try:
            return func()
        except PowerError as exc:
            errors[field] = (str(exc), exc.code)
            return None

    for eye in ("od", "os"):
        f = lambda name: f"{eye}_{name}"  # noqa: E731
        values = {name: out.get(f(name)) for name in ("sph", "cyl", "axis", "add", "prism", "base", "va")}
        any_power = any(values[n] not in (None, "") for n in ("sph", "cyl", "axis", "add", "prism"))
        if not any_power:
            for name in ("sph", "cyl", "axis", "add", "prism"):
                out[f(name)] = None
            out[f("base")] = out.get(f("base")) or ""
            continue
        if values["sph"] in (None, ""):
            errors[f("sph")] = ("SPH is required when the eye has a prescription.", "sph_required")
            continue
        sph = run(f("sph"), lambda: check_sph(values["sph"]))
        cyl = run(f("cyl"), lambda: check_cyl(values["cyl"])) if values["cyl"] not in (None, "") else Decimal("0")
        axis = None
        if cyl not in (None, Decimal("0")):
            if values["axis"] in (None, ""):
                errors[f("axis")] = ("AXIS is required when CYL is not zero.", "axis_required")
            else:
                axis = run(f("axis"), lambda: check_axis(values["axis"]))
        add = run(f("add"), lambda: check_add(values["add"])) if values["add"] not in (None, "", 0, "0") else None
        prism = None
        if values["prism"] not in (None, "", 0, "0"):
            prism = run(
                f("prism"), lambda: check_step(values["prism"], *PRISM_RANGE, name="prism")
            )
            if not values["base"]:
                errors[f("base")] = ("Prism needs a base direction.", "base_required")
        out[f("sph")] = sph
        out[f("cyl")] = None if cyl is None else (cyl or Decimal("0.00"))
        out[f("axis")] = axis
        out[f("add")] = add
        out[f("prism")] = prism
        out[f("base")] = values["base"] if prism else ""

    if not errors and out.get("od_sph") is None and out.get("os_sph") is None:
        errors["od_sph"] = ("At least one eye needs a prescription.", "rx_empty")

    for field, rng, step in (
        ("pd_distance", PD_RANGE, HALF),
        ("pd_near", PD_RANGE, HALF),
        ("pd_od", MONO_PD_RANGE, HALF),
        ("pd_os", MONO_PD_RANGE, HALF),
    ):
        if out.get(field) in (None, ""):
            out[field] = None
            continue
        value = to_decimal(out[field])
        if value is None or not rng[0] <= value <= rng[1] or value % step:
            errors[field] = (f"PD must be between {rng[0]} and {rng[1]} mm in 0.5 steps.", "invalid_pd")

    if out.get("lens_design") and out["lens_design"] not in LENS_DESIGNS:
        errors["lens_design"] = ("Unknown lens design.", "invalid_choice")
    if out.get("lens_index") and out["lens_index"] not in LENS_INDEXES:
        errors["lens_index"] = ("Unknown lens index.", "invalid_choice")
    coatings = out.get("lens_coatings") or []
    if not isinstance(coatings, list) or any(c not in LENS_COATINGS for c in coatings):
        errors["lens_coatings"] = ("Unknown coating.", "invalid_choice")
    else:
        out["lens_coatings"] = sorted(set(coatings), key=LENS_COATINGS.index)

    if errors:
        raise RxError(errors)
    return out
