package pro.momin.localmind

import android.app.Application
import com.ryanheise.audioservice.AudioServicePlugin

class LocalMindApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Native callbacks and TTS belong to the process, not an Activity or
        // media Service. Android still reclaims the entire idle process.
        AudioServicePlugin.setRetainFlutterEngine(true)
    }
}
