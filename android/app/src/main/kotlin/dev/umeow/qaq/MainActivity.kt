package dev.umeow.qaq

import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.Log
import java.util.concurrent.Executor

class MainActivity : FlutterActivity() {
    private val CHANNEL = "qaq/global"
    private val logTag = "FlutterActivity"
    private val mainExecutor = Executor { command -> runOnUiThread(command) }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update_home_screen_weight" -> {
                    Log.i(logTag, "update_weight")
                    try {
                        val intend = Intent("android.appwidget.action.APPWIDGET_UPDATE")
                        this.sendBroadcast(intend)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                        Log.e(logTag, e.toString())
                    }
                }
                "get_feedback_device_info" -> {
                    result.success(
                        mapOf(
                            "model" to Build.MODEL,
                            "androidRelease" to Build.VERSION.RELEASE,
                        ),
                    )
                }
                "set_webview_proxy_override" -> {
                    val port = call.argument<Int>("port")
                    val host = call.argument<String>("host")
                    if (port == null || port !in 1..65535 || host.isNullOrBlank()) {
                        result.error("INVALID_PROXY_ARGUMENTS", "A valid proxy port and host are required.", null)
                    } else {
                        setWebViewProxyOverride(port, host, result)
                    }
                }
                "clear_webview_proxy_override" -> clearWebViewProxyOverride(result)
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setWebViewProxyOverride(port: Int, host: String, result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.error(
                "WEBVIEW_PROXY_UNSUPPORTED",
                "Android WebView ProxyOverride is not supported on this device.",
                null,
            )
            return
        }

        try {
            val reverseBypassSupported =
                WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE_REVERSE_BYPASS)
            val builder = ProxyConfig.Builder()
                .addProxyRule("http://127.0.0.1:$port")

            if (reverseBypassSupported) {
                builder
                    .addBypassRule(host)
                    .setReverseBypassEnabled(true)
            } else {
                builder
                    .addBypassRule("127.0.0.1")
                    .addBypassRule("localhost")
            }

            ProxyController.getInstance().setProxyOverride(
                builder.build(),
                mainExecutor,
            ) {
                result.success(reverseBypassSupported)
            }
        } catch (e: Exception) {
            Log.e(logTag, "Unable to apply WebView proxy override", e)
            result.error("WEBVIEW_PROXY_ERROR", e.message, null)
        }
    }

    private fun clearWebViewProxyOverride(result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(null)
            return
        }

        try {
            ProxyController.getInstance().clearProxyOverride(mainExecutor) {
                result.success(null)
            }
        } catch (e: Exception) {
            Log.e(logTag, "Unable to clear WebView proxy override", e)
            result.error("WEBVIEW_PROXY_ERROR", e.message, null)
        }
    }
}
