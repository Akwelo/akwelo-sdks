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

Options: `baseUrl` (default `https://flow.akwelo.com`, must be https) and `attestationToken`.
Prefer embedding? Render `<AkweloVerifyView sessionToken={t} onResult={fn} />` yourself, and give
the person a way to leave: the embedded view cannot close itself.

The modal has a close button that always works. A page that cannot load, answers with an HTTP
error, or whose web process dies ends in an `error` result, not a blank screen. Links the person
taps open in the system browser.

`submitted` only means capture finished; never treat it as a pass.

## Device attestation

`attestationToken` accepts a string or an async function. Pure JS cannot produce Play Integrity or
App Attest tokens; obtain one with a native module and pass it in. A function that throws, or takes
longer than 5 seconds, is skipped. **Akwelo stores the token and does not verify it yet, so today it
adds no protection.** **TODO:** a companion native
module is planned once real Google Play Console and Apple Developer accounts are set up.

## Development

```sh
npm install
npm run typecheck && npm test && npm run build
```
