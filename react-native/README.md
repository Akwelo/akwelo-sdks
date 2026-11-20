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
  case 'error':     showError(result.error); break;
}
```

Options: `baseUrl` (default `https://flow.akwelo.com`) and `attestationToken`.
Prefer embedding? Render `<AkweloVerifyView sessionToken={t} onResult={fn} />` yourself.

`submitted` only means capture finished; never treat it as a pass.

## Device attestation

`attestationToken` accepts a string or an async function. Pure JS cannot produce Play Integrity or
App Attest tokens; obtain one with a native module and pass it in. **TODO:** a companion native
module is planned once real Google Play Console and Apple Developer accounts are set up.

## Development

```sh
npm install
npm run typecheck && npm test && npm run build
```
