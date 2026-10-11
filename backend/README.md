# Optics Lab — Django backend

See `../CLAUDE.md` for architecture and conventions.

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env.local                           # never commit .env.local
python manage.py migrate
python manage.py createsuperuser                     # Tera admin: /admin/
python manage.py create_lab "Demo Lab" owner1 'Owner-Pass1!'   # prints the activation code
python manage.py runserver                           # http://127.0.0.1:8000/api/v1/health/
pytest                                               # uses config.settings.test (fast hasher); or: python manage.py test
python manage.py makemigrations --check
```

Settings: `config.settings.local` (default), `config.settings.production`
(`DJANGO_SETTINGS_MODULE=config.settings.production`; requires `SECRET_KEY`, `ALLOWED_HOSTS`,
`DATABASE_URL`).

## API (P1)

| Endpoint | Who | Notes |
|---|---|---|
| `POST desktop/activate/` | public (throttled) | `{activation_code, device_id, device_name?, app_version?}` → `{device_key, device, lab}` |
| `POST desktop/login/` | public (throttled) | `{username, password, device_key}` → `{token, user, membership, lab, plan, device}` |
| `GET auth/me/` | lab member | same session payload (no token) |
| `POST auth/logout/` | authenticated | revokes this device's token only |
| `GET/PATCH lab/` | member reads, owner edits | lab settings (print header, logo, currency…) |
| `lab/users/` | owner | list/create/update lab users (no delete — deactivate) |
| `lab/devices/` | owner | list/rename/(de)activate devices |

Tenant isolation: lab-owned models extend `apps.core.models.LabScopedModel`; their endpoints use
`apps.core.viewsets.LabScoped*ViewSet` (a test fails if one does not). Plan feature flags gate
endpoints with `apps.core.permissions.requires_feature("<flag>")`.
