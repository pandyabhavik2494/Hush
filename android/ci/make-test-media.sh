#!/usr/bin/env bash
# Makes tagged test songs (with embedded covers) and two music videos, like the iTunes files:
#  - "Hush Test Album" by Hush Test Artist (2024): Hush Test One, Hush Test Two (with Guest Singer), Hush Test Three
#  - "Guest Album" by Guest Singer (2023): Guest Song A, Guest Song B
#  - 40 one-song albums "Quiet Album 01".."Quiet Album 40" by Quiet Players, so the grids and lists
#    are long enough to scroll (the device tests check scrolling stays smooth)
#  - "Hush Test Artist - Hush Test Video.mp4" (20 s) and "Guest Singer - Second Video.mp4" (12 s)
# The device tests (androidTest/HushTestBase.kt) depend on these names.
set -euo pipefail
out="$1"
mkdir -p "$out/Music/Hush Test Artist/Hush Test Album" "$out/Music/Guest Singer/Guest Album" "$out/Music Videos" "$out/covers"

song() {  # song <file> <title> <artist> <album> <album artist> <track> <of> <year> <cover> <frequency> <seconds>
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=${10}:duration=${11}" -i "$9" \
    -map 0:a -map 1:v -c:a aac -b:a 96k -c:v png -disposition:v attached_pic \
    -metadata title="$2" -metadata artist="$3" -metadata album="$4" \
    -metadata album_artist="$5" -metadata track="$6/$7" -metadata date="$8" \
    "$1"
}

cover() {  # cover <file> <colour>
  ffmpeg -loglevel error -y -f lavfi -i "color=c=$2:s=600x600:d=1" -frames:v 1 "$1"
}

cover "$out/cover.png" 0x8a6d3b
n=1
for title in "Hush Test One" "Hush Test Two" "Hush Test Three"; do
  artist="Hush Test Artist"
  [ "$n" = 2 ] && artist="Hush Test Artist & Guest Singer"
  song "$out/Music/Hush Test Artist/Hush Test Album/0$n $title.m4a" "$title" "$artist" "Hush Test Album" \
    "Hush Test Artist" "$n" 3 2024 "$out/cover.png" $((300 + n * 110)) 40
  n=$((n + 1))
done

cover "$out/covers/guest.png" 0x3b5a8a
song "$out/Music/Guest Singer/Guest Album/01 Guest Song A.m4a" "Guest Song A" "Guest Singer" "Guest Album" "Guest Singer" 1 2 2023 "$out/covers/guest.png" 520 40
song "$out/Music/Guest Singer/Guest Album/02 Guest Song B.m4a" "Guest Song B" "Guest Singer" "Guest Album" "Guest Singer" 2 2 2023 "$out/covers/guest.png" 560 40

for i in $(seq -w 1 40); do
  dir="$out/Music/Quiet Players/Quiet Album $i"
  mkdir -p "$dir"
  # A different colour for each cover, so the grid has real pictures to draw.
  colour=$(printf '0x%02x%02x%02x' $(( (10#$i * 53) % 200 + 30 )) $(( (10#$i * 97) % 200 + 30 )) $(( (10#$i * 31) % 200 + 30 )))
  cover "$out/covers/quiet-$i.png" "$colour"
  song "$dir/01 Quiet Song $i.m4a" "Quiet Song $i" "Quiet Players" "Quiet Album $i" "Quiet Players" 1 1 2020 \
    "$out/covers/quiet-$i.png" $((200 + 10#$i * 7)) 20
done

ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=24:duration=20" -f lavfi -i "sine=frequency=500:duration=20" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/Music Videos/Hush Test Artist - Hush Test Video.mp4"
ffmpeg -loglevel error -y -f lavfi -i "smptebars=size=640x360:rate=24:duration=12" -f lavfi -i "sine=frequency=650:duration=12" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/Music Videos/Guest Singer - Second Video.mp4"
rm -rf "$out/covers"
find "$out" -type f | sort
