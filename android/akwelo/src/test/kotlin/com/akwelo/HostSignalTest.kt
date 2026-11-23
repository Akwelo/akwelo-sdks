package com.akwelo

import android.view.Display
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class HostSignalTest {
    @Test fun payloadJson() {
        assertEquals("""{"screen_capture":"active","source":"android"}""", HostSignal.json(active = true, seen = false))
        assertEquals(
            """{"screen_capture":"inactive","source":"android","screen_capture_seen":true}""",
            HostSignal.json(active = false, seen = true),
        )
    }

    /** Decoded the way the hosted page does (readHostEnv in apps/flow): base64url, padding optional. */
    @Test fun envFragmentIsBase64UrlJson() {
        for (seen in listOf(false, true)) for (active in listOf(false, true)) {
            val env = HostSignal.env(active, seen)
            assertTrue(env, Regex("^[A-Za-z0-9_-]+$").matches(env))
            assertEquals(HostSignal.json(active, seen), String(Base64.getUrlDecoder().decode(env)))
        }
        val env = HostSignal.env(active = true, seen = true)
        assertEquals(
            "https://flow.akwelo.com/verify/selfie#token=abc&env=$env",
            VerifyUrl.build(AkweloOptions.DEFAULT_BASE_URL, "abc", null, env),
        )
    }

    @Test fun scriptNeverThrowsInThePage() {
        assertEquals(
            """try{window.AkweloHost&&window.AkweloHost.signal({"screen_capture":"inactive","source":"android"})}catch(e){}""",
            HostSignal.script(active = false, seen = false),
        )
    }

    @Test fun stateReportsChangesAndRemembersACapture() {
        val s = HostSignalState(complete = true)
        assertNull(s.script())
        assertTrue(s.set(false))
        assertFalse(s.set(false))
        assertFalse(s.seen)
        assertTrue(s.set(true))
        assertFalse(s.set(true))
        assertTrue(s.set(false))
        assertTrue(s.seen) // kept after the capture stopped
        assertEquals(HostSignal.script(active = false, seen = true), s.script())
        assertFalse(s.markSeen())
    }

    /** API 34 screenshot: seen, with screen_capture unchanged rather than claiming active. */
    @Test fun aScreenshotIsSeenNotActive() {
        val s = HostSignalState(complete = true)
        s.set(false)
        assertTrue(s.markSeen())
        assertEquals(false, s.active)
        assertEquals("""{"screen_capture":"inactive","source":"android","screen_capture_seen":true}""", s.json())
    }

    @Test fun whichDisplaysCountAsCapture() {
        val on = Display.STATE_ON
        val own = Display.DEFAULT_DISPLAY
        assertFalse(CaptureDisplays.counts(own, Display.DEFAULT_DISPLAY, Display.FLAG_PRESENTATION, on))
        assertTrue(CaptureDisplays.counts(own, 2, Display.FLAG_PRESENTATION, on)) // HDMI, Miracast, Chromecast mirror
        assertTrue(CaptureDisplays.counts(own, 3, 0, on)) // a public virtual display (screen mirroring)
        assertFalse(CaptureDisplays.counts(own, 4, Display.FLAG_PRIVATE, on)) // another app's own surface
        assertFalse(CaptureDisplays.counts(own, 2, Display.FLAG_PRESENTATION, Display.STATE_OFF))
    }

    /** Only a display that is on shows a copy: dozing (always-on), suspended-doze and unknown do not. */
    @Test fun onlyADisplayThatIsOnCounts() {
        val p = Display.FLAG_PRESENTATION
        for (state in listOf(Display.STATE_ON, Display.STATE_VR, Display.STATE_ON_SUSPEND)) {
            assertTrue("state $state", CaptureDisplays.counts(0, 2, p, state))
        }
        for (state in listOf(Display.STATE_OFF, Display.STATE_DOZE, Display.STATE_DOZE_SUSPEND, Display.STATE_UNKNOWN)) {
            assertFalse("state $state", CaptureDisplays.counts(0, 2, p, state))
        }
    }

    private fun d(id: Int, flags: Int = 0, state: Int = Display.STATE_ON) = CaptureDisplays.Info(id, flags, state)

    @Test fun phoneScreenWithAPresentationDisplayIsMirrored() {
        assertTrue(CaptureDisplays.mirrored(0, listOf(d(0), d(2, Display.FLAG_PRESENTATION))))
    }

    /** DeX or desktop windowing: the activity is on the monitor. Neither the monitor nor the phone panel mirrors it. */
    @Test fun activityOnTheExternalMonitorIsNotMirrored() {
        assertFalse(CaptureDisplays.mirrored(2, listOf(d(0), d(2, Display.FLAG_PRESENTATION))))
        assertFalse(CaptureDisplays.mirrored(2, listOf(d(2, Display.FLAG_PRESENTATION))))
        assertFalse(CaptureDisplays.mirrored(2, listOf(d(2))))
        // A further display besides the activity's own still counts.
        assertTrue(CaptureDisplays.mirrored(2, listOf(d(0), d(2, Display.FLAG_PRESENTATION), d(3, Display.FLAG_PRESENTATION))))
    }

    /** Below API 35 an `inactive` cannot be known (recorders, Cast, remote access are invisible): report nothing. */
    @Test fun withoutRecordingDetectionNothingIsReportedUntilSomethingIsSeen() {
        val s = HostSignalState(complete = false)
        s.set(false)
        assertNull(s.json())
        assertNull(s.env())
        assertNull(s.script())
        assertTrue(s.set(true))
        assertEquals(HostSignal.json(active = true, seen = true), s.json())
        s.set(false) // presentation display unplugged: the capture was still seen
        assertEquals(HostSignal.json(active = false, seen = true), s.json())
    }

    /** API 34 screenshot with no display detected: report it, even though nothing was known before. */
    @Test fun aScreenshotIsReportedWithoutRecordingDetection() {
        val s = HostSignalState(complete = false)
        s.set(false)
        assertTrue(s.markSeen())
        assertEquals(HostSignal.script(active = false, seen = true), s.script())
        val t = HostSignalState(complete = false) // screenshot before any state was recorded
        assertTrue(t.markSeen())
        assertEquals(HostSignal.json(active = false, seen = true), t.json())
    }
}
