package com.akwelo

import org.json.JSONException
import org.json.JSONObject

/** Capture outcome reported by the hosted page. The verification decision is delivered to your backend. */
enum class VerifyStatus { SUBMITTED, CANCELLED, ERROR }

data class VerifyResult(
    val status: VerifyStatus,
    val sessionId: String? = null,
    val error: String? = null,
) {
    companion object {
        const val MESSAGE_TYPE = "akwelo.verify.result"

        /** Parses a bridge message. Returns null for messages that are not an Akwelo result. */
        @JvmStatic
        fun parse(json: String?): VerifyResult? {
            if (json.isNullOrBlank()) return null
            return try {
                val obj = JSONObject(json)
                if (obj.optString("type") != MESSAGE_TYPE) return null
                val status = when (obj.optString("status")) {
                    "submitted" -> VerifyStatus.SUBMITTED
                    "cancelled" -> VerifyStatus.CANCELLED
                    "error" -> VerifyStatus.ERROR
                    else -> return null
                }
                VerifyResult(
                    status = status,
                    sessionId = obj.optString("sessionId").ifEmpty { null },
                    error = if (obj.has("error") && !obj.isNull("error")) obj.getString("error") else null,
                )
            } catch (e: JSONException) {
                null
            }
        }

        internal fun cancelled() = VerifyResult(VerifyStatus.CANCELLED)
        internal fun error(message: String) = VerifyResult(VerifyStatus.ERROR, error = message)
    }
}
