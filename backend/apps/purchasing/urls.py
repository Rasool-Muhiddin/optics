from rest_framework.routers import SimpleRouter

from .views import SupplierOrderViewSet, SupplierPaymentViewSet, SupplierViewSet

router = SimpleRouter()
router.register("suppliers", SupplierViewSet, basename="supplier")
router.register("orders", SupplierOrderViewSet, basename="supplier-order")
router.register("payments", SupplierPaymentViewSet, basename="supplier-payment")

urlpatterns = router.urls
