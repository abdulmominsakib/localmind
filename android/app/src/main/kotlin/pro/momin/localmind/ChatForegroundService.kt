package pro.momin.localmind

import android.app.*
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class ChatForegroundService : Service() {
    companion object {
        private const val TAG = "ChatForegroundService"
        private const val CHANNEL_ID = "chat_generation_channel"
        private const val NOTIFICATION_ID = 1001
        private const val LOCK_TAG = "LocalMind:chat"
        // Safety net in case a stop never arrives; far longer than any reply.
        private const val WAKE_LOCK_TIMEOUT_MS = 60 * 60 * 1000L
        const val TYPE_SPECIAL_USE = "specialUse"
        const val TYPE_MICROPHONE = "microphone"

        // Only touched on the main thread: the method channel handlers and
        // onStartCommand both run there.
        private val activeTypes = mutableSetOf<String>()
        private var pendingStarts = 0

        /** Whether a chat reply, model load or voice capture still holds the service. */
        val isHeld: Boolean
            get() = activeTypes.isNotEmpty()

        fun startService(context: Context, type: String = TYPE_SPECIAL_USE) {
            if (type == TYPE_MICROPHONE && !hasMicrophonePermission(context)) {
                throw SecurityException("RECORD_AUDIO permission has not been granted")
            }

            val intent = Intent(context, ChatForegroundService::class.java)
            ContextCompat.startForegroundService(context, intent)
            pendingStarts++
            activeTypes.add(type)
        }

        fun stopService(context: Context, type: String) {
            activeTypes.remove(type)
            if (activeTypes.isNotEmpty()) return
            // Stopping before onStartCommand has called startForeground()
            // crashes the app with ForegroundServiceDidNotStartInTimeException,
            // so onStartCommand finishes a stop that races a start.
            if (pendingStarts > 0) return
            context.stopService(Intent(context, ChatForegroundService::class.java))
        }

        private fun hasMicrophonePermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (pendingStarts > 0) pendingStarts--
        createNotificationChannel()

        // Every startForegroundService() must be answered by startForeground(),
        // even when the service is about to stop, or Android kills the app.
        val useMicrophone = TYPE_MICROPHONE in activeTypes && hasMicrophonePermission(this)
        if (!promoteToForeground(useMicrophone)) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (activeTypes.isEmpty() && pendingStarts == 0) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        acquireLocks()

        // A restarted service would have no Flutter engine behind it.
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    /**
     * Keeps the CPU and Wi-Fi awake while a reply streams. Without them a
     * long thinking phase lets the screen turn off, the device sleep and the
     * radio power down, and the server's socket is dropped mid-reply
     * ("Connection closed while receiving data").
     */
    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) {
            val powerManager = getSystemService(PowerManager::class.java)
            wakeLock = powerManager
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, LOCK_TAG)
                .apply {
                    setReferenceCounted(false)
                    acquire(WAKE_LOCK_TIMEOUT_MS)
                }
        }
        if (wifiLock?.isHeld != true) {
            val wifiManager = applicationContext.getSystemService(WifiManager::class.java)
            @Suppress("DEPRECATION")
            wifiLock = wifiManager
                ?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, LOCK_TAG)
                ?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
    }

    private fun releaseLocks() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        wifiLock?.takeIf { it.isHeld }?.release()
        wifiLock = null
    }

    private fun promoteToForeground(useMicrophone: Boolean): Boolean {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("LocalMind")
            .setContentText(if (useMicrophone) "Listening…" else "Generating response…")
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return try {
                startForeground(NOTIFICATION_ID, notification)
                true
            } catch (error: RuntimeException) {
                Log.w(TAG, "Could not start the foreground service", error)
                false
            }
        }

        // Android 14+ can refuse the microphone type (e.g. while the app is
        // not visible); fall back to special use so the start still completes.
        val candidates = if (useMicrophone) {
            listOf(
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            listOf(ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        }
        for (type in candidates) {
            try {
                startForeground(NOTIFICATION_ID, notification, type)
                return true
            } catch (error: RuntimeException) {
                Log.w(TAG, "Could not start the foreground service with type $type", error)
            }
        }
        return false
    }

    private fun createNotificationChannel() {
        val serviceChannel = NotificationChannel(
            CHANNEL_ID,
            "Chat Generation Service Channel",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows a notification when AI is generating a response in the background"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(serviceChannel)
    }
}
