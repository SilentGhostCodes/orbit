package app.orbit.client

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.OutputStreamWriter
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * qWDTT (github.com/kostfuciy/qWDTT): WireGuard carried through VK call TURN relays. Its client is
 * a separate program, `libqwdtt.so` (built in CI), run here in the VPN process. It takes TURN
 * credentials from VK calls, opens DTLS through the relays to the user's server, and listens on
 * 127.0.0.1:[port] as the server's WireGuard endpoint. Xray's wireguard outbound dials that port, so
 * the tunnel stays one Xray instance: phone → Xray → WireGuard → qWDTT → VK relay → server.
 *
 * [start] blocks until the server sent its WireGuard config (the client saves it as wg-turn.conf)
 * and returns it as the settings of an Xray wireguard outbound.
 */
class QwdttTunnel(private val ctx: Context, private val profile: JSONObject) {
    private val lock = Any()
    private var process: Process? = null
    private var stdin: OutputStreamWriter? = null
    private val ready = CountDownLatch(1)

    @Volatile private var settings: JSONObject? = null
    @Volatile private var failure: String? = null
    @Volatile private var cancelled = false
    @Volatile private var lastError: String? = null

    /** Called (on the reader thread) when the client exits after the tunnel came up. */
    @Volatile var onExit: ((String) -> Unit)? = null

    private val port = profile.optInt("port", DEFAULT_PORT).takeIf { it in 1024..65535 } ?: DEFAULT_PORT
    private val dir = File(ctx.filesDir, "qwdtt")

    fun start(timeoutMs: Long = START_TIMEOUT_MS): JSONObject {
        val binary = File(ctx.applicationInfo.nativeLibraryDir, "libqwdtt.so")
        if (!binary.exists()) throw IllegalStateException("В этой сборке нет клиента qWDTT")

        val peer = profile.optString("peer").trim()
        val hashes = profile.optJSONArray("hashes").strings().filter { it.isNotBlank() }
        val password = profile.optString("password")
        require(peer.isNotEmpty()) { "В профиле qWDTT нет адреса сервера" }
        require(hashes.isNotEmpty()) { "В профиле qWDTT нет хешей звонков" }
        require(password.isNotEmpty()) { "В профиле qWDTT нет пароля" }

        dir.mkdirs()
        File(dir, CONF).delete()

        val cmd = mutableListOf(
            binary.path,
            "-peer", peer,
            "-vk", hashes.joinToString(","),
            "-n", profile.optInt("workers", 16).coerceIn(1, 108).toString(),
            "-listen", "127.0.0.1:$port",
            "-device-id", profile.optString("deviceId").ifBlank { "orbit" },
            "-password", password,
            // the Go solver first; the VK window only when it gives up (see onCaptcha)
            "-captcha-mode", "auto",
            "-vk-auth", "anonymous",
            "-vk-anon-path", "vkcalls",
            "-go-dns", profile.optString("dns", "yandex").ifBlank { "yandex" },
            "-obfs", profile.optString("obfs", "audio").ifBlank { "audio" },
            "-mode", "vpn",
        )
        if (profile.optBoolean("turnTcp")) cmd.add("-turn-tcp")
        if (profile.optBoolean("noDtls")) cmd.add("-notls")

        val started = synchronized(lock) {
            if (cancelled) throw IllegalStateException("Подключение отменено")
            ProcessBuilder(cmd).directory(dir).redirectErrorStream(true).apply {
                environment()["LD_LIBRARY_PATH"] = ctx.applicationInfo.nativeLibraryDir
            }.start().also {
                process = it
                stdin = OutputStreamWriter(it.outputStream, Charsets.UTF_8)
            }
        }
        VpnStore.log(ctx, "qWDTT: запуск, сервер $peer, звонков ${hashes.size}")
        Thread({ read(started, password) }, "qwdtt-reader").apply { isDaemon = true }.start()

        if (!ready.await(timeoutMs, TimeUnit.MILLISECONDS)) {
            stop()
            throw IllegalStateException("qWDTT не подключился за ${timeoutMs / 1000} с" + (lastError?.let { ": $it" } ?: ""))
        }
        failure?.let { throw IllegalStateException(it) }
        return settings ?: throw IllegalStateException("qWDTT не прислал конфиг")
    }

    private fun read(p: Process, password: String) {
        try {
            p.inputStream.bufferedReader(Charsets.UTF_8).useLines { lines ->
                for (raw in lines) {
                    val line = raw.trim()
                    if (line.isEmpty() || line.startsWith("║") || line.startsWith("╔") || line.startsWith("╚")) continue
                    when {
                        line.startsWith("CAPTCHA_SOLVE|") -> onCaptcha(line)
                        line.contains("Сохранён в $CONF") -> onConfig()
                        else -> {
                            // the client prints the password nowhere, but just in case
                            val safe = if (password.isNotEmpty()) line.replace(password, "***") else line
                            if (isNoteworthy(safe)) VpnStore.log(ctx, "qWDTT: ${safe.take(300)}")
                            if (safe.contains("ошибк", true) || safe.contains("error", true) || safe.contains("капч", true)) {
                                lastError = safe.substringAfter("] ").take(200)
                            }
                        }
                    }
                }
            }
        } catch (_: Throwable) {
        }
        val code = runCatching { p.waitFor() }.getOrDefault(-1)
        QwdttCaptcha.cancel(ctx, this)
        val reason = if (cancelled) "остановлен" else "клиент завершился (код $code)" + (lastError?.let { ": $it" } ?: "")
        if (ready.count > 0) {
            failure = "qWDTT: $reason"
            ready.countDown()
        } else if (!cancelled) {
            VpnStore.log(ctx, "qWDTT: $reason")
            onExit?.invoke("qWDTT: $reason")
        }
    }

    private fun isNoteworthy(line: String) =
        line.contains("[КЛИЕНТ]") || line.contains("[КАПЧА]") || line.contains("[CREDS]") ||
            line.contains("ошибк", true) || line.contains("error", true) || line.contains("fail", true)

    /** The server's WireGuard config arrived: an Xray wireguard outbound's settings. */
    private fun onConfig() {
        if (ready.count == 0L) return
        val conf = runCatching { File(dir, CONF).readText() }.getOrNull()
        val parsed = conf?.let { runCatching { outboundSettings(it, port) }.getOrNull() }
        if (parsed == null) {
            failure = "qWDTT: сервер прислал непонятный конфиг WireGuard"
        } else {
            settings = parsed
            VpnStore.log(ctx, "qWDTT: конфиг WireGuard получен")
        }
        runCatching { File(dir, CONF).delete() } // it holds the private key
        ready.countDown()
    }

    /**
     * `CAPTCHA_SOLVE|mode|redirect_uri|session_token`. "auto" is the client's short try of a hidden
     * WebView: Orbit has none, so it answers at once and the client goes on with its own solver.
     * "manual"/"selected" means a person has to: Orbit shows VK's window (see CaptchaActivity).
     */
    private fun onCaptcha(line: String) {
        val parts = line.removePrefix("CAPTCHA_SOLVE|").split("|", limit = 3)
        val mode = parts.getOrNull(0).orEmpty()
        val uri = parts.getOrNull(1).orEmpty()
        if (mode == "auto" || !uri.startsWith("https://")) {
            answerCaptcha(if (uri.startsWith("https://")) "error:unsupported" else "error:invalid CAPTCHA_SOLVE format")
            return
        }
        VpnStore.log(ctx, "qWDTT: ВК просит капчу")
        QwdttCaptcha.request(ctx, this, uri)
    }

    /** The success token from VK's window, or "error:…". */
    fun answerCaptcha(result: String) {
        val clean = result.replace("\n", " ").replace("\r", " ").trim()
        synchronized(lock) {
            runCatching {
                stdin?.apply {
                    write("CAPTCHA_RESULT|$clean\n")
                    flush()
                }
            }
        }
    }

    /** Stops the client; safe from any thread, also while [start] waits. */
    fun stop() {
        cancelled = true
        QwdttCaptcha.cancel(ctx, this)
        val p = synchronized(lock) {
            runCatching {
                stdin?.apply {
                    write("STOP\n")
                    flush()
                }
            }
            process.also { process = null }
        }
        if (ready.count > 0) {
            failure = "Подключение отменено"
            ready.countDown()
        }
        p ?: return
        // "STOP" lets it close its relays; a stuck one is killed
        if (runCatching { p.waitFor(2, TimeUnit.SECONDS) }.getOrDefault(false) != true) p.destroyForcibly()
        runCatching { File(dir, CONF).delete() }
    }

    companion object {
        const val DEFAULT_PORT = 9000
        private const val CONF = "wg-turn.conf"
        private const val START_TIMEOUT_MS = 180_000L

        private fun JSONArray?.strings(): List<String> =
            if (this == null) emptyList() else (0 until length()).map { optString(it).trim() }

        /**
         * A WireGuard config (`[Interface]`/`[Peer]`, as wg-quick writes it) as the settings of an
         * Xray wireguard outbound, its endpoint the qWDTT client on 127.0.0.1:[port].
         */
        fun outboundSettings(conf: String, port: Int): JSONObject {
            var section = ""
            val iface = mutableMapOf<String, String>()
            val peer = mutableMapOf<String, String>()
            for (raw in conf.lines()) {
                val line = raw.substringBefore('#').trim()
                if (line.isEmpty()) continue
                if (line.startsWith("[")) {
                    section = line.lowercase()
                    continue
                }
                val key = line.substringBefore('=').trim().lowercase()
                val value = line.substringAfter('=', "").trim()
                if (value.isEmpty()) continue
                when (section) {
                    "[interface]" -> iface[key] = value
                    "[peer]" -> peer[key] = value
                }
            }
            val secret = iface["privatekey"] ?: throw IllegalArgumentException("no PrivateKey")
            val publicKey = peer["publickey"] ?: throw IllegalArgumentException("no PublicKey")
            val addresses = iface["address"]?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()
            if (addresses.isEmpty()) throw IllegalArgumentException("no Address")

            val peerJson = JSONObject()
                .put("publicKey", publicKey)
                .put("endpoint", "127.0.0.1:$port")
                .put("allowedIPs", JSONArray().put("0.0.0.0/0").put("::/0"))
                .put("keepAlive", peer["persistentkeepalive"]?.toIntOrNull() ?: 25)
            peer["presharedkey"]?.let { peerJson.put("preSharedKey", it) }

            return JSONObject()
                .put("secretKey", secret)
                .put("address", JSONArray(addresses))
                .put("peers", JSONArray().put(peerJson))
                .put("mtu", iface["mtu"]?.toIntOrNull()?.coerceIn(1000, 1420) ?: 1280)
                .put("noKernelTun", true)
        }
    }
}
