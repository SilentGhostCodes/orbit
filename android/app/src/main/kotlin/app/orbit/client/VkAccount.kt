package app.orbit.client

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * qWDTT's «аккаунт ВК» mode: TURN credentials taken from the user's own VK session instead of
 * anonymous VK API calls. With the session (a WebView login, cookies kept by the VPN process's
 * WebView), joining the call page in a hidden WebView makes VK answer with `turn_server`
 * {username, credential, urls}, which qWDTT's client takes (a creds file at start,
 * `TURN_CREDS|hash|base64` later, when it asks with `VK_AUTH_REQUIRED|hash`). If the hidden join
 * does not get there (VK asks for something), the same page opens for the user.
 *
 * Everything with a WebView runs in the VPN process ([VkActivity] too): one WebView profile, one
 * set of VK cookies.
 */
object VkAccount {
    data class Turn(val user: String, val pass: String, val urls: List<String>) {
        fun toJson(): JSONObject = JSONObject().put("u", user).put("p", pass).put("urls", JSONArray(urls))
    }

    class NoSessionException : IllegalStateException("Войди в аккаунт ВК: Настройки → qWDTT → Вход в ВК")

    private const val CHANNEL = "orbit_vk"
    private const val NOTIFICATION = 3
    private const val HIDDEN_JOIN_MS = 25_000L
    private const val VISIBLE_JOIN_MS = 180_000L

    private val main = Handler(Looper.getMainLooper())
    private val VK_URLS = listOf(
        "https://vk.com", "https://vk.ru", "https://m.vk.com", "https://m.vk.ru",
        "https://id.vk.com", "https://id.vk.ru", "https://login.vk.com", "https://login.vk.ru",
    )

    /** For the app process, which has no WebView: written here on login and logout. */
    fun statusFile(ctx: Context) = File(ctx.filesDir, "vk_account.json")

    /** One join at a time: VK's call page is one session. */
    private val joinLock = Any()

    // the visible join the user is asked for, while one waits
    private val visibleLock = Any()
    private var visibleHash: String? = null
    private var visibleLatch: CountDownLatch? = null
    private var visibleResult: Turn? = null

    @Volatile private var cancelled = false

    private fun <T> onMain(timeoutMs: Long = 5_000, block: () -> T): T? {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        var result: T? = null
        val done = CountDownLatch(1)
        main.post {
            try {
                result = block()
            } finally {
                done.countDown()
            }
        }
        done.await(timeoutMs, TimeUnit.MILLISECONDS)
        return result
    }

    fun hasSession(): Boolean = onMain {
        val cm = CookieManager.getInstance()
        VK_URLS.any { url -> cm.getCookie(url)?.split(';')?.any { it.trim().startsWith("remixsid=") && it.trim().length > 9 } == true }
    } ?: false

    fun saveStatus(ctx: Context) {
        val logged = hasSession()
        runCatching {
            if (logged) statusFile(ctx).writeText(JSONObject().put("loggedIn", true).put("at", System.currentTimeMillis()).toString())
            else statusFile(ctx).delete()
        }
    }

    fun logout(ctx: Context) {
        onMain {
            CookieManager.getInstance().apply {
                removeAllCookies(null)
                flush()
            }
        }
        runCatching { statusFile(ctx).delete() }
        VpnStore.log(ctx, "ВК: выход из аккаунта")
    }

    /** Cuts short whatever join is waiting (the tunnel stops). */
    fun cancel(ctx: Context) {
        cancelled = true
        synchronized(visibleLock) {
            visibleResult = null
            visibleLatch?.countDown()
        }
        clearPrompt(ctx)
    }

    /**
     * TURN credentials for [hash] from the user's VK session: a hidden join first, then the page
     * shown to the user. Blocks; not on the main thread.
     */
    fun turn(ctx: Context, hash: String): Turn = synchronized(joinLock) {
        cancelled = false
        if (!hasSession()) throw NoSessionException()
        hiddenJoin(ctx.applicationContext, hash)?.let { return it }
        if (cancelled) throw IllegalStateException("Подключение отменено")
        VpnStore.log(ctx, "ВК: скрытый вход в звонок не удался, нужен ты")
        visibleJoin(ctx, hash)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun hiddenJoin(ctx: Context, hash: String): Turn? {
        val done = CountDownLatch(1)
        var result: Turn? = null
        var web: WebView? = null
        var urlIndex = 0
        val tick = object : Runnable {
            override fun run() {
                val view = web ?: return
                view.evaluateJavascript(JOIN_CLICK, null)
                main.postDelayed(this, 1_500)
            }
        }
        main.post {
            try {
                web = WebView(ctx).apply {
                    setup(this)
                    addJavascriptInterface(object {
                        @JavascriptInterface
                        fun onTurnServer(json: String) {
                            parseTurn(json)?.let {
                                result = it
                                done.countDown()
                            }
                        }
                    }, "OrbitVk")
                    webViewClient = object : WebViewClient() {
                        override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                            view.evaluateJavascript(TURN_INTERCEPTOR, null)
                        }

                        override fun onPageFinished(view: WebView, url: String?) {
                            view.evaluateJavascript(TURN_INTERCEPTOR, null)
                            view.evaluateJavascript(NOT_FOUND) { r ->
                                // m.vk.ru may not know the call: the next address
                                if (r?.contains("404") == true && urlIndex < joinUrls(hash).size - 1) {
                                    urlIndex++
                                    view.loadUrl(joinUrls(hash)[urlIndex])
                                }
                            }
                        }
                    }
                    loadUrl(joinUrls(hash)[0])
                }
                main.postDelayed(tick, 2_000)
            } catch (_: Throwable) {
                done.countDown()
            }
        }
        val waited = System.currentTimeMillis()
        while (!done.await(500, TimeUnit.MILLISECONDS)) {
            if (cancelled || System.currentTimeMillis() - waited > HIDDEN_JOIN_MS) break
        }
        main.post {
            main.removeCallbacks(tick)
            web?.apply {
                stopLoading()
                removeJavascriptInterface("OrbitVk")
                destroy()
            }
            web = null
        }
        return result
    }

    private fun visibleJoin(ctx: Context, hash: String): Turn {
        val latch = CountDownLatch(1)
        synchronized(visibleLock) {
            visibleHash = hash
            visibleLatch = latch
            visibleResult = null
        }
        prompt(ctx, "join", "ВК: подтверди вход в звонок", "Нажми — без этого qWDTT не подключится", VkActivity.joinIntent(ctx))
        try {
            latch.await(VISIBLE_JOIN_MS, TimeUnit.MILLISECONDS)
            return synchronized(visibleLock) { visibleResult }
                ?: throw IllegalStateException(if (cancelled) "Подключение отменено" else "ВК: вход в звонок не подтверждён")
        } finally {
            synchronized(visibleLock) {
                visibleHash = null
                visibleLatch = null
            }
            clearPrompt(ctx)
            VkActivity.current?.let { a -> a.runOnUiThread { if (a.mode == VkActivity.MODE_JOIN) a.finish() } }
        }
    }

    /** The call the user is asked to join, while one waits. */
    fun pendingJoin(): String? = synchronized(visibleLock) { visibleHash }

    /** From [VkActivity]: the call page answered with TURN credentials (null: closed without). */
    fun joined(turn: Turn?) {
        synchronized(visibleLock) {
            if (visibleLatch == null) return
            visibleResult = turn
            visibleLatch?.countDown()
        }
    }

    // --- the home screen's prompt and the notification ---

    private fun prompt(ctx: Context, action: String, title: String, text: String, intent: Intent) {
        VpnStore.publishVk(ctx, action)
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Вход в ВК", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(
            ctx, 3, intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(ctx, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(ctx)
        runCatching {
            nm.notify(
                NOTIFICATION,
                builder.setSmallIcon(R.drawable.ic_stat_orbit)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .build(),
            )
        }
    }

    private fun clearPrompt(ctx: Context) {
        ctx.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION)
        VpnStore.publishVk(ctx, null, onlyIf = "join")
    }

    // --- shared WebView bits ---

    fun joinUrls(hash: String) = listOf(
        "https://m.vk.ru/call/join/$hash",
        "https://vk.ru/call/join/$hash",
        "https://m.vk.com/call/join/$hash",
        "https://vk.com/call/join/$hash",
    )

    @SuppressLint("SetJavaScriptEnabled")
    fun setup(view: WebView) {
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            cacheMode = WebSettings.LOAD_DEFAULT
        }
        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(view, true)
        }
    }

    fun parseTurn(json: String): Turn? = runCatching {
        val o = JSONObject(json)
        val urls = when (val u = o.opt("urls")) {
            is JSONArray -> (0 until u.length()).map { u.optString(it) }
            is String -> listOf(u)
            else -> emptyList()
        }.map { it.trim() }.filter { it.isNotEmpty() }
        val user = o.optString("username")
        val pass = o.optString("credential")
        if (user.isBlank() || pass.isBlank() || urls.isEmpty()) null else Turn(user, pass, urls)
    }.getOrNull()

    /** Catches the `turn_server` VK's call API answers with, in fetch and XHR responses. */
    val TURN_INTERCEPTOR = """
        (function() {
          if (window.__orbitTurn) return;
          window.__orbitTurn = true;
          function look(text) {
            if (!text || text.indexOf('turn_server') < 0) return;
            try {
              var d = JSON.parse(text);
              var t = d.turn_server || (d.response && d.response.turn_server);
              if (t && t.username && t.credential && t.urls) OrbitVk.onTurnServer(JSON.stringify(t));
            } catch (e) {}
          }
          var f = window.fetch;
          if (f) window.fetch = function() {
            var p = f.apply(this, arguments);
            p.then(function(r) { r.clone().text().then(look).catch(function() {}); }).catch(function() {});
            return p;
          };
          var send = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.send = function() {
            var x = this;
            x.addEventListener('load', function() { try { look(x.responseText); } catch (e) {} });
            return send.apply(this, arguments);
          };
        })();
    """.trimIndent()

    /** Presses the call page's «Присоединиться» / «Продолжить в браузере», never «Открыть в приложении». */
    val JOIN_CLICK = """
        (function() {
          var bad = ['в приложении', 'in app', 'скачать', 'vk звонки'];
          var good = [['продолжить в браузере', 100], ['continue in browser', 95], ['присоединиться', 90], ['join', 80],
                      ['войти в звонок', 70], ['продолжить', 50], ['continue', 45]];
          var best = null, score = 0;
          document.querySelectorAll('button, a, [role="button"]').forEach(function(el) {
            var t = (el.innerText || el.textContent || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().toLowerCase();
            if (!t || t.length > 60) return;
            for (var i = 0; i < bad.length; i++) if (t.indexOf(bad[i]) >= 0) return;
            for (var j = 0; j < good.length; j++) {
              if (t.indexOf(good[j][0]) >= 0) {
                var s = good[j][1] - t.length / 10;
                if (s > score) { score = s; best = el; }
                break;
              }
            }
          });
          if (best) { try { best.click(); } catch (e) {} }
        })();
    """.trimIndent()

    val NOT_FOUND =
        "(function(){var t=document.body?document.body.innerText:'';return t.indexOf('Такой страницы нет')>=0||t.indexOf('Страница не найдена')>=0?'404':'';})();"
}

/**
 * VK in a WebView, in the VPN process: signing in (from Настройки → qWDTT) or joining a call the
 * hidden WebView could not (from the prompt while connecting).
 */
class VkActivity : Activity() {
    var mode = MODE_LOGIN
        private set
    private var web: WebView? = null
    private var finished = false
    private val main = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            web?.evaluateJavascript(VkAccount.JOIN_CLICK, null)
            main.postDelayed(this, 2_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_LOGIN
        if (mode == MODE_LOGOUT) {
            VkAccount.logout(applicationContext)
            finish()
            overridePendingTransition(0, 0)
            return
        }
        val hash = if (mode == MODE_JOIN) VkAccount.pendingJoin() else null
        if (mode == MODE_JOIN && hash == null) {
            finish()
            return
        }
        current = this

        val title = TextView(this).apply {
            text = if (mode == MODE_JOIN) "Вход в звонок ВК" else "Вход в ВК"
            setTextColor(Color.parseColor("#F2F2F0"))
            textSize = 17f
            setPadding(48, 48, 48, 8)
        }
        val hint = TextView(this).apply {
            text = if (mode == MODE_JOIN) {
                "Если ВК спросит — нажми «Присоединиться». Окно закроется само"
            } else {
                "qWDTT берёт доступ к звонкам из твоего аккаунта. Пароль видит только ВК"
            }
            setTextColor(Color.parseColor("#8E8F94"))
            textSize = 13f
            setPadding(48, 0, 48, 24)
        }
        val close = TextView(this).apply {
            text = "Закрыть"
            setTextColor(Color.parseColor("#8E8F94"))
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(48, 36, 48, 48)
            setOnClickListener { finish() }
        }
        val view = WebView(this).apply {
            VkAccount.setup(this)
            addJavascriptInterface(Bridge(), "OrbitVk")
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                    if (mode == MODE_JOIN) view.evaluateJavascript(VkAccount.TURN_INTERCEPTOR, null)
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    if (mode == MODE_JOIN) {
                        view.evaluateJavascript(VkAccount.TURN_INTERCEPTOR, null)
                    } else if (VkAccount.hasSession() && !url.orEmpty().contains("/login")) {
                        // signed in: VK left the login pages
                        CookieManager.getInstance().flush()
                        VkAccount.saveStatus(applicationContext)
                        VpnStore.log(applicationContext, "ВК: вход выполнен")
                        finish()
                    }
                }

                // VK ID may hand over to its own app: stay in the WebView
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val scheme = request.url.scheme.orEmpty()
                    return scheme != "https" && scheme != "http"
                }
            }
        }
        web = view
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(Color.parseColor("#1B1C1F"))
                addView(title)
                addView(hint)
                addView(
                    FrameLayout(this@VkActivity).apply { addView(view) },
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
                )
                addView(close)
            },
        )
        if (mode == MODE_JOIN) {
            view.loadUrl(VkAccount.joinUrls(hash!!)[0])
            main.postDelayed(tick, 2_000)
        } else {
            view.loadUrl("https://m.vk.ru/login")
        }
    }

    override fun onDestroy() {
        main.removeCallbacks(tick)
        if (current === this) current = null
        if (mode == MODE_JOIN && !finished) {
            finished = true
            VkAccount.joined(null)
        }
        if (mode == MODE_LOGIN) VkAccount.saveStatus(applicationContext)
        web?.apply {
            removeJavascriptInterface("OrbitVk")
            destroy()
        }
        web = null
        super.onDestroy()
    }

    private inner class Bridge {
        @JavascriptInterface
        fun onTurnServer(json: String) {
            val turn = VkAccount.parseTurn(json) ?: return
            main.post {
                if (finished) return@post
                finished = true
                VkAccount.joined(turn)
                finish()
            }
        }
    }

    companion object {
        const val EXTRA_MODE = "mode"
        const val MODE_LOGIN = "login"
        const val MODE_JOIN = "join"
        const val MODE_LOGOUT = "logout"

        @Volatile
        var current: VkActivity? = null

        fun intent(ctx: Context, mode: String) = Intent(ctx, VkActivity::class.java).putExtra(EXTRA_MODE, mode)

        fun joinIntent(ctx: Context) = intent(ctx, MODE_JOIN)
    }
}
