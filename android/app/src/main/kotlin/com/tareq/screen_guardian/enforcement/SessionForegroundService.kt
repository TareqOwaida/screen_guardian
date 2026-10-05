package com.tareq.screen_guardian.enforcement

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.tareq.screen_guardian.MainActivity
import com.tareq.screen_guardian.R

/**
 * Keeps the session countdown alive in the background, shows the remaining
 * time in a persistent notification, fires the "time's up" transition and acts
 * as a fallback foreground-app poller (UsageStats) when the accessibility
 * service is not connected.
 */
class SessionForegroundService : Service() {

    companion object {
        private const val TAG = "SessionService"
        private const val CHANNEL_ID = "guardian_session"
        private const val NOTIF_ID = 1001
        private const val TICK_MS = 1000L

        /** True while an instance of this service is alive. */
        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private var timeUpFired = false
    private var lastNotifiedMinute = -1L

    private val tick = object : Runnable {
        override fun run() {
            val s = SessionStore.load(this@SessionForegroundService)
            if (!s.active) {
                stopSelf()
                return
            }
            val minute = s.remainingMillis / 60_000
            if (minute != lastNotifiedMinute) {
                lastNotifiedMinute = minute
                updateNotification(s)
            }
            if (s.isExpired && !timeUpFired) {
                timeUpFired = true
                onTimeUp(s)
            } else if (!s.isExpired) {
                timeUpFired = false
            }
            fallbackPoll(s)
            SessionStore.emit("tick", mapOf("remaining" to s.remainingMillis))
            handler.postDelayed(this, TICK_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val s = SessionStore.load(this)
        if (!s.active) {
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground(buildNotification(s))
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    /**
     * Called when the user swipes the task away or the system removes it. A
     * session that is still stored must keep running, so restart ourselves.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val s = SessionStore.load(this)
        if (s.active) {
            Log.i(TAG, "task removed during active session – restarting service")
            EnforcementController.rearmIfNeeded(this)
            EnforcementController.bringAppToFront(this, "taskRemoved")
        }
    }

    private fun onTimeUp(s: SessionState) {
        Log.i(TAG, "session for ${s.profileName} expired")
        if (EnforcementController.isDeviceOwner(this)) {
            val dpm = getSystemService(android.app.admin.DevicePolicyManager::class.java)
            try {
                dpm.setLockTaskPackages(
                    android.content.ComponentName(this, GuardianDeviceAdminReceiver::class.java),
                    arrayOf(packageName),
                )
            } catch (e: Exception) {
                Log.w(TAG, "could not narrow kiosk apps at expiry", e)
            }
        }
        SessionStore.emit("sessionEnded")
        AppBlockerAccessibilityService.instance?.enforceNow()
        EnforcementController.bringAppToFront(this, "timeUp")
    }

    /**
     * If the accessibility service is not running, use UsageStats (if granted)
     * to detect the foreground app and bounce back to Screen Guardian.
     */
    private fun fallbackPoll(s: SessionState) {
        if (AppBlockerAccessibilityService.instance != null) return
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return
        val now = System.currentTimeMillis()
        val events = try {
            usm.queryEvents(now - 5_000, now)
        } catch (_: Exception) {
            return
        }
        var lastPkg: String? = null
        val ev = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            if (ev.eventType == UsageEvents.Event.ACTIVITY_RESUMED) lastPkg = ev.packageName
        }
        val pkg = lastPkg ?: return
        if (pkg == packageName) return
        if (s.isExpired || pkg !in s.allowedPackages) {
            EnforcementController.bringAppToFront(this, if (s.isExpired) "timeUp" else "blocked")
        }
    }

    // ------------------------------------------------------- notification

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Screen-time session", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows the remaining time of the active profile"
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(s: SessionState): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val mins = s.remainingMillis / 60_000
        val text = if (s.isExpired) getString(R.string.time_up_title) else "$mins min remaining"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setContentTitle("${s.profileName} – Screen Guardian")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(s: SessionState) {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(s))
    }

    private fun startInForeground(n: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }
}
