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
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * VK's «не робот» check, when qWDTT's client cannot pass it by itself. The request lives here, in
 * the VPN process, next to the client waiting for the answer; [CaptchaActivity] runs in the same
 * process. The user gets there from a notification or from the app (status `captcha`).
 */
object QwdttCaptcha {
    private const val CHANNEL = "orbit_captcha"
    private const val NOTIFICATION = 2

    private val lock = Any()
    private var tunnel: QwdttTunnel? = null
    private var url: String? = null

    /** The page VK wants solved, while one is waiting. */
    fun pendingUrl(): String? = synchronized(lock) { url }

    fun request(ctx: Context, from: QwdttTunnel, redirectUri: String) {
        synchronized(lock) {
            tunnel = from
            url = redirectUri
        }
        VpnStore.publishVk(ctx, "captcha")
        notify(ctx)
        // a window already open shows the new page
        CaptchaActivity.current?.let { activity -> activity.runOnUiThread { activity.load() } }
    }

    /** The window's answer: VK's success token, or "error:…". Each request is answered once. */
    fun answer(ctx: Context, result: String) {
        val target = synchronized(lock) {
            tunnel.also {
                tunnel = null
                url = null
            }
        } ?: return
        target.answerCaptcha(result)
        clear(ctx)
    }

    /** The client stopped or gave up waiting: the window and notification go away. */
    fun cancel(ctx: Context, from: QwdttTunnel) {
        val window = synchronized(lock) {
            if (tunnel !== from) return
            tunnel = null
            url = null
            CaptchaActivity.current
        }
        window?.runOnUiThread { window.finish() }
        clear(ctx)
    }

    fun clear(ctx: Context) {
        ctx.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION)
        VpnStore.publishVk(ctx, null, onlyIf = "captcha")
    }

    private fun notify(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Капча ВК", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(
            ctx, 2,
            Intent(ctx, CaptchaActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(ctx, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(ctx)
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_orbit)
            .setContentTitle("ВК просит капчу")
            .setContentText("Нажми, чтобы подтвердить — иначе qWDTT не подключится")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_CALL)
            .build()
        runCatching { nm.notify(NOTIFICATION, n) }
    }
}

/**
 * VK's captcha page in a WebView. A script catches the answer to `captchaNotRobot.check` (as
 * qWDTT's own app does) and hands its success_token to the waiting client.
 */
class CaptchaActivity : Activity() {
    private var web: WebView? = null
    private var answered = false
    private val main = Handler(Looper.getMainLooper())

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = this
        if (QwdttCaptcha.pendingUrl() == null) {
            finish()
            return
        }
        val title = TextView(this).apply {
            text = "Подтверди, что ты не робот"
            setTextColor(Color.parseColor("#F2F2F0"))
            textSize = 17f
            setPadding(48, 48, 48, 8)
        }
        val hint = TextView(this).apply {
            text = "Это проверка ВКонтакте: без неё звонок не даст подключиться"
            setTextColor(Color.parseColor("#8E8F94"))
            textSize = 13f
            setPadding(48, 0, 48, 24)
        }
        val cancel = TextView(this).apply {
            text = "Отмена"
            setTextColor(Color.parseColor("#8E8F94"))
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(48, 36, 48, 48)
            setOnClickListener { finishWith("error:cancelled") }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        val view = WebView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            addJavascriptInterface(Bridge(), "OrbitCaptcha")
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                    view.evaluateJavascript(INTERCEPTOR, null)
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    view.evaluateJavascript(INTERCEPTOR, null)
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
                addView(FrameLayout(this@CaptchaActivity).apply { addView(view) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
                addView(cancel)
            },
        )
        load()
    }

    fun load() {
        val url = QwdttCaptcha.pendingUrl() ?: return finish()
        answered = false
        web?.loadUrl(url)
    }

    private fun finishWith(result: String) {
        if (answered) return
        answered = true
        QwdttCaptcha.answer(applicationContext, result)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() = finishWith("error:cancelled")

    override fun onDestroy() {
        if (current === this) current = null
        // closed without an answer (swiped away): the client is told, rather than left waiting
        if (!answered && !isChangingConfigurations) {
            answered = true
            QwdttCaptcha.answer(applicationContext, "error:cancelled")
        }
        web?.apply {
            removeJavascriptInterface("OrbitCaptcha")
            destroy()
        }
        web = null
        super.onDestroy()
    }

    private inner class Bridge {
        @JavascriptInterface
        fun onSuccess(token: String) {
            if (token.isBlank() || token.length > 4096) return
            main.post { finishWith(token.trim()) }
        }

        @JavascriptInterface
        fun onError(error: String) {
            // a failed try: VK shows a new task in the same window
            VpnStore.log(applicationContext, "qWDTT: капча не принята: ${error.take(160)}")
        }
    }

    companion object {
        @Volatile
        var current: CaptchaActivity? = null

        private val INTERCEPTOR = """
            (function() {
              if (window.__orbitCaptcha) return;
              window.__orbitCaptcha = true;
              function handle(data) {
                if (data && data.response && data.response.success_token) {
                  OrbitCaptcha.onSuccess(data.response.success_token);
                } else if (data && data.error) {
                  OrbitCaptcha.onError(JSON.stringify(data.error));
                }
              }
              var fetch0 = window.fetch;
              if (fetch0) window.fetch = function() {
                var url = arguments[0];
                var u = typeof url === 'string' ? url : (url && url.url) || '';
                var p = fetch0.apply(this, arguments);
                if (u.indexOf('captchaNotRobot.check') >= 0) {
                  p.then(function(r) { r.clone().json().then(handle).catch(function() {}); }).catch(function() {});
                }
                return p;
              };
              var open0 = XMLHttpRequest.prototype.open, send0 = XMLHttpRequest.prototype.send;
              XMLHttpRequest.prototype.open = function(m, u) { this.__orbitUrl = u; return open0.apply(this, arguments); };
              XMLHttpRequest.prototype.send = function() {
                var x = this;
                if (x.__orbitUrl && String(x.__orbitUrl).indexOf('captchaNotRobot.check') >= 0) {
                  x.addEventListener('load', function() { try { handle(JSON.parse(x.responseText)); } catch (e) {} });
                }
                return send0.apply(this, arguments);
              };
            })();
        """.trimIndent()
    }
}
