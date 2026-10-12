"""
Read-only aggregates for the dashboard and reports. Every query is filtered by the lab.

A report is `{"columns": [keys], "rows": [dicts], "totals": dict, ...extra}` so the desktop
can render any report as a table and the same rows can be exported as CSV.
"""

import datetime
from decimal import Decimal

from django.db.models import Count, DecimalField, ExpressionWrapper, F, Min, Q, Sum, Value
from django.db.models.functions import Coalesce, TruncDay, TruncMonth
from django.utils import timezone

from apps.catalog.models import Product
from apps.jobs.models import Job
from apps.purchasing.models import Supplier, SupplierOrder
from apps.sales.models import Invoice, InvoiceLine, Payment

ZERO = Decimal("0.00")
MONEY = DecimalField(max_digits=16, decimal_places=2)


def _money(value):
    return f"{(value or ZERO):.2f}"


def _sum(field, **kwargs):
    return Coalesce(Sum(field, **kwargs), Value(ZERO), output_field=MONEY)


def date_range(params, default_days=None):
    """`date_from` / `date_to` (inclusive, YYYY-MM-DD); default = this month so far."""
    today = timezone.localdate()

    def parse(name):
        raw = params.get(name)
        try:
            return datetime.date.fromisoformat(raw) if raw else None
        except ValueError:
            return None

    start = parse("date_from") or (
        today - datetime.timedelta(days=default_days) if default_days else today.replace(day=1)
    )
    end = parse("date_to") or today
    if end < start:
        start, end = end, start
    return start, end


def _valid_invoices(lab, start, end):
    return Invoice.objects.filter(lab=lab, created_at__date__gte=start, created_at__date__lte=end).exclude(
        status=Invoice.Status.CANCELLED
    )


def _trunc(group):
    return TruncMonth("created_at") if group == "month" else TruncDay("created_at")


def _period(value, group):
    if value is None:
        return ""
    value = timezone.localtime(value) if isinstance(value, datetime.datetime) and timezone.is_aware(value) else value
    return value.strftime("%Y-%m" if group == "month" else "%Y-%m-%d")


def _local_date(value):
    if isinstance(value, datetime.datetime):
        return (timezone.localtime(value) if timezone.is_aware(value) else value).date()
    return value


# --- Dashboard ----------------------------------------------------------------------


def dashboard(lab, *, sees_costs, has_referrals):
    today = timezone.localdate()
    month_start = today.replace(day=1)
    today_inv = _valid_invoices(lab, today, today).aggregate(n=Count("id"), total=_sum("total"))
    month_inv = _valid_invoices(lab, month_start, today).aggregate(
        n=Count("id"), total=_sum("total"), cost=_sum("cost_total")
    )
    collected = Payment.objects.filter(lab=lab, is_void=False, paid_at__date=today).aggregate(t=_sum("amount"))["t"]
    credit = (
        Invoice.objects.filter(lab=lab, balance__gt=0, patient__isnull=False)
        .exclude(status=Invoice.Status.CANCELLED)
        .aggregate(customers=Count("patient", distinct=True), balance=_sum("balance"))
    )
    jobs = Job.objects.filter(lab=lab)
    open_orders = SupplierOrder.objects.filter(lab=lab, status__in=SupplierOrder.OPEN)
    week_start = today - datetime.timedelta(days=6)
    daily = {
        _local_date(row["day"]): row["total"]
        for row in _valid_invoices(lab, week_start, today)
        .annotate(day=TruncDay("created_at")).values("day").annotate(total=_sum("total"))
    }
    data = {
        "today": {"invoices": today_inv["n"], "sales_total": _money(today_inv["total"]), "collected": _money(collected)},
        "month": {"invoices": month_inv["n"], "sales_total": _money(month_inv["total"])},
        "credit": {"customers": credit["customers"], "balance": _money(credit["balance"])},
        "jobs": {
            "open": jobs.filter(status__in=(*Job.ACTIVE, Job.Status.READY)).count(),
            "overdue": jobs.filter(promised_date__lt=today, status__in=Job.ACTIVE).count(),
            "ready": jobs.filter(status=Job.Status.READY).count(),
        },
        "stock": {"low": _low_stock(lab).count()},
        "orders": {"open": open_orders.count(), "late": open_orders.filter(expected_date__lt=today).count()},
        "sales_last_7_days": [
            {"date": (week_start + datetime.timedelta(days=i)).isoformat(),
             "total": _money(daily.get(week_start + datetime.timedelta(days=i)))}
            for i in range(7)
        ],
    }
    if sees_costs:
        data["month"]["profit"] = _money(month_inv["total"] - month_inv["cost"])
    if has_referrals:
        from apps.doctors.models import Referral

        data["referrals"] = {"open": Referral.objects.filter(lab=lab, status__in=Referral.OPEN).count()}
    return data


# --- Reports ------------------------------------------------------------------------


def sales_report(lab, params):
    start, end = date_range(params)
    group = "month" if params.get("group") == "month" else "day"
    invoices = _valid_invoices(lab, start, end)
    rows = [
        {
            "period": _period(r["period"], group), "invoices": r["n"], "subtotal": _money(r["subtotal"]),
            "discount": _money(r["discount"]), "total": _money(r["total"]), "balance": _money(r["balance"]),
        }
        for r in invoices.annotate(period=_trunc(group)).values("period").annotate(
            n=Count("id"), subtotal=_sum("subtotal"),
            discount=Coalesce(Sum(F("lines_discount") + F("invoice_discount")), Value(ZERO), output_field=MONEY),
            total=_sum("total"), balance=_sum("balance"),
        ).order_by("period")
    ]
    totals = invoices.aggregate(
        n=Count("id"), subtotal=_sum("subtotal"), total=_sum("total"), balance=_sum("balance"),
        discount=Coalesce(Sum(F("lines_discount") + F("invoice_discount")), Value(ZERO), output_field=MONEY),
    )
    payments = (
        Payment.objects.filter(lab=lab, is_void=False, paid_at__date__gte=start, paid_at__date__lte=end)
        .values("method").annotate(amount=_sum("amount"), n=Count("id")).order_by("method")
    )
    top = (
        InvoiceLine.objects.filter(invoice__in=invoices)
        .values("product", name=F("product__name"), kind=F("product__kind"))
        .annotate(qty=Sum("qty"), revenue=_sum("line_total")).order_by("-revenue")[:10]
    )
    return {
        "date_from": start.isoformat(), "date_to": end.isoformat(), "group": group,
        "columns": ["period", "invoices", "subtotal", "discount", "total", "balance"],
        "rows": rows,
        "totals": {
            "invoices": totals["n"], "subtotal": _money(totals["subtotal"]), "discount": _money(totals["discount"]),
            "total": _money(totals["total"]), "balance": _money(totals["balance"]),
        },
        "payments_by_method": [
            {"method": p["method"], "count": p["n"], "amount": _money(p["amount"])} for p in payments
        ],
        "top_products": [
            {"product": t["product"], "name": t["name"], "kind": t["kind"], "qty": t["qty"],
             "revenue": _money(t["revenue"])}
            for t in top
        ],
    }


def profit_report(lab, params):
    start, end = date_range(params)
    group = "month" if params.get("group") == "month" else "day"
    invoices = _valid_invoices(lab, start, end)

    def row(period, revenue, cost):
        profit = (revenue or ZERO) - (cost or ZERO)
        margin = (profit * 100 / revenue).quantize(Decimal("0.1")) if revenue else Decimal("0.0")
        return {"period": period, "revenue": _money(revenue), "cost": _money(cost), "profit": _money(profit),
                "margin": f"{margin}"}

    rows = [
        row(_period(r["period"], group), r["revenue"], r["cost"])
        for r in invoices.annotate(period=_trunc(group)).values("period")
        .annotate(revenue=_sum("total"), cost=_sum("cost_total")).order_by("period")
    ]
    totals = invoices.aggregate(revenue=_sum("total"), cost=_sum("cost_total"))
    line_cost = ExpressionWrapper(F("unit_cost") * F("qty"), output_field=MONEY)
    by_kind = (
        InvoiceLine.objects.filter(invoice__in=invoices).values(kind=F("product__kind"))
        .annotate(revenue=_sum("line_total"), cost=Coalesce(Sum(line_cost), Value(ZERO), output_field=MONEY))
        .order_by("kind")
    )
    estimated = InvoiceLine.objects.filter(invoice__in=invoices, cost_source="reference").count()
    return {
        "date_from": start.isoformat(), "date_to": end.isoformat(), "group": group,
        "columns": ["period", "revenue", "cost", "profit", "margin"],
        "rows": rows,
        "totals": {k: v for k, v in row("", totals["revenue"], totals["cost"]).items() if k != "period"},
        # Before invoice-level discounts (those are not split over lines).
        "by_kind": [{"kind": k["kind"], **{x: y for x, y in row("", k["revenue"], k["cost"]).items() if x != "period"}}
                    for k in by_kind],
        # Lines still costed at the product's reference price (rx lens not received yet, services).
        "estimated_cost_lines": estimated,
    }


def credit_report(lab, params):
    today = timezone.localdate()
    rows = []
    for r in (
        Invoice.objects.filter(lab=lab, balance__gt=0, patient__isnull=False)
        .exclude(status=Invoice.Status.CANCELLED)
        .values("patient", name=F("patient__full_name"), phone=F("patient__phone"))
        .annotate(balance=_sum("balance"), invoices=Count("id"), oldest=Min("created_at"))
        .order_by("-balance", "patient")
    ):
        oldest_day = timezone.localtime(r["oldest"]).date() if r["oldest"] else today
        rows.append({
            "patient": r["patient"], "name": r["name"], "phone": r["phone"], "invoices": r["invoices"],
            "balance": _money(r["balance"]), "oldest": oldest_day.isoformat(), "days": (today - oldest_day).days,
        })
    buckets = []
    for low, high in ((0, 30), (31, 60), (61, 90), (91, None)):
        selected = [r for r in rows if r["days"] >= low and (high is None or r["days"] <= high)]
        buckets.append({"from_days": low, "to_days": high, "customers": len(selected),
                        "balance": _money(sum((Decimal(r["balance"]) for r in selected), ZERO))})
    return {
        "columns": ["name", "phone", "invoices", "balance", "oldest", "days"],
        "rows": rows,
        "totals": {"customers": len(rows), "balance": _money(sum((Decimal(r["balance"]) for r in rows), ZERO))},
        "ageing": buckets,
    }


def _low_stock(lab):
    return Product.objects.filter(
        lab=lab, is_active=True, track_stock=True, reorder_level__gt=0, quantity__lte=F("reorder_level")
    )


def stock_report(lab, params, *, sees_costs):
    """Low stock (default) or every stock-tracked product (`all=true`) + stock value by kind (costs)."""
    products = Product.objects.filter(lab=lab, is_active=True, track_stock=True).select_related("brand")
    if params.get("all") not in ("true", "1"):
        products = _low_stock(lab).select_related("brand")
    columns = ["name", "kind", "brand", "quantity", "reorder_level"]
    if sees_costs:
        columns.append("value")
    rows = []
    for p in products.order_by("kind", "name"):
        row = {"product": p.id, "name": p.name, "kind": p.kind, "brand": p.brand.name if p.brand_id else "",
               "quantity": p.quantity, "reorder_level": p.reorder_level}
        if sees_costs:
            row["value"] = _money(p.quantity * p.average_cost) if not p.uses_variants else _money(_variant_value(p))
        rows.append(row)
    data = {"columns": columns, "rows": rows, "totals": {"products": len(rows)}}
    if sees_costs:
        data["value_by_kind"] = _stock_value_by_kind(lab)
    return data


def _variant_value(product):
    value = ExpressionWrapper(F("quantity") * F("average_cost"), output_field=MONEY)
    return product.variants.filter(quantity__gt=0).aggregate(v=Coalesce(Sum(value), Value(ZERO), output_field=MONEY))["v"]


def _stock_value_by_kind(lab):
    from apps.catalog.models import LensVariant

    value = ExpressionWrapper(F("quantity") * F("average_cost"), output_field=MONEY)
    totals = {}
    for r in (
        Product.objects.filter(lab=lab, track_stock=True, quantity__gt=0)
        .exclude(kind__in=Product.VARIANT_KINDS).values("kind").annotate(v=Sum(value))
    ):
        totals[r["kind"]] = totals.get(r["kind"], ZERO) + (r["v"] or ZERO)
    for r in (
        LensVariant.objects.filter(lab=lab, quantity__gt=0).values(kind=F("product__kind")).annotate(v=Sum(value))
    ):
        totals[r["kind"]] = totals.get(r["kind"], ZERO) + (r["v"] or ZERO)
    return [{"kind": k, "value": _money(v)} for k, v in sorted(totals.items())]


def jobs_report(lab, params):
    today = timezone.localdate()
    jobs = Job.objects.filter(lab=lab).select_related("patient")
    overdue = jobs.filter(promised_date__lt=today, status__in=Job.ACTIVE).order_by("promised_date", "number")
    counts = dict(jobs.values_list("status").annotate(n=Count("id")).values_list("status", "n"))
    return {
        "columns": ["number", "patient", "phone", "status", "promised_date", "days_late"],
        "rows": [
            {"job": j.id, "number": j.number, "patient": j.patient.full_name, "phone": j.patient.phone,
             "status": j.status, "promised_date": j.promised_date.isoformat(),
             "days_late": (today - j.promised_date).days}
            for j in overdue
        ],
        "totals": {"overdue": overdue.count()},
        "counts": {s: counts.get(s, 0) for s, _ in Job.Status.choices},
    }


def suppliers_report(lab, params):
    rows = []
    suppliers = Supplier.objects.filter(lab=lab).annotate(
        balance=_sum("orders__balance"),
        open_orders=Count("orders", filter=Q(orders__status__in=SupplierOrder.OPEN)),
    ).order_by("-balance", "name")
    for s in suppliers:
        if not s.balance and not s.open_orders and params.get("all") not in ("true", "1"):
            continue
        rows.append({"supplier": s.id, "name": s.name, "phone": s.phone, "open_orders": s.open_orders,
                     "balance": _money(s.balance)})
    return {
        "columns": ["name", "phone", "open_orders", "balance"],
        "rows": rows,
        "totals": {"suppliers": len(rows), "balance": _money(sum((Decimal(r["balance"]) for r in rows), ZERO))},
    }
