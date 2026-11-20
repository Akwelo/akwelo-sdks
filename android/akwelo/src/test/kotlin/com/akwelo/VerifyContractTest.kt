package com.akwelo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VerifyContractTest {
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

    @Test fun ignoresForeignOrMalformed() {
        assertNull(VerifyResult.parse("""{"type":"other","status":"submitted"}"""))
        assertNull(VerifyResult.parse("""{"type":"akwelo.verify.result","status":"approved"}"""))
        assertNull(VerifyResult.parse("not json"))
        assertNull(VerifyResult.parse(null))
    }
}
