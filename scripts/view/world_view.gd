extends Node2D
## 世界畫面：地面分塊、按對角線排序之物件層、車船行人、煙火天氣與資料圖層。

const Art = preload("res://scripts/view/art.gd")
const Batch = preload("res://scripts/view/batch.gd")
const UIArt = preload("res://scripts/ui/ui_art.gd")
const Motion = preload("res://scripts/view/motion.gd")
const CH := 10
const SEG := 16
const ROLE_NEAR := {
	"house": ["woman", "woman", "child", "elder"],
	"farm": ["farmer"], "mulberry": ["farmer"], "tea": ["farmer"], "granary": ["farmer", "porter"],
	"shop": ["peddler", "woman", "scholar"], "theater": ["woman", "child", "scholar"],
	"workshop": ["porter"], "lumber": ["porter"], "quarry": ["porter"], "mine": ["porter"], "kiln": ["porter"],
	"fishery": ["porter"], "station": ["porter"], "dock": ["porter"], "warehouse": ["porter"],
	"school": ["scholar", "child"], "academy": ["scholar"],
	"temple": ["monk"], "pagoda": ["monk"],
	"yamen": ["official"], "constable": ["official"],
}
const ROLE_ANY := ["farmer", "porter", "peddler", "woman", "woman", "child", "elder", "scholar"]

var objects: Node2D
var ground_root: Node2D
var overlay: Overlay
var fx: FX
var anim: AnimLayer
var alerts: AlertLayer
var ground_chunks: Array = []
var obj_chunks := {}
var movers := {}
var walkers: Array = []
var walkers_shown := true
var road_cells: Array = []
var road_cells_t := 0.0
var last_season := -1
var last_rank := -1
var cam: Camera2D
var offscreen := false   # 長卷離屏繪製用：不接管 Game.dirty、不藏動畫中的建築、行人車船定格
var sweep: Array = []     # 換季漸染：[[延遲秒, 分塊], ...]，依延遲排序
# 待重畫的分塊：畫面內的每幀限量處理，畫面外的等鏡頭移過去再畫，避免一次重畫幾十塊造成停頓
var pend_ground := {}
var pend_obj := {}
const REDRAW_GROUND_PER_FRAME := 3
const REDRAW_OBJ_PER_FRAME := 10
var sweep_t := 0.0
const SWEEP_TIME := 1.5


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
	sweep.clear()
	pend_ground.clear()
	pend_obj.clear()
	var N: int = Game.N
	ground_root = Node2D.new()
	add_child(ground_root)
	var nch := ceili(N / float(CH))
	for cy in nch:
		for cx in nch:
			var g := GroundChunk.new()
			g.cx = cx
			g.cy = cy
			var a := tile_pos(cx * CH - 0.5, cy * CH - 0.5)
			var b := tile_pos(cx * CH + CH - 0.5, cy * CH + CH - 0.5)
			var l := tile_pos(cx * CH - 0.5, cy * CH + CH - 0.5)
			var r := tile_pos(cx * CH + CH - 0.5, cy * CH - 0.5)
			g.bounds = Rect2(Vector2(l.x, a.y), Vector2(r.x - l.x, b.y - a.y)).grow(40)
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
			var x0 := maxi(maxi(0, d - N + 1), sg * SEG)
			var x1 := mini(mini(d, N - 1), sg * SEG + SEG - 1)
			var p0 := tile_pos(x0, d - x0)
			var p1 := tile_pos(x1, d - x1)
			# 建築與樹往上長，留足高度；兩格寬的建築會跨到隔壁對角線
			oc.bounds = Rect2(Vector2(minf(p0.x, p1.x), p0.y), Vector2(absf(p1.x - p0.x), 0)).grow_individual(80, 260, 80, 40)
			oc.position = Vector2(0, d * Art.TH * 0.5)
			objects.add_child(oc)
			obj_chunks[d * 8 + sg] = oc
	overlay = Overlay.new()
	add_child(overlay)
	fx = FX.new()
	fx.view = self
	add_child(fx)
	anim = AnimLayer.new()
	anim.view = self
	add_child(anim)
	alerts = AlertLayer.new()
	alerts.view = self
	add_child(alerts)
	last_season = -1
	if offscreen:
		for o in obj_chunks.values():
			o.show_all = true
		overlay.visible = false
		anim.visible = false
		anim.process_mode = Node.PROCESS_MODE_DISABLED
		alerts.visible = false
		alerts.process_mode = Node.PROCESS_MODE_DISABLED
		_sync_movers(0.0)
		_update_walkers(0.0)
		return
	Game.anim_hide.clear()
	if not Game.building_fx.is_connected(_on_building_fx):
		Game.building_fx.connect(_on_building_fx)
	if not Game.building_removed.is_connected(_on_building_removed):
		Game.building_removed.connect(_on_building_removed)


func _process(delta: float) -> void:
	if not Game.running or objects == null or offscreen:
		return
	if Game.season() != last_season:
		var first := last_season < 0
		last_season = Game.season()
		Art.season = last_season
		if not first and Motion.full:
			_start_sweep()
	_run_sweep(delta)
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
			pend_ground[ground_chunks[k]] = true
		for k in oset:
			if obj_chunks.has(k):
				pend_obj[obj_chunks[k]] = true
		overlay.queue_redraw()
	_flush_redraws()
	_sync_movers(delta)
	_update_walkers(delta)


## 只重畫畫面內的待畫分塊，每幀限量；畫面外的留著，鏡頭移過去時再畫。
func _flush_redraws() -> void:
	if pend_ground.is_empty() and pend_obj.is_empty():
		return
	var vr := view_rect()
	var n := 0
	for g in pend_ground.keys():
		if n >= REDRAW_GROUND_PER_FRAME:
			break
		if g.bounds.intersects(vr):
			g.queue_redraw()
			pend_ground.erase(g)
			n += 1
	n = 0
	for o in pend_obj.keys():
		if n >= REDRAW_OBJ_PER_FRAME:
			break
		if o.bounds.intersects(vr):
			o.queue_redraw()
			pend_obj.erase(o)
			n += 1


## 換季：不在一幀內全換，而是由畫面左方往右，按分塊錯開重畫，約一秒半掃過全圖，像顏色一層層染上去。
## 尚未輪到的分塊保留舊季節的畫面（畫好的指令會留著，直到重畫）。
func _start_sweep() -> void:
	Game.dirty.clear()
	overlay.queue_redraw()
	sweep.clear()
	sweep_t = 0.0
	var N: int = Game.N
	var vr := view_rect()
	# 只有畫面內的分塊參與漸染；畫面外的記為待畫，鏡頭移過去時再畫
	for g in ground_chunks:
		if not g.bounds.intersects(vr):
			pend_ground[g] = true
			continue
		var tx: float = g.cx * CH + CH * 0.5
		var ty: float = g.cy * CH + CH * 0.5
		sweep.append([_sweep_delay(tx, ty), g])
	for o in obj_chunks.values():
		if not o.bounds.intersects(vr):
			pend_obj[o] = true
			continue
		var x: float = clampf(o.seg * SEG + SEG * 0.5, maxf(0, o.d - N + 1), mini(o.d, N - 1))
		sweep.append([_sweep_delay(x, o.d - x), o])
	sweep.sort_custom(func(a, b): return a[0] < b[0])


func _sweep_delay(tx: float, ty: float) -> float:
	var N: float = Game.N
	var u := ((tx - ty) + N) / (2.0 * N)
	var jitter := fmod(absf(tx * 12.9898 + ty * 78.233) * 0.137, 1.0) * 0.12
	return clampf(u, 0.0, 1.0) * SWEEP_TIME + jitter


func _run_sweep(delta: float) -> void:
	if sweep.is_empty():
		return
	sweep_t += delta
	var k := 0
	while k < sweep.size() and sweep[k][0] <= sweep_t:
		if is_instance_valid(sweep[k][1]):
			sweep[k][1].queue_redraw()
			pend_ground.erase(sweep[k][1])
			pend_obj.erase(sweep[k][1])
		k += 1
	if k > 0:
		sweep = sweep.slice(k)


func redraw_all() -> void:
	for g in ground_chunks:
		g.queue_redraw()
	for o in obj_chunks.values():
		o.queue_redraw()
	overlay.queue_redraw()


func _sync_movers(delta: float = 0.0) -> void:
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
		var real := tile_pos(p.x, p.y) + Vector2(0, 1)
		var sort_y := real.y
		if Defs.VEHICLES[v.kind]["mode"] == "water":
			# 船在橋下：排在整段橋之前畫，由橋面擋住；福船過橋前放倒桅杆，過了再豎起
			var t := Vector2i(roundi(p.x), roundi(p.y))
			var under := Game.inb(t.x, t.y) and Game.road[Game.idx(t.x, t.y)] > 0
			if under:
				var dk: Array = deck_at(Vector2(t))
				var d: int = dk[1] if dk[1] >= 0 else t.x + t.y
				sort_y = d * Art.TH * 0.5 - 0.5
			var near := under
			for k in [1, 2]:
				var a: Vector2i = t + v.dir * k
				if Game.inb(a.x, a.y) and Game.road[Game.idx(a.x, a.y)] > 0 and Game.terrain[Game.idx(a.x, a.y)] == Defs.T.WATER:
					near = true
			var goal := 0.0 if near else 1.0
			var mast: float = goal if delta <= 0.0 or not Motion.full else move_toward(m.mast, goal, delta * 2.2)
			if mast != m.mast:
				m.mast = mast
				m.queue_redraw()
		m.position = Vector2(real.x, sort_y)
		var off := Vector2(0, real.y - sort_y)
		if off != m.draw_off:
			m.draw_off = off
			m.queue_redraw()
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
	var want := mini(150, int(Game.stats.pop / 7))
	if road_cells.is_empty():
		want = 0
	while walkers.size() < want:
		var w := Mover.new()
		w.kind = "walker"
		w.v = randi() % 12   # 樣貌只取十二種：衣色、裙色、貨色已夠分辨，畫好的網格才能多人共用
		var i: int = road_cells[randi() % road_cells.size()]
		w.tile = Vector2i(i % Game.N, i / Game.N)
		w.target = w.tile
		w.off = Vector2(randf_range(-0.18, 0.18), randf_range(-0.18, 0.18))
		w.fpos = Vector2(w.tile)
		w.life = randf_range(20, 60)
		w.role = _pick_role(w.tile)
		w.pace = 0.6 if w.role == "elder" else 1.0
		w.ph = randf()
		w.visible = walkers_shown
		objects.add_child(w)
		walkers.append(w)
	# 全景時人只有幾個像素高，不畫，省下每人一次繪製
	var show := cam != null and cam.zoom.x >= 0.5
	if show != walkers_shown:
		walkers_shown = show
		for w in walkers:
			w.visible = show
	var spd0: float = Game.SPEEDS[Game.speed] * delta * 0.9
	for w in walkers.duplicate():
		w.life -= delta
		if walkers.size() > want or w.life <= 0 or not Game.inb(w.target.x, w.target.y) \
				or Game.road[Game.idx(w.target.x, w.target.y)] == 0:
			walkers.erase(w)
			w.queue_free()
			continue
		var spd: float = spd0 * w.pace
		if w.wait > 0.0:
			# 駐足：在店前看貨、在路口閒談
			w.wait -= delta * maxf(1.0, Game.SPEEDS[Game.speed]) if Game.speed > 0 else 0.0
			continue
		var tgt := Vector2(w.target)
		var d: Vector2 = tgt - w.fpos
		if d.length() > 0.001 and spd > 0:
			# 步伐與朝向：每格約走兩步半，相位量化為八格以免每幀重繪
			var sd := Art.iso(d.x, d.y)
			var front := sd.y > 0
			var flip := sd.x < 0
			w.ph = fmod(w.ph + spd * (3.4 if w.role == "child" else 2.5), 1.0)
			var f := int(w.ph * 8.0)
			if f != w.frame or front != w.front or flip != w.flip:
				w.frame = f
				w.front = front
				w.flip = flip
				w.queue_redraw()
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
			if randf() < 0.18 and _near_shop(w.tile):
				w.wait = randf_range(1.0, 2.5)
				w.ph = 0.0
				w.frame = -1
				w.queue_redraw()
		else:
			w.fpos += d.normalized() * spd
		var p: Vector2 = w.fpos + w.off
		_place_walker(w, p)


## 行人走上橋：按橋面曲線抬高；拱橋、虹橋整段畫在最前一格，行人要排在整段橋之後才不會被橋身蓋住。
func _place_walker(w, p: Vector2) -> void:
	var real := tile_pos(p.x, p.y) + Vector2(0, 1)
	var sort_y := real.y
	var t := Vector2i(roundi(p.x), roundi(p.y))
	if Game.inb(t.x, t.y) and Game.road[Game.idx(t.x, t.y)] > 0:
		var dk: Array = deck_at(p)
		real.y -= dk[0]
		if dk[1] >= 0:
			sort_y = maxf(sort_y, dk[1] * Art.TH * 0.5 + 1.5)
	w.position = Vector2(real.x, sort_y)
	var off := Vector2(0, real.y - sort_y)
	if off != w.draw_off:
		w.draw_off = off
		w.queue_redraw()


## 某點的橋面高度（像素）與整段橋所在的對角線（拱橋、虹橋；平橋與陸地為 -1）。
## 高度與 art.gd 的畫法一致：平橋 7，通航水面上的高腳平橋 14，兩頭斜板；拱橋、虹橋依弧線。
func deck_at(p: Vector2) -> Array:
	var g = Game
	var t := Vector2i(roundi(p.x), roundi(p.y))
	if not g.inb(t.x, t.y):
		return [0.0, -1]
	var i: int = g.idx(t.x, t.y)
	if g.road[i] == 0:
		return [0.0, -1]
	if g.terrain[i] != Defs.T.WATER:
		# 岸上：平橋的斜板從橋頭往岸上延伸約三分之一格
		for d in Game.DIRS:
			var n: Vector2i = t + d
			if not g._is_bridge(n.x, n.y):
				continue
			var ni: int = g.idx(n.x, n.y)
			if g.combo_tiles.has(ni) or g.arch_bridge(n.x, n.y):
				continue
			var dist := 0.5 - (p - Vector2(t)).dot(Vector2(d))
			if dist < 0.32:
				return [(14.0 if g.navigable(n.x, n.y) else 7.0) * (1.0 - dist / 0.32), -1]
		return [0.0, -1]
	var sp: Array = g.combo_tiles.get(i, [])
	var rainbow := not sp.is_empty()
	var ax: bool = (g.inb(t.x + 1, t.y) and g.road[g.idx(t.x + 1, t.y)] > 0) or (g.inb(t.x - 1, t.y) and g.road[g.idx(t.x - 1, t.y)] > 0)
	if not rainbow:
		if not g.arch_bridge(t.x, t.y):
			return [14.0 if g.navigable(t.x, t.y) else 7.0, -1]
		sp = g.bridge_span(t.x, t.y)
		ax = sp[2]
	var n: int = sp[1]
	var k: int = sp[0]
	var a: float = p.x if ax else p.y
	var front_a: int = (t.x if ax else t.y) + (n - 1 - k)
	var u := a - front_a
	var front_d: int = t.x + t.y + (n - 1 - k)
	var h := 0.0
	if rainbow:
		var u0 := -(n - 1) - 0.5 - 0.32
		var span := 0.82 - u0
		h = clampf(9.0 + n * 4.5, 14.0, 30.0) * sin(PI * clampf((u - u0) / span, 0.0, 1.0))
	else:
		var u0 := -(n - 1) - 0.5 - 0.34
		var span := 0.84 - u0
		h = clampf(8.0 + n * 6.0, 16.0, 36.0) * pow(sin(PI * clampf((u - u0) / span, 0.0, 1.0)), 0.75)
	return [h, front_d]


func _near_shop(t: Vector2i) -> bool:
	for d in Game.DIRS:
		var b := Game.building_at(t.x + d.x, t.y + d.y)
		if not b.is_empty() and b.type in ["shop", "theater", "well", "temple"]:
			return true
	return false


## 依出生處附近之建築定行人身分：田邊多農夫，作坊碼頭多挑夫，寺前有僧，衙前有官。
func _pick_role(t: Vector2i) -> String:
	var votes := []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := t.x + dx
			var y := t.y + dy
			if not Game.inb(x, y):
				continue
			var id: int = Game.bld[Game.idx(x, y)]
			if id < 0 or not Game.buildings.has(id):
				continue
			votes.append_array(ROLE_NEAR.get(Game.buildings[id].type, []))
	if not votes.is_empty() and randf() < 0.7:
		return votes[randi() % votes.size()]
	return ROLE_ANY[randi() % ROLE_ANY.size()]


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
	var bounds := Rect2()
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
				if g.combo_ground.has(i) and g.road[i] == 0:
					_paving(x, y, c, g.combo_ground[i])
					if bid >= 0 and g.buildings[bid].type == "farm":
						_field(c, g.buildings[bid].level, g.tree_var[i])
				elif bid >= 0:
					var b: Dictionary = g.buildings[bid]
					if b.type == "farm":
						_field(c, b.level, g.tree_var[i])
					elif Art.on_plinth(b):
						_plinth(c, 0.44, sea == 3)
					elif b.size == 1 and b.type not in ["mine", "tea", "quarry"]:
						_inset(c, 0.44, Color(0.74, 0.69, 0.56, 0.55) if sea != 3 else Color(0.9, 0.9, 0.88, 0.6))
				elif g.zone[i] > 0:
					var zc: Color = Defs.ZONE_COLORS[g.zone[i]]
					_inset(c, 0.44, zc)
					var pts := PackedVector2Array([c + Art.iso(-0.44, -0.44), c + Art.iso(0.44, -0.44), c + Art.iso(0.44, 0.44), c + Art.iso(-0.44, 0.44), c + Art.iso(-0.44, -0.44)])
					cv.draw_polyline(pts, Color(zc, 0.7), 1.0)
				if g.road[i] > 0:
					_road(x, y, c, g.road[i])

	const PAVE := {"siheyuan": Color(0.78, 0.76, 0.71), "fansha": Color(0.84, 0.74, 0.52), "yashu": Color(0.72, 0.71, 0.68),
		"wazi": Color(0.76, 0.6, 0.5), "caoyun": Color(0.7, 0.58, 0.42), "sangji": Color(0.64, 0.72, 0.52),
		"chama": Color(0.74, 0.66, 0.5), "guanyao": Color(0.8, 0.7, 0.6)}

	## 格局範圍內的鋪地：整片石板，外緣壓一道深色路緣，看得出是一處院落或街區。
	func _paving(x: int, y: int, c: Vector2, kind: String) -> void:
		var g = Game
		var col: Color = PAVE.get(kind, Color(0.75, 0.72, 0.66))
		if Game.season() == 3:
			col = col.lerp(Color(0.93, 0.93, 0.92), 0.35)
		_inset(c, 0.5, col)
		var lc := col.darkened(0.12)
		for k in range(1, 3):
			var t := -0.5 + k / 3.0
			cv.draw_line(c + Art.iso(-0.5, t), c + Art.iso(0.5, t), lc, 1.0)
			cv.draw_line(c + Art.iso(t + (0.08 if k == 1 else -0.08), -0.5), c + Art.iso(t + (0.08 if k == 1 else -0.08), 0.5), lc, 1.0)
		for d in Game.DIRS:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if not (g.inb(nx, ny) and g.combo_ground.get(g.idx(nx, ny), "") == kind):
				_edge(c, d, 0.06, col.darkened(0.35))

	func WorldView_tile(x: float, y: float) -> Vector2:
		return Vector2((x - y) * 32.0, (x + y) * 16.0)

	## 石砌台基：三像素高，頂面淺石色，兩個前立面較暗，墨線勾邊。
	func _plinth(c: Vector2, e: float, snow: bool) -> void:
		var col := Color(0.77, 0.74, 0.67) if not snow else Color(0.9, 0.9, 0.88)
		var up := Vector2(0, -Art.PLINTH_H)
		var W := c + Art.iso(-e, e)
		var S := c + Art.iso(e, e)
		var E := c + Art.iso(e, -e)
		var Nn := c + Art.iso(-e, -e)
		cv.draw_colored_polygon(PackedVector2Array([W, S, S + up, W + up]), Color(0.6, 0.57, 0.51))
		cv.draw_colored_polygon(PackedVector2Array([S, E, E + up, S + up]), Color(0.68, 0.65, 0.58))
		cv.draw_colored_polygon(PackedVector2Array([Nn + up, E + up, S + up, W + up]), col)
		cv.draw_polyline(PackedVector2Array([W + up, Nn + up, E + up, E, S, W, W + up]), Art.INK_LINE, Art.W_MID)
		cv.draw_line(S, S + up, Art.INK_LINE, Art.W_MID)
		cv.draw_polyline(PackedVector2Array([W + up, S + up, E + up]), Color(Art.INK_LINE, 0.5), Art.W_MID)

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
		# 路心沒有路伸出去的那幾邊補上路緣：丁字口對面、轉角外側、斷頭路的路頭，路緣才連得起來
		for d in Game.DIRS:
			if dirs.has(d) or dirs.is_empty():
				continue
			var dv := Vector2(d) * w
			var pv := Vector2(-d.y, d.x) * w
			cv.draw_line(c + Art.iso(dv.x - pv.x, dv.y - pv.y), c + Art.iso(dv.x + pv.x, dv.y + pv.y), edge, 1.0)
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
	var show_all := false
	var bounds := Rect2()

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
				if b.x + b.size - 1 == x and b.y + b.size - 1 == y and (show_all or not g.anim_hide.has(bid)):
					_building(b)
			elif g.wall[i] > 0:
				_wall(x, y, c)
			elif g.road[i] > 0:
				if g.terrain[i] == Defs.T.WATER:
					var ax: bool = (g.inb(x + 1, y) and g.road[g.idx(x + 1, y)] > 0) or (g.inb(x - 1, y) and g.road[g.idx(x - 1, y)] > 0)
					if g.combo_tiles.has(i):
						# 整段虹橋畫在最前一格，其餘各格不畫
						var sp: Array = g.combo_tiles[i]
						if sp[0] == sp[1] - 1:
							Art.rainbow_bridge(cv, c, ax, sp[1], v)
					elif g.arch_bridge(x, y):
						# 石拱橋：整段畫在最前一格
						var sp: Array = g.bridge_span(x, y)
						if sp[0] == sp[1] - 1:
							Art.stone_arch(cv, c, sp[2], sp[1], v)
					else:
						var dn := Vector2i(-1, 0) if ax else Vector2i(0, -1)
						var land_n: bool = g.inb(x + dn.x, y + dn.y) and g.terrain[g.idx(x + dn.x, y + dn.y)] != Defs.T.WATER
						var land_p: bool = g.inb(x - dn.x, y - dn.y) and g.terrain[g.idx(x - dn.x, y - dn.y)] != Defs.T.WATER
						Art.bridge(cv, c, ax, g.road[i] == 2, land_n, land_p, g.navigable(x, y))
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
		var off := Vector2(0, -position.y)
		# 建築本體放大並立上台基；畫完復原
		var xf: Array = Art.body_xf(b, c, off)
		if b.age < 6 and b.type != "farm" and b.type != "yamen" and b.type != "town":
			cv.draw_set_transform(xf[0], 0.0, xf[1])
			Art.scaffold(cv, c)
			cv.draw_set_transform(off)
			return
		if b.get("combo", "") != "":
			Art.combo_under(cv, b.combo, c, v, b.type)
		match b.type:
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
			_:
				cv.draw_set_transform(xf[0], 0.0, xf[1])
				Art.building(cv, b.type, c, b.level, v)
		if b.get("combo", "") != "":
			cv.draw_set_transform(xf[0], 0.0, xf[1])
			Art.combo_deco(cv, b.combo, c, b.size, v, b.type, b.get("quad", -1))
		if b.size == 1 and b.age >= 6 and b.type in ["house", "shop"] and b.get("combo", "") != "siheyuan":
			cv.draw_set_transform(xf[0], 0.0, xf[1])
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nb := Game.building_at(b.x + d.x, b.y + d.y)
				if not nb.is_empty() and nb.type == b.type and nb.age >= 6 and nb.get("combo", "") != "siheyuan":
					Art.link(cv, c, d, b.type, mini(b.level, nb.level))
		cv.draw_set_transform(off)


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
	var role := ""
	var pace := 1.0
	var ph := 0.0
	var frame := -1
	var front := true
	var flip := false
	var wait := 0.0
	var draw_off := Vector2.ZERO   # 排序位置與實際畫的位置之差（過橋時用）
	var mast := 1.0                # 福船桅杆：1 豎起，0 放倒
	## 行人畫好的網格：身分、樣貌、朝向、步態幀、季節相同者共用，每人每幀只需一次繪製。
	static var fig_cache := {}

	func _draw() -> void:
		if kind == "walker":
			var key := "%s|%d|%d|%d|%d|%d" % [role, v, int(front), int(flip), frame, Art.season]
			var m = fig_cache.get(key)
			if m == null:
				if fig_cache.size() > 6000:
					fig_cache.clear()
				var b := Batch.new()
				Art.figure(b, role, v, front, flip, 0.0 if frame < 0 else (frame + 0.5) / 8.0)
				m = b.to_mesh()
				fig_cache[key] = m if m != null else false
			if m is ArrayMesh:
				draw_set_transform(draw_off)
				draw_mesh(m, null)
		else:
			draw_set_transform(draw_off)
			Art.vehicle(self, kind, dir, cargo_col, loaded, mast)


# ───────────────────────── 煙火天氣 ─────────────────────────

class FX extends Node2D:
	var view
	var t := 0.0
	var emit_t := 0.0
	var smokes: Array = []
	var flames: Array = []
	var flakes: Array = []
	var cv   # 每幀把煙、火、水光、雪花併成一個網格，一次畫出

	func _ready() -> void:
		z_index = 5
		for k in 140:
			flakes.append(Vector3(randf(), randf(), randf()))

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
				cv.draw_line(p, p + Vector2(9, 0), Color(col, sin(ph * PI) * 0.45), 1.2)

	func _tile_of(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x / 32.0 + p.y / 16.0) * 0.5), int((p.y / 16.0 - p.x / 32.0) * 0.5))

	func _process(delta: float) -> void:
		t = Motion.ambient_t
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
							if b.get("combo", "") == "guanyao":
								smokes.append(c + Art.iso(0.1, -0.1) - Vector2(0, 18))
						"temple":
							if b.get("combo", "") == "fansha":
								smokes.append(c + Art.iso(0.85, 0.85) - Vector2(0, 16))
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
		cv = Batch.new()
		_paint()
		cv.emit(self)
		cv = null

	func _paint() -> void:
		var vr: Rect2 = view.view_rect()
		if view.cam.zoom.x >= 0.55 and Motion.full:
			_shimmer(vr)
		for s in smokes:
			if not vr.has_point(s):
				continue
			for k in 5:
				var ph := fmod(t * 0.35 + k / 5.0 + s.x * 0.013, 1.0)
				var p: Vector2 = s + Vector2(sin(ph * 4.0 + k) * 3.0 + ph * 12.0, -ph * 34.0)
				cv.draw_circle(p, 2.5 + ph * 6.0, Color(0.55, 0.55, 0.56, (1.0 - ph) * 0.35))
		for f in flames:
			if not vr.has_point(f):
				continue
			for k in 6:
				var ph := fmod(t * 1.7 + k / 6.0, 1.0)
				var p: Vector2 = f + Vector2(sin(k * 2.1 + t * 3.0) * 10.0, -6.0 - ph * 28.0)
				var r := (1.0 - ph) * 7.0 + 2.0
				cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.6, 0), p + Vector2(r * 0.6, 0), p + Vector2(sin(t * 9.0 + k) * 2.0, -r * 1.8)]),
					Color(1.0, 0.45 + ph * 0.4, 0.1, 0.85 * (1.0 - ph)))
				cv.draw_circle(p - Vector2(0, 20 + ph * 20), 4 + ph * 6, Color(0.2, 0.18, 0.18, 0.4 * (1.0 - ph)))
		var sea: int = Game.season()
		if (sea == 3 or sea == 0) and Motion.full:
			for fl in flakes:
				var px := vr.position.x + fmod(fl.x * vr.size.x + sin(t * 0.7 + fl.z * 6.0) * 20.0 + t * (8.0 if sea == 0 else 3.0), vr.size.x)
				var py := vr.position.y + fmod(fl.y * vr.size.y + t * (40.0 + fl.z * 30.0) * (0.35 if sea == 0 else 1.0), vr.size.y)
				if sea == 3:
					cv.draw_circle(Vector2(px, py), 1.2 + fl.z * 1.4, Color(1, 1, 1, 0.85))
				elif fl.z < 0.25:
					cv.draw_circle(Vector2(px, py), 1.6, Color(0.96, 0.7, 0.78, 0.8))


func _on_building_fx(id: int, kind: String) -> void:
	if anim == null or not Game.buildings.has(id):
		return
	anim.trigger(Game.buildings[id], kind)


func _on_building_removed(b: Dictionary, cause: String) -> void:
	if objects == null or offscreen or not Game.running:
		return
	if not view_rect().grow(200).has_point(AnimLayer.center(b)):
		return
	var tr := Transient.new()
	tr.kind = "collapse"
	tr.b = b
	tr.cause = cause
	add_transient(tr)


## 臨時節點放進 objects，依建築最前一角的對角線排序：前排的房子會正確地擋住它。
func add_transient(tr: Node2D) -> void:
	var b: Dictionary = tr.b
	var d: int = b.x + b.size - 1 + b.y + b.size - 1
	tr.position = Vector2(0, d * Art.TH * 0.5 + 0.5)
	objects.add_child(tr)


func view_rect() -> Rect2:
	var vs := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - vs * 0.5, vs).grow(40)


# ───────────────────────── 建造動畫 ─────────────────────────

## 建築落成、升級時由地面「長」起來（暫由此層繪製），並有塵土、金光、浮字；工地上有匠人敲打。
class AnimLayer extends Node2D:
	var view
	var bursts: Array = []  # {pos, kind, t, text}
	var scaffolds: Array = []
	var scan_t := 0.0
	var t := 0.0

	func _ready() -> void:
		z_index = 4

	static func center(b: Dictionary) -> Vector2:
		var h: float = (b.size - 1) * 0.5
		return Vector2((b.x + h - b.y - h) * 32.0, (b.x + h + b.y + h) * 16.0)

	func trigger(b: Dictionary, kind: String) -> void:
		var c := center(b)
		if not view.view_rect().grow(200).has_point(c):
			return
		match kind:
			"placed":
				bursts.append({"pos": c, "kind": "dust", "t": 0.0, "text": ""})
			"built", "upgrade":
				if b.type not in ["dock", "town", "yamen", "farm"] and not Game.anim_hide.has(b.id):
					var tr := Transient.new()
					tr.kind = "rise"
					tr.b = b
					Game.anim_hide[b.id] = true
					Game.mark_b(b)
					view.add_transient(tr)
				bursts.append({"pos": c, "kind": "dust", "t": 0.0, "text": ""})
				if kind == "upgrade":
					var names: Array = Defs.GROW[b.type].get("names", []) if Defs.GROW.has(b.type) else []
					var nm: String = names[b.level - 1] if b.level - 1 < names.size() else ""
					bursts.append({"pos": c, "kind": "rise", "t": 0.0, "text": "升為" + nm if nm != "" else "升級"})
				if kind == "upgrade":
					Sfx.play("coin")
			"combo":
				var nm: String = Defs.combo(b.combo).get("name", "")
				for e in bursts:
					if e.kind == "combo" and e.text.ends_with(nm) and e.pos.distance_to(c) < 260 and e.t < 0.5:
						e.ring.append(c)
						return
				bursts.append({"pos": c, "kind": "combo", "t": 0.0, "text": "格局 · " + nm, "ring": [c]})

	func _process(delta: float) -> void:
		t += delta
		for e in bursts:
			e.t += delta
		bursts = bursts.filter(func(e): return e.t < (2.2 if e.kind != "dust" else 0.9))
		scan_t -= delta
		if scan_t <= 0:
			scan_t = 0.5
			scaffolds.clear()
			var vr: Rect2 = view.view_rect()
			if view.cam.zoom.x >= 0.7:
				for b in Game.buildings.values():
					if b.age < 6 and b.type not in ["farm", "yamen", "town"]:
						var c := center(b)
						if vr.has_point(c):
							scaffolds.append([c, b.id])
		queue_redraw()

	func _draw() -> void:
		for sc in scaffolds:
			_workers(sc[0], sc[1])
		_garlands()
		var f := UIArt.font("title")
		for e in bursts:
			var c: Vector2 = e.pos
			match e.kind:
				"dust":
					var p: float = e.t / 0.9
					for k in 8:
						var ang := k * TAU / 8.0 + 0.3
						var q := c + Vector2(cos(ang) * 30.0, sin(ang) * 15.0) * (0.4 + p)
						draw_circle(q + Vector2(0, -p * 6.0), 4.0 + p * 6.0, Color(0.82, 0.76, 0.64, 0.55 * (1.0 - p)))
				"rise":
					var p: float = e.t / 2.2
					for k in 10:
						var ph := fmod(p * 1.6 + k * 0.137, 1.0)
						var q := c + Vector2(sin(k * 2.3) * 22.0, -20.0 - ph * 50.0)
						draw_circle(q, 2.2 * (1.0 - ph) + 0.6, Color(1.0, 0.84, 0.35, (1.0 - ph) * (1.0 - p)))
					_float_text(f, c + Vector2(0, -56 - p * 30.0), e.text, 20, Color(UIArt.NIJIN.darkened(0.2), 1.0 - p * p))
				"combo":
					var p: float = e.t / 2.2
					for q in e.ring:
						var r := 20.0 + p * 70.0
						var pts := PackedVector2Array()
						for k in 33:
							var ang := k * TAU / 32.0
							pts.append(q + Vector2(cos(ang) * r, sin(ang) * r * 0.5))
						draw_polyline(pts, Color(1.0, 0.82, 0.35, 0.9 * (1.0 - p)), 3.0, true)
					_float_text(f, c + Vector2(0, -70 - p * 26.0), e.text, 24, Color(UIArt.ZHU, 1.0 - p * p))

	## 瓦子：成員之間牽起成串燈籠，隨風輕擺。
	func _garlands() -> void:
		if view.cam.zoom.x < 0.6:
			return
		var vr: Rect2 = view.view_rect()
		for gp in Game.combo_groups:
			if gp.id != "wazi":
				continue
			var rest := []
			for id in gp.members:
				if Game.buildings.has(id):
					rest.append(center(Game.buildings[id]) - Vector2(0, 22))
			# 由戲樓起，每次接到最近的一家，至多四段，成一條街上的燈串
			var chain := [rest.pop_front()]
			rest = rest.filter(func(q): return q.distance_to(chain[0]) > 55)
			while rest.size() > 0 and chain.size() < 4:
				var last: Vector2 = chain[-1]
				var bi := 0
				for j in rest.size():
					if last.distance_to(rest[j]) < last.distance_to(rest[bi]):
						bi = j
				if last.distance_to(rest[bi]) > 150:
					break
				var nxt: Vector2 = rest.pop_at(bi)
				rest = rest.filter(func(q): return q.distance_to(nxt) > 55)
				chain.append(nxt)
			for k in range(1, chain.size()):
				var a: Vector2 = chain[k - 1]
				var b: Vector2 = chain[k]
				if not vr.has_point(a) and not vr.has_point(b):
					continue
				var at: float = Motion.ambient_t if Motion.full else 0.0
				var sway := sin(at * 1.8 + k) * 2.0
				var line := PackedVector2Array()
				for j in 13:
					var u := j / 12.0
					line.append(a.lerp(b, u) + Vector2(0, sin(u * PI) * (10.0 + sway)))
				draw_polyline(line, Color(0.2, 0.15, 0.12, 0.8), 1.0, true)
				for j in range(1, 12, 2):
					var q: Vector2 = line[j]
					var sw := sin(at * 2.6 + j + k) * 1.2 if Motion.full else 0.0
					draw_line(q, q + Vector2(sw, 3), Color(0.2, 0.15, 0.12, 0.8), 0.8)
					var lc := Vector2(q.x + sw, q.y + 5.5)
					draw_circle(lc, 2.3, Color(0.94, 0.24, 0.12))
					draw_circle(lc + Vector2(-0.7, -0.7), 0.9, Color(1.0, 0.6, 0.35))

	func _float_text(f: Font, at: Vector2, text: String, size: int, col: Color) -> void:
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var r := Rect2(at - Vector2(w * 0.5 + 8, size * 0.85), Vector2(w + 16, size * 1.3))
		draw_rect(r, Color(UIArt.PAPER, col.a * 0.92))
		draw_rect(r, Color(UIArt.INK, col.a * 0.5), false, 1.0)
		draw_string(f, Vector2(at.x - w * 0.5, at.y + size * 0.15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

	## 工地兩名匠人揮錘，錘落時揚起一點木屑。
	func _workers(c: Vector2, id: int) -> void:
		for k in 2:
			var at := c + Art.iso(-0.34 + k * 0.62, 0.34 - k * 0.1)
			var ph := fmod(Motion.world_t * 1.6 + k * 0.5 + id * 0.17, 1.0)
			Art.figure(self, ["porter", "farmer"][k], id + k, true, k == 1, 0.25, at)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var dirx := -1.0 if k == 1 else 1.0
			var sh := at + Vector2(1.5 * dirx, -8.5)
			var ang := lerpf(-2.2, -0.5, absf(sin(ph * PI))) if dirx > 0 else PI - lerpf(-2.2, -0.5, absf(sin(ph * PI)))
			var tip := sh + Vector2(cos(ang), sin(ang)) * 8.0
			draw_line(sh, tip, Art.WOOD, 1.4)
			draw_line(tip - Vector2(cos(ang + PI / 2), sin(ang + PI / 2)) * 2.0, tip + Vector2(cos(ang + PI / 2), sin(ang + PI / 2)) * 2.0, Color(0.3, 0.3, 0.32), 2.0)
			if ph > 0.45 and ph < 0.6:
				for j in 3:
					draw_circle(tip + Vector2((j - 1) * 3.0, -2.0 - j), 1.2, Color(0.85, 0.75, 0.55, 0.8))


# ───────────────────────── 臨時：落成長起、倒塌與殘垣 ─────────────────────────

## 放在 objects 裡依對角線排序的臨時節點，前後遮擋才正確。
## rise：落成、升級時建築由地面長起（0.6 秒）。
## collapse：拆除、焚毀、沖毀時屋頂向內塌、屋身下沉、揚起灰土，原地留一堆殘垣，數秒後淡去；焚毀者留焦黑木架。
class Transient extends Node2D:
	const RISE := 0.6
	const FALL := 0.45
	var kind := ""
	var b: Dictionary
	var cause := ""
	var t := 0.0
	var life := 0.6
	var c := Vector2.ZERO
	var v := 0
	var flat := false
	var mesh: ArrayMesh   # 建築先合成一個網格，之後每幀只縮放，不重畫整棟
	var texts: Array = []  # 招牌字另外畫

	func _ready() -> void:
		var h: float = (b.size - 1) * 0.5
		c = Vector2((b.x + h - b.y - h) * 32.0, (b.x + h + b.y + h) * 16.0)
		v = Game.tree_var[Game.idx(b.x, b.y)]
		flat = b.type in ["farm", "mulberry", "tea"] or b.age < 6
		if kind == "rise":
			life = RISE
		else:
			life = 4.0 if cause == "fire" else 2.6
			if flat:
				life = 1.6

	func _process(delta: float) -> void:
		t += delta
		if kind == "rise":
			if t >= life or not Game.buildings.has(b.id):
				_finish()
				return
		else:
			# 原地又蓋了東西，殘垣立刻讓位
			if t > FALL and Game.bld[Game.idx(b.x, b.y)] >= 0:
				_finish()
				return
			# 塌的時候愈塌愈暗（焚毀者焦黑），之後殘垣在最後六成秒淡去
			var fade := clampf((life - t) / 0.6, 0.0, 1.0)
			var tint := Color.WHITE
			if not flat and t < FALL:
				var k := Motion.ease_in(t / FALL)
				tint = Color(1.0 - 0.3 * k, 1.0 - 0.33 * k, 1.0 - 0.36 * k)
				if cause == "fire":
					tint = Color(0.5 - 0.2 * k, 0.42 - 0.2 * k, 0.38 - 0.2 * k)
			self_modulate = Color(tint, fade)
			if t >= life:
				_finish()
				return
		queue_redraw()

	func _finish() -> void:
		if kind == "rise":
			Game.anim_hide.erase(b.id)
			if Game.buildings.has(b.id):
				Game.mark_b(Game.buildings[b.id])
		queue_free()

	func _draw() -> void:
		var off := Vector2(0, -position.y)
		if kind == "rise":
			var p: float = clampf(t / RISE, 0.0, 1.0)
			var c1 := 1.70158
			var e := 1.0 + (c1 + 1.0) * pow(p - 1.0, 3) + c1 * pow(p - 1.0, 2)
			_paint_building(c + off, Vector2(lerpf(0.86, 1.0, minf(1.0, p * 1.4)), maxf(0.05, e)))
			return
		if not flat and t < FALL:
			# 屋頂向內塌、屋身下沉，愈塌愈暗
			var k := Motion.ease_in(t / FALL)
			_paint_building(c + off, Vector2(1.0 + 0.06 * k, 1.0 - 0.82 * k))
		if t > FALL * 0.6 or flat:
			_rubble(c + off)
		_dust(c + off)

	func _paint_building(at: Vector2, sc: Vector2) -> void:
		# 與地圖上的畫法一致：本體放大並立上台基
		var k := Art.BUILDING_SCALE
		sc *= k
		if Art.on_plinth(b):
			at.y -= Art.PLINTH_H
		if mesh == null:
			var cv := Batch.new()
			if b.get("combo", "") != "":
				Art.combo_under(cv, b.combo, Vector2.ZERO, v, b.type)
			Art.building(cv, b.type, Vector2.ZERO, b.level, v)
			if b.get("combo", "") != "":
				Art.combo_deco(cv, b.combo, Vector2.ZERO, b.size, v, b.type, b.get("quad", -1))
			mesh = cv.to_mesh()
			texts = cv.texts
			if mesh == null:
				return
		draw_set_transform(at, 0.0, sc)
		draw_mesh(mesh, null)
		for t in texts:
			draw_string(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], t[4])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## 一堆殘垣：土堆、碎瓦、斷木；焚毀者焦黑並立幾根燒剩的柱子。
	func _rubble(at: Vector2) -> void:
		var e: float = b.size * 0.5
		var burnt := cause == "fire"
		var earth := Color(0.24, 0.21, 0.19) if burnt else Color(0.62, 0.56, 0.46)
		if flat:
			return
		var g := clampf((t - FALL * 0.6) / 0.25, 0.0, 1.0)
		var mound := PackedVector2Array()
		for k in 14:
			var a := k / 14.0 * TAU
			var rr := e * (0.62 + 0.08 * sin(a * 3.0 + v))
			mound.append(at + Art.iso(cos(a) * rr * 0.9, sin(a) * rr * 0.9) - Vector2(0, maxf(0.0, -sin(a)) * 3.0 * g))
		draw_colored_polygon(mound, earth)
		draw_polyline(mound + PackedVector2Array([mound[0]]), Color(0.16, 0.11, 0.08, 0.5), 1.0)
		var tile := Color(0.2, 0.2, 0.21) if burnt else Art.ROOF_G
		for k in 9:
			var hx := fmod(absf(sin((b.id + 1) * 12.9898 + k * 78.233)) * 43758.5, 1.0) - 0.5
			var hy := fmod(absf(sin((b.id + 1) * 39.3468 + k * 11.135)) * 24634.6, 1.0) - 0.5
			var q := at + Art.iso(hx * e * 1.1, hy * e * 1.1) - Vector2(0, 2.0 + 3.0 * g * (1.0 - absf(hx) - absf(hy)))
			if k % 3 == 0:
				var dir := Vector2(cos(k * 1.7), sin(k * 1.7) * 0.5) * 7.0
				draw_line(q - dir, q + dir, Color(0.15, 0.1, 0.08) if burnt else Art.WOOD, 2.0)
			else:
				draw_colored_polygon(PackedVector2Array([q + Vector2(-3, 0), q + Vector2(0, -1.6), q + Vector2(3, 0), q + Vector2(0, 1.6)]), tile)
		if burnt:
			for k in 3:
				var q := at + Art.iso(-0.3 + k * 0.3, 0.25 - k * 0.2)
				draw_line(q, q - Vector2(0, 14.0 - k * 3.0), Color(0.12, 0.09, 0.08), 2.5)
			if t < 2.0:
				for k in 5:
					var q := at + Art.iso(sin(k * 2.1) * 0.35, cos(k * 1.3) * 0.35)
					draw_circle(q - Vector2(0, 2), 1.4, Color(1.0, 0.45, 0.15, (1.0 - t / 2.0) * (0.5 + 0.5 * sin(t * 9.0 + k))))
			# 一縷將散的煙
			for k in 4:
				var ph := fmod(t * 0.4 + k / 4.0, 1.0)
				draw_circle(at + Vector2(sin(ph * 4.0 + k) * 3.0 + ph * 10.0, -10.0 - ph * 34.0), 3.0 + ph * 6.0, Color(0.35, 0.34, 0.34, (1.0 - ph) * 0.3))

	## 灰土：自牆根向四周揚起，一秒內散盡。
	func _dust(at: Vector2) -> void:
		var p := clampf((t - FALL * 0.4) / 1.0, 0.0, 1.0) if not flat else clampf(t / 0.9, 0.0, 1.0)
		if p <= 0.0 or p >= 1.0:
			return
		var col := Color(0.4, 0.38, 0.36) if cause == "fire" else Color(0.82, 0.76, 0.64)
		var e: float = b.size * 0.5
		for k in 10:
			var ang := k * TAU / 10.0 + 0.3
			var q := at + Vector2(cos(ang) * 34.0 * e, sin(ang) * 17.0 * e) * (0.35 + p) - Vector2(0, 6.0 + p * 12.0)
			draw_circle(q, 4.0 + p * 8.0, Color(col, 0.6 * (1.0 - p)))


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


# ───────────────────────── 警示籤 ─────────────────────────

## 出事的建築上方掛一張小紙籤；全景時同一街區合併為帶數字的一張。點擊可打開冊頁。
class AlertLayer extends Node2D:
	const ICON := {"fire": "fire", "plague": "bad", "road": "road", "water": "water", "raw": "industry", "staff": "people"}
	const RED := ["fire", "plague"]
	var view
	var items: Array = []
	var hits: Array = []
	var scan_t := 0.0
	var sig := ""
	var last_zoom := -1.0
	var last_hover := -2
	var born := {}   # 籤的鍵 → 掛上的時刻（介面時鐘），用於垂落
	var quiet := false
	var sway_t := 0.0

	func _ready() -> void:
		z_index = 8

	## 只在內容、縮放或滑鼠所指改變時重畫，平時不耗效能。
	func _process(delta: float) -> void:
		scan_t -= delta
		var z: float = view.cam.zoom.x
		if scan_t <= 0.0 or (z < 0.6) != (last_zoom < 0.6):
			# 縮放跨過合併門檻時籤會重組，這時不播垂落
			quiet = (z < 0.6) != (last_zoom < 0.6)
			scan_t = 0.5
			_scan()
			quiet = false
		var h := -1
		var mp := get_global_mouse_position()
		for k in range(hits.size() - 1, -1, -1):
			if hits[k][0].has_point(mp):
				h = k
				break
		# 輕擺每秒重畫三十次就夠，不必每幀
		sway_t -= delta
		var sway: bool = Motion.full and not items.is_empty() and sway_t <= 0.0
		if sway:
			sway_t = 1.0 / 30.0
		if z != last_zoom or h != last_hover or sway:
			last_zoom = z
			last_hover = h
			queue_redraw()

	func _scan() -> void:
		var raw := []
		for b in Game.buildings.values():
			var p: Dictionary = Game.problem_of(b)
			if p.is_empty():
				continue
			var h: float = (b.size - 1) * 0.5
			var c := Vector2((b.x - b.y) * 32.0, (b.x + h + b.y + h) * 16.0)
			raw.append({"id": b.id, "kind": p.kind, "text": p.text, "pos": c - Vector2(0, 26 + b.size * 14),
				"count": 1, "tile": Vector2i(b.x, b.y)})
		if view.cam.zoom.x >= 0.6:
			_set_items(raw)
			return
		var groups := {}
		for it in raw:
			var key := Vector2i(it.tile.x / 6, it.tile.y / 6)
			if not groups.has(key):
				var g: Dictionary = it.duplicate()
				g.count = 0
				g.sum = Vector2.ZERO
				groups[key] = g
			var g: Dictionary = groups[key]
			g.count += 1
			g.sum += it.pos
			if Game.PROBLEM_ORDER.find(it.kind) < Game.PROBLEM_ORDER.find(g.kind):
				g.kind = it.kind
				g.text = it.text
				g.id = it.id
				g.tile = it.tile
		var out := []
		for g in groups.values():
			g.pos = g.sum / g.count
			out.append(g)
		_set_items(out)

	func _set_items(list: Array) -> void:
		var parts := PackedStringArray()
		for it in list:
			parts.append("%d%s%d" % [it.id, it.kind, it.count])
		var ns := ",".join(parts)
		items = list
		var now := Motion.ui_t
		var keep := {}
		for it in list:
			var key := "%d%s" % [it.id, it.kind]
			keep[key] = born.get(key, now - 10.0 if quiet else now)
		born = keep
		if ns != sig:
			sig = ns
			queue_redraw()

	## 世界座標下點中的紙籤；無則回傳空字典。
	func hit(p: Vector2) -> Dictionary:
		for k in range(hits.size() - 1, -1, -1):
			if hits[k][0].has_point(p):
				return hits[k][1]
		return {}

	func _draw() -> void:
		hits.clear()
		if items.is_empty():
			return
		var s := 1.0 / maxf(view.cam.zoom.x, 0.2)
		var mouse := get_global_mouse_position()
		var hover := {}
		var tf := UIArt.font("title")
		for it in items:
			var red: bool = it.kind in RED
			var p: Vector2 = it.pos
			# 以籤腳（繩的下端）為軸輕擺：平時約三度，失火疫病加倍；新掛上的籤由上方垂落、晃兩下停住
			if Motion.full:
				var age: float = Motion.ui_t - born.get("%d%s" % [it.id, it.kind], -10.0)
				var amp := deg_to_rad(6.0 if red else 3.0)
				var ang := sin(Motion.ambient_t * TAU / 2.5 + it.id * 0.7) * amp
				ang += deg_to_rad(14.0) * exp(-age * 4.0) * sin(age * 13.0)
				var drop := -16.0 * s * (1.0 - Motion.ease_out(age / 0.3))
				var pivot: Vector2 = it.pos + Vector2(0, 14.0 * s)
				draw_set_transform_matrix(Transform2D(ang, pivot) * Transform2D(0.0, -pivot + Vector2(0, drop)))
			var w := 26.0 * s
			var hh := 30.0 * s
			var r := Rect2(p - Vector2(w * 0.5, hh), Vector2(w, hh))
			draw_line(p, it.pos + Vector2(0, 14.0 * s), Color(UIArt.INK, 0.55), 1.2 * s)
			UIArt.slip(self, r, Color("f2d6c8") if red else UIArt.PAPER, 2.0 * s)
			draw_rect(r, Color(UIArt.BAD if red else UIArt.INK_2, 0.9), false, 1.2 * s)
			draw_circle(r.position + Vector2(w * 0.5, 3.5 * s), 1.6 * s, Color(UIArt.INK, 0.6))
			UIArt.icon(self, ICON.get(it.kind, "bad"), Rect2(r.position + Vector2(3.0 * s, 6.0 * s), Vector2(20.0 * s, 20.0 * s)),
				UIArt.BAD if red else UIArt.INK)
			if it.count > 1:
				var cc := r.position + Vector2(w, 0)
				draw_circle(cc, 9.0 * s, UIArt.ZHU)
				UIArt.text_c(self, tf, cc, str(it.count), int(12 * s), UIArt.SEAL_TEXT)
			draw_set_transform_matrix(Transform2D.IDENTITY)
			var hr := r.grow(4.0 * s)
			hits.append([hr, it])
			if hr.has_point(mouse):
				hover = {"r": r, "it": it}
		if not hover.is_empty():
			var r: Rect2 = hover.r
			var it: Dictionary = hover.it
			var txt: String = it.text if it.count <= 1 else "%s等 %d 處" % [it.text, it.count]
			var bf := UIArt.font("body")
			var fs := int(15 * s)
			var tw := bf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var lr := Rect2(r.end.x + 4.0 * s, r.position.y + 4.0 * s, tw + 14.0 * s, 22.0 * s)
			UIArt.slip(self, lr, UIArt.PAPER, 2.0 * s)
			UIArt.text_l(self, bf, lr.position.x + 7.0 * s, lr.get_center().y, txt, fs, UIArt.BAD if it.kind in RED else UIArt.INK)
