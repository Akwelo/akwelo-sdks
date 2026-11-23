# @akwelo/react-native

Akwelo identity verification for React Native. Opens Akwelo's hosted selfie capture page in a
`react-native-webview` modal and resolves with the outcome.

## Install

```sh
npm install @akwelo/react-native react-native-webview
cd ios && pod install
```

- **iOS:** add `NSCameraUsageDescription` to Info.plist.
- **Android:** add `<uses-permission android:name="android.permission.CAMERA" />` to your manifest
  and request it at runtime (e.g. `PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.CAMERA)`)
  before calling `verify`.

## Usage

```tsx
import { Akwelo, AkweloProvider } from '@akwelo/react-native';

export default function App() {
  return (
    <AkweloProvider>
      <Root />
    </AkweloProvider>
  );
}

// sessionToken comes from your backend, which created the session with your secret key.
const result = await Akwelo.verify({ sessionToken });
switch (result.status) {
  case 'submitted': showPending(result.sessionId); break; // decision arrives at your backend
  case 'cancelled': showRetry(); break;
  case 'error':     showError(result.error, result.errorMessage); break; // error is a stable code
}
```

`verify` never rejects. With status `error`, `result.error` is a code from the
[list in the root README](../README.md#error-codes).

Options: `baseUrl` (default `https://flow.akwelo.com`, must be https), `attestationToken` and
`screenCaptureActive` (see below).
Prefer embedding? Render `<AkweloVerifyView sessionToken={t} onResult={fn} />` yourself, and give
the person a way to leave: the embedded view cannot close itself.

The modal has a close button that always works. A page that cannot load, answers with an HTTP
error, or whose web process dies ends in an `error` result, not a blank screen. Links the person
taps open in the system browser.

`submitted` only means capture finished; never treat it as a pass.

## Device attestation

`attestationToken` accepts a string or an async function. Pure JS cannot produce Play Integrity or
App Attest tokens; obtain one with a native module and pass it in. A function that throws, or takes
longer than 5 seconds, is skipped. Akwelo verifies the token. To require it, pass `attestation` with the apps you expect (`ios_app_ids` as `TEAMID.bundle.id`, `android_package_names`) when your backend creates the session. The session result carries `device_attestation` with a `status` (`verified`, `failed`, `unverified` or `absent`) and a `reason`. A session that expected attestation and did not get a verified one goes to review and is never approved automatically.

## Screen capture

Akwelo sends a session to review when the screen was recorded, mirrored or shared while the selfie
was taken. React Native cannot see this; feed `screenCaptureActive` from a small native module of
your own. It takes a boolean, or a function that subscribes to changes and returns an unsubscribe
function. Without it nothing is sent, and Akwelo records the capture environment as `unknown`.

```ts
import { NativeEventEmitter, NativeModules } from 'react-native';
const { ScreenCapture } = NativeModules; // your module, below
const events = new NativeEventEmitter(ScreenCapture);

await Akwelo.verify({
  sessionToken,
  screenCaptureActive: (onChange) => {
    // null means unknown (Android 14 and below with nothing seen): report nothing.
    ScreenCapture.isCaptured().then((v: boolean | null) => v != null && onChange(v));
    const sub = events.addListener('screenCaptureChanged', (e) => onChange(e.active));
    return () => sub.remove();
  },
});
```

iOS side (Swift, in an `RCTEventEmitter` subclass): resolve `isCaptured` with
`UIScreen.main.isCaptured`, and on `UIScreen.capturedDidChangeNotification` send
`screenCaptureChanged` with `["active": UIScreen.main.isCaptured]`.

Android side (Kotlin): on Android 15+, `activity.windowManager.addScreenRecordingCallback(mainExecutor)
{ state -> emit(state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE) }` (declare
`android.permission.DETECT_SCREEN_RECORDING`). On Android 14 and below only report `true`, while
`DisplayManager.getDisplays()` has a display that is on with `Display.FLAG_PRESENTATION`, other
than `Display.DEFAULT_DISPLAY` and the activity's own display; never report `false` there
(resolve `isCaptured` with `null`).
Screen recorders, Cast mirroring and remote-access apps cannot be seen on those versions, so
staying silent lets Akwelo record `unknown` instead of "not detected".

## Development

```sh
npm install
npm run typecheck && npm test && npm run build
```
