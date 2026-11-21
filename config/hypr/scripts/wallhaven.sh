#!/usr/bin/env bash
# wallhaven.sh search MODE PAGE [QUERY] [CATS: 111 = general/anime/people bits]  -> JSON lines {id,thumb,large,path,res,type} (sfw only)
#   MODE: toplist | hot | latest | random
# wallhaven.sh get URL                   -> downloads into ~/Pictures/Wallpapers, prints the file path
dir="$HOME/Pictures/Wallpapers"
case "$1" in
  search)
    mode="${2:-toplist}"; page="${3:-1}"; q="$4"; cat="${5:-111}"; sort=toplist
    case "$mode" in latest) sort=date_added ;; random) sort=random ;; hot) sort=hot ;; esac
    [ -n "$q" ] && [ "$mode" = toplist ] && sort=relevance
    curl -fsG -m 15 "https://wallhaven.cc/api/v1/search" --data-urlencode "q=$q" \
         -d "categories=$cat" -d purity=100 -d "sorting=$sort" -d "page=$page" -d atleast=1920x1080 -d ratios=landscape \
      | python3 -I -c '
import json, sys
for w in json.load(sys.stdin).get("data", []):
    print(json.dumps({"id": w["id"], "thumb": w["thumbs"]["small"], "large": w["thumbs"]["large"], "path": w["path"],
                      "res": w["resolution"], "type": w["file_type"].split("/")[-1].replace("jpeg", "jpg").upper(),
                      "date": w["created_at"][:10]}))' ;;
  get)
    mkdir -p "$dir"; out="$dir/$(basename "$2")"
    [ -s "$out" ] || curl -fsL -m 120 -o "$out.part" "$2" && { [ -s "$out" ] || mv "$out.part" "$out"; }
    [ -s "$out" ] && echo "$out" ;;
esac
