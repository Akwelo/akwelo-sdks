package com.akwelo

import android.app.Activity
import android.content.Intent

/**
 * Entry point.
 *
 * ```
 * Akwelo.verify(activity, sessionToken) { result -> ... }
 * ```
 * The callback is invoked exactly once on the main thread.
 */
object Akwelo {
    internal var pending: ((VerifyResult) -> Unit)? = null

    @JvmStatic
    @JvmOverloads
    fun verify(
        activity: Activity,
        sessionToken: String,
        options: AkweloOptions = AkweloOptions(),
        onResult: (VerifyResult) -> Unit,
    ) {
        if (sessionToken.isBlank()) {
            onResult(VerifyResult.error("sessionToken must not be blank"))
            return
        }
        // Only one verification at a time; a superseded caller is told it was cancelled.
        pending?.invoke(VerifyResult.cancelled())
        pending = onResult
        val intent = Intent(activity, AkweloVerifyActivity::class.java)
            .putExtra(AkweloVerifyActivity.EXTRA_TOKEN, sessionToken)
            .putExtra(AkweloVerifyActivity.EXTRA_BASE_URL, options.baseUrl)
        options.playIntegrityCloudProjectNumber?.let {
            intent.putExtra(AkweloVerifyActivity.EXTRA_CLOUD_PROJECT, it)
        }
        activity.startActivity(intent)
    }

    internal fun deliver(result: VerifyResult) {
        val cb = pending
        pending = null
        cb?.invoke(result)
    }
}
