-- Runs hypr/titlebars.lua against a fake Hyprland API and checks what it sets up.
-- Usage (from the plugin directory): lua tests/hypr.test.lua

local harness = dofile((arg[0]:match("^(.*)/[^/]+$") or ".") .. "/harness.lua")
local run = harness.run
local plugin_path = harness.plugin_path

local failures, count = 0, 0
local function test(name, body)
  count = count + 1
  local ok, message = pcall(body)
  if not ok then
    failures = failures + 1
    print("FAIL " .. name .. "\n     " .. tostring(message))
  end
end

local function eq(actual, expected, what)
  if actual ~= expected then
    error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function icons(seen)
  local list = {}
  for _, button in ipairs(seen.buttons) do
    list[#list + 1] = button.icon
  end
  return table.concat(list, " ")
end

local function has_rule(seen, key)
  for _, rule in ipairs(seen.rules) do
    if rule.rules[key] ~= nil then
      return rule
    end
  end
end

test("defaults reproduce the stock look", function()
  local seen = run(nil)
  eq(#seen.notifications, 0, "notifications")
  eq(seen.loaded[1], plugin_path, "plugin path")
  eq(seen.bars.bar_height, 26, "bar_height")
  eq(seen.bars.bar_color, "rgb(1a1b26)", "bar_color")
  eq(seen.bars.col.text, "rgb(a9b1d6)", "col.text")
  eq(seen.bars.bar_text_font, "monospace", "font")
  eq(seen.bars.bar_text_size, 12, "text size")
  eq(seen.bars.bar_text_weight, "medium", "weight")
  eq(seen.bars.bar_text_align, "center", "align")
  eq(seen.bars.bar_buttons_alignment, "right", "alignment")
  eq(seen.bars.bar_padding, 12, "padding")
  eq(seen.bars.bar_button_padding, 8, "button padding")
  eq(seen.bars.bar_precedence_over_border, true, "precedence")
  eq(seen.bars.icon_on_hover, true, "icon_on_hover")
  eq(seen.bars.inactive_button_color, "rgb(414868)", "inactive buttons")
  eq(seen.bars.enabled, true, "enabled")
  -- Right-aligned buttons are added edge-first: close, maximize, minimize.
  eq(icons(seen), "× + −", "button order")
  eq(seen.buttons[1].bg_color, "rgb(f7768e)", "close color")
  eq(seen.buttons[2].bg_color, "rgb(9ece6a)", "maximize color")
  eq(seen.buttons[3].bg_color, "rgb(e0af68)", "minimize color")
  eq(seen.buttons[1].fg_color, "rgb(0e0e14)", "glyph color")
  eq(seen.buttons[1].size, 12, "button size")
  assert(seen.buttons[1].action:find("hl.dsp.window.close()", 1, true), "close action")
  assert(seen.bars.on_double_click:find('mode = "maximized"', 1, true), "double click maximizes")
  eq(has_rule(seen, "hyprbars:title_color").rules["hyprbars:title_color"], "rgb(565f89)", "dim title rule")
  eq(seen.binds["SUPER + M"], "Minimize window", "minimize shortcut")
  eq(seen.binds["SUPER + ALT + M"], "Restore minimized window", "restore shortcut")
  assert(seen.events["window.active"], "restore-on-activate hook")
end)

test("first pass registers shortcuts but waits for the plugin", function()
  local seen = run(nil, { first_pass = true })
  eq(seen.loaded[1], plugin_path, "plugin path")
  eq(#seen.config, 0, "config calls")
  eq(#seen.buttons, 0, "buttons")
  eq(seen.binds["SUPER + M"], "Minimize window", "minimize shortcut")
end)

test("missing plugin build skips the bars", function()
  local seen = run(nil, { no_plugin_file = true })
  eq(#seen.loaded, 0, "plugin loads")
  eq(#seen.buttons, 0, "buttons")
  assert(seen.events["window.active"], "minimize still restores")
end)

test("left placement with macOS order", function()
  local seen = run('{ "buttons": "left", "order": "mac" }')
  eq(seen.bars.bar_buttons_alignment, "left", "alignment")
  eq(icons(seen), "× − +", "left-aligned buttons are added in reading order")
end)

test("right placement with macOS order reads close, minimize, maximize", function()
  local seen = run('{ "order": "mac" }')
  eq(icons(seen), "+ − ×", "edge-first order")
end)

test("hidden buttons are skipped", function()
  local seen = run('{ "showMaximize": false, "showMinimize": false }')
  eq(icons(seen), "×", "only close")
end)

test("glyph-only styles drop the circles and enlarge the glyphs", function()
  local seen = run('{ "style": "symbols" }')
  eq(icons(seen), "× □ −", "symbols glyphs")
  eq(seen.buttons[1].bg_color, "rgba(00000000)", "transparent circle")
  eq(seen.buttons[1].fg_color, "rgb(a9b1d6)", "glyph uses title color")
  eq(seen.buttons[1].size, 18, "scaled size")
  eq(seen.bars.icon_on_hover, false, "glyphs always visible")
  eq(seen.bars.inactive_button_color, "rgba(00000000)", "no inactive circles")

  seen = run('{ "style": "nerd", "buttonSize": 14 }')
  eq(icons(seen), "󰅖 󰖯 󰖰", "nerd glyphs")
  eq(seen.buttons[1].size, 21, "scaled nerd size")
end)

test("labeled and mono styles", function()
  local seen = run('{ "style": "labeled" }')
  eq(seen.bars.icon_on_hover, false, "labeled shows glyphs")
  eq(seen.buttons[1].bg_color, "rgb(f7768e)", "labeled keeps colors")

  seen = run('{ "style": "mono" }')
  eq(seen.buttons[1].bg_color, "rgb(565f89)", "mono circle")
  eq(seen.buttons[3].bg_color, "rgb(565f89)", "mono circles match")
  eq(seen.buttons[1].fg_color, "rgb(1a1b26)", "mono glyph")
end)

test("custom colors apply only when not following the theme", function()
  local custom = '"colors": { "close": "#ff0000", "bar": "blue", "title": "#11223380" }'
  local seen = run('{ "followTheme": true, ' .. custom .. ' }')
  eq(seen.buttons[1].bg_color, "rgb(f7768e)", "theme close color")

  seen = run('{ "followTheme": false, ' .. custom .. ' }')
  eq(seen.buttons[1].bg_color, "rgb(ff0000)", "custom hex")
  eq(seen.bars.bar_color, "rgb(7aa2f7)", "theme role by name")
  eq(seen.bars.col.text, "rgba(11223380)", "hex with alpha")
  eq(seen.buttons[2].bg_color, "rgb(9ece6a)", "unset colors keep defaults")
  eq(#seen.notifications, 0, "no problems")
end)

test("title, double click, shortcuts, and enabled switches", function()
  local seen = run('{ "title": false, "doubleClick": "none", "shortcuts": false, "enabled": false, "dimInactive": false }')
  eq(seen.bars.bar_title_enabled, false, "title off")
  eq(seen.bars.on_double_click, "", "no double click")
  eq(seen.binds["SUPER + M"], nil, "no shortcuts")
  eq(seen.bars.enabled, false, "bars disabled")
  eq(has_rule(seen, "hyprbars:title_color"), nil, "no dim rule")

  seen = run('{ "doubleClick": "minimize", "titleFont": "Inter", "titleAlign": "left" }')
  assert(seen.bars.on_double_click:find("special:minimized", 1, true), "double click minimizes")
  eq(seen.bars.bar_text_font, "Inter", "font")
  eq(seen.bars.bar_text_align, "left", "align")
end)

test("apps without title bars", function()
  local function no_bar_apps(seen)
    local apps = {}
    for _, rule in ipairs(seen.rules) do
      if rule.rules["hyprbars:no_bar"] and type(rule.match) == "string" then
        apps[#apps + 1] = rule.match
      end
    end
    return table.concat(apps, ",")
  end

  local seen = run('{ "noBarApps": ["^chromium$", "org.gnome.Nautilus"] }')
  eq(no_bar_apps(seen), "^WebcamOverlay-(small|medium|large)$,^chromium$,org.gnome.Nautilus", "no_bar rules")

  -- A list with anything invalid in it is ignored as a whole and reported.
  seen = run('{ "noBarApps": ["^chromium$", "", 5] }')
  eq(no_bar_apps(seen), "^WebcamOverlay-(small|medium|large)$", "invalid list ignored")
  assert(seen.notifications[1].text:find("noBarApps", 1, true), "reported")
end)

test("bad values fall back and are reported", function()
  local seen = run('{ "style": "fancy", "barHeight": 200, "buttonSize": "big", "colors": { "close": "nope" }, "followTheme": false }')
  eq(seen.bars.bar_height, 26, "out-of-range height uses the default")
  eq(seen.buttons[1].size, 12, "default size")
  eq(icons(seen), "× + −", "default style")
  eq(seen.buttons[1].bg_color, "rgb(f7768e)", "fallback color")
  eq(#seen.notifications, 1, "one notification")
  local text = seen.notifications[1].text
  assert(text:find("ignored invalid", 1, true) and text:find("style", 1, true), text)
  assert(text:find("barHeight", 1, true) and text:find("buttonSize", 1, true), text)
  assert(text:find('unknown color "nope"', 1, true), text)
end)

test("invalid JSON falls back to defaults", function()
  local seen = run('{ "style": "mono", }')
  eq(icons(seen), "× + −", "defaults used")
  eq(seen.buttons[1].bg_color, "rgb(f7768e)", "default colors")
  assert(seen.notifications[1].text:find("not valid JSON", 1, true), seen.notifications[1].text)
end)

test("settings gear sits opposite the buttons when the patch is built", function()
  local seen = run(nil)
  eq(#seen.buttons, 3, "no gear without the patched build")

  seen = run(nil, { features = "opposite\n" })
  eq(#seen.buttons, 4, "gear added")
  local gear = seen.buttons[4]
  eq(gear.icon, "󰒓", "gear glyph")
  eq(gear.opposite, true, "opposite side")
  eq(gear.icon_always, true, "always visible")
  eq(gear.bg_color, "rgba(00000000)", "no circle")
  eq(gear.fg_color, "rgb(565f89)", "dim glyph")
  eq(gear.size, 18, "gear size")
  assert(gear.action:find("summon marcho78.titlebars", 1, true), "opens the panel")

  seen = run('{ "settingsButton": false }', { features = "opposite\n" })
  eq(#seen.buttons, 3, "gear turned off")
end)

test("JSON strings, escapes, and whitespace", function()
  local seen = run('\n{\n\t"titleFont" : "A \\"B\\" \\u00d7 \\ud83d\\ude00 \\\\",\n  "noBarApps": [ ],\n  "titleSize": 1.4e1\n}\n')
  eq(seen.bars.bar_text_font, 'A "B" × 😀 \\', "decoded string")
  eq(seen.bars.bar_text_size, 14, "exponent number")
  eq(#seen.notifications, 0, "no problems")

  seen = run("   ")
  eq(#seen.notifications, 0, "blank file means defaults")
end)

harness.cleanup()
print(string.format("%d/%d tests passed", count - failures, count))
os.exit(failures == 0 and 0 or 1)
