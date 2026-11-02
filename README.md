# HOLA Professional (Flutter)

Flutter port of the HOLA clickable prototype (`../prototype/index.html`): one app with five
role experiences (Customer, Salon owner/manager, Salon staff, HOLA sales officer, HOLA delivery rider).

## Run in Android Studio
1. Open this `app/` folder in Android Studio (Flutter + Dart plugins installed).
2. `flutter pub get` (Android Studio prompts automatically).
3. Pick an Android emulator or device and press Run.

CLI: `flutter run` · release APK: `flutter build apk --release`

## Architecture: MVVM + clean architecture
```
lib/
  main.dart                  entry point; MultiProvider(appProviders())
  app/                       composition root (di.dart), root (splash → login → shell), shell + tab registry
    viewmodels/              app-wide VMs: SessionViewModel (role, tab, theme, sound), SyncViewModel (offline outbox)
  core/
    mvvm/view_model.dart     ViewModel base (loading/error, run(), safe notify)
    theme/                   HOLA tokens, gradients, type scale, icon set
    utils/                   pure helpers: formatting, clock, synthesised sounds
  domain/                    no Flutter imports
    entities/                Salon, Booking, Appt, Visit, Delivery, SOrder, Credit… + status vocabulary
    repositories/            repository contracts (Auth, Catalog, Booking, SalonOps, Trade, Field, Delivery, Sync…)
  data/
    sources/demo/            DEMO data (prototype only)
    repositories/            Demo* implementations of the contracts
  shared/widgets/            HOLA component library (pure UI, no business logic)
  features/<feature>/
    <feature>.dart           barrel: public views + <feature>Providers()
    viewmodels/              state + business rules, talk to repositories only
    views/                   screens: render VM state, forward user events
    widgets/                 feature-only UI pieces
```
Features: `auth`, `profile`, `customer`, `salon`, `trade` (B2B orders and credit), `field`, `sync`, `rider`.

Dependency rule: views → viewmodels → repository contracts (domain) ← data implementations.
To connect the HOLA API, add `Api*Repository` classes in `data/repositories/` and swap them in `app/di.dart`.
No view or viewmodel changes are needed.

## Tests
`flutter test` boots the app and opens every tab of all five experiences.

## Notes
- `lib/data/demo_data.dart` is prototype sample data only. Real data comes from the HOLA API
  (staging `https://hola.metaxperts.net/api/v1`); it is not wired in this build.
- On the sign-in screen, "Prototype: sign in as" picks the experience. In production `GET /me` decides it from permissions.
- Brand: Instrument Sans (bundled, OFL), HOLA palette, logo never recoloured (inverted on dark grounds).
