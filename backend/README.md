# Optics Lab — Django backend

See `../CLAUDE.md` for architecture and conventions.

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env.local                           # never commit .env.local
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver                           # http://127.0.0.1:8000/api/v1/health/
pytest                                               # or: python manage.py test
python manage.py makemigrations --check
```

Settings: `config.settings.local` (default), `config.settings.production`
(`DJANGO_SETTINGS_MODULE=config.settings.production`; requires `SECRET_KEY`, `ALLOWED_HOSTS`,
`DATABASE_URL`).
