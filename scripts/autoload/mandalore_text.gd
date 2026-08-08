extends Node
## 2026-08-07, on request: the Mandalore font's uppercase "A" glyph is broken/buggy ("bị lỗi") — every place
## that renders text in Mandalore must substitute a lowercase "a" for any uppercase "A" instead, everywhere
## in the string, no other casing touched (an all-caps label like "AUTO:OFF" becomes "aUTO:OFF" — accepted
## tradeoff, per explicit request, rather than leaving a broken glyph on screen).
##
## Single choke point so every one of the ~30 files that load assets/fonts/mandalore/mandalore.ttf can route
## BOTH static UI literals ("WIN", "CRAFT", tab labels, headers...) and dynamic/data-driven text (weapon/aux
## names, enemy "Last Hit By" names, fragment names, rarity labels, etc. — anything built at runtime, where
## the "A" can't be fixed by editing a source literal because it comes from data) through one function:
##     label.text = MandaloreText.a("Some Text")
## Autoload (registered in project.godot) so every file can call it directly with no preload boilerplate.
##
## Letter-spacing (same request, "spacing giãn ra gấp đôi hiện tại"): applied here too, but via a completely
## different mechanism — FontFile.set_extra_spacing() is a property of the FONT RESOURCE, not the text
## string, and every one of those ~30 files load() the SAME path (res://assets/fonts/mandalore/mandalore.ttf).
## Godot's resource loader caches by path, so every load() call anywhere in the project returns the exact
## same FontFile instance — set the spacing ONCE, here, on that shared instance at boot, and it applies
## everywhere automatically. No default extra spacing existed to literally "double" (Font spacing defaults
## to 0px), so GLYPH_SPACING_PX below is a fresh, tunable pick — adjust and re-run if it reads too
## tight/loose in game.
const FONT_PATH := "res://assets/fonts/mandalore/mandalore.ttf"
const GLYPH_SPACING_PX := 4

func _ready() -> void:
	var f := load(FONT_PATH) as FontFile
	if f != null:
		f.set_extra_spacing(0, TextServer.SPACING_GLYPH, GLYPH_SPACING_PX)   # FontFile's setter takes a cache_index (0 = the font's only/default cache entry) — plain Font.set_spacing() is getter-only on this class

func a(text: String) -> String:
	return text.replace("A", "a")
