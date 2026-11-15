package pro.momin.localmind

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Dart-facing side of the OS download path: enqueues WorkManager workers,
/// forwards cancel requests, and reports progress/completion back to Dart
/// while the Flutter engine is alive. Finalize-on-init (`.osdone` marker) is
/// handled by the Dart engine on startup.
object OsBackgroundDownloadPlugin {
    const val CHANNEL_NAME = "localmind/os_downloads"

    const val KEY_TASK_ID = "taskId"
    const val KEY_URL = "url"
    const val KEY_TOKEN = "authToken"
    const val KEY_OFFSET = "offset"
    const val KEY_TOTAL = "totalBytes"
    const val KEY_PART_PATH = "partPath"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventChannel: MethodChannel? = null

    fun register(channel: MethodChannel) {
        eventChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "handOff" -> {
                    val context = eventContext ?: run {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val taskId = call.argument<String>(KEY_TASK_ID)
                    val url = call.argument<String>(KEY_URL)
                    val partPath = call.argument<String>(KEY_PART_PATH)
                    if (taskId == null || url == null || partPath == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    enqueue(context, taskId, url, partPath,
                        call.argument<Long>(KEY_OFFSET) ?: 0L,
                        call.argument<Long>(KEY_TOTAL) ?: 0L,
                        call.argument<String>(KEY_TOKEN))
                    result.success(true)
                }
                "cancel" -> {
                    val taskId = call.argument<String>(KEY_TASK_ID)
                    if (taskId != null && eventContext != null) {
                        WorkManager.getInstance(eventContext!!).cancelAllWorkByTag(tag(taskId))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onEngineDetach() {
        eventChannel = null
    }

    private var eventContext: Context? = null

    private fun tag(taskId: String) = "os-download-$taskId"

    private fun enqueue(
        context: Context,
        taskId: String,
        url: String,
        partPath: String,
        offset: Long,
        total: Long,
        token: String?,
    ) {
        val request = OneTimeWorkRequestBuilder<OsBackgroundDownloadWorker>()
            .setInputData(workDataOf(
                KEY_TASK_ID to taskId,
                KEY_URL to url,
                KEY_OFFSET to offset,
                KEY_TOTAL to total,
                KEY_PART_PATH to partPath,
                KEY_TOKEN to (token ?: ""),
            ))
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            )
            .addTag(tag(taskId))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            tag(taskId), ExistingWorkPolicy.KEEP, request)
    }

    private fun emit(event: Map<String, Any?>) {
        val channel = eventChannel ?: return
        mainHandler.post { channel.invokeMethod("onEvent", event) }
    }

    fun reportProgress(context: Context, taskId: String, received: Long, total: Long) {
        emit(mapOf(
            "taskId" to taskId,
            "receivedBytes" to received,
            "totalBytes" to total,
            "completed" to false,
        ))
    }

    fun reportCompleted(context: Context, taskId: String, size: Long) {
        emit(mapOf("taskId" to taskId, "receivedBytes" to size, "completed" to true))
    }

    fun reportFailure(context: Context, taskId: String, error: String) {
        emit(mapOf("taskId" to taskId, "completed" to false, "error" to error))
    }
}
