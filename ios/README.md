# Akwelo iOS SDK

Swift library that presents Akwelo's hosted selfie capture page in a `WKWebView` and returns the outcome.
iOS 14+, Swift 5.9+.

## Install

**Swift Package Manager:** add `https://github.com/akwelo/akwelo-sdks` and pick the `Akwelo` product.
(SPM resolves the root `Package.swift`, which points at `ios/Sources`; `ios/Package.swift` is for local work.)

**CocoaPods:**

```ruby
pod 'Akwelo', '~> 0.2'
```

Add to your app's Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>We use the camera to verify your identity.</string>
```

Without it iOS terminates an app that asks for the camera, so `verify` checks first and returns
`missing_camera_usage_description` instead of opening the capture screen.

## Usage

```swift
import Akwelo

// sessionToken comes from your backend, which created the session with your secret key.
let result = try await Akwelo.verify(sessionToken: token, from: self)
switch result.status {
case .submitted: showPending(result.sessionId)   // decision arrives at your backend
case .cancelled: showRetry()
case .error:     showError(result.error, result.errorMessage)   // error is a stable code
}

// Options
let options = AkweloOptions(baseURL: URL(string: "https://flow.akwelo.com")!, useAppAttest: false)
```

A completion-handler overload exists for non-async code. `submitted` only means capture finished.

`verify` throws only for arguments that can never work: a blank token (`invalidSessionToken`) or a
base URL that is not https (`invalidBaseURL`). Everything that goes wrong at run time comes back as
a result with status `.error` and a code from the [list in the root README](../README.md#error-codes).
Call it from a view controller that is on screen and not already presenting; otherwise it returns
`presentation_failed`.

The capture screen is a full-screen modal with a close button that always works, so a page that
cannot load can never trap the person. A page that fails to load, answers with an HTTP error, or
whose web process dies ends in an `.error` result. Links the person taps open in Safari.
Camera capture inside a `WKWebView` needs iOS 14.3 or later.

## Device attestation (App Attest)

`useAppAttest: true` sends an App Attest attestation (clientDataHash = SHA-256 of the session token)
as `attest=`. **Akwelo stores it and does not verify it with Apple yet, so today it adds no
protection.** It is best-effort: a failure, or no attestation within 5 seconds, loads the page
without it. **TODO:** requires an Apple Developer team with the App Attest capability, the
`com.apple.developer.devicecheck.appattest-environment` entitlement, and backend verification. Not
tested on real devices yet; failures fall back to loading without attestation.

## Development

```
cd ios && swift build && swift test   # Foundation-only logic; the UIKit screen is skipped off Apple platforms
xcodebuild test -scheme Akwelo -destination 'platform=iOS Simulator,name=iPhone 16'   # from the repo root, on macOS
```
