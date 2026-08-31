# UI — design system ("CRT phosphor console")

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this before styling any code-built UI (panels, dev editors,
> buttons, labels). In-game diegetic HUD (HP/shield bars, toast, run clock, pointers) is a separate concern —
> see [`hud.md`](hud.md) — and stays on the Mandalore font.

## The system (added 2026-08-30, ported from the Electric Quest Board design doc)

A dark near-black ground with a green bias, phosphor-tinted text, **one** green accent (`#45e873`, the same
green as `selection_scan.gdshader`) + amber as the semantic second. Applied to every code-built panel to
replace Godot's default control theme + the ad-hoc "sea blue" (`Color(0.30, 0.45, 0.75)` …).

### 1. Fonts — `assets/fonts/ui/`
| Role | File | Used for |
|------|------|----------|
| Display | `ChakraPetch-{Regular,Medium,SemiBold,Bold}.ttf` | headings, titles, buttons, uppercase labels |
| Body | `IBMPlexSans-VF.ttf` | running text, descriptions, list rows (also the Theme `default_font`) |
| Mono | `IBMPlexMono-{Regular,Medium,SemiBold}.ttf` | numbers, ids, prices, code, data entry |

The HUD-editor "Font:" dropdown (text layers) scans `res://assets/fonts/` **recursively** (`_scan_fonts_in`),
so these show up as `ui/ChakraPetch-SemiBold`, `ui/IBMPlexSans-VF`, `ui/IBMPlexMono-Regular`, … — a font in a
subfolder is stored as `<subdir>/<basename>` and `_font_path()` resolves it as `FONTS_FOLDER + name + ext`.

(OFL-licensed, from google/fonts.) **Menus/panels that call `MandaloreText.a()` keep the Mandalore font**
(user decision 2026-08-30) — `a()` remaps characters for that font and corrupts real text under any other
face. So the font swap only reaches text that was already on the engine default font + bare controls.

### 2. `scripts/ui/ui_palette.gd` — `class_name UiPalette`
Colour tokens (`GROUND / SURFACE / SURFACE_2 / SURFACE_3 / INK / MUTED / FAINT / WIRE / WIRE_2 / ACCENT /
ACCENT_INK / ACCENT_DIM / ACCENT_WASH / SELECT_WASH / AMBER / DANGER / GOOD`), the `F_*` font paths, and
helpers: `stamp(node, font, size, col)`, `panel_style()`, `inset_style()`, `card_style(accent)`,
`display()/body()/mono()`. Use these for any code that builds its own `StyleBoxFlat` / `ColorRect` / `modulate`.

### 3. `assets/ui/theme.tres` — global Theme
Set as `project.godot` `[gui] theme/custom`. Styles Button/OptionButton/LineEdit/TextEdit/Panel/PanelContainer/
PopupMenu/PopupPanel/HSlider/VSlider/ProgressBar/ScrollBar/TabBar/TabContainer/Tree/ItemList/Tooltip/
Separator + `default_font`. **Every bare `Button.new()` etc. inherits it automatically** — no per-file code.

Rebuilt by **`tools/build_ui_theme.gd`** — `godot --headless --script tools/build_ui_theme.gd`. The palette
is duplicated at the top of that file (a bare `--script` SceneTree can't reliably resolve the `UiPalette`
class); **keep it in sync with `ui_palette.gd`**, which is the human source of truth.

## Rules

- **New code-built UI:** rely on the global Theme for bare controls; reach for `UiPalette.*` tokens for
  custom styleboxes/fills/label colours. Don't hardcode a new `Color(0.x, 0.y, 0.z)` for chrome.
- **Don't** restyle: rarity colours; weapon-slot orange / aux-slot blue (`AUX_SLOT_COLOR` — mirrors the HUD);
  the shield bar's blue; the per-tool teal/cyan/violet border accents on the Atlantic/Volcanic edit panels;
  gizmo/point-type colours in `creep_edit_mode`; the in-game HUD.
- `item_widget.gd` is LOCKED (tooltip-critical) — not swept; its bare controls still pick up the Theme.
