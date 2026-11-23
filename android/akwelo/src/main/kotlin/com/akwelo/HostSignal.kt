package com.akwelo

import android.view.Display

/**
 * The capture environment report the hosted page receives through `window.AkweloHost.signal(...)`
 * (after every load and on every change) and, for the first value, as `env=` in the fragment:
 * `{"screen_capture":"active|inactive","source":"android"[,"screen_capture_seen":true]}`.
 * Evidence for Akwelo's server, never a verdict.
 */
internal object HostSignal {
    const val SOURCE = "android"

    /** Fixed keys and values, so the JSON is written by hand in a stable order. */
    fun json(active: Boolean, seen: Boolean): String = buildString {
        append("""{"screen_capture":"""").append(if (active) "active" else "inactive")
        append("""","source":"""").append(SOURCE).append('"')
        if (seen) append(""","screen_capture_seen":true""")
        append('}')
    }

    /** base64url JSON without padding, for `env=`. */
    fun env(active: Boolean, seen: Boolean): String = base64Url(json(active, seen).toByteArray(Charsets.UTF_8))

    /** JavaScript that hands the report to the page; it never throws, whatever state the page is in. */
    fun script(active: Boolean, seen: Boolean): String =
        "try{window.AkweloHost&&window.AkweloHost.signal(${json(active, seen)})}catch(e){}"

    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    // java.util.Base64 needs API 26 and android.util.Base64 is a stub in unit tests.
    private fun base64Url(bytes: ByteArray): String = buildString {
        var i = 0
        while (i < bytes.size) {
            val n = ((bytes[i].toInt() and 0xFF) shl 16) or
                ((bytes.getOrElse(i + 1) { 0 }.toInt() and 0xFF) shl 8) or
                (bytes.getOrElse(i + 2) { 0 }.toInt() and 0xFF)
            val chars = minOf(4, ((bytes.size - i) * 8 + 5) / 6)
            for (k in 0 until chars) append(ALPHABET[(n shr (18 - 6 * k)) and 63])
            i += 3
        }
    }
}

/**
 * Screen capture as last observed, and whether any was seen since the capture screen opened.
 *
 * [complete] says whether an `inactive` can be known: only with the API 35+ screen recording
 * callback. Below that, recorders, Cast mirroring and remote-access apps use a private
 * MediaProjection display other apps cannot see, so nothing is reported until something is seen
 * (a presentation display or a screenshot), and Akwelo records `unknown`.
 */
internal class HostSignalState(var complete: Boolean = false) {
    var active: Boolean? = null
        private set
    var seen = false
        private set

    /** Records an observation; answers whether what the page should hear changed. */
    fun set(value: Boolean): Boolean {
        val changed = active != value || (value && !seen)
        active = value
        if (value) seen = true
        return changed
    }

    /** A capture happened without changing the current state (a screenshot); answers whether that is news. */
    fun markSeen(): Boolean {
        if (seen) return false
        seen = true
        if (active == null) active = false // seen, though no live state was known
        return true
    }

    private val reported: Boolean? get() = active?.takeIf { complete || seen }

    fun json(): String? = reported?.let { HostSignal.json(it, seen) }
    fun script(): String? = reported?.let { HostSignal.script(it, seen) }
    fun env(): String? = reported?.let { HostSignal.env(it, seen) }
}

internal object CaptureDisplays {
    /** What [mirrored] needs of an `android.view.Display`, so the rule is testable off-device. */
    data class Info(val id: Int, val flags: Int, val state: Int)

    /**
     * Whether the screen the activity is on is copied elsewhere: another display (not the
     * activity's own, not the built-in panel) that is on and is either a presentation display
     * (HDMI, Miracast, Smart View) or a public virtual display. With the activity on an external
     * monitor (Samsung DeX, desktop windowing, a secondary built-in display), that monitor is where
     * the selfie is shown, and the phone's own panel being on does not mirror it.
     */
    fun mirrored(ownDisplayId: Int, displays: List<Info>): Boolean =
        displays.any { counts(ownDisplayId, it.id, it.flags, it.state) }

    /** On and showing content; OFF, DOZE (always-on), DOZE_SUSPEND and UNKNOWN are not. */
    private fun isOn(state: Int): Boolean =
        state == Display.STATE_ON || state == Display.STATE_VR || state == Display.STATE_ON_SUSPEND

    fun counts(ownDisplayId: Int, displayId: Int, flags: Int, state: Int): Boolean =
        displayId != ownDisplayId &&
            displayId != Display.DEFAULT_DISPLAY &&
            isOn(state) &&
            ((flags and Display.FLAG_PRESENTATION) != 0 || (flags and Display.FLAG_PRIVATE) == 0)
}
