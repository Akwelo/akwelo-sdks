# Akwelo Android SDK

Kotlin library that opens Akwelo's hosted selfie capture page in a WebView and returns the outcome.

Maven coordinates: `com.akwelo:akwelo-android`.
**Note:** until the `akwelo.com` namespace is verified on Maven Central, the artifact is published
as `io.github.akwelo:akwelo-android`. Use that group ID for now.

## Install

```kotlin
// settings.gradle.kts: mavenCentral() must be in your repositories
dependencies {
    implementation("io.github.akwelo:akwelo-android:0.2.0") // later: com.akwelo:akwelo-android
}
```

minSdk 24. The library manifest adds `INTERNET` and `CAMERA`; camera permission is requested at
runtime only when the page asks for it.

## Usage

```kotlin
// 1. Your backend creates a session with your secret key and returns its sessionToken.
// 2. In the app (recommended): the result reaches you even if Android recreated your Activity,
//    or restarted your process, while the capture screen was open.
private val verify = registerForActivityResult(AkweloVerifyContract()) { result ->
    when (result.status) {
        VerifyStatus.SUBMITTED -> showPending(result.sessionId) // decision arrives at your backend
        VerifyStatus.CANCELLED -> showRetry()
        VerifyStatus.ERROR -> showError(result.error, result.errorMessage) // error is a stable code
    }
}
verify.launch(AkweloVerifyRequest(sessionToken))

// Or with a callback. It is invoked exactly once on the main thread while your process lives;
// it cannot survive Android killing the process while the capture screen is open.
Akwelo.verify(activity, sessionToken) { result -> }

// Optional configuration
AkweloVerifyRequest(
    sessionToken,
    AkweloOptions(baseUrl = "https://flow.akwelo.com", playIntegrityCloudProjectNumber = null),
)
```

`SUBMITTED` means capture finished, not that the user passed. Fetch the decision server side.
With `ERROR`, `result.error` is a code from the [list in the root README](../README.md#error-codes).

What the screen does for you: it stays alive across rotation, dark-mode and font-size changes
(no reload, no lost attempt); a page that cannot load or a WebView process that dies ends in an
`ERROR` result instead of a blank page or a crash of your app; links the person taps open in
their browser; back cancels.

## Device attestation (Play Integrity)

Set `playIntegrityCloudProjectNumber` to send a Play Integrity token (nonce = SHA-256 of the
session token) to the page as `attest=`. Use the **Cloud project number Akwelo gives you**, not
your own Google Cloud project's: Akwelo decodes the token, and Google lets only the project that
requested a token decode it. Your app must be distributed through Google Play for Play Integrity to
answer. See the root README's [Status and limits](../README.md#status-and-limits) for what Akwelo
does with the token today. Attestation is best-effort: a failure, or no token within 5 seconds, loads the page without it.

## Screen capture

While the capture screen is open the SDK tells the page whether the screen is being captured, and
Akwelo sends a session captured that way to review. No setup: the library manifest adds the
install-time permissions `DETECT_SCREEN_RECORDING` and `DETECT_SCREEN_CAPTURE`.

- Android 15+: screen recording and projection of the app
  (`WindowManager.addScreenRecordingCallback`), so an `inactive` is reported too.
- Android 14: a screenshot marks capture as seen for the attempt (`screen_capture_seen`).
- Every version: an external presentation display (HDMI, Miracast, Smart View) showing the screen
  the capture is on. This is `active` while it lasts. With the capture itself on an external
  monitor (Samsung DeX, desktop windowing), that monitor and the phone's own panel do not count.

Screen recorders, Cast mirroring and remote-access apps (AnyDesk, TeamViewer) are not detectable
on Android 14 and below: they use a private display other apps cannot see. There the session
reports nothing unless a presentation display or a screenshot is seen, and Akwelo records the
capture environment as `unknown`, never as "not detected".

The SDK does not set `FLAG_SECURE`; the screen can still be captured, and that is reported.

## Development

```
gradle :akwelo:testDebugUnitTest   # needs the Android SDK (ANDROID_HOME)
```
