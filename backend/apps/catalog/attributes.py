"""
Kind-specific product details, stored in `Product.attributes` (JSON) and validated here.

To add a field: add it to the kind's schema below (and to the Flutter form). Unknown keys
are rejected so the data stays clean.
"""

import re
from decimal import Decimal, InvalidOperation

LENS_INDEXES = ["1.50", "1.53", "1.56", "1.59", "1.60", "1.67", "1.74"]
LENS_DESIGNS = ["single_vision", "bifocal", "progressive", "office"]
LENS_COATINGS = ["ar", "blue_cut", "photochromic", "hard_coat", "uv", "polarized", "hydrophobic", "mirror", "tint"]
FRAME_GENDERS = ["men", "women", "unisex", "kids"]
FRAME_TYPES = ["full_rim", "semi_rimless", "rimless"]
CONTACT_REPLACEMENTS = ["daily", "biweekly", "monthly", "quarterly", "yearly"]
FRAME_SIZE_RE = re.compile(r"^\d{2}-\d{1,2}-\d{3}$")  # eye-bridge-temple, e.g. 52-18-140


class AttributeError_(ValueError):
    def __init__(self, field, message):
        super().__init__(message)
        self.field = field


def _text(max_length=100):
    def check(value):
        if not isinstance(value, str) or len(value) > max_length:
            raise ValueError(f"Text up to {max_length} characters.")
        return value.strip()

    return check


def _choice(options):
    def check(value):
        if value not in options:
            raise ValueError(f"One of: {', '.join(options)}.")
        return value

    return check


def _multi(options):
    def check(value):
        if not isinstance(value, list) or any(item not in options for item in value):
            raise ValueError(f"List of: {', '.join(options)}.")
        return sorted(set(value), key=options.index)

    return check


def _number(low, high, decimals=2):
    def check(value):
        try:
            number = Decimal(str(value))
        except (InvalidOperation, ValueError):
            raise ValueError("A number.") from None
        if isinstance(value, bool) or not low <= number <= high:
            raise ValueError(f"Between {low} and {high}.")
        return str(number.quantize(Decimal(1).scaleb(-decimals)))

    return check


def _frame_size(value):
    if not isinstance(value, str) or not FRAME_SIZE_RE.match(value.strip()):
        raise ValueError("Format eye-bridge-temple, e.g. 52-18-140.")
    return value.strip()


_LENS = {
    "material": _text(),
    "index": _choice(LENS_INDEXES),
    "design": _choice(LENS_DESIGNS),
    "coatings": _multi(LENS_COATINGS),
    "diameter": _number(40, 90, 0),
}

SCHEMAS = {
    "frame": {
        "model": _text(),
        "color": _text(),
        "size": _frame_size,
        "material": _text(),
        "gender": _choice(FRAME_GENDERS),
        "shape": _text(),
        "frame_type": _choice(FRAME_TYPES),
    },
    "stock_lens": _LENS,
    "rx_lens": _LENS,
    "contact_lens": {
        "replacement": _choice(CONTACT_REPLACEMENTS),
        "base_curve": _number(7, 10),
        "diameter": _number(12, 16, 1),
        "material": _text(),
        "color": _text(),
        "pack_size": _number(1, 365, 0),
    },
    "accessory": {"material": _text(), "color": _text()},
    "solution": {"volume_ml": _number(1, 5000, 0)},
    "service": {},
}


def clean_attributes(kind, attributes):
    """Returns the cleaned dict or raises `AttributeError_(field, message)`."""
    if attributes in (None, ""):
        return {}
    if not isinstance(attributes, dict):
        raise AttributeError_("attributes", "Must be an object.")
    schema = SCHEMAS.get(kind, {})
    cleaned = {}
    for key, value in attributes.items():
        if key not in schema:
            raise AttributeError_(key, f"Unknown attribute for {kind}.")
        if value in (None, "", []):
            continue
        try:
            cleaned[key] = schema[key](value)
        except ValueError as exc:
            raise AttributeError_(key, str(exc)) from None
    return cleaned
