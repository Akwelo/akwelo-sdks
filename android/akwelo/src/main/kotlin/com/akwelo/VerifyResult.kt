package com.akwelo

import android.content.Intent
import org.json.JSONException
import org.json.JSONObject

/** Capture outcome reported by the hosted page. The verification decision is delivered to your backend. */
enum class VerifyStatus { SUBMITTED, CANCELLED, ERROR }

data class VerifyResult(
    val status: VerifyStatus,
    val sessionId: String? = null,
    /** Stable error code when [status] is [VerifyStatus.ERROR], for example `camera_unavailable`. See README. */
    val error: String? = null,
    /** Text for a person, in the page's language when the page reported the error. */
    val errorMessage: String? = null,
) {
    internal fun toIntent(): Intent = Intent()
        .putExtra(EXTRA_STATUS, status.name)
        .putExtra(EXTRA_SESSION_ID, sessionId)
        .putExtra(EXTRA_ERROR, error)
        .putExtra(EXTRA_ERROR_MESSAGE, errorMessage)

    companion object {
        const val MESSAGE_TYPE = "akwelo.verify.result"
        private const val EXTRA_STATUS = "akwelo.result.status"
        private const val EXTRA_SESSION_ID = "akwelo.result.sessionId"
        private const val EXTRA_ERROR = "akwelo.result.error"
        private const val EXTRA_ERROR_MESSAGE = "akwelo.result.errorMessage"

        /**
         * Parses a bridge message. Returns null for messages that are not an Akwelo result.
         * The page sends `error` as `{code, message}`; a bare string is read as the code.
         *
         * Values are read with `opt` and a type check, never `optString`/`getString`: Android's
         * org.json turns a JSON null into the text "null" and an object into its JSON text.
         */
        @JvmStatic
        fun parse(json: String?): VerifyResult? {
            if (json.isNullOrBlank()) return null
            return try {
                val obj = JSONObject(json)
                if (obj.opt("type") != MESSAGE_TYPE) return null
                val status = when (obj.opt("status")) {
                    "submitted" -> VerifyStatus.SUBMITTED
                    "cancelled" -> VerifyStatus.CANCELLED
                    "error" -> VerifyStatus.ERROR
                    else -> return null
                }
                var code: String? = null
                var message: String? = null
                when (val e = obj.opt("error")) {
                    is String -> code = e.text()
                    is JSONObject -> {
                        code = (e.opt("code") as? String).text()
                        message = (e.opt("message") as? String).text()
                    }
                }
                // An error always carries a code, so callers can switch on it.
                if (status == VerifyStatus.ERROR && code == null) code = "unknown_error"
                VerifyResult(status, (obj.opt("sessionId") as? String).text(), code, message)
            } catch (e: JSONException) {
                null
            }
        }

        private fun String?.text(): String? = this?.takeIf { it.isNotEmpty() }

        /** The result an [AkweloVerifyActivity] finished with; null when it set none. */
        internal fun fromIntent(intent: Intent?): VerifyResult? {
            val name = intent?.getStringExtra(EXTRA_STATUS) ?: return null
            val status = VerifyStatus.values().firstOrNull { it.name == name } ?: return null
            return VerifyResult(
                status,
                intent.getStringExtra(EXTRA_SESSION_ID),
                intent.getStringExtra(EXTRA_ERROR),
                intent.getStringExtra(EXTRA_ERROR_MESSAGE),
            )
        }

        internal fun cancelled() = VerifyResult(VerifyStatus.CANCELLED)

        /** An SDK-side failure, in the same shape as one the page reports. */
        internal fun error(code: String, message: String) =
            VerifyResult(VerifyStatus.ERROR, error = code, errorMessage = message)
    }
}
