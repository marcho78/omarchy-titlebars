// Checks that the panel preview (Styles.js) draws the same buttons, in the
// same order and colors, as the real bars configured by hypr/titlebars.lua.
// Usage (from the plugin directory): node tests/styles.test.cjs

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { execFileSync } = require("node:child_process");

const directory = path.join(__dirname, "..");
const Styles = {};
vm.createContext(Styles);
vm.runInContext(fs.readFileSync(path.join(directory, "Styles.js"), "utf8"), Styles);

const defaults = JSON.parse(fs.readFileSync(path.join(directory, "defaults.json"), "utf8"));
const schema = JSON.parse(fs.readFileSync(path.join(directory, "schema.json"), "utf8"));
// Same palette tests/harness.lua gives the Lua side.
const harness = fs.readFileSync(path.join(__dirname, "harness.lua"), "utf8");
const palette = Styles.parsePalette(harness.split("harness.colors = [[")[1].split("]]")[0]);

// Hyprland color strings -> QML color strings (alpha first).
function qmlColor(hyprland) {
  const solid = hyprland.match(/^rgb\(([0-9a-f]{6})\)$/);
  if (solid) return "#" + solid[1];
  const alpha = hyprland.match(/^rgba\(([0-9a-f]{6})([0-9a-f]{2})\)$/);
  return "#" + alpha[2] + alpha[1];
}

const cases = [
  {},
  { buttons: "left" },
  { order: "mac" },
  { buttons: "left", order: "mac" },
  { style: "labeled" },
  { style: "mono", buttons: "left" },
  { style: "symbols", buttonSize: 14 },
  { style: "nerd", order: "mac" },
  { showMaximize: false },
  { showClose: false, showMinimize: false, style: "symbols" },
  { followTheme: false, colors: { close: "#ff0000", bar: "blue", icon: "#11223380" } },
  { followTheme: false, style: "mono", colors: { titleInactive: "#abcdef" } },
  { style: "fancy", buttonSize: 99 },
];

let passed = 0;
for (const user of cases) {
  const lua = JSON.parse(execFileSync("lua", [path.join(__dirname, "dump.lua"), JSON.stringify(user)], { encoding: "utf8" }));
  // Copy out of the vm context so deepEqual sees ordinary arrays and objects.
  const settings = JSON.parse(JSON.stringify(Styles.merge(defaults, user, schema)));
  const colors = JSON.parse(JSON.stringify(Styles.colorsFor(settings, defaults, palette)));
  const preview = JSON.parse(JSON.stringify(Styles.buttons(settings, colors)));

  // hyprbars adds buttons edge-first; the preview lists them left to right.
  const luaButtons = lua.alignment === "right" ? lua.buttons.slice().reverse() : lua.buttons;
  const label = JSON.stringify(user);

  assert.equal(lua.alignment, settings.buttons, `${label}: alignment`);
  assert.deepEqual(preview.map((b) => b.glyph), luaButtons.map((b) => b.icon), `${label}: glyphs`);
  assert.deepEqual(preview.map((b) => b.fill), luaButtons.map((b) => qmlColor(b.bg)), `${label}: fills`);
  assert.deepEqual(preview.map((b) => b.glyphColor), luaButtons.map((b) => qmlColor(b.fg)), `${label}: glyph colors`);
  assert.deepEqual(preview.map((b) => b.size), luaButtons.map((b) => b.size), `${label}: sizes`);
  for (const button of preview) {
    assert.equal(button.glyphsOnHover, lua.hover, `${label}: hover`);
    assert.equal(button.inactiveFill, qmlColor(lua.inactive), `${label}: inactive fill`);
  }
  assert.equal(colors.bar, qmlColor(lua.bar), `${label}: bar color`);
  assert.equal(colors.title, qmlColor(lua.title), `${label}: title color`);
  passed++;
}

console.log(`${passed}/${cases.length} style cases match the Hyprland config`);
