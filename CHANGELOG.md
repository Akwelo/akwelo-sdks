# Changelog

All four SDKs share a version.

## 0.2.0

Reliability release. The public entry points are unchanged; `VerifyResult` gains `errorMessage`
and `result.error` is now always a stable code (it used to be free text, or lost).

### New in every SDK
- **Screen capture is reported.** Recording, mirroring or sharing the screen while the selfie is
  taken is a sign of coaching or a remote-access scam. The SDK sends it to the capture page
  (`window.AkweloHost.signal`, and `env=` in the fragment) and Akwelo sends such a session to
  review. iOS uses `UIScreen.isCaptured`. Android 15+ detects screen recording and projection of
  the app; Android 14 detects screenshots (as `screen_capture_seen`); all versions detect an
  external presentation display (HDMI, Miracast, Smart View). Screen recorders, Cast mirroring and
  remote-access apps are not detectable on Android 14 and below, where the session reports nothing
  unless one of those is seen (Akwelo records `unknown`). React Native and Flutter take `screenCaptureActive` (and Flutter `watchScreenCapture`) from your app's native code.
  `FLAG_SECURE` is not set. Android adds the install-time permissions `DETECT_SCREEN_RECORDING`
  and `DETECT_SCREEN_CAPTURE`.

### Fixed in every SDK
- **Error details from the capture page were lost or garbled.** The page sends
  `error: { code, message }`; the SDKs expected a string. iOS, React Native and Flutter dropped
  it; Android returned the raw JSON text, and the text `"null"` as the session id of a cancelled
  capture. `error` is now the code and `errorMessage` the text.
- **A capture could end without a result.** A page that failed to load, answered with an HTTP
  error, or whose web process died left a blank screen (and, on iOS, no way to close it). Each
  now ends in an `error` result: `page_load_failed` or `webview_crashed`.
- **Links in the page did nothing.** The privacy notice and help links now open in the system
  browser; the WebView itself still never leaves the Akwelo origin.
- **A slow attestation provider blocked the capture page.** It is skipped after 5 seconds.
- **A second `verify` call disturbed the first.** It now gets `already_in_progress`.
- `baseUrl` must be https (http only for a development server on the same machine); anything else
  is refused with `invalid_base_url` instead of opening a screen that can never finish.
- Documentation describes device attestation: Akwelo verifies the token, and a session that
  expected attestation without a verified one goes to review.

### Android
- `playIntegrityCloudProjectNumber` is the Cloud project number Akwelo gives you, not your own
  project's: Akwelo decodes the token. The documentation said otherwise.
- A dead WebView process no longer takes the host app down with it.
- The capture screen is no longer reloaded (costing an attempt) on dark-mode, font-size, locale,
  keyboard or multi-window changes.
- New `AkweloVerifyContract` (Activity Result API): the result survives Activity recreation and
  process death, which a callback cannot.
- WebView's own error page, which prints the URL and with it the session token, is never shown.
- The page stays clear of system bars and the camera cutout under edge-to-edge (Android 15+).

### iOS
- `verify` could wait forever when the presenting view controller was off screen or already
  presenting: UIKit ignores the `present` call and nothing ever called back. It now returns
  `presentation_failed`. A result that arrives while the screen is still animating in is now
  delivered after the animation instead of relying on a dismiss UIKit may drop.
- A native close button: a full-screen modal had no way out if the page did not draw.
- `missing_camera_usage_description` instead of a crash when the Info.plist key is absent.

### React Native
- A close button in the modal; `npm pack` now builds `dist` first.

### Flutter
- The minimum Flutter version was wrong (3.19): the code and its dependencies need 3.24.
- The page no longer uses Material widgets, so it also runs in Cupertino-only apps.
- New dependency: `url_launcher`, to open tapped links in the browser.
