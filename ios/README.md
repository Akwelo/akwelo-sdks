# Akwelo iOS SDK

Swift library that presents Akwelo's hosted selfie capture page in a `WKWebView` and returns the outcome.
iOS 14+, Swift 5.9+.

## Install

**Swift Package Manager:** add `https://github.com/akwelo/akwelo-sdks` and pick the `Akwelo` product.
(SPM resolves the root `Package.swift`, which points at `ios/Sources`; `ios/Package.swift` is for local work.)

**CocoaPods:**

```ruby
pod 'Akwelo', '~> 0.1'
```

Add to your app's Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>We use the camera to verify your identity.</string>
```

## Usage

```swift
import Akwelo

// sessionToken comes from your backend, which created the session with your secret key.
let result = try await Akwelo.verify(sessionToken: token, from: self)
switch result.status {
case .submitted: showPending(result.sessionId)   // decision arrives at your backend
case .cancelled: showRetry()
case .error:     showError(result.error)
}

// Options
let options = AkweloOptions(baseURL: URL(string: "https://flow.akwelo.com")!, useAppAttest: false)
```

A completion-handler overload exists for non-async code. `submitted` only means capture finished.

## Device attestation (App Attest)

`useAppAttest: true` sends an App Attest attestation (clientDataHash = SHA-256 of the session token)
as `attest=`. **TODO:** requires an Apple Developer team with the App Attest capability, the
`com.apple.developer.devicecheck.appattest-environment` entitlement, and backend verification. Not
tested on real devices yet; failures fall back to loading without attestation.

## Development

```
cd ios && swift build && swift test   # on macOS with Xcode; UIKit code is skipped on Linux
```
