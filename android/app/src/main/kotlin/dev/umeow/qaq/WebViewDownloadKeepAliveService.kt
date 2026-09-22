package dev.umeow.qaq

import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class WebViewDownloadKeepAliveService : Service() {
    companion object {
        const val EXTRA_DOWNLOAD_ID = "downloadId"
        const val EXTRA_FILE_NAME = "fileName"
        private const val CHANNEL_ID = "qaq_istudy_download_relay"
        private const val NOTIFICATION_ID = 0x5144
        private const val STATUS_CHECK_INTERVAL_MS = 5_000L
    }

    private val activeDownloads = mutableMapOf<Long, String>()
    private val statusHandler = Handler(Looper.getMainLooper())
    private var receiverRegistered = false

    private val statusCheck = object : Runnable {
        override fun run() {
            reconcileActiveDownloads()
            if (activeDownloads.isNotEmpty()) {
                statusHandler.postDelayed(this, STATUS_CHECK_INTERVAL_MS)
            }
        }
    }

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
            val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
            if (id < 0 || activeDownloads.remove(id) == null) return
            updateOrFinish()
        }
    }

    @Suppress("DEPRECATION")
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(downloadReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(downloadReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val downloadId = intent?.getLongExtra(EXTRA_DOWNLOAD_ID, -1L) ?: -1L
        val fileName = intent?.getStringExtra(EXTRA_FILE_NAME)?.takeIf { it.isNotBlank() } ?: "iStudy 檔案"
        if (downloadId >= 0) activeDownloads[downloadId] = fileName

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // A very small download can finish before this service registers its
        // completion receiver. Query DownloadManager as a second source of
        // truth so a missed broadcast cannot leave the FGS notification behind.
        statusHandler.removeCallbacks(statusCheck)
        statusHandler.post(statusCheck)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        statusHandler.removeCallbacks(statusCheck)
        if (receiverRegistered) {
            unregisterReceiver(downloadReceiver)
            receiverRegistered = false
        }
        removeForegroundNotification()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun reconcileActiveDownloads() {
        if (activeDownloads.isEmpty()) {
            finishService()
            return
        }

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val ids = activeDownloads.keys.toLongArray()
        val liveIds = mutableSetOf<Long>()

        manager.query(DownloadManager.Query().setFilterById(*ids))?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val statusColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val status = cursor.getInt(statusColumn)
                if (
                    status == DownloadManager.STATUS_PENDING ||
                        status == DownloadManager.STATUS_RUNNING ||
                        status == DownloadManager.STATUS_PAUSED
                ) {
                    liveIds.add(id)
                }
            }
        }

        activeDownloads.keys.retainAll(liveIds)
        updateOrFinish()
    }

    private fun updateOrFinish() {
        if (activeDownloads.isEmpty()) {
            finishService()
        } else {
            updateNotification()
        }
    }

    private fun finishService() {
        statusHandler.removeCallbacks(statusCheck)
        activeDownloads.clear()
        removeForegroundNotification()
        stopSelf()
    }

    private fun removeForegroundNotification() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "iStudy 下載連線",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        val contentText = if (activeDownloads.size <= 1) {
            activeDownloads.values.firstOrNull() ?: "iStudy 檔案"
        } else {
            "${activeDownloads.size} 個 iStudy 檔案"
        }

        builder
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("iStudy 校外下載")
            .setContentText(contentText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_DEFERRED)
        }

        return builder.build()
    }
}
