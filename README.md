# Hush

Hush is a small, native iPhone music player for the music already in your device library — songs you bought from the iTunes Store or added in the Music app and downloaded to the phone. No accounts, no ads, no tracking.

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

## Credits

Two artist photos ship inside the app, from Wikimedia Commons (cropped and resized):

- KK — "KK (124).jpg" by Endeshow1, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
- A. R. Rahman — "AR Rahman at Premier Futsal Press Meet (cropped).jpg" by Sriram Narasimhan, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
