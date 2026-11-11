-- ==============================================================================
-- CARBON SHELL — HYPRLAND MASTER CONFIGURATION (LUA)
-- Location: ~/.config/hypr/hyprland.lua
-- Hyprland 0.57+ Native Lua Configuration
-- Dynamically integrates with Carbon Settings App (carbon-config-editor)
-- ==============================================================================

local home = os.getenv("HOME") or "/home/zily"
local carbon_dir = os.getenv("CARBON_CONFIG_DIR") or (home .. "/.config/carbon")

--------------------------------------------------------------------------------
-- 1. ENVIRONMENT VARIABLES
--------------------------------------------------------------------------------
hl.env("CARBON_CONFIG_DIR", carbon_dir)
hl.env("PATH", home .. "/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl")
hl.env("GST_PLUGIN_PATH", home .. "/.local/lib/gstreamer-1.0")
hl.env("LIBVA_DRIVERS_PATH", home .. "/.local/lib/dri")
hl.env("LD_LIBRARY_PATH", home .. "/.local/lib")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "capitaine-cursors")
hl.env("LIBVA_DRIVER_NAME", "i965")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_DESKTOP_PORTAL", "hyprland")

--------------------------------------------------------------------------------
-- 2. CONFIG PARSERS (READ LIVE FROM CARBON SETTINGS APP)
--------------------------------------------------------------------------------
local function parse_conf(path)
    local cfg = {}
    local f = io.open(path, "r")
    if not f then return cfg end
    for raw in f:lines() do
        local line = raw:match("^%s*(.-)%s*$")
        if line and line ~= "" and not line:match("^[#$]") and not line:match("[{}]") then
            local k, v = line:match("^([%w_%.%-]+)%s*=%s*(.+)$")
            if k and v then
                v = v:match("^(.-)%s*$")
                k = k:gsub("%-", "_")
                if v == "true" or v == "yes" or v == "on" then
                    cfg[k] = true
                elseif v == "false" or v == "no" or v == "off" then
                    cfg[k] = false
                elseif tonumber(v) then
                    cfg[k] = tonumber(v)
                else
                    cfg[k] = v
                end
            end
        end
    end
    f:close()
    return cfg
end

local function load_colors(path)
    local colors = {}
    local f = io.open(path, "r")
    if not f then return colors end
    for line in f:lines() do
        local k, v = line:match("^%$([%w_]+)%s*=%s*(.+)$")
        if k and v then
            colors[k] = v:gsub("%s+$", "")
        end
    end
    f:close()
    return colors
end

local function load_json(path)
    local data = {}
    local f = io.open(path, "r")
    if not f then return data end
    local content = f:read("*a")
    f:close()
    for k, v in content:gmatch('"([%w_]+)"%s*:%s*([^,\n}%]]+)') do
        v = v:match("^%s*(.-)%s*$")
        if v == "true" then
            data[k] = true
        elseif v == "false" then
            data[k] = false
        elseif tonumber(v) then
            data[k] = tonumber(v)
        elseif v:match('^"(.*)"$') then
            data[k] = v:match('^"(.*)"$')
        end
    end
    return data
end

local c = load_colors(carbon_dir .. "/colors.conf")
local col_active_border = c.outline or "rgba(899296ff)"
local col_inactive_border = c.outline_variant or "rgba(40484bff)"

local lnf = parse_conf(carbon_dir .. "/looknfeel.conf")
local inp = parse_conf(carbon_dir .. "/input.conf")
local mouse_json = load_json(carbon_dir .. "/carbon-mouse-touchpad.json")
local kb_json = load_json(carbon_dir .. "/carbon-keyboard.json")
local tp_override = parse_conf(home .. "/.config/hypr/touchpad.conf")

--------------------------------------------------------------------------------
-- 3. MONITORS & DISPLAYS (FROM carbon/monitors.conf)
--------------------------------------------------------------------------------
local function load_monitors(path)
    local f = io.open(path, "r")
    local count = 0
    if f then
        for raw in f:lines() do
            local line = raw:match("^%s*(.-)%s*$")
            if line and line:match("^monitor%s*=") then
                local spec = line:match("^monitor%s*=%s*(.+)$")
                if spec then
                    local parts = {}
                    for p in spec:gmatch("[^,]+") do
                        table.insert(parts, p:match("^%s*(.-)%s*$"))
                    end
                    if #parts >= 4 then
                        local mon = {
                            output = parts[1],
                            mode = parts[2],
                            position = parts[3],
                            scale = tonumber(parts[4]) or 1,
                        }
                        for i = 5, #parts, 2 do
                            if parts[i] == "transform" and parts[i+1] then
                                mon.transform = tonumber(parts[i+1]) or 0
                            elseif parts[i] == "vrr" and parts[i+1] then
                                mon.vrr = tonumber(parts[i+1]) or 0
                            end
                        end
                        hl.monitor(mon)
                        count = count + 1
                    end
                end
            end
        end
        f:close()
    end
    if count == 0 then
        hl.monitor({ output = "eDP-1", mode = "1366x768@59", position = "auto", scale = 1 })
        hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
    end
end

load_monitors(carbon_dir .. "/monitors.conf")

--------------------------------------------------------------------------------
-- 4. INPUT & TOUCHPAD CONFIGURATION (FROM carbon/input.conf)
--------------------------------------------------------------------------------
hl.config({
    input = {
        kb_layout          = kb_json.kb_layout or inp.kb_layout or "us",
        kb_variant         = kb_json.kb_variant or inp.kb_variant or "",
        kb_model           = kb_json.kb_model or inp.kb_model or "",
        kb_options         = inp.kb_options or "",
        repeat_rate        = kb_json.repeat_rate or inp.repeat_rate or 25,
        repeat_delay       = kb_json.repeat_delay or inp.repeat_delay or 600,
        numlock_by_default = (kb_json.numlock_by_default ~= nil) and kb_json.numlock_by_default or false,
        sensitivity        = mouse_json.sensitivity or inp.sensitivity or 0.0,
        accel_profile      = mouse_json.accel_profile or inp.accel_profile or "flat",
        left_handed        = (mouse_json.left_handed ~= nil) and mouse_json.left_handed or false,
        follow_mouse       = mouse_json.follow_mouse or inp.follow_mouse or 1,
        natural_scroll     = (mouse_json.natural_scroll_mouse == true),
        touchpad = {
            disable_while_typing = (mouse_json.disable_while_typing ~= nil) and mouse_json.disable_while_typing or true,
            natural_scroll       = (mouse_json.natural_scroll_touchpad == true),
            tap_to_click         = (mouse_json.tap_to_click ~= nil) and mouse_json.tap_to_click or true,
            tap_and_drag         = (mouse_json.tap_and_drag ~= nil) and mouse_json.tap_and_drag or true,
            clickfinger_behavior = (mouse_json.clickfinger_behavior ~= nil) and mouse_json.clickfinger_behavior or false,
            scroll_factor        = mouse_json.scroll_factor or 1.00,
        },
    },

    cursor = {
        no_warps = true,
    },

    general = {
        gaps_in          = lnf.gaps_in or 6,
        gaps_out         = lnf.gaps_out or 6,
        border_size      = lnf.border_size or 1,
        col = {
            active_border   = col_active_border,
            inactive_border = col_inactive_border,
        },
        resize_on_border = lnf.resize_on_border or false,
        allow_tearing    = lnf.allow_tearing or false,
        layout           = lnf.layout or "dwindle",
        snap = {
            enabled = true,
        },
    },

    decoration = {
        rounding         = lnf.rounding or 0,
        rounding_power   = lnf.rounding_power or 2,
        active_opacity   = lnf.active_opacity or 0.88,
        inactive_opacity = lnf.inactive_opacity or 0.78,
        dim_inactive     = false,
        dim_special      = 0.3,

        shadow = {
            enabled      = (lnf.shadow_enabled ~= nil) and lnf.shadow_enabled or false,
            range        = lnf.shadow_range or 15,
            render_power = lnf.shadow_render_power or 3,
            color        = "rgba(1a1a1aee)",
        },

        blur = {
            enabled           = (lnf.blur_enabled ~= nil) and lnf.blur_enabled or true,
            size              = lnf.blur_size or 5,
            passes            = lnf.blur_passes or 2,
            ignore_opacity    = (lnf.blur_ignore_opacity ~= nil) and lnf.blur_ignore_opacity or true,
            new_optimizations = (lnf.blur_new_optimizations ~= nil) and lnf.blur_new_optimizations or true,
            special           = lnf.blur_special or false,
            popups            = (lnf.blur_popups ~= nil) and lnf.blur_popups or true,
            xray              = (lnf.blur_xray ~= nil) and lnf.blur_xray or true,
            vibrancy          = lnf.blur_vibrancy or 0.1696,
        },
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
})

-- Per-device overrides (Internal touchpad disabled when external mouse preferred)
if tp_override.name then
    hl.device({
        name    = tp_override.name,
        enabled = (tp_override.enabled ~= nil) and tp_override.enabled or false,
    })
else
    hl.device({
        name    = "dll07d0:01-044e:120b",
        enabled = false,
    })
end

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

--------------------------------------------------------------------------------
-- 5. ANIMATIONS & CURVES
--------------------------------------------------------------------------------
hl.config({
    animations = {
        enabled = true,
    },
})

hl.curve("myBezier",   { type = "bezier", points = { {0.05, 0.9},  {0.1,  1.05} } })
hl.curve("been",       { type = "bezier", points = { {0.24, 0.9},  {0.25, 0.91} } })
hl.curve("been2",      { type = "bezier", points = { {0.0,  0.94}, {0.5,  0.99} } })
hl.curve("menu_decel", { type = "bezier", points = { {0.1,  1.0},  {0.0,  1.0}  } })
hl.curve("linear",     { type = "bezier", points = { {0.0,  0.0},  {1.0,  1.0}  } })
hl.curve("wind",       { type = "bezier", points = { {0.05, 0.9},  {0.1,  1.05} } })
hl.curve("winIn",      { type = "bezier", points = { {0.1,  1.1},  {0.1,  1.1}  } })
hl.curve("winOut",     { type = "bezier", points = { {0.3, -0.3},  {0.0,  1.0}  } })
hl.curve("slow",       { type = "bezier", points = { {0.0,  0.85}, {0.3,  1.0}  } })
hl.curve("overshot",   { type = "bezier", points = { {0.7,  0.6},  {0.1,  1.1}  } })
hl.curve("bounce",     { type = "bezier", points = { {1.1,  1.6},  {0.1,  0.85} } })
hl.curve("sligshot",   { type = "bezier", points = { {1.0, -1.0},  {0.15, 1.25} } })

hl.animation({ leaf = "windowsIn",   enabled = true, speed = 4, bezier = "slow",     style = "popin" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 5, bezier = "been",     style = "popin 70%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "wind",     style = "slide" })
hl.animation({ leaf = "border",      enabled = true, speed = 1, bezier = "linear" })
hl.animation({ leaf = "fade",        enabled = true, speed = 4, bezier = "overshot" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 4, bezier = "wind" })
hl.animation({ leaf = "windows",     enabled = true, speed = 4, bezier = "bounce",   style = "popin" })

--------------------------------------------------------------------------------
-- 6. WINDOW RULES & LAYER RULES (CARBON SHELL BLUR & POSITIONING)
--------------------------------------------------------------------------------
local carbon_layers = {
    "carbon-.*",
    "carbon-bar-minimal",
    "carbon-bar-pill-full",
    "carbon-bar-pill-vert",
    "carbon-bar-notch",
    "carbon-bar-notch-center",
    "carbon-controls",
    "carbon-spotlight",
    "carbon-launcher",
    "carbon-music",
    "carbon-music-small",
    "carbon-overview",
    "carbon-wallpaper-picker",
    "carbon-mixer",
    "carbon-brightness",
    "carbon-battery",
    "carbon-wifi",
    "carbon-bluetooth",
    "carbon-tray",
    "carbon-calendar",
    "carbon-center-dashboard",
    "carbon-power",
    "carbon-sensor",
    "carbon-osd",
    "quickshell",
    "tide-island",
}

for _, ns in ipairs(carbon_layers) do
    hl.layer_rule({ name = "blur-" .. ns, match = { namespace = ns }, blur = true, ignore_alpha = 0.2 })
end
hl.layer_rule({ name = "carbon-noanim", match = { namespace = "carbon-.*" }, no_anim = true })
hl.layer_rule({ name = "blur-logout-dialog", match = { namespace = "logout_dialog" }, blur = true })

-- Opacity
hl.window_rule({ match = { class = "org.gnome.Nautilus" }, opacity = "0.85 override 0.85 override" })
hl.window_rule({ match = { class = "kitty" },              opacity = "0.88 override 0.82 override" })
hl.window_rule({ match = { class = "gedit" },              opacity = "0.90 override 0.84 override" })
hl.window_rule({ match = { class = "mousepad" },           opacity = "0.90 override 0.84 override" })
hl.window_rule({ match = { class = "org.gnome.TextEditor" }, opacity = "0.90 override 0.84 override" })
hl.window_rule({ match = { class = "discord" },            opacity = "0.90 override 0.80 override 1.0 override" })
hl.window_rule({ match = { class = "vesktop" },            opacity = "0.90 override 0.80 override 1.0 override" })
hl.window_rule({ match = { class = "Spotify" },            opacity = "0.85 override 0.70 override 1.0 override" })

-- Dialogs & Floating Windows
hl.window_rule({ match = { class = "org.pulseaudio.pavucontrol" }, float = true, size = "50% 60%" })
hl.window_rule({ match = { class = "pwvucontrol" },                float = true, size = "50% 60%" })
hl.window_rule({ match = { title = "Save As" },                    float = true, size = "50% 60%", center = true })
hl.window_rule({ match = { title = "Save a File" },                float = true, size = "50% 60%", center = true })
hl.window_rule({ match = { title = "Pick Files" },                 float = true, size = "50% 60%", center = true })
hl.window_rule({ match = { initial_title = "Open Files" },         float = true, size = "70% 60%" })

-- Carbon Config Editor GUI floating window
hl.window_rule({ match = { class = "carbon-config-editor.*" }, float = true, size = "920 680", center = true })
hl.window_rule({ match = { class = "org.carbon.configeditor" }, float = true, size = "920 680", center = true })
hl.window_rule({ match = { title = "Settings" },                float = true, size = "920 680", center = true })

-- Maximize suppression & XWayland drag fixes
hl.window_rule({ name = "suppress-maximize",  match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ name = "fix-xwayland-drags", match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false }, no_focus = true })

-- Dynamic Blur & Opacity Exceptions (FROM carbon/blur-exceptions.conf)
local function load_blur_exceptions(path)
    local f = io.open(path, "r")
    if not f then return end
    local rules_by_class = {}
    for raw in f:lines() do
        local line = raw:match("^%s*(.-)%s*$")
        if line and line:match("^windowrule%s*=") then
            local rule_type, pattern = line:match("^windowrule%s*=%s*(.-)%s*,%s*match:class%s*(.+)$")
            if rule_type and pattern then
                rules_by_class[pattern] = rules_by_class[pattern] or {}
                if rule_type:match("^no_blur") then
                    rules_by_class[pattern].no_blur = true
                elseif rule_type:match("^opacity%s+(.+)$") then
                    rules_by_class[pattern].opacity = rule_type:match("^opacity%s+(.+)$")
                end
            end
        end
    end
    f:close()
    for pattern, spec in pairs(rules_by_class) do
        hl.window_rule({
            match = { class = pattern },
            no_blur = spec.no_blur or false,
            opacity = spec.opacity,
        })
    end
end

load_blur_exceptions(carbon_dir .. "/blur-exceptions.conf")

--------------------------------------------------------------------------------
-- 7. AUTOSTART DAEMONS & USER PROCESSES (FROM carbon/autostart.conf)
--------------------------------------------------------------------------------
local function get_autostart_commands(path)
    local cmds = {}
    local f = io.open(path, "r")
    if not f then return cmds end
    for raw in f:lines() do
        local line = raw:match("^%s*(.-)%s*$")
        if line and line:match("^exec%-once") then
            local cmd = line:match("^exec%-once%s*=%s*(.+)$")
            if cmd and cmd ~= "" then
                table.insert(cmds, cmd)
            end
        end
    end
    f:close()
    return cmds
end

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("sh " .. carbon_dir .. "/scripts/portal.sh")
    hl.exec_cmd("sh " .. carbon_dir .. "/scripts/carbon-audio-init.sh")
    hl.exec_cmd("systemctl --user start carbon-awww.service")
    hl.exec_cmd("systemctl --user start carbon-quickshell.service")
    hl.exec_cmd("bash -c 'wl-paste --watch cliphist store'")
    hl.exec_cmd("bash -c 'wl-paste --type image --watch cliphist store'")
    hl.exec_cmd("hypridle -c " .. carbon_dir .. "/hypridle.conf")
    hl.exec_cmd("sh " .. carbon_dir .. "/scripts/carbon-snap-top.sh")
    hl.exec_cmd(home .. "/.config/hypr/scripts/carbon-night.sh restore")

    -- Dynamic user startup apps
    local user_apps = get_autostart_commands(carbon_dir .. "/autostart.conf")
    for _, app_cmd in ipairs(user_apps) do
        hl.exec_cmd(app_cmd)
    end
end)

hl.on("config.reloaded", function()
    hl.exec_cmd(home .. "/.config/hypr/scripts/carbon-night.sh restore")
end)

--------------------------------------------------------------------------------
-- 8. LOAD KEYBINDINGS
--------------------------------------------------------------------------------
dofile(home .. "/.config/hypr/keybinds.lua")
pcall(dofile, home .. "/.config/hypr/current-mode-keybinds.lua")
