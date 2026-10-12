"""
Arabic CSV headers / values for exported reports. The CSV file is a user-facing document
opened in Excel, so it carries its labels (the JSON API keeps stable keys only).
"""

CSV_LABELS = {
    "period": "الفترة",
    "invoices": "عدد الفواتير",
    "subtotal": "المجموع قبل الخصم",
    "discount": "الخصم",
    "total": "الإجمالي",
    "balance": "المتبقي",
    "revenue": "المبيعات",
    "cost": "الكلفة",
    "profit": "الربح",
    "margin": "هامش الربح %",
    "name": "الاسم",
    "phone": "الهاتف",
    "oldest": "أقدم فاتورة",
    "days": "عدد الأيام",
    "customers": "عدد الزبائن",
    "kind": "النوع",
    "brand": "الماركة",
    "quantity": "الكمية",
    "reorder_level": "حد إعادة الطلب",
    "value": "قيمة المخزون",
    "products": "عدد الأصناف",
    "number": "رقم الطلب",
    "patient": "المراجع",
    "status": "الحالة",
    "promised_date": "موعد التسليم",
    "days_late": "أيام التأخير",
    "overdue": "المتأخرة",
    "open_orders": "طلبات مفتوحة",
    "suppliers": "عدد الموردين",
}

VALUE_LABELS = {
    "frame": "إطار",
    "stock_lens": "عدسة مخزنية",
    "rx_lens": "عدسة طبية (حسب الطلب)",
    "contact_lens": "عدسة لاصقة",
    "accessory": "إكسسوار",
    "solution": "محلول",
    "service": "خدمة",
    "pending": "قيد الانتظار",
    "lens_ordered": "تم طلب العدسة",
    "in_workshop": "في الورشة",
}
