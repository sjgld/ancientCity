extends Node
## 自動遊玩：以真實的工具操作（拖路、劃區、建屋、開路線）玩一局，供錄製示範影片。
## 啟動：Godot --path . --write-movie out.avi --fixed-fps 30 -- --autoplay

const WorldView = preload("res://scripts/view/world_view.gd")
const FPS := 30.0
const LENGTH := 260.0  # 影片長度（秒）

var main
var ui
var frames := 0
var ox := 0
var oy := 0
var used := {}
var road_done := {}
var done := {}


func _process(_d: float) -> void:
	frames += 1


func elapsed() -> float:
	return frames / FPS


func wait(sec: float) -> void:
	for i in maxi(1, int(sec * FPS)):
		await get_tree().process_frame


func say(text: String) -> void:
	ui.toast(text)


func cam_to(t: Vector2, z: float, sec: float) -> void:
	var p0: Vector2 = main.cam.position
	var p1 := WorldView.tile_pos(t.x, t.y)
	var z0: float = main.cam.zoom.x
	var n := maxi(1, int(sec * FPS))
	for k in n:
		var s := smoothstep(0.0, 1.0, (k + 1) / float(n))
		main.cam.position = p0.lerp(p1, s)
		var zz := lerpf(z0, z, s)
		main.cam.zoom = Vector2(zz, zz)
		await get_tree().process_frame


func hover(t: Vector2i) -> void:
	main.hover = t
	main.cursor.queue_redraw()


func use_tool(cat: String, id: String) -> void:
	if ui.cur_cat != cat:
		ui._on_cat(cat)
	main.set_tool(id)
	ui._fill_palette()


func drag(cat: String, id: String, a: Vector2i, b: Vector2i, sec: float = 0.8) -> void:
	use_tool(cat, id)
	hover(a)
	await wait(0.25)
	main._press(a)
	var n := maxi(1, int(sec * FPS))
	for k in n:
		var t := (k + 1) / float(n)
		hover(Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t))))
		await get_tree().process_frame
	main._release(b)
	await wait(0.2)


func place(type: String, at: Vector2i) -> bool:
	var cat: String = Defs.B[type]["cat"]
	use_tool(cat, "b:" + type)
	await cam_to(Vector2(at), main.cam.zoom.x, 0.5)
	hover(at)
	await wait(0.5)
	var ok: bool = Game.valid_place(type, at.x, at.y) == ""
	main._press(at)
	await wait(0.35)
	return ok


func done_tool() -> void:
	main.set_tool("")
	ui.clear_tool()
	ui.cur_cat = ""
	ui.palette_wrap.visible = false


# ───────────────────────── 城市規劃 ─────────────────────────

## 街區寬窄不一：道路間距輪流取下表，街區內部有二、三、四格等大小，城市才不會是一格格棋盤。
const SPAN := [4, 3, 5, 3, 4, 5]


func _cum(i: int, phase: int) -> int:
	var s := 0
	if i >= 0:
		for k in i:
			s += SPAN[(k + phase) % SPAN.size()]
	else:
		for k in range(i, 0):
			s -= SPAN[posmod(k + phase, SPAN.size())]
	return s


func gx(i: int) -> int:
	return ox + 2 + _cum(i, 0)


func gy(j: int) -> int:
	return oy + 2 + _cum(j, 3)


func build_block(b: Vector2i, z: int) -> void:
	used[b] = z
	print("t=%.0f block %s zone %d info %s money %d" % [elapsed(), b, z, block_info(b), Game.money])
	var x0 := gx(b.x)
	var x1 := gx(b.x + 1)
	var y0 := gy(b.y)
	var y1 := gy(b.y + 1)
	await cam_to(Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5), 1.25, 0.7)
	for seg in [[Vector2i(x0, y0), Vector2i(x1, y0)], [Vector2i(x1, y0), Vector2i(x1, y1)],
			[Vector2i(x0, y1), Vector2i(x1, y1)], [Vector2i(x0, y0), Vector2i(x0, y1)]]:
		var key := "%s-%s" % [seg[0], seg[1]]
		if road_done.has(key):
			continue
		road_done[key] = true
		var need := false
		for c in main.line_cells(seg[0], seg[1]):
			if Game.inb(c.x, c.y) and Game.road[Game.idx(c.x, c.y)] == 0:
				need = true
		if need:
			await drag("road", "road_dirt", seg[0], seg[1], 0.5)
	await drag("zone", "zone_%d" % z, Vector2i(x0 + 1, y0 + 1), Vector2i(x1 - 1, y1 - 1), 0.6)
	done_tool()


## 評估一個街區：四邊道路能否修（不穿山、少架橋），內部可建之地多寡。
func block_info(b: Vector2i) -> Dictionary:
	var x0 := gx(b.x)
	var x1 := gx(b.x + 1)
	var y0 := gy(b.y)
	var y1 := gy(b.y + 1)
	var info := {"valid": false, "buildable": 0, "flat": 0, "fert": 0.0, "bridges": 0, "dist": absi(b.x) + absi(b.y)}
	for seg in [[Vector2i(x0, y0), Vector2i(x1, y0)], [Vector2i(x1, y0), Vector2i(x1, y1)],
			[Vector2i(x0, y1), Vector2i(x1, y1)], [Vector2i(x0, y0), Vector2i(x0, y1)]]:
		for c in main.line_cells(seg[0], seg[1]):
			if not Game.inb(c.x, c.y):
				return info
			var i := Game.idx(c.x, c.y)
			if Game.road[i] > 0:
				continue
			if Game.terrain[i] == Defs.T.MOUNTAIN or Game.bld[i] >= 0:
				return info
			if Game.terrain[i] == Defs.T.WATER:
				info.bridges += 1
	if info.bridges > 2:
		return info
	for y in range(y0 + 1, y1):
		for x in range(x0 + 1, x1):
			var i := Game.idx(x, y)
			var t: int = Game.terrain[i]
			if t == Defs.T.WATER or t == Defs.T.MOUNTAIN or Game.bld[i] >= 0:
				continue
			info.buildable += 1
			if t != Defs.T.HILL:
				info.flat += 1
				info.fert += Game.fert[i]
	info.valid = info.buildable >= 4
	return info


func pick_block(z: int) -> Vector2i:
	var best := Vector2i(999, 999)
	var best_score := -INF
	for j in range(-6, 7):
		for i in range(-6, 7):
			var b := Vector2i(i, j)
			if used.has(b):
				continue
			var adj := false
			for d in Game.DIRS:
				if used.has(b + d):
					adj = true
			if not adj:
				continue
			var info := block_info(b)
			if not info.valid:
				continue
			# 轄境：街區中心沿路約在範圍之內
			if (absi((gx(i) + gx(i + 1)) / 2 - ox) + absi((gy(j) + gy(j + 1)) / 2 - oy)) > Game.radius() - 4:
				continue
			var score := 0.0
			match z:
				1:
					score = info.buildable * 1.0 - info.dist * 2.0
				2:
					score = info.buildable * 0.5 - info.dist * 3.0
				3:
					score = info.buildable * 1.0 + info.dist * 1.5 - _near_houses(b) * 2.0
				4:
					if info.flat < 6:
						continue
					score = info.fert * 2.0 + info.flat - info.dist * 1.0
			score -= info.bridges * 3.0
			if score > best_score:
				best_score = score
				best = b
	return best


func _near_houses(b: Vector2i) -> int:
	var n := 0
	for u in used:
		if used[u] == 1 and (u - b).length() < 1.6:
			n += 1
	return n


func free_cells(z: int) -> int:
	var n := 0
	for i in Game.N * Game.N:
		if Game.zone[i] == z and Game.bld[i] < 0 and Game._grow_ok(i % Game.N, i / Game.N, z):
			n += 1
	return n


func next_block(z: int) -> bool:
	if Game.money < 400:
		return false
	var b := pick_block(z)
	if b.x == 999:
		return false
	await build_block(b, z)
	return true


func find_spot(type: String, c: Vector2i, r: int, need_road: bool = false) -> Vector2i:
	for d in r + 1:
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				var x := c.x + dx
				var y := c.y + dy
				if Game.valid_place(type, x, y) != "":
					continue
				if need_road:
					var ok := false
					for dd in Game.DIRS:
						if Game.inb(x + dd.x, y + dd.y) and Game.conn_road(Game.idx(x + dd.x, y + dd.y)):
							ok = true
					if not ok:
						continue
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## 為缺某項服務的民居就近設施。
func serve(type: String, key: String, min_lacking: int) -> bool:
	var d: Dictionary = Defs.B[type]
	if d.rank > Game.rank or Game.money < d.cost + 300:
		return false
	var lacking := []
	for b in Game.buildings.values():
		if b.type == "house" and b.conn and Game.cover[key][Game.idx(b.x, b.y)] == 0:
			lacking.append(b)
	if lacking.size() < min_lacking:
		return false
	var h: Dictionary = lacking[lacking.size() / 2]
	var sp := find_spot(type, Vector2i(h.x, h.y), 4, true)
	if sp.x < 0:
		return false
	say("%s：%s" % [d.name, d.desc])
	await place(type, sp)
	done_tool()
	Game._compute_cover()
	return true


func road_path(a: Vector2i, b: Vector2i) -> Array:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, Game.N, Game.N)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	g.update()
	for y in Game.N:
		for x in Game.N:
			var i := Game.idx(x, y)
			if Game.terrain[i] == Defs.T.MOUNTAIN or (Game.bld[i] >= 0 and Game.road[i] == 0):
				g.set_point_solid(Vector2i(x, y), true)
			elif Game.road[i] > 0:
				g.set_point_weight_scale(Vector2i(x, y), 0.3)
			elif Game.terrain[i] == Defs.T.WATER:
				g.set_point_weight_scale(Vector2i(x, y), 6.0)
			elif Game.terrain[i] == Defs.T.HILL:
				g.set_point_weight_scale(Vector2i(x, y), 2.0)
	return Array(g.get_id_path(a, b))


func open_trade() -> bool:
	if Game.rank < 1 or Game.money < 1800 or done.has("trade"):
		return false
	done["trade"] = true
	say("開闢商路：以牛車將城中餘糧運往外邑販售")
	var sp := find_spot("station", Vector2i(gx(1), gy(0)), 6, true)
	print("trade: station spot ", sp)
	if sp.x < 0:
		return false
	await place("station", sp)
	done_tool()
	var st: Dictionary = Game.building_at(sp.x, sp.y)
	var towns := []
	for b in Game.buildings.values():
		if b.type == "town" and Game.stop_cell(b, "road") != Game.NO_CELL:
			towns.append(b)
	towns.sort_custom(func(p, q): return absi(p.x - ox) + absi(p.y - oy) < absi(q.x - ox) + absi(q.y - oy))
	var town := {}
	var path := []
	for b in towns:
		path = road_path(Game.stop_cell(st, "road"), Game.stop_cell(b, "road"))
		print("trade: try ", b.name, " path ", path.size())
		if not path.is_empty():
			town = b
			break
	if path.is_empty():
		return false
	# 沿途分段拖路，鏡頭跟著走
	var k := 0
	while k < path.size() - 1:
		var k2 := mini(k + 10, path.size() - 1)
		await cam_to(Vector2(path[k2]), 1.0, 0.4)
		use_tool("road", "road_dirt")
		Game.build_roads(path.slice(k, k2 + 1), 1)
		hover(path[k2])
		await wait(0.15)
		k = k2
	done_tool()
	Game.connectivity_dirty = true
	await cam_to(Vector2(sp), 1.1, 1.0)
	use_tool("transport", "route")
	hover(sp)
	await wait(0.4)
	main._press(sp)
	await cam_to(Vector2(town.x, town.y), 0.9, 1.0)
	hover(Vector2i(town.x, town.y))
	await wait(0.4)
	main._press(Vector2i(town.x, town.y))
	print("trade: routes ", Game.routes.size())
	await wait(0.5)
	main.set_tool("")
	await wait(2.5)
	ui.close_windows()
	return true


func open_water() -> bool:
	if Game.rank < 1 or Game.money < 2000 or done.has("water"):
		return false
	done["water"] = true
	var sp := Vector2i(-1, -1)
	var bd := 999
	for y in range(oy - 14, oy + 15):
		for x in range(ox - 14, ox + 15):
			if Game.valid_place("dock", x, y) != "":
				continue
			var near := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if Game.inb(x + dx, y + dy) and Game.conn_road(Game.idx(x + dx, y + dy)):
						near = true
			var d := absi(x - ox) + absi(y - oy)
			if near and d < bd:
				bd = d
				sp = Vector2i(x, y)
	print("water: dock spot ", sp)
	if sp.x < 0:
		return false
	say("修建碼頭，漕船順流而下，直抵揚州")
	await place("dock", sp)
	done_tool()
	var dk: Dictionary = Game.building_at(sp.x, sp.y)
	for b in Game.buildings.values():
		if b.type == "town" and Game.stop_cell(b, "water") != Game.NO_CELL:
			print("water: route ", Game.create_route(dk.id, b.id))
			break
	return true


func follow_vehicle(sec: float) -> void:
	if Game.vehicles.is_empty():
		return
	var v: Dictionary = Game.vehicles.values()[0]
	main.selected_vehicle = v.id
	ui.show_info()
	var n := int(sec * FPS)
	await cam_to(v.pos, 1.6, 1.0)
	for k in n:
		var target := WorldView.tile_pos(v.pos.x, v.pos.y)
		main.cam.position = main.cam.position.lerp(target, 0.15)
		await get_tree().process_frame
	main.selected_vehicle = -1
	ui.show_info()


# ───────────────────────── 主流程 ─────────────────────────

func run() -> void:
	ui = main.ui
	main.bot_mode = true
	await wait(4.0)
	ui.name_edit.text = "清河"
	await wait(1.0)
	main.start_new("清河", 4242)
	var y: Dictionary = Game.buildings[Game.yamen_id]
	ox = y.x
	oy = y.y
	Game.speed = 1
	used[Vector2i(-1, -1)] = 0
	await cam_to(Vector2(ox + 1, oy + 1), 1.3, 1.5)
	say("宣和元年，奉旨築城。先修道路、劃民居")
	await wait(2.0)
	await next_block(1)
	say("擇肥沃平地，開墾農田")
	await next_block(4)
	await next_block(1)
	say("劃設市肆，百姓方有買賣之處")
	await next_block(2)
	Game.speed = 3
	await wait(4.0)
	await serve("well", "water", 1)
	var sp := find_spot("granary", Vector2i(gx(0) + 1, gy(0) + 1), 5, true)
	if sp.x >= 0:
		say("修糧倉以存秋糧，否則冬日無以為繼")
		await place("granary", sp)
		done_tool()
	await next_block(3)
	var showed := {}
	var last_rank := 0
	while elapsed() < LENGTH - 25.0:
		Game.speed = 3
		await wait(1.6)
		if Game.rank != last_rank:
			last_rank = Game.rank
			await wait(3.0)
		var s: Dictionary = Game.stats
		var acted := false
		if Game.food_short > 0.05 or s.dF > 45:
			acted = await next_block(4)
		elif s.dR > 20 and free_cells(1) < 8:
			acted = await next_block(1)
		elif s.dC > 35 and free_cells(2) < 3:
			acted = await next_block(2)
		elif s.dI > 35 and free_cells(3) < 3:
			acted = await next_block(3)
		if acted:
			continue
		if await open_trade():
			print("t=%.0f action trade" % elapsed())
			if not showed.has("routes"):
				showed["routes"] = true
				ui.open_window("routes")
				await wait(3.0)
				ui.close_windows()
				await follow_vehicle(6.0)
			continue
		if await open_water():
			print("t=%.0f action water" % elapsed())
			continue
		if Game.rank >= 1 and not done.has("silk") and Game.money > 900:
			done["silk"] = true
			var m := find_spot("mulberry", Vector2i(gx(3), gy(2)), 8, true)
			if m.x >= 0:
				say("種桑養蠶，作坊便可織出綢緞")
				await place("mulberry", m)
				var m2 := find_spot("mulberry", m, 4, true)
				if m2.x >= 0:
					await place("mulberry", m2)
				done_tool()
				continue
		if Game.rank >= 1 and not done.has("policy") and Game.money > 1500:
			done["policy"] = true
			say("頒行政令：勸課農桑")
			ui.open_window("policy")
			await wait(2.0)
			Game.toggle_policy("farming")
			ui.close_windows()
			ui.open_window("policy")
			await wait(2.0)
			ui.close_windows()
			continue
		if Game.rank >= 1 and not done.has("garden") and Game.money > 1200:
			done["garden"] = true
			say("點綴園林，提升地價")
			for k in 3:
				var hs := []
				for b in Game.buildings.values():
					if b.type == "house" and b.level >= 2:
						hs.append(b)
				if hs.is_empty():
					break
				var h: Dictionary = hs[(k * 7) % hs.size()]
				var gp := find_spot("garden", Vector2i(h.x, h.y), 3)
				if gp.x >= 0:
					await place("garden", gp)
			done_tool()
			continue
		if Game.rank >= 2 and not done.has("arch") and Game.money > 1500:
			done["arch"] = true
			var ap := find_spot("archway", Vector2i(gx(0), gy(-1)), 5, true)
			if ap.x >= 0:
				say("立牌坊以壯觀瞻")
				await place("archway", ap)
				done_tool()
				continue
		for pair in [["well", "water", 2], ["clinic", "health", 4], ["firewatch", "fire", 5], ["constable", "security", 5],
				["school", "edu", 6], ["temple", "faith", 10], ["theater", "fun", 10]]:
			if await serve(pair[0], pair[1], pair[2]):
				print("t=%.0f action serve %s" % [elapsed(), pair[0]])
				acted = true
				break
		if acted:
			continue
		if Game.cap_of("grain") < s.pop * 0.2 * 5 + 250 and Game.money > 600:
			var g := find_spot("granary", Vector2i(gx(1), gy(1)), 8, true)
			if g.x >= 0:
				print("t=%.0f action granary" % elapsed())
				await place("granary", g)
				done_tool()
				continue
		if not showed.has("stats") and elapsed() > LENGTH * 0.6:
			showed["stats"] = true
			ui.open_window("stats")
			await wait(3.5)
			ui.close_windows()
			continue
		if not showed.has("overview") and elapsed() > LENGTH * 0.45:
			showed["overview"] = true
			await cam_to(Vector2(ox + 6, oy + 2), 0.55, 2.5)
			await wait(2.5)
			await cam_to(Vector2(ox + 4, oy), 1.2, 2.0)
			continue
	# 尾聲
	done_tool()
	Game.speed = 1
	say("%s · %s　人丁 %d" % [Game.city_name, Game.rank_name(), Game.stats.pop])
	await cam_to(Vector2(ox + 4, oy - 2), 1.8, 3.0)
	await wait(3.0)
	await cam_to(Vector2(ox + 5, oy + 2), 0.45, 5.0)
	ui.banner("上河築城 · 一局實錄")
	await wait(5.0)
	print("AUTOPLAY DONE t=%.1f pop=%d rank=%s money=%d routes=%d" % [elapsed(), Game.stats.pop, Game.rank_name(), Game.money, Game.routes.size()])
	get_tree().quit()
