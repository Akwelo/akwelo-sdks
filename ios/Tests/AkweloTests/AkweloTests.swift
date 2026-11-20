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

    func testIgnoresForeign() {
        XCTAssertNil(VerifyResult.parse(#"{"type":"x","status":"submitted"}"#))
        XCTAssertNil(VerifyResult.parse(#"{"type":"akwelo.verify.result","status":"approved"}"#))
        XCTAssertNil(VerifyResult.parse("nope"))
        XCTAssertNil(VerifyResult.parse(nil))
    }
}
