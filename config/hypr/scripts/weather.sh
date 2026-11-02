#!/usr/bin/env bash
# weather for the dashboard (open-meteo, no API key) -> ~/.cache/sakura-weather.json
# location is detected once and saved in ~/.config/sakura/weather.json (edit "city", "lat", "lon" there to change it)
LOC="$HOME/.config/sakura/weather.json"; OUT="$HOME/.cache/sakura-weather.json"
if [ ! -s "$LOC" ]; then
  curl -s --max-time 6 "http://ip-api.com/json/?fields=city,lat,lon" | python3 -I -c '
import json,sys
d=json.load(sys.stdin); print(json.dumps({"city":d.get("city","?"),"lat":d.get("lat",35.68),"lon":d.get("lon",139.69)}))' > "$LOC" 2>/dev/null
  [ -s "$LOC" ] || echo '{"city":"Tokyo","lat":35.68,"lon":139.69}' > "$LOC"
fi
read -r lat lon city < <(python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["lat"],d["lon"],d["city"])' "$LOC")
url="https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=7"
curl -s --max-time 8 "$url" | python3 -I -c '
import json,sys
d=json.load(sys.stdin); d["city"]=sys.argv[1]; print(json.dumps(d))' "$city" > "$OUT.tmp" && [ -s "$OUT.tmp" ] && mv "$OUT.tmp" "$OUT"
