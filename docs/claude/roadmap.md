# Roadmap

Moved verbatim from CLAUDE.md §9.

## 9. Roadmap (one item per session, in order)

- [x] **P0 Scaffold**: Django project + apps skeleton, settings split, DRF, token auth, health endpoint,
      pytest setup; Flutter desktop project with RTL theme, router, ApiService base, ConnectivityService,
      cache DB base, repository base class.
- [x] **P1 Accounts & tenancy**: Lab, LabUser roles, lab-scoped base viewset, activation/login, billing plans
      + feature flags, Django Admin for all of it. Flutter: activation + login + main layout with sidebar.
- [x] **P2 Catalog & inventory**: categories, brands, products by kind, lens power variants, stock ledger,
      weighted-average cost. Flutter: inventory screens (list, filters, add/edit per kind, lens power grid).
- [x] **P3 Patients, exams, prescriptions**: models, validation, transposition helper. Flutter: patient
      profile, exam history, Rx entry form (OD/OS table), print prescription + exam report.
- [x] **P4 POS & sales**: atomic checkout, discounts, credit + payments, invoice numbering. Flutter: POS
      screen, credit customers list, invoice print (A4/A5 + thermal).
- [x] **P5 Customer jobs**: lifecycle + status log, link to invoice/prescription. Flutter: jobs board.
- [x] **P6 Supplier orders**: suppliers, orders, receiving → stock, payments. Flutter: pending orders screen.
- [x] **P7 Doctor linking**: doctor accounts, links, referrals, accept → patient/exam/Rx in lab.
      Flutter: doctor mode (separate sidebar), lab inbox for referrals. Gated by plan flag.
- [x] **P8 Dashboard & reports**: sales, profit, credit balances, stock low/levels, jobs overdue,
      supplier balances; export gated by plan.
- [x] **P9 Offline read cache** completion across all domains + offline banners.
- [x] **P10 Release**: Inno Setup installer, update endpoint, production deploy, production build.
      Before release: move token/device-key storage from plain `optics_auth.json` to encrypted storage
      (Windows DPAPI via `CryptProtectData`, or equivalent: Keychain on macOS, libsecret on Linux), with a
      one-time migration of the existing file and deletion of the plain copy.

