# Building a desktop release (Windows)

On the Windows build PC (the owner's PC):

**Requirements**: Flutter **3.44.8**, Visual Studio 2022 with "Desktop development with C++",
Inno Setup 6.3+ (it includes `Languages\Arabic.isl`; for an older Inno Setup download `Arabic.isl`
from https://jrsoftware.org/files/istrans/ into its `Languages` folder).

## One command

```powershell
cd <repo>
.\installer\build_release.ps1 -Version 1.0.0 -BuildNumber 1
# optional: -ApiBaseUrl https://optics-api.tera-software1.com/api/v1  (this is the default)
```

It runs `flutter pub get`, `flutter test`, then:

```powershell
cd app
flutter build windows --release `
  --build-name=1.0.0 --build-number=1 `
  --dart-define=API_BASE_URL=https://optics-api.tera-software1.com/api/v1 `
  --dart-define=APP_VERSION=1.0.0
```

and compiles `installer\optics.iss` with Inno Setup →
`installer\Output\optics-setup-1.0.0.exe`, printing its SHA-256.

Rules:
- `APP_VERSION` must equal `--build-name` (the app reports it and compares it with the server).
- Every release needs a **higher** version (`1.0.0` → `1.0.1`…). Never change the `AppId` in
  `optics.iss` (updates find the installed copy by it).
- Without `API_BASE_URL` the app talks to `http://127.0.0.1:8000/api/v1` (development).

## Publish it (in-app updates)

1. Admin → **App updates → Desktop app versions → Add**: platform Windows, version `1.0.0`,
   build `1`, upload `optics-setup-1.0.0.exe` (the SHA-256 and size are computed on upload),
   Arabic release notes, *mandatory* only for breaking releases (or set *min supported version*).
2. Every installed app checks `GET /api/v1/desktop/latest-version/` at start-up and shows
   "يتوفر إصدار جديد". "تحديث الآن" downloads the installer, verifies the SHA-256, runs it with
   `/SILENT /SP- /NOCANCEL /CLOSEAPPLICATIONS /NORESTART` (Windows asks for administrator
   approval) and closes; the installer replaces the files and starts the new version.
3. Large files: you can host the installer elsewhere (e.g. an R2 public bucket) and fill
   *installer URL* + *SHA-256* (from the build script output) instead of uploading.

## First installation at a lab

Run `optics-setup-<version>.exe` (Arabic or English setup), keep "desktop shortcut", start the app,
enter the lab's activation code, log in. Activation, the encrypted token/device key (DPAPI) and the
offline cache live in `%APPDATA%\com.terasoftware\Optics Lab\` and survive updates and uninstall.
