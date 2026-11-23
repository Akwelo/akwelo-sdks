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

## Screen capture

Akwelo sends a session to review when the screen was recorded, mirrored or shared while the selfie
was taken. Flutter cannot see this; feed it from your app's platform code with
`AkweloOptions(screenCaptureActive: bool)` or, for changes while the page is open,
`watchScreenCapture`. Without either, nothing is sent and Akwelo records `unknown`.

```dart
const channel = EventChannel('app/screen_capture'); // yours, below
await Akwelo.verify(context, sessionToken: token, options: AkweloOptions(
  watchScreenCapture: (onChange) {
    // Only a real bool is forwarded: no event means unknown, never `false`.
    final sub = channel.receiveBroadcastStream().listen((v) { if (v is bool) onChange(v); });
    return sub.cancel;
  },
));
```

iOS (`AppDelegate.swift`, a `FlutterStreamHandler` on that channel): send
`UIScreen.main.isCaptured` on listen and on every `UIScreen.capturedDidChangeNotification`.

Android (`MainActivity.kt`, an `EventChannel.StreamHandler`): on Android 15+ send
`windowManager.addScreenRecordingCallback(mainExecutor) { s -> events.success(s == WindowManager.SCREEN_RECORDING_STATE_VISIBLE) }`
(declare `android.permission.DETECT_SCREEN_RECORDING`). On Android 14 and below only send `true`,
while `DisplayManager.getDisplays()` has a display that is on with `Display.FLAG_PRESENTATION`,
other than `Display.DEFAULT_DISPLAY` and the activity's own display; never send `false` there.
Screen recorders, Cast mirroring and remote-access apps cannot be seen on those versions, so
staying silent lets Akwelo record `unknown` instead of "not detected".

## Development

```sh
flutter pub get && flutter test
```
