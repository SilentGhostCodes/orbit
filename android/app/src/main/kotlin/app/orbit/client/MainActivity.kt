package app.orbit.client

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import libXray.DialerController
import libXray.LibXray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val io = Executors.newCachedThreadPool()
    private var pendingVpnPermission: MethodChannel.Result? = null
    private var statusSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private var dnsServer: String? = null

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val json = intent.getStringExtra("status") ?: return
            statusSink?.success(toMap(JSONObject(json)))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "orbit/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent == null) {
                        result.success(true)
                    } else {
                        pendingVpnPermission = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_VPN)
                    }
                }

                "start" -> {
                    VpnStore.configFile(this).writeText(call.argument<String>("config")!!)
                    VpnStore.optionsFile(this).writeText(call.argument<String>("vpn")!!)
                    val fallback = call.argument<String>("fallback")
                    if (fallback != null) VpnStore.fallbackFile(this).writeText(fallback) else VpnStore.fallbackFile(this).delete()
                    val intent = Intent(this, OrbitVpnService::class.java).setAction(VpnStore.ACTION_START)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(null)
                }

                "stop" -> {
                    VpnStore.stop(this)
                    result.success(null)
                }

                "status" -> result.success(toMap(VpnStore.status(this)))

                "setAutoConnect" -> {
                    val options = VpnStore.options(this).put("autoConnect", call.argument<Boolean>("on") == true)
                    VpnStore.optionsFile(this).writeText(options.toString())
                    result.success(null)
                }

                "libxray", "orbitPing" -> {
                    val request = call.argument<String>("request")!!
                    val dns = call.argument<String>("dns") ?: "1.1.1.1"
                    val orbitPing = call.method == "orbitPing"
                    io.execute {
                        val response = runCatching {
                            useDns(dns)
                            if (orbitPing) LibXray.orbitPing(request) else LibXray.invoke(request)
                        }.getOrElse {
                            JSONObject().put("success", false).put("error", it.message ?: it.toString()).toString()
                        }
                        runOnUiThread { result.success(response) }
                    }
                }

                "icmpPing" -> {
                    val host = call.argument<String>("host")!!
                    val timeout = call.argument<Int>("timeout") ?: 5
                    io.execute {
                        val delay = icmpPing(host, timeout)
                        runOnUiThread { result.success(delay) }
                    }
                }

                "installedApps" -> io.execute {
                    val apps = runCatching { installedApps() }
                    runOnUiThread {
                        apps.onSuccess { result.success(it) }.onFailure { result.error("apps", it.message, null) }
                    }
                }

                "deviceInfo" -> {
                    val maker = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
                    val model = if (Build.MODEL.startsWith(Build.MANUFACTURER, ignoreCase = true)) Build.MODEL else "$maker ${Build.MODEL}"
                    result.success(mapOf("osVersion" to Build.VERSION.RELEASE, "model" to model))
                }

                "openVpnSettings" -> {
                    runCatching { startActivity(Intent(Settings.ACTION_VPN_SETTINGS)) }
                    result.success(null)
                }

                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "orbit/status").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    statusSink = events
                    if (!receiverRegistered) {
                        val filter = IntentFilter(VpnStore.ACTION_STATUS)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                        } else {
                            @Suppress("UnspecifiedRegisterReceiverFlag")
                            registerReceiver(statusReceiver, filter)
                        }
                        receiverRegistered = true
                    }
                    // the current state at once, so a reopened app does not wait for a change
                    events.success(toMap(VpnStore.status(this@MainActivity)))
                }

                override fun onCancel(arguments: Any?) {
                    statusSink = null
                }
            },
        )
    }

    override fun onDestroy() {
        if (receiverRegistered) runCatching { unregisterReceiver(statusReceiver) }
        receiverRegistered = false
        io.shutdown()
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN) {
            pendingVpnPermission?.success(resultCode == RESULT_OK)
            pendingVpnPermission = null
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * Go on Android has no resolver of its own (no /etc/resolv.conf: it asks 127.0.0.1:53, where
     * nothing answers), so without this every server given by name failed to ping. The app's process
     * is always outside the tunnel, so its sockets need no protecting.
     */
    @Synchronized
    private fun useDns(ip: String) {
        val server = "$ip:53"
        if (server == dnsServer) return
        LibXray.setDNS(Unprotected, server)
        dnsServer = server
    }

    /** One echo through the system's ping (apps may not open raw sockets); milliseconds, or -1. */
    private fun icmpPing(host: String, timeoutSeconds: Int): Int = runCatching {
        val process = ProcessBuilder("/system/bin/ping", "-c", "1", "-W", "$timeoutSeconds", "-n", host)
            .redirectErrorStream(true)
            .start()
        if (!process.waitFor(timeoutSeconds + 2L, TimeUnit.SECONDS)) {
            process.destroy()
            return@runCatching -1
        }
        val output = process.inputStream.bufferedReader().readText()
        Regex("""time=([0-9.]+)""").find(output)?.groupValues?.get(1)?.toDouble()?.roundToInt() ?: -1
    }.getOrDefault(-1)

    private object Unprotected : DialerController {
        override fun protectFd(fd: Long): Boolean = true
    }

    private fun installedApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val size = (40 * resources.displayMetrics.density).toInt().coerceAtLeast(48)
        return pm.getInstalledApplications(0)
            .filter { it.packageName != packageName }
            .map { info ->
                val system = info.flags and ApplicationInfo.FLAG_SYSTEM != 0 &&
                    info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP == 0
                // system apps nobody can open (services, overlays) only clutter the list
                val launchable = pm.getLaunchIntentForPackage(info.packageName) != null
                mapOf(
                    "package" to info.packageName,
                    "name" to info.loadLabel(pm).toString(),
                    "system" to (system || !launchable),
                    "icon" to runCatching { iconPng(info, size) }.getOrNull(),
                )
            }
    }

    private fun iconPng(info: ApplicationInfo, size: Int): ByteArray {
        val drawable = info.loadIcon(packageManager)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun toMap(json: JSONObject): Map<String, Any?> = mapOf(
        "state" to json.optString("state", VpnStore.DISCONNECTED),
        "since" to json.optLong("since"),
        "error" to json.optString("error"),
        "server" to json.optString("server"),
    )

    companion object {
        private const val REQUEST_VPN = 1
        private const val REQUEST_NOTIFICATIONS = 2
    }
}
