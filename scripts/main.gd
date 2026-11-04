extends Node2D
## 主場景：攝影機、滑鼠工具、游標預覽，並把介面與世界接起來。

const Art = preload("res://scripts/view/art.gd")
const WorldView = preload("res://scripts/view/world_view.gd")
const UI = preload("res://scripts/ui/ui.gd")

var cam: Camera2D
var world: Node2D
var cursor: Cursor
var ui: CanvasLayer

var tool := ""
var hover := Vector2i(-1, -1)
var drag_start := Vector2i(-1, -1)
var dragging := false
var panning := false
var pan_moved := 0.0
var selected := -1
var selected_vehicle := -1
var hover_text := ""
var bot_mode := false
var selected_tile := Vector2i(-1, -1)
var route_first := -1
var title_mode := true
var title_t := 0.0
var shots := ""
var auto := false


func _ready() -> void:
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	world = WorldView.new()
	add_child(world)
	cursor = Cursor.new()
	cursor.main = self
	cursor.z_index = 20
	add_child(cursor)
	ui = UI.new()
	ui.main = self
	add_child(ui)
	Game.map_reset.connect(_on_map_reset)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
		if a == "--auto":
			auto = true
	Game.new_game("清河", randi() % 100000 if shots == "" else 4242)
	Game.speed = 0
	ui.show_title(true)
	if "--autoplay" in OS.get_cmdline_user_args():
		var bot = load("res://scripts/tools/autoplay.gd").new()
		bot.main = self
		add_child(bot)
		bot.run()
	elif shots != "":
		if "--gallery" in OS.get_cmdline_user_args():
			DirAccess.make_dir_recursive_absolute(shots)
			_gallery()
		elif "--uitest" in OS.get_cmdline_user_args():
			DirAccess.make_dir_recursive_absolute(shots)
			_ui_test()
		else:
			_run_shots()


func _on_map_reset() -> void:
	world.setup(cam)
	var y: Dictionary = Game.buildings.get(Game.yamen_id, {})
	if not y.is_empty():
		cam.position = WorldView.tile_pos(y.x + 1, y.y + 1)
	cam.zoom = Vector2.ONE
	selected = -1
	selected_vehicle = -1
	tool = ""


func start_new(cname: String, seed_v: int) -> void:
	title_mode = false
	Game.new_game(cname, seed_v)
	Game.speed = 1
	ui.show_title(false)


func load_saved() -> bool:
	if Game.load_game():
		title_mode = false
		Game.speed = 1
		ui.show_title(false)
		return true
	return false


# ───────────────────────── 座標 ─────────────────────────

static func to_tile_f(p: Vector2) -> Vector2:
	return Vector2((p.x / 32.0 + p.y / 16.0) * 0.5, (p.y / 16.0 - p.x / 32.0) * 0.5)


static func to_tile(p: Vector2) -> Vector2i:
	var fx := (p.x / 32.0 + p.y / 16.0) * 0.5
	var fy := (p.y / 16.0 - p.x / 32.0) * 0.5
	return Vector2i(roundi(fx), roundi(fy))


func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var cells := []
	var c := a
	cells.append(c)
	var horiz := absi(b.x - a.x) >= absi(b.y - a.y)
	if horiz:
		while c.x != b.x:
			c.x += signi(b.x - c.x)
			cells.append(c)
		while c.y != b.y:
			c.y += signi(b.y - c.y)
			cells.append(c)
	else:
		while c.y != b.y:
			c.y += signi(b.y - c.y)
			cells.append(c)
		while c.x != b.x:
			c.x += signi(b.x - c.x)
			cells.append(c)
	return cells


func rect_cells(a: Vector2i, b: Vector2i) -> Array:
	var cells := []
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			cells.append(Vector2i(x, y))
	return cells


func tool_kind() -> String:
	if tool in ["road_dirt", "road_stone", "canal", "wall"]:
		return "line"
	if tool.begins_with("zone_") or tool == "bulldoze":
		return "rect"
	if tool.begins_with("b:"):
		return "place"
	return tool


# ───────────────────────── 輸入 ─────────────────────────

func set_tool(t: String) -> void:
	tool = t
	route_first = -1
	dragging = false
	if t == "route":
		ui.toast("點選起點：驛站、碼頭或外邑")
	cursor.queue_redraw()


func _process(delta: float) -> void:
	if title_mode:
		title_t += delta
		cam.position += Vector2(cos(title_t * 0.1), sin(title_t * 0.13)) * 12.0 * delta
		return
	var kv := Vector2.ZERO
	if not ui.typing():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			kv.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			kv.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			kv.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			kv.y += 1
	if kv != Vector2.ZERO:
		cam.position += kv.normalized() * 700.0 * delta / cam.zoom.x
		_clamp_cam()
	if bot_mode:
		return
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var t := to_tile(get_global_mouse_position())
	if over_ui and not dragging:
		t = Vector2i(-1, -1)
	if t != hover:
		hover = t
		cursor.queue_redraw()
	var ht := _hover_info(t) if tool == "" and not panning else ""
	ui.set_hover(ht, get_viewport().get_mouse_position())


func _vehicle_at(p: Vector2) -> int:
	var best := -1
	var bd := 0.6
	for v in Game.vehicles.values():
		var d: float = (v.pos as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = v.id
	return best


func _hover_info(t: Vector2i) -> String:
	if not Game.inb(t.x, t.y):
		return ""
	var vid := _vehicle_at(to_tile_f(get_global_mouse_position()))
	if vid >= 0:
		var v: Dictionary = Game.vehicles[vid]
		var s: String = "[b]%s[/b]" % Defs.VEHICLES[v.kind]["name"]
		if v.amt > 0:
			s += "　{i:store} %s [b]%d[/b]" % [Defs.cargo_name(v.cargo), int(v.amt)]
		return s
	var b := Game.building_at(t.x, t.y)
	if b.is_empty():
		return ""
	var s := "[b]%s[/b]" % Game.bname(b)
	match b.type:
		"house":
			var hp := int(b.happy)
			s += "　{i:people} [b]%d[/b]　{i:%s} [b]%d[/b]" % [Defs.GROW.house.pop[b.level - 1], "mood_good" if hp >= 65 else ("mood_bad" if hp < 40 else "mood"), hp]
		"farm":
			s += "　{i:land} 肥力 [b]%d%%[/b]" % int(Game.fert[Game.idx(b.x, b.y)] * 100)
		"town":
			s += "　[color=#8b7d6e]外邑[/color]"
	if b.get("combo", "") != "":
		s += "　{i:good} %s" % Defs.combo(b.combo).get("name", "")
	if b.fire > 0:
		s += "　{i:fire} [color=#b1372a][b]失火[/b][/color]"
	elif b.type != "town" and b.type != "yamen" and not b.conn:
		s += "　{i:bad} [color=#b1372a]未通達[/color]"
	return s


func _clamp_cam() -> void:
	var N: int = Game.N
	var lim := Rect2(Vector2(-N * 32.0, 0), Vector2(N * 64.0, N * 32.0))
	cam.position = cam.position.clamp(lim.position, lim.end)


func _unhandled_input(ev: InputEvent) -> void:
	if title_mode:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / 1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				panning = true
				pan_moved = 0.0
			else:
				panning = false
				if mb.button_index == MOUSE_BUTTON_RIGHT and pan_moved < 6.0:
					_cancel()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(to_tile(get_global_mouse_position()))
			else:
				_release(to_tile(get_global_mouse_position()))
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if panning:
			cam.position -= mm.relative / cam.zoom.x
			pan_moved += mm.relative.length()
			_clamp_cam()
		if dragging:
			hover = to_tile(get_global_mouse_position())
			cursor.queue_redraw()
	elif ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_ESCAPE:
				_cancel()
			KEY_SPACE:
				ui.set_speed(0 if Game.speed > 0 else 1)
			KEY_1:
				ui.set_speed(1)
			KEY_2:
				ui.set_speed(2)
			KEY_3:
				ui.set_speed(3)
			KEY_B:
				ui.pick_tool("bulldoze")
			KEY_F5:
				Game.save_game()
			KEY_F9:
				load_saved()


func _zoom_at(f: float, screen_pos: Vector2) -> void:
	var before := get_global_mouse_position()
	var z := clampf(cam.zoom.x * f, 0.3, 2.5)
	cam.zoom = Vector2(z, z)
	var after := get_canvas_transform().affine_inverse() * screen_pos
	cam.position += before - after
	_clamp_cam()


func _cancel() -> void:
	if tool != "":
		set_tool("")
		ui.clear_tool()
	else:
		selected = -1
		selected_vehicle = -1
		selected_tile = Vector2i(-1, -1)
		ui.show_info()
	cursor.queue_redraw()


func _press(t: Vector2i) -> void:
	match tool_kind():
		"line", "rect":
			drag_start = t
			dragging = true
		"place":
			var type := tool.substr(2)
			var s: int = Defs.B[type]["size"]
			var o := t - Vector2i((s - 1) / 2, (s - 1) / 2) if s > 1 else t
			var err := Game.place_building(type, o.x, o.y)
			if err != "":
				ui.toast(err, true)
			else:
				Game.connectivity_dirty = true
				Sfx.play("build")
		"route":
			var b := Game.building_at(t.x, t.y)
			if b.is_empty() or not Game.is_stop(b):
				ui.toast("請點選驛站、碼頭或外邑", true)
				return
			if route_first < 0:
				route_first = b.id
				ui.toast("起點：%s。再點選終點。" % Game.bname(b))
			else:
				var err := Game.create_route(route_first, b.id)
				if err != "":
					ui.toast(err, true)
				else:
					ui.toast("路線已開通！")
					set_tool("")
					ui.clear_tool()
					ui.open_window("routes")
				route_first = -1
		_:
			selected_vehicle = _vehicle_at(to_tile_f(get_global_mouse_position()))
			if selected_vehicle >= 0:
				selected = -1
				selected_tile = Vector2i(-1, -1)
			else:
				var b := Game.building_at(t.x, t.y)
				selected = b.id if not b.is_empty() else -1
				selected_tile = t
			ui.show_info()
	cursor.queue_redraw()


func _release(t: Vector2i) -> void:
	if not dragging:
		return
	dragging = false
	var spent := 0
	match tool:
		"road_dirt":
			spent = Game.build_roads(line_cells(drag_start, t), 1)
		"road_stone":
			spent = Game.build_roads(line_cells(drag_start, t), 2)
		"canal":
			spent = Game.build_canals(line_cells(drag_start, t))
		"wall":
			spent = Game.build_walls(line_cells(drag_start, t))
		"bulldoze":
			var cells := rect_cells(drag_start, t)
			if cells.size() > 1:
				# 範圍拆除不動民間以外之官建，以免誤拆
				for c in cells:
					var b := Game.building_at(c.x, c.y)
					if not b.is_empty() and not Game.is_grow(b):
						continue
					Game.bulldoze(c.x, c.y)
			else:
				var err := Game.bulldoze(t.x, t.y)
				if err != "":
					ui.toast(err, true)
		_:
			if tool.begins_with("zone_"):
				var z := int(tool.substr(5))
				for c in rect_cells(drag_start, t):
					Game.set_zone(c.x, c.y, z)
	if spent > 0:
		ui.toast("花費 %d 兩" % spent)
		Sfx.play("build")
	cursor.queue_redraw()


# ───────────────────────── 截圖自測 ─────────────────────────

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	title_mode = false
	ui.show_title(false)
	if auto:
		_auto_build()
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	await get_tree().process_frame
	print("first frames ms=", Time.get_ticks_msec() - t0)
	for i in 90:
		await get_tree().process_frame
	t0 = Time.get_ticks_msec()
	for i in 60:
		await get_tree().process_frame
	print("city frame ms=", (Time.get_ticks_msec() - t0) / 60.0)
	_shot("01_city.png")
	cam.zoom = Vector2(0.35, 0.35)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	t0 = Time.get_ticks_msec()
	for i in 60:
		await get_tree().process_frame
	print("overview frame ms=", (Time.get_ticks_msec() - t0) / 60.0)
	_shot("02_overview.png")
	cam.zoom = Vector2(1.8, 1.8)
	await get_tree().process_frame
	await get_tree().process_frame
	_shot("03_close.png")
	cam.zoom = Vector2.ONE
	ui.open_window("policy")
	await get_tree().process_frame
	await get_tree().process_frame
	_shot("04_policy.png")
	ui.open_window("routes")
	await get_tree().process_frame
	await get_tree().process_frame
	_shot("05_routes.png")
	ui.close_windows()
	for b in Game.buildings.values():
		if b.type == "house" and b.level >= 2:
			selected = b.id
			break
	ui.show_info()
	world.overlay.mode = "lv"
	world.overlay.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_shot("06_overlay.png")
	ui.show_title(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_shot("07_title.png")
	print("SHOTS DONE pop=%d money=%d rank=%s routes=%d vehicles=%d" % [Game.stats.pop, Game.money, Game.rank_name(), Game.routes.size(), Game.vehicles.size()])
	get_tree().quit()


func _ui_test() -> void:
	# 以程式模擬玩家操作各工具與視窗
	start_new("測試", 777)
	await get_tree().process_frame
	var y: Dictionary = Game.buildings[Game.yamen_id]
	var o := Vector2i(y.x, y.y)
	ui._on_cat("road")
	ui._on_tool("road_dirt")
	_press(o + Vector2i(3, 4))
	_release(o + Vector2i(12, 4))
	_press(o + Vector2i(8, -6))
	_release(o + Vector2i(8, 10))
	ui._on_cat("zone")
	ui._on_tool("zone_1")
	_press(o + Vector2i(3, -6))
	_release(o + Vector2i(12, 3))
	ui._on_tool("zone_4")
	_press(o + Vector2i(3, 5))
	_release(o + Vector2i(12, 7))
	ui._on_tool("zone_2")
	_press(o + Vector2i(9, 8))
	_release(o + Vector2i(9, 10))
	ui._on_cat("civic")
	set_tool("b:well")
	_press(o + Vector2i(5, 3))
	set_tool("b:granary")
	_press(o + Vector2i(6, 3))
	ui._on_cat("view")
	ui._on_view("water")
	ui._on_view("")
	set_tool("bulldoze")
	_press(o + Vector2i(12, 4))
	_release(o + Vector2i(12, 4))
	_cancel()
	_press(o)
	ui.show_info()
	for w in ["stock", "policy", "routes", "help", "stats"]:
		ui.open_window(w)
		for i in 3:
			await get_tree().process_frame
	ui.close_windows()
	Game.toggle_policy("light_tax")
	ui.set_speed(3)
	for i in 120:
		await get_tree().process_frame
	Game.advance_days(30 * 8)
	for i in 30:
		await get_tree().process_frame
	print("ui test pop=", Game.stats.pop, " money=", int(Game.money), " bld=", Game.buildings.size(), " quests=", Game.quests_done.keys())
	ui.open_window("stats")
	for i in 5:
		await get_tree().process_frame
	_shot("09_stats.png")
	ui.close_windows()
	print("save=", Game.save_game())
	var pop: int = Game.stats.pop
	print("load=", load_saved(), " pop match=", Game.stats.pop == pop)
	for i in 60:
		await get_tree().process_frame
	_shot("08_uitest.png")
	print("UI TEST DONE")
	get_tree().quit()


func _gallery() -> void:
	# 在平地上陳列各式建築，供檢視造型
	title_mode = false
	ui.show_title(false)
	Game.speed = 0
	Game.month = int(OS.get_environment("GALLERY_MONTH")) if OS.get_environment("GALLERY_MONTH") != "" else 5
	var ox := 30
	var oy := 30
	for y in range(oy - 2, oy + 14):
		for x in range(ox - 2, ox + 24):
			var i := Game.idx(x, y)
			if Game.bld[i] >= 0:
				Game.remove_building(Game.bld[i])
			Game.terrain[i] = Defs.T.GRASS
			Game.road[i] = 0
			Game.zone[i] = 0
	var rows := [
		[["house", 1], ["house", 1], ["house", 2], ["house", 2], ["house", 3], ["house", 3], ["shop", 1], ["shop", 2], ["shop", 3], ["workshop", 1], ["workshop", 2], ["workshop", 3]],
		[["well", 1], ["granary", 1], ["warehouse", 1], ["constable", 1], ["clinic", 1], ["firewatch", 1], ["school", 1], ["theater", 1], ["garden", 1], ["archway", 1], ["pagoda", 1], ["station", 1]],
		[["yamen", 1], ["temple", 1], ["academy", 1], ["belltower", 1], ["farm", 2], ["farm", 3], ["mulberry", 1], ["kiln", 1], ["lumber", 1], ["fishery", 1]],
	]
	for r in rows.size():
		var x := ox
		for it in rows[r]:
			var size: int = Defs.B[it[0]]["size"] if Defs.B.has(it[0]) else 1
			var id := Game.add_building(it[0], x, oy + r * 4, {"level": it[1], "age": 30})
			Game.tree_var[Game.idx(x, oy + r * 4)] = (x * 37) % 256
			x += size + 1
	Game.build_roads(line_cells(Vector2i(ox - 1, oy + 1), Vector2i(ox + 23, oy + 1)), 2)
	Game.build_roads(line_cells(Vector2i(ox - 1, oy + 5), Vector2i(ox + 23, oy + 5)), 1)
	for i in Game.N * Game.N:
		Game.dirty[i] = true
	cam.zoom = Vector2(2.2, 2.2)
	var focus := OS.get_environment("GALLERY_FOCUS")
	if focus != "":
		cam.zoom = Vector2(4, 4)
		var k := 0
		for b in Game.buildings.values():
			if b.type in focus.split(","):
				cam.position = WorldView.tile_pos(b.x + (b.size - 1) * 0.5, b.y + (b.size - 1) * 0.5) - Vector2(0, 40)
				for f in 6:
					await get_tree().process_frame
				_shot("f_%s.png" % b.type)
				k += 1
		print("GALLERY DONE")
		get_tree().quit()
		return
	for k in 6:
		var cx := ox + 1 + k * 4
		cam.position = WorldView.tile_pos(cx, oy + 2.5)
		for f in 6:
			await get_tree().process_frame
		_shot("g%d.png" % k)
	print("GALLERY DONE")
	get_tree().quit()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots.path_join(name))


func _find_spot(type: String, c: Vector2i, r: int, rmin: int = 0) -> Vector2i:
	for d in range(rmin, r + 1):
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				if Game.valid_place(type, c.x + dx, c.y + dy) == "":
					return Vector2i(c.x + dx, c.y + dy)
	return Vector2i(-1, -1)


func _auto_build() -> void:
	# 自動造一座城以檢驗模擬與畫面
	var y: Dictionary = Game.buildings[Game.yamen_id]
	var ox: int = y.x
	var oy: int = y.y
	Game.money = 60000
	for k in range(-2, 5):
		Game.build_roads(line_cells(Vector2i(ox - 3, oy + 2 + k * 4), Vector2i(ox + 14, oy + 2 + k * 4)), 1)
	for k in range(0, 5):
		Game.build_roads(line_cells(Vector2i(ox + 2 + k * 4, oy - 8), Vector2i(ox + 2 + k * 4, oy + 18)), 1)
	for c in rect_cells(Vector2i(ox - 3, oy - 8), Vector2i(ox + 18, oy + 6)):
		Game.set_zone(c.x, c.y, 1)
	for c in rect_cells(Vector2i(ox - 3, oy + 7), Vector2i(ox + 18, oy + 10)):
		Game.set_zone(c.x, c.y, 2)
	for c in rect_cells(Vector2i(ox - 3, oy + 11), Vector2i(ox + 18, oy + 14)):
		Game.set_zone(c.x, c.y, 3)
	for c in rect_cells(Vector2i(ox - 3, oy + 15), Vector2i(ox + 18, oy + 21)):
		Game.set_zone(c.x, c.y, 4)
	Game.advance_days(5)
	for p in [[3, -3], [7, 1], [11, -3], [-1, 5], [11, 5], [15, 1]]:
		Game.place_building("well", ox + p[0], oy + p[1])
	Game.place_building("granary", ox + 5, oy + 3)
	Game.place_building("granary", ox + 9, oy + 3)
	Game.advance_days(30 * 14)
	var cen := Vector2i(ox + 6, oy + 3)
	for t in ["clinic", "constable", "school", "firewatch", "temple", "theater", "garden", "garden", "warehouse", "archway", "well", "well"]:
		var sp := _find_spot(t, cen, 14)
		if sp.x >= 0:
			Game.place_building(t, sp.x, sp.y)
	Game.advance_days(30 * 24)
	# 車路：城內驛站 → 最近的外邑
	var st_pos := _find_spot("station", cen, 12)
	Game.place_building("station", st_pos.x, st_pos.y)
	var st: Dictionary = Game.building_at(st_pos.x, st_pos.y)
	var best_town := {}
	for b in Game.buildings.values():
		if b.type == "town" and Game.stop_cell(b, "road") != Game.NO_CELL:
			if best_town.is_empty() or absi(b.x - ox) + absi(b.y - oy) < absi(best_town.x - ox) + absi(best_town.y - oy):
				best_town = b
	Game.build_roads(line_cells(Game.stop_cell(best_town, "road"), Game.stop_cell(st, "road")), 1)
	Game.connectivity_dirty = true
	print("cart route: ", Game.create_route(st.id, best_town.id), " to ", best_town.name)
	# 水路：碼頭 → 揚州
	var dk_pos := _find_spot("dock", cen, 14)
	if dk_pos.x >= 0:
		Game.place_building("dock", dk_pos.x, dk_pos.y)
		var dk: Dictionary = Game.building_at(dk_pos.x, dk_pos.y)
		for b in Game.buildings.values():
			if b.type == "town" and Game.stop_cell(b, "water") != Game.NO_CELL:
				print("boat route: ", Game.create_route(dk.id, b.id), " to ", b.name)
				break
	# 遠方產業：伐木場 + 驛站，運回城內
	var lm := _find_spot("lumber", cen, 30, 10)
	if lm.x >= 0:
		Game.place_building("lumber", lm.x, lm.y)
		var s2 := _find_spot("station", lm, 3)
		if s2.x < 0:
			var rc := line_cells(lm + Vector2i(1, 0), lm + Vector2i(1, 3))
			Game.build_roads(rc, 1)
			s2 = _find_spot("station", lm, 3)
		Game.place_building("station", s2.x, s2.y)
		var sb2: Dictionary = Game.building_at(s2.x, s2.y)
		Game.build_roads(line_cells(Game.stop_cell(sb2, "road"), Game.stop_cell(st, "road")), 1)
		print("lumber route: ", Game.create_route(sb2.id, st.id), " lumber conn=", Game.building_at(lm.x, lm.y).conn)
	Game.advance_days(30 * 8)
	for r in Game.routes.values():
		print("route %s->%s income=%d last=%d" % [Game.bname(Game.buildings[r.a]), Game.bname(Game.buildings[r.b]), r.total, r.last])
	for v in Game.vehicles.values():
		print("  veh ", v.kind, " ", v.state, " cargo=", v.cargo, " amt=", v.amt, " pos=", v.pos)
	print("auto: pop=%d happy=%d money=%d stock=%s" % [Game.stats.pop, Game.stats.happy, Game.money, str(Game.stock)])
	print("report: ", Game.report)


# ───────────────────────── 游標預覽 ─────────────────────────

class Cursor extends Node2D:
	var main

	func _process(_d: float) -> void:
		if main.selected >= 0 or main.selected_vehicle >= 0 or main.tool == "route" or main.ui.window_open("routes"):
			queue_redraw()

	func _diamond(t: Vector2i, col: Color, fill: bool = true) -> void:
		var c := Vector2((t.x - t.y) * 32.0, (t.x + t.y) * 16.0)
		var pts := PackedVector2Array([c + Art.iso(-0.5, -0.5), c + Art.iso(0.5, -0.5), c + Art.iso(0.5, 0.5), c + Art.iso(-0.5, 0.5)])
		if fill:
			draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Color(col, 0.9), 1.5)

	func _rect_outline(x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
		var pts := PackedVector2Array([Art.iso(x0, y0), Art.iso(x1, y0), Art.iso(x1, y1), Art.iso(x0, y1), Art.iso(x0, y0)])
		draw_polyline(pts, col, 2.0)

	func _circle(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for k in 49:
			var a := k / 48.0 * TAU
			pts.append(Art.iso(c.x + cos(a) * r, c.y + sin(a) * r))
		draw_colored_polygon(pts, Color(col, 0.12))
		draw_polyline(pts, Color(col, 0.7), 1.5)

	func _draw() -> void:
		var g = Game
		var m = main
		# 路線
		var show_routes: bool = m.ui.window_open("routes") or m.tool == "route"
		for r in g.routes.values():
			var sv: Dictionary = g.vehicles.get(m.selected_vehicle, {})
			var hl: bool = show_routes or r.a == m.selected or r.b == m.selected or (not sv.is_empty() and sv.route == r.id)
			if not hl:
				continue
			var a: Dictionary = g.buildings.get(r.a, {})
			var b: Dictionary = g.buildings.get(r.b, {})
			if a.is_empty() or b.is_empty():
				continue
			var p: Array = g.find_path(r.mode, g.stop_cell(a, r.mode), g.stop_cell(b, r.mode))
			var pts := PackedVector2Array()
			for c in p:
				pts.append(Art.iso(c.x, c.y))
			if pts.size() > 1:
				draw_polyline(pts, Color(r.color, 0.8), 3.0)
		if g.vehicles.has(m.selected_vehicle):
			var vp: Vector2 = g.vehicles[m.selected_vehicle].pos
			var c := Art.iso(vp.x, vp.y)
			draw_arc(c - Vector2(0, 6), 14.0, 0, TAU, 32, Color(1, 0.9, 0.3), 2.0)
		if m.selected >= 0 and g.buildings.has(m.selected):
			var b: Dictionary = g.buildings[m.selected]
			_rect_outline(b.x - 0.5, b.y - 0.5, b.x + b.size - 0.5, b.y + b.size - 0.5, Color(1, 0.9, 0.3))
			var d: Dictionary = Defs.B.get(b.type, {})
			if d.has("catch"):
				var r: int = d.catch
				_rect_outline(b.x - r - 0.5, b.y - r - 0.5, b.x + r + 0.5, b.y + r + 0.5, Color(0.3, 0.6, 1.0))
			if d.has("cover"):
				var k: String = d.cover.keys()[0]
				_circle(g.b_center(b), d.cover[k], Color(0.3, 0.8, 0.4))
		elif m.selected_tile.x >= 0 and m.tool == "":
			_diamond(m.selected_tile, Color(1, 0.9, 0.3, 0.2))
		var h: Vector2i = m.hover
		if not g.inb(h.x, h.y):
			return
		if m.bot_mode:
			# 示範影片用的游標
			var ap := Art.iso(h.x, h.y) + Vector2(4, -6)
			var arrow := PackedVector2Array([ap, ap + Vector2(0, 17), ap + Vector2(4.5, 13), ap + Vector2(8, 20), ap + Vector2(10.5, 19), ap + Vector2(7, 12), ap + Vector2(12.5, 12)])
			draw_colored_polygon(arrow, Color(0.08, 0.06, 0.05))
			arrow.append(arrow[0])
			draw_polyline(arrow, Color(1, 0.97, 0.9), 1.5)
		match m.tool_kind():
			"line":
				var cells: Array = m.line_cells(m.drag_start, h) if m.dragging else [h]
				var total := 0
				for c in cells:
					var ok := true
					var cost := 0
					match m.tool:
						"road_dirt":
							cost = g.road_cost(c.x, c.y, 1)
							ok = cost >= 0
						"road_stone":
							cost = g.road_cost(c.x, c.y, 2)
							ok = cost >= 0
						"canal":
							ok = g.inb(c.x, c.y) and g.bld[g.idx(c.x, c.y)] < 0 and g.road[g.idx(c.x, c.y)] == 0 and g.terrain[g.idx(c.x, c.y)] != Defs.T.MOUNTAIN
							cost = 40
						"wall":
							ok = g.inb(c.x, c.y) and g.bld[g.idx(c.x, c.y)] < 0 and g.terrain[g.idx(c.x, c.y)] != Defs.T.WATER
							cost = 20
					total += maxi(cost, 0)
					_diamond(c, Color(0.3, 0.9, 0.4, 0.35) if ok else Color(0.95, 0.25, 0.2, 0.35))
				var e: Vector2i = h
				Art.label(self, Art.iso(e.x, e.y) - Vector2(0, 26), "%d 兩" % total, 15, Color(0.15, 0.08, 0.05))
			"rect":
				var cells: Array = m.rect_cells(m.drag_start, h) if m.dragging else [h]
				var col := Color(0.95, 0.3, 0.2, 0.35)
				if m.tool.begins_with("zone_"):
					var z := int(m.tool.substr(5))
					col = Defs.ZONE_COLORS[z] if z > 0 else Color(0.5, 0.5, 0.5, 0.35)
					for c in cells:
						if z == 0 or g.can_zone(c.x, c.y, z):
							_diamond(c, Color(col, 0.55))
						else:
							_diamond(c, Color(0.6, 0.6, 0.6, 0.12), false)
				else:
					for c in cells:
						_diamond(c, col)
			"place":
				var type: String = m.tool.substr(2)
				var d: Dictionary = Defs.B[type]
				var s: int = d.size
				var o: Vector2i = h - Vector2i((s - 1) / 2, (s - 1) / 2) if s > 1 else h
				var err: String = g.valid_place(type, o.x, o.y)
				for dy in s:
					for dx in s:
						_diamond(o + Vector2i(dx, dy), Color(0.3, 0.9, 0.4, 0.35) if err == "" else Color(0.95, 0.25, 0.2, 0.4))
				var cc := Vector2(o.x + (s - 1) * 0.5, o.y + (s - 1) * 0.5)
				if d.has("cover"):
					var k: String = d.cover.keys()[0]
					_circle(cc, d.cover[k], Color(0.3, 0.8, 0.4))
				if d.has("catch"):
					var r: int = d.catch
					_rect_outline(o.x - r - 0.5, o.y - r - 0.5, o.x + r + s - 0.5, o.y + r + s - 0.5, Color(0.3, 0.6, 1.0))
				var lp := Art.iso(cc.x, cc.y) - Vector2(0, 40 + s * 10)
				Art.label(self, lp, err if err != "" else "%s　%d 兩" % [d.name, d.cost], 15, Color(0.6, 0.1, 0.05) if err != "" else Color(0.1, 0.25, 0.1))
			"route":
				var b: Dictionary = g.building_at(h.x, h.y)
				var ok: bool = not b.is_empty() and g.is_stop(b)
				_diamond(h, Color(0.3, 0.6, 1.0, 0.4) if ok else Color(0.6, 0.6, 0.6, 0.2))
				if m.route_first >= 0 and g.buildings.has(m.route_first):
					var a: Dictionary = g.buildings[m.route_first]
					draw_line(Art.iso(a.x, a.y), Art.iso(h.x, h.y), Color(0.3, 0.6, 1.0, 0.8), 2.0)
			_:
				_diamond(h, Color(1, 1, 1, 0.15))
