"""
`/api/v1/reports/…` — read-only aggregates.

- `dashboard/`: any lab member (profit only with cost permission).
- Reports (`sales/`, `profit/`, `credit/`, `stock/`, `jobs/`, `suppliers/`): owner, or staff with
  `can_view_costs` (§4: reports are the owner's; staff see costs/profit only when permitted).
- `?export=csv` on any report returns a CSV file (UTF-8 with BOM, Arabic headers for Excel) and
  needs the plan feature `report_export`.
"""

import csv
import io

from django.http import HttpResponse
from rest_framework import exceptions
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.costs import request_sees_costs
from apps.core.permissions import LabAccess

from . import services
from .csv_labels import CSV_LABELS, VALUE_LABELS


class ReportAccess(LabAccess):
    def has_permission(self, request, view):
        if not super().has_permission(request, view):
            return False
        if not request.lab_user.sees_costs:
            raise exceptions.PermissionDenied(
                "Reports are for the owner and staff with the cost permission.", code="cost_permission_required"
            )
        return True


class DashboardView(APIView):
    """`GET /api/v1/reports/dashboard/` — today / this month / open work at a glance."""

    permission_classes = [LabAccess]

    def get(self, request):
        lab = request.lab
        return Response(services.dashboard(
            lab, sees_costs=request_sees_costs(request), has_referrals=lab.license.plan.has_feature("doctor_linking"),
        ))


def to_csv(name, report):
    """Main table of a report as CSV (Excel-friendly: BOM + Arabic headers and values)."""
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    columns = report["columns"]
    writer.writerow([CSV_LABELS.get(c, c) for c in columns])
    for row in report["rows"]:
        writer.writerow([VALUE_LABELS.get(row.get(c), row.get(c)) if c in ("kind", "status") else row.get(c)
                         for c in columns])
    totals = report.get("totals") or {}
    if totals:
        writer.writerow([])
        for key, value in totals.items():
            writer.writerow([CSV_LABELS.get(key, key), value])
    response = HttpResponse("﻿" + buffer.getvalue(), content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = f'attachment; filename="{name}.csv"'
    return response


class _ReportView(APIView):
    permission_classes = [ReportAccess]
    name = ""

    def build(self, request):
        raise NotImplementedError

    def get(self, request):
        report = self.build(request)
        if request.query_params.get("export") == "csv":
            if not request.lab.license.plan.has_feature("report_export"):
                raise exceptions.PermissionDenied(
                    "Feature 'report_export' is not included in the lab's plan.", code="feature_not_in_plan"
                )
            return to_csv(self.name, report)
        return Response(report)


class SalesReportView(_ReportView):
    """`?date_from&date_to&group=day|month` — invoices (not cancelled), payments by method, top products."""

    name = "sales"

    def build(self, request):
        return services.sales_report(request.lab, request.query_params)


class ProfitReportView(_ReportView):
    """Revenue − cost (weighted average / supplier / reference cost snapshots) per period and per kind."""

    name = "profit"

    def build(self, request):
        return services.profit_report(request.lab, request.query_params)


class CreditReportView(_ReportView):
    """Open credit balances per patient with ageing by the oldest unpaid invoice."""

    name = "credit"

    def build(self, request):
        return services.credit_report(request.lab, request.query_params)


class StockReportView(_ReportView):
    """Low stock (`all=true` for every stock item) + stock value by kind."""

    name = "stock"

    def build(self, request):
        return services.stock_report(request.lab, request.query_params, sees_costs=request_sees_costs(request))


class JobsReportView(_ReportView):
    """Overdue jobs + counts per status."""

    name = "jobs"

    def build(self, request):
        return services.jobs_report(request.lab, request.query_params)


class SuppliersReportView(_ReportView):
    """What the lab owes each supplier (`all=true` includes suppliers with nothing open)."""

    name = "suppliers"

    def build(self, request):
        return services.suppliers_report(request.lab, request.query_params)
