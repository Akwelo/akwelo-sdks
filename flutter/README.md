# akwelo (Flutter)

Akwelo identity verification for Flutter. Opens Akwelo's hosted selfie capture page with
`webview_flutter` and returns the outcome.

## Install

```sh
flutter pub add akwelo
```

- **iOS:** add `NSCameraUsageDescription` to `ios/Runner/Info.plist`.
- **Android:** add `<uses-permission android:name="android.permission.CAMERA" />` and request it at
  runtime (e.g. with `permission_handler`) before calling `verify`. The SDK cannot ask for it: without
  it the page reports `camera_unavailable`. minSdk 24 (set by current `webview_flutter_android`).

Flutter 3.24 or later (Dart 3.5).

## Usage

```dart
import 'package:akwelo/akwelo.dart';

// sessionToken comes from your backend, which created the session with your secret key.
final result = await Akwelo.verify(context, sessionToken: token);
switch (result.status) {
  case VerifyStatus.submitted: showPending(result.sessionId); // decision arrives at your backend
  case VerifyStatus.cancelled: showRetry();
  case VerifyStatus.error:     showError(result.error, result.errorMessage); // error is a stable code
}

// Options
await Akwelo.verify(context, sessionToken: token,
    options: AkweloOptions(baseUrl: 'https://flow.akwelo.com', attestationToken: myAttestFn));
```

`submitted` only means capture finished; never treat it as a pass.

`verify` never throws. With status `error`, `result.error` is a code from the
[list in the root README](../README.md#error-codes).

The page has a close button that always works, and uses no Material or Cupertino widgets, so it
runs in any app. A page that cannot load or answers with an HTTP error ends in an `error` result,
not a blank screen. Links the person taps open in the system browser (`url_launcher`).

## Device attestation

`attestationToken` is an optional async callback returning a Play Integrity or App Attest token,
passed to the page as `attest=`. A callback that throws, or takes longer than 5 seconds, is skipped.
**Akwelo stores the token and does not verify it yet, so today it adds no protection.** **TODO:** a built-in native helper is planned once real Google Play
Console and Apple Developer accounts are set up.

## Development

```sh
flutter pub get && flutter test
```
