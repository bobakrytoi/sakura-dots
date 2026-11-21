#!/usr/bin/env bash
# walllist.sh DIR...  -> "mtime<TAB>path" of pictures and videos in DIRs (not recursive), newest first
for d in "$@"; do [ -d "$d" ] && find "$d" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \) -printf '%T@\t%p\n'; done 2>/dev/null | sort -rn | awk -F'\t' '!seen[$2]++'
