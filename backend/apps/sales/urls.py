from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import CheckoutPreviewView, CheckoutView, CreditCustomersView, InvoiceViewSet, PayCustomerView, PaymentViewSet

router = SimpleRouter()
router.register("invoices", InvoiceViewSet, basename="invoice")
router.register("payments", PaymentViewSet, basename="payment")

urlpatterns = [
    path("checkout/", CheckoutView.as_view(), name="checkout"),
    path("checkout/preview/", CheckoutPreviewView.as_view(), name="checkout-preview"),
    path("credit-customers/", CreditCustomersView.as_view(), name="credit-customers"),
    path("credit-customers/<int:patient_id>/pay/", PayCustomerView.as_view(), name="credit-customer-pay"),
    *router.urls,
]
