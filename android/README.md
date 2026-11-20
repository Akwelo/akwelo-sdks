# Akwelo Android SDK

Kotlin library that opens Akwelo's hosted selfie capture page in a WebView and returns the outcome.

Maven coordinates: `com.akwelo:akwelo-android`.
**Note:** until the `akwelo.com` namespace is verified on Maven Central, the artifact is published
as `io.github.akwelo:akwelo-android`. Use that group ID for now.

## Install

```kotlin
// settings.gradle.kts: mavenCentral() must be in your repositories
dependencies {
    implementation("io.github.akwelo:akwelo-android:0.1.0") // later: com.akwelo:akwelo-android
}
```

minSdk 24. The library manifest adds `INTERNET` and `CAMERA`; camera permission is requested at
runtime only when the page asks for it.

## Usage

```kotlin
// 1. Your backend creates a session with your secret key and returns its sessionToken.
// 2. In the app:
Akwelo.verify(activity, sessionToken) { result ->
    when (result.status) {
        VerifyStatus.SUBMITTED -> showPending(result.sessionId) // decision arrives at your backend
        VerifyStatus.CANCELLED -> showRetry()
        VerifyStatus.ERROR -> showError(result.error)
    }
}

// Optional configuration
Akwelo.verify(
    activity, sessionToken,
    AkweloOptions(baseUrl = "https://flow.akwelo.com", playIntegrityCloudProjectNumber = null),
) { result -> }
```

`SUBMITTED` means capture finished, not that the user passed. Fetch the decision server side.

## Device attestation (Play Integrity)

Set `playIntegrityCloudProjectNumber` to send a Play Integrity token (nonce = SHA-256 of the
session token) to the page as `attest=`. **TODO:** this needs a Play Console app linked to a Google
Cloud project with the Play Integrity API enabled; it has not been tested against real Google
accounts yet. Attestation is best-effort: failures load the page without it.

## Development

```
gradle :akwelo:testDebugUnitTest   # needs the Android SDK (ANDROID_HOME)
```
