package com.localtok.local_tok

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Foreground service that keeps the app process alive during screen-off listening.
 * Shows a persistent notification indicating that LeoTok is playing in the background.
 *
 * The PARTIAL_WAKE_LOCK is held ONLY while audio is actually playing (see
 * [setPlaying]) — merely enabling screen-off listening must not drain battery.
 */
class BackgroundAudioService : Service() {

    companion object {
        const val CHANNEL_ID = "leotok_playback"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.localtok.local_tok.STOP_BACKGROUND_AUDIO"

        @Volatile
        private var wakeLock: PowerManager.WakeLock? = null

        /** Acquire/release the CPU wake lock based on actual playback state. */
        fun setPlaying(playing: Boolean) {
            val wl = wakeLock
            if (wl == null) return
            if (playing && !wl.isHeld) {
                wl.acquire()
            } else if (!playing && wl.isHeld) {
                wl.release()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // NOTE: the wake lock is NOT acquired here — see setPlaying().
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LeoTok:WakeLock")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "熄屏听剧",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "LeoTok 后台播放通知"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingOpenIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("LeoTok 熄屏听剧中")
                .setContentText("视频正在后台播放声音")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(pendingOpenIntent)
                .setOngoing(true)
                .setPriority(Notification.PRIORITY_LOW)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("LeoTok 熄屏听剧中")
                .setContentText("视频正在后台播放声音")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(pendingOpenIntent)
                .setOngoing(true)
                .setPriority(Notification.PRIORITY_LOW)
                .build()
        }
    }
}
