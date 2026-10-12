from django.urls import path

from .views import (
    CreditReportView, DashboardView, JobsReportView, ProfitReportView, SalesReportView, StockReportView,
    SuppliersReportView,
)

urlpatterns = [
    path("dashboard/", DashboardView.as_view(), name="dashboard"),
    path("sales/", SalesReportView.as_view(), name="report-sales"),
    path("profit/", ProfitReportView.as_view(), name="report-profit"),
    path("credit/", CreditReportView.as_view(), name="report-credit"),
    path("stock/", StockReportView.as_view(), name="report-stock"),
    path("jobs/", JobsReportView.as_view(), name="report-jobs"),
    path("suppliers/", SuppliersReportView.as_view(), name="report-suppliers"),
]
