from django.db import migrations, models

import apps.core.codes
from apps.core.codes import generate_link_code


def fill_codes(apps_registry, schema_editor):
    Lab = apps_registry.get_model("labs", "Lab")
    used = set()
    for lab in Lab.objects.all():
        code = generate_link_code()
        while code in used:
            code = generate_link_code()
        used.add(code)
        lab.doctor_link_code = code
        lab.save(update_fields=["doctor_link_code"])


class Migration(migrations.Migration):

    dependencies = [
        ("labs", "0003_labuser_can_manage_inventory"),
    ]

    operations = [
        migrations.AddField(
            model_name="lab",
            name="doctor_link_code",
            field=models.CharField(max_length=16, null=True),
        ),
        migrations.RunPython(fill_codes, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="lab",
            name="doctor_link_code",
            field=models.CharField(
                default=apps.core.codes.generate_link_code,
                help_text="Given by the lab to doctors so they can request a link (P7). Not secret like the activation code.",
                max_length=16,
                unique=True,
            ),
        ),
    ]
