package com.pandyabhavik.hush

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import com.pandyabhavik.hush.ui.HushRoot

class MainActivity : ComponentActivity() {
    private val model: HushModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        setContent { HushRoot(model) }
    }

    override fun onStart() {
        super.onStart()
        model.player.setVisible(true)
    }

    override fun onResume() {
        super.onResume()
        model.refreshPlayCounts()
    }

    override fun onStop() {
        // Off screen: stop reading the position four times a second (playback carries on).
        model.player.setVisible(false)
        super.onStop()
    }
}
