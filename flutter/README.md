# akwelo (Flutter)

Akwelo identity verification for Flutter. Opens Akwelo's hosted selfie capture page with
`webview_flutter` and returns the outcome.

## Install

```sh
flutter pub add akwelo
```

- **iOS:** add `NSCameraUsageDescription` to `ios/Runner/Info.plist`.
- **Android:** add `<uses-permission android:name="android.permission.CAMERA" />` and request it at
  runtime (e.g. with `permission_handler`) before calling `verify`. minSdk 21+.

## Usage

```dart
import 'package:akwelo/akwelo.dart';

// sessionToken comes from your backend, which created the session with your secret key.
final result = await Akwelo.verify(context, sessionToken: token);
switch (result.status) {
  case VerifyStatus.submitted: showPending(result.sessionId); // decision arrives at your backend
  case VerifyStatus.cancelled: showRetry();
  case VerifyStatus.error:     showError(result.error);
}

// Options
await Akwelo.verify(context, sessionToken: token,
    options: AkweloOptions(baseUrl: 'https://flow.akwelo.com', attestationToken: myAttestFn));
```

`submitted` only means capture finished; never treat it as a pass.

## Device attestation

`attestationToken` is an optional async callback returning a Play Integrity or App Attest token,
passed to the page as `attest=`. **TODO:** a built-in native helper is planned once real Google Play
Console and Apple Developer accounts are set up.

## Development

```sh
flutter pub get && flutter test
```
