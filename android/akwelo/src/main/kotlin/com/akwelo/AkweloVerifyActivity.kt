package com.akwelo

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.launch

/** Full-screen WebView hosting the Akwelo capture page. Internal; start it via [Akwelo.verify]. */
class AkweloVerifyActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private var pendingPermission: PermissionRequest? = null
    private var delivered = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val token = intent.getStringExtra(EXTRA_TOKEN)
        if (token.isNullOrBlank()) return finishWith(VerifyResult.error("missing session token"))
        val baseUrl = intent.getStringExtra(EXTRA_BASE_URL) ?: AkweloOptions.DEFAULT_BASE_URL

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            val origin = VerifyUrl.origin(baseUrl)
            if (origin != null && WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
                // Injected only into main-frame documents from the Akwelo origin.
                WebViewCompat.addWebMessageListener(this, "AkweloBridge", setOf(origin)) { _, msg, src, isMainFrame, _ ->
                    if (isMainFrame && VerifyUrl.isTrusted(src.toString(), baseUrl)) {
                        VerifyResult.parse(msg.data)?.let { finishWith(it) }
                    }
                }
            } else {
                // Legacy fallback: interface is visible to every page, so check the current top-level origin.
                addJavascriptInterface(AkweloJsBridge { json ->
                    runOnUiThread {
                        if (VerifyUrl.isTrusted(webView.url, baseUrl)) VerifyResult.parse(json)?.let { finishWith(it) }
                    }
                }, "AkweloBridge")
            }
            webViewClient = object : WebViewClient() {
                // Keep the WebView on the Akwelo origin; never hand the bridge to another site.
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    request.isForMainFrame && !VerifyUrl.isTrusted(request.url.toString(), baseUrl)
            }
            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) {
                    val wantsCamera = request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)
                    val trusted = VerifyUrl.isTrusted(request.origin.toString(), baseUrl)
                    if (!wantsCamera || !trusted) return request.deny()
                    if (hasCamera()) request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
                    else {
                        pendingPermission = request
                        ActivityCompat.requestPermissions(
                            this@AkweloVerifyActivity, arrayOf(Manifest.permission.CAMERA), REQ_CAMERA
                        )
                    }
                }
            }
        }
        setContentView(webView)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = finishWith(VerifyResult.cancelled())
        })

        val projectNumber = intent.getLongExtra(EXTRA_CLOUD_PROJECT, -1L)
        lifecycleScope.launch {
            val attest = if (projectNumber > 0) PlayIntegrity.token(this@AkweloVerifyActivity, projectNumber, token) else null
            webView.loadUrl(VerifyUrl.build(baseUrl, token, attest))
        }
    }

    private fun hasCamera() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_CAMERA) return
        val req = pendingPermission ?: return
        pendingPermission = null
        if (hasCamera()) req.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) else req.deny()
    }

    private fun finishWith(result: VerifyResult) {
        if (delivered) return
        delivered = true
        Akwelo.deliver(result)
        finish()
    }

    override fun onDestroy() {
        // Activity killed without a result (e.g. process death): report cancellation once.
        if (!delivered && isFinishing) {
            delivered = true
            Akwelo.deliver(VerifyResult.cancelled())
        }
        if (::webView.isInitialized) webView.destroy()
        super.onDestroy()
    }

    internal companion object {
        const val EXTRA_TOKEN = "akwelo.token"
        const val EXTRA_BASE_URL = "akwelo.baseUrl"
        const val EXTRA_CLOUD_PROJECT = "akwelo.cloudProject"
        private const val REQ_CAMERA = 0xA1
    }
}

/** Exposed to the page as `window.AkweloBridge.postMessage(json)`. */
internal class AkweloJsBridge(private val onMessage: (String) -> Unit) {
    @JavascriptInterface
    fun postMessage(json: String) = onMessage(json)
}
