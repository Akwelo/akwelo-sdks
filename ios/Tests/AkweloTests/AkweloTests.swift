import XCTest
@testable import Akwelo

final class AkweloTests: XCTestCase {
    func testOriginCheckIsExact() {
        let base = AkweloOptions.defaultBaseURL
        XCTAssertTrue(VerifyURL.isTrusted(URL(string: "https://flow.akwelo.com/verify/selfie#token=x"), base: base))
        XCTAssertTrue(VerifyURL.isTrusted(URL(string: "https://FLOW.akwelo.com:443/"), base: base))
        XCTAssertFalse(VerifyURL.isTrusted(URL(string: "https://flow.akwelo.com.evil.com/"), base: base))
        XCTAssertFalse(VerifyURL.isTrusted(URL(string: "https://flow.akwelo.com@evil.com/"), base: base))
        XCTAssertFalse(VerifyURL.isTrusted(URL(string: "http://flow.akwelo.com/"), base: base))
        XCTAssertFalse(VerifyURL.isTrusted(nil, base: base))
    }

    func testDefaultURL() throws {
        let url = try VerifyURL.build(baseURL: AkweloOptions.defaultBaseURL, sessionToken: "abc")
        XCTAssertEqual(url.absoluteString, "https://flow.akwelo.com/verify/selfie#token=abc")
    }

    func testTrimsSlashAndEncodes() throws {
        let url = try VerifyURL.build(baseURL: URL(string: "https://staging.example/")!,
                                      sessionToken: "a+b=", attestation: "x y")
        XCTAssertEqual(url.absoluteString, "https://staging.example/verify/selfie#token=a%2Bb%3D&attest=x%20y")
    }

    func testRejectsBlankToken() {
        XCTAssertThrowsError(try VerifyURL.build(baseURL: AkweloOptions.defaultBaseURL, sessionToken: "  "))
    }

    func testParsesStringAndDictionary() {
        let json = #"{"type":"akwelo.verify.result","sessionId":"s_1","status":"submitted"}"#
        XCTAssertEqual(VerifyResult.parse(json), VerifyResult(status: .submitted, sessionId: "s_1"))
        let dict: [String: Any] = ["type": "akwelo.verify.result", "sessionId": "s_1", "status": "error", "error": "camera_denied"]
        XCTAssertEqual(VerifyResult.parse(dict)?.error, "camera_denied")
    }

    // Exactly what apps/flow postVerifyResult sends: `error` is an object and `sessionId` may be null.
    func testReadsTheErrorObjectThePageSends() {
        let want = VerifyResult(status: .error, error: "camera_unavailable", errorMessage: "We could not use your camera.")
        let json = #"{"type":"akwelo.verify.result","sessionId":null,"status":"error","error":{"code":"camera_unavailable","message":"We could not use your camera."}}"#
        XCTAssertEqual(VerifyResult.parse(json), want)
        // WKWebView hands over a decoded dictionary, with NSNull for null.
        let dict: [String: Any] = [
            "type": "akwelo.verify.result", "sessionId": NSNull(), "status": "error",
            "error": ["code": "camera_unavailable", "message": "We could not use your camera."],
        ]
        XCTAssertEqual(VerifyResult.parse(dict), want)
    }

    func testAnErrorAlwaysHasACode() {
        XCTAssertEqual(VerifyResult.parse(#"{"type":"akwelo.verify.result","status":"error"}"#)?.error, "unknown_error")
        XCTAssertEqual(VerifyResult.parse(#"{"type":"akwelo.verify.result","status":"cancelled","sessionId":null}"#),
                       VerifyResult(status: .cancelled))
    }

    func testBaseURLMustBeHTTPSOrThisMachine() {
        XCTAssertEqual(VerifyURL.validBaseOrigin(URL(string: "https://flow.akwelo.com/")), "https://flow.akwelo.com")
        XCTAssertEqual(VerifyURL.validBaseOrigin(URL(string: "https://staging.example:8443")), "https://staging.example:8443")
        XCTAssertEqual(VerifyURL.validBaseOrigin(URL(string: "http://localhost:5173")), "http://localhost:5173")
        for bad in ["http://flow.akwelo.com", "http://192.168.1.20:5173", "flow.akwelo.com", "ftp://x", "https://u:p@x.com"] {
            XCTAssertNil(VerifyURL.validBaseOrigin(URL(string: bad)), bad)
        }
        XCTAssertNil(VerifyURL.validBaseOrigin(nil))
    }

    func testLoadFailures() {
        let base = AkweloOptions.defaultBaseURL
        let page = URL(string: "https://flow.akwelo.com/verify/selfie")
        func result(_ domain: String, _ code: Int, _ url: URL?) -> VerifyResult? {
            VerifyURL.resultForLoadError(domain: domain, code: code, failingURL: url, base: base)
        }
        // The capture page did not load: offline, DNS, TLS.
        XCTAssertEqual(result(NSURLErrorDomain, NSURLErrorNotConnectedToInternet, page)?.error, "page_load_failed")
        XCTAssertEqual(result(NSURLErrorDomain, NSURLErrorTimedOut, nil)?.error, "page_load_failed")
        // A navigation the SDK itself stopped, or a tapped link that did not open, is not a failure.
        XCTAssertNil(result(NSURLErrorDomain, NSURLErrorCancelled, page))
        XCTAssertNil(result("WebKitErrorDomain", 102, page))
        XCTAssertNil(result(NSURLErrorDomain, NSURLErrorNotConnectedToInternet, URL(string: "https://akwelo.com/privacy")))
    }

    func testTimeoutDoesNotWaitForWorkThatNeverAnswers() async {
        let started = Date()
        let late: String? = await firstResult(within: 0.05) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return "late"
        }
        XCTAssertNil(late)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        let quick: String? = await firstResult(within: 5) { "quick" }
        XCTAssertEqual(quick, "quick")
        let none: String? = await firstResult(within: 5) { nil }
        XCTAssertNil(none)
    }

    func testIgnoresForeign() {
        XCTAssertNil(VerifyResult.parse(#"{"type":"x","status":"submitted"}"#))
        XCTAssertNil(VerifyResult.parse(#"{"type":"akwelo.verify.result","status":"approved"}"#))
        XCTAssertNil(VerifyResult.parse("nope"))
        XCTAssertNil(VerifyResult.parse(nil))
    }
}
