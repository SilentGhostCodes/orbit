package app.orbit.client

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * What the app and the VPN process share. They are separate processes, so everything goes through
 * files in filesDir plus one broadcast for live updates.
 */
object VpnStore {
    const val ACTION_START = "app.orbit.client.START"
    const val ACTION_STOP = "app.orbit.client.STOP"
    const val ACTION_STATUS = "app.orbit.client.STATUS"

    const val DISCONNECTED = "disconnected"
    const val CONNECTING = "connecting"
    const val CONNECTED = "connected"
    const val DISCONNECTING = "disconnecting"

    /** The Xray config the tunnel runs. */
    fun configFile(ctx: Context) = File(ctx.filesDir, "active.json")

    /** The same server with Orbit's own routing, for when the subscription's routing fails to start. */
    fun fallbackFile(ctx: Context) = File(ctx.filesDir, "fallback.json")

    /** Per-app rules, DNS, the server name: see vpnOptions() in Dart. */
    fun optionsFile(ctx: Context) = File(ctx.filesDir, "vpn.json")

    private fun stateFile(ctx: Context) = File(ctx.filesDir, "vpn_state.json")

    private fun logFile(ctx: Context) = File(ctx.filesDir, "service.log")

    fun options(ctx: Context): JSONObject =
        runCatching { JSONObject(optionsFile(ctx).readText()) }.getOrDefault(JSONObject())

    fun publish(ctx: Context, state: String, error: String? = null, since: Long = 0, server: String? = null) {
        val json = JSONObject()
            .put("state", state)
            .put("error", error ?: "")
            .put("since", since)
            .put("server", server ?: "")
        runCatching { stateFile(ctx).writeText(json.toString()) }
        ctx.sendBroadcast(
            Intent(ACTION_STATUS).setPackage(ctx.packageName).putExtra("status", json.toString()),
        )
    }

    /**
     * What qWDTT waits for the user to do in VK, kept on the published state: "captcha"
     * (QwdttCaptcha), "join" (VkAccount), or null. [onlyIf]: clear only that one.
     */
    @Synchronized
    fun publishVk(ctx: Context, action: String?, onlyIf: String? = null) {
        val json = runCatching { JSONObject(stateFile(ctx).readText()) }.getOrNull() ?: return
        if (onlyIf != null && json.optString("vk") != onlyIf) return
        json.put("vk", action ?: "")
        runCatching { stateFile(ctx).writeText(json.toString()) }
        ctx.sendBroadcast(
            Intent(ACTION_STATUS).setPackage(ctx.packageName).putExtra("status", json.toString()),
        )
    }

    /** The last published state, or disconnected when the VPN process is not alive to back it. */
    fun status(ctx: Context): JSONObject {
        val json = runCatching { JSONObject(stateFile(ctx).readText()) }.getOrNull()
            ?: return JSONObject().put("state", DISCONNECTED)
        if (json.optString("state") != DISCONNECTED && !vpnProcessAlive(ctx)) {
            return JSONObject().put("state", DISCONNECTED)
        }
        return json
    }

    private fun vpnProcessAlive(ctx: Context): Boolean {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val name = "${ctx.packageName}:vpn"
        return am.runningAppProcesses?.any { it.processName == name } == true
    }

    fun isConnected(ctx: Context) = status(ctx).optString("state") == CONNECTED

    /** Starts the tunnel with the saved config, when Android already allowed this app a VPN. */
    fun startSaved(ctx: Context): Boolean {
        if (VpnService.prepare(ctx) != null || !configFile(ctx).exists()) return false
        val intent = Intent(ctx, OrbitVpnService::class.java).setAction(ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(intent) else ctx.startService(intent)
        return true
    }

    fun stop(ctx: Context) {
        ctx.startService(Intent(ctx, OrbitVpnService::class.java).setAction(ACTION_STOP))
    }

    private val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    fun log(ctx: Context, message: String) {
        runCatching {
            val file = logFile(ctx)
            if (file.length() > 256 * 1024) file.writeText("")
            file.appendText("${time.format(Date())} $message\n")
        }
    }
}
