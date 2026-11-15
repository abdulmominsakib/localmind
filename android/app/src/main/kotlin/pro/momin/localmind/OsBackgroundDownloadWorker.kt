package pro.momin.localmind

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * OS-executed download for one Hugging Face hand-off (see openspec change
 * add-os-background-downloads). The worker MOVES BYTES ONLY: it appends into
 * the partial file from the hand-off offset and reports progress/completion
 * back through [OsBackgroundDownloadPlugin]. The Dart engine keeps all
 * bookkeeping; finalize-on-init reads the `.osdone` marker when the app is
 * next opened.
 */
class OsBackgroundDownloadWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {

    override fun doWork(): Result {
        val taskId = inputData.getString(OsBackgroundDownloadPlugin.KEY_TASK_ID)
            ?: return Result.failure()
        val url = inputData.getString(OsBackgroundDownloadPlugin.KEY_URL)
            ?: return Result.failure()
        val offset = inputData.getLong(OsBackgroundDownloadPlugin.KEY_OFFSET, 0L)
        val total = inputData.getLong(OsBackgroundDownloadPlugin.KEY_TOTAL, 0L)
        val partPath = inputData.getString(OsBackgroundDownloadPlugin.KEY_PART_PATH)
            ?: return Result.failure()
        val authToken = inputData.getString(OsBackgroundDownloadPlugin.KEY_TOKEN)

        val partFile = File(partPath)
        // The engine truncated the partial to the recorded offset before
        // handing off; keep that contract (append starts at `offset`).
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 30_000
            readTimeout = 60_000
            if (offset > 0) setRequestProperty("Range", "bytes=$offset-")
            if (!authToken.isNullOrEmpty()) {
                setRequestProperty("Authorization", "Bearer $authToken")
            }
        }
        val status = connection.responseCode
        if (status == 401 || status == 403) {
            connection.disconnect()
            OsBackgroundDownloadPlugin.reportFailure(
                applicationContext, taskId, "Authentication failed (HTTP $status)")
            return Result.failure()
        }
        if (status != 206 && status != 200) {
            connection.disconnect()
            OsBackgroundDownloadPlugin.reportFailure(
                applicationContext, taskId, "HTTP $status")
            return Result.failure()
        }
        // 200 with a resume request = server ignored the Range: report so the
        // Dart engine's retry restarts from byte 0 cleanly.
        if (status == 200 && offset > 0) {
            connection.disconnect()
            OsBackgroundDownloadPlugin.reportFailure(
                applicationContext, taskId, "Range not honored (HTTP 200)")
            return Result.retry()
        }

        connection.inputStream.use { input ->
            java.io.FileOutputStream(partFile, true).use { out ->
                val buffer = ByteArray(256 * 1024)
                var received = offset
                while (true) {
                    if (isStopped) {
                        // Cancelled (user delete): engine removes the files.
                        return Result.failure()
                    }
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    received += read
                    if (received % (4 * 1024 * 1024) < read) {
                        out.fd.sync()
                        OsBackgroundDownloadPlugin.reportProgress(
                            applicationContext, taskId, received,
                            if (total > 0) total else received)
                    }
                }
                out.fd.sync()
            }
        }
        connection.disconnect()

        // Finalize-on-init contract: file is complete; write the marker the
        // engine reads when the app is next opened.
        val size = partFile.length()
        java.io.PrintWriter(File("$partPath.osdone")).use { it.println(size) }
        OsBackgroundDownloadPlugin.reportCompleted(applicationContext, taskId, size)
        return Result.success()
    }
}
