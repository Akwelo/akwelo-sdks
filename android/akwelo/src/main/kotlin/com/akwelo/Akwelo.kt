package com.akwelo

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.activity.result.contract.ActivityResultContract
import java.util.UUID

/**
 * Entry point.
 *
 * ```
 * Akwelo.verify(activity, sessionToken) { result -> ... }
 * ```
 * The callback is invoked exactly once, on the main thread, for as long as your app's process
 * lives. If Android kills the process while the capture screen is open, a callback cannot
 * survive: use [AkweloVerifyContract] with `registerForActivityResult` to get the result then too.
 *
 * One capture at a time: a call made while another is open gets `already_in_progress` at once and
 * leaves the open one untouched.
 */
object Akwelo {
    private val main = Handler(Looper.getMainLooper())
    private val requests = RequestRegistry<(VerifyResult) -> Unit>()

    @JvmStatic
    @JvmOverloads
    fun verify(
        activity: Activity,
        sessionToken: String,
        options: AkweloOptions = AkweloOptions(),
        onResult: (VerifyResult) -> Unit,
    ) {
        precheck(sessionToken, options)?.let { return onMain { onResult(it) } }
        val id = UUID.randomUUID().toString()
        when (val claim = requests.claim(id, onResult)) {
            is RequestRegistry.Claim.Busy ->
                return onMain { onResult(VerifyResult.error("already_in_progress", "A verification is already open")) }
            is RequestRegistry.Claim.Granted ->
                // A screen that was asked for and never appeared: tell its caller, then carry on.
                claim.abandoned?.let { stale ->
                    onMain { stale(VerifyResult.error("presentation_failed", "The capture screen did not open")) }
                }
        }
        try {
            activity.startActivity(AkweloVerifyActivity.intent(activity, sessionToken, options, id))
        } catch (e: RuntimeException) {
            deliver(id, VerifyResult.error("presentation_failed", e.message ?: "The capture screen did not open"))
        }
    }

    internal fun attached(requestId: String?) = requests.attached(requestId)

    internal fun deliver(requestId: String?, result: VerifyResult) {
        val callback = requests.release(requestId) ?: return
        onMain { callback(result) }
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }
}

/** What to verify: the input of [AkweloVerifyContract]. */
data class AkweloVerifyRequest(
    val sessionToken: String,
    val options: AkweloOptions = AkweloOptions(),
)

/**
 * The capture screen as an Activity Result contract. Unlike the callback of [Akwelo.verify], the
 * result reaches your Activity or Fragment even when Android recreated it, or restarted your
 * process, while the capture screen was open.
 *
 * ```
 * private val verify = registerForActivityResult(AkweloVerifyContract()) { result -> ... }
 * verify.launch(AkweloVerifyRequest(sessionToken))
 * ```
 */
class AkweloVerifyContract : ActivityResultContract<AkweloVerifyRequest, VerifyResult>() {
    override fun createIntent(context: Context, input: AkweloVerifyRequest): Intent =
        AkweloVerifyActivity.intent(context, input.sessionToken, input.options, requestId = null)

    override fun getSynchronousResult(context: Context, input: AkweloVerifyRequest): SynchronousResult<VerifyResult>? =
        precheck(input.sessionToken, input.options)?.let { SynchronousResult(it) }

    /** A screen that closed without setting a result (back, task removed) was cancelled. */
    override fun parseResult(resultCode: Int, intent: Intent?): VerifyResult =
        VerifyResult.fromIntent(intent) ?: VerifyResult.cancelled()
}

/** Null when capture can start; otherwise the error to report without opening anything. */
internal fun precheck(sessionToken: String?, options: AkweloOptions): VerifyResult? = when {
    sessionToken.isNullOrBlank() -> VerifyResult.error("invalid_session_token", "sessionToken must not be blank")
    VerifyUrl.validBaseOrigin(options.baseUrl) == null ->
        VerifyResult.error("invalid_base_url", "baseUrl must be an https URL")
    else -> null
}
