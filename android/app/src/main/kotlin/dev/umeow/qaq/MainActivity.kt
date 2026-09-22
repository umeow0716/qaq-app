package dev.umeow.qaq

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.webkit.URLUtil
import androidx.annotation.NonNull
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.Log
import java.io.ByteArrayOutputStream
import java.nio.charset.Charset
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executor

class MainActivity : FlutterActivity() {
    private val CHANNEL = "qaq/global"
    private val logTag = "FlutterActivity"
    private val mainExecutor = Executor { command -> runOnUiThread(command) }
    private val filePickerRequestCode = 0x5141
    private var pendingFilePickerResult: MethodChannel.Result? = null

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
                "set_webview_cookie" -> setWebViewCookie(call, result)
                "pick_webview_files" -> pickWebViewFiles(call, result)
                "enqueue_webview_download" -> enqueueWebViewDownload(call, result)
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != filePickerRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val pending = pendingFilePickerResult
        pendingFilePickerResult = null
        if (pending == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(emptyList<String>())
            return
        }

        val uris = linkedSetOf<String>()
        data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.toString()?.let(uris::add)
            }
        }
        data.data?.toString()?.let(uris::add)
        pending.success(uris.toList())
    }

    @Suppress("DEPRECATION")
    private fun pickWebViewFiles(call: MethodCall, result: MethodChannel.Result) {
        if (pendingFilePickerResult != null) {
            result.error("FILE_PICKER_BUSY", "Another WebView file picker is already open.", null)
            return
        }

        val mode = call.argument<String>("mode") ?: "open"
        val capture = call.argument<Boolean>("capture") == true
        val acceptTypes = resolveMimeTypes(call.argument<List<String>>("acceptTypes") ?: emptyList())
        val intent = when {
            mode == "save" -> Intent(Intent.ACTION_CREATE_DOCUMENT)
            capture -> Intent(Intent.ACTION_GET_CONTENT)
            else -> Intent(Intent.ACTION_OPEN_DOCUMENT)
        }

        if (!capture) intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.type = if (acceptTypes.size == 1) acceptTypes.first() else "*/*"
        if (acceptTypes.size > 1 && !acceptTypes.contains("*/*")) {
            intent.putExtra(Intent.EXTRA_MIME_TYPES, acceptTypes.toTypedArray())
        }
        if (mode == "openMultiple") {
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        call.argument<String>("filenameHint")?.takeIf { it.isNotBlank() }?.let {
            intent.putExtra(Intent.EXTRA_TITLE, it)
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (mode == "save") {
            intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }

        pendingFilePickerResult = result
        try {
            startActivityForResult(intent, filePickerRequestCode)
        } catch (e: Exception) {
            pendingFilePickerResult = null
            Log.e(logTag, "Unable to open WebView file picker", e)
            result.error("FILE_PICKER_ERROR", e.message, null)
        }
    }

    private fun resolveMimeTypes(values: List<String>): List<String> {
        val resolved = values
            .flatMap { it.split(',') }
            .mapNotNull { raw ->
                val value = raw.trim().lowercase(Locale.US)
                when {
                    value.isEmpty() -> null
                    value == "*/*" -> value
                    value.startsWith(".") -> MimeTypeMap.getSingleton()
                        .getMimeTypeFromExtension(value.removePrefix("."))
                    value.contains("/") -> value
                    else -> null
                }
            }
            .distinct()
        return if (resolved.contains("*/*")) listOf("*/*") else resolved
    }

    private fun enqueueWebViewDownload(call: MethodCall, result: MethodChannel.Result) {
        val requestUrl = call.argument<String>("requestUrl")
        val sourceUrl = call.argument<String>("sourceUrl") ?: requestUrl
        if (requestUrl.isNullOrBlank() || sourceUrl.isNullOrBlank()) {
            result.error("INVALID_DOWNLOAD_ARGUMENTS", "A download URL is required.", null)
            return
        }

        val requestUri = Uri.parse(requestUrl)
        if (requestUri.scheme != "http" && requestUri.scheme != "https") {
            result.error("INVALID_DOWNLOAD_URL", "Only HTTP(S) downloads are supported.", null)
            return
        }

        try {
            val contentDisposition = call.argument<String>("contentDisposition")
            val mimeType = call.argument<String>("mimeType")
            val userAgent = call.argument<String>("userAgent")
            val cookie = call.argument<String>("cookie")
            val referer = call.argument<String>("referer")
            val keepAlive = call.argument<Boolean>("keepAlive") == true
            val filename = resolveBrowserLikeFilename(sourceUrl, contentDisposition, mimeType)

            val request = DownloadManager.Request(requestUri)
                .setTitle(filename)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)

            if (!mimeType.isNullOrBlank()) request.setMimeType(mimeType)
            if (!userAgent.isNullOrBlank()) request.addRequestHeader("User-Agent", userAgent)
            if (!cookie.isNullOrBlank()) request.addRequestHeader("Cookie", cookie)
            if (!referer.isNullOrBlank()) request.addRequestHeader("Referer", referer)

            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val downloadId = manager.enqueue(request)
            if (keepAlive) {
                val keepAliveIntent = Intent(this, WebViewDownloadKeepAliveService::class.java)
                    .putExtra(WebViewDownloadKeepAliveService.EXTRA_DOWNLOAD_ID, downloadId)
                    .putExtra(WebViewDownloadKeepAliveService.EXTRA_FILE_NAME, filename)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(keepAliveIntent)
                } else {
                    startService(keepAliveIntent)
                }
            }
            result.success(downloadId)
        } catch (e: Exception) {
            Log.e(logTag, "Unable to enqueue WebView download", e)
            result.error("WEBVIEW_DOWNLOAD_ERROR", e.message, null)
        }
    }

    private fun resolveBrowserLikeFilename(
        sourceUrl: String,
        contentDisposition: String?,
        mimeType: String?,
    ): String {
        val dispositionName = parseContentDispositionFilename(contentDisposition)
        val candidate = dispositionName ?: Uri.decode(URLUtil.guessFileName(sourceUrl, null, mimeType))
        return sanitizeDownloadFilename(candidate)
    }

    private fun parseContentDispositionFilename(contentDisposition: String?): String? {
        if (contentDisposition.isNullOrBlank()) return null

        // RFC 6266 prefers filename* over filename. Android only gained
        // consistent filename*=UTF-8''... parsing in newer platform releases,
        // so parse it here to keep QAQ's behavior stable on older devices too.
        val extended = Regex(
            """(?i)(?:^|;)\s*filename\*\s*=\s*("(?:\\.|[^"])*"|[^;]+)""",
        ).find(contentDisposition)?.groupValues?.get(1)
        decodeExtendedFilename(extended)?.let { return it }

        val plain = Regex(
            """(?i)(?:^|;)\s*filename\s*=\s*("(?:\\.|[^"])*"|[^;]+)""",
        ).find(contentDisposition)?.groupValues?.get(1)
        return unquoteHeaderValue(plain)?.let(Uri::decode)
    }

    private fun decodeExtendedFilename(rawValue: String?): String? {
        val value = unquoteHeaderValue(rawValue) ?: return null
        val firstQuote = value.indexOf('\'')
        if (firstQuote <= 0) return null
        val secondQuote = value.indexOf('\'', firstQuote + 1)
        if (secondQuote < 0) return null

        val charset = try {
            Charset.forName(value.substring(0, firstQuote))
        } catch (_: Exception) {
            return null
        }
        val encoded = value.substring(secondQuote + 1)
        val bytes = ByteArrayOutputStream(encoded.length)
        var index = 0

        while (index < encoded.length) {
            if (encoded[index] == '%' && index + 2 < encoded.length) {
                val byte = encoded.substring(index + 1, index + 3).toIntOrNull(16)
                if (byte != null) {
                    bytes.write(byte)
                    index += 3
                    continue
                }
            }

            val char = encoded[index]
            if (char.code <= 0x7f) {
                bytes.write(char.code)
            } else {
                bytes.write(char.toString().toByteArray(charset))
            }
            index++
        }

        return bytes.toByteArray().toString(charset).takeIf { it.isNotBlank() }
    }

    private fun unquoteHeaderValue(rawValue: String?): String? {
        var value = rawValue?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (value.length >= 2 && value.first() == '"' && value.last() == '"') {
            value = value.substring(1, value.length - 1)
                .replace(Regex("""\\(.)"""), "$1")
        }
        return value.takeIf { it.isNotBlank() }
    }

    private fun sanitizeDownloadFilename(value: String): String {
        val sanitized = value
            .replace(Regex("""[\\/:*?"<>|\u0000-\u001F]"""), "_")
            .trim()
            .trimEnd('.', ' ')
        return sanitized.ifEmpty { "download" }
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

    private fun setWebViewCookie(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val name = call.argument<String>("name")
        val value = call.argument<String>("value")
        val path = call.argument<String>("path") ?: "/"

        if (url.isNullOrBlank() || name.isNullOrEmpty() || value == null) {
            result.error("INVALID_COOKIE_ARGUMENTS", "A cookie URL, name and value are required.", null)
            return
        }

        try {
            val domain = call.argument<String>("domain")
            val expiresDate = call.argument<Number>("expiresDate")?.toLong()
            val maxAge = call.argument<Number>("maxAge")?.toLong()
            val isSecure = call.argument<Boolean>("isSecure") == true
            val isHttpOnly = call.argument<Boolean>("isHttpOnly") == true

            val cookieValue = buildString {
                append(name)
                append("=")
                append(value)
                append("; Path=")
                append(path)
                if (!domain.isNullOrBlank()) {
                    append("; Domain=")
                    append(domain)
                }
                if (expiresDate != null) {
                    append("; Expires=")
                    append(formatCookieExpirationDate(expiresDate))
                }
                if (maxAge != null) {
                    append("; Max-Age=")
                    append(maxAge)
                }
                if (isSecure) append("; Secure")
                if (isHttpOnly) append("; HttpOnly")
                append(";")
            }

            val cookieManager = CookieManager.getInstance()
            cookieManager.setCookie(url, cookieValue) { successful ->
                cookieManager.flush()
                result.success(successful)
            }
        } catch (e: Exception) {
            Log.e(logTag, "Unable to set WebView cookie", e)
            result.error("WEBVIEW_COOKIE_ERROR", e.message, null)
        }
    }

    private fun formatCookieExpirationDate(timestamp: Long): String =
        SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("GMT")
        }.format(Date(timestamp))

}
