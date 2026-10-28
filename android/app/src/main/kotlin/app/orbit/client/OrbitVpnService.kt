package app.orbit.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import libXray.DialerController
import libXray.LibXray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * The tunnel. Android hands packets to the TUN descriptor, and Xray-core reads it itself through
 * its tun inbound (`env: {"xray.tun.fd": …}`), so the whole VPN is one Xray instance. Xray's own
 * sockets are protected from the tunnel through [Protector].
 */
class OrbitVpnService : VpnService() {
    private val worker = Executors.newSingleThreadExecutor()
    private var tun: ParcelFileDescriptor? = null
    private var running = false
    private var serverName = ""

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                },
            )
        }
        current = this
        // xray-core keeps every controller ever registered, so one per process, pointing at the live service
        if (!registered) {
            LibXray.registerDialerController(Protector)
            LibXray.registerListenerController(Protector)
            registered = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == VpnStore.ACTION_STOP) {
            worker.execute { stop(null) }
            return START_NOT_STICKY
        }
        // START, a restart by the system, or Android's always-on VPN: run the saved config
        foreground(getString(R.string.connecting))
        worker.execute { start() }
        return START_STICKY
    }

    private fun start() {
        val options = VpnStore.options(this)
        serverName = options.optString("server")
        VpnStore.publish(this, VpnStore.CONNECTING, server = serverName)
        try {
            if (running) stopCore()
            val config = JSONObject(VpnStore.configFile(this).readText())
            options.optJSONArray("notes")?.let { notes ->
                for (i in 0 until notes.length()) VpnStore.log(this, notes.optString(i))
            }

            val fd = establish(options)
            val dns = options.optString("dnsIp", "1.1.1.1")
            LibXray.setDNS(Protector, "$dns:53")
            val error = runXray(config, fd)
            if (error != null) {
                // the subscription's routing did not start: Orbit's own routing, rather than no VPN
                val fallback = VpnStore.fallbackFile(this).takeIf { it.exists() } ?: throw IllegalStateException(error)
                VpnStore.log(this, "роутинг подписки не запустился ($error), включаю роутинг Orbit")
                runXray(JSONObject(fallback.readText()), fd)?.let { throw IllegalStateException(it) }
            }

            running = true
            VpnStore.log(this, "connected: $serverName")
            VpnStore.publish(this, VpnStore.CONNECTED, since = System.currentTimeMillis(), server = serverName)
            foreground(getString(R.string.connected_to, serverName))
        } catch (e: Throwable) {
            VpnStore.log(this, "start failed: ${e.message}")
            stop(e.message ?: e.toString())
        }
    }

    /** Starts Xray on [config] with the tunnel's [fd]; the error, or null once it runs. */
    private fun runXray(config: JSONObject, fd: Int): String? {
        // Xray appends to its log; each connection starts a fresh one
        config.optJSONObject("log")?.optString("error")?.takeIf { it.isNotEmpty() }?.let {
            runCatching { File(it).writeText("") }
        }
        val env = (config.optJSONObject("env") ?: JSONObject()).put("xray.tun.fd", fd.toString())
        // the subscription's routing may name geosite:/geoip: lists
        runCatching { env.put("xray.location.asset", GeoFiles.dir(this).path) }
            .onFailure { VpnStore.log(this, "geo files: ${it.message}") }
        config.put("env", env)
        val response = JSONObject(LibXray.invoke(request("runXray", JSONObject().put("xrayJson", config.toString()))))
        return if (response.optBoolean("success")) null else response.optString("error", "Xray не запустился")
    }

    private fun establish(options: JSONObject): Int {
        val builder = Builder()
            .setSession("Orbit")
            .setMtu(1500)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(options.optString("dnsIp", "1.1.1.1"))
        runCatching {
            builder.addAddress("fdfe:dcba:9876::1", 126)
            builder.addRoute("::", 0)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val apps = options.optJSONArray("apps")
        val packages = (0 until (apps?.length() ?: 0)).map { apps!!.getString(it) }.filter { it != packageName }
        when (options.optString("appsMode")) {
            "include" -> {
                var added = 0
                for (p in packages) {
                    try {
                        builder.addAllowedApplication(p)
                        added++
                    } catch (_: PackageManager.NameNotFoundException) {
                    }
                }
                // "only these" with none of them installed would route nothing: keep Orbit out instead
                if (added == 0) builder.addDisallowedApplication(packageName)
            }
            else -> {
                // Orbit itself stays outside: its pings and subscription updates go straight to the servers
                builder.addDisallowedApplication(packageName)
                if (options.optString("appsMode") == "exclude") {
                    for (p in packages) {
                        try {
                            builder.addDisallowedApplication(p)
                        } catch (_: PackageManager.NameNotFoundException) {
                        }
                    }
                }
            }
        }

        tun?.close()
        val pfd = builder.establish() ?: throw IllegalStateException(getString(R.string.no_permission))
        tun = pfd
        return pfd.fd
    }

    private fun stopCore() {
        runCatching { LibXray.invoke(request("stopXray", JSONObject())) }
        runCatching { LibXray.resetDNS() }
        running = false
    }

    private fun stop(error: String?) {
        VpnStore.publish(this, VpnStore.DISCONNECTING, server = serverName)
        stopCore()
        runCatching { tun?.close() }
        tun = null
        VpnStore.log(this, if (error == null) "disconnected" else "stopped: $error")
        VpnStore.publish(this, VpnStore.DISCONNECTED, error = error, server = serverName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
    }

    override fun onRevoke() {
        // another VPN took over, or the user turned Orbit off in Android's settings
        worker.execute { stop(null) }
    }

    override fun onDestroy() {
        if (running) {
            stopCore()
            runCatching { tun?.close() }
            VpnStore.publish(this, VpnStore.DISCONNECTED, server = serverName)
        }
        worker.shutdown()
        if (current === this) current = null
        super.onDestroy()
    }

    private fun foreground(text: String) {
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, OrbitVpnService::class.java).setAction(VpnStore.ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_orbit)
            .setContentTitle("Orbit")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.disconnect), stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION, notification)
        }
    }

    /** Keeps Xray's sockets out of the tunnel. */
    private object Protector : DialerController {
        override fun protectFd(fd: Long): Boolean = current?.protect(fd.toInt()) ?: false
    }

    companion object {
        private const val CHANNEL = "orbit_vpn"
        private const val NOTIFICATION = 1

        @Volatile
        private var current: OrbitVpnService? = null
        private var registered = false

        fun request(method: String, payload: JSONObject): String =
            JSONObject().put("apiVersion", 3).put("method", method).put("payload", payload).toString()
    }
}
