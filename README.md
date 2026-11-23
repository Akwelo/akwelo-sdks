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
   `baseUrl` defaults to `https://flow.akwelo.com` and is configurable. It must be `https`
   (plain `http` is accepted only for a development server on the same machine). The token
   travels in the URL fragment, so it is not sent to the server in the request or logged by proxies.
2. Camera permission and inline media playback are granted to the page, and only to the page:
   the WebView never navigates to another origin. A link the person taps (privacy notice, help)
   opens in the system browser.
3. The page reports the outcome through a JS bridge named `AkweloBridge`
   (Android `WebMessageListener` or `addJavascriptInterface`, iOS `WKScriptMessageHandler` named
   `akwelo`, React Native `window.ReactNativeWebView.postMessage`, Flutter `JavaScriptChannel`):

   ```json
   {"type":"akwelo.verify.result","sessionId":"vs_... or null","status":"submitted|cancelled|error","error":{"code":"camera_unavailable","message":"..."}}
   ```

   `error` is present only with status `error`. The SDKs also accept a bare string there and
   read it as the code.
4. **Capture environment.** After every page load and on every change, the SDK evaluates
   `try{window.AkweloHost&&window.AkweloHost.signal(<report>)}catch(e){}` in the page, and puts
   the first report in the fragment as `&env=<base64url JSON>`:

   ```json
   {"screen_capture":"active|inactive","source":"ios|android|react-native|flutter","screen_capture_seen":true}
   ```

   `screen_capture` is whether the screen is being recorded, mirrored or shared right now.
   `screen_capture_seen` is present once any capture was seen since the screen opened (also an
   Android 14 screenshot) and stays after it stops. The report is evidence, not a verdict: Akwelo's
   server decides (a capture sends an approval to review) and trusts it more with a verified
   device attestation. iOS and Android detect it themselves; React Native and Flutter forward what
   the host app reports (`screenCaptureActive`); when nothing is known nothing is sent. Android 15+
   detects screen recording and projection of the app; Android 14 detects screenshots; all
   versions detect an external presentation display (HDMI, Miracast, Smart View). Screen
   recorders, Cast mirroring and remote-access apps are not detectable on Android 14 and below,
   where the session reports nothing unless a presentation display or screenshot is seen.
5. `submitted` only means capture finished. The decision (pass / fail / review) is delivered
   to **your backend** via the session API or webhook; never trust a client-side result.

## What every SDK guarantees

- **One result, always.** Every way out of the capture screen ends in exactly one result: the
  page finishing, the person closing the screen, the page failing to load, the WebView process
  dying. A call never hangs and never leaves the person on a blank screen: a native close button
  (iOS, React Native, Flutter) or the system back button (Android) always works.
- **One capture at a time.** A second `verify` while one is open gets `already_in_progress` at
  once; the open capture is not disturbed.
- **Errors have a code.** With status `error`, `error` is a stable code and `errorMessage` is text
  for a person (in the page's language when the page reported it).
- **Attestation never blocks capture.** No token within 5 seconds means the page loads without one.

### Error codes

| Code | Reported by | Meaning | What to do |
|---|---|---|---|
| `invalid_session_token` | SDK, page | Blank token, or not a `session_token` | Fix the integration |
| `invalid_base_url` | SDK | `baseUrl` is not `https` | Fix the integration |
| `already_in_progress` | SDK | A capture is already open | Wait for it |
| `presentation_failed` | SDK | The capture screen could not be shown | Call from a screen that is visible |
| `missing_camera_usage_description` | SDK (iOS) | `NSCameraUsageDescription` is not in Info.plist | Add it |
| `provider_not_mounted` | SDK (React Native) | `<AkweloProvider>` is not mounted | Mount it |
| `webview_unavailable` | SDK (Android) | The system WebView is disabled or updating | Ask the person to retry |
| `page_load_failed` | SDK | The capture page did not load (offline, DNS, TLS, HTTP error) | Retry with the same token |
| `webview_crashed` | SDK | The page's process died, usually low memory | Retry with the same token |
| `missing_token` | page | The link carried no token | Fix the integration |
| `camera_unavailable` | page | No camera, or permission denied | Ask the person to allow the camera |
| `session_token_expired`, `session_token_used` | page | The token is past its 10 minutes, or a capture was already submitted with it | Create a new session |
| `attempts_exhausted` | page | No capture attempts left on this session | Create a new session |
| `session_not_capturing` | page | The session is already decided, expired or cancelled | Create a new session |
| `capture_failed` | page | The capture could not start | Retry with the same token |
| `unknown_error` | SDK | The page reported an error without a code | Retry |

A network failure during capture is not a result: the page offers the person a retry, and
reports `cancelled` if they give up. The page can report other API error codes; treat an unknown
code as a generic failure.

## Status and limits

- **Device attestation.** Play Integrity and App Attest tokens passed as `attest=` are forwarded
  to Akwelo with the capture and verified there. Pass `attestation` (the apps you expect) when
  your backend creates the session to require it: a session without a verified attestation goes
  to review. The screen-capture report is marked `trusted` only when attestation is verified. See
  each package README.
- **Android, process death.** The callback of `Akwelo.verify(activity, token) { }` cannot survive
  Android killing your app's process while the capture screen is open. Use `AkweloVerifyContract`
  to receive the result in that case too. The capture itself is unaffected: the decision still
  reaches your backend.
- **Flutter on Android, WebView crash.** `webview_flutter_android` does not report a dead WebView
  process, so the SDK cannot turn it into `webview_crashed` there; Android closes the app.
- **Flutter on Android, camera permission.** Your app must hold the `CAMERA` permission before
  `verify` is called; otherwise the page reports `camera_unavailable`.
- **iOS 14.0 to 14.2** cannot use the camera inside a `WKWebView`; the page reports
  `camera_unavailable`. Capture works from iOS 14.3.

## License

MIT, see [LICENSE](LICENSE).
