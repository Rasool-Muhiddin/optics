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

Bundled font: Noto Naskh Arabic (SIL OFL 1.1, see `assets/fonts/NotoNaskhArabic-OFL.txt`).
