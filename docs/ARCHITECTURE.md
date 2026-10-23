# veriwork-mobile — architecture & conventions

Flutter client for the **existing** VeriWork/PagerLook backend. It reuses the same REST API,
auth, and business rules as `veriwork-frontend`; nothing server-side is duplicated or changed.

## Layout

```
lib/
  main.dart / app.dart          bootstrap, MaterialApp.router
  core/
    config/env.dart             API_URL, APP_URL, GOOGLE_SERVER_CLIENT_ID (--dart-define)
    network/api_client.dart     Dio client: envelope unwrap, Bearer auth, single-flight refresh
    network/api_exception.dart  ApiException + errorMessage(e)
    network/upload.dart         PickedDoc, buildFormData, file validation (mimetype matters!)
    storage/session_store.dart  tokens + user/profile/company in Keychain/EncryptedSharedPrefs
    auth/auth_controller.dart   session ChangeNotifier (web AuthContext)
    auth/home_routes.dart       employeeHomeRoute / enterpriseHomeRoute / isPortalUnlocked
    auth/company_permissions.dart  companyPermissionsProvider (web usePermissions)
    router/                     go_router config, guards (web guards.jsx), bottom-nav shells
    providers.dart              Riverpod providers for api client, API modules, auth
    theme/app_theme.dart        AppColors / AppRadii / Tone (web design tokens)
    utils/json.dart             asMap, asList, listFrom, str, asBool, asInt, pick, idOf …
    utils/formatters.dart       formatDate, timeAgo, humanize, initials, mediaUrl …
    utils/validators.dart       email/phone/password/pincode/aadhaar validators
    widgets/widgets.dart        shared UI kit (import this barrel)
  data/api/                     1:1 ports of veriwork-frontend/src/api/*.js
  features/<area>/…             screens
```

## Rules

1. **API calls only through `lib/data/api/*`** (`ref.read(employeeApiProvider).fetchJobs()` …).
   Each method mirrors a function in `veriwork-frontend/src/api/*.js` and returns the
   envelope's `data` (dynamic JSON). Failures throw `ApiException` with the backend's message.
2. **JSON is read with `core/utils/json.dart`** (`asMap`, `listFrom`, `str`, `asBool`, `idOf`…),
   never with raw casts. Field names follow what the web pages read.
3. **State:** Riverpod 2 (no codegen). Reads use `FutureProvider.autoDispose` (`.family` for ids)
   declared at the top of the screen file; mutations call the API from the widget, show a
   spinner on the button, then `ref.invalidate(...)` the affected providers. Lists support
   pull-to-refresh (`RefreshIndicator` → `ref.refresh(provider.future)`).
4. **Session:** `ref.watch(authProvider)` gives `user`, `profile`, `company`. After login call
   `loginEmployee/loginEnterprise/loginAdmin(data)` then `context.go(...)`. When a screen gets a
   fresh profile/company from the API, store it with `updateProfile` / `updateCompany(…, merge: true)`
   so guards and home routing stay right.
5. **Navigation:** paths match the web routes (see `core/router/app_router.dart`).
   `context.go` for tab roots / after login / flow completion; `context.push` for detail screens
   so back works. Never construct screens directly from other screens.
6. **UI kit** (`core/widgets/widgets.dart`): `AppButton`, `AppTextField`, `AppDropdown`,
   `AppDateField`, `AppCard`, `InfoRow`, `SectionHeader`, `PageIntro`, `StatCard`/`StatGrid`,
   `InfoBanner`, `StatusBadge`, `AsyncValueView`, `LoadingView`, `ErrorView`, `EmptyState`,
   `BusyOverlay`, `OtpInput`, `PhoneField`, `AsyncAutocompleteField`, `FilterChipsBar`,
   `SearchField`, `AppAvatar`, `BrandLogo`, `ScoreRing`, `LabeledProgress`, `MiniBarChart`,
   `BreakdownBars`, `MenuTile`/`MenuSection`, `showToast`/`showErrorToast`,
   `showConfirmDialog`, `showTextInputDialog`, `pickDocumentWithSheet`, `pickImage`,
   `openExternalUrl`, `copyToClipboard`. Colours only via `AppColors` / `Tone`.
7. **Uploads:** pick with `pickDocumentWithSheet` / `pickImage` (they validate like the web) and
   pass the `PickedDoc` to the API method — it sets the right mimetype for multer.
8. **No mock data.** Empty states use `EmptyState`; errors use `ErrorView` with retry.
9. Every screen is a full `Scaffold` with its own `AppBar`. Tab roots are wrapped by the
   portal shell's bottom navigation automatically.
10. Layout: padding 16, `ListView` bodies, `SafeArea` where there's no AppBar, nothing wider
    than the screen (use `Expanded`/`Wrap`/ellipsis). Forms use `Form` + validators and keep
    the primary button reachable above the keyboard.
