// sakura mono - sakura-cam phone side. Camera -> WebRTC -> the PC (server.py). Control both ways over a
// data channel ("ctl"); the WebSocket /ws does signaling and is the fallback for control.
"use strict";
const $ = id => document.getElementById(id);
const body = document.body;

// ── words ──
const RU = {
  "Searching for your PC…": "Ищу компьютер…", "Connecting…": "Подключаюсь…", "Live": "В эфире", "Paused": "Пауза",
  "Make sure the phone and the PC are on the same network.": "Телефон и компьютер должны быть в одной сети.",
  "The PC sees the camera. Tap to start.": "Компьютер на связи. Нажми, чтобы начать.",
  "Start": "Начать", "Starting the camera…": "Запускаю камеру…", "Allow the camera": "Разреши доступ к камере",
  "Safari asks once. If it said no: Settings › Safari › Camera.": "Safari спросит один раз. Если отказал: Настройки › Safari › Камера.",
  "Try again": "Ещё раз", "Opened on another device": "Открыто на другом устройстве", "Take over": "Забрать",
  "Torch is not available on this camera": "У этой камеры нет фонарика", "Mic on": "Микрофон включён", "Mic off": "Микрофон выключен",
  "Focus": "Фокус", "Front": "Фронт", "Tap twice to wake": "Два касания - разбудить", "Connection lost": "Связь пропала",
  "The camera stopped": "Камера остановилась", "PC": "ПК",
};
let lang = (navigator.language || "en").startsWith("ru") ? "ru" : "en";
const tr = s => lang === "ru" && RU[s] ? RU[s] : s;

// ── state ──
const S = {
  ws: null, pc: null, dc: null, stream: null, vSender: null, aSender: null, micTrack: null,
  cfg: { res: "1080p", fps: 30, camera: "back", bitrate: 8, mic: false, zoom: 1 },
  want: true, connected: false, live: false, starting: false, kicked: false,
  devices: [], cam: "back", torch: false, zoom: 1, rtt: 0, hostIdx: 0, retry: 0, black: false,
};
const store = {
  get(k, d) { try { const v = localStorage.getItem("sc." + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem("sc." + k, JSON.stringify(v)); } catch (e) {} },
};
S.cam = store.get("cam", "back");

// ── ui helpers ──
function setClass(name, on) { body.classList.toggle(name, !!on); }
let toastT = 0;
function toast(t) { const el = $("toast"); el.textContent = t; el.classList.add("show"); clearTimeout(toastT); toastT = setTimeout(() => el.classList.remove("show"), 1900); }
function haptic() { try { navigator.vibrate && navigator.vibrate(8); } catch (e) {} }
function card(title, text, btn, fn) {
  $("cardTitle").textContent = title; $("cardText").textContent = text || "";
  const b = $("cardBtn"); b.hidden = !btn; b.textContent = btn || ""; b.onclick = fn || null;
}
function accent(hex) {
  if (!/^#[0-9a-f]{6}$/i.test(hex || "")) return;
  const r = parseInt(hex.slice(1, 3), 16), g = parseInt(hex.slice(3, 5), 16), b = parseInt(hex.slice(5, 7), 16);
  document.documentElement.style.setProperty("--acc", hex);
  document.documentElement.style.setProperty("--acc-rgb", `${r}, ${g}, ${b}`);
  store.set("accent", hex);
}
accent(store.get("accent", ""));

function render() {
  setClass("ready", true);
  setClass("searching", !S.connected);
  setClass("live", S.live);
  setClass("starting", S.starting);
  setClass("paused", S.connected && !S.live && !S.starting && S.stream === null && !S.want);
  const s = S.stream && S.stream.getVideoTracks()[0];
  const st = s ? s.getSettings() : {};
  $("stTitle").textContent = !S.connected ? tr("Searching for your PC…") : S.live ? tr("Live") : S.starting ? tr("Connecting…") : tr("Paused");
  $("stInfo").textContent = S.live ? [st.height ? (Math.min(st.width, st.height)) + "p" : "", st.frameRate ? Math.round(st.frameRate) + " fps" : "",
                                      S.rtt ? S.rtt + " ms" : ""].filter(Boolean).join(" · ") : "";
  if (S.kicked) card(tr("Opened on another device"), "", tr("Take over"), () => { S.kicked = false; connect(true); });
  else if (!S.connected) card("Sakura Cam", tr("Make sure the phone and the PC are on the same network."));
  else if (!S.live && !S.starting && !S.want) card(tr("Paused"), tr("The PC sees the camera. Tap to start."), tr("Start"), () => setWant(true));
  else if (S.starting) card("Sakura Cam", tr("Starting the camera…"));
  // controls
  const caps = trackCaps();
  $("torch").classList.toggle("off", !caps.torch);
  $("torch").classList.toggle("on", S.torch);
  $("mic").classList.toggle("on", !!S.cfg.mic);
  $("dark").classList.toggle("on", S.black);
  $("video").classList.toggle("mirror", S.cam === "front");
  renderLenses();
  $("blackText").textContent = S.live ? "Sakura Cam · " + tr("Live") : "Sakura Cam · " + tr("Paused");
}

// ── lenses ──
function lensKind(label) {
  const l = (label || "").toLowerCase();
  if (/front|фронт|передн/.test(l)) return "front";
  if (/dual|triple|двойн|тройн/.test(l)) return "virtual";
  if (/ultra|сверхшир/.test(l)) return "wide";
  if (/tele|телеобъект/.test(l)) return "tele";
  if (/back|rear|задн|основн/.test(l)) return "back";
  return "other";
}
async function listDevices() {
  try {
    const all = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === "videoinput");
    const seen = {};
    S.devices = all.map(d => ({ id: d.deviceId, label: d.label, kind: lensKind(d.label) }))
      .filter(d => d.kind !== "virtual" && d.kind !== "other" && !seen[d.kind] && (seen[d.kind] = 1));
  } catch (e) { S.devices = []; }
  if (!S.devices.length) S.devices = [{ kind: "back" }, { kind: "front" }];
}
const LENS_TXT = { wide: "0.5×", back: "1×", tele: "2×" };
function renderLenses() {
  const box = $("lenses");
  const backs = ["wide", "back", "tele"].filter(k => S.devices.some(d => d.kind === k));
  const key = backs.join(",") + "|" + S.cam;
  if (box.dataset.key === key) return;
  box.dataset.key = key;
  box.innerHTML = "";
  for (const k of backs) {
    const b = document.createElement("button");
    b.className = "lens" + (S.cam === k ? " on" : "");
    b.textContent = LENS_TXT[k];
    b.onclick = () => { haptic(); switchCam(k); };
    box.appendChild(b);
  }
  box.style.display = backs.length > 1 ? "" : "none";
}
function constraintsFor(kind) {
  const [w, h] = S.cfg.res === "720p" ? [1280, 720] : [1920, 1080];
  const v = { width: { ideal: w }, height: { ideal: h }, frameRate: { ideal: +S.cfg.fps || 30, max: 60 } };
  const d = S.devices.find(x => x.kind === kind && x.id);
  if (d) v.deviceId = { exact: d.id };
  else v.facingMode = kind === "front" ? "user" : "environment";
  return v;
}

// ── camera ──
async function openCamera() {
  stopTracks();
  const stream = await navigator.mediaDevices.getUserMedia({ video: constraintsFor(S.cam), audio: false });
  S.stream = stream;
  $("video").srcObject = stream;
  const t = stream.getVideoTracks()[0];
  t.onended = () => { if (S.stream === stream) { S.live = false; toast(tr("The camera stopped")); render(); } };
  S.torch = false; S.zoom = 1;
  await listDevices();
  return t;
}
function stopTracks() {
  if (S.stream) S.stream.getTracks().forEach(t => t.stop());
  S.stream = null;
  $("video").srcObject = null;
}
function trackCaps() {
  const t = S.stream && S.stream.getVideoTracks()[0];
  try { return t && t.getCapabilities ? t.getCapabilities() : {}; } catch (e) { return {}; }
}

async function start() {
  if (!S.connected || S.starting) return;
  S.starting = true; S.live = false; render();
  try {
    const track = await openCamera();
    await newPeer(track);
  } catch (e) {
    S.starting = false;
    stopTracks();
    if (e && (e.name === "NotAllowedError" || e.name === "SecurityError")) card(tr("Allow the camera"), tr("Safari asks once. If it said no: Settings › Safari › Camera."), tr("Try again"), () => start());
    else card("Sakura Cam", String(e && e.message || e), tr("Try again"), () => start());
    render();
    return;
  }
}
async function stop() {
  closePeer();
  stopTracks();
  S.live = false; S.starting = false;
  releaseWake();
  status(); render();
}
function setWant(on) {
  S.want = on;
  send({ t: "status", want: on });
  if (on) start(); else stop();
}

async function newPeer(track) {
  closePeer();
  const pc = new RTCPeerConnection({ iceServers: [] });
  S.pc = pc;
  const enc = { maxBitrate: (+S.cfg.bitrate || 8) * 1e6, maxFramerate: +S.cfg.fps || 30 };
  const vt = pc.addTransceiver(track, { direction: "sendonly", streams: [S.stream], sendEncodings: [enc] });
  S.vSender = vt.sender;
  try { const p = S.vSender.getParameters(); p.degradationPreference = "maintain-framerate"; await S.vSender.setParameters(p); } catch (e) {}
  const at = pc.addTransceiver("audio", { direction: "sendonly" });
  S.aSender = at.sender;
  const dc = pc.createDataChannel("ctl");
  S.dc = dc;
  dc.onmessage = e => { try { onMsg(JSON.parse(e.data)); } catch (x) {} };
  dc.onopen = () => status();
  pc.onconnectionstatechange = () => {
    const st = pc.connectionState;
    if (pc !== S.pc) return;
    if (st === "connected") { S.live = true; S.starting = false; holdWake(); status(); if (S.cfg.mic) micOn(); applyZoom(S.cfg.zoom || 1, true); }
    if (st === "failed" || st === "disconnected") { S.live = false; if (S.want && S.connected) setTimeout(() => { if (S.want && !S.live && !S.starting) start(); }, 1200); }
    render();
  };
  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  await iceDone(pc);
  send({ t: "offer", sdp: pc.localDescription.sdp }, true);
}
function iceDone(pc) {
  return new Promise(res => {
    if (pc.iceGatheringState === "complete") return res();
    const t = setTimeout(res, 2500);
    pc.addEventListener("icegatheringstatechange", () => { if (pc.iceGatheringState === "complete") { clearTimeout(t); res(); } });
  });
}
function closePeer() {
  if (S.pc) { try { S.pc.close(); } catch (e) {} }
  S.pc = null; S.dc = null; S.vSender = null; S.aSender = null;
  if (S.micTrack) { S.micTrack.stop(); S.micTrack = null; }
}

async function switchCam(kind) {
  if (kind === S.cam && S.stream) return;
  S.cam = kind; store.set("cam", kind);
  if (!S.live || !S.vSender) { render(); status(); return; }
  try {
    const t = await openCamera();
    await S.vSender.replaceTrack(t);
  } catch (e) { toast(String(e.message || e)); }
  render(); status();
}

async function micOn() {
  if (!S.aSender) return;
  try {
    const s = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: true, autoGainControl: true } });
    S.micTrack = s.getAudioTracks()[0];
    await S.aSender.replaceTrack(S.micTrack);
  } catch (e) { toast(String(e.message || e)); }
}
async function micOff() {
  if (S.aSender) await S.aSender.replaceTrack(null).catch(() => {});
  if (S.micTrack) { S.micTrack.stop(); S.micTrack = null; }
}
async function setMic(on, fromPc) {
  S.cfg.mic = on;
  if (S.live) on ? await micOn() : await micOff();
  if (!fromPc) send({ t: "status", mic: on, setMic: on });
  toast(tr(on ? "Mic on" : "Mic off"));
  render();
}

async function setTorch(on) {
  const t = S.stream && S.stream.getVideoTracks()[0];
  if (!t || !trackCaps().torch) { toast(tr("Torch is not available on this camera")); return; }
  on = on === "toggle" ? !S.torch : !!on;
  try { await t.applyConstraints({ advanced: [{ torch: on }] }); S.torch = on; } catch (e) { toast(String(e.message || e)); }
  render(); status();
}

function zoomRange() { const z = trackCaps().zoom; return z && z.max > z.min ? z : null; }
async function applyZoom(v, quiet) {
  const r = zoomRange();
  const t = S.stream && S.stream.getVideoTracks()[0];
  if (r && t) {
    v = Math.max(r.min, Math.min(r.max, v));
    try { await t.applyConstraints({ advanced: [{ zoom: v }] }); } catch (e) {}
  } else v = Math.max(1, Math.min(4, v));        // digital zoom happens on the PC
  S.zoom = v;
  if (!quiet) { const tip = $("zoomTip"); tip.textContent = v.toFixed(1) + "×"; tip.classList.add("show"); clearTimeout(applyZoom.t); applyZoom.t = setTimeout(() => tip.classList.remove("show"), 700); }
}

async function focusAt(x, y) {
  const t = S.stream && S.stream.getVideoTracks()[0];
  const c = trackCaps();
  if (!t) return;
  try {
    const adv = { pointsOfInterest: [{ x, y }] };
    if (c.focusMode && c.focusMode.includes("single-shot")) adv.focusMode = "single-shot";
    if (c.exposureMode && c.exposureMode.includes("single-shot")) adv.exposureMode = "single-shot";
    await t.applyConstraints({ advanced: [adv] });
  } catch (e) {}
}
function focusRing(px, py) {
  const el = document.createElement("div");
  el.className = "focus"; el.style.left = px + "px"; el.style.top = py + "px";
  document.body.appendChild(el); setTimeout(() => el.remove(), 950);
}

// ── keep the screen on ──
let wake = null;
async function holdWake() {
  try { if ("wakeLock" in navigator && !wake) { wake = await navigator.wakeLock.request("screen"); wake.addEventListener("release", () => { wake = null; }); } } catch (e) { wake = null; }
  try { await $("keep").play(); } catch (e) {}
}
function releaseWake() { try { wake && wake.release(); } catch (e) {} wake = null; try { $("keep").pause(); } catch (e) {} }

// ── talking to the PC ──
function hosts() {
  const list = [location.host];
  for (const h of store.get("hosts", [])) { const hp = h.includes(":") ? h : h + ":8781"; if (!list.includes(hp)) list.push(hp); }
  return list;
}
function send(m, wsOnly) {
  const s = JSON.stringify(m);
  if (!wsOnly && S.dc && S.dc.readyState === "open") { try { S.dc.send(s); return; } catch (e) {} }
  if (S.ws && S.ws.readyState === 1) S.ws.send(s);
}
function status() {
  const t = S.stream && S.stream.getVideoTracks()[0];
  const st = t ? t.getSettings() : {};
  const c = trackCaps();
  const z = zoomRange();
  send({ t: "status", want: S.want, live: S.live, cam: S.cam, lenses: S.devices.map(d => d.kind),
         w: st.width || 0, h: st.height || 0, fps: Math.round(st.frameRate || 0),
         torch: !!c.torch, torchOn: S.torch, zoomNative: z ? { min: z.min, max: z.max } : null, zoom: S.zoom,
         focus: !!(c.focusMode || c.pointsOfInterest), mic: !!S.cfg.mic, battery: S.battery || null,
         orient: (screen.orientation && screen.orientation.angle) || 0 });
}
function connect(force) {
  if (S.ws && S.ws.readyState <= 1 && !force) return;
  if (S.ws) { try { S.ws.onclose = null; S.ws.close(); } catch (e) {} }
  const list = hosts();
  const host = list[S.hostIdx % list.length];
  let ws;
  try { ws = new WebSocket("wss://" + host + "/ws"); } catch (e) { S.hostIdx++; return setTimeout(connect, 600); }
  S.ws = ws;
  const opened = setTimeout(() => { if (ws.readyState !== 1) { try { ws.close(); } catch (e) {} } }, 3500);
  ws.onopen = () => {
    clearTimeout(opened);
    S.connected = true; S.retry = 0; S.kicked = false;
    send({ t: "hello", ua: navigator.userAgent, name: "iPhone" }, true);
    render();
  };
  ws.onmessage = e => { try { onMsg(JSON.parse(e.data)); } catch (x) {} };
  ws.onclose = () => {
    clearTimeout(opened);
    const was = S.connected;
    S.connected = false;
    if (S.ws === ws) S.ws = null;
    if (was && !S.kicked) { toast(tr("Connection lost")); stop(); }
    if (!was) S.hostIdx++;
    render();
    if (!S.kicked) setTimeout(connect, Math.min(4000, 500 + 400 * S.retry++));
  };
}
function onMsg(m) {
  switch (m.t) {
    case "cfg":
      if (m.lang) lang = m.lang;
      accent(m.accent);
      if (m.hosts) store.set("hosts", m.hosts);
      Object.assign(S.cfg, m.cfg || {});
      if (m.cfg && m.cfg.camera && !store.get("camSet", false)) S.cam = m.cfg.camera;
      S.want = m.want !== false;
      if (S.want && !S.live && !S.starting) start(); else render();
      break;
    case "answer":
      if (S.pc) S.pc.setRemoteDescription({ type: "answer", sdp: m.sdp }).catch(e => toast(String(e.message || e)));
      break;
    case "stream":
      S.want = !!m.on; S.want ? start() : stop();
      break;
    case "set":
      if ("camera" in m) { store.set("camSet", false); switchCam(m.camera); }
      if ("mic" in m) setMic(!!m.mic, true);
      if ("zoom" in m) applyZoom(+m.zoom, false);
      for (const k of ["res", "fps", "bitrate"]) if (k in m) { S.cfg[k] = m[k]; if (S.live) start(); }
      break;
    case "torch": setTorch(m.on); break;
    case "focus": focusAt(m.x, m.y); focusRing(m.x * innerWidth, m.y * innerHeight); break;
    case "kick": S.kicked = true; stop(); render(); break;
    case "ping": send({ t: "pong", ts: m.ts }); break;
    case "pong": S.rtt = Math.max(1, Date.now() - m.ts); render(); break;
  }
}
setInterval(() => { if (S.live) send({ t: "ping", ts: Date.now() }); }, 2000);

// ── controls ──
$("live").onclick = () => { haptic(); setWant(!(S.live || S.starting)); };
$("flip").onclick = () => { haptic(); store.set("camSet", true); switchCam(S.cam === "front" ? (store.get("lastBack", "back")) : (store.set("lastBack", S.cam), "front")); };
$("torch").onclick = () => { haptic(); setTorch("toggle"); };
$("mic").onclick = () => { haptic(); setMic(!S.cfg.mic); };
$("dark").onclick = () => { haptic(); setBlack(true); };

function setBlack(on) {
  S.black = on; render();
  if (on) driftBlack();
}
function driftBlack() {                       // the little line wanders so nothing burns into the OLED
  if (!S.black) return;
  const el = $("blackInfo");
  el.style.left = (20 + Math.random() * 60) + "%";
  el.style.top = (25 + Math.random() * 50) + "%";
  setTimeout(driftBlack, 6000);
}
let lastTap = 0;
$("black").addEventListener("touchend", e => { const n = Date.now(); if (n - lastTap < 350) setBlack(false); lastTap = n; e.preventDefault(); });
$("black").addEventListener("dblclick", () => setBlack(false));

// tap = focus, pinch = zoom (on the picture, not on the dock)
let pinch = null, tapStart = null;
const stage = $("stage");
stage.addEventListener("touchstart", e => {
  if (e.touches.length === 2) { const [a, b] = e.touches; pinch = { d: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), z: S.zoom }; tapStart = null; }
  else if (e.touches.length === 1) tapStart = { x: e.touches[0].clientX, y: e.touches[0].clientY, t: Date.now() };
}, { passive: true });
stage.addEventListener("touchmove", e => {
  if (pinch && e.touches.length === 2) {
    const [a, b] = e.touches; const d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
    const v = pinch.z * d / pinch.d;
    applyZoom(v);
    if (!zoomRange()) send({ t: "status", zoomReq: S.zoom });
  }
}, { passive: true });
stage.addEventListener("touchend", e => {
  if (pinch && e.touches.length < 2) { pinch = null; status(); return; }
  if (tapStart && Date.now() - tapStart.t < 300 && S.live) {
    focusRing(tapStart.x, tapStart.y);
    focusAt(tapStart.x / innerWidth, tapStart.y / innerHeight);
  }
  tapStart = null;
});

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") {
    connect();
    if (S.want && S.connected && (!S.live || !S.stream || S.stream.getVideoTracks()[0].readyState === "ended")) start();
    else if (S.live) holdWake();
  }
});
addEventListener("orientationchange", () => setTimeout(status, 400));
document.addEventListener("gesturestart", e => e.preventDefault());

if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
listDevices().then(render);
render();
connect();
