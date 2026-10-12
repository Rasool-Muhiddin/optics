from rest_framework.routers import SimpleRouter

from .views import StockMovementViewSet

router = SimpleRouter()
router.register("movements", StockMovementViewSet, basename="stock-movement")

urlpatterns = router.urls
