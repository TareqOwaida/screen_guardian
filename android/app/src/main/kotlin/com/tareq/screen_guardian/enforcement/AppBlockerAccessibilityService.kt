package com.tareq.screen_guardian.enforcement

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.tareq.screen_guardian.R

/**
 * Watches window changes. While a session is active, any package that is not
 * in the profile's allow-list (or any package at all once time is up) is
 * covered with a full-screen accessibility overlay and the user is bounced
 * back to Screen Guardian.
 *
 * TYPE_ACCESSIBILITY_OVERLAY does not require the "draw over other apps"
 * permission, so blocking works even when that permission was refused.
 */
class AppBlockerAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "AppBlocker"

        @Volatile
        var instance: AppBlockerAccessibilityService? = null

        /** Packages that must never be blocked (system UI, keyboards, ...). */
        private val SYSTEM_ALLOW = setOf(
            "android",
            "com.android.systemui",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.incallui",
            "com.android.phone",
            "com.android.server.telecom",
            "com.android.emergency",
        )
    }

    private enum class Mode { BLOCKED, TIME_UP, HOME }

    private val handler = Handler(Looper.getMainLooper())
    private var overlay: View? = null
    private var lastBlockedPackage: String? = null
    private var lastRearmCheck = 0L
    private var launcherPackages: Set<String> = emptySet()
    private var imePackages: Set<String> = emptySet()

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        launcherPackages = resolveLaunchers()
        imePackages = resolveImes()
        Log.i(TAG, "connected; launchers=$launcherPackages")
        // The system re-binds this service after our process is killed, so it
        // doubles as the watchdog that revives the timer service.
        EnforcementController.rearmIfNeeded(this)
        enforceNow()
    }

    override fun onDestroy() {
        instance = null
        handler.removeCallbacksAndMessages(null)
        hideOverlay()
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        evaluate(pkg, event.className?.toString())
    }

    /** Re-check the currently focused app (called by the timer / bridge). */
    fun enforceNow() {
        handler.post {
            val pkg = try {
                rootInActiveWindow?.packageName?.toString()
            } catch (_: Exception) {
                null
            }
            if (pkg != null) evaluate(pkg, null) else if (!SessionStore.load(this).active) hideOverlay()
        }
    }

    private fun evaluate(pkg: String, className: String?) {
        val state = SessionStore.load(this)
        if (!state.active) {
            hideOverlay()
            return
        }
        // Cheap watchdog: if the timer service died (task manager "Stop",
        // low memory...) bring it back the moment the child does anything.
        val now = System.currentTimeMillis()
        if (now - lastRearmCheck > 3_000) {
            lastRearmCheck = now
            EnforcementController.rearmIfNeeded(this)
        }
        if (pkg == packageName) {
            // Our own overlay also reports our package name; only dismiss it
            // when a real activity of ours reached the foreground.
            if (className == null || className.contains("Activity")) hideOverlay()
            return
        }
        if (pkg in SYSTEM_ALLOW || pkg in imePackages) return

        val expired = state.isExpired
        if (expired) {
            block(pkg, state, Mode.TIME_UP)
            return
        }
        if (pkg in launcherPackages) {
            // Home / Recents / swipe-away landed on the launcher: cover it and
            // send the child straight back to Screen Guardian. The overlay is
            // removed automatically once our activity is in front.
            block(pkg, state, Mode.HOME)
            return
        }
        if (pkg in state.allowedPackages) {
            hideOverlay()
            return
        }
        block(pkg, state, Mode.BLOCKED)
    }

    private fun block(pkg: String, state: SessionState, mode: Mode) {
        if (lastBlockedPackage != pkg || overlay == null) {
            Log.i(TAG, "blocking $pkg ($mode)")
            showOverlay(state, mode)
            lastBlockedPackage = pkg
        }
        val reason = when (mode) {
            Mode.TIME_UP -> "timeUp"
            Mode.HOME -> "home"
            Mode.BLOCKED -> "blocked"
        }
        if (mode == Mode.HOME) {
            EnforcementController.bringAppToFront(this, reason)
        } else {
            // Push the blocked app to the background and surface Screen Guardian.
            performGlobalAction(GLOBAL_ACTION_HOME)
            handler.postDelayed({ EnforcementController.bringAppToFront(this, reason) }, 150)
        }
    }

    // ------------------------------------------------------------ overlay

    private fun showOverlay(state: SessionState, mode: Mode) {
        hideOverlay()
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        // Colours mirror the Flutter theme: ink navy for "time's up", deep
        // teal for everything else.
        val overlayColor = if (mode == Mode.TIME_UP) "#F51B2430" else "#F5075756"
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor(overlayColor))
            setPadding(dp(32), dp(32), dp(32), dp(32))
            isClickable = true
        }
        val title = when (mode) {
            Mode.TIME_UP -> getString(R.string.time_up_title)
            Mode.HOME -> getString(R.string.returning_title)
            Mode.BLOCKED -> getString(R.string.blocked_title)
        }
        val body = when (mode) {
            Mode.TIME_UP -> getString(R.string.time_up_body, state.profileName)
            Mode.HOME -> getString(R.string.returning_body, state.profileName)
            Mode.BLOCKED -> getString(R.string.blocked_body, state.profileName)
        }
        root.addView(TextView(this).apply {
            text = title
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = body
            setTextColor(Color.parseColor("#CCFFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(28))
        })
        root.addView(Button(this).apply {
            text = getString(R.string.back_to_guardian)
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#1B2430"))
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#F5B532"))
            }
            setPadding(dp(24), dp(14), dp(24), dp(14))
            setOnClickListener {
                hideOverlay()
                EnforcementController.bringAppToFront(this@AppBlockerAccessibilityService, "overlay")
            }
        })

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.CENTER }
        try {
            wm.addView(root, params)
            overlay = root
        } catch (e: Exception) {
            Log.w(TAG, "overlay failed", e)
        }
    }

    fun hideOverlay() {
        val v = overlay ?: return
        overlay = null
        lastBlockedPackage = null
        try {
            (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------ helpers

    private fun resolveLaunchers(): Set<String> {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return packageManager.queryIntentActivities(i, 0)
            .map { it.activityInfo.packageName }
            .filter { it != packageName }
            .toSet()
    }

    private fun resolveImes(): Set<String> {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        return imm.inputMethodList.map { it.packageName }.toSet()
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()
}
