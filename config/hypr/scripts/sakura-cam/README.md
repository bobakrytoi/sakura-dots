# Sakura Cam

iPhone as a webcam for the sakura mono rice, without an iOS app. The camera page runs in Safari (added to the
Home Screen as an app) and streams over WebRTC to `server.py`, which writes the picture into a v4l2loopback
device called "Sakura Cam" and, if wanted, the phone's microphone into a PipeWire source called "Sakura Mic".

## Pieces

- `server.py` - the server (aiohttp + aiortc). Ports: 8780 http (setup page, CA profile), 8781 https (camera page,
  WebSocket), 8782 local API for quickshell (127.0.0.1 only). The header of the file lists the API.
- `certs.py` - a tiny local CA in `~/.local/share/sakura/cam`. The phone trusts the CA once; the server
  certificate is re-issued whenever the PC's addresses change (Wi-Fi / USB tethering).
- `v4l2out.py` - writes I420 frames into the loopback device.
- `static/` - the phone side: `setup.html` (first run), `index.html` + `app.js` + `style.css` (camera page, PWA),
  `sw.js` (keeps the page on the phone), icons (`mkicon.py` draws them).
- quickshell: `CamLink.qml` (state, commands, hotkey), `SakuraCam.qml` (panel from the notch), Settings > Sakura Cam,
  live activity "cam" in `Notch.qml`.
- user service: `~/.config/systemd/user/sakura-cam.service`.

## Setting it up on a new machine

```
cd ~/.config/hypr/scripts/sakura-cam
uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python aiortc aiohttp cryptography segno numpy pillow zeroconf
systemctl --user enable --now sakura-cam.service
```

The virtual camera needs the v4l2loopback module (root, once):

```
sudo pacman -S --needed v4l2loopback-dkms usbmuxd
echo v4l2loopback | sudo tee /etc/modules-load.d/sakura-cam.conf
echo 'options v4l2loopback video_nr=10 card_label="Sakura Cam" exclusive_caps=1' | sudo tee /etc/modprobe.d/sakura-cam.conf
sudo modprobe v4l2loopback
systemctl --user restart sakura-cam
```

`exclusive_caps=1` is what Chromium-based apps (Discord, browsers) need to list the device. `usbmuxd` pairs the
iPhone for USB tethering (Personal Hotspot over the cable).

With Mullvad on, local network sharing has to be allowed (`mullvad lan set allow`), or the phone cannot reach the PC.

## Checks

```
qs ipc call cam state            # service / phone / device
curl -s 127.0.0.1:8782/state     # everything the server knows
journalctl --user -u sakura-cam -f
```
