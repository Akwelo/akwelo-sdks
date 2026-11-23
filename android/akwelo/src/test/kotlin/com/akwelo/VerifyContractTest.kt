package com.akwelo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VerifyContractTest {
    @Test fun originCheckIsExact() {
        val base = AkweloOptions.DEFAULT_BASE_URL
        org.junit.Assert.assertTrue(VerifyUrl.isTrusted("https://flow.akwelo.com/verify/selfie#token=x", base))
        org.junit.Assert.assertTrue(VerifyUrl.isTrusted("https://FLOW.akwelo.com:443/", "$base/"))
        org.junit.Assert.assertFalse(VerifyUrl.isTrusted("https://flow.akwelo.com.evil.com/", base))
        org.junit.Assert.assertFalse(VerifyUrl.isTrusted("https://flow.akwelo.com@evil.com/", base))
        org.junit.Assert.assertFalse(VerifyUrl.isTrusted("http://flow.akwelo.com/", base))
        org.junit.Assert.assertFalse(VerifyUrl.isTrusted("https://flow.akwelo.com:8443/", base))
        org.junit.Assert.assertFalse(VerifyUrl.isTrusted(null, base))
    }

    @Test fun buildsDefaultUrl() {
        assertEquals(
            "https://flow.akwelo.com/verify/selfie#token=abc",
            VerifyUrl.build(AkweloOptions.DEFAULT_BASE_URL, "abc"),
        )
    }

    @Test fun trimsTrailingSlashAndEncodes() {
        assertEquals(
            "https://staging.example/verify/selfie#token=a%2Bb%3D&attest=x%20y",
            VerifyUrl.build("https://staging.example/", "a+b=", "x y"),
        )
    }

    @Test(expected = IllegalArgumentException::class) fun rejectsBlankToken() {
        VerifyUrl.build("https://x", " ")
    }

    @Test fun parsesSubmitted() {
        val r = VerifyResult.parse("""{"type":"akwelo.verify.result","sessionId":"s_1","status":"submitted"}""")
        assertEquals(VerifyResult(VerifyStatus.SUBMITTED, "s_1", null), r)
    }

    @Test fun parsesError() {
        val r = VerifyResult.parse("""{"type":"akwelo.verify.result","sessionId":"s_1","status":"error","error":"camera_denied"}""")
        assertEquals(VerifyStatus.ERROR, r?.status)
        assertEquals("camera_denied", r?.error)
    }

    // Exactly what apps/flow postVerifyResult sends: `error` is an object and `sessionId` may be null.
    @Test fun readsTheErrorObjectThePageSends() {
        val r = VerifyResult.parse(
            """{"type":"akwelo.verify.result","sessionId":null,"status":"error",""" +
                """"error":{"code":"camera_unavailable","message":"We could not use your camera."}}"""
        )
        assertEquals(
            VerifyResult(VerifyStatus.ERROR, null, "camera_unavailable", "We could not use your camera."), r
        )
    }

    @Test fun anErrorAlwaysHasACodeAndNullIsNotText() {
        assertEquals("unknown_error", VerifyResult.parse("""{"type":"akwelo.verify.result","status":"error"}""")?.error)
        assertEquals(
            VerifyResult(VerifyStatus.CANCELLED),
            VerifyResult.parse("""{"type":"akwelo.verify.result","status":"cancelled","sessionId":null,"error":null}"""),
        )
        assertNull(VerifyResult.parse("""{"type":"akwelo.verify.result","status":null}"""))
    }

    @Test fun baseUrlMustBeHttpsOrThisMachine() {
        assertEquals("https://flow.akwelo.com", VerifyUrl.validBaseOrigin("https://flow.akwelo.com/"))
        assertEquals("https://staging.example:8443", VerifyUrl.validBaseOrigin("https://staging.example:8443"))
        assertEquals("http://localhost:5173", VerifyUrl.validBaseOrigin("http://localhost:5173"))
        assertEquals("http://10.0.2.2:5173", VerifyUrl.validBaseOrigin("http://10.0.2.2:5173/"))
        for (u in listOf("http://flow.akwelo.com", "http://192.168.1.20:5173", "flow.akwelo.com", "ftp://x", "https://u:p@x.com", "", null)) {
            assertNull(u, VerifyUrl.validBaseOrigin(u))
        }
    }

    @Test fun precheckNamesTheProblemBeforeAnythingOpens() {
        assertNull(precheck("vst_abc", AkweloOptions()))
        assertEquals("invalid_session_token", precheck(" ", AkweloOptions())?.error)
        assertEquals("invalid_session_token", precheck(null, AkweloOptions())?.error)
        assertEquals("invalid_base_url", precheck("vst_abc", AkweloOptions(baseUrl = "http://flow.akwelo.com"))?.error)
        assertEquals(VerifyStatus.ERROR, precheck("", AkweloOptions())?.status)
    }

    @Test fun oneCaptureAtATime() {
        val reg = RequestRegistry<String>()
        assertEquals(RequestRegistry.Claim.Granted<String>(null), reg.claim("a", "first"))
        reg.attached("a")
        assertEquals(RequestRegistry.Claim.Busy, reg.claim("b", "second"))
        assertNull(reg.release("b")) // not the open one: nothing to deliver, nothing disturbed
        assertEquals("first", reg.release("a"))
        assertNull(reg.release("a")) // a result is delivered once
        assertEquals(RequestRegistry.Claim.Granted<String>(null), reg.claim("c", "third"))
    }

    @Test fun aScreenThatNeverOpenedDoesNotBlockTheNextCaptureForever() {
        var now = 0L
        val reg = RequestRegistry<String>(staleAfterMs = 10_000) { now }
        reg.claim("a", "first") // startActivity was refused silently: never attached
        now = 9_999
        assertEquals(RequestRegistry.Claim.Busy, reg.claim("b", "second"))
        now = 10_000
        assertEquals(RequestRegistry.Claim.Granted("first"), reg.claim("b", "second"))
        assertNull(reg.release("a"))
        // An attached screen is never treated as stale, however long the capture takes.
        reg.attached("b")
        now = 3_600_000
        assertEquals(RequestRegistry.Claim.Busy, reg.claim("c", "third"))
        assertEquals("second", reg.release("b"))
    }

    @Test fun ignoresForeignOrMalformed() {
        assertNull(VerifyResult.parse("""{"type":"other","status":"submitted"}"""))
        assertNull(VerifyResult.parse("""{"type":"akwelo.verify.result","status":"approved"}"""))
        assertNull(VerifyResult.parse("not json"))
        assertNull(VerifyResult.parse(null))
    }
}
