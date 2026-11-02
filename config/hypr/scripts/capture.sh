#!/usr/bin/env bash
# Capture backend (like NVIDIA ShadowPlay) on top of gpu-screen-recorder (NVENC, almost no FPS cost)
#   replay-on | replay-off | replay-toggle | replay-save | record-toggle | record-stop | status | apply
CFG="$HOME/.config/capture/config.json"
RUN="${XDG_RUNTIME_DIR:-/tmp}/capture"
mkdir -p "$RUN" "$(dirname "$CFG")"

[ -f "$CFG" ] || cat > "$CFG" <<'EOF'
{
  "replaySeconds": 60,
  "fps": 60,
  "quality": "very_high",
  "audio": "desktop",
  "monitor": "focused",
  "folder": "~/Videos/Clips",
  "replayAutostart": true,
  "hotkeys": {
    "menu": "ALT + Z",
    "replaySave": "ALT + SHIFT + F10",
    "replayToggle": "ALT + SHIFT + F9",
    "record": "ALT + F9",
    "screenshot": "ALT + F1"
  }
}
EOF

cfg() { python3 -I -c 'import json,sys,os; d=json.load(open(sys.argv[1])); v=d
for k in sys.argv[2].split("."): v=v.get(k,"") if isinstance(v,dict) else ""
print(os.path.expanduser(str(v)))' "$CFG" "$1"; }

monitor() {
  local m; m=$(cfg monitor)
  if [ "$m" = "focused" ] || [ -z "$m" ]; then
    hyprctl monitors -j | python3 -I -c 'import json,sys;print([m["name"] for m in json.load(sys.stdin) if m["focused"]][0])'
  else echo "$m"; fi
}
audio_args() {
  case "$(cfg audio)" in
    desktop)      echo "-a default_output" ;;
    desktop+mic)  echo "-a default_output|default_input" ;;
    mic)          echo "-a default_input" ;;
    *)            echo "" ;;
  esac
}
alive() { [ -f "$RUN/$1.pid" ] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }
bar()   { pkill -RTMIN+9 waybar 2>/dev/null; true; }

# called by gpu-screen-recorder after a replay/recording is saved
if [ "$1" = "--saved" ]; then
  f="$2"; kind="$3"
  notify-send -a "Capture" -i video-x-generic "$( [ "$kind" = replay ] && echo "Instant Replay saved" || echo "Recording saved")" "$(basename "$f")"
  exit 0
fi

case "$1" in
  replay-on)
    alive replay && exit 0
    dir=$(cfg folder)/Replays; mkdir -p "$dir"
    # shellcheck disable=SC2046
    setsid gpu-screen-recorder -w "$(monitor)" -f "$(cfg fps)" -q "$(cfg quality)" -c mp4 -ac aac $(audio_args) \
      -r "$(cfg replaySeconds)" -sc "$HOME/.config/hypr/scripts/capture-saved.sh" -o "$dir" >"$RUN/replay.log" 2>&1 &
    echo $! > "$RUN/replay.pid"; sleep 0.3; bar
    notify-send -a "Capture" "Instant Replay on" "Last $(cfg replaySeconds)s are kept · $(cfg hotkeys.replaySave) to save" ;;
  replay-off)
    alive replay && kill -INT "$(cat "$RUN/replay.pid")"; rm -f "$RUN/replay.pid"; bar
    notify-send -a "Capture" "Instant Replay off" ;;
  replay-toggle)
    if alive replay; then "$0" replay-off; else "$0" replay-on; fi ;;
  replay-save)
    if alive replay; then kill -USR1 "$(cat "$RUN/replay.pid")"
    else notify-send -a "Capture" "Instant Replay is off" "Turn it on with $(cfg hotkeys.replayToggle) or Alt+Z"; fi ;;
  record-toggle)
    if alive record; then
      kill -INT "$(cat "$RUN/record.pid")"; rm -f "$RUN/record.pid" "$RUN/record.start"; bar
    else
      dir=$(cfg folder)/Recordings; mkdir -p "$dir"
      f="$dir/$(date +%Y-%m-%d_%H-%M-%S).mp4"
      # shellcheck disable=SC2046
      setsid gpu-screen-recorder -w "$(monitor)" -f "$(cfg fps)" -q "$(cfg quality)" -c mp4 -ac aac $(audio_args) \
        -sc "$HOME/.config/hypr/scripts/capture-saved.sh" -o "$f" >"$RUN/record.log" 2>&1 &
      echo $! > "$RUN/record.pid"; date +%s > "$RUN/record.start"; sleep 0.3; bar
      notify-send -a "Capture" "Recording started" "$(cfg hotkeys.record) to stop"
    fi ;;
  record-stop)
    alive record && "$0" record-toggle ;;
  apply)
    # settings changed: restart replay with the new settings
    if alive replay; then "$0" replay-off >/dev/null; sleep 0.5; "$0" replay-on; fi ;;
  autostart)
    [ "$(cfg replayAutostart)" = "True" ] && "$0" replay-on >/dev/null 2>&1 ;;
  status)
    r=false; c=false; secs=0
    alive replay && r=true
    if alive record; then c=true; secs=$(( $(date +%s) - $(cat "$RUN/record.start" 2>/dev/null || date +%s) )); fi
    if [ "$c" = true ]; then
      printf '{"text":"\U000f044a  %02d:%02d","class":"rec","tooltip":"Recording — click to stop"}\n' $((secs/60)) $((secs%60))
    elif [ "$r" = true ]; then
      printf '{"text":"\U000f0459","class":"replay","tooltip":"Instant Replay is on — click to open (Alt+Z)"}\n'
    else
      echo '{"text":"","class":"off"}'
    fi ;;
  json)
    r=false; c=false; secs=0
    alive replay && r=true
    if alive record; then c=true; secs=$(( $(date +%s) - $(cat "$RUN/record.start" 2>/dev/null || date +%s) )); fi
    echo "{\"replay\":$r,\"record\":$c,\"recordSeconds\":$secs}" ;;
  *) sed -n '2,3p' "$0" ;;
esac
