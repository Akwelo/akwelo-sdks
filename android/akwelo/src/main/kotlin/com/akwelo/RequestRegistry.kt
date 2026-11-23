package com.akwelo

/**
 * The one capture that may be open, and who is waiting for it. Pure state, no Android types.
 *
 * A request is claimed before its screen is started and attached once the screen exists. A claim
 * that was never attached (the system refused to start the screen and said nothing) must not
 * block every later capture, so after [staleAfterMs] the next claim replaces it.
 */
internal class RequestRegistry<T : Any>(
    private val staleAfterMs: Long = 10_000,
    private val now: () -> Long = System::currentTimeMillis,
) {
    sealed interface Claim<out T> {
        /** The request is now the open one. [abandoned] is a stale waiter it replaced, if any. */
        data class Granted<T>(val abandoned: T?) : Claim<T>
        data object Busy : Claim<Nothing>
    }

    private class Entry<T>(val id: String, val waiter: T, val claimedAt: Long, var attached: Boolean = false)

    private var open: Entry<T>? = null

    @Synchronized
    fun claim(id: String, waiter: T): Claim<T> {
        val current = open
        if (current != null && (current.attached || now() - current.claimedAt < staleAfterMs)) return Claim.Busy
        open = Entry(id, waiter, now())
        return Claim.Granted(current?.waiter)
    }

    /** The screen for [id] exists. */
    @Synchronized
    fun attached(id: String?) {
        open?.takeIf { it.id == id }?.attached = true
    }

    /** Ends the request and returns its waiter; null when [id] is not the open request. */
    @Synchronized
    fun release(id: String?): T? {
        val current = open?.takeIf { it.id == id } ?: return null
        open = null
        return current.waiter
    }
}
