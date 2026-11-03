extends Node2D
## 世界畫面：地面分塊、按對角線排序之物件層、車船行人、煙火天氣與資料圖層。

const Art = preload("res://scripts/art.gd")
const Batch = preload("res://scripts/batch.gd")
const CH := 10
const SEG := 16

var objects: Node2D
var ground_root: Node2D
var overlay: Overlay
var fx: FX
var ground_chunks: Array = []
var obj_chunks := {}
var movers := {}
var walkers: Array = []
var road_cells: Array = []
var road_cells_t := 0.0
var last_season := -1
var last_rank := -1
var cam: Camera2D


static func tile_pos(x: float, y: float) -> Vector2:
	return Vector2((x - y) * Art.TW * 0.5, (x + y) * Art.TH * 0.5)


func setup(camera: Camera2D) -> void:
	cam = camera
	for c in get_children():
		c.queue_free()
	ground_chunks.clear()
	obj_chunks.clear()
	movers.clear()
	walkers.clear()
	var N: int = Game.N
	ground_root = Node2D.new()
	add_child(ground_root)
	var nch := ceili(N / float(CH))
	for cy in nch:
		for cx in nch:
			var g := GroundChunk.new()
			g.cx = cx
			g.cy = cy
			ground_root.add_child(g)
			ground_chunks.append(g)
	objects = Node2D.new()
	objects.y_sort_enabled = true
	add_child(objects)
	for d in 2 * N - 1:
		for sg in range(maxi(0, d - N + 1) / SEG, mini(d, N - 1) / SEG + 1):
			var oc := ObjChunk.new()
			oc.d = d
			oc.seg = sg
			oc.position = Vector2(0, d * Art.TH * 0.5)
			objects.add_child(oc)
			obj_chunks[d * 8 + sg] = oc
	overlay = Overlay.new()
	add_child(overlay)
	fx = FX.new()
	fx.view = self
	add_child(fx)
	last_season = -1


func _process(delta: float) -> void:
	if not Game.running or objects == null:
		return
	if Game.season() != last_season:
		last_season = Game.season()
		Art.season = last_season
	if Game.rank != last_rank:
		last_rank = Game.rank
		Art.rank = last_rank
		if Game.buildings.has(Game.yamen_id):
			Game.mark_b(Game.buildings[Game.yamen_id])
	if not Game.dirty.is_empty():
		var N: int = Game.N
		var nch := ceili(N / float(CH))
		var gset := {}
		var oset := {}
		for i in Game.dirty:
			var x: int = i % N
			var y: int = i / N
			gset[(y / CH) * nch + x / CH] = true
			oset[(x + y) * 8 + x / SEG] = true
		Game.dirty.clear()
		for k in gset:
			ground_chunks[k].queue_redraw()
		for k in oset:
			if obj_chunks.has(k):
				obj_chunks[k].queue_redraw()
		overlay.queue_redraw()
	_sync_movers()
	_update_walkers(delta)


func redraw_all() -> void:
	for g in ground_chunks:
		g.queue_redraw()
	for o in obj_chunks.values():
		o.queue_redraw()
	overlay.queue_redraw()


func _sync_movers() -> void:
	for id in movers.keys():
		if not Game.vehicles.has(id):
			movers[id].queue_free()
			movers.erase(id)
	for v in Game.vehicles.values():
		var m: Mover = movers.get(v.id)
		if m == null:
			m = Mover.new()
			m.kind = v.kind
			objects.add_child(m)
			movers[v.id] = m
		var p: Vector2 = v.pos
		m.position = tile_pos(p.x, p.y) + Vector2(0, 1)
		var col: Color = Defs.CARGO[v.cargo]["color"] if v.cargo != "" else Color.WHITE
		var loaded: bool = v.amt > 0
		if m.dir != v.dir or m.loaded != loaded or m.cargo_col != col:
			m.dir = v.dir
			m.loaded = loaded
			m.cargo_col = col
			m.queue_redraw()


func _update_walkers(delta: float) -> void:
	road_cells_t -= delta
	if road_cells_t <= 0:
		road_cells_t = 3.0
		road_cells.clear()
		for i in Game.N * Game.N:
			if Game.road[i] > 0 and Game.terrain[i] != Defs.T.WATER and Game.conn_road(i):
				road_cells.append(i)
	var want := mini(70, int(Game.stats.pop / 12))
	if road_cells.is_empty():
		want = 0
	while walkers.size() < want:
		var w := Mover.new()
		w.kind = "walker"
		w.v = randi() % 50
		var i: int = road_cells[randi() % road_cells.size()]
		w.tile = Vector2i(i % Game.N, i / Game.N)
		w.target = w.tile
		w.off = Vector2(randf_range(-0.18, 0.18), randf_range(-0.18, 0.18))
		w.fpos = Vector2(w.tile)
		w.life = randf_range(20, 60)
		objects.add_child(w)
		walkers.append(w)
	var spd: float = Game.SPEEDS[Game.speed] * delta * 0.9
	for w in walkers.duplicate():
		w.life -= delta
		if walkers.size() > want or w.life <= 0 or not Game.inb(w.target.x, w.target.y) \
				or Game.road[Game.idx(w.target.x, w.target.y)] == 0:
			walkers.erase(w)
			w.queue_free()
			continue
		var tgt := Vector2(w.target)
		var d: Vector2 = tgt - w.fpos
		if d.length() <= spd:
			w.fpos = tgt
			w.tile = w.target
			var opts := []
			for dd in Game.DIRS:
				var n: Vector2i = w.tile + dd
				if Game.inb(n.x, n.y) and Game.road[Game.idx(n.x, n.y)] > 0 and n != w.prev:
					opts.append(n)
			w.prev = w.tile
			w.target = opts[randi() % opts.size()] if opts.size() > 0 else w.prev
		else:
			w.fpos += d.normalized() * spd
		var p: Vector2 = w.fpos + w.off
		w.position = tile_pos(p.x, p.y) + Vector2(0, 1)


# ───────────────────────── 地面 ─────────────────────────

class GroundChunk extends Node2D:
	var cv

	func _draw() -> void:
		cv = Batch.new()
		_paint()
		cv.emit(self)
		cv = null

	var cx := 0
	var cy := 0
	static var noise: FastNoiseLite

	func _land_col(i: int, x: int, y: int) -> Color:
		var g = Game
		var base: Color = [Color(0.66, 0.74, 0.5), Color(0.56, 0.68, 0.42), Color(0.74, 0.68, 0.45), Color(0.9, 0.9, 0.88)][Game.season()]
		var t: int = g.terrain[i]
		if t == Defs.T.HILL:
			base = base.lerp(Color(0.72, 0.64, 0.45), 0.4)
		elif t == Defs.T.MOUNTAIN:
			base = base.lerp(Color(0.5, 0.56, 0.48), 0.55)
		elif t == Defs.T.FOREST:
			base = base.darkened(0.08)
		var n := noise.get_noise_2d(x * 3.0, y * 3.0)
		return base.lightened(n * 0.12) if n > 0 else base.darkened(-n * 0.12)

	func _corner(x: int, y: int, water: bool) -> Color:
		# 角點 (x, y) 指四格 (x-1..x, y-1..y) 之交會處
		var g = Game
		var acc := Color(0, 0, 0, 0)
		var n := 0
		var wn := 0
		for dy in [-1, 0]:
			for dx in [-1, 0]:
				var tx: int = x + dx
				var ty: int = y + dy
				if not g.inb(tx, ty):
					continue
				var i: int = g.idx(tx, ty)
				if g.terrain[i] == Defs.T.WATER:
					wn += 1
				elif not water:
					acc += _land_col(i, tx, ty)
					n += 1
		if water:
			var wc := Art.WATER if Game.season() != 3 else Art.WATER.lerp(Color(0.85, 0.9, 0.95), 0.35)
			var nz := noise.get_noise_2d(x * 5.0, y * 5.0)
			return wc.darkened(0.04 * wn + nz * 0.08).lightened(0.12 * (4 - wn) / 4.0)
		return acc / n if n > 0 else Color(0.6, 0.7, 0.5)

	func _paint() -> void:
		if noise == null:
			noise = FastNoiseLite.new()
			noise.frequency = 0.02
		var g = Game
		var N: int = g.N
		var x0 := cx * 10
		var y0 := cy * 10
		var sea: int = Game.season()
		for y in range(y0, mini(y0 + 10, N)):
			for x in range(x0, mini(x0 + 10, N)):
				var i: int = g.idx(x, y)
				var c := WorldView_tile(x, y)
				var water: bool = g.terrain[i] == Defs.T.WATER
				var Nn := c + Art.iso(-0.5, -0.5)
				var E := c + Art.iso(0.5, -0.5)
				var S := c + Art.iso(0.5, 0.5)
				var W := c + Art.iso(-0.5, 0.5)
				cv.draw_polygon(PackedVector2Array([Nn, E, S, W]), PackedColorArray([
					_corner(x, y, water), _corner(x + 1, y, water), _corner(x + 1, y + 1, water), _corner(x, y + 1, water)]))
				if water:
					if g.canal[i] > 0:
						for d in Game.DIRS:
							var nx: int = x + d.x
							var ny: int = y + d.y
							if g.inb(nx, ny) and g.terrain[g.idx(nx, ny)] != Defs.T.WATER:
								_edge(c, d, 0.08, Art.STONE)
					continue
				for d in Game.DIRS:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if g.inb(nx, ny) and g.terrain[g.idx(nx, ny)] == Defs.T.WATER and g.canal[g.idx(nx, ny)] == 0:
						_edge(c, d, 0.14, Color(0.82, 0.76, 0.6) if sea != 3 else Color(0.9, 0.9, 0.88))
				var bid: int = g.bld[i]
				if bid >= 0:
					var b: Dictionary = g.buildings[bid]
					if b.type == "farm":
						_field(c, b.level, g.tree_var[i])
					elif b.size == 1 and b.type not in ["mine", "tea", "quarry"]:
						_inset(c, 0.44, Color(0.74, 0.69, 0.56, 0.55) if sea != 3 else Color(0.9, 0.9, 0.88, 0.6))
				elif g.zone[i] > 0:
					var zc: Color = Defs.ZONE_COLORS[g.zone[i]]
					_inset(c, 0.44, zc)
					var pts := PackedVector2Array([c + Art.iso(-0.44, -0.44), c + Art.iso(0.44, -0.44), c + Art.iso(0.44, 0.44), c + Art.iso(-0.44, 0.44), c + Art.iso(-0.44, -0.44)])
					cv.draw_polyline(pts, Color(zc, 0.7), 1.0)
				if g.road[i] > 0:
					_road(x, y, c, g.road[i])

	func WorldView_tile(x: float, y: float) -> Vector2:
		return Vector2((x - y) * 32.0, (x + y) * 16.0)

	func _inset(c: Vector2, e: float, col: Color) -> void:
		cv.draw_colored_polygon(PackedVector2Array([c + Art.iso(-e, -e), c + Art.iso(e, -e), c + Art.iso(e, e), c + Art.iso(-e, e)]), col)

	func _edge(c: Vector2, d: Vector2i, w: float, col: Color) -> void:
		var dv := Vector2(d)
		var pv := Vector2(-d.y, d.x)
		var a := dv * 0.5 + pv * 0.5
		var b := dv * 0.5 - pv * 0.5
		var a2 := dv * (0.5 - w) + pv * (0.5 - w)
		var b2 := dv * (0.5 - w) - pv * (0.5 - w)
		cv.draw_colored_polygon(PackedVector2Array([c + Art.iso(a.x, a.y), c + Art.iso(b.x, b.y), c + Art.iso(b2.x, b2.y), c + Art.iso(a2.x, a2.y)]), col)

	func _field(c: Vector2, lvl: int, v: int) -> void:
		var cols := [Color(0.62, 0.76, 0.4), Color(0.42, 0.62, 0.28), Color(0.86, 0.73, 0.32), Color(0.66, 0.6, 0.5)]
		var col: Color = cols[Game.season()]
		if Game.season() == 2 and Game.month >= 8:
			col = Color(0.7, 0.62, 0.42)
		_inset(c, 0.47, col.darkened(0.12))
		var ax := v % 2 == 0
		var lc := col.lightened(0.18)
		for k in 7:
			var t := -0.4 + k * 0.133
			var p0 := c + (Art.iso(-0.44, t) if ax else Art.iso(t, -0.44))
			var p1 := c + (Art.iso(0.44, t) if ax else Art.iso(t, 0.44))
			cv.draw_line(p0, p1, lc, 1.6)
		cv.draw_polyline(PackedVector2Array([c + Art.iso(-0.47, -0.47), c + Art.iso(0.47, -0.47), c + Art.iso(0.47, 0.47), c + Art.iso(-0.47, 0.47), c + Art.iso(-0.47, -0.47)]), Color(0.45, 0.4, 0.25, 0.6), 1.0)

	func _road(x: int, y: int, c: Vector2, kind: int) -> void:
		var g = Game
		var w := 0.2
		var col := Color(0.74, 0.62, 0.44) if kind == 1 else Color(0.64, 0.62, 0.58)
		if Game.season() == 3:
			col = col.lerp(Color(0.92, 0.92, 0.9), 0.4)
		var edge := col.darkened(0.25)
		var water: bool = g.terrain[g.idx(x, y)] == Defs.T.WATER
		if water:
			return
		var dirs := []
		for d in Game.DIRS:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if g.inb(nx, ny):
				var j: int = g.idx(nx, ny)
				if g.road[j] > 0:
					dirs.append(d)
				elif g.bld[j] >= 0 and g.buildings[g.bld[j]].type in ["station", "town", "yamen"]:
					dirs.append(d)
		for d in dirs:
			var dv := Vector2(d)
			var pv := Vector2(-d.y, d.x)
			var pts := [pv * -w, dv * 0.5 + pv * -w, dv * 0.5 + pv * w, pv * w]
			var sp := PackedVector2Array()
			for p in pts:
				sp.append(c + Art.iso(p.x, p.y))
			cv.draw_colored_polygon(sp, col)
			cv.draw_line(sp[0], sp[1], edge, 1.0)
			cv.draw_line(sp[2], sp[3], edge, 1.0)
		var cs := PackedVector2Array([c + Art.iso(-w, -w), c + Art.iso(w, -w), c + Art.iso(w, w), c + Art.iso(-w, w)])
		cv.draw_colored_polygon(cs, col)
		if kind == 2:
			for d in dirs:
				for k in 3:
					var t := 0.12 + k * 0.13
					var dv := Vector2(d) * t
					var pv := Vector2(-d.y, d.x) * w
					cv.draw_line(c + Art.iso(dv.x - pv.x, dv.y - pv.y), c + Art.iso(dv.x + pv.x, dv.y + pv.y), edge.lightened(0.1), 0.8)
		if dirs.is_empty():
			cv.draw_polyline(cs + PackedVector2Array([cs[0]]), edge, 1.0)


# ───────────────────────── 物件（依對角線） ─────────────────────────

class ObjChunk extends Node2D:
	var cv

	func _draw() -> void:
		cv = Batch.new()
		_paint()
		cv.emit(self)
		cv = null

	var d := 0
	var seg := 0

	func _paint() -> void:
		var g = Game
		var N: int = g.N
		cv.draw_set_transform(Vector2(0, -position.y))
		for x in range(maxi(maxi(0, d - N + 1), seg * SEG), mini(mini(d, N - 1), seg * SEG + SEG - 1) + 1):
			var y := d - x
			var i: int = g.idx(x, y)
			var c := Vector2((x - y) * 32.0, (x + y) * 16.0)
			var bid: int = g.bld[i]
			var v: int = g.tree_var[i]
			if bid >= 0:
				var b: Dictionary = g.buildings[bid]
				if b.x + b.size - 1 == x and b.y + b.size - 1 == y:
					_building(b)
			elif g.wall[i] > 0:
				_wall(x, y, c)
			elif g.road[i] > 0:
				if g.terrain[i] == Defs.T.WATER:
					var ax: bool = (g.inb(x + 1, y) and g.road[g.idx(x + 1, y)] > 0) or (g.inb(x - 1, y) and g.road[g.idx(x - 1, y)] > 0)
					Art.bridge(cv, c, ax, g.road[i] == 2)
			else:
				var t: int = g.terrain[i]
				if t == Defs.T.FOREST:
					Art.trees(cv, c, v, g.shore[i] > 0 and v % 2 == 0)
				elif t == Defs.T.MOUNTAIN:
					Art.mountain(cv, c, v)
				elif t == Defs.T.HILL:
					Art.hill(cv, c, v)
				elif t == Defs.T.GRASS and g.zone[i] == 0:
					if v < 6:
						Art.tree_round(cv, c + Art.iso(0.1, -0.1), 0.8, v)
					elif v > 250:
						Art.tree_pine(cv, c, 0.8)

	func _wall(x: int, y: int, c: Vector2) -> void:
		var g = Game
		var conn := []
		for dd in Game.DIRS:
			var nx: int = x + dd.x
			var ny: int = y + dd.y
			conn.append(g.inb(nx, ny) and g.wall[g.idx(nx, ny)] > 0)
		var gate: bool = g.road[g.idx(x, y)] > 0
		var road_x: bool = (g.inb(x + 1, y) and g.road[g.idx(x + 1, y)] > 0) or (g.inb(x - 1, y) and g.road[g.idx(x - 1, y)] > 0)
		Art.wall_tile(cv, c, conn, gate, road_x)

	func _building(b: Dictionary) -> void:
		var g = Game
		var h: float = (b.size - 1) * 0.5
		var c := Vector2((b.x + h - b.y - h) * 32.0, (b.x + h + b.y + h) * 16.0)
		var v: int = g.tree_var[g.idx(b.x, b.y)]
		if b.age < 6 and b.type != "farm" and b.type != "yamen" and b.type != "town":
			Art.scaffold(cv, c)
			return
		match b.type:
			"house":
				Art.house(cv, c, b.level, v)
			"shop":
				Art.shop(cv, c, b.level, v)
			"workshop":
				Art.workshop(cv, c, b.level, v)
			"farm":
				Art.farmhouse(cv, c, b.level, v)
			"yamen":
				Art.yamen(cv, c, v)
			"temple":
				Art.temple(cv, c, v)
			"academy":
				Art.academy(cv, c, v)
			"belltower":
				Art.belltower(cv, c, v)
			"pagoda":
				Art.pagoda(cv, c, v)
			"archway":
				Art.archway(cv, c, v)
			"garden":
				Art.garden(cv, c, v)
			"theater":
				Art.theater(cv, c, v)
			"well":
				Art.well(cv, c, v)
			"constable":
				Art.small_office(cv, c, "捕", Art.WALL_W, v)
			"clinic":
				Art.small_office(cv, c, "醫", Art.WALL_W, v)
			"school":
				Art.small_office(cv, c, "塾", Art.WALL_W, v)
			"firewatch":
				Art.firewatch(cv, c, v)
			"granary":
				Art.granary(cv, c, v)
			"warehouse":
				Art.warehouse(cv, c, v)
			"lumber":
				Art.lumber(cv, c, v)
			"quarry":
				Art.quarry(cv, c, v)
			"mine":
				Art.mountain(cv, c, v | 7)
				Art.mine(cv, c, v)
			"mulberry":
				Art.mulberry(cv, c, v)
			"tea":
				Art.tea(cv, c, v)
			"fishery":
				Art.fishery(cv, c, v)
			"kiln":
				Art.kiln(cv, c, v)
			"station":
				Art.station(cv, c, v)
			"dock":
				var wd := Vector2i(1, 0)
				for dd in Game.DIRS:
					var nx: int = b.x + dd.x
					var ny: int = b.y + dd.y
					if g.inb(nx, ny) and g.terrain[g.idx(nx, ny)] == Defs.T.WATER:
						wd = dd
						break
				Art.dock(cv, c, v, wd)
			"town":
				Art.town(cv, c, b.name)


# ───────────────────────── 車船行人 ─────────────────────────

class Mover extends Node2D:
	var kind := ""
	var dir := Vector2i(1, 0)
	var loaded := false
	var cargo_col := Color.WHITE
	var v := 0
	# 行人
	var tile := Vector2i.ZERO
	var target := Vector2i.ZERO
	var prev := Vector2i(-9, -9)
	var fpos := Vector2.ZERO
	var off := Vector2.ZERO
	var life := 0.0

	func _draw() -> void:
		if kind == "walker":
			Art.walker(self, v)
		else:
			Art.vehicle(self, kind, dir, cargo_col, loaded)


# ───────────────────────── 煙火天氣 ─────────────────────────

class FX extends Node2D:
	var view
	var t := 0.0
	var emit_t := 0.0
	var smokes: Array = []
	var flames: Array = []
	var flakes: Array = []

	func _ready() -> void:
		z_index = 5

	func _shimmer(vr: Rect2) -> void:
		var g = Game
		var a := _tile_of(vr.position)
		var b := _tile_of(vr.end)
		var c := _tile_of(Vector2(vr.end.x, vr.position.y))
		var d := _tile_of(Vector2(vr.position.x, vr.end.y))
		var x0 := maxi(0, mini(mini(a.x, b.x), mini(c.x, d.x)))
		var x1 := mini(g.N - 1, maxi(maxi(a.x, b.x), maxi(c.x, d.x)))
		var y0 := maxi(0, mini(mini(a.y, b.y), mini(c.y, d.y)))
		var y1 := mini(g.N - 1, maxi(maxi(a.y, b.y), maxi(c.y, d.y)))
		var col := Color(1, 1, 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var i: int = y * g.N + x
				if g.terrain[i] != Defs.T.WATER or g.road[i] > 0:
					continue
				var h := (x * 73 + y * 151) % 97
				if h % 3 != 0:
					continue
				var ph := fmod(t * 0.25 + h / 97.0, 1.0)
				var p := Vector2((x - y) * 32.0, (x + y) * 16.0) + Vector2((h % 7 - 3) * 4.0 + ph * 10.0, (h % 5 - 2) * 3.0)
				draw_line(p, p + Vector2(9, 0), Color(col, sin(ph * PI) * 0.45), 1.2)

	func _tile_of(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x / 32.0 + p.y / 16.0) * 0.5), int((p.y / 16.0 - p.x / 32.0) * 0.5))
		for k in 140:
			flakes.append(Vector3(randf(), randf(), randf()))

	func _process(delta: float) -> void:
		t += delta * maxf(0.3, Game.SPEEDS[Game.speed])
		emit_t -= delta
		if emit_t <= 0:
			emit_t = 1.0
			smokes.clear()
			flames.clear()
			for b in Game.buildings.values():
				var h: float = (b.size - 1) * 0.5
				var c := Vector2((b.x - b.y) * 32.0, (b.x + h + b.y + h) * 16.0)
				if b.fire > 0:
					flames.append(c)
				elif b.age >= 6:
					match b.type:
						"kiln":
							smokes.append(c + Art.iso(0.42, -0.15) - Vector2(0, 30))
						"workshop":
							if b.level == 2:
								smokes.append(c + Art.iso(0.13, -0.15) - Vector2(0, 26))
							elif b.level == 3:
								smokes.append(c + Art.iso(0.18, -0.22) - Vector2(0, 32))
						"house":
							if Game.season() == 3 and b.level >= 2 and int(b.id) % 3 == 0:
								smokes.append(c + Art.iso(0.1, -0.1) - Vector2(0, 22))
		queue_redraw()

	func _draw() -> void:
		var vr: Rect2 = view.view_rect()
		if view.cam.zoom.x >= 0.55:
			_shimmer(vr)
		for s in smokes:
			if not vr.has_point(s):
				continue
			for k in 5:
				var ph := fmod(t * 0.35 + k / 5.0 + s.x * 0.013, 1.0)
				var p: Vector2 = s + Vector2(sin(ph * 4.0 + k) * 3.0 + ph * 12.0, -ph * 34.0)
				draw_circle(p, 2.5 + ph * 6.0, Color(0.55, 0.55, 0.56, (1.0 - ph) * 0.35))
		for f in flames:
			if not vr.has_point(f):
				continue
			for k in 6:
				var ph := fmod(t * 1.7 + k / 6.0, 1.0)
				var p: Vector2 = f + Vector2(sin(k * 2.1 + t * 3.0) * 10.0, -6.0 - ph * 28.0)
				var r := (1.0 - ph) * 7.0 + 2.0
				draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.6, 0), p + Vector2(r * 0.6, 0), p + Vector2(sin(t * 9.0 + k) * 2.0, -r * 1.8)]),
					Color(1.0, 0.45 + ph * 0.4, 0.1, 0.85 * (1.0 - ph)))
				draw_circle(p - Vector2(0, 20 + ph * 20), 4 + ph * 6, Color(0.2, 0.18, 0.18, 0.4 * (1.0 - ph)))
		var sea: int = Game.season()
		if sea == 3 or sea == 0:
			for fl in flakes:
				var px := vr.position.x + fmod(fl.x * vr.size.x + sin(t * 0.7 + fl.z * 6.0) * 20.0 + t * (8.0 if sea == 0 else 3.0), vr.size.x)
				var py := vr.position.y + fmod(fl.y * vr.size.y + t * (40.0 + fl.z * 30.0) * (0.35 if sea == 0 else 1.0), vr.size.y)
				if sea == 3:
					draw_circle(Vector2(px, py), 1.2 + fl.z * 1.4, Color(1, 1, 1, 0.85))
				elif fl.z < 0.25:
					draw_circle(Vector2(px, py), 1.6, Color(0.96, 0.7, 0.78, 0.8))


func view_rect() -> Rect2:
	var vs := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - vs * 0.5, vs).grow(40)


# ───────────────────────── 資料圖層 ─────────────────────────

class Overlay extends Node2D:
	var cv

	func _draw() -> void:
		cv = Batch.new()
		_paint()
		cv.emit(self)
		cv = null

	var mode := ""

	func _ready() -> void:
		z_index = 3

	func _paint() -> void:
		if mode == "":
			return
		var g = Game
		var N: int = g.N
		for y in N:
			for x in N:
				var i: int = g.idx(x, y)
				var col := Color(0, 0, 0, 0)
				var t: int = g.terrain[i]
				var built: bool = g.bld[i] >= 0 or g.zone[i] > 0
				match mode:
					"lv":
						if t != Defs.T.WATER and (built or g.road[i] > 0 or g.near_conn[i] <= 3):
							var v: float = g.lv[i] / 100.0
							col = Color(1.0 - v, 0.3 + v * 0.6, 0.2, 0.5)
					"fert":
						if t != Defs.T.WATER and t != Defs.T.MOUNTAIN:
							var v: float = clampf((g.fert[i] - 0.5) / 0.9, 0, 1)
							col = Color(0.9 - v * 0.7, 0.55 + v * 0.35, 0.15, 0.5)
					"pollution":
						var v: float = g.cover["pollution"][i]
						if v > 0.05:
							col = Color(0.4, 0.25, 0.1, clampf(v * 0.25, 0.1, 0.7))
					"conn":
						if g.road[i] > 0:
							col = Color(0.2, 0.8, 0.3, 0.75) if g.conn_road(i) else Color(0.9, 0.2, 0.15, 0.75)
						elif g.near_conn[i] <= 3:
							col = Color(0.3, 0.7, 0.3, 0.15)
					_:
						var v: float = g.cover[mode][i]
						if v > 0:
							col = Color(0.2, 0.55, 0.95, 0.42) if mode == "water" else Color(0.25, 0.8, 0.35, 0.42)
						elif built:
							col = Color(0.9, 0.25, 0.2, 0.35)
				if col.a <= 0:
					continue
				var c := Vector2((x - y) * 32.0, (x + y) * 16.0)
				cv.draw_colored_polygon(PackedVector2Array([c + Art.iso(-0.5, -0.5), c + Art.iso(0.5, -0.5), c + Art.iso(0.5, 0.5), c + Art.iso(-0.5, 0.5)]), col)
