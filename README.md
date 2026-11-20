# Akwelo SDKs

Public mobile SDKs for Akwelo identity verification (selfie / liveness capture).

v1 SDKs are thin, auditable webview wrappers around Akwelo's hosted capture page. Your
backend creates a verification session with your secret API key and hands the short-lived
`sessionToken` to the app; the SDK opens the capture page and returns the outcome.

| Package | Directory | Install name | Entry point |
|---|---|---|---|
| Android (Kotlin) | [`android/`](android/) | `com.akwelo:akwelo-android` (published as `io.github.akwelo` for now) | `Akwelo.verify(activity, token) { result -> }` |
| iOS (Swift) | [`ios/`](ios/) | Swift Package `Akwelo` / CocoaPod `Akwelo` | `try await Akwelo.verify(sessionToken:from:)` |
| React Native | [`react-native/`](react-native/) | `@akwelo/react-native` | `await Akwelo.verify({ sessionToken })` |
| Flutter | [`flutter/`](flutter/) | `akwelo` (pub.dev) | `await Akwelo.verify(context, sessionToken: ...)` |

## Shared contract

1. The SDK opens `{baseUrl}/verify/selfie#token={sessionToken}[&attest={attestationToken}]`.
   `baseUrl` defaults to `https://flow.akwelo.com` and is configurable. The token travels in
   the URL fragment so it is never sent to servers or logged by proxies.
2. Camera permission and inline media playback are granted to the page.
3. The page reports the outcome through a JS bridge named `AkweloBridge`
   (Android `addJavascriptInterface`, iOS `WKScriptMessageHandler` named `akwelo`,
   React Native `window.ReactNativeWebView.postMessage`, Flutter `JavaScriptChannel`):

   ```json
   {"type":"akwelo.verify.result","sessionId":"...","status":"submitted|cancelled|error","error":"optional"}
   ```

4. `submitted` only means capture finished. The decision (pass / fail / review) is delivered
   to **your backend** via the session API or webhook; never trust a client-side result.

Device attestation (Play Integrity on Android, App Attest on iOS) is optional and passed as
`attest=`. It needs real Google Cloud / Apple Developer accounts; see each package README.

## License

MIT, see [LICENSE](LICENSE).
