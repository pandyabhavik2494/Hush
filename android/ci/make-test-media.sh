#!/usr/bin/env bash
# Makes three tagged test songs (with embedded covers) and one music video, like the iTunes files.
set -euo pipefail
out="$1"
mkdir -p "$out/Music/Hush Test Artist/Hush Test Album" "$out/Music Videos"
ffmpeg -loglevel error -y -f lavfi -i "color=c=0x8a6d3b:s=600x600:d=1" -frames:v 1 "$out/cover.png"
n=1
for title in "Hush Test One" "Hush Test Two" "Hush Test Three"; do
  artist="Hush Test Artist"
  [ "$n" = 2 ] && artist="Hush Test Artist & Guest Singer"
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$((300 + n * 110)):duration=40" -i "$out/cover.png" \
    -map 0:a -map 1:v -c:a aac -b:a 96k -c:v png -disposition:v attached_pic \
    -metadata title="$title" -metadata artist="$artist" -metadata album="Hush Test Album" \
    -metadata album_artist="Hush Test Artist" -metadata track="$n/3" -metadata date=2024 \
    "$out/Music/Hush Test Artist/Hush Test Album/0$n $title.m4a"
  n=$((n + 1))
done
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=24:duration=8" -f lavfi -i "sine=frequency=500:duration=8" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/Music Videos/Hush Test Artist - Hush Test Video.mp4"
find "$out" -type f | sort
