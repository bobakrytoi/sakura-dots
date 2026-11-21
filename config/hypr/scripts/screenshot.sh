#!/usr/bin/env bash
# screenshots: region | screen | edit | delay N | satty | done copy|save FILE | ocr FILE | color VALUE
# region/screen/edit open the HolyScreen-style editor of the shell (quickshell/Shot.qml): every monitor is grabbed the
# moment you press the key, the shell shows that frame frozen, you select + annotate, Enter copies / Ctrl+S saves.
# Without the shell (or with Settings > shotEditor off) the old flow runs: frozen slurp selection, saved + copied at once.
# region/edit: the screen freezes the moment you press the key - you select on the frozen frame,
# and exactly that frame is saved (videos, games, animations won't move away).
# Settings > Screenshots & recording: shotDir, shotName (date format), shotCopy, shotNotify, shotEdit, shotFreeze
eval "$(python3 -I - "$HOME/.config/sakura/settings.json" <<'PY2'
import json, sys, os, shlex
try: c = json.load(open(sys.argv[1]))
except Exception: c = {}
v = {"dir": os.path.expanduser(c.get("shotDir", "~/Pictures/Screenshots")), "name": c.get("shotName", "%Y-%m-%d_%H-%M-%S"),
     "copy": "1" if c.get("shotCopy", True) else "0", "note": "1" if c.get("shotNotify", True) else "0",
     "edit": "1" if c.get("shotEdit", False) else "0", "freeze": "1" if c.get("shotFreeze", True) else "0",
     "editor": "1" if c.get("shotEditor", True) else "0"}
for k, x in v.items(): print("shot_%s=%s" % (k, shlex.quote(str(x))))
PY2
)"
dir="${shot_dir:-$HOME/Pictures/Screenshots}"; mkdir -p "$dir"
f="$dir/$(date +"${shot_name:-%Y-%m-%d_%H-%M-%S}").png"
slurp_args=(-d -b 0e0e1088 -c f4b6c8ff -s ffffff10 -w 2)

# slurp/hyprpicker grab the keyboard; when they close, Hyprland says the old window is focused again
# but never re-enters it, so Qt/GTK apps (Telegram!) miss the new clipboard until you switch away and back.
# Re-focusing that window after the copy hands it the fresh clipboard.
prev=$(hyprctl activewindow -j 2>/dev/null | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("address",""))
except Exception: pass')
refocus() { [ -n "$prev" ] && hyprctl dispatch "hl.dsp.focus({window='address:$prev'})" >/dev/null 2>&1; }

frozen_region() {           # prints the path of the cropped frozen frame, or fails if you cancel
  local full="${XDG_RUNTIME_DIR:-/tmp}/shot-frozen.png" out="$1" g
  grim "$full" || return 1                                  # 1. grab every monitor right now
  local fz=""; [ "$shot_freeze" = 1 ] && { hyprpicker -r -z >/dev/null 2>&1 & fz=$!; }   # 2. show that frame frozen on all monitors
  sleep 0.12
  g=$(slurp "${slurp_args[@]}"); local rc=$?                 # 3. select on the frozen picture
  [ -n "$fz" ] && { kill "$fz" 2>/dev/null; wait "$fz" 2>/dev/null; }
  [ $rc -ne 0 ] || [ -z "$g" ] && { rm -f "$full"; return 1; }
  # 4. cut the selection out of the frame grabbed in step 1 (grim's full image uses the global layout coordinates)
  local xy=${g% *} wh=${g#* }
  magick "$full" -crop "${wh}+${xy%,*}+${xy#*,}" +repage "$out"
  rm -f "$full"
}

run="${XDG_RUNTIME_DIR:-/tmp}"
# the editor in the shell: grab every monitor now (parallel, raw ppm = no encoding delay) + the window layout for click-to-select
open_editor() {           # $1 = region | screen; fails when the shell can't take it
  [ "$shot_editor" = 1 ] || return 1
  local names lay
  names=$(hyprctl monitors -j | python3 -I -c 'import json,sys;print(" ".join(m["name"] for m in json.load(sys.stdin)))') || return 1
  for m in $names; do grim -t ppm -o "$m" "$run/shot-$m.ppm" & done
  lay=$(python3 -I - "$(hyprctl monitors -j)" "$(hyprctl clients -j)" <<'PY3'
import json, sys
try: mons = json.loads(sys.argv[1]); cl = json.loads(sys.argv[2])
except Exception: print('{"mons":[],"wins":[]}'); sys.exit()
vis = set()
for m in mons:
    vis.add(m.get("activeWorkspace", {}).get("id"))
    if m.get("specialWorkspace", {}).get("id"): vis.add(m["specialWorkspace"]["id"])
ws = [c for c in cl if c.get("mapped", True) and not c.get("hidden") and c.get("workspace", {}).get("id") in vis]
# topmost first: fullscreen, then floating/pinned, then tiled - most recently focused first within each
ws.sort(key=lambda c: (0 if c.get("fullscreen") else 1 if (c.get("floating") or c.get("pinned")) else 2, c.get("focusHistoryID", 99)))
print(json.dumps({
  "mons": [{"name": m["name"], "x": m["x"], "y": m["y"], "w": round(m["width"] / m.get("scale", 1)), "h": round(m["height"] / m.get("scale", 1))} for m in mons],
  "wins": [{"x": c["at"][0], "y": c["at"][1], "w": c["size"][0], "h": c["size"][1], "title": c.get("title", ""), "cls": c.get("class", "")} for c in ws]}))
PY3
)
  wait
  printf '%s' "$prev" > "$run/shot-prev"
  local fn=open; [ -n "$SHOT_TEST" ] && fn=test     # SHOT_TEST=1: no keyboard grab (for checking the look)
  timeout 2 qs ipc call shot "$fn" "$1" "$lay" >/dev/null 2>&1
}
announce() {              # $1 = file, $2 = what happened (sound, mascot, the notch)
  "$HOME/.config/hypr/scripts/sfx.sh" screenshot &
  qs ipc call mascot react screenshot >/dev/null 2>&1 &
  if [ "$shot_note" = 1 ] && ! timeout 1 qs ipc call notice file shot "$2" "$1" >/dev/null 2>&1; then notify-send -a "Screenshot" -i "$1" "$2" "${dir/#$HOME/\~}"; fi
}

case "$1" in
  done)   # the editor finished: done copy|save FILE
          prev=$(cat "$run/shot-prev" 2>/dev/null)
          case "$2" in
            copy) wl-copy -t image/png < "$3"; refocus; announce "$3" "Screenshot copied" ;;
            save) cp -f "$3" "$f"; [ "$shot_copy" = 1 ] && wl-copy -t image/png < "$f"; refocus
                  announce "$f" "$([ "$shot_copy" = 1 ] && echo "Screenshot saved and copied" || echo "Screenshot saved")" ;;
          esac
          exit 0 ;;
  ocr)    prev=$(cat "$run/shot-prev" 2>/dev/null)
          if ! command -v tesseract >/dev/null; then
            notify-send -a "Screenshot" -i dialog-information "Copy text needs Tesseract" "sudo pacman -S tesseract tesseract-data-eng tesseract-data-rus"; exit 1
          fi
          langs=$(tesseract --list-langs 2>/dev/null | grep -xE 'eng|rus' | paste -sd+); [ -n "$langs" ] || langs=eng
          txt=$(tesseract "$2" - -l "$langs" 2>/dev/null | sed -e 's/[[:space:]]*$//' | sed -e '/./,$!d')
          if [ -n "$txt" ]; then printf '%s' "$txt" | wl-copy; refocus
            timeout 1 qs ipc call notice file shot "Text copied" "$2" >/dev/null 2>&1 || notify-send -a "Screenshot" "Text copied" "$(printf '%s' "$txt" | head -c 120)"
          else notify-send -a "Screenshot" "No text found"; fi
          exit 0 ;;
  color)  prev=$(cat "$run/shot-prev" 2>/dev/null)
          printf '%s' "$2" | wl-copy; refocus
          notify-send -a "Screenshot" -i color-picker "Colour copied" "$2"
          exit 0 ;;
  delay)  sleep "${2:-3}"; exec "$0" region ;;
  satty)  tmp="$run/shot-edit.png"
          frozen_region "$tmp" || { refocus; exit 0; }
          satty --filename "$tmp" --output-filename "$f" --copy-command wl-copy --early-exit --initial-tool brush --corner-roundness 12
          rm -f "$tmp"; refocus; exit 0 ;;
  region|edit) open_editor region && exit 0; [ -n "$SHOT_TEST" ] && exit 1
          if [ "$1" = edit ] || [ "$shot_edit" = 1 ]; then exec "$0" satty; fi
          frozen_region "$f" || { refocus; exit 0; } ;;
  screen) open_editor screen && exit 0
          mon=$(hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["monitor"])'); grim -o "$mon" "$f" ;;
esac
[ "$shot_copy" = 1 ] && wl-copy < "$f"
refocus
"$HOME/.config/hypr/scripts/sfx.sh" screenshot &
qs ipc call mascot react screenshot >/dev/null 2>&1 &   # the mascot says cheese
# the notch says it (click = open the file); the full notification only if the shell isn't there
note=$([ "$shot_copy" = 1 ] && echo "Screenshot copied" || echo "Screenshot saved")
if [ "$shot_note" = 1 ] && ! timeout 1 qs ipc call notice file shot "$note" "$f" >/dev/null 2>&1; then notify-send -a "Screenshot" -i "$f" "Screenshot saved" "$([ "$shot_copy" = 1 ] && echo "Copied to clipboard · ")${dir/#$HOME/\~}"; fi
