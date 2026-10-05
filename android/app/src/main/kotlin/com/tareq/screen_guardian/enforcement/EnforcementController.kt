package com.tareq.screen_guardian.enforcement

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import com.tareq.screen_guardian.dns.DnsFilterVpnService

/**
 * Single entry point that turns a [SessionState] into running enforcement:
 * foreground timer service, DNS VPN and (when the app is device owner) lock
 * task mode. Also used by [BootReceiver] to re-arm after a reboot.
 */
object EnforcementController {
    private const val TAG = "Enforcement"

    fun start(ctx: Context, state: SessionState) {
        SessionStore.save(ctx, state)
        try {
            startServices(ctx, state)
        } catch (e: Exception) {
            stop(ctx)
            throw e
        }
        AppBlockerAccessibilityService.instance?.enforceNow()
    }

    fun startServices(ctx: Context, state: SessionState) {
        val svc = Intent(ctx, SessionForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.startForegroundService(svc)
        } else {
            ctx.startService(svc)
        }
        if (state.dnsFilterEnabled) startDns(ctx)
    }

    fun startDns(ctx: Context): Boolean {
        if (VpnService.prepare(ctx) != null) {
            Log.w(TAG, "VPN consent missing – DNS filter not started")
            return false
        }
        val i = Intent(ctx, DnsFilterVpnService::class.java).setAction(DnsFilterVpnService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
        return true
    }

    fun stop(ctx: Context) {
        SessionStore.clear(ctx)
        ctx.stopService(Intent(ctx, SessionForegroundService::class.java))
        // Android also binds a running VPN service. stopService alone does not
        // destroy a bound service, so explicitly close its tunnel first.
        if (DnsFilterVpnService.isRunning) {
            ctx.startService(Intent(ctx, DnsFilterVpnService::class.java).setAction(DnsFilterVpnService.ACTION_STOP))
        } else {
            ctx.stopService(Intent(ctx, DnsFilterVpnService::class.java))
        }
        AppBlockerAccessibilityService.instance?.hideOverlay()
        SessionStore.emit("sessionEnded")
    }

    // ------------------------------------------------------------- kiosk

    fun isDeviceOwner(ctx: Context): Boolean {
        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isDeviceOwnerApp(ctx.packageName)
    }

    /**
     * Hardens the running activity while a session is active.
     *
     * Always: the task is hidden from the Recents screen so the child cannot
     * swipe it away (the process keeps running and the accessibility blocker
     * bounces them back if they reach the launcher).
     *
     * When provisioned as device owner we additionally whitelist our app plus
     * the allowed apps and pin the task, which disables Home / Recents / status
     * bar entirely. Without device owner we rely on the accessibility blocker.
     */
    fun enterKiosk(activity: Activity, allowed: Set<String>) {
        setExcludedFromRecents(activity, true)
        if (!isDeviceOwner(activity)) return
        val keyguard = activity.getSystemService(android.app.KeyguardManager::class.java)
        if (keyguard.isKeyguardLocked) return
        try {
            val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val admin = ComponentName(activity, GuardianDeviceAdminReceiver::class.java)
            dpm.setLockTaskPackages(admin, (allowed + activity.packageName).toTypedArray())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dpm.setLockTaskFeatures(
                    admin,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                        DevicePolicyManager.LOCK_TASK_FEATURE_BLOCK_ACTIVITY_START_IN_TASK
                    else DevicePolicyManager.LOCK_TASK_FEATURE_NONE,
                )
            }
            val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            if (am.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE) {
                activity.startLockTask()
            }
        } catch (e: Exception) {
            Log.w(TAG, "enterKiosk failed", e)
        }
    }

    fun exitKiosk(activity: Activity) {
        setExcludedFromRecents(activity, false)
        try {
            // Release the owning task before changing the allow-list. Clearing
            // the list first can remove our task before it releases child tasks.
            val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            if (am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
                activity.stopLockTask()
            }
            if (isDeviceOwner(activity)) {
                val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                dpm.setLockTaskPackages(
                    ComponentName(activity, GuardianDeviceAdminReceiver::class.java), emptyArray(),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "exitKiosk failed", e)
        }
    }

    private fun setExcludedFromRecents(activity: Activity, excluded: Boolean) {
        try {
            val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (task in am.appTasks) {
                task.setExcludeFromRecents(excluded)
            }
        } catch (e: Exception) {
            Log.w(TAG, "setExcludeFromRecents($excluded) failed", e)
        }
    }

    /**
     * Re-creates the foreground timer service if the process was killed (for
     * example via the Android 13+ "Active apps ▸ Stop" button) while a session
     * is still stored. Safe to call often.
     */
    fun rearmIfNeeded(ctx: Context) {
        val s = SessionStore.load(ctx)
        if (!s.active) return
        try {
            if (!SessionForegroundService.isRunning) {
                Log.i(TAG, "session active but timer service missing – re-arming")
                startServices(ctx, s)
            } else if (s.dnsFilterEnabled && !DnsFilterVpnService.isRunning) {
                startDns(ctx)
            }
        } catch (e: Exception) {
            // Background service starts may be refused; the blocker must stay alive.
            Log.w(TAG, "could not re-arm services; will retry on resume", e)
        }
    }

    /** Brings the Flutter activity to the front (used by blocker + timer). */
    fun bringAppToFront(ctx: Context, reason: String) {
        val i = Intent(ctx, com.tareq.screen_guardian.MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            putExtra("reason", reason)
        }
        try {
            ctx.startActivity(i)
        } catch (e: Exception) {
            Log.w(TAG, "bringAppToFront failed", e)
        }
    }
}
