# Hush

Hush is a small, native music player for the music already in your library — songs you bought from the iTunes Store or added in the Music app and downloaded to the device. It comes as an iPhone app and a Mac app (Hush for Mac). No accounts, no ads, no tracking.

## What it does

- **Four tabs:** Albums, Songs, Playlists and Artists. Swipe between them or tap a tab; tap the tab you're on to jump back to the top.
- **Search and sort** every tab. Albums, playlists and artists also match by the songs inside them.
- **Artists** are built from song and album credits (collaborations are split, spelling variants merged). Mark favourites; the Artists tab opens on them.
- **Playlists** mirror the ones you make in the Music app. They are read-only in Hush: edit them in Music, then pull down to refresh.
- **Now Playing** with an Up Next queue you can reorder, a mini player on every screen, and "Playing from" links back to the album, artist or playlist.
- **Liquid Glass header** on iOS 26 and later: the controls float over the library, which scrolls underneath with a light blur.

## Build and install

1. Open `Hush.xcodeproj` in Xcode and sign in to your Apple Account under **Xcode → Settings → Accounts** if needed.
2. Choose the **Hush** app target, then select your team under **Signing & Capabilities**. Keep automatic signing enabled.
3. Connect your iPhone, select it as the run destination, then choose **Run**.
4. On first launch, allow Hush to access your media library.

Requires iOS 17 or later (iPhone only). With a free Personal Team the provisioning profile expires after seven days, so run the app from Xcode again to renew it.

## How it works

- SwiftUI app. Playback uses `MPMusicPlayerController.applicationQueuePlayer` (MediaPlayer), so music keeps playing when the phone is locked or Hush is in the background.
- Playlist artwork and artist photos come from MusicKit (the Apple Music catalog); when Apple Music has no photo for an artist, Deezer's public catalog is asked instead. Only the artist's name is sent. Photos are cached on the device.
- Nothing else leaves the phone. See the in-app About screen (tap the Hush wordmark) for the privacy policy.

## Hush for Mac

The same library, the same look, in one window: a sidebar (Albums, Songs, Playlists, Artists, Music Videos, Movies and every playlist), a toolbar with search and sort, a player bar along the bottom, Now Playing in the cover's own colours, an Up Next panel, a floating mini player and a full-window video player.

- **Albums, Playlists and Movies** hide the titles under the artwork (the artwork already carries the name) and sit edge to edge as a mosaic. The toolbar's titles button shows them.
- **Songs** is a sortable table; right-click any song for Play Next, Add to Up Next, Go to Album, Go to Artist and Show in Finder.
- **Artists** share the iPhone app's rules (collaborations split, spellings merged), photos and favourites.
- **Music Videos and Movies** play in Hush with Fit / Fill / Zoom (press Z; Fill, the default, never shows black bands, even in full screen), subtitles and audio choices, Picture in Picture and full screen. Copy-protected items show a "TV app" badge and open in the TV app. Videos never appear among songs.
- **Keyboard:** Space play/pause, ⌘1–⌘6 sections, ⌘F search, ⌘← / ⌘→ previous/next, ⌘L go to the playing song, ⌘U Up Next, ⇧⌘F Now Playing, ⇧⌘M mini player, ⌘R refresh, Esc closes Now Playing or a video. Media keys, AirPods and Control Center work too.

### Build and run

1. Open `Hush.xcodeproj`, choose the **Hush for Mac** scheme and **My Mac**, select your team under **Signing & Capabilities** if needed, then **Run**. Requires macOS 14 or later.
2. On first launch, allow Hush to access your Music library (System Settings › Privacy & Security › Media & Apple Music).
3. If your Music or TV library lives outside your home folder (on an external drive, say), Hush shows an **Allow Access** banner once: choose the folder it suggests and it's remembered.

### How it works

- Reads the Music and TV libraries with the iTunesLibrary framework (songs, albums, your own playlists — not smart or built-in ones — music videos and movies), plus movies sitting in the TV app's media folder. Playlists are read-only; edit them in Music.
- Playback is Hush's own queue on `AVQueuePlayer` (gapless, with history, shuffle and repeat), reporting to Control Center through `MPNowPlayingInfoCenter`. Videos use `AVPlayerLayer`.
- Sandboxed, with read-only access to the Music and Movies folders, user-selected folders (kept as a security-scoped bookmark) and outgoing network for artist photos.
- Code both apps use lives in `Shared/` (style, artist-name merging, search, favourites, artist photos, cover colour sampling); `Hush/` is the iPhone app and `HushMac/` the Mac app.

## Credits

Two artist photos ship inside the app, from Wikimedia Commons (cropped and resized):

- KK — "KK (124).jpg" by Endeshow1, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
- A. R. Rahman — "AR Rahman at Premier Futsal Press Meet (cropped).jpg" by Sriram Narasimhan, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
