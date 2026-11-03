extends Node
## Temporary FPS benchmark (Claude): loads the main scene, freezes the player at spawn and times each heavy feature off.

const SCENE := "res://cultic/scenes/CULTIC_ROOM_MAIN_SCENE.tscn"
const WARMUP := 1.2
const MEASURE := 2.5

var root: Node
var rid: RID
var lines: PackedStringArray = []

var _acc_frames := 0
var _acc_time := 0.0
var _acc_gpu := 0.0
var _acc_cpu := 0.0
var _acc_proc := 0.0
var _acc_draw := 0.0
var _acc_prims := 0.0
var _acc_obj := 0.0
var _measuring := false


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root = load(SCENE).instantiate()
	add_child(root)
	rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await get_tree().create_timer(3.0).timeout
	var player := root.get_node_or_null("Player")
	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lines.append("window %s  3d scale %.2f  vsync off" % [str(get_window().size), get_viewport().scaling_3d_scale])
	await _run_all()
	var f := FileAccess.open("res://tools/art/_bench/results.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	get_tree().quit()


func _process(delta: float) -> void:
	if not _measuring:
		return
	_acc_frames += 1
	_acc_time += delta
	_acc_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_acc_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_acc_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_acc_draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_acc_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_acc_obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)


func _measure(label: String) -> void:
	await get_tree().create_timer(WARMUP).timeout
	_acc_frames = 0; _acc_time = 0.0; _acc_gpu = 0.0; _acc_cpu = 0.0; _acc_proc = 0.0
	_acc_draw = 0.0; _acc_prims = 0.0; _acc_obj = 0.0
	_measuring = true
	await get_tree().create_timer(MEASURE).timeout
	_measuring = false
	var n := maxf(_acc_frames, 1)
	lines.append("%-34s fps %6.1f | gpu %6.2f ms | render-cpu %6.2f ms | scripts %5.2f ms | draws %6d | tris %8d | objs %5d" % [
		label, _acc_frames / maxf(_acc_time, 0.001), _acc_gpu / n, _acc_cpu / n, _acc_proc / n,
		int(_acc_draw / n), int(_acc_prims / n), int(_acc_obj / n)])


func _lights() -> Array:
	return root.find_children("*", "Light3D", true, false)


func _run_all() -> void:
	var env: Environment = (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	var vp := get_viewport()
	await _measure("BASELINE")

	# omni/spot shadows off
	var shadowed := []
	for l: Light3D in _lights():
		if not (l is DirectionalLight3D) and l.shadow_enabled:
			shadowed.append(l); l.shadow_enabled = false
	await _measure("omni shadows OFF (%d lights)" % shadowed.size())
	for l in shadowed: l.shadow_enabled = true

	# omni shadows dual paraboloid
	var omnis := []
	for l in shadowed:
		if l is OmniLight3D:
			omnis.append([l, l.omni_shadow_mode]); l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	await _measure("omni shadows dual-paraboloid")
	for e in omnis: e[0].omni_shadow_mode = e[1]

	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = false
		await _measure("sun shadow OFF")
		sun.shadow_enabled = true

	var hidden := []
	for l: Light3D in _lights():
		if not (l is DirectionalLight3D) and l.visible:
			hidden.append(l); l.visible = false
	await _measure("all omni lights hidden (%d)" % hidden.size())
	for l in hidden: l.visible = true

	env.volumetric_fog_enabled = false
	await _measure("volumetric fog OFF")
	env.volumetric_fog_enabled = true

	env.ssao_enabled = false
	await _measure("SSAO OFF")
	env.ssao_enabled = true

	env.glow_enabled = false
	await _measure("glow OFF")
	env.glow_enabled = true

	var post := root.get_node_or_null("RetroPost") as CanvasLayer
	if post:
		post.visible = false
		await _measure("RetroPost filter hidden")
		post.visible = true

	var old_scale := vp.scaling_3d_scale
	vp.scaling_3d_scale = 0.35
	await _measure("3d scale 0.35")
	vp.scaling_3d_scale = old_scale

	for group in ["Shell", "Furniture", "Decor", "NewModels", "RepoModels", "Gentleman", "SkySphere", "WetAsphalt", "WindowGlass", "BasementHatch", "BasementFog"]:
		var n := root.get_node_or_null(group)
		if n and "visible" in n:
			n.visible = false
			await _measure("hide " + group)
			n.visible = true

	var flick := root.get_node_or_null("FireFlicker")
	if flick:
		flick.process_mode = Node.PROCESS_MODE_DISABLED
		await _measure("FireFlicker paused")
		flick.process_mode = Node.PROCESS_MODE_INHERIT

	# everything cheap at once
	for l in shadowed: l.shadow_enabled = false
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	await _measure("ALL: omni shadows+vfog+ssao OFF")
