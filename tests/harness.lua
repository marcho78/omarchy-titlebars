-- Loads hypr/titlebars.lua against a fake Hyprland API in a throwaway HOME.
-- Shared by hypr.test.lua and dump.lua.

local plugin_dir = arg[0]:match("^(.*)/tests/[^/]+$") or "."

local home = io.popen("mktemp -d"):read("l")
os.execute("mkdir -p '" .. home .. "/.config/omarchy' '" .. home .. "/.local/state/omarchy/current/theme' '" .. home .. "/.local/share/hyprbars'")

local function write(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local harness = {
  plugin_dir = plugin_dir,
  settings_path = home .. "/.config/omarchy/titlebars.json",
  plugin_path = home .. "/.local/share/hyprbars/hyprbars.so",
  features_path = home .. "/.local/share/hyprbars/features",
  colors_path = home .. "/.local/state/omarchy/current/theme/colors.toml",
}

harness.colors = [[
accent = "#7aa2f7"
background = "#1a1b26"
darker_background = "#0e0e14"
foreground = "#a9b1d6"
dark_foreground = "#565f89"
muted = "#414868"
red = "#f7768e"
yellow = "#e0af68"
green = "#9ece6a"
blue = "#7aa2f7"
]]
write(harness.colors_path, harness.colors)

package.loaded["default.hypr.paths"] = {
  home = home,
  config_home = home .. "/.config",
  state_home = home .. "/.local/state",
}

-- Loads the module once with the given settings file contents (nil = no file)
-- and returns everything it asked Hyprland to do.
function harness.run(settings_text, options)
  options = options or {}
  os.remove(harness.settings_path)
  if settings_text then
    write(harness.settings_path, settings_text)
  end
  if options.features then
    write(harness.features_path, options.features)
  else
    os.remove(harness.features_path)
  end
  if options.no_plugin_file then
    os.remove(harness.plugin_path)
  else
    write(harness.plugin_path, "")
  end

  local seen = { config = {}, buttons = {}, rules = {}, binds = {}, events = {}, notifications = {}, loaded = {} }

  hl = {
    config = function(values) seen.config[#seen.config + 1] = values end,
    on = function(name, callback) seen.events[name] = callback end,
    timer = function() end,
    dispatch = function() end,
    get_windows = function() return {} end,
    get_active_monitor = function() return { name = "eDP-1" } end,
    notification = { create = function(n) seen.notifications[#seen.notifications + 1] = n end },
    dsp = { window = { move = function(args) return args end } },
    plugin = {
      load = function(path) seen.loaded[#seen.loaded + 1] = path end,
      hyprbars = not options.first_pass and {
        add_button = function(button) seen.buttons[#seen.buttons + 1] = button end,
      } or nil,
    },
  }
  o = {
    bind = function(keys, description) seen.binds[keys] = description end,
    window = function(match, rules) seen.rules[#seen.rules + 1] = { match = match, rules = rules } end,
    shell_quote = function(value) return "'" .. tostring(value):gsub("'", "'\\''") .. "'" end,
  }

  assert(loadfile(plugin_dir .. "/hypr/titlebars.lua"))(plugin_dir)
  seen.bars = seen.config[1] and seen.config[1].plugin.hyprbars
  return seen
end

function harness.cleanup()
  os.execute("rm -rf '" .. home .. "'")
end

return harness
