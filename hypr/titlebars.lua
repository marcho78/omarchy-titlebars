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

local settings_path = paths.config_home .. "/omarchy/titlebars.json"
local colors_path = paths.state_home .. "/omarchy/current/theme/colors.toml"
local hyprbars_path = paths.home .. "/.local/share/hyprbars/hyprbars.so"
local features_path = paths.home .. "/.local/share/hyprbars/features"
local minimized_workspace = "special:minimized"

-- Settings -------------------------------------------------------------------

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local text = file:read("a")
  file:close()
  return text
end

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

-- defaults.json holds the default look; schema.json the allowed choices and ranges.
local defaults, defaults_error = decode_json(read_file(plugin_dir .. "/defaults.json") or "")
local schema, schema_error = decode_json(read_file(plugin_dir .. "/schema.json") or "")
if type(defaults) ~= "table" or type(schema) ~= "table" then
  local problem = type(defaults) ~= "table" and "defaults.json (" .. tostring(defaults_error) or "schema.json (" .. tostring(schema_error)
  hl.notification.create({ text = "Title Bars: can't read " .. problem .. ")", duration = 10000, icon = "error" })
  return
end

local user = {}
local user_text = read_file(settings_path)
if user_text and user_text:find("%S") then
  local decoded, decode_error = decode_json(user_text)
  if type(decoded) == "table" then
    user = decoded
  else
    problems[#problems + 1] = "titlebars.json is not valid JSON (" .. tostring(decode_error) .. "), using the defaults"
  end
end

local choices = {}
for key, list in pairs(schema.choices or {}) do
  choices[key] = {}
  for _, choice in ipairs(list) do
    choices[key][choice] = true
  end
end
local ranges = schema.ranges or {}

local settings = {}
for key, default in pairs(defaults) do
  local value = user[key]

  if value == nil then
    settings[key] = default
  elseif type(value) ~= type(default) then
    problems[#problems + 1] = key .. " should be a " .. type(default)
    settings[key] = default
  elseif key == "colors" then
    settings.colors = {}
    for role, default_color in pairs(default) do
      settings.colors[role] = type(value[role]) == "string" and value[role] or default_color
    end
  elseif key == "noBarApps" then
    settings.noBarApps = {}
    for _, app in ipairs(value) do
      if type(app) == "string" and app ~= "" then
        settings.noBarApps[#settings.noBarApps + 1] = app
      end
    end
  elseif choices[key] and not choices[key][value] then
    problems[#problems + 1] = key .. ' can\'t be "' .. tostring(value) .. '"'
    settings[key] = default
  elseif ranges[key] then
    local low, high = ranges[key][1], ranges[key][2]
    settings[key] = math.floor(math.max(low, math.min(high, value)) + 0.5)
  else
    settings[key] = value
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

for line in (read_file(colors_path) or ""):gmatch("[^\n]+") do
  local key, hex = line:match('^%s*([%w_]+)%s*=%s*"#(%x%x%x%x%x%x)"')
  if key then
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
  return "hyprctl dispatch " .. o.shell_quote(expression)
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
local features = read_file(features_path) or ""
if settings.settingsButton and features:find("opposite", 1, true) then
  hyprbars.add_button({
    bg_color = transparent,
    fg_color = colors.titleInactive,
    size = math.floor(settings.buttonSize * 1.5 + 0.5),
    icon = "󰒓",
    action = "omarchy-shell shell summon marcho78.titlebars '{}'",
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
