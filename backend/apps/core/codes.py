"""Short human-typed codes (doctor ↔ lab link codes)."""

import secrets

LINK_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I


def generate_link_code():
    """8 unambiguous characters, shown in the app and typed by the other side."""
    return "".join(secrets.choice(LINK_CODE_ALPHABET) for _ in range(8))


def normalize_link_code(value):
    return "".join(ch for ch in (value or "") if ch.isalnum()).upper()
