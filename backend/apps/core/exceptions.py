"""
Uniform API error format: `{"detail": "...", "code": "..."}`.

Validation errors additionally carry `errors` with the per-field details. User-facing
(Arabic) messages are produced by the Flutter app from `code`, never here.
"""

from rest_framework import exceptions, status
from rest_framework.views import exception_handler


class APIError(exceptions.APIException):
    """Raise for business-rule failures: `raise APIError("Stock too low", code="insufficient_stock")`."""

    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = "Request could not be processed."
    default_code = "error"


def _first_code(codes):
    if isinstance(codes, dict):
        for value in codes.values():
            return _first_code(value)
    if isinstance(codes, list):
        return _first_code(codes[0]) if codes else None
    return codes


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is None:
        return None

    if isinstance(exc, exceptions.ValidationError):
        detail = exc.detail
        if isinstance(detail, dict) or (isinstance(detail, list) and len(detail) != 1):
            response.data = {
                "detail": "Validation failed.",
                "code": "validation_error",
                "errors": response.data,
                # Same shape as `errors`, with stable codes instead of English messages.
                "error_codes": exc.get_codes(),
            }
            return response
        message = detail[0] if isinstance(detail, list) else detail
        response.data = {"detail": str(message), "code": getattr(message, "code", "invalid")}
        return response

    if isinstance(exc, exceptions.APIException):
        detail = exc.detail
        code = _first_code(exc.get_codes()) or "error"
        message = detail if isinstance(detail, str) else str(detail)
        response.data = {"detail": str(message), "code": str(code)}
    return response
