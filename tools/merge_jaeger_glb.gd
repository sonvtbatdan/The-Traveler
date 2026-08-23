extends SceneTree
## DEV TOOL (2026-08-23) — merges Jeager's eight animation glbs into ONE file.
##
## Every one of those glbs carries a byte-identical copy of the same 174k-vertex mesh and the same 7.9 MB
## texture, purely so it can carry one animation: ~270 MB of assets for ~20 MB of unique content. The GAME
## already merged them at runtime (`_merge_jaeger_clip` lifted each Animation and threw the mesh away), so
## this changes nothing about what is rendered — it moves that merge from every startup to once, here.
##
## `stand.glb` is the base: the user's clean, animation-free reference model. Its mesh/skeleton were verified
## identical to the clip glbs' (174381 verts, 24 bones, same bone names) before this was written.
##
## Run:  godot --path . --script tools/merge_jaeger_glb.gd

const SRC_DIR := "res://assets/weaponry/Jeager/"
const BASE    := SRC_DIR + "stand.glb"
const OUT     := SRC_DIR + "Jeager.glb"
## glb basename -> clip name to store it under. Must stay in step with arena_weapons.gd's JAEGER3D_CLIPS.
const CLIPS := {
	"Walk": "Walk", "Run": "Run", "Fly": "Fly", "Dive": "Dive",
	"Kick": "Kick", "Low Kick": "Low Kick", "Slash": "Slash", "Fly punch": "Fly Punch",
}

func _initialize() -> void:
	var packed := load(BASE) as PackedScene
	if packed == null:
		push_error("merge_jaeger: cannot load " + BASE); quit(1); return
	var root := packed.instantiate() as Node3D
	get_root().add_child(root)
	var ap := _find_ap(root)
	if ap == null:
		push_error("merge_jaeger: stand.glb has no AnimationPlayer to merge into"); quit(1); return

	var skel := _find_skel(root)
	if skel == null:
		push_error("merge_jaeger: stand.glb has no Skeleton3D"); quit(1); return
	# Where the tracks must point AFTER the merge. The source glbs do NOT agree on this: seven of them name
	# the armature node "Armature", but "Fly punch.glb" names it "target_character", so its tracks address
	# `target_character/Skeleton3D:<Bone>`. Godot resolves a track by PATH, so those never bound to anything —
	# neither in this export nor in the runtime merge this replaces, which is why Fly Punch's clip played
	# without a single bone moving. Re-addressing every track by BONE NAME against the target's own skeleton
	# is what actually fixes it.
	var skel_rel := ap.get_node(ap.root_node).get_path_to(skel)
	print("retargeting every track to: ", skel_rel)

	var lib_name := StringName("")
	if not ap.has_animation_library(lib_name):
		ap.add_animation_library(lib_name, AnimationLibrary.new())
	var lib := ap.get_animation_library(lib_name)
	# Drop stand's own stub clip — it is an empty "clip0" placeholder, not an animation.
	for existing: StringName in lib.get_animation_list():
		lib.remove_animation(existing)

	for base_name: String in CLIPS:
		var clip_name: String = CLIPS[base_name]
		var src := load(SRC_DIR + base_name + ".glb") as PackedScene
		if src == null:
			push_warning("merge_jaeger: missing " + base_name); continue
		var tmp := src.instantiate() as Node3D
		var sap := _find_ap(tmp)
		if sap == null:
			tmp.free(); push_warning("merge_jaeger: no AnimationPlayer in " + base_name); continue
		# Longest clip, for the same reason _merge_jaeger_clip picks it: "Fly punch.glb" ships a 0.07s stub
		# alongside the real 3.03s lunge, and the stub sorts first.
		var best: Animation = null
		for n: String in sap.get_animation_list():
			var a := sap.get_animation(n)
			if a != null and (best == null or a.length > best.length):
				best = a
		if best == null:
			tmp.free(); continue
		var a := best.duplicate(true) as Animation
		var dropped := _retarget(a, skel_rel, skel)
		lib.add_animation(StringName(clip_name), a)
		print("  + %-10s len=%.2fs tracks=%d dropped=%d" % [clip_name, a.length, a.get_track_count(), dropped])
		tmp.free()

	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err != OK:
		push_error("merge_jaeger: append_from_scene failed %d" % err); quit(1); return
	err = doc.write_to_filesystem(st, OUT)
	print("write ", OUT, " err=", err)
	var f := FileAccess.open(OUT, FileAccess.READ)
	print("merged size = %.1f MB" % ((f.get_length() if f != null else 0) / 1048576.0))
	quit(0)

## Re-points every track at `skel_rel:<bone>`, keeping only the ones whose bone actually exists in the
## target skeleton. Returns how many were dropped. Iterates backwards because removing shifts the indices.
func _retarget(a: Animation, skel_rel: NodePath, skel: Skeleton3D) -> int:
	var dropped := 0
	for i in range(a.get_track_count() - 1, -1, -1):
		var sub := a.track_get_path(i).get_concatenated_subnames()
		if sub.is_empty() or skel.find_bone(sub) < 0:
			a.remove_track(i)
			dropped += 1
			continue
		a.track_set_path(i, NodePath(str(skel_rel) + ":" + sub))
	return dropped

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c: Node in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c: Node in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null
