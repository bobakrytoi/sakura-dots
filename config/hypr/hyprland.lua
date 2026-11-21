-- ╭──────────────────────────────────────────────────────────╮
-- │  ✿  sakura mono - hyprland rice                          │
-- │  monochrome + soft sakura pink accent             │
-- ╰──────────────────────────────────────────────────────────╯
--  Keybind cheatsheet:  SUPER + /

------------------
---- MONITORS ----
------------------
-- Screens are set in Settings > Displays, which writes ~/.config/hypr/monitors.lua.
-- Without that file (a fresh install / another PC) every screen just uses its preferred mode.
-- The main monitor (dock, start menu, widgets, workspaces 1-5) is "mainMonitor" in ~/.config/sakura/settings.json.
local function readall(p) local f = io.open(p, "r"); if not f then return nil end local t = f:read("a"); f:close(); return t end
local sakuraCfg  = readall(os.getenv("HOME") .. "/.config/sakura/settings.json") or ""
MAIN_MONITOR     = sakuraCfg:match('"mainMonitor"%s*:%s*"([^"]+)"')
SECOND_MONITOR   = sakuraCfg:match('"secondMonitor"%s*:%s*"([^"]+)"')
ACCENT           = sakuraCfg:match('"accent"%s*:%s*"#(%x%x%x%x%x%x)"') or "f4b6c8"   -- Settings > Appearance > Accent color
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
do
    local mf = os.getenv("HOME") .. "/.config/hypr/monitors.lua"
    if readall(mf) then pcall(dofile, mf) end
end

-- workspaces 1-5 on the main monitor, 6-10 on the second one (only when they are known)
for i = 1, 10 do
    local mon = (i <= 5) and MAIN_MONITOR or SECOND_MONITOR
    if mon then
        hl.workspace_rule({ workspace = tostring(i), monitor = mon, default = (i == 1 or i == 6), persistent = true })
    else
        hl.workspace_rule({ workspace = tostring(i), persistent = (i <= 5) })
    end
end


-------------------
---- PROGRAMS ----
-------------------
local terminal    = "kitty"
local fileManager = "dolphin"
local browser     = "firefox"
local menu        = os.getenv("HOME") .. "/.config/hypr/scripts/menu.sh"
local scripts     = os.getenv("HOME") .. "/.config/hypr/scripts"


-------------------
---- AUTOSTART ---
-------------------
hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("sleep 0.5 && " .. scripts .. "/wallpaper.sh restore")
    hl.exec_cmd(scripts .. "/waybar.sh")
    hl.exec_cmd("sleep 2; " .. scripts .. "/sfx.sh login")
    hl.exec_cmd("sleep 4; " .. scripts .. "/rgb.sh login")
    -- notifications: quickshell (Notifs.qml); swaync is no longer started
    hl.exec_cmd(scripts .. "/osd.sh")   -- swayosd at the position from Settings > Notifications
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("hypridle")
    hl.exec_cmd(scripts .. "/clipwatch.sh login")   -- cliphist watchers, as set in Settings
    hl.exec_cmd("sleep 1.5; command -v qs && qs")
    hl.exec_cmd("sleep 3; " .. scripts .. "/session.py restore")
    hl.exec_cmd("sleep 5; command -v gpu-screen-recorder && " .. scripts .. "/capture.sh autostart")   -- reopen last session's apps in place
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Sakura 24")
    hl.exec_cmd(scripts .. "/autoscroll.py")   -- middle-button autoscroll daemon
end)


-----------------------------
---- ENVIRONMENT ---
-----------------------------
hl.env("XCURSOR_THEME", "Bibata-Modern-Sakura")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Sakura")
-- NVIDIA
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
-- Wayland everywhere possible
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("MOZ_ENABLE_WAYLAND", "1")
-- WebKitGTK (Telegram mini apps, help viewers) crashes on NVIDIA with its DMA-BUF renderer
hl.env("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
hl.env("WEBKIT_DISABLE_COMPOSITING_MODE", "1")


-------------------------
---- LOOK AND FEEL ----
-------------------------
hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 14,
        gaps_workspaces = 60,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(ffffffee)", "rgba(" .. ACCENT .. "ee)", "rgba(8a8a94aa)", "rgba(" .. ACCENT .. "ee)" }, angle = 45 },
            inactive_border = "rgba(2a2a30aa)",
        },
        resize_on_border = true,
        allow_tearing    = true,     -- only games marked "immediate" below tear (lowest input lag)
        layout = "dwindle",
        snap = { enabled = true },
    },

    decoration = {
        rounding       = 14,
        rounding_power = 3,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        dim_inactive = true,

        -- jelly windows: they wobble while you drag them
        wobble = { enabled = true, mesh = 24, stiffness = 420, damping = 15, mass = 0.65, intensity = 0.45 },
        dim_strength = 0.06,
        dim_special  = 0.4,

        screen_shader = os.getenv("HOME") .. "/.config/hypr/shaders/color.glsl",   -- color correction (Settings > Appearance)

        shadow = {
            enabled      = true,
            range        = 26,
            render_power = 3,
            offset       = "0 6",
            color          = "rgba(000000aa)",
            color_inactive = "rgba(00000066)",
        },

        blur = {
            enabled   = true,
            size      = 8,
            passes    = 3,
            noise     = 0.015,
            contrast  = 1.0,
            brightness = 0.85,
            vibrancy  = 0.2,
            vibrancy_darkness = 0.3,
            popups    = true,
            special   = true,
            new_optimizations = true,
        },
    },

    animations = {
        enabled = true,
        workspace_wraparound = true,
    },
})

-- animations: smooth, no bounce
hl.curve("smooth",    { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })
hl.curve("outQuint",  { type = "bezier", points = { {0.22, 1},   {0.36, 1} } })
hl.curve("outExpo",   { type = "bezier", points = { {0.16, 1},   {0.3, 1} } })
hl.curve("inOut",     { type = "bezier", points = { {0.65, 0},   {0.35, 1} } })
hl.curve("fadeOutC",  { type = "bezier", points = { {0.4, 0},    {1, 1} } })
hl.curve("linear",    { type = "bezier", points = { {0, 0},      {1, 1} } })
-- "rubber": windows follow the cursor with a little inertia and settle with a soft bounce (drag + snap only)
hl.curve("rubber",    { type = "spring", mass = 1, stiffness = 260, damping = 17 })

hl.animation({ leaf = "global",           enabled = true, speed = 6,   bezier = "outQuint" })
hl.animation({ leaf = "windows",          enabled = true, speed = 4.5, bezier = "outQuint" })
hl.animation({ leaf = "windowsIn",        enabled = true, speed = 4,   bezier = "outQuint", style = "popin 92%" })
hl.animation({ leaf = "windowsOut",       enabled = true, speed = 3,   bezier = "fadeOutC", style = "popin 92%" })
hl.animation({ leaf = "windowsMove",      enabled = true, speed = 4.5, bezier = "outQuint" })
hl.animation({ leaf = "border",           enabled = true, speed = 6,   bezier = "outQuint" })
hl.animation({ leaf = "borderangle",      enabled = true, speed = 100, bezier = "linear",   style = "loop" })
hl.animation({ leaf = "fadeIn",           enabled = true, speed = 4,   bezier = "outQuint" })
hl.animation({ leaf = "fadeOut",          enabled = true, speed = 3,   bezier = "fadeOutC" })
hl.animation({ leaf = "fadeSwitch",       enabled = true, speed = 5,   bezier = "outQuint" })
hl.animation({ leaf = "fadeShadow",       enabled = true, speed = 5,   bezier = "outQuint" })
hl.animation({ leaf = "fadeDim",          enabled = true, speed = 5,   bezier = "outQuint" })
hl.animation({ leaf = "layersIn",         enabled = true, speed = 3.5, bezier = "outQuint", style = "fade" })
hl.animation({ leaf = "layersOut",        enabled = true, speed = 3,   bezier = "fadeOutC", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",     enabled = true, speed = 3.5, bezier = "outQuint" })
hl.animation({ leaf = "fadeLayersOut",    enabled = true, speed = 3,   bezier = "fadeOutC" })
hl.animation({ leaf = "workspaces",       enabled = true, speed = 5,   bezier = "outExpo",  style = "slidefade 10%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5,   bezier = "outExpo",  style = "slidefadevert 15%" })
hl.animation({ leaf = "zoomFactor",       enabled = true, speed = 5,   bezier = "outQuint" })

-- fullscreen video (YouTube etc.) must not switch the monitors to HDR or a "video" picture mode:
-- that made the screens go black for a couple of seconds and then washed out the colors
hl.config({
    render = {
        cm_auto_hdr       = 0,       -- never flip to HDR on its own
        send_content_type = false,   -- don't tell the monitor "this is a video/game" (some monitors change picture mode)
        direct_scanout    = 0,       -- fullscreen apps still go through Color Control
    },
})

hl.config({
    dwindle = { preserve_split = true },
    master  = { new_status = "master" },
    scrolling = { fullscreen_on_one_column = true },
})


--------------
---- MISC ----
--------------
hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        allow_session_lock_restore = true,   -- if the quickshell lock dies, another locker can take over
        disable_splash_rendering = true,
        background_color        = "rgb(0e0e10)",
        animate_manual_resizes  = true,
        animate_mouse_windowdragging = false,   -- the window follows the cursor exactly; the jelly does the rest
        focus_on_activate       = true,
        enable_swallow          = true,
        swallow_regex           = "^(kitty)$",
        session_lock_blur       = true,
        mouse_move_focuses_monitor = false,   -- moving the mouse to the other monitor does not steal focus
        middle_click_paste      = false,
        on_focus_under_fullscreen = 2,
        float_force_onscreen    = 1,
        new_float_force_onscreen = 1,
    },
    cursor = {
        default_monitor = MAIN_MONITOR or "",
        no_warps = true,
        warp_on_change_workspace = 0,
    },
    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles   = true,
    },
    layers = {
        allow_new_top_layers_over_existing_fullscreen = true,
    },
})


---------------
---- INPUT ----
---------------
hl.config({
    input = {
        kb_layout  = "us,ru",
        kb_variant = ",",
        kb_model   = "",
        kb_options = "grp:alt_shift_toggle",
        kb_rules   = "",
        numlock_by_default = true,
        follow_mouse = 2,                 -- like Windows: a window takes focus only when you click it
        float_switch_override_focus = 0,  -- hovering floating windows never steals focus
        sensitivity  = 0,
        touchpad = { natural_scroll = false },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })


---------------------
---- KEYBINDS ----
---------------------
local mod = "SUPER"
local function sh(cmd) return hl.dsp.exec_cmd(cmd) end

-- apps
hl.bind(mod .. " + Q",          sh(terminal),                         { desc = "Terminal" })
hl.bind(mod .. " + Return",     sh(terminal),                         { desc = "Terminal" })
hl.bind(mod .. " + E",          sh(fileManager),                      { desc = "File manager" })
hl.bind(mod .. " + B",          sh(browser),                          { desc = "Browser" })
hl.bind(mod .. " + R",          sh(menu),                             { desc = "App launcher" })
hl.bind(mod .. " + SPACE",      sh(menu),                             { desc = "App launcher" })
hl.bind(mod .. " + V",          sh(scripts .. "/clipboard.sh"),       { desc = "Clipboard history" })
hl.bind(mod .. " + N",          sh("qs ipc call notifs-center toggle"),           { desc = "Notification center" })
-- (removed by user request: Super+M power menu) hl.bind(mod .. " + M",          sh(scripts .. "/powermenu.sh"),       { desc = "Power menu" })
hl.bind(mod .. " + L",          sh(scripts .. "/lock.sh"),          { desc = "Lock screen" })
hl.bind(mod .. " + SHIFT + C",  sh("hyprpicker -a -n"),               { desc = "Color picker" })
hl.bind(mod .. " + SLASH",      sh(scripts .. "/keybinds.sh"),        { desc = "Keybind cheatsheet" })
hl.bind("CTRL + SHIFT + ESCAPE", sh(os.getenv("HOME") .. "/.local/bin/taskmgr"), { desc = "Task manager" })

-- screenshots
hl.bind("Print",                sh(scripts .. "/screenshot.sh region"), { desc = "Screenshot region" })
hl.bind(mod .. " + SHIFT + S",  sh(scripts .. "/screenshot.sh region"), { desc = "Screenshot region" })
hl.bind("SHIFT + Print",        sh(scripts .. "/screenshot.sh screen"), { desc = "Screenshot monitor" })
hl.bind(mod .. " + Print",      sh(scripts .. "/screenshot.sh edit"),   { desc = "Screenshot + edit" })

-- windows
hl.bind(mod .. " + C",          hl.dsp.window.close(),                      { desc = "Close window" })
hl.bind(mod .. " + F",          hl.dsp.window.fullscreen(),                 { desc = "Fullscreen" })
hl.bind(mod .. " + T",          hl.dsp.window.float({ action = "toggle" }), { desc = "Toggle floating" })
hl.bind(mod .. " + P",          hl.dsp.window.pseudo(),                     { desc = "Pseudo-tile" })
-- cursor lock ("invisible wall") for games, all inside the compositor, no scripts:
--  * while a locked game is the active window, every OTHER monitor is shifted +20000 px in the layout, so the
--    game's monitor has no neighbour and its edge is a hard wall (no leak, no polling; position-only change,
--    no modeset). Back to monitors.lua the moment the game stops being active: Super (key down), any layer
--    that takes the keyboard (start menu, Alt+Tab switcher), another window, leaving fullscreen.
--  * the "games-cursorlock" window rules below (confine_pointer) stay as a second line of defence.
--  * Super+Shift+G flips the lock for the active window via tags ("nolock" / "cursorlock").
local CL_MONITORS = os.getenv("HOME") .. "/.config/hypr/monitors.lua"
local function cl_tags(w)
    local tags = {}
    for _, t in ipairs(w.tags or {}) do tags[(tostring(t):gsub("%*$", ""))] = true end
    return tags
end
local function cl_auto(w)
    local c = tostring(w.class or "")
    return (w.fullscreen or 0) ~= 0 and (c == "cs2" or c == "dota2" or c == "gamescope" or c:match("^steam_app_") ~= nil)
end
local function cl_locked(w)
    if not w then return false end
    local tags = cl_tags(w)
    return tags.cursorlock == true or (cl_auto(w) and not tags.nolock)
end
local function cl_monitor_rules()   -- the hl.monitor{} rules monitors.lua would apply
    local rules, orig = {}, hl.monitor
    hl.monitor = function(r) rules[#rules + 1] = r end
    pcall(dofile, CL_MONITORS)
    hl.monitor = orig
    return rules
end
local cl_wall = nil                 -- name of the monitor the wall is around, or nil
local cl_set
cl_set = function(mon)
    if mon == cl_wall then return end
    if cl_wall then pcall(dofile, CL_MONITORS) end          -- put the layout back
    cl_wall = mon
    if not mon then return end
    for _, r in ipairs(cl_monitor_rules()) do
        local x, y = tostring(r.position or ""):match("^(-?%d+)x(-?%d+)$")
        if r.output and r.output ~= "" and r.output ~= mon and x then
            local c = {}
            for k, v in pairs(r) do c[k] = v end
            c.position = (tonumber(x) + 20000) .. "x" .. y
            hl.monitor(c)
        end
    end
end
local function cl_monname(w)
    local m = w and w.monitor
    if not m then return nil end
    local ok, n = pcall(function() return m.name end)
    if ok and n then return tostring(n) end
    return tostring(m):match(":([^)]+)%)")
end
-- debounce: release is instant, arming waits CL_SETTLE ms and re-checks, so fast
-- focus flapping (alt-tab spam, a shell restart) never moves outputs back and forth
local CL_SETTLE = 400
local cl_pending = nil
local function cl_want()
    local w = hl.get_active_window()
    return cl_locked(w) and cl_monname(w) or nil
end
local cl_set_now = cl_set
cl_set = function(mon)
    if cl_pending then pcall(function() cl_pending:set_enabled(false) end); cl_pending = nil end
    if not mon or mon == cl_wall then return cl_set_now(mon) end
    if cl_wall then cl_set_now(nil) end
    cl_pending = hl.timer(function()
        cl_pending = nil
        if cl_want() == mon then cl_set_now(mon) end
    end, { timeout = CL_SETTLE, type = "oneshot" })
end
local function cl_refresh() cl_set(cl_want()) end
hl.on("window.active", cl_refresh)
hl.on("window.fullscreen", cl_refresh)
hl.on("window.close", cl_refresh)
hl.on("window.update_rules", cl_refresh)
hl.on("layer.opened", function(ls)
    local ki = ls and ls.keyboard_interactivity
    if ki ~= nil and ki ~= 0 and ki ~= false and ki ~= "none" then cl_set(nil) end
end)
hl.on("layer.closed", cl_refresh)
hl.on("input.keyboard.key", function(code, _, state)
    if state == 1 and (code == 133 or code == 134) then cl_set(nil) end   -- Super down: free at once
end)
hl.bind(mod .. " + SHIFT + G", function()
    local w = hl.get_active_window()
    if not w then return end
    local tags, auto, locked = cl_tags(w), cl_auto(w), cl_locked(w)
    local win = "address:" .. tostring(w.address)
    if locked then
        if tags.cursorlock then hl.dispatch(hl.dsp.window.tag({ tag = "-cursorlock", window = win })) end
        if auto and not tags.nolock then hl.dispatch(hl.dsp.window.tag({ tag = "+nolock", window = win })) end
    else
        if tags.nolock then hl.dispatch(hl.dsp.window.tag({ tag = "-nolock", window = win })) end
        if not auto then hl.dispatch(hl.dsp.window.tag({ tag = "+cursorlock", window = win })) end
    end
    cl_set((not locked) and cl_monname(w) or nil)
    hl.dispatch(hl.dsp.exec_cmd("notify-send -a Hyprland -t 1500 'Курсор' '" .. (locked and "свободен" or "заперт в окне") .. "'"))
end, { desc = "Toggle cursor lock" })
hl.bind(mod .. " + J",          hl.dsp.layout("togglesplit"),               { desc = "Toggle split" })
hl.bind("ALT + TAB",            sh("qs ipc call switcher next"),            { desc = "Switch windows (Alt+Tab)" })
hl.bind("ALT + SHIFT + TAB",    sh("qs ipc call switcher prev"),            { desc = "Switch windows backwards" })
hl.bind("ALT_L", sh("qs ipc call switcher commit"), { release = true, ignore_mods = true, non_consuming = true })
hl.bind("ALT_R", sh("qs ipc call switcher commit"), { release = true, ignore_mods = true, non_consuming = true })
-- triple Shift: the mascot runs along the screen (mascot-shift.sh counts the taps)
hl.bind("SHIFT_L", sh(scripts .. "/mascot-shift.sh"), { release = true, ignore_mods = true, non_consuming = true })
hl.bind("SHIFT_R", sh(scripts .. "/mascot-shift.sh"), { release = true, ignore_mods = true, non_consuming = true })

for _, d in ipairs({ "left", "right", "up", "down" }) do
    if d == "left" or d == "right" then hl.bind(mod .. " + " .. d, hl.dsp.focus({ direction = d })) end
    hl.bind(mod .. " + SHIFT + " .. d, hl.dsp.window.swap({ direction = d }))
end

-- workspaces
for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mod .. " + S",          hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + ALT + S",    hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- mouse
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- volume / brightness / media (with OSD)
-- volume keys / a headset wheel: step at once, keep stepping while held (vol.sh hold), stop on release
hl.bind("XF86AudioRaiseVolume",  sh(scripts .. "/vol.sh hold up"),   { locked = true })
hl.bind("XF86AudioLowerVolume",  sh(scripts .. "/vol.sh hold down"), { locked = true })
hl.bind("XF86AudioRaiseVolume",  sh(scripts .. "/vol.sh release"),   { locked = true, release = true })
hl.bind("XF86AudioLowerVolume",  sh(scripts .. "/vol.sh release"),   { locked = true, release = true })
hl.bind("XF86AudioMute",         sh(scripts .. "/vol.sh mute"),    { locked = true })   -- OSD in the notch (swayosd if qs is down)
hl.bind("XF86AudioMicMute",      sh(scripts .. "/vol.sh micmute"), { locked = true })
hl.bind("XF86MonBrightnessUp",   sh("swayosd-client --brightness raise"),          { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", sh("swayosd-client --brightness lower"),          { locked = true, repeating = true })
hl.bind("XF86AudioNext",  sh("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", sh("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  sh("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  sh("playerctl previous"),   { locked = true })
hl.bind("XF86Calculator", sh(os.getenv("HOME") .. "/.local/bin/sakura-calc"), { desc = "Calculator" })   -- Super+C is close-window


--------------------------------
---- WINDOW AND LAYER RULES ----
--------------------------------
-- all windows float (free placement like Windows); SUPER+T toggles tiling for a window
hl.window_rule({ name = "float-all", match = { class = ".*" }, float = true })
-- games always open truly fullscreen (no floating, no moving around)
hl.window_rule({ name = "games-fullscreen", match = { class = "^(cs2|dota2|steam_app_.*|gamescope)$" }, fullscreen = true, float = false })
-- cursor lock: a focused fullscreen game keeps the pointer inside its window (real compositor confine,
-- released on alt-tab / workspace switch / leaving fullscreen). Super+Shift+G flips it per window via tags:
-- "nolock" switches the auto lock off, "cursorlock" forces it on for any window. Later rules win.
hl.window_rule({ name = "games-cursorlock", match = { class = "^(cs2|dota2|steam_app_.*|gamescope)$", fullscreen = true }, confine_pointer = true })
hl.window_rule({ name = "cursorlock-off",   match = { tag = "nolock" },     confine_pointer = false })
hl.window_rule({ name = "cursorlock-force", match = { tag = "cursorlock" }, confine_pointer = true })
-- center new native windows; X11 apps (Steam etc.) place their own popups, menus and notifications
hl.window_rule({ name = "center-native", match = { class = ".*", xwayland = false }, center = true })

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- floating centered utilities
for _, c in ipairs({
    "org.pulseaudio.pavucontrol", "nm-connection-editor", "org.gnome.Calculator",
    "org.gnome.Loupe", "org.gnome.FileRoller", "com.gabm.satty", "btop",
    "nwg-look", "qt6ct", "kvantummanager", "org.gnome.NautilusPreviewer", "org.kde.ark",
    "xdg-desktop-portal-gtk", "hyprland-run", "hyprland-share-picker",
    "mullvad-vpn",   -- runs under XWayland (mullvad-open), so center-native does not cover it
}) do
    hl.window_rule({ name = "float-" .. c, match = { class = "^(" .. c .. ")$" }, float = true, center = true })
end
hl.window_rule({ name = "size-pavu", match = { class = "^(org.pulseaudio.pavucontrol)$" }, size = "900 600" })
hl.window_rule({ name = "size-btop", match = { class = "^(btop)$" },                      size = "1200 750" })

-- open/save dialogs
hl.window_rule({ name = "float-dialogs", match = { title = "^(Open File|Save File|Open Folder|Открыть файл|Сохранить файл|Select a File|Choose Files).*" }, float = true, center = true, size = "1000 650" })
-- picture-in-picture
hl.window_rule({ name = "pip", match = { title = "^(Picture-in-Picture|Картинка в картинке)$" }, float = true, pin = true, size = "640 360", move = "monitor_w-660 monitor_h-380" })
-- mpv: opens fitted inside the work area (mpv.conf autofit-larger=80%x80%), centered between the top bar and the dock; f / double-click = real fullscreen
hl.window_rule({ name = "mpv", match = { class = "^(mpv)$" }, float = true, center = true })

-- glass file manager
hl.window_rule({ name = "glass-nautilus", match = { class = "^(org.gnome.Nautilus)$" }, opacity = "0.93 0.88" })
-- Dolphin (default file manager): the glass comes from the Kvantum theme "Sakura" (translucent background,
-- opaque text - hypr/scripts/qt-theme.py), Hyprland only blurs what is behind it; a bit dimmer when unfocused
hl.window_rule({ name = "glass-dolphin", match = { class = "^(org.kde.dolphin)$" }, opacity = "1.0 0.94" })
hl.window_rule({ name = "glass-kate",    match = { class = "^(org.kde.kate|org.kde.kwrite)$" }, opacity = "0.92 0.88" })
hl.window_rule({ name = "size-ark",      match = { class = "^(org.kde.ark)$" },     size = "900 600" })

-- blur behind bar, menus, notifications, dock
for _, ns in ipairs({ "waybar", "waybar-left", "waybar-right", "rofi", "swaync-control-center", "swaync-notification-window", "nwg-dock", "swayosd", "notes", "sketch", "edge-tab", "trayflyout", "dock", "topbar", "desktop-widgets", "power", "netmenu", "wallpicker", "desktopmenu", "widget-editor", "clipboard", "archive", "notifications", "notifcenter", "mascot", "corner-island", "sakura-sound-mini", "shot", "shot-pin", "convert", "convert-progress" }) do
    hl.layer_rule({ name = "blur-" .. ns, match = { namespace = "^(" .. ns .. ")$" }, blur = true, ignore_alpha = 0.2 })
end
hl.layer_rule({ name = "anim-rofi",   match = { namespace = "^(rofi)$" },   animation = "popin 95%" })
hl.layer_rule({ name = "anim-swaync", match = { namespace = "^(swaync-control-center|swaync-notification-window)$" }, animation = "slide right" })
hl.layer_rule({ name = "anim-dock",   match = { namespace = "^(nwg-dock)$" }, animation = "slide bottom" })
hl.layer_rule({ name = "anim-waybar", match = { namespace = "^(waybar|waybar-left|waybar-right)$" },  animation = "slide" })   -- slides from whichever edge it is on (top or bottom, see barpos.sh)


------------------------------
---- MINIMIZE (_ button) -----
------------------------------
-- minimized windows go to a hidden workspace; SUPER+H shows/hides it,
-- clicking the app in the taskbar brings it back
local function mlog(...)
    local f = io.open(os.getenv("HOME") .. "/.cache/hypr-minimize.log", "a")
    if not f then return end
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local t = type(v)
        local d = tostring(v)
        if t == "table" or t == "userdata" then
            local ok, addr = pcall(function() return v.address end)
            local ok2, mn = pcall(function() return v.minimized end)
            local ok3, win = pcall(function() return v.window end)
            d = d .. " address=" .. tostring(ok and addr) .. " minimized=" .. tostring(ok2 and mn) .. " window=" .. tostring(ok3 and win)
        end
        parts[#parts + 1] = t .. ":" .. d
    end
    f:write(os.date("%H:%M:%S ") .. table.concat(parts, " | ") .. "\n")
    f:close()
end

-- the window comes back the way it was: on its own workspace (so its own monitor), floating or tiled, where,
-- how big, fullscreen. __minSave on minimize, __minBack to bring it back (minimize.sh calls them through hyprctl eval).
-- Kept in a file, not in a Lua table: "hyprctl reload" (accent.sh, Settings, …) starts Lua afresh and would forget it.
-- One line per window: address float x y w h fullscreen monitor-x monitor-y workspace
local MINF = os.getenv("HOME") .. "/.cache/sakura/minimized"
local function mxy(v) if v == nil then return nil end return (v.x or v[1]), (v.y or v[2]) end
local function minRead()
    local t = {}
    local f = io.open(MINF, "r"); if not f then return t end
    for line in f:lines() do
        local a, fl, x, y, w, h, fs, mx, my, ws = line:match("^(%S+) (%d) (%-?%d+) (%-?%d+) (%d+) (%d+) (%d+) (%-?%d+) (%-?%d+) (%-?%d+)$")
        if a then t[a] = { float = fl == "1", x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h),
                           fs = tonumber(fs), mx = tonumber(mx), my = tonumber(my), ws = tonumber(ws) } end
    end
    f:close()
    return t
end
local function minWrite(t)
    local f = io.open(MINF, "w"); if not f then return end
    for a, g in pairs(t) do
        f:write(string.format("%s %d %d %d %d %d %d %d %d %d\n", a, g.float and 1 or 0, g.x, g.y, g.w, g.h, g.fs, g.mx, g.my, g.ws))
    end
    f:close()
end
function __minSave(addr)
    local w = hl.get_window("address:" .. addr); if not w then return end
    local x, y = mxy(w.at); local W, H = mxy(w.size)
    local m = w.monitor or hl.get_active_monitor()
    local t = minRead()
    for a in pairs(t) do if not hl.get_window("address:" .. a) then t[a] = nil end end   -- closed windows
    t[addr] = { float = w.floating, x = x, y = y, w = W, h = H, fs = w.fullscreen or 0, mx = m and m.x or 0, my = m and m.y or 0,
               ws = w.workspace and w.workspace.id or 0 }
    minWrite(t)
end
-- fallbackWs: where it goes when nothing was saved (minimized before this existed): the current workspace
function __minBack(addr, fallbackWs)
    local sel = "address:" .. addr
    local t = minRead()
    local g = t[addr]
    if g then t[addr] = nil; minWrite(t) end
    local ws = (g and g.ws and g.ws > 0) and g.ws or fallbackWs
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws), window = sel }))
    if not g then return end
    local w = hl.get_window(sel); if not w then return end
    if g.float and not w.floating then hl.dispatch(hl.dsp.window.float({ action = "set", window = sel }))
    elseif not g.float and w.floating then hl.dispatch(hl.dsp.window.float({ action = "unset", window = sel })) end
    if g.float and g.x then
        local m = w.monitor or hl.get_active_monitor()        -- its workspace may sit on another monitor by now
        local dx, dy = (m and m.x or g.mx) - g.mx, (m and m.y or g.my) - g.my
        hl.dispatch(hl.dsp.window.resize({ x = g.w, y = g.h, window = sel }))   -- resize first (it keeps the center)
        hl.dispatch(hl.dsp.window.move({ x = g.x + dx, y = g.y + dy, window = sel }))
    end
    if g.fs ~= 0 then hl.dispatch(hl.dsp.window.fullscreen({ mode = g.fs == 1 and "maximized" or "fullscreen", action = "set", window = sel })) end
end

hl.on("window.minimize", function(a, b, c)
    local w = a
    local okw, inner = pcall(function() return a.window end)
    if okw and inner then w = inner end
    local ok, addr = pcall(function() return w.address end)
    if not ok or not addr then return end
    local state = b
    local okm, mn = pcall(function() return a.minimized end)
    if okm and mn ~= nil then state = mn end
    if state == false or state == 0 or state == "0" then return end
    -- small delay: the app re-activates itself right after the request
    hl.exec_cmd("sleep 0.15; " .. scripts .. "/minimize.sh hide-addr " .. addr)
end)
hl.bind(mod .. " + X", sh(scripts .. "/minimize.sh hide"),    { desc = "Minimize window" })
hl.bind(mod .. " + H", sh(scripts .. "/minimize.sh restore"), { desc = "Restore minimized window" })

-- drag / resize any window (also ones without a title bar, like the terminal)
-- (turned off automatically while a fullscreen game has focus - games use Alt+click)
__altDrag = {
    hl.bind("ALT + mouse:272", hl.dsp.window.drag(),   { mouse = true }),
    hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true }),
}

-- a minimized window that gets activated (taskbar click etc.) comes straight back to where it was,
-- spat out of the top bar's notch (minimize.sh restore-addr → quickshell Genie.qml → restore-now)
hl.on("window.active", function(w)
    if not w then return end
    local ok, name = pcall(function() return w.workspace and w.workspace.name end)
    if not ok or name ~= "special:minimized" then return end
    local addr = w.address
    if __min_skip == addr then return end          -- this is the minimize itself, not a restore
    local m = hl.get_active_monitor(); if not m then return end
    local sp = m.active_special_workspace
    if sp and sp.name == "special:minimized" then hl.dispatch(hl.dsp.workspace.toggle_special("minimized")) end
    -- it stays hidden while it flies out; a second activation meanwhile must not start another flight
    __min_skip = addr
    hl.timer(function() if __min_skip == addr then __min_skip = nil end end, { timeout = 1200, type = "oneshot" })
    hl.exec_cmd(scripts .. "/minimize.sh restore-addr " .. addr)
end)

-- Win key alone opens the start menu
hl.bind("SUPER + SUPER_L", sh(scripts .. "/menu.sh"), { release = true, dont_inhibit = true, desc = "Start menu" })
hl.layer_rule({ name = "blur-startmenu", match = { namespace = "^(startmenu)$" }, blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ name = "anim-startmenu", match = { namespace = "^(startmenu)$" }, animation = "fade" })   -- the menu animates itself (grows out of the dock)
hl.layer_rule({ name = "anim-shot", match = { namespace = "^(shot)$" }, no_anim = true })   -- screenshot editor: the frozen frame must appear instantly (Shot.qml fades itself)
hl.layer_rule({ name = "blur-share-picker", match = { namespace = "^(share-picker)$" }, blur = true, ignore_alpha = 0.2, no_anim = true })   -- screen-share picker (hypr/scripts/share-picker-qs) animates itself
hl.layer_rule({ name = "blur-minimize-picker", match = { namespace = "^(minimize-picker)$" }, blur = true, ignore_alpha = 0.2, no_anim = true })   -- minimized windows picker (hypr/scripts/minimize-qs)

-- load values saved by the Settings app (overrides the defaults above)
do
    local us = os.getenv("HOME") .. "/.config/hypr/user-settings.lua"
    local f = io.open(us, "r")
    if f then f:close(); pcall(dofile, us) end
end
-- Password helper (quickshell PasswordHelper.qml): its hotkey lives in pwhelper.lua, written by Settings > Password helper
do
    local pf = os.getenv("HOME") .. "/.config/hypr/pwhelper.lua"
    local f = io.open(pf, "r")
    if f then f:close(); pcall(dofile, pf) end
end
hl.layer_rule({ name = "blur-pwhelper", match = { namespace = "^(pwhelper)$" }, blur = true, ignore_alpha = 0.05, no_anim = true })   -- frosted backdrop; it animates itself
hl.window_rule({ name = "settings-app", match = { title = "^(Settings)$", class = "^(org.quickshell)$" }, float = true, center = true, size = "1120 740" })
hl.window_rule({ name = "taskmgr-app", match = { title = "^(Task Manager)$", class = "^(org.quickshell)$" }, float = true, center = true, size = "1140 740" })
hl.window_rule({ name = "sakura-sound", match = { title = "^(Sakura Sound)$", class = "^(org.quickshell)$" }, float = true, center = true, size = "1240 800", rounding = 22 })
-- sakura-calc (~/.config/sakura-calc, own app id): floating glass calculator; size comes from the app (remembered per mode)
hl.window_rule({ name = "sakura-calc", match = { class = "^(sakura-calc)$" }, float = true, center = true, rounding = 22 })


-- bring a lost window back to the middle of the screen
hl.bind(mod .. " + G", hl.dsp.window.center(), { desc = "Center window" })

-- keep floating windows reachable: if a window stops with its title bar under the top bar
-- or mostly off-screen, slide it back (does nothing while you are still dragging it)
do
    local lastPos = {}
    local function xy(v) if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
        return (v.x or v[1]), (v.y or v[2]) end
    hl.timer(function()
        local ok, wins = pcall(hl.get_windows, { floating = true })
        if not ok or not wins then return end
        for _, w in ipairs(wins) do
            pcall(function()
                if not w.mapped or (w.fullscreen or 0) ~= 0 then return end
                if (w.title or "") == "" then return end      -- popups, menus, toasts (e.g. Steam notifications)
                if w.xwayland then return end                  -- X11 apps and games place themselves
                local cls = (w.class or ""):lower()
                if cls == "cs2" or cls == "dota2" or cls:match("^steam_app_") or cls == "gamescope" then return end
                local ws = w.workspace
                if not ws or ws.special or not ws.visible then return end
                local m = w.monitor; if not m then return end
                local x, y = xy(w.at); local W, H = xy(w.size)
                if not x or not W then return end
                local key = w.address
                local pos = x .. "," .. y
                local prev = lastPos[key]; lastPos[key] = pos
                if prev ~= pos then return end           -- still moving
                local r      = m.reserved or {}
                local rt     = r.top or 0
                local top    = m.y + (rt > 0 and rt + 2 or 0)   -- below the top bar; the very edge when the bar sits at the bottom (barpos.sh)
                local bottom = m.y + m.height - 90        -- title bar stays above the dock
                local left   = m.x - W + 150
                local right  = m.x + m.width - 150
                local nx = math.max(left, math.min(right, x))
                local ny = math.max(top, math.min(bottom, y))
                if nx ~= x or ny ~= y then
                    hl.dispatch(hl.dsp.window.move({ x = nx, y = ny, window = "address:" .. key }))
                end
            end)
        end
    end, { timeout = 1000, type = "repeat" })
end

hl.layer_rule({ name = "blur-switcher", match = { namespace = "^(switcher)$" }, blur = true, ignore_alpha = 0.2 })



-- MAXIMIZE like Windows: a maximized window simply fills the free area between the bar and the dock.
-- It stays a normal window, so other windows open on top of it and nothing un-maximizes by itself.
do
    local GAP = 8
    __maxSaved = __maxSaved or {}
    local function xy(v) if v == nil then return nil end return (v.x or v[1]), (v.y or v[2]) end
    __prevFs = __prevFs or {}
    __fsExitAt = __fsExitAt or {}
    function __maxToggle(addr, keep)
        local w = hl.get_window("address:" .. addr); if not w then return end
        local sel = "address:" .. addr
        if (w.fullscreen or 0) ~= 0 then
            hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = sel }))
        end
        local g = __maxSaved[addr]
        if g and keep then                      -- back from fullscreen video: stay maximized, just refit
            local m = w.monitor or hl.get_active_monitor()
            local r = m.reserved or {}
            local tg = (r.top or 0) > 0 and GAP or 0
            hl.dispatch(hl.dsp.window.resize({ x = m.width - (r.left or 0) - (r.right or 0) - 2 * GAP, y = m.height - (r.top or 0) - (r.bottom or 0) - GAP - tg, window = sel }))
            hl.dispatch(hl.dsp.window.move({ x = m.x + (r.left or 0) + GAP, y = m.y + (r.top or 0) + tg, window = sel }))
        elseif g then
            __maxSaved[addr] = nil
            hl.dispatch(hl.dsp.window.resize({ x = g[3], y = g[4], window = sel }))
            hl.dispatch(hl.dsp.window.move({ x = g[1], y = g[2], window = sel }))
        else
            local m = w.monitor or hl.get_active_monitor()
            local r = m.reserved or {}
            local x, y = xy(w.at); local W, H = xy(w.size)
            __maxSaved[addr] = { x, y, W, H }
            local ax = m.x + (r.left or 0) + GAP
            local tg = (r.top or 0) > 0 and GAP or 0    -- no bar on top (barpos.sh) → touch the top edge
            local ay = m.y + (r.top or 0) + tg
            local aw = m.width  - (r.left or 0) - (r.right or 0)  - 2 * GAP
            local ah = m.height - (r.top or 0)  - (r.bottom or 0) - GAP - tg
            hl.dispatch(hl.dsp.window.resize({ x = aw, y = ah, window = sel }))   -- resize first (it keeps the center)
            hl.dispatch(hl.dsp.window.move({ x = ax, y = ay, window = sel }))
        end
    end
    -- an app's own "maximize" button: turn Hyprland's maximized state into a fill-the-area resize
    hl.on("window.fullscreen", function(w)
        local ok, fs = pcall(function() return w.fullscreen end)
        if not ok then return end
        local addr = w.address
        local prev = __prevFs[addr] or 0; __prevFs[addr] = fs
        if prev == 2 and fs ~= 2 then __fsExitAt[addr] = os.time() end
        if fs ~= 1 then return end          -- real fullscreen (F11, games, video) is left alone
        -- a browser leaving fullscreen video asks to be maximized again: that's not a click on the maximize button
        local keep = __maxSaved[addr] ~= nil and __fsExitAt[addr] ~= nil and os.time() - __fsExitAt[addr] <= 2
        hl.exec_cmd("hyprctl eval '__maxToggle(\"" .. addr .. "\", " .. tostring(keep) .. ")'")
    end)
    hl.on("window.destroy", function(w)
        local ok, addr = pcall(function() return w.address end)
        if ok and addr then __maxSaved[addr] = nil end
    end)
end
hl.bind(mod .. " + UP", sh("hyprctl eval 'local w = hl.get_active_window(); if w then __maxToggle(w.address) end'"), { desc = "Maximize / restore window" })
hl.bind(mod .. " + DOWN", sh(scripts .. "/minimize.sh hide"), { desc = "Minimize window" })


-- remember the size a window had when it was closed and open it the same size next time
-- (Qt apps on Wayland can't: Dolphin saves "maximized" instead of its size). Only main windows:
-- dialogs of the same app (Properties, copying…) have other titles and keep their own size.
do
    local SIZES = os.getenv("HOME") .. "/.local/state/sakura/winsize"
    local REMEMBER = { ["org.kde.dolphin"] = " - Dolphin$", ["org.kde.kate"] = " - Kate$", ["org.kde.kwrite"] = " - KWrite$" }   -- class = title pattern of the main window
    local sizes = {}
    local f = io.open(SIZES, "r")
    if f then for l in f:lines() do local c, w, h = l:match("^(%S+) (%d+) (%d+)$"); if c then sizes[c] = { tonumber(w), tonumber(h) } end end f:close() end
    local function save()
        os.execute("mkdir -p " .. os.getenv("HOME") .. "/.local/state/sakura")
        local o = io.open(SIZES, "w"); if not o then return end
        for c, s in pairs(sizes) do o:write(c .. " " .. s[1] .. " " .. s[2] .. "\n") end
        o:close()
    end
    hl.on("window.close", function(w)
        local ok, cls, title, fl, fs, sz = pcall(function() return w.class, w.title or "", w.floating, w.fullscreen or 0, w.size end)
        if not ok or not REMEMBER[cls] or not fl or fs ~= 0 or not sz then return end
        if not title:match(REMEMBER[cls]) then return end
        local x, y = sz.x or sz[1], sz.y or sz[2]
        if x and y and x >= 300 and y >= 200 then sizes[cls] = { x, y }; save() end
    end)
    function __sizeRestore(addr)
        local w = hl.get_window("address:" .. addr); if not w then return end
        local s, pat = sizes[w.class], REMEMBER[w.class]
        if not s or not w.floating or (w.fullscreen or 0) ~= 0 or not (w.title or ""):match(pat) then return end
        hl.dispatch(hl.dsp.window.resize({ x = s[1], y = s[2], window = "address:" .. addr }))   -- keeps the center
    end
    hl.on("window.open", function(w)
        local ok, cls = pcall(function() return w.class end)
        if ok and REMEMBER[cls] and sizes[cls] then
            hl.exec_cmd("sleep 0.12; hyprctl eval '__sizeRestore(\"" .. w.address .. "\")'")
        end
    end)
end

-- remember open apps (where they are, how big) so they come back after a restart
hl.timer(function() hl.exec_cmd(scripts .. "/session.py save") end, { timeout = 45000, type = "repeat" })
hl.on("hyprland.shutdown", function() os.execute(scripts .. "/session.py save") end)

-- games (CS2, any Steam game, gamescope) always go truly fullscreen, above the bar and dock
hl.on("window.open", function(w)
    local ok, cls = pcall(function() return (w.class or ""):lower() end)
    if not ok then return end
    if cls == "cs2" or cls == "dota2" or cls == "gamescope" or cls:match("^steam_app_") then
        local addr = w.address
        hl.exec_cmd("sleep 0.5; hyprctl dispatch \"hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'address:" .. addr .. "' })\"")
    end
end)
-- gamescope drops fullscreen when it loses focus (menu, Alt+Tab): put it back when you return to the game
hl.on("window.active", function(w)
    local ok, cls = pcall(function() return (w.class or ""):lower() end)
    if not ok then return end
    if (cls == "cs2" or cls == "dota2" or cls == "gamescope" or cls:match("^steam_app_")) and (w.fullscreen or 0) == 0 then
        hl.exec_cmd("sleep 0.15; hyprctl dispatch \"hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'address:" .. w.address .. "' })\"")
    end
end)

-- ── GAME MODE ─────────────────────────────────────────────────────────
-- games render immediately (tearing allowed = lowest input lag)
-- (no "immediate"/tearing for games: tearing skips the compositor, so Color Control would not apply in games)
-- while a fullscreen game has focus: no blur / animations / shadows / dimming (color correction stays on)
-- switching is instant (no config reload), so nothing flickers or lags when you leave the game
do
    local function isGame(w)
        local ok, cls = pcall(function() return (w.class or ""):lower() end)
        return ok and (cls == "cs2" or cls == "dota2" or cls == "gamescope" or cls:match("^steam_app_") ~= nil or (w.content_type == "game"))
    end
    __gameMode = false
    local saved = nil
    local function get(k) local ok, v = pcall(hl.get_config, k); if ok then return v end end
    local function setGameMode(on)
        if on == __gameMode then return end
        __gameMode = on
        for _, b in ipairs(__altDrag or {}) do pcall(function() b:set_enabled(not on) end) end
        if __asGame then pcall(__asGame, on) end   -- autoscroll off: the middle button belongs to the game
        if on then
            saved = {
                anim = get("animations.enabled"), blur = get("decoration.blur.enabled"), wobble = get("decoration.wobble.enabled"),
                shadow = get("decoration.shadow.enabled"), dim = get("decoration.dim_inactive"),
            }
            hl.config({ animations = { enabled = false },
                        decoration = { blur = { enabled = false }, shadow = { enabled = false }, dim_inactive = false, wobble = { enabled = false } } })
        elseif saved then
            -- applied through hyprctl eval: config changes from inside an event handler back to file values are ignored
            hl.exec_cmd(string.format("hyprctl eval 'hl.config({ animations = { enabled = %s }, decoration = { blur = { enabled = %s }, shadow = { enabled = %s }, dim_inactive = %s, wobble = { enabled = %s } } })'",
                tostring(saved.anim ~= false), tostring(saved.blur ~= false), tostring(saved.shadow ~= false), tostring(saved.dim == true), tostring(saved.wobble == true)))
        end
    end
    local function check()
        local w = hl.get_active_window()
        setGameMode(w ~= nil and isGame(w) and (w.fullscreen or 0) == 2)
    end
    hl.on("window.active", function() check() end)
    hl.on("window.fullscreen", function() check() end)
    hl.on("window.destroy", function() hl.exec_cmd("sleep 0.2; hyprctl eval '__gameCheck()'") end)
    function __gameCheck() check() end
end

-- ── AUTOSCROLL (middle button, like Windows) ─────────────────────────
-- the wheel press/release goes to scripts/autoscroll.py (FIFO); it replays a normal middle click for a quick click,
-- otherwise shows the anchor (quickshell Autoscroll.qml) and scrolls through a virtual mouse.
-- the binds are on only while the daemon runs, and off in fullscreen games.
do
    local run = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    local fifo, pidf = run .. "/sakura-autoscroll.fifo", run .. "/sakura-autoscroll.pid"
    local function alive()
        local t = readall(pidf); local pid = t and t:match("%d+")
        if not pid then return false end
        local c = readall("/proc/" .. pid .. "/cmdline")
        return c ~= nil and c:find("autoscroll", 1, true) ~= nil
    end
    local function send(c)
        if not alive() then return false end
        local f = io.open(fifo, "w"); if not f then return false end
        f:write(c); f:close(); return true
    end
    local main = {
        hl.bind("mouse:274", function() if not send("d") then __asSync() end end, { ignore_mods = true }),
        hl.bind("mouse:274", function() send("u") end, { ignore_mods = true, release = true }),
    }
    -- while autoscroll is latched: any click or Esc stops it (and is eaten, like in Windows)
    local stop = {}
    for _, k in ipairs({ "mouse:272", "mouse:273" }) do
        stop[#stop + 1] = hl.bind(k, function() send("s") end, { ignore_mods = true })
        stop[#stop + 1] = hl.bind(k, function() end, { ignore_mods = true, release = true })
    end
    stop[#stop + 1] = hl.bind("Escape", function() send("s") end, { ignore_mods = true })
    __asPassing, __asSticky = false, false
    function __asSync()
        local on = alive() and not __gameMode and not __asPassing
        for _, b in ipairs(main) do pcall(function() b:set_enabled(on) end) end
        for _, b in ipairs(stop) do pcall(function() b:set_enabled(on and __asSticky) end) end
    end
    function __asPass(p) __asPassing = p; __asSync() end
    function __asSetSticky(v) __asSticky = v; __asSync() end
    function __asGame(on) if on then send("s"); __asSticky = false end; __asSync() end
    __asSync()
end
hl.layer_rule({ name = "blur-autoscroll", match = { namespace = "^(autoscroll)$" }, blur = true, ignore_alpha = 0.3 })

-- Capture (Alt+Z): hotkeys generated by the overlay, instant replay at login
do
    local cb = os.getenv("HOME") .. "/.config/hypr/capture-binds.lua"
    local f = io.open(cb, "r"); if f then f:close(); pcall(dofile, cb) end
end
hl.layer_rule({ name = "blur-capture", match = { namespace = "^(capture)$" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ name = "blur-dashboard", match = { namespace = "^(dashboard|media)$" }, blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ name = "blur-mixer", match = { namespace = "^(mixer)$" }, blur = true, ignore_alpha = 0.2 })


-- ── AERO SNAP: drag a window to an edge / corner ───────────────────────
-- left/right edge = half screen, corners = quarter, top edge = fill. A pink outline shows where it lands.
-- It snaps when you drop it (or hold it at the edge for half a second). Dragging a snapped window away restores its size.
do
    local G = 8            -- gap
    local EDGE = 10        -- how close to the edge the cursor must be
    local CORNER = 90      -- corner zone size
    __snapSaved = __snapSaved or {}
    local st = { armed = false, ticks = 0, dragging = false, addr = nil, last = nil, still = 0, zone = nil, released = false, restored = false }
    local function xy(v) if v == nil then return nil end return (v.x or v[1]), (v.y or v[2]) end
    local function area(m)
        local r = m.reserved or {}
        return m.x + (r.left or 0) + G, m.y + (r.top or 0) + G,
               m.width - (r.left or 0) - (r.right or 0) - 2 * G, m.height - (r.top or 0) - (r.bottom or 0) - 2 * G
    end
    local function zoneRect(m, z)
        local ax, ay, aw, ah = area(m)
        local hw, hh = math.floor((aw - G) / 2), math.floor((ah - G) / 2)
        if z == "left"  then return ax, ay, hw, ah end
        if z == "right" then return ax + aw - hw, ay, hw, ah end
        if z == "top"   then return ax, ay, aw, ah end
        if z == "tl"    then return ax, ay, hw, hh end
        if z == "tr"    then return ax + aw - hw, ay, hw, hh end
        if z == "bl"    then return ax, ay + ah - hh, hw, hh end
        if z == "br"    then return ax + aw - hw, ay + ah - hh, hw, hh end
    end
    local function zoneAt(cx, cy)
        local ok, m = pcall(hl.get_monitor_at, cx, cy); if not ok or not m then return nil end
        local lx, ly, W, H = cx - m.x, cy - m.y, m.width, m.height
        local L, R, T, B = lx <= EDGE, lx >= W - 1 - EDGE, ly <= EDGE, ly >= H - 1 - EDGE
        local nl, nr, nt, nb = lx < CORNER, lx > W - CORNER, ly < CORNER, ly > H - CORNER
        if (L and nt) or (T and nl) then return "tl", m end
        if (R and nt) or (T and nr) then return "tr", m end
        if (L and nb) or (B and nl) then return "bl", m end
        if (R and nb) or (B and nr) then return "br", m end
        if L then return "left", m end
        if R then return "right", m end
        if T then return "top", m end
        return nil, m
    end
    local function preview(z, m)
        if z then
            local x, y, w, h = zoneRect(m, z)
            hl.exec_cmd(string.format("qs ipc call -- snap show %s %d %d %d %d", m.name, x - m.x, y - m.y, w, h))
        else
            hl.exec_cmd("qs ipc call snap hide")
        end
    end
    local function drop(w)
        local z, m = st.zone, st.zoneMon
        preview(nil)
        if not z or not m then return end
        local sel = "address:" .. w.address
        if not __snapSaved[w.address] then local W, H = xy(w.size); __snapSaved[w.address] = { W, H } end
        local x, y, ww, hh = zoneRect(m, z)
        hl.dispatch(hl.dsp.window.resize({ x = ww, y = hh, window = sel }))
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = sel }))
    end
    -- ignore_mods: the same watcher also runs for Super/Alt + drag, not only for title-bar drags
    hl.bind("mouse:272", function()
        st.armed = true; st.ticks = 0; st.released = false; st.dragging = false; st.zone = nil; st.still = 0
        local c = hl.get_cursor_pos(); st.c0x, st.c0y = xy(c)
        local w = hl.get_active_window(); if w then st.w0x, st.w0y = xy(w.at); st.addr = w.address else st.w0x = nil end
        st.last = nil
    end, { non_consuming = true, ignore_mods = true })
    hl.bind("mouse:272", function() st.released = true end, { non_consuming = true, release = true, ignore_mods = true })
    hl.timer(function()
        if not st.armed and not st.dragging then return end
        local w = hl.get_active_window()
        if not w or not w.floating or (w.fullscreen or 0) ~= 0 then st.armed = false; st.dragging = false; return end
        local x, y = xy(w.at); local pos = x .. "," .. y
        if not st.dragging then
            if st.w0x == nil or st.addr ~= w.address then st.w0x, st.w0y = x, y; st.addr = w.address end
            -- a real drag: the window moved more than 10 px AND moved together with the cursor
            local c = hl.get_cursor_pos(); local cx, cy = xy(c)
            local wdx, wdy = x - st.w0x, y - st.w0y
            local cdx, cdy = cx - (st.c0x or cx), cy - (st.c0y or cy)
            -- (the "rubber" animation lets the window trail the cursor, so only the direction has to match)
            local moved = math.abs(wdx) + math.abs(wdy) > 10
            local together = (wdx * cdx + wdy * cdy) > 0
            st.ticks = st.ticks + 1
            if moved and together then
                st.dragging = true; st.still = 0; st.restored = false   -- and handle this tick right away (a quick flick + drop still snaps)
            else
                if st.released or st.ticks > 40 then st.armed = false end   -- just a click (or a click that never moved the window)
                st.last = pos
                return
            end
        end
        -- dragging
        local c = hl.get_cursor_pos(); local cx, cy = xy(c)
        if not st.restored and not __snapSaved[w.address] and __maxSaved and __maxSaved[w.address] then
            local g = __maxSaved[w.address]; __maxSaved[w.address] = nil; __snapSaved[w.address] = { g[3], g[4] }
        end
        if not st.restored and __snapSaved[w.address] then
            -- pulled a snapped window away: give it its old size back under the cursor
            local s = __snapSaved[w.address]; __snapSaved[w.address] = nil; st.restored = true
            local sel = "address:" .. w.address
            local ox, oy = xy(w.at); local ow = xy(w.size)
            local frac = ow > 0 and math.max(0.1, math.min(0.9, (cx - ox) / ow)) or 0.5   -- keep the cursor at the same spot of the title bar
            local m = hl.get_monitor_at(cx, cy) or w.monitor
            local W2, H2 = s[1], s[2]
            if m then
                local ax, ay, aw, ah = area(m)
                -- it was (almost) full screen before: come back at a comfortable size instead
                if W2 >= aw * 0.9 or H2 >= ah * 0.9 then W2, H2 = math.floor(aw * 0.65), math.floor(ah * 0.7) end
                W2, H2 = math.min(W2, aw), math.min(H2, ah)
            end
            local nx = math.floor(cx - W2 * frac)
            local ny = math.floor(cy - 18)
            if m then
                local ax, ay, aw, ah = area(m)
                nx = math.max(ax, math.min(ax + aw - W2, nx))
                ny = math.max(ay, math.min(ay + ah - H2, ny))       -- whole window stays above the dock
            end
            hl.dispatch(hl.dsp.window.resize({ x = W2, y = H2, window = sel }))
            hl.dispatch(hl.dsp.window.move({ x = nx, y = ny, window = sel }))
        end
        local z, m = zoneAt(cx, cy)
        if z ~= st.zone or (m and st.zoneMon and m.name ~= st.zoneMon.name) then st.zone = z; st.zoneMon = m; preview(z, m) end
        if pos ~= st.last then st.still = 0 else st.still = st.still + 50 end
        st.last = pos
        -- drop on release; holding still at an edge for half a second also snaps.
        -- Pausing in the middle of the screen no longer ends the drag (that used to switch snapping off).
        if st.released or (st.zone and st.still >= 500) or st.still >= 8000 then
            if st.zone then drop(w) else preview(nil) end
            st.dragging = false; st.armed = false; st.zone = nil; st.last = nil
        end
    end, { timeout = 50, type = "repeat" })
end
hl.layer_rule({ name = "blur-lyrics", match = { namespace = "^(lyrics)$" }, blur = true, ignore_alpha = 0.02, no_anim = true })

-- lock key sounds: a soft "thock" per key, but ONLY while the screen is locked.
-- The binds use ignore_mods (so Shift+key also sounds), which would otherwise swallow
-- Ctrl+C / Ctrl+V in normal use - so they stay disabled until lock.sh enables them.
__locked = __locked or false
__lockKeys = __lockKeys or {}
do
    local snd = os.getenv("HOME") .. "/.local/share/sounds/sakura/"
    local n = 0
    local function play(file)
        if not __locked then return end
        local off = io.open(os.getenv("HOME") .. "/.config/sakura/sounds-off", "r")
        if off then off:close(); return end
        hl.exec_cmd("pw-play --volume 0.7 " .. snd .. file)
    end
    local keys = {}
    for c in ("abcdefghijklmnopqrstuvwxyz0123456789"):gmatch(".") do keys[#keys + 1] = c end
    for _, k in ipairs({ "space", "minus", "equal", "period", "comma", "slash", "semicolon", "apostrophe", "bracketleft", "bracketright", "grave", "backslash" }) do keys[#keys + 1] = k end
    local opts = { locked = true, non_consuming = true, ignore_mods = true }
    for _, k in ipairs(keys) do
        __lockKeys[#__lockKeys + 1] = hl.bind(k, function() n = n % 3 + 1; play("key" .. n .. ".wav") end, opts)
    end
    __lockKeys[#__lockKeys + 1] = hl.bind("BackSpace", function() play("key-back.wav") end, opts)
    __lockKeys[#__lockKeys + 1] = hl.bind("Return",    function() play("key-enter.wav") end, opts)
    __lockKeys[#__lockKeys + 1] = hl.bind("KP_Enter",  function() play("key-enter.wav") end, opts)

    function __setLockKeys(on)
        __locked = on
        for _, b in ipairs(__lockKeys) do pcall(function() b:set_enabled(on) end) end
    end
    __setLockKeys(false)        -- off while you are using the desktop
end
