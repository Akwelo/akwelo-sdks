package com.akwelo

import android.content.Context
import android.util.Base64
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import kotlinx.coroutines.tasks.await
import java.security.MessageDigest

/**
 * Requests a classic Play Integrity token bound to the session (nonce = SHA-256 of the token).
 * Akwelo's backend decrypts and checks it with Google.
 *
 * TODO(akwelo): needs a Play Console app linked to a Google Cloud project with the Play Integrity
 * API enabled, and server-side verification credentials. Untested until those exist.
 */
internal object PlayIntegrity {
    suspend fun token(context: Context, cloudProjectNumber: Long, sessionToken: String): String? = try {
        val digest = MessageDigest.getInstance("SHA-256").digest(sessionToken.toByteArray())
        val nonce = Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        IntegrityManagerFactory.create(context.applicationContext)
            .requestIntegrityToken(
                IntegrityTokenRequest.builder()
                    .setNonce(nonce)
                    .setCloudProjectNumber(cloudProjectNumber)
                    .build()
            )
            .await()
            .token()
    } catch (e: Exception) {
        null // attestation is best-effort; the backend decides how to treat its absence
    }
}
