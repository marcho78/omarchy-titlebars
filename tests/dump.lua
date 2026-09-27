-- Prints what hypr/titlebars.lua configures for a settings JSON string, as
-- JSON, so tests/styles.test.cjs can compare it with Styles.js.
-- Usage: lua tests/dump.lua '<settings json>'

local harness = dofile((arg[0]:match("^(.*)/[^/]+$") or ".") .. "/harness.lua")
local seen = harness.run(arg[1])
harness.cleanup()

local function encode(value)
  local kind = type(value)
  if kind == "string" then
    return '"' .. value:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
  elseif kind == "number" or kind == "boolean" then
    return tostring(value)
  elseif kind == "table" then
    local parts = {}
    if #value > 0 then
      for _, item in ipairs(value) do
        parts[#parts + 1] = encode(item)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
      parts[#parts + 1] = encode(tostring(key)) .. ":" .. encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local buttons = {}
for _, button in ipairs(seen.buttons) do
  buttons[#buttons + 1] = { icon = button.icon, bg = button.bg_color, fg = button.fg_color, size = button.size }
end

print(encode({
  buttons = buttons,
  alignment = seen.bars.bar_buttons_alignment,
  hover = seen.bars.icon_on_hover,
  inactive = seen.bars.inactive_button_color,
  bar = seen.bars.bar_color,
  title = seen.bars.col.text,
}))
