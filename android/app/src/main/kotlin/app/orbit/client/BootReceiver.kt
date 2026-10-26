package app.orbit.client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** "Автоподключение": brings the tunnel up after a reboot, with the last server used. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!VpnStore.options(context).optBoolean("autoConnect")) return
        if (VpnStore.startSaved(context)) VpnStore.log(context, "auto-connect after ${intent.action}")
    }
}
