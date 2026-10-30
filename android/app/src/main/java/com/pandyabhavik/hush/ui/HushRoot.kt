package com.pandyabhavik.hush.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.pandyabhavik.hush.BuildConfigInfo
import com.pandyabhavik.hush.HushModel

private val audioPermission =
    if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

@Composable
fun HushRoot(model: HushModel) {
    HushMaterialTheme {
        val context = LocalContext.current
        var granted by remember {
            mutableStateOf(ContextCompat.checkSelfPermission(context, audioPermission) == PackageManager.PERMISSION_GRANTED)
        }
        val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
            granted = result[audioPermission] == true
        }
        LaunchedEffect(granted) { if (granted) model.start() }

        CrashReport()
        Box(Modifier.fillMaxSize().background(Hush.paper)) {
            if (granted) Main(model) else Welcome {
                val permissions = buildList {
                    add(audioPermission)
                    if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
                }
                request.launch(permissions.toTypedArray())
            }
        }
    }
}

@Composable
private fun Welcome(onAllow: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        Text("Hush", style = TextStyle(fontFamily = Hush.wordmark, fontSize = 52.sp, color = Hush.ink))
        Spacer(Modifier.height(16.dp))
        Text(
            "Hush plays the music saved on this phone. Allow it to see your music to begin.",
            style = Hush.sans(16.sp, Hush.muted), textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(32.dp))
        PillButton("Allow Access to Music", Icons.Rounded.LibraryMusic, filled = true, Modifier.width(280.dp), onAllow)
    }
}

@Composable
private fun Main(model: HushModel) {
    val stack = remember { mutableStateListOf<Route>() }
    var playerOpen by rememberSaveable { mutableStateOf(false) }
    var about by remember { mutableStateOf(false) }
    var video by remember { mutableStateOf<com.pandyabhavik.hush.data.Video?>(null) }
    val actions = remember(model) {
        HushActions(model, push = { stack.add(it) }, showPlayer = { playerOpen = it }, showVideo = { video = it })
    }
    val hasSong = model.library.song(model.player.currentId) != null
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val bottomPadding = if (hasSong) 64.dp + 12.dp + navBottom else navBottom

    BackHandler(enabled = stack.isNotEmpty() && !playerOpen) { stack.removeAt(stack.lastIndex) }

    CompositionLocalProvider(LocalActions provides actions) {
        Box(Modifier.fillMaxSize()) {
            // The library stays underneath, so its tabs and scroll positions are kept.
            LibraryScreen(model, bottomPadding) { about = true }

            AnimatedContent(
                targetState = stack.size to stack.lastOrNull(),
                transitionSpec = {
                    if (targetState.first > initialState.first) {
                        slideInHorizontally(tween(260)) { it / 3 } + fadeIn(tween(200)) togetherWith fadeOut(tween(160))
                    } else {
                        fadeIn(tween(160)) togetherWith slideOutHorizontally(tween(240)) { it / 3 } + fadeOut(tween(200))
                    }
                },
                label = "pages",
            ) { (_, route) ->
                val back: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
                when (route) {
                    null -> Box(Modifier.fillMaxSize())
                    is Route.AlbumPage -> AlbumPage(route.key, bottomPadding, back)
                    is Route.PlaylistPage -> PlaylistPage(route.id, bottomPadding, back)
                    is Route.ArtistPage -> ArtistPage(route.id, bottomPadding, back)
                }
            }

            if (hasSong) {
                MiniPlayer(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 6.dp).fillMaxWidth())
            }

            AnimatedVisibility(
                visible = playerOpen && hasSong,
                enter = slideInVertically(tween(320)) { it },
                exit = slideOutVertically(tween(260)) { it },
            ) {
                NowPlaying(onClose = { playerOpen = false })
            }

            video?.let { VideoPlayer(it, onClose = { video = null }) }
        }
    }

    if (about) {
        AlertDialog(
            onDismissRequest = { about = false },
            containerColor = Hush.card,
            title = { Text("Hush", style = TextStyle(fontFamily = Hush.wordmark, fontSize = 28.sp, color = Hush.ink)) },
            text = {
                Text(
                    "A quiet player for the music on this phone. Version ${BuildConfigInfo.versionName(LocalContext.current)}.\n\n" +
                        "No accounts, no ads, no tracking. Only artist names are sent to Deezer, to find artist photos.\n\n" +
                        "${model.library.songs.size} songs · ${model.library.albums.size} albums · ${model.library.playlists.size} playlists",
                    style = Hush.sans(15.sp, Hush.muted),
                )
            },
            confirmButton = { TextButton(onClick = { about = false }) { Text("Done", color = Hush.ink) } },
        )
    }
}

/** After an unexpected close, show what went wrong once, with a button to copy it. */
@Composable
private fun CrashReport() {
    val context = LocalContext.current
    val file = remember { com.pandyabhavik.hush.HushApplication.crashFile(context.applicationContext as android.app.Application) }
    var report by remember { mutableStateOf(if (file.exists()) file.readText() else null) }
    val text = report ?: return
    val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
    fun dismiss() {
        file.delete()
        report = null
    }
    AlertDialog(
        onDismissRequest = ::dismiss,
        containerColor = Hush.card,
        title = { Text("Hush closed unexpectedly", style = Hush.serif(22.sp)) },
        text = {
            Column {
                Text("Copy the details and paste them to Claude so it can be fixed.", style = Hush.sans(15.sp, Hush.muted))
                Spacer(Modifier.height(12.dp))
                Text(
                    text.lines().take(14).joinToString("\n"),
                    style = Hush.sans(11.sp, Hush.muted),
                    modifier = Modifier.height(180.dp).verticalScroll(rememberScrollState()),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                clipboard.setText(androidx.compose.ui.text.AnnotatedString(text))
                dismiss()
            }) { Text("Copy Details", color = Hush.ink) }
        },
        dismissButton = { TextButton(onClick = ::dismiss) { Text("Close", color = Hush.muted) } },
    )
}
