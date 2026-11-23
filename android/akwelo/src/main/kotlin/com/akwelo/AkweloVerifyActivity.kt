package com.akwelo

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.http.SslError
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Full-screen WebView hosting the Akwelo capture page. Internal; start it via [Akwelo.verify] or
 * [AkweloVerifyContract]. Every way out of this screen ends in exactly one [VerifyResult].
 */
class AkweloVerifyActivity : AppCompatActivity() {
    private var webView: WebView? = null
    private lateinit var spinner: ProgressBar
    private lateinit var baseUrl: String
    private var requestId: String? = null
    private var pendingPermission: PermissionRequest? = null
    private var delivered = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestId = intent.getStringExtra(EXTRA_REQUEST_ID)
        Akwelo.attached(requestId)
        val token = intent.getStringExtra(EXTRA_TOKEN)
        baseUrl = intent.getStringExtra(EXTRA_BASE_URL) ?: AkweloOptions.DEFAULT_BASE_URL
        precheck(token, AkweloOptions(baseUrl))?.let { return finishWith(it) }
        val origin = VerifyUrl.validBaseOrigin(baseUrl) ?: return
        token ?: return

        val web = try {
            WebView(this)
        } catch (e: RuntimeException) {
            // No WebView on this device right now (disabled, or being updated by the Play Store).
            return finishWith(VerifyResult.error("webview_unavailable", e.message ?: "WebView is not available"))
        }
        webView = web
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            allowFileAccess = false
            allowContentAccess = false
            setGeolocationEnabled(false)
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            // Injected only into main-frame documents from the Akwelo origin.
            WebViewCompat.addWebMessageListener(web, "AkweloBridge", setOf(origin)) { _, msg, src, isMainFrame, _ ->
                if (isMainFrame && VerifyUrl.isTrusted(src.toString(), baseUrl)) {
                    VerifyResult.parse(msg.data)?.let { runOnUiThread { finishWith(it) } }
                }
            }
        } else {
            // Legacy fallback: interface is visible to every page, so check the current top-level origin.
            web.addJavascriptInterface(AkweloJsBridge { json ->
                runOnUiThread {
                    if (VerifyUrl.isTrusted(webView?.url, baseUrl)) VerifyResult.parse(json)?.let { finishWith(it) }
                }
            }, "AkweloBridge")
        }
        web.webViewClient = Client()
        web.webChromeClient = Chrome()

        spinner = ProgressBar(this)
        val root = FrameLayout(this)
        root.addView(web, FrameLayout.LayoutParams(MATCH, MATCH))
        root.addView(spinner, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        // Edge-to-edge (the default from Android 15): keep the page, and its Cancel button, clear
        // of the status bar, the navigation bar and the camera cutout.
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            // Consumed: the page must not add the same insets again through CSS safe-area values.
            WindowInsetsCompat.CONSUMED
        }
        setContentView(root)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = finishWith(VerifyResult.cancelled())
        })

        val projectNumber = intent.getLongExtra(EXTRA_CLOUD_PROJECT, -1L)
        lifecycleScope.launch {
            // Attestation is best-effort: the page never waits on Google Play services.
            val attest = if (projectNumber <= 0) null else withTimeoutOrNull(AkweloOptions.ATTESTATION_TIMEOUT_MS) {
                PlayIntegrity.token(this@AkweloVerifyActivity, projectNumber, token)
            }
            if (!delivered) webView?.loadUrl(VerifyUrl.build(baseUrl, token, attest))
        }
    }

    private inner class Client : WebViewClient() {
        // Keep the WebView on the Akwelo origin; never hand the bridge to another site. A link the
        // person tapped (privacy notice, help) opens in their browser instead.
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            if (!request.isForMainFrame || VerifyUrl.isTrusted(request.url.toString(), baseUrl)) return false
            if (request.hasGesture() && request.url.scheme in WEB_SCHEMES) {
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, request.url).addCategory(Intent.CATEGORY_BROWSABLE))
                } catch (_: ActivityNotFoundException) {
                    // No browser installed: the link does nothing, capture carries on.
                }
            }
            return true
        }

        override fun onPageCommitVisible(view: WebView, url: String) {
            spinner.visibility = View.GONE
        }

        // The capture page itself did not load. WebView's own error page prints the URL, session
        // token included, so the screen closes with an error instead of showing it.
        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (isCapturePage(request)) {
                finishWith(VerifyResult.error("page_load_failed", error.description?.toString() ?: "The capture page did not load"))
            }
        }

        override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
            if (isCapturePage(request)) {
                finishWith(VerifyResult.error("page_load_failed", "The capture page answered HTTP ${response.statusCode}"))
            }
        }

        override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
            handler.cancel() // never proceed past a certificate error
            if (VerifyUrl.isTrusted(error.url, baseUrl)) {
                finishWith(VerifyResult.error("page_load_failed", "The capture page's certificate was not accepted"))
            }
        }

        // The page's process died (low memory is the usual cause). Without this override Android
        // kills the host app too. The WebView is unusable from here on.
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            (view.parent as? ViewGroup)?.removeView(view)
            view.destroy()
            if (view === webView) webView = null
            finishWith(VerifyResult.error("webview_crashed", "The capture page stopped unexpectedly"))
            return true
        }

        private fun isCapturePage(request: WebResourceRequest) =
            request.isForMainFrame && VerifyUrl.isTrusted(request.url.toString(), baseUrl)
    }

    private inner class Chrome : WebChromeClient() {
        override fun onPermissionRequest(request: PermissionRequest) {
            val wantsCamera = request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)
            val trusted = VerifyUrl.isTrusted(request.origin.toString(), baseUrl)
            if (!wantsCamera || !trusted) return request.deny()
            if (hasCamera()) request.grant(CAMERA_ONLY)
            else {
                pendingPermission = request
                ActivityCompat.requestPermissions(
                    this@AkweloVerifyActivity, arrayOf(Manifest.permission.CAMERA), REQ_CAMERA
                )
            }
        }

        override fun onPermissionRequestCanceled(request: PermissionRequest) {
            if (pendingPermission === request) pendingPermission = null
        }
    }

    private fun hasCamera() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_CAMERA) return
        val req = pendingPermission ?: return
        pendingPermission = null
        if (hasCamera()) req.grant(CAMERA_ONLY) else req.deny()
    }

    private fun finishWith(result: VerifyResult) {
        if (delivered) return
        delivered = true
        setResult(RESULT_OK, result.toIntent())
        Akwelo.deliver(requestId, result)
        finish()
    }

    override fun onDestroy() {
        // Closed without a result (the task was removed, the host finished us): report cancellation
        // once. Not when Android is only recreating the screen: the capture carries on then.
        if (!delivered && isFinishing) {
            delivered = true
            Akwelo.deliver(requestId, VerifyResult.cancelled())
        }
        webView?.let {
            (it.parent as? ViewGroup)?.removeView(it)
            it.destroy()
        }
        webView = null
        super.onDestroy()
    }

    internal companion object {
        const val EXTRA_TOKEN = "akwelo.token"
        const val EXTRA_BASE_URL = "akwelo.baseUrl"
        const val EXTRA_CLOUD_PROJECT = "akwelo.cloudProject"
        const val EXTRA_REQUEST_ID = "akwelo.requestId"
        private const val REQ_CAMERA = 0xA1
        private const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        private const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
        private val CAMERA_ONLY = arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE)
        private val WEB_SCHEMES = setOf("https", "http")

        fun intent(context: Context, sessionToken: String, options: AkweloOptions, requestId: String?): Intent {
            val intent = Intent(context, AkweloVerifyActivity::class.java)
                .putExtra(EXTRA_TOKEN, sessionToken)
                .putExtra(EXTRA_BASE_URL, options.baseUrl)
                .putExtra(EXTRA_REQUEST_ID, requestId)
            options.playIntegrityCloudProjectNumber?.let { intent.putExtra(EXTRA_CLOUD_PROJECT, it) }
            return intent
        }
    }
}

/** Exposed to the page as `window.AkweloBridge.postMessage(json)`. */
internal class AkweloJsBridge(private val onMessage: (String) -> Unit) {
    @JavascriptInterface
    fun postMessage(json: String) = onMessage(json)
}
