-- Title Bars: the Hyprland half of the marcho78.titlebars Omarchy plugin.
--
-- Draws window title bars with minimize / maximize / close buttons through the
-- hyprbars plugin (https://github.com/hyprwm/hyprland-plugins). The look comes
-- from this plugin's defaults.json with ~/.config/omarchy/titlebars.json on
-- top; the Title Bars panel and the `titlebars` command edit that file and
-- reload Hyprland.
--
-- ~/.config/hypr/titlebars.lua (written by `titlebars setup`) runs this file
-- with the plugin directory as its argument.

local plugin_dir = ...
local paths = require("default.hypr.paths")

local hyprbars_path = paths.home .. "/.local/share/hyprbars/hyprbars.so"
local max_state_bytes = 256 * 1024
local minimized_workspace = "special:minimized"

-- Settings -------------------------------------------------------------------

-- A small JSON reader for the settings files. It reports problems as a second
-- return value instead of raising, so a bad file never breaks Hyprland's config.
local function decode_json(text)
  local pos = 1
  local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

  local function fail(message)
    error({ message = message .. " at character " .. pos }, 0)
  end

  local function skip_whitespace()
    pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
  end

  local function read_hex4(at)
    local hex = text:sub(at, at + 3)
    if not hex:match("^%x%x%x%x$") then
      fail("invalid \\u escape")
    end
    return tonumber(hex, 16)
  end

  local function read_string()
    local parts = {}
    pos = pos + 1
    while true do
      local special = text:find('["\\]', pos)
      if not special then
        fail("unterminated string")
      end

      parts[#parts + 1] = text:sub(pos, special - 1)
      pos = special
      if text:sub(pos, pos) == '"' then
        pos = pos + 1
        return table.concat(parts)
      end

      local escape = text:sub(pos + 1, pos + 1)
      if escape == "u" then
        local code = read_hex4(pos + 2)
        pos = pos + 6
        if code >= 0xD800 and code <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then
          local low = read_hex4(pos + 2)
          if low >= 0xDC00 and low <= 0xDFFF then
            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
            pos = pos + 6
          end
        end
        parts[#parts + 1] = utf8.char(code)
      elseif escapes[escape] then
        parts[#parts + 1] = escapes[escape]
        pos = pos + 2
      else
        fail("invalid escape")
      end
    end
  end

  local read_value

  local function read_object()
    local object = {}
    pos = pos + 1
    skip_whitespace()
    if text:sub(pos, pos) == "}" then
      pos = pos + 1
      return object
    end

    while true do
      if text:sub(pos, pos) ~= '"' then
        fail("expected a key")
      end
      local key = read_string()
      skip_whitespace()
      if text:sub(pos, pos) ~= ":" then
        fail("expected ':'")
      end
      pos = pos + 1
      object[key] = read_value()
      skip_whitespace()

      local separator = text:sub(pos, pos)
      pos = pos + 1
      if separator == "}" then
        return object
      elseif separator ~= "," then
        fail("expected ',' or '}'")
      end
      skip_whitespace()
    end
  end

  local function read_array()
    local array = {}
    pos = pos + 1
    skip_whitespace()
    if text:sub(pos, pos) == "]" then
      pos = pos + 1
      return array
    end

    while true do
      array[#array + 1] = read_value()
      skip_whitespace()

      local separator = text:sub(pos, pos)
      pos = pos + 1
      if separator == "]" then
        return array
      elseif separator ~= "," then
        fail("expected ',' or ']'")
      end
    end
  end

  local literals = { ["true"] = true, ["false"] = false }

  function read_value()
    skip_whitespace()
    local char = text:sub(pos, pos)
    if char == "{" then
      return read_object()
    elseif char == "[" then
      return read_array()
    elseif char == '"' then
      return read_string()
    end

    for word, value in pairs(literals) do
      if text:sub(pos, pos + #word - 1) == word then
        pos = pos + #word
        return value
      end
    end
    if text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    end

    local number = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if number and tonumber(number) then
      pos = pos + #number
      return tonumber(number)
    end

    fail("unexpected input")
  end

  local ok, result = pcall(function()
    local value = read_value()
    skip_whitespace()
    if pos <= #text then
      fail("unexpected trailing input")
    end
    return value
  end)

  if ok then
    return result
  end
  return nil, type(result) == "table" and result.message or tostring(result)
end

local problems = {}

-- Everything under $HOME is read by bin/titlebars, which opens files without
-- following symlinks, refuses FIFOs and oversized files, and validates the
-- settings. Plain Lua can't do that, and a hung read here would stall the
-- compositor, so the call has a hard deadline and a byte cap.
local function load_state()
  local command = "/usr/bin/timeout -k 1 3 /usr/bin/python3 -I "
    .. o.shell_quote(plugin_dir .. "/bin/titlebars")
    .. " hypr 2>/dev/null"
  local handle = io.popen(command, "r")
  if not handle then
    return nil, "couldn't run bin/titlebars"
  end
  local output = handle:read(max_state_bytes + 1) or ""
  handle:close()
  if #output > max_state_bytes then
    return nil, "bin/titlebars printed too much"
  end
  return decode_json(output)
end

local state, state_error = load_state()
if type(state) ~= "table" or type(state.defaults) ~= "table" or type(state.settings) ~= "table" then
  hl.notification.create({ text = "Title Bars: can't load settings (" .. tostring(state_error) .. ")", duration = 10000, icon = "error" })
  return
end

local defaults = state.defaults
for _, problem in ipairs(type(state.problems) == "table" and state.problems or {}) do
  problems[#problems + 1] = tostring(problem)
end

-- bin/titlebars already validated these; keep Lua honest about their types.
local settings = {}
for key, default in pairs(defaults) do
  local value = state.settings[key]
  if type(value) == type(default) then
    settings[key] = value
  else
    settings[key] = default
  end
end

-- Colors ---------------------------------------------------------------------

-- Theme roles (colors.toml keys) as rrggbb, with Tokyo Night for anything missing.
local palette = {
  background = "1a1b26",
  darker_background = "0e0e14",
  foreground = "a9b1d6",
  dark_foreground = "565f89",
  muted = "414868",
  red = "f7768e",
  yellow = "e0af68",
  green = "9ece6a",
}

for key, hex in pairs(type(state.palette) == "table" and state.palette or {}) do
  if type(key) == "string" and type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") then
    palette[key] = hex:lower()
  end
end

-- A color is a theme role ("red", "background", ...) or "#rrggbb" / "#rrggbbaa".
local function resolve_color(value, fallback_role)
  local hex
  if type(value) == "string" then
    hex = value:match("^#(%x%x%x%x%x%x)$") or value:match("^#(%x%x%x%x%x%x%x%x)$") or palette[value]
  end
  if not hex then
    problems[#problems + 1] = 'unknown color "' .. tostring(value) .. '"'
    hex = palette[fallback_role]
  end
  return (#hex == 8 and "rgba(" or "rgb(") .. hex .. ")"
end

local colors = {}
local chosen = settings.followTheme and defaults.colors or settings.colors
for role, default_role in pairs(defaults.colors) do
  colors[role] = resolve_color(chosen[role], default_role)
end

-- Minimize -------------------------------------------------------------------

-- Hyprland has no minimized state, so minimized windows wait on a hidden
-- special workspace until they are activated again.
local function is_minimized(window)
  return window ~= nil and window.workspace ~= nil and window.workspace.name == minimized_workspace
end

local function restore(window)
  local monitor = window.monitor or hl.get_active_monitor()
  hl.dispatch(hl.dsp.window.move({ monitor = monitor.name, window = window }))
end

-- Clicking a minimized app in a dock, Alt+Tab, or omarchy-launch-or-focus all
-- activate the window: bring it back to the current workspace when they do.
hl.on("window.active", function(window)
  if is_minimized(window) then
    -- Defer until Hyprland has finished handling the focus change.
    hl.timer(function()
      if is_minimized(window) then
        restore(window)
      end
    end, { timeout = 1, type = "oneshot" })
  end
end)

if settings.shortcuts then
  o.bind("SUPER + M", "Minimize window", hl.dsp.window.move({ workspace = minimized_workspace, follow = false }))
  o.bind("SUPER + ALT + M", "Restore minimized window", function()
    local latest
    for _, window in ipairs(hl.get_windows()) do
      if is_minimized(window) and (latest == nil or window.focus_history_id < latest.focus_history_id) then
        latest = window
      end
    end

    if latest then
      restore(latest)
    end
  end)
end

-- The settings panel floats like Omarchy's other utility windows, and stays
-- opaque so the windows behind it don't show through the controls.
o.window({ class = "^org\\.quickshell$", title = "^Title Bars$" }, { float = true, center = true, tag = "-default-opacity", opacity = "1 1" })

-- Title bars -----------------------------------------------------------------

local plugin_file = io.open(hyprbars_path, "r")
if not plugin_file then
  return
end
plugin_file:close()

hl.plugin.load(hyprbars_path)

-- Hyprland loads plugins after the config has run, then reloads it, so the
-- hyprbars API only exists on that second pass.
local hyprbars = hl.plugin.hyprbars
if not hyprbars then
  return
end

local function dispatch(expression)
  return "/usr/bin/hyprctl dispatch " .. o.shell_quote(expression)
end

local actions = {
  minimize = dispatch('hl.dsp.window.move({ workspace = "' .. minimized_workspace .. '", follow = false })'),
  maximize = dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })'),
  close = dispatch("hl.dsp.window.close()"),
}

-- Keep in sync with STYLES in Styles.js, which draws the panel's preview.
-- fill: "role" colors each button, "mono" uses one neutral color, "none" shows
-- only the glyph. scale enlarges glyph-only buttons so the glyphs stay legible.
local styles = {
  dots = { fill = "role", hover = true, glyphs = { minimize = "−", maximize = "+", close = "×" } },
  labeled = { fill = "role", hover = false, glyphs = { minimize = "−", maximize = "+", close = "×" } },
  mono = { fill = "mono", hover = true, glyphs = { minimize = "−", maximize = "+", close = "×" } },
  symbols = { fill = "none", hover = false, scale = 1.5, glyphs = { minimize = "−", maximize = "□", close = "×" } },
  nerd = { fill = "none", hover = false, scale = 1.5, glyphs = { minimize = "󰖰", maximize = "󰖯", close = "󰅖" } },
}
local style = styles[settings.style]
local transparent = "rgba(00000000)"

local function button_colors(name)
  if style.fill == "role" then
    return colors[name], colors.icon
  elseif style.fill == "mono" then
    return colors.titleInactive, colors.bar
  end
  return transparent, colors.title
end

local double_click = { maximize = actions.maximize, minimize = actions.minimize, none = "" }

hl.config({
  plugin = {
    hyprbars = {
      enabled = settings.enabled,
      bar_height = settings.barHeight,
      bar_color = colors.bar,
      col = { text = colors.title },
      bar_title_enabled = settings.title,
      bar_text_font = settings.titleFont ~= "" and settings.titleFont or "monospace",
      bar_text_size = settings.titleSize,
      bar_text_weight = settings.titleWeight,
      bar_text_align = settings.titleAlign,
      bar_buttons_alignment = settings.buttons,
      bar_padding = settings.barPadding,
      bar_button_padding = settings.buttonSpacing,
      -- Let the window border wrap the title bar too.
      bar_precedence_over_border = settings.borderAroundBar,
      icon_on_hover = style.hover,
      inactive_button_color = style.fill == "none" and transparent or colors.inactiveButton,
      on_double_click = double_click[settings.doubleClick],
    },
  },
})

local order = settings.order == "mac" and { "close", "minimize", "maximize" } or { "minimize", "maximize", "close" }
local shown = { minimize = settings.showMinimize, maximize = settings.showMaximize, close = settings.showClose }
local size = math.floor(settings.buttonSize * (style.scale or 1) + 0.5)

-- hyprbars puts the first button at the bar's edge, so a right-aligned row is
-- added in reverse to read left to right as configured.
local first, last, step = 1, #order, 1
if settings.buttons == "right" then
  first, last, step = #order, 1, -1
end

for i = first, last, step do
  local name = order[i]
  if shown[name] then
    local bg, fg = button_colors(name)
    hyprbars.add_button({ bg_color = bg, fg_color = fg, size = size, icon = style.glyphs[name], action = actions[name] })
  end
end

-- A settings gear on the far side of the bar. Needs our hyprbars patch, which
-- `titlebars build` records in the features file when it applies.
if settings.settingsButton and state.gear == true then
  hyprbars.add_button({
    bg_color = transparent,
    fg_color = colors.titleInactive,
    size = math.floor(settings.buttonSize * 1.5 + 0.5),
    icon = "󰒓",
    action = "/usr/bin/omarchy-shell shell summon marcho78.titlebars '{}'",
    opposite = true,
    icon_always = true,
  })
end

-- Dim the title of unfocused windows to match their muted buttons.
if settings.dimInactive then
  o.window({ focus = false }, { ["hyprbars:title_color"] = colors.titleInactive })
end

-- Overlays that shouldn't get a title bar, plus the user's own list.
o.window({ tag = "pip" }, { ["hyprbars:no_bar"] = true })
o.window("^WebcamOverlay-(small|medium|large)$", { ["hyprbars:no_bar"] = true })
o.window({ class = "^Hermes$", title = "^Hermes HUD$" }, { ["hyprbars:no_bar"] = true })
for _, app in ipairs(settings.noBarApps) do
  o.window(app, { ["hyprbars:no_bar"] = true })
end

if #problems > 0 then
  hl.notification.create({ text = "Title Bars: " .. table.concat(problems, "; "), duration = 8000, icon = "warning" })
end
