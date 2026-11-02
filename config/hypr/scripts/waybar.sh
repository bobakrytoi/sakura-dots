#!/usr/bin/env bash
# keep the top bar alive: restart it if it ever crashes (e.g. when a game changes the display)
pkill -x waybar; sleep 0.2
while true; do
  waybar
  sleep 1
done
