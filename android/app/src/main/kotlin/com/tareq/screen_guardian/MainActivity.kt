package com.tareq.screen_guardian

import android.Manifest
import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.view.WindowManager
import com.tareq.screen_guardian.enforcement.AppBlockerAccessibilityService
import com.tareq.screen_guardian.enforcement.EnforcementController
import com.tareq.screen_guardian.enforcement.GuardianDeviceAdminReceiver
import com.tareq.screen_guardian.enforcement.SessionState
import com.tareq.screen_guardian.enforcement.SessionStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "com.tareq.screen_guardian/native"
        const val EVENT_CHANNEL = "com.tareq.screen_guardian/events"
        private const val REQ_VPN = 4001
        private const val REQ_NOTIFICATIONS = 4002
    }

    private var pendingVpnResult: MethodChannel.Result? = null

    // Flutter calls this for SystemNavigator.pop, including root Back handling.
    // Keep the native guard active before Flutter has restored its own state.
    override fun popSystemNavigator(): Boolean =
        SessionStore.load(this).active || super.popSystemNavigator()

    override fun finish() {
        if (!SessionStore.load(this).active) super.finish()
    }

    override fun finishAndRemoveTask() {
        if (!SessionStore.load(this).active) super.finishAndRemoveTask()
    }

    override fun moveTaskToBack(nonRoot: Boolean): Boolean =
        if (SessionStore.load(this).active) false else super.moveTaskToBack(nonRoot)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Show on top of the keyguard so the "time's up" screen is visible
        // even when the child locks/unlocks the phone.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }

    override fun onResume() {
        super.onResume()
        val s = SessionStore.load(this)
        if (s.active) {
            EnforcementController.enterKiosk(this, if (s.isExpired) emptySet() else s.allowedPackages)
            EnforcementController.rearmIfNeeded(this)
        } else {
            EnforcementController.exitKiosk(this)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SessionStore.eventSink = { m -> runOnUiThread { events?.success(m) } }
                }

                override fun onCancel(arguments: Any?) {
                    SessionStore.eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getPermissionStatus" -> result.success(permissionStatus())
                        "requestPermission" -> {
                            requestPermission(call.argument<String>("key") ?: "", result)
                        }
                        "getInstalledApps" -> Thread { installedApps(result) }.start()
                        "launchApp" -> result.success(launchApp(call.argument<String>("packageName") ?: ""))
                        "isDeviceOwner" -> result.success(EnforcementController.isDeviceOwner(this))
                        "startSession" -> {
                            startSession(call.arguments as Map<*, *>)
                            result.success(SessionStore.load(this).toMap())
                        }
                        "extendSession" -> {
                            val s = SessionStore.extend(this, call.argument<Int>("minutes") ?: 0)
                            if (s.active) {
                                EnforcementController.startServices(this, s)
                                EnforcementController.enterKiosk(this, s.allowedPackages)
                            }
                            AppBlockerAccessibilityService.instance?.enforceNow()
                            result.success(s.toMap())
                        }
                        "stopSession" -> {
                            EnforcementController.stop(this)
                            EnforcementController.exitKiosk(this)
                            result.success(SessionStore.load(this).toMap())
                        }
                        "getSessionState" -> result.success(SessionStore.load(this).toMap())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("native_error", e.message, null)
                }
            }
    }

    // ------------------------------------------------------------ session

    @Suppress("UNCHECKED_CAST")
    private fun startSession(args: Map<*, *>) {
        check(!SessionStore.load(this).active) { "A session is already locked. End it with the parent PIN first." }
        check(AppBlockerAccessibilityService.instance != null) { "The accessibility blocker is not connected. A parent must enable it first." }
        val now = System.currentTimeMillis()
        val minutes = (args["durationMinutes"] as? Int) ?: 30
        require(minutes in 1..240) { "Session length must be between 1 and 240 minutes." }
        require(!(args["profileId"] as? String).isNullOrBlank()) { "A saved profile is required." }
        if (args["dnsFilterEnabled"] == true) {
            check(VpnService.prepare(this) == null) { "Safe DNS requires VPN permission." }
        }
        val state = SessionState(
            active = true,
            profileId = args["profileId"] as? String ?: "",
            profileName = args["profileName"] as? String ?: "",
            allowedPackages = (args["allowedPackages"] as? List<String>)?.toSet() ?: emptySet(),
            startedAt = now,
            endsAt = now + minutes * 60_000L,
            dnsFilterEnabled = args["dnsFilterEnabled"] as? Boolean ?: false,
            blockedDomains = (args["blockedDomains"] as? List<String>)?.map { it.lowercase() }?.toSet() ?: emptySet(),
            blockedIps = (args["blockedIps"] as? List<String>)?.toSet() ?: emptySet(),
        )
        EnforcementController.start(this, state)
        EnforcementController.enterKiosk(this, state.allowedPackages)
    }

    // -------------------------------------------------------- permissions

    private fun permissionStatus(): Map<String, Boolean> = mapOf(
        "accessibility" to (isAccessibilityEnabled() && AppBlockerAccessibilityService.instance != null),
        "usageAccess" to hasUsageAccess(),
        "overlay" to Settings.canDrawOverlays(this),
        "notifications" to notificationsEnabled(),
        "deviceAdmin" to isDeviceAdmin(),
        "batteryOptimization" to ignoringBatteryOptimizations(),
        "vpn" to (VpnService.prepare(this) == null),
    )

    private fun requestPermission(key: String, result: MethodChannel.Result) {
        when (key) {
            "accessibility" -> {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "usageAccess" -> {
                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                result.success(null)
            }
            "overlay" -> {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
                )
                result.success(null)
            }
            "notifications" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
                } else {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                    )
                }
                result.success(null)
            }
            "deviceAdmin" -> {
                val i = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                    putExtra(
                        DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                        ComponentName(this@MainActivity, GuardianDeviceAdminReceiver::class.java),
                    )
                    putExtra(
                        DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                        getString(R.string.device_admin_description),
                    )
                }
                startActivity(i)
                result.success(null)
            }
            "batteryOptimization" -> {
                startActivity(
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")),
                )
                result.success(null)
            }
            "vpn" -> {
                val consent = VpnService.prepare(this)
                if (consent == null) {
                    result.success(true)
                } else {
                    pendingVpnResult = result
                    startActivityForResult(consent, REQ_VPN)
                }
            }
            else -> result.error("unknown_permission", key, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN) {
            val granted = resultCode == RESULT_OK
            pendingVpnResult?.success(granted)
            pendingVpnResult = null
            val s = SessionStore.load(this)
            if (granted && s.active && s.dnsFilterEnabled) EnforcementController.startDns(this)
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(this, AppBlockerAccessibilityService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        for (name in splitter) {
            if (name.equals(expected, ignoreCase = true)) return true
        }
        return AppBlockerAccessibilityService.instance != null
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun notificationsEnabled(): Boolean {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val enabled = nm.areNotificationsEnabled()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return enabled && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return enabled
    }

    private fun isDeviceAdmin(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isAdminActive(ComponentName(this, GuardianDeviceAdminReceiver::class.java))
    }

    private fun ignoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    // ---------------------------------------------------------------- apps

    private fun installedApps(result: MethodChannel.Result) {
        val pm = packageManager
        val launchable = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(launchable, 0)
        val seen = HashSet<String>()
        val list = ArrayList<Map<String, Any?>>()
        for (ri in resolved) {
            val pkg = ri.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            val ai: ApplicationInfo = ri.activityInfo.applicationInfo
            val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                (ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
            list.add(
                mapOf(
                    "packageName" to pkg,
                    "appName" to ri.loadLabel(pm).toString(),
                    "isSystem" to isSystem,
                    "icon" to iconBytes(ri.loadIcon(pm)),
                ),
            )
        }
        runOnUiThread { result.success(list) }
    }

    private fun iconBytes(drawable: android.graphics.drawable.Drawable): ByteArray? = try {
        val size = 96
        val bmp = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = Canvas(b)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(c)
            b
        }
        ByteArrayOutputStream().use { out ->
            bmp.compress(Bitmap.CompressFormat.PNG, 90, out)
            out.toByteArray()
        }
    } catch (_: Exception) {
        null
    }

    private fun launchApp(pkg: String): Boolean {
        val session = SessionStore.load(this)
        if (!session.active || session.isExpired || pkg !in session.allowedPackages) return false
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && EnforcementController.isDeviceOwner(this)) {
                val options = android.app.ActivityOptions.makeBasic().setLockTaskEnabled(true)
                startActivity(intent, options.toBundle())
            } else {
                startActivity(intent)
            }
            true
        } catch (_: Exception) {
            false
        }
    }
}
