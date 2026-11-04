package pro.momin.localmind

import androidx.annotation.NonNull
import android.app.Activity
import android.app.ActivityManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "localmind/chat_background"
    private val MEMORY_CHANNEL = "localmind/device_memory"
    private val ASSISTANT_CHANNEL = "localmind/android_assistant"

    private var assistantChannel: MethodChannel? = null
    private var pendingAssistantInvocation = false
    private var pendingRoleRequest: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureAssistantInvocation(intent)
    }

    override fun onDestroy() {
        assistantChannel?.setMethodCallHandler(null)
        assistantChannel = null
        pendingRoleRequest?.error("activity_detached", "Activity detached", null)
        pendingRoleRequest = null
        super.onDestroy()
    }

    // Back on the root route would otherwise finish this activity and, with
    // it, the Flutter engine while a reply may still be generating. Leave the
    // app the way Android 12+ does instead.
    override fun popSystemNavigator(): Boolean = moveTaskToBack(true)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureAssistantInvocation(intent)
        deliverAssistantInvocation()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val appContext = applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    try {
                        ChatForegroundService.startService(appContext)
                        result.success(null)
                    } catch (error: IllegalStateException) {
                        // Android 12+ refuses foreground services started
                        // from the background.
                        result.error(
                            "foreground_service_unavailable",
                            error.message ?: "The background service could not start.",
                            null
                        )
                    }
                }
                "stopForeground" -> {
                    ChatForegroundService.stopService(
                        appContext,
                        ChatForegroundService.TYPE_SPECIAL_USE
                    )
                    result.success(null)
                }
                "startForegroundMic" -> {
                    try {
                        ChatForegroundService.startService(
                            appContext,
                            ChatForegroundService.TYPE_MICROPHONE
                        )
                        result.success(null)
                    } catch (error: SecurityException) {
                        result.error(
                            "microphone_permission_required",
                            error.message ?: "Microphone permission is required.",
                            null
                        )
                    } catch (error: IllegalStateException) {
                        result.error(
                            "microphone_service_unavailable",
                            error.message ?: "The microphone service could not start.",
                            null
                        )
                    }
                }
                "setNativeWorkActive" -> {
                    nativeWorkActive = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "stopForegroundMic" -> {
                    ChatForegroundService.stopService(
                        appContext,
                        ChatForegroundService.TYPE_MICROPHONE
                    )
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEMORY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMemoryInfo" -> {
                    val activityManager = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val memoryInfo = ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memoryInfo)
                    result.success(
                        mapOf(
                            "totalMemoryMb" to (memoryInfo.totalMem / (1024 * 1024)),
                            "availableMemoryMb" to (memoryInfo.availMem / (1024 * 1024))
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }

        assistantChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ASSISTANT_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingInvocation" -> {
                        val wasPending = pendingAssistantInvocation
                        pendingAssistantInvocation = false
                        result.success(wasPending)
                    }
                    "getAssistantStatus" -> result.success(getAssistantStatus())
                    "requestAssistantRole" -> requestAssistantRole(result)
                    "openAssistantSettings" -> {
                        if (openAssistantSettings()) {
                            result.success(null)
                        } else {
                            result.error(
                                "assistant_settings_unavailable",
                                "Android assistant settings are unavailable.",
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == ASSISTANT_ROLE_REQUEST_CODE) {
            val result = pendingRoleRequest ?: return
            pendingRoleRequest = null
            result.success(
                resultCode == Activity.RESULT_OK || getAssistantStatus() == "active"
            )
            return
        }
        try {
            super.onActivityResult(requestCode, resultCode, data)
        } catch (error: IllegalStateException) {
            // Contain only the observed Flutter ProcessText duplicate reply.
            // Unrelated plugin errors must retain their original failure path.
            if (!ActivityResultErrors.isDuplicateProcessTextReply(error)) throw error
            Log.w("LocalMind", "ProcessText result was already delivered", error)
        }
    }

    private fun captureAssistantInvocation(intent: Intent?) {
        if (intent?.action == Intent.ACTION_ASSIST) {
            pendingAssistantInvocation = true
        }
    }

    private fun deliverAssistantInvocation() {
        if (!pendingAssistantInvocation) return
        val channel = assistantChannel ?: return

        channel.invokeMethod("assistantInvoked", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                pendingAssistantInvocation = false
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

            override fun notImplemented() = Unit
        })
    }

    private fun getAssistantStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "manual"

        val roleManager = getSystemService(RoleManager::class.java)
        if (!roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
            return "unsupported"
        }
        return if (roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)) {
            "active"
        } else {
            "available"
        }
    }

    private fun requestAssistantRole(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            if (openAssistantSettings()) {
                result.success(false)
            } else {
                result.error(
                    "assistant_settings_unavailable",
                    "Android assistant settings are unavailable.",
                    null
                )
            }
            return
        }

        val roleManager = getSystemService(RoleManager::class.java)
        if (!roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
            result.success(false)
            return
        }
        if (roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)) {
            result.success(true)
            return
        }
        if (pendingRoleRequest != null) {
            result.error(
                "assistant_role_request_active",
                "An assistant role request is already active.",
                null
            )
            return
        }

        pendingRoleRequest = result
        startActivityForResult(
            roleManager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT),
            ASSISTANT_ROLE_REQUEST_CODE
        )
    }

    private fun openAssistantSettings(): Boolean {
        val candidates = listOf(
            Intent(Settings.ACTION_VOICE_INPUT_SETTINGS),
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )

        for (candidate in candidates) {
            try {
                startActivity(candidate)
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next settings destination.
            }
        }
        return false
    }

    companion object {
        private const val ASSISTANT_ROLE_REQUEST_CODE = 4101

        // Only touched on the main thread, like ChatForegroundService's holds.
        private var nativeWorkActive = false
    }
}
