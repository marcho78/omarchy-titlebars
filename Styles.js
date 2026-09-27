// Styles.js - what the title bars look like for a given set of settings.
//
// Mirrors hypr/titlebars.lua so the panel preview matches the real bars;
// tests/styles.test.cjs runs both and fails if they drift apart.

// fill: "role" colors each button, "mono" uses one neutral color, "none" shows
// only the glyph. scale enlarges glyph-only buttons so the glyphs stay legible.
var STYLES = {
  dots: { fill: "role", hover: true, scale: 1, glyphs: { minimize: "−", maximize: "+", close: "×" } },
  labeled: { fill: "role", hover: false, scale: 1, glyphs: { minimize: "−", maximize: "+", close: "×" } },
  mono: { fill: "mono", hover: true, scale: 1, glyphs: { minimize: "−", maximize: "+", close: "×" } },
  symbols: { fill: "none", hover: false, scale: 1.5, glyphs: { minimize: "−", maximize: "□", close: "×" } },
  nerd: { fill: "none", hover: false, scale: 1.5, glyphs: { minimize: "󰖰", maximize: "󰖯", close: "󰅖" } }
}

var ORDERS = {
  standard: ["minimize", "maximize", "close"],
  mac: ["close", "minimize", "maximize"]
}

var TRANSPARENT = "#00000000"

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// colors.toml -> { role: "rrggbb" }
function parsePalette(text) {
  var palette = {}
  String(text || "").split("\n").forEach(function(line) {
    var match = line.match(/^\s*([\w]+)\s*=\s*"#([0-9a-fA-F]{6})"/)
    if (match) palette[match[1]] = match[2].toLowerCase()
  })
  return palette
}

// Defaults with the user's overrides on top, validated the way the Lua does.
function merge(defaults, user, schema) {
  var settings = clone(defaults)
  var choices = (schema && schema.choices) || {}
  var ranges = (schema && schema.ranges) || {}
  user = user || {}

  Object.keys(defaults).forEach(function(key) {
    var value = user[key]
    var fallback = defaults[key]
    if (value === undefined || value === null) return
    if (key === "colors") {
      if (typeof value !== "object" || Array.isArray(value)) return
      Object.keys(fallback).forEach(function(role) {
        if (typeof value[role] === "string") settings.colors[role] = value[role]
      })
    } else if (key === "noBarApps") {
      if (Array.isArray(value)) settings.noBarApps = value.filter(function(app) { return typeof app === "string" && app !== "" })
    } else if (typeof value !== typeof fallback) {
      return
    } else if (choices[key] && choices[key].indexOf(value) < 0) {
      return
    } else if (ranges[key]) {
      settings[key] = Math.round(Math.max(ranges[key][0], Math.min(ranges[key][1], value)))
    } else {
      settings[key] = value
    }
  })
  return settings
}

// A setting color ("red", "#rrggbb", "#rrggbbaa") as a QML color string.
// QML writes alpha first (#aarrggbb); the settings use CSS/Hyprland order.
function resolveColor(value, fallbackRole, palette) {
  var hex = null
  if (typeof value === "string") {
    var solid = value.match(/^#([0-9a-fA-F]{6})$/)
    var alpha = value.match(/^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})$/)
    if (solid) hex = solid[1]
    else if (alpha) return "#" + alpha[2] + alpha[1]
    else if (palette[value]) hex = palette[value]
  }
  return "#" + (hex || palette[fallbackRole] || "000000")
}

function colorsFor(settings, defaults, palette) {
  var chosen = settings.followTheme ? defaults.colors : settings.colors
  var colors = {}
  Object.keys(defaults.colors).forEach(function(role) {
    colors[role] = resolveColor(chosen[role], defaults.colors[role], palette)
  })
  return colors
}

// The visible buttons, left to right, with how each one is drawn.
function buttons(settings, colors) {
  var style = STYLES[settings.style] || STYLES.dots
  var shown = { minimize: settings.showMinimize, maximize: settings.showMaximize, close: settings.showClose }
  var size = Math.floor(settings.buttonSize * style.scale + 0.5)

  return (ORDERS[settings.order] || ORDERS.standard).filter(function(name) {
    return shown[name]
  }).map(function(name) {
    var fill = TRANSPARENT
    var glyphColor = colors.title
    if (style.fill === "role") {
      fill = colors[name]
      glyphColor = colors.icon
    } else if (style.fill === "mono") {
      fill = colors.titleInactive
      glyphColor = colors.bar
    }
    return {
      name: name,
      glyph: style.glyphs[name],
      fill: fill,
      inactiveFill: style.fill === "none" ? TRANSPARENT : colors.inactiveButton,
      glyphColor: glyphColor,
      size: size,
      // hyprbars sizes glyphs from the button size.
      glyphSize: Math.max(1, Math.round(size * 0.62)),
      glyphsOnHover: style.hover
    }
  })
}

// The settings gear on the far side of the bar (needs the hyprbars patch).
function settingsButton(settings, colors) {
  if (!settings.settingsButton) return null
  var size = Math.floor(settings.buttonSize * 1.5 + 0.5)
  return { glyph: "󰒓", color: colors.titleInactive, size: size, glyphSize: Math.max(1, Math.round(size * 0.62)) }
}
