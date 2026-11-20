package com.akwelo

import java.net.URLEncoder

data class AkweloOptions(
    /** Hosted capture origin. Override for staging or self-hosted deployments. */
    val baseUrl: String = DEFAULT_BASE_URL,
    /**
     * Google Cloud project number linked to your app in the Play Console. When set, a Play Integrity
     * token is requested and passed to the page as `attest=`. Null disables attestation.
     * TODO(akwelo): requires a real Play Console + Google Cloud project; not configured yet.
     */
    val playIntegrityCloudProjectNumber: Long? = null,
) {
    companion object {
        const val DEFAULT_BASE_URL = "https://flow.akwelo.com"
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

    private fun encode(v: String) = URLEncoder.encode(v, "UTF-8").replace("+", "%20")
}
