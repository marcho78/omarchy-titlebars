# hyprbars (vendored)

Source: https://github.com/hyprwm/hyprland-plugins, directory `hyprbars/`,
commit `7644cecdb947060682891a0db2a0cdc5c0b9e704` (tag v0.56.0, the commit
hyprpm.toml pins for Hyprland 0.56.0 through 0.56.2). BSD 3-Clause, see LICENSE.

Title Bars compiles these files on your machine with `bin/titlebars build`;
nothing is downloaded. Upstream's Makefile, CMake and Meson files are not used.

One local change, `opposite-side-buttons.patch`, is already applied: a button
can sit on the other side of the bar (the settings gear) and keep its look on
unfocused windows.

To update: check out the new pinned commit, copy `main.cpp`, `barDeco.*`,
`BarPassElement.*` and `globals.hpp` here, apply the patch, and add the new
Hyprland commits to `hypr/pins.json`.

| File | SHA-256 |
|---|---|
| `barDeco.cpp` | `bcc50af5804850468249fd61b866b1a07a662a648e8e2901c3b3f7135bff3e06` |
| `BarPassElement.cpp` | `0e607597b130ec8277fb301b2b97b0fcde977a64e2163b53024907e4b4476fe7` |
| `main.cpp` | `651681b02d2d60131864ed239641e25291dc47f0f1bcf980af8002e049639903` |
| `barDeco.hpp` | `9e2c3e6829eeb6b24be69456ed97ea1fef99e4d45477cbb518ae925b07a3207f` |
| `BarPassElement.hpp` | `9a460848366edc61c55500f5577180d10f383b65022b3952648efe3b4e7208f8` |
| `globals.hpp` | `4b806ddf3a6424715d6ba672df73601eb97373f19c2ec22efe599753ebca1ea6` |
