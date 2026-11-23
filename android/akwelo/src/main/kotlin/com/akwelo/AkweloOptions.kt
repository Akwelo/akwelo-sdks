package com.akwelo

import java.net.URI
import java.net.URLEncoder

data class AkweloOptions(
    /**
     * Hosted capture origin. Override for staging or self-hosted deployments. Must be https
     * (plain http is accepted only for a development server on this machine or the emulator host).
     */
    val baseUrl: String = DEFAULT_BASE_URL,
    /**
     * Google Cloud project number linked to your app in the Play Console. When set, a Play Integrity
     * token is requested and passed to the page as `attest=`. Null disables attestation. Capture
     * never waits on it: no token within [ATTESTATION_TIMEOUT_MS] means the page loads without one.
     * TODO(akwelo): requires a real Play Console + Google Cloud project; not configured yet.
     */
    val playIntegrityCloudProjectNumber: Long? = null,
) {
    companion object {
        const val DEFAULT_BASE_URL = "https://flow.akwelo.com"

        /** How long capture waits for an attestation token before starting without one. */
        const val ATTESTATION_TIMEOUT_MS = 5000L
    }
}

object VerifyUrl {
    /** Builds `{baseUrl}/verify/selfie#token=...[&attest=...]`. Secrets stay in the fragment. */
    @JvmStatic
    fun build(baseUrl: String, sessionToken: String, attestationToken: String? = null): String {
        require(sessionToken.isNotBlank()) { "sessionToken must not be blank" }
        val base = baseUrl.trimEnd('/')
        val sb = StringBuilder(base).append("/verify/selfie#token=").append(encode(sessionToken))
        if (!attestationToken.isNullOrEmpty()) sb.append("&attest=").append(encode(attestationToken))
        return sb.toString()
    }

    /** `scheme://host[:port]` of [url], lower-cased, or null if it has no host. Used for exact-origin checks. */
    @JvmStatic
    fun origin(url: String?): String? {
        if (url.isNullOrBlank()) return null
        val u = try { URI(url.trim()) } catch (_: Exception) { return null }
        val scheme = u.scheme?.lowercase() ?: return null
        val host = u.host?.lowercase() ?: return null
        if (u.rawUserInfo != null) return null
        val defaultPort = (scheme == "https" && u.port == 443) || (scheme == "http" && u.port == 80)
        return if (u.port == -1 || defaultPort) "$scheme://$host" else "$scheme://$host:${u.port}"
    }

    @JvmStatic
    fun isTrusted(url: String?, baseUrl: String): Boolean {
        val o = origin(url) ?: return false
        return o == origin(baseUrl)
    }

    private val LOCAL_HOSTS = setOf("localhost", "127.0.0.1", "10.0.2.2", "[::1]")

    /**
     * The origin of a usable `baseUrl`, or null. The page handles a camera and a session token, so
     * it must be https; plain http is accepted only for a development server on this machine.
     */
    @JvmStatic
    fun validBaseOrigin(baseUrl: String?): String? {
        val o = origin(baseUrl) ?: return null
        if (o.startsWith("https://")) return o
        if (!o.startsWith("http://")) return null
        val host = o.removePrefix("http://").replace(Regex(":\\d+$"), "")
        return if (host in LOCAL_HOSTS) o else null
    }

    private fun encode(v: String) = URLEncoder.encode(v, "UTF-8").replace("+", "%20")
}
