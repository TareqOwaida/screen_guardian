package com.tareq.screen_guardian.enforcement

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Re-arms the timer service and DNS filter if a session was running. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val s = SessionStore.load(context)
        if (!s.active) return
        Log.i("BootReceiver", "restoring session for ${s.profileName} after ${intent.action}")
        try {
            EnforcementController.startServices(context, s)
        } catch (e: Exception) {
            Log.w("BootReceiver", "failed to restore services", e)
        }
    }
}
