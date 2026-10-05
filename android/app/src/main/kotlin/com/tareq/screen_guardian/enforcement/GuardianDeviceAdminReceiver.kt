package com.tareq.screen_guardian.enforcement

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device-admin hook. Being an active device administrator means the app can
 * only be uninstalled after the admin is deactivated in Settings – which is a
 * blocked app during a child session.
 *
 * When provisioned as *device owner* (see README) this component also enables
 * true kiosk lock-task mode.
 */
class GuardianDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        Log.i("GuardianAdmin", "device admin enabled")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Log.i("GuardianAdmin", "device admin disabled")
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        return "Disabling this will allow Screen Guardian to be removed and children to leave their profile."
    }
}
