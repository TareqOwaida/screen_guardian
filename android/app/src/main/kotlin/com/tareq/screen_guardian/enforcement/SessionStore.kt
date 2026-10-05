package com.tareq.screen_guardian.enforcement

import android.content.Context
import android.content.SharedPreferences

/**
 * Persisted, process-independent description of the running screen-time
 * session. Read by the accessibility service, the foreground service, the VPN
 * and the Flutter bridge so enforcement keeps working even if the Flutter
 * process is killed or the device reboots.
 */
data class SessionState(
    val active: Boolean,
    val profileId: String,
    val profileName: String,
    val allowedPackages: Set<String>,
    val startedAt: Long,
    val endsAt: Long,
    val dnsFilterEnabled: Boolean,
    val blockedDomains: Set<String>,
    val blockedIps: Set<String>,
) {
    val isExpired: Boolean get() = active && System.currentTimeMillis() >= endsAt
    val remainingMillis: Long get() = (endsAt - System.currentTimeMillis()).coerceAtLeast(0)

    fun toMap(): Map<String, Any?> = mapOf(
        "active" to active,
        "profileId" to profileId,
        "profileName" to profileName,
        "startedAt" to startedAt,
        "endsAt" to endsAt,
        "expired" to isExpired,
    )

    companion object {
        val NONE = SessionState(false, "", "", emptySet(), 0, 0, false, emptySet(), emptySet())
    }
}

object SessionStore {
    private const val PREFS = "guardian_session"

    /** Listener used by MainActivity to push events to Flutter's EventChannel. */
    @Volatile
    var eventSink: ((Map<String, Any?>) -> Unit)? = null

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(ctx: Context): SessionState {
        val p = prefs(ctx)
        if (!p.getBoolean("active", false)) return SessionState.NONE
        return SessionState(
            active = true,
            profileId = p.getString("profileId", "") ?: "",
            profileName = p.getString("profileName", "") ?: "",
            allowedPackages = p.getStringSet("allowed", emptySet()) ?: emptySet(),
            startedAt = p.getLong("startedAt", 0),
            endsAt = p.getLong("endsAt", 0),
            dnsFilterEnabled = p.getBoolean("dns", false),
            blockedDomains = p.getStringSet("blockedDomains", emptySet()) ?: emptySet(),
            blockedIps = p.getStringSet("blockedIps", emptySet()) ?: emptySet(),
        )
    }

    fun save(ctx: Context, s: SessionState) {
        prefs(ctx).edit()
            .putBoolean("active", s.active)
            .putString("profileId", s.profileId)
            .putString("profileName", s.profileName)
            .putStringSet("allowed", s.allowedPackages)
            .putLong("startedAt", s.startedAt)
            .putLong("endsAt", s.endsAt)
            .putBoolean("dns", s.dnsFilterEnabled)
            .putStringSet("blockedDomains", s.blockedDomains)
            .putStringSet("blockedIps", s.blockedIps)
            .commit().also { check(it) { "Could not persist the session." } }
    }

    fun clear(ctx: Context) {
        check(prefs(ctx).edit().clear().commit()) { "Could not clear the session." }
    }

    fun extend(ctx: Context, minutes: Int): SessionState {
        require(minutes in 1..240) { "Extension must be between 1 and 240 minutes." }
        val s = load(ctx)
        check(s.active) { "There is no session to extend." }
        val base = if (s.isExpired) System.currentTimeMillis() else s.endsAt
        val updated = s.copy(endsAt = base + minutes * 60_000L)
        save(ctx, updated)
        return updated
    }

    fun emit(event: String, extra: Map<String, Any?> = emptyMap()) {
        eventSink?.invoke(mapOf("event" to event) + extra)
    }
}
