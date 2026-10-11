"""
Shared optical-power rules (lens variants in P2, prescriptions in P3).

All powers are Decimals in 0.25 D steps. Cylinder is stored in minus-cyl convention.
"""

from decimal import Decimal, InvalidOperation

QUARTER = Decimal("0.25")

SPH_RANGE = (Decimal("-30"), Decimal("30"))
CYL_RANGE = (Decimal("-10"), Decimal("10"))
ADD_RANGE = (Decimal("0.50"), Decimal("4.00"))
AXIS_RANGE = (1, 180)


class PowerError(ValueError):
    """`code` is a stable machine code for the API (`invalid_sph`, `axis_required`…)."""

    def __init__(self, message, code):
        super().__init__(message)
        self.code = code


def to_decimal(value):
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def check_step(value, low, high, *, name, step=QUARTER):
    """Raises `PowerError(code=f"invalid_{name}")` unless low <= value <= high in `step` increments."""
    number = to_decimal(value)
    if number is None or not (low <= number <= high) or number % step != 0:
        raise PowerError(f"{name.upper()} must be between {low} and {high} in steps of {step}.", f"invalid_{name}")
    return number


def check_sph(value):
    return check_step(value, *SPH_RANGE, name="sph")


def check_cyl(value):
    return check_step(value, *CYL_RANGE, name="cyl")


def check_add(value):
    return check_step(value, *ADD_RANGE, name="add")


def check_axis(value):
    number = None if isinstance(value, bool) else to_decimal(value)
    if number is None or number != number.to_integral_value() or not AXIS_RANGE[0] <= number <= AXIS_RANGE[1]:
        raise PowerError("AXIS must be an integer between 1 and 180.", "invalid_axis")
    return int(number)


def transpose(sph, cyl, axis):
    """
    Plus-cyl ⇄ minus-cyl transposition: SPH' = SPH + CYL, CYL' = −CYL, AXIS' = AXIS ± 90
    (kept in 1..180). With CYL = 0 nothing changes (axis is dropped).
    """
    sph, cyl = Decimal(str(sph)), Decimal(str(cyl or 0))
    if cyl == 0:
        return sph, Decimal("0.00"), None
    new_axis = int(axis) + 90 if int(axis) <= 90 else int(axis) - 90
    return (sph + cyl).quantize(Decimal("0.01")), (-cyl).quantize(Decimal("0.01")), new_axis


def to_minus_cyl(sph, cyl, axis):
    """Returns the prescription in minus-cyl form (unchanged if CYL ≤ 0)."""
    if cyl is not None and Decimal(str(cyl)) > 0:
        return transpose(sph, cyl, axis)
    return sph, cyl, axis
