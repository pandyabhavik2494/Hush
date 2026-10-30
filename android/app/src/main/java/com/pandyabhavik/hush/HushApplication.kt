package com.pandyabhavik.hush

import android.app.Application
import java.io.File

class HushApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // If Hush ever closes unexpectedly, keep the details so it can say so next time.
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                crashFile(this).writeText(
                    "Hush ${BuildConfigInfo.versionName(this)} on Android ${android.os.Build.VERSION.RELEASE} " +
                        "(${android.os.Build.MODEL}), thread ${thread.name}\n\n" + error.stackTraceToString(),
                )
            }
            previous?.uncaughtException(thread, error)
        }
    }

    companion object {
        fun crashFile(app: Application) = File(app.filesDir, "last-crash.txt")
    }
}
