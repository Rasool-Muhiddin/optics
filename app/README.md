# optics_app — Flutter desktop client

Arabic-first (RTL) desktop client for the Optics Lab Management System. Windows is the
primary target; Linux/macOS must still compile. See `../CLAUDE.md` for architecture.

Requires Flutter with Dart ≥ 3.12.

```bash
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
flutter analyze
flutter test
```

Layout (`lib/`): `core/` (config, theme, router, errors, formatters, strings),
`data/api` (ApiClient + one ApiService per domain), `data/cache` (read-only SQLite cache),
`data/repositories` (the only layer screens call), `models/`, `services/`, `screens/`, `widgets/`.

Auth flow (P1): first run → activation screen (code from Tera) → login → main layout with
sidebar. Device key + token live in `optics_auth.json` in the app-support directory
(`services/auth_storage.dart`); `services/auth_controller.dart` drives the router redirects.
For local testing, create a lab with `python manage.py create_lab ...` in `backend/`.

Bundled font: Noto Naskh Arabic (SIL OFL 1.1, see `assets/fonts/NotoNaskhArabic-OFL.txt`).
