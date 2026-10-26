package app.orbit.client

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** The Orbit tile in the quick settings shade: on and off with the last server used. */
class OrbitTileService : TileService() {
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = refresh()
    }

    override fun onStartListening() {
        super.onStartListening()
        val filter = IntentFilter(VpnStore.ACTION_STATUS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        refresh()
    }

    override fun onStopListening() {
        runCatching { unregisterReceiver(receiver) }
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (VpnStore.status(this).optString("state") != VpnStore.DISCONNECTED) {
            VpnStore.stop(this)
        } else if (!VpnStore.startSaved(this)) {
            // no permission or nothing connected before: the app has to do it the first time
            val launch = packageManager.getLaunchIntentForPackage(packageName)?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE),
                )
            } else {
                @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
                startActivityAndCollapse(launch)
            }
        }
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val status = VpnStore.status(this)
        val state = status.optString("state")
        tile.state = if (state == VpnStore.DISCONNECTED) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = status.optString("server").takeIf { state == VpnStore.CONNECTED && it.isNotEmpty() }
        }
        tile.updateTile()
    }
}
