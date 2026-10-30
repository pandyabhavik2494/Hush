#!/usr/bin/env bash
# Runs inside the emulator job: copies the test media on, smoke-tests the release APK the way a
# person would (tap a song, keep playing), then runs the instrumented tests at one of the Fold's screen sizes.
set -uo pipefail
media="$1"      # from make-test-media.sh
apk="$2"        # the release APK
results="$3"
screen="$4"     # cover-screen or inner-screen
mkdir -p "$results"
status=0

adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
adb push "$media/Music/." /sdcard/Music/ >/dev/null
adb shell mkdir -p "'/sdcard/Music Videos'"
adb push "$media/Music Videos/." "/sdcard/Music Videos/" >/dev/null
adb shell content call --uri content://media --method scan_volume --arg external_primary || true
sleep 8
adb shell content query --uri content://media/external/audio/media --projection title:relative_path | head -5

tap_text() {  # taps the first on-screen element whose text is $1
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null
  adb pull /sdcard/ui.xml "$results/ui.xml" >/dev/null
  local bounds
  bounds=$(python3 - "$results/ui.xml" "$1" <<'PY'
import re, sys
xml = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r'<node [^>]*>', xml):
    node = m.group(0)
    if f'text="{sys.argv[2]}"' in node:
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
        x1, y1, x2, y2 = map(int, b.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
)
  [ -z "$bounds" ] && { echo "Could not find '$1' on screen"; return 1; }
  adb shell input tap $bounds
}

echo "== Smoke test of the release APK =="
adb logcat -c
adb install -r "$apk"
for p in READ_MEDIA_AUDIO POST_NOTIFICATIONS; do adb shell pm grant com.pandyabhavik.hush android.permission.$p; done
adb shell am start -W -n com.pandyabhavik.hush/.MainActivity
sleep 6
adb exec-out screencap -p > "$results/release-1-launch.png"
tap_text "Songs" && sleep 2 && tap_text "Hush Test One" && sleep 8
adb exec-out screencap -p > "$results/release-2-playing.png"
if adb shell pidof com.pandyabhavik.hush >/dev/null && adb shell dumpsys media_session | grep -Eq "PlaybackState \{state=(3|PLAYING)"; then
  echo "Release APK: playing after a tap, no crash"
else
  echo "::error::Release APK did not keep playing after tapping a song"
  status=1
fi
adb logcat -d > "$results/logcat-release.txt"
adb logcat -d -b crash > "$results/crash-release.txt"
adb uninstall com.pandyabhavik.hush >/dev/null || true

run_suite() {  # $1 = label
  adb logcat -c
  adb shell rm -rf /sdcard/Download/hush-screens
  if ! ./gradlew --no-daemon connectedDebugAndroidTest; then status=1; fi
  mkdir -p "$results/$1"
  adb pull /sdcard/Download/hush-screens/. "$results/$1/" >/dev/null || true
  cp -r app/build/reports/androidTests/connected "$results/$1/report" 2>/dev/null || true
  adb logcat -d > "$results/$1/logcat.txt"
  adb logcat -d -b crash > "$results/$1/crash.txt"
}

if [ "$screen" = cover-screen ]; then
  echo "== Instrumented tests, phone-sized screen (like the Fold's cover screen) =="
  adb shell wm size 1080x2520
  adb shell wm density 420
else
  echo "== Instrumented tests, the Fold's inner screen size =="
  adb shell wm size 1968x2184
  adb shell wm density 374
fi
run_suite "$screen"
adb shell wm size reset
adb shell wm density reset

exit $status
