extends Node
## 遊戲狀態與模擬：地圖、建築、經濟、服務、事件、貨運路線與存檔。

signal message(text: String, kind: int)   # kind: 0 一般 1 喜 2 憂
signal rank_changed(r: int)
signal map_reset
signal month_passed
signal quest_done(id: String)
signal combo_found(id: String)
signal building_fx(id: int, kind: String)   # placed／built／upgrade／combo，供畫面播放動畫

const WorldGen = preload("res://scripts/worldgen.gd")
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const COVER_KEYS := ["water", "security", "health", "fire", "edu", "faith", "fun", "beauty", "pollution", "market"]
const SPEEDS := [0, 1, 2, 4]
const NO_CELL := Vector2i(-1, -1)

var N: int = Defs.N
var rng := RandomNumberGenerator.new()
var running := false
var map_seed := 0

# 地圖層
var terrain := PackedByteArray()
var road := PackedByteArray()
var zone := PackedByteArray()
var wall := PackedByteArray()
var canal := PackedByteArray()
var tree_var := PackedByteArray()
var fert := PackedFloat32Array()
var bld := PackedInt32Array()
var shore := PackedByteArray()      # 距水兩格內為 1
var lv := PackedFloat32Array()      # 地價
var road_dist := PackedInt32Array() # 自縣衙沿路之距離，-1 為不通
var near_conn := PackedByteArray()  # 距通達道路之格數（0..3），255 為過遠
var cover := {}

var buildings := {}
var routes := {}
var vehicles := {}
var next_id := 1
var next_route := 1
var next_veh := 1
var yamen_id := -1
var station_count := 0

# 時間與城市
var city_name := "清河"
var era := "開元"
var year := 1
var month := 0
var day := 0
var day_acc := 0.0
var speed := 1
var rank := 0
var money := 6000.0
var stock := {}
var policies := {}
var tax := {"res": 10, "com": 10, "ind": 10, "farm": 10}
var stats := {}
var report := {"income": {}, "expense": {}}
var trade_month := 0.0
var drought := 0
var bumper := false
var food_short := 0.0
var lux_ratio := 1.0
var goods_ratio := 1.0
var ws_supplied := 0.0
var log_lines: Array = []
var quests_done := {}
var combos_found := {}    # 已成之格局：id → 日期
var combo_tiles := {}     # 虹橋橋面：格索引 → [序, 長]
var combo_count := {}     # 各格局現存處數
var combo_ground := {}    # 格局範圍內鋪地的格：索引 → 格局 id
var combo_groups: Array = []  # 每處格局：{id, members}
var anim_hide := {}       # 正在播放升起動畫、暫不由地圖分塊繪製的建築
var history: Array = []

var dirty := {}
var connectivity_dirty := true
var zone_dirty := true
var zone_cells: Array = [[], [], [], [], []]
var burning := {}
var astar_road: AStarGrid2D
var astar_water: AStarGrid2D


# ───────────────────────── 基本工具 ─────────────────────────

func idx(x: int, y: int) -> int:
	return y * N + x


func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < N and y < N


func mark(x: int, y: int) -> void:
	if inb(x, y):
		dirty[idx(x, y)] = true


func mark_b(b: Dictionary) -> void:
	for dy in range(-1, b.size + 1):
		for dx in range(-1, b.size + 1):
			mark(b.x + dx, b.y + dy)


func rank_name() -> String:
	return Defs.RANKS[rank]["name"]


func date_str() -> String:
	var y := "元" if year == 1 else Defs.cn_num(year)
	return "%s%s年 %s %s" % [era, y, Defs.SEASONS[Defs.season_of(month)], Defs.MONTHS[month]]


func season() -> int:
	return Defs.season_of(month)


func log_msg(text: String, kind: int = 0) -> void:
	log_lines.push_front({"t": date_str(), "text": text, "kind": kind})
	if log_lines.size() > 60:
		log_lines.pop_back()
	message.emit(text, kind)


func radius() -> int:
	return Defs.RANKS[rank]["radius"]


func conn_road(i: int) -> bool:
	return road_dist[i] >= 0 and road_dist[i] <= radius()


func cap_of(c: String) -> float:
	var food := c in Defs.FOOD
	var base := 300.0 if food else 200.0
	for b in buildings.values():
		var d: Dictionary = Defs.B.get(b.type, {})
		if d.has("store") and b.conn:
			base += d.store.get("food" if food else "goods", 0)
	return base


func add_stock(c: String, amt: float) -> float:
	var cap := cap_of(c)
	var before: float = stock.get(c, 0.0)
	stock[c] = minf(before + amt, cap)
	return stock[c] - before


func take_stock(c: String, amt: float) -> float:
	if amt <= 0.0:
		return 0.0
	var have: float = stock.get(c, 0.0)
	var got := minf(have, amt)
	stock[c] = have - got
	return got


# ───────────────────────── 新局 ─────────────────────────

func _alloc() -> void:
	var nn := N * N
	for a in ["terrain", "road", "zone", "wall", "canal", "tree_var", "shore", "near_conn"]:
		var arr := PackedByteArray()
		arr.resize(nn)
		arr.fill(0)
		set(a, arr)
	fert = PackedFloat32Array()
	fert.resize(nn)
	lv = PackedFloat32Array()
	lv.resize(nn)
	bld = PackedInt32Array()
	bld.resize(nn)
	bld.fill(-1)
	road_dist = PackedInt32Array()
	road_dist.resize(nn)
	road_dist.fill(-1)
	cover = {}
	for k in COVER_KEYS:
		var c := PackedFloat32Array()
		c.resize(nn)
		cover[k] = c


func _reset() -> void:
	_alloc()
	buildings = {}
	routes = {}
	vehicles = {}
	next_id = 1
	next_route = 1
	next_veh = 1
	yamen_id = -1
	station_count = 0
	year = 1
	month = 0
	day = 0
	day_acc = 0.0
	speed = 1
	rank = 0
	money = 6000.0
	stock = {}
	for c in Defs.CARGO_ORDER:
		stock[c] = 0.0
	stock["grain"] = 150.0
	policies = {}
	tax = {"res": 10, "com": 10, "ind": 10, "farm": 10}
	stats = {"pop": 0, "labor": 0, "jobs": 0, "staff": 1.0, "happy": 60.0, "unemp": 0.0,
		"dR": 0.0, "dC": 0.0, "dI": 0.0, "dF": 0.0, "houses": 0, "farm_est": 0.0}
	report = {"income": {}, "expense": {}}
	trade_month = 0.0
	drought = 0
	bumper = false
	food_short = 0.0
	log_lines = []
	quests_done = {}
	combos_found = {}
	combo_tiles = {}
	combo_count = {}
	combo_ground = {}
	combo_groups = []
	history = []
	dirty = {}
	burning = {}
	connectivity_dirty = true
	zone_dirty = true


func new_game(cname: String, seed_v: int) -> void:
	_reset()
	city_name = cname
	map_seed = seed_v
	rng.seed = seed_v
	era = Defs.ERAS[rng.randi() % Defs.ERAS.size()]
	WorldGen.generate(self, seed_v)
	_finish_setup()
	log_msg("%s元年，奉旨於此設%s，名曰「%s」。" % [era, rank_name(), city_name], 1)
	log_msg("先修道路、劃民居與農田，再鑿井建倉。", 0)


func _finish_setup() -> void:
	_compute_shore()
	_init_astar()
	_update_connectivity()
	_compute_cover()
	recount()
	_check_combos()
	for i in N * N:
		dirty[i] = true
	running = true
	map_reset.emit()


# ───────────────────────── 建築 ─────────────────────────

func add_building(type: String, x: int, y: int, extra: Dictionary = {}) -> int:
	var size: int = Defs.B[type]["size"] if Defs.B.has(type) else 1
	var b := {"id": next_id, "type": type, "x": x, "y": y, "size": size, "level": 1, "age": 0,
		"conn": false, "stock": {}, "happy": 60.0, "bad": 0, "fire": 0, "last": 0.0, "name": ""}
	b.merge(extra, true)
	next_id += 1
	for dy in size:
		for dx in size:
			var i := idx(x + dx, y + dy)
			bld[i] = b.id
			if terrain[i] == Defs.T.FOREST:
				terrain[i] = Defs.T.GRASS
	buildings[b.id] = b
	b.conn = _bconn(b)
	mark_b(b)
	if running and b.age < 6:
		building_fx.emit(b.id, "placed")
	return b.id


func remove_building(id: int) -> void:
	if not buildings.has(id):
		return
	var b: Dictionary = buildings[id]
	for dy in b.size:
		for dx in b.size:
			bld[idx(b.x + dx, b.y + dy)] = -1
	if b.type in ["station", "dock"]:
		for r in routes.values().duplicate():
			if r.a == id or r.b == id:
				delete_route(r.id, 0.5)
	burning.erase(id)
	buildings.erase(id)
	mark_b(b)


func building_at(x: int, y: int) -> Dictionary:
	if not inb(x, y):
		return {}
	var id := bld[idx(x, y)]
	return buildings.get(id, {})


func is_grow(b: Dictionary) -> bool:
	return Defs.GROW.has(b.type)


func bname(b: Dictionary) -> String:
	if b.name != "":
		return b.name
	if is_grow(b):
		return Defs.GROW[b.type]["names"][b.level - 1]
	return Defs.B[b.type]["name"]


func b_center(b: Dictionary) -> Vector2:
	var h: float = (b.size - 1) * 0.5
	return Vector2(b.x + h, b.y + h)


func _bconn(b: Dictionary) -> bool:
	if b.type == "yamen":
		return true
	if b.type == "town":
		return false
	if b.type == "farm":
		return near_conn[idx(b.x, b.y)] <= 3
	if b.type == "station" or b.type == "dock":
		# 車站碼頭兩格內有通達道路即可與城中互通貨物
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x: int = b.x + dx
				var y: int = b.y + dy
				if inb(x, y) and conn_road(idx(x, y)):
					return true
		return false
	for dy in range(-1, b.size + 1):
		for dx in range(-1, b.size + 1):
			var inside: bool = dx >= 0 and dy >= 0 and dx < b.size and dy < b.size
			var corner: bool = (dx == -1 or dx == b.size) and (dy == -1 or dy == b.size)
			if inside or corner:
				continue
			var x: int = b.x + dx
			var y: int = b.y + dy
			if inb(x, y) and conn_road(idx(x, y)):
				return true
	return false


func valid_place(type: String, x: int, y: int) -> String:
	var d: Dictionary = Defs.B[type]
	var s: int = d.size
	if d.rank > rank:
		return "需晉為「%s」方可建造" % Defs.RANKS[d.rank]["name"]
	if money < d.cost:
		return "銀兩不足"
	var place: String = d.get("place", "land")
	for dy in s:
		for dx in s:
			if not inb(x + dx, y + dy):
				return "超出地界"
			var i := idx(x + dx, y + dy)
			if bld[i] >= 0:
				return "此處已有建築"
			if road[i] > 0:
				return "此處有道路"
			if wall[i] > 0:
				return "此處有城牆"
			var t := terrain[i]
			if t == Defs.T.WATER:
				return "不可建於水上"
			if t == Defs.T.MOUNTAIN and place != "mountain":
				return "山地無法營建"
			if place == "hill" and t != Defs.T.HILL:
				return "須建於丘陵"
			if place == "mountain" and t != Defs.T.MOUNTAIN:
				return "須建於山上"
			if place == "grass" and not (t == Defs.T.GRASS or t == Defs.T.FOREST):
				return "須建於平地"
	match place:
		"forest":
			var n := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if inb(x + dx, y + dy) and terrain[idx(x + dx, y + dy)] == Defs.T.FOREST:
						n += 1
			if n < 4:
				return "周圍林木不足（需四格）"
		"shore":
			if not _adjacent(x, y, s, func(i): return terrain[i] == Defs.T.WATER):
				return "須臨水"
		"road":
			if not _adjacent(x, y, s, func(i): return road[i] > 0):
				return "須臨道路"
	return ""


func _adjacent(x: int, y: int, s: int, pred: Callable) -> bool:
	for dy in range(-1, s + 1):
		for dx in range(-1, s + 1):
			var inside: bool = dx >= 0 and dy >= 0 and dx < s and dy < s
			var corner: bool = (dx == -1 or dx == s) and (dy == -1 or dy == s)
			if inside or corner or not inb(x + dx, y + dy):
				continue
			if pred.call(idx(x + dx, y + dy)):
				return true
	return false


func place_building(type: String, x: int, y: int) -> String:
	var err := valid_place(type, x, y)
	if err != "":
		return err
	var d: Dictionary = Defs.B[type]
	money -= d.cost
	for dy in d.size:
		for dx in d.size:
			zone[idx(x + dx, y + dy)] = 0
	zone_dirty = true
	var extra := {}
	if type == "station" or type == "dock":
		extra["name"] = "%s·%s" % ["驛" if type == "station" else "埠", _stem(station_count)]
		station_count += 1
	var id := add_building(type, x, y, extra)
	if type in ["station", "dock"]:
		var b: Dictionary = buildings[id]
		b.conn = _bconn(b)
	return ""


func _stem(n: int) -> String:
	var s: String = Defs.STEMS[n % 10]
	if n >= 10:
		s += Defs.cn_num(n / 10 + 1)
	return s


# ───────────────────────── 道路、運河、城牆、分區 ─────────────────────────

func road_cost(x: int, y: int, kind: int) -> int:
	if not inb(x, y):
		return -1
	var i := idx(x, y)
	if bld[i] >= 0 or terrain[i] == Defs.T.MOUNTAIN:
		return -1
	if road[i] >= kind:
		return 0
	var base := 5 if kind == 1 else 15
	if terrain[i] == Defs.T.WATER:
		return base * 5
	if terrain[i] == Defs.T.HILL:
		return base * 2
	return base


func build_roads(cells: Array, kind: int) -> int:
	if kind == 2 and rank < 1:
		log_msg("石板路需晉為「鎮」方可鋪設。", 2)
		return 0
	var spent := 0
	for c in cells:
		var cost := road_cost(c.x, c.y, kind)
		if cost <= 0:
			continue
		if money < cost:
			log_msg("銀兩不足，道路未能修完。", 2)
			break
		var i := idx(c.x, c.y)
		money -= cost
		spent += cost
		road[i] = kind
		zone[i] = 0
		if terrain[i] == Defs.T.FOREST:
			terrain[i] = Defs.T.GRASS
		astar_road.set_point_solid(c, false)
		mark(c.x, c.y)
		for d in DIRS:
			mark(c.x + d.x, c.y + d.y)
	if spent > 0:
		connectivity_dirty = true
		zone_dirty = true
	return spent


func build_canals(cells: Array) -> int:
	if rank < 1:
		log_msg("開鑿運河需晉為「鎮」。", 2)
		return 0
	var spent := 0
	for c in cells:
		if not inb(c.x, c.y):
			continue
		var i := idx(c.x, c.y)
		if bld[i] >= 0 or road[i] > 0 or wall[i] > 0:
			continue
		if terrain[i] == Defs.T.WATER or terrain[i] == Defs.T.MOUNTAIN:
			continue
		if money < 40:
			log_msg("銀兩不足，運河未能鑿完。", 2)
			break
		money -= 40
		spent += 40
		terrain[i] = Defs.T.WATER
		canal[i] = 1
		zone[i] = 0
		astar_water.set_point_solid(c, false)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				mark(c.x + dx, c.y + dy)
	if spent > 0:
		_compute_shore()
		zone_dirty = true
	return spent


func build_walls(cells: Array) -> int:
	if rank < 1:
		log_msg("修築城牆需晉為「鎮」。", 2)
		return 0
	var spent := 0
	for c in cells:
		if not inb(c.x, c.y):
			continue
		var i := idx(c.x, c.y)
		if bld[i] >= 0 or wall[i] > 0 or terrain[i] == Defs.T.WATER or terrain[i] == Defs.T.MOUNTAIN:
			continue
		if money < 20:
			log_msg("銀兩不足，城牆未能修完。", 2)
			break
		money -= 20
		spent += 20
		wall[i] = 1
		zone[i] = 0
		if terrain[i] == Defs.T.FOREST:
			terrain[i] = Defs.T.GRASS
		mark(c.x, c.y)
		for d in DIRS:
			mark(c.x + d.x, c.y + d.y)
	zone_dirty = true
	return spent


func bulldoze(x: int, y: int) -> String:
	if not inb(x, y):
		return ""
	var i := idx(x, y)
	if bld[i] >= 0:
		var b: Dictionary = buildings[bld[i]]
		if b.type == "yamen" or b.type == "town":
			return "此乃%s，不可拆除" % bname(b)
		remove_building(b.id)
		money -= 2
		connectivity_dirty = true
		return ""
	if wall[i] > 0:
		wall[i] = 0
	elif road[i] > 0:
		road[i] = 0
		astar_road.set_point_solid(Vector2i(x, y), true)
		connectivity_dirty = true
	elif canal[i] > 0:
		canal[i] = 0
		terrain[i] = Defs.T.GRASS
		astar_water.set_point_solid(Vector2i(x, y), true)
		_compute_shore()
	else:
		return ""
	money -= 2
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			mark(x + dx, y + dy)
	return ""


func can_zone(x: int, y: int, z: int) -> bool:
	if not inb(x, y):
		return false
	var i := idx(x, y)
	if road[i] > 0 or wall[i] > 0:
		return false
	if bld[i] >= 0 and not is_grow(buildings[bld[i]]):
		return false
	var t := terrain[i]
	if t == Defs.T.WATER or t == Defs.T.MOUNTAIN:
		return false
	if z == Defs.Z.FARM:
		if t == Defs.T.HILL:
			return false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if absi(dx) + absi(dy) <= 3 and inb(x + dx, y + dy) and road[idx(x + dx, y + dy)] > 0:
					return true
		return false
	for d in DIRS:
		if inb(x + d.x, y + d.y) and road[idx(x + d.x, y + d.y)] > 0:
			return true
	return false


func set_zone(x: int, y: int, z: int) -> void:
	if not inb(x, y):
		return
	var i := idx(x, y)
	if z != 0 and not can_zone(x, y, z):
		return
	if bld[i] >= 0:
		var b: Dictionary = buildings[bld[i]]
		if is_grow(b) and (z == 0 or Defs.GROW[b.type]["zone"] != z):
			remove_building(b.id)
		elif not is_grow(b):
			return
	if zone[i] != z:
		zone[i] = z
		zone_dirty = true
		mark(x, y)


# ───────────────────────── 連通、覆蓋 ─────────────────────────

func _compute_shore() -> void:
	for y in N:
		for x in N:
			var s := 0
			if terrain[idx(x, y)] != Defs.T.WATER:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						if inb(x + dx, y + dy) and terrain[idx(x + dx, y + dy)] == Defs.T.WATER:
							s = 1
			shore[idx(x, y)] = s


func _init_astar() -> void:
	astar_road = AStarGrid2D.new()
	astar_water = AStarGrid2D.new()
	for a in [astar_road, astar_water]:
		a.region = Rect2i(0, 0, N, N)
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		a.update()
	for y in N:
		for x in N:
			var i := idx(x, y)
			astar_road.set_point_solid(Vector2i(x, y), road[i] == 0)
			astar_water.set_point_solid(Vector2i(x, y), terrain[i] != Defs.T.WATER)


func _update_connectivity() -> void:
	road_dist.fill(-1)
	var q: Array[int] = []
	if buildings.has(yamen_id):
		var y: Dictionary = buildings[yamen_id]
		for dy in range(-1, y.size + 1):
			for dx in range(-1, y.size + 1):
				var x: int = y.x + dx
				var yy: int = y.y + dy
				if inb(x, yy) and road[idx(x, yy)] > 0 and road_dist[idx(x, yy)] < 0:
					road_dist[idx(x, yy)] = 0
					q.append(idx(x, yy))
	var h := 0
	while h < q.size():
		var i := q[h]
		h += 1
		var cx := i % N
		var cy := i / N
		for d in DIRS:
			var nx := cx + d.x
			var ny := cy + d.y
			if not inb(nx, ny):
				continue
			var j := idx(nx, ny)
			if road[j] > 0 and road_dist[j] < 0:
				road_dist[j] = road_dist[i] + 1
				q.append(j)
	near_conn.fill(255)
	var q2: Array[int] = []
	for i in N * N:
		if road[i] > 0 and conn_road(i):
			near_conn[i] = 0
			q2.append(i)
	h = 0
	while h < q2.size():
		var i := q2[h]
		h += 1
		if near_conn[i] >= 3:
			continue
		var cx := i % N
		var cy := i / N
		for d in DIRS:
			var nx := cx + d.x
			var ny := cy + d.y
			if inb(nx, ny) and near_conn[idx(nx, ny)] == 255:
				near_conn[idx(nx, ny)] = near_conn[i] + 1
				q2.append(idx(nx, ny))
	for b in buildings.values():
		b.conn = _bconn(b)
	connectivity_dirty = false


func _stamp(key: String, c: Vector2, r: float, amount: float, additive: bool) -> void:
	var arr: PackedFloat32Array = cover[key]
	var ri := int(ceil(r))
	var cx := int(round(c.x))
	var cy := int(round(c.y))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := cx + dx
			var y := cy + dy
			if not inb(x, y):
				continue
			var dist := Vector2(x, y).distance_to(c)
			if dist > r:
				continue
			var i := idx(x, y)
			if additive:
				arr[i] += amount * (1.0 - dist / (r + 1.0))
			else:
				arr[i] = maxf(arr[i], amount)


func _compute_cover() -> void:
	for k in COVER_KEYS:
		cover[k].fill(0.0)
	var edu_mult := 1.35 if policies.has("education") else 1.0
	for b in buildings.values():
		var c := b_center(b)
		if b.type == "shop":
			if b.conn:
				_stamp("market", c, 5 + b.level, 1.0, false)
			continue
		if b.type == "workshop":
			_stamp("pollution", c, 3, b.level * 0.8, true)
			continue
		if not Defs.B.has(b.type):
			continue
		var d: Dictionary = Defs.B[b.type]
		if d.has("pollute") and d.pollute > 0:
			_stamp("pollution", c, 3, d.pollute * 0.5, true)
		if not b.conn or not d.has("cover"):
			continue
		for k in d.cover:
			var r: float = d.cover[k]
			if k == "edu":
				r *= edu_mult
			_stamp(k, c, r, 1.0, k == "beauty")
	var sec_bonus := 0.3 if policies.has("baojia") else 0.0
	var sec: PackedFloat32Array = cover["security"]
	for y in N:
		for x in N:
			var i := idx(x, y)
			if wall[i] > 0 and road[i] > 0:
				_stamp("security", Vector2(x, y), 3, 1.0, false)
	var bea: PackedFloat32Array = cover["beauty"]
	var pol: PackedFloat32Array = cover["pollution"]
	for i in N * N:
		if sec_bonus > 0:
			sec[i] = minf(1.0, sec[i] + sec_bonus)
		var v := 12.0
		v += minf(bea[i], 6.0) * 7.0
		v += cover["water"][i] * 6.0 + sec[i] * 5.0 + cover["health"][i] * 5.0
		v += cover["edu"][i] * 6.0 + cover["faith"][i] * 4.0 + cover["fun"][i] * 4.0
		v += shore[i] * 8.0
		v -= pol[i] * 6.0
		if wall[i] > 0:
			v += 3.0
		var x := i % N
		var y := i / N
		for d in DIRS:
			if inb(x + d.x, y + d.y) and road[idx(x + d.x, y + d.y)] == 2:
				v += 8.0
				break
		lv[i] = clampf(v, 0.0, 100.0)


# ───────────────────────── 時間推進 ─────────────────────────

func _process(delta: float) -> void:
	if not running or speed == 0:
		return
	var dd: float = delta * SPEEDS[speed] / Defs.DAY_SEC
	_update_vehicles(dd)
	day_acc += dd
	var guard := 0
	while day_acc >= 1.0 and guard < 8:
		day_acc -= 1.0
		guard += 1
		_daily()


func advance_days(n: int) -> void:
	for i in n:
		_update_vehicles(1.0)
		_daily()


func _daily() -> void:
	if connectivity_dirty:
		_update_connectivity()
	day += 1
	for b in buildings.values():
		b.age += 1
		if b.age == 6:
			mark_b(b)
			building_fx.emit(b.id, "built")
	_update_fires()
	_grow()
	if day % 5 == 0:
		_check_combos()
		recount()
		_check_quests()
	if day >= 30:
		day = 0
		_monthly()


func _monthly() -> void:
	if connectivity_dirty:
		_update_connectivity()
	_compute_cover()
	_economy()
	_happiness()
	_station_transfer()
	_upgrades()
	_events()
	var old_season := season()
	month += 1
	if month >= 12:
		month = 0
		year += 1
		log_msg("新歲伊始，%s。" % date_str(), 0)
	if season() != old_season:
		for i in N * N:
			dirty[i] = true
	if drought > 0:
		drought -= 1
	recount()
	_check_rank()
	history.append({"pop": stats.pop, "money": money, "happy": stats.happy, "trade": report.income.get("貿易", 0.0), "net": report.get("net", 0.0)})
	if history.size() > 240:
		history.pop_front()
	_check_quests()
	month_passed.emit()


# ───────────────────────── 統計與需求 ─────────────────────────

func recount() -> void:
	var pop := 0
	var houses := 0
	var cj := 0
	var ij := 0
	var fj := 0
	var oj := 0
	var est := 0.0
	for b in buildings.values():
		match b.type:
			"house":
				pop += Defs.GROW.house.pop[b.level - 1]
				houses += 1
			"shop":
				cj += Defs.GROW.shop.jobs[b.level - 1]
			"workshop":
				ij += Defs.GROW.workshop.jobs[b.level - 1]
			"farm":
				fj += Defs.GROW.farm.jobs[b.level - 1]
				est += Defs.GROW.farm["yield"][b.level - 1] * fert[idx(b.x, b.y)] * 0.875
			_:
				if Defs.B.has(b.type) and b.conn:
					oj += Defs.B[b.type].get("jobs", 0)
	var labor := int(pop * 0.4)
	var jobs := cj + ij + fj + oj
	stats.pop = pop
	stats.houses = houses
	stats.labor = labor
	stats.jobs = jobs
	stats.staff = clampf(float(labor) / maxf(jobs, 1.0), 0.0, 1.0) if jobs > 0 else 1.0
	stats.unemp = maxf(0.0, labor - jobs) / maxf(labor, 1.0)
	stats.farm_est = est
	var happy: float = stats.happy
	var r := 25.0 + 75.0 * (jobs - labor * 0.85) / maxf(labor, 20.0) + (happy - 50.0) * 0.5
	if pop < 60:
		r = maxf(r, 75.0)
	if food_short > 0.2:
		r -= 50.0
	var dc := pop * 0.13 + 4.0
	var di := pop * 0.17 + 4.0
	var cons := pop * 0.2 * 1.4 + 3.0
	stats.dR = clampf(r, -100, 100)
	stats.dC = clampf(100.0 * (dc - cj) / dc, -100, 100)
	stats.dI = clampf(100.0 * (di - ij) / di, -100, 100)
	stats.dF = clampf(100.0 * (cons - est) / cons, -100, 100)


func _grow() -> void:
	if zone_dirty:
		for z in 5:
			zone_cells[z] = []
		for i in N * N:
			if zone[i] > 0:
				zone_cells[zone[i]].append(i)
		zone_dirty = false
	var dem := [0.0, stats.dR, stats.dC, stats.dI, stats.dF]
	for z in range(1, 5):
		var d: float = dem[z]
		var cells: Array = zone_cells[z]
		if d <= 0 or cells.is_empty():
			continue
		var tries := 2 + int(d / 25.0)
		for t in tries:
			var i: int = cells[rng.randi() % cells.size()]
			if rng.randf() * 100.0 > d:
				continue
			var x := i % N
			var y := i / N
			if _grow_ok(x, y, z):
				add_building(Defs.ZONE_GROW[z], x, y)
				recount()
				dem = [0.0, stats.dR, stats.dC, stats.dI, stats.dF]
				d = dem[z]
				if d <= 0:
					break


func _grow_ok(x: int, y: int, z: int) -> bool:
	var i := idx(x, y)
	if bld[i] >= 0 or road[i] > 0 or wall[i] > 0:
		return false
	var t := terrain[i]
	if t == Defs.T.WATER or t == Defs.T.MOUNTAIN:
		return false
	if z == Defs.Z.FARM:
		return t != Defs.T.HILL and near_conn[i] <= 3
	for d in DIRS:
		if inb(x + d.x, y + d.y) and conn_road(idx(x + d.x, y + d.y)):
			return true
	return false


# ───────────────────────── 經濟 ─────────────────────────

func _economy() -> void:
	var s: float = stats.staff
	var tm := 0.8 if policies.has("light_tax") else 1.0
	var farm_mult := 1.0
	if policies.has("farming"):
		farm_mult *= 1.25
	if policies.has("water_work"):
		farm_mult *= 1.1
	if drought > 0:
		farm_mult *= 0.5
	if bumper:
		farm_mult *= 1.5
	bumper = false
	var harvest: float = Defs.HARVEST[month]
	var grain_made := 0.0
	var shop_jobs := 0.0
	var sell_need := 0.0
	var make_total := 0.0
	var l3 := 0
	for b in buildings.values():
		var l: int = b.level - 1
		match b.type:
			"farm":
				if b.conn:
					var amt: float = Defs.GROW.farm["yield"][l] * fert[idx(b.x, b.y)] * harvest * farm_mult * s
					grain_made += add_stock("grain", amt)
					b.last = amt
			"shop":
				if b.conn:
					shop_jobs += Defs.GROW.shop.jobs[l]
					sell_need += Defs.GROW.shop.sell[l]
			"workshop":
				if b.conn:
					make_total += Defs.GROW.workshop.make[l] * s
			"house":
				if b.level == 3:
					l3 += 1
			_:
				var d: Dictionary = Defs.B.get(b.type, {})
				if not d.has("produce"):
					continue
				var st := s if b.conn else 0.7
				var ratio := 1.0
				if d.has("consume"):
					var need := 0.0
					var got := 0.0
					for c in d.consume:
						need += d.consume[c] * st
						got += _take_input(b, c, d.consume[c] * st)
					ratio = got / maxf(need, 0.001)
				var made := 0.0
				for c in d.produce:
					var amt: float = d.produce[c] * st * ratio
					if c == "silk" and policies.has("farming"):
						amt *= 1.25
					if b.conn:
						add_stock(c, amt)
					else:
						b.stock[c] = minf(b.stock.get(c, 0.0) + amt, 120.0)
					made += amt
				b.last = made
	# 作坊加工
	var remaining := make_total
	for pair in [["silk", "cloth"], ["iron", "ware"], ["wood", "ware"]]:
		var use := minf(remaining, stock.get(pair[0], 0.0))
		if use > 0:
			stock[pair[0]] -= use
			add_stock(pair[1], use)
			remaining -= use
	add_stock("ware", remaining * 0.4)
	ws_supplied = (make_total - remaining) / make_total if make_total > 0 else 0.0
	var ind_output := make_total - remaining * 0.6
	# 糧食
	var pop: int = stats.pop
	var need_food := pop * 0.2
	var got_food := take_stock("grain", need_food)
	got_food += take_stock("fish", need_food - got_food)
	food_short = 1.0 - got_food / need_food if need_food > 0 else 0.0
	if food_short > 0.3 and pop > 30:
		log_msg("城中缺糧，百姓怨聲載道！", 2)
	# 奢侈品
	var lux_need := l3 * 0.5
	var lux_got := 0.0
	for c in Defs.LUXURY:
		lux_got += take_stock(c, lux_need - lux_got)
	lux_ratio = lux_got / lux_need if lux_need > 0 else 1.0
	# 市肆售貨
	var got_goods := 0.0
	var lux_sold := 0.0
	for c in Defs.LUXURY:
		var g := take_stock(c, sell_need * 0.4 - lux_sold)
		lux_sold += g
	got_goods = lux_sold + take_stock("ware", sell_need - lux_sold)
	goods_ratio = got_goods / sell_need if sell_need > 0 else 1.0
	# 稅收
	var inc := {}
	inc["戶稅"] = pop * 0.3 * tax.res / 10.0 * tm
	inc["商稅"] = (shop_jobs * 1.0 * (0.4 + 0.6 * goods_ratio) + lux_sold * 1.5) * tax.com / 10.0 * tm * (1.2 if policies.has("open_trade") else 1.0)
	inc["工稅"] = ind_output * 0.8 * tax.ind / 10.0 * tm
	inc["田賦"] = grain_made * 0.25 * tax.farm / 10.0 * tm
	inc["貿易"] = trade_month
	var ci := 0.0
	for k in combo_count:
		ci += Defs.combo(k).get("income", 0) * combo_count[k]
	if ci > 0:
		inc["格局"] = ci
	trade_month = 0.0
	var outg := {"建築維護": 0.0, "道路城牆": 0.0, "車船": 0.0, "政令": 0.0}
	for b in buildings.values():
		if Defs.B.has(b.type):
			outg["建築維護"] += Defs.B[b.type]["upkeep"]
	for i in N * N:
		if road[i] == 1:
			outg["道路城牆"] += 0.25 if terrain[i] == Defs.T.WATER else 0.05
		elif road[i] == 2:
			outg["道路城牆"] += 0.4 if terrain[i] == Defs.T.WATER else 0.15
		if wall[i] > 0:
			outg["道路城牆"] += 0.2
	for v in vehicles.values():
		outg["車船"] += Defs.VEHICLES[v.kind]["upkeep"]
	for p in policies:
		outg["政令"] += Defs.POLICIES[p]["upkeep"]
	var total := 0.0
	for k in inc:
		total += inc[k]
	for k in outg:
		total -= outg[k]
	money += total - inc["貿易"]   # 貿易收入已於交貨時入帳
	report = {"income": inc, "expense": outg, "net": total}
	for r in routes.values():
		r.last = r.income
		r.income = 0.0
	if money < 0:
		log_msg("府庫虧空，須開源節流！", 2)


func _take_input(b: Dictionary, c: String, amt: float) -> float:
	if b.conn:
		return take_stock(c, amt)
	var got := 0.0
	for s in _stations_covering(b):
		var have: float = s.stock.get(c, 0.0)
		var g := minf(have, amt - got)
		s.stock[c] = have - g
		got += g
		if got >= amt:
			break
	return got


func _stations_covering(b: Dictionary) -> Array:
	var res := []
	var c := b_center(b)
	for s in buildings.values():
		if s.type != "station" and s.type != "dock":
			continue
		var r: int = Defs.B[s.type]["catch"]
		var sc := b_center(s)
		if absf(sc.x - c.x) <= r + 0.5 and absf(sc.y - c.y) <= r + 0.5:
			res.append(s)
	return res


func _station_transfer() -> void:
	for b in buildings.values():
		if b.conn or b.stock.is_empty() or b.type in ["station", "dock", "town"]:
			continue
		var sts := _stations_covering(b)
		if sts.is_empty():
			continue
		var s: Dictionary = sts[0]
		for c in b.stock.keys():
			var room: float = 500.0 - s.stock.get(c, 0.0)
			var mv := minf(room, b.stock[c])
			s.stock[c] = s.stock.get(c, 0.0) + mv
			b.stock[c] -= mv


func _happiness() -> void:
	var total := 0.0
	var wsum := 0.0
	var unemp: float = stats.unemp
	for b in buildings.values():
		if b.type != "house":
			continue
		var i := idx(b.x, b.y)
		var h := 34.0
		h += cover["water"][i] * 10.0 + cover["health"][i] * 8.0 + cover["security"][i] * 8.0
		h += cover["fire"][i] * 5.0 + cover["faith"][i] * 6.0 + cover["edu"][i] * 4.0
		h += cover["fun"][i] * 6.0 + cover["market"][i] * 6.0
		h += lv[i] * 0.15 - cover["pollution"][i] * 4.0
		h -= (tax.res - 10) * 2.0
		h -= food_short * 30.0
		h -= unemp * 20.0
		if policies.has("light_tax"):
			h += 8.0
		if policies.has("baojia"):
			h -= 4.0
		if policies.has("fire_ban"):
			h -= 3.0
		if b.level == 3 and lux_ratio < 0.5:
			h -= 10.0
		if not b.conn:
			h -= 30.0
		b.happy = clampf(h, 0.0, 100.0)
		var p: int = Defs.GROW.house.pop[b.level - 1]
		total += b.happy * p
		wsum += p
	stats.happy = total / wsum if wsum > 0 else 60.0


func _lux_stock() -> float:
	var t := 0.0
	for c in Defs.LUXURY:
		t += stock.get(c, 0.0)
	return t


func _upgrades() -> void:
	var s: float = stats.staff
	var lux := _lux_stock()
	var removed := 0
	for b in buildings.values().duplicate():
		if not is_grow(b) or b.age < 20:
			continue
		var i := idx(b.x, b.y)
		var up := false
		var chance := 0.0
		match b.type:
			"house":
				if b.happy < 25:
					b.bad += 1
					if b.bad >= 3:
						b.bad = 0
						if b.level > 1:
							b.level -= 1
							mark_b(b)
						else:
							remove_building(b.id)
							removed += 1
						continue
				else:
					b.bad = 0
				if b.level == 1:
					up = cover["water"][i] > 0 and cover["market"][i] > 0 and b.happy >= 50 and food_short < 0.2 and b.conn
					chance = 0.25
				elif b.level == 2:
					up = cover["water"][i] > 0 and cover["edu"][i] > 0 and (cover["faith"][i] > 0 or cover["fun"][i] > 0) \
						and lv[i] >= 45 and b.happy >= 62 and lux >= 3.0 and food_short < 0.1
					chance = 0.12
				elif cover["water"][i] == 0:
					b.level -= 1
					mark_b(b)
			"shop":
				if b.level == 1:
					up = goods_ratio >= 0.6 and lv[i] >= 25
					chance = 0.2
				elif b.level == 2:
					up = goods_ratio >= 0.7 and lux >= 3.0 and lv[i] >= 50 and cover["edu"][i] > 0
					chance = 0.1
			"workshop":
				if b.level == 1:
					up = s >= 0.85 and ws_supplied >= 0.5
					chance = 0.15
				elif b.level == 2:
					up = s >= 0.9 and ws_supplied >= 0.6 and cover["edu"][i] > 0
					chance = 0.1
			"farm":
				if b.level == 1:
					up = s >= 0.8 and (cover["water"][i] > 0 or fert[i] >= 1.1)
					chance = 0.12
				elif b.level == 2:
					up = s >= 0.9 and rank >= 2 and fert[i] >= 1.0
					chance = 0.08
		if up and b.level < 3 and rng.randf() < chance:
			b.level += 1
			mark_b(b)
			building_fx.emit(b.id, "upgrade")
	if removed > 0:
		log_msg("有%s戶人家不堪其苦，棄屋而去。" % Defs.cn_num(removed), 2)


func _check_rank() -> void:
	while rank < Defs.RANKS.size() - 1 and stats.pop >= Defs.RANKS[rank + 1]["pop"]:
		rank += 1
		var rw: int = Defs.RANKS[rank]["reward"]
		money += rw
		connectivity_dirty = true
		log_msg("聖旨到！%s人丁興旺，升格為「%s」，賞銀%d兩。" % [city_name, rank_name(), rw], 1)
		rank_changed.emit(rank)


# ───────────────────────── 格局 ─────────────────────────

## 與 cell 相距 r 格內（含建築占地）的建築。
func _near_buildings(cell: Vector2i, r: int) -> Array:
	var res := []
	for b in buildings.values():
		var dx := maxi(0, maxi(b.x - cell.x, cell.x - (b.x + b.size - 1)))
		var dy := maxi(0, maxi(b.y - cell.y, cell.y - (b.y + b.size - 1)))
		if maxi(dx, dy) <= r:
			res.append(b)
	return res


func _is_bridge(x: int, y: int) -> bool:
	return inb(x, y) and road[idx(x, y)] > 0 and terrain[idx(x, y)] == Defs.T.WATER


## 檢查各處格局：成立者標記於建築（b.combo）或橋面（combo_tiles），首次成立時收入圖鑑。
func _check_combos() -> void:
	var tiles := {}
	var counts := {}
	var member := {}
	var groups := []
	# 虹橋：沿橋走向找出整段橋面，看兩頭的市肆
	var seen := {}
	for i in N * N:
		if seen.has(i) or road[i] == 0 or terrain[i] != Defs.T.WATER:
			continue
		var x := i % N
		var y := i / N
		var d := Vector2i(1, 0) if (_is_bridge(x + 1, y) or _is_bridge(x - 1, y)) else Vector2i(0, 1)
		var s := Vector2i(x, y)
		while _is_bridge(s.x - d.x, s.y - d.y):
			s -= d
		var span := []
		var p := s
		while _is_bridge(p.x, p.y):
			span.append(idx(p.x, p.y))
			seen[idx(p.x, p.y)] = true
			p += d
		if span.size() < 2:
			continue
		var shops := {}
		for e in [s - d, p]:
			for b in _near_buildings(e, 3):
				if b.type == "shop":
					shops[b.id] = true
		if shops.size() >= 2:
			for k in span.size():
				tiles[span[k]] = [k, span.size()]
			counts["hongqiao"] = counts.get("hongqiao", 0) + 1
	# 瓦子、漕運
	for b in buildings.values():
		if b.type == "theater":
			var near := []
			for o in _near_buildings(Vector2i(b.x, b.y), 3):
				if o.type == "shop" and o.level >= 2:
					near.append(o)
			if near.size() >= 2:
				counts["wazi"] = counts.get("wazi", 0) + 1
				member[b.id] = "wazi"
				for o in near:
					member[o.id] = "wazi"
				groups.append({"id": "wazi", "members": [b.id] + near.map(func(o): return o.id)})
		elif b.type == "dock":
			var store := false
			var stores := []
			for o in _near_buildings(Vector2i(b.x, b.y), 3):
				if o.type in ["granary", "warehouse"]:
					store = true
					stores.append(o.id)
			var water := false
			for r in routes.values():
				if r.mode == "water" and (r.a == b.id or r.b == b.id):
					water = true
			if store and water:
				counts["caoyun"] = counts.get("caoyun", 0) + 1
				member[b.id] = "caoyun"
				groups.append({"id": "caoyun", "members": [b.id] + stores})
	# 四合院：四座瓦屋以上的民居排成二乘二；quad 記其在院中的位置
	var quad := {}
	for b in buildings.values():
		if b.type != "house" or b.level < 2 or member.has(b.id):
			continue
		var cells := [Vector2i(b.x, b.y), Vector2i(b.x + 1, b.y), Vector2i(b.x, b.y + 1), Vector2i(b.x + 1, b.y + 1)]
		var group := []
		for q in cells:
			var o := building_at(q.x, q.y)
			if o.is_empty() or o.type != "house" or o.level < 2 or member.has(o.id):
				break
			group.append(o)
		if group.size() == 4:
			counts["siheyuan"] = counts.get("siheyuan", 0) + 1
			for k in 4:
				member[group[k].id] = "siheyuan"
				quad[group[k].id] = k
			groups.append({"id": "siheyuan", "members": group.map(func(o): return o.id)})
	# 其餘以「甲建築若干格內有乙建築」成立
	var pairs := [["fansha", "temple", ["pagoda"], 3], ["yashu", "yamen", ["archway"], 3], ["sangji", "mulberry", ["fishery"], 3],
		["chama", "tea", ["station"], 5], ["guanyao", "kiln", ["quarry"], 4]]
	for pr in pairs:
		for b in buildings.values():
			if b.type != pr[1]:
				continue
			var mates := []
			for o in _near_buildings(Vector2i(b.x, b.y), pr[3] + b.size - 1):
				if o.type in pr[2]:
					mates.append(o)
			if mates.is_empty():
				continue
			counts[pr[0]] = counts.get(pr[0], 0) + 1
			member[b.id] = pr[0]
			for o in mates:
				if not member.has(o.id):
					member[o.id] = pr[0]
			groups.append({"id": pr[0], "members": [b.id] + mates.map(func(o): return o.id)})
	# 格局範圍：成員所占之外接框內，非路非水的空地一併鋪地，使之連成一片
	var ground := {}
	for gp in groups:
		var x0 := N
		var y0 := N
		var x1 := -1
		var y1 := -1
		for id in gp.members:
			var mb: Dictionary = buildings[id]
			x0 = mini(x0, mb.x)
			y0 = mini(y0, mb.y)
			x1 = maxi(x1, mb.x + mb.size - 1)
			y1 = maxi(y1, mb.y + mb.size - 1)
		if x1 - x0 > 7 or y1 - y0 > 7:
			continue
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var k := idx(xx, yy)
				if road[k] > 0 or terrain[k] == Defs.T.WATER:
					continue
				if bld[k] >= 0 and not gp.members.has(bld[k]):
					continue
				ground[k] = gp.id
	for k in combo_ground:
		if ground.get(k, "") != combo_ground[k]:
			dirty[k] = true
	for k in ground:
		if not combo_ground.has(k):
			dirty[k] = true
	combo_ground = ground
	combo_groups = groups
	for i in combo_tiles:
		if not tiles.has(i):
			dirty[i] = true
	for i in tiles:
		if not combo_tiles.has(i):
			dirty[i] = true
	combo_tiles = tiles
	for b in buildings.values():
		var m: String = member.get(b.id, "")
		var qv: int = quad.get(b.id, -1)
		if b.get("combo", "") != m or b.get("quad", -1) != qv:
			var fresh: bool = m != "" and b.get("combo", "") != m
			b.combo = m
			b.quad = qv
			mark_b(b)
			if fresh:
				building_fx.emit(b.id, "combo")
	combo_count = counts
	for id in counts:
		if not combos_found.has(id):
			combos_found[id] = date_str()
			log_msg("格局成立：「%s」。%s" % [Defs.combo(id).name, Defs.combo(id).verse], 1)
			combo_found.emit(id)


# ───────────────────────── 詔令 ─────────────────────────

func count_type(t: String, min_level: int = 1) -> int:
	var n := 0
	for b in buildings.values():
		if b.type == t and b.level >= min_level and b.age >= 6:
			n += 1
	return n


func current_quests(n: int = 3) -> Array:
	var res := []
	for q in Defs.QUESTS:
		if not quests_done.has(q.id):
			res.append(q)
			if res.size() >= n:
				break
	return res


func _quest_met(id: String) -> bool:
	match id:
		"res":
			return zone.count(Defs.Z.RES) + count_type("house") >= 10
		"farm":
			return count_type("farm") >= 5
		"well":
			return count_type("well") >= 1
		"pop50":
			return stats.pop >= 50
		"granary":
			return count_type("granary") >= 1
		"shop":
			return count_type("shop") >= 3
		"tile":
			return count_type("house", 2) >= 1
		"zhen":
			return rank >= 1
		"route":
			return not routes.is_empty()
		"temple":
			return count_type("temple") >= 1
		"trade":
			return report.income.get("貿易", 0.0) >= 100.0
		"court":
			return count_type("house", 3) >= 1
		"xian":
			return rank >= 2
		"lux":
			return stock.get("cloth", 0.0) + stock.get("porcelain", 0.0) >= 20.0
		"zhou":
			return rank >= 3
		"pagoda":
			return count_type("pagoda") >= 1
		"fu":
			return rank >= 4
		"jing":
			return rank >= 5
	return false


func _check_quests() -> void:
	# 只檢查最前面幾條，循序漸進
	for q in current_quests(3):
		if _quest_met(q.id):
			quests_done[q.id] = true
			money += q.reward
			if q.reward > 0:
				log_msg("詔令達成：「%s」，賞銀%d兩。" % [q.text, q.reward], 1)
			else:
				log_msg("詔令達成：「%s」。%s已成天下名都！" % [q.text, city_name], 1)
			quest_done.emit(q.id)


# ───────────────────────── 災異與事件 ─────────────────────────

func _update_fires() -> void:
	for id in burning.keys():
		if not buildings.has(id):
			burning.erase(id)
			continue
		var b: Dictionary = buildings[id]
		b.fire -= 1
		var fc: float = cover["fire"][idx(b.x, b.y)]
		for d in DIRS:
			var n := building_at(b.x + d.x, b.y + d.y)
			if not n.is_empty() and n.fire <= 0 and n.type not in ["yamen", "town", "farm"] \
					and rng.randf() < 0.05 * (1.0 - 0.8 * fc):
				n.fire = 10
				burning[n.id] = true
				mark_b(n)
		if b.fire <= 0:
			burning.erase(id)
			if rng.randf() < 0.25 + 0.7 * fc:
				log_msg("%s火勢已被撲滅。" % bname(b), 0)
				mark_b(b)
			else:
				log_msg("%s焚毀殆盡。" % bname(b), 2)
				remove_building(id)


func _events() -> void:
	# 火災
	var fire_p := 0.0012 * (0.5 if policies.has("fire_ban") else 1.0) * (1.5 if season() == 3 else 1.0)
	for b in buildings.values():
		if b.type in ["farm", "yamen", "town"] or b.fire > 0:
			continue
		var fc: float = cover["fire"][idx(b.x, b.y)]
		if rng.randf() < fire_p * (1.0 - 0.85 * fc):
			b.fire = 10
			burning[b.id] = true
			mark_b(b)
			log_msg("%s走水了！" % bname(b), 2)
	var pop: int = stats.pop
	if pop < 40:
		return
	# 旱災
	if month in [3, 4, 5] and drought == 0 and rng.randf() < 0.04:
		drought = 3
		log_msg("久旱不雨，田禾枯槁，糧產減半。", 2)
	# 洪水
	if month in [4, 5, 6] and not policies.has("water_work") and rng.randf() < 0.04:
		_flood()
	# 豐年
	if month == 7 and rng.randf() < 0.18:
		bumper = true
		log_msg("風調雨順，今歲大熟！", 1)
	# 瘟疫
	var hcov := _avg_cover_houses("health")
	if rng.randf() < 0.025 and hcov < 0.5:
		var lost := 0
		for b in buildings.values().duplicate():
			if b.type == "house" and rng.randf() < 0.12:
				if b.level > 1:
					b.level -= 1
					mark_b(b)
				else:
					remove_building(b.id)
				lost += 1
		log_msg("疫病流行，%s戶染疾。廣設醫館可防。" % Defs.cn_num(lost), 2)
	# 盜匪
	if rng.randf() < 0.03 and _avg_cover_houses("security") < 0.5 and money > 500:
		var l := money * 0.08
		money -= l
		log_msg("盜匪夜劫府庫，失銀%d兩。" % int(l), 2)
	# 朝廷巡察
	if month == 9 and stats.happy >= 60 and pop >= 200:
		var rw := 200 * (rank + 1)
		money += rw
		log_msg("巡按御史過境，嘉%s政通人和，賜銀%d兩。" % [city_name, rw], 1)
	# 商旅
	if rng.randf() < 0.04:
		var g := 100 + rng.randi() % 250
		money += g
		log_msg("西域商隊途經此地，納稅銀%d兩。" % g, 1)


func _avg_cover_houses(key: String) -> float:
	var t := 0.0
	var n := 0
	for b in buildings.values():
		if b.type == "house":
			t += cover[key][idx(b.x, b.y)]
			n += 1
	return t / n if n > 0 else 1.0


func _flood() -> void:
	var tries := 0
	while tries < 50:
		tries += 1
		var x := rng.randi() % N
		var y := rng.randi() % N
		if terrain[idx(x, y)] != Defs.T.WATER or canal[idx(x, y)] > 0:
			continue
		var hit := 0
		for b in buildings.values().duplicate():
			if not is_grow(b):
				continue
			if absi(b.x - x) > 6 or absi(b.y - y) > 6:
				continue
			var wet := false
			for d in DIRS:
				var nx: int = b.x + d.x
				var ny: int = b.y + d.y
				if inb(nx, ny) and terrain[idx(nx, ny)] == Defs.T.WATER:
					wet = true
			if wet and rng.randf() < 0.5:
				hit += 1
				if b.type == "farm":
					b.level = 1
					mark_b(b)
				else:
					remove_building(b.id)
		if hit > 0:
			log_msg("河水暴漲，沖毀%s處屋舍田畝。施行「興修水利」可防。" % Defs.cn_num(hit), 2)
		return


# ───────────────────────── 貨運 ─────────────────────────

func is_stop(b: Dictionary) -> bool:
	return b.type in ["station", "dock", "town"]


func stop_modes(b: Dictionary) -> Array:
	match b.type:
		"station":
			return ["road"]
		"dock":
			return ["water"]
		"town":
			var m := []
			if stop_cell(b, "road") != NO_CELL:
				m.append("road")
			if stop_cell(b, "water") != NO_CELL:
				m.append("water")
			return m
	return []


func stop_cell(b: Dictionary, mode: String) -> Vector2i:
	for dy in range(-1, b.size + 1):
		for dx in range(-1, b.size + 1):
			var inside: bool = dx >= 0 and dy >= 0 and dx < b.size and dy < b.size
			var corner: bool = (dx == -1 or dx == b.size) and (dy == -1 or dy == b.size)
			if inside or corner:
				continue
			var x: int = b.x + dx
			var y: int = b.y + dy
			if not inb(x, y):
				continue
			var i := idx(x, y)
			if mode == "road" and road[i] > 0:
				return Vector2i(x, y)
			if mode == "water" and terrain[i] == Defs.T.WATER:
				return Vector2i(x, y)
	return NO_CELL


func find_path(mode: String, a: Vector2i, b: Vector2i) -> Array:
	var g := astar_road if mode == "road" else astar_water
	if a == NO_CELL or b == NO_CELL or g.is_point_solid(a) or g.is_point_solid(b):
		return []
	return Array(g.get_id_path(a, b))


func route_mode(a: Dictionary, b: Dictionary) -> String:
	var ma := stop_modes(a)
	var mb := stop_modes(b)
	for m in ["road", "water"]:
		if m in ma and m in mb:
			return m
	return ""


func create_route(a_id: int, b_id: int) -> String:
	if a_id == b_id:
		return "起訖不可為同一處"
	var a: Dictionary = buildings.get(a_id, {})
	var b: Dictionary = buildings.get(b_id, {})
	if a.is_empty() or b.is_empty() or not is_stop(a) or not is_stop(b):
		return "請選擇驛站、碼頭或外邑"
	var mode := route_mode(a, b)
	if mode == "":
		return "兩處運輸方式不同（車走驛站，船走碼頭）"
	var p := find_path(mode, stop_cell(a, mode), stop_cell(b, mode))
	if p.is_empty():
		return "兩處之間無%s相通" % ("道路" if mode == "road" else "水道")
	var kind := best_vehicle(mode)
	if money < Defs.VEHICLES[kind]["cost"]:
		return "銀兩不足以購置%s" % Defs.VEHICLES[kind]["name"]
	var r := {"id": next_route, "a": a_id, "b": b_id, "mode": mode, "income": 0.0, "last": 0.0, "total": 0.0,
		"color": Color.from_hsv(fmod(next_route * 0.17, 1.0), 0.65, 0.85)}
	next_route += 1
	routes[r.id] = r
	add_vehicle(r.id, kind)
	log_msg("開闢新路線：%s ⇄ %s。" % [bname(a), bname(b)], 1)
	return ""


func best_vehicle(mode: String) -> String:
	var best := ""
	for k in Defs.VEHICLES:
		var v: Dictionary = Defs.VEHICLES[k]
		if v.mode == mode and v.rank <= rank:
			best = k
	return best


func add_vehicle(route_id: int, kind: String = "") -> String:
	var r: Dictionary = routes.get(route_id, {})
	if r.is_empty():
		return "路線不存在"
	if kind == "":
		kind = best_vehicle(r.mode)
	var d: Dictionary = Defs.VEHICLES[kind]
	if money < d.cost:
		return "銀兩不足"
	money -= d.cost
	var n := route_vehicles(route_id).size()
	var v := {"id": next_veh, "kind": kind, "route": route_id, "at": r.a, "to": r.b, "path": [], "pi": 0, "t": 0.0,
		"cargo": "", "amt": 0.0, "state": "load", "wait": 1.0 + n * 4.0, "trip": 0.0,
		"pos": Vector2(stop_cell(buildings[r.a], r.mode)), "dir": Vector2i(1, 0)}
	next_veh += 1
	vehicles[v.id] = v
	return ""


func remove_vehicle(route_id: int) -> void:
	var vs := route_vehicles(route_id)
	if vs.is_empty():
		return
	var v: Dictionary = vs.back()
	money += Defs.VEHICLES[v.kind]["cost"] * 0.4
	vehicles.erase(v.id)


func delete_route(route_id: int, refund: float = 0.4) -> void:
	for v in route_vehicles(route_id):
		money += Defs.VEHICLES[v.kind]["cost"] * refund
		vehicles.erase(v.id)
	routes.erase(route_id)


func route_vehicles(route_id: int) -> Array:
	var res := []
	for v in vehicles.values():
		if v.route == route_id:
			res.append(v)
	return res


func _update_vehicles(dd: float) -> void:
	var boat_mult := 1.3 if policies.has("grand_canal") else 1.0
	for v in vehicles.values():
		var r: Dictionary = routes.get(v.route, {})
		if r.is_empty():
			continue
		if v.state == "load" or v.state == "lost":
			v.wait -= dd
			if v.wait <= 0:
				_depart(v, r)
			continue
		var d: Dictionary = Defs.VEHICLES[v.kind]
		var p: Array = v.path
		var cur: Vector2i = p[mini(v.pi, p.size() - 1)]
		var sp: float = d.speed
		if r.mode == "road":
			if road[idx(cur.x, cur.y)] == 2:
				sp *= 1.35
		else:
			sp *= boat_mult
		v.t += sp * dd
		v.trip += dd
		while v.t >= 1.0 and v.pi < p.size() - 1:
			v.t -= 1.0
			v.pi += 1
		if v.pi >= p.size() - 1:
			v.pos = Vector2(p.back())
			_arrive(v, r)
		else:
			var a: Vector2i = p[v.pi]
			var b: Vector2i = p[v.pi + 1]
			v.dir = b - a
			v.pos = Vector2(a).lerp(Vector2(b), v.t)


func _depart(v: Dictionary, r: Dictionary) -> void:
	var src: Dictionary = buildings.get(v.at, {})
	var dst: Dictionary = buildings.get(v.to, {})
	if src.is_empty() or dst.is_empty():
		return
	var p := find_path(r.mode, stop_cell(src, r.mode), stop_cell(dst, r.mode))
	if p.size() < 2:
		v.state = "lost"
		v.wait = 10.0
		return
	if v.state == "load":
		_load(v, src, dst)
	v.path = p
	v.pi = 0
	v.t = 0.0
	v.trip = 0.0
	v.state = "move"


func _accepts(dst: Dictionary, c: String) -> bool:
	if dst.type == "town" or dst.conn:
		return true
	for b in buildings.values():
		var d: Dictionary = Defs.B.get(b.type, {})
		if d.has("consume") and d.consume.has(c) and not b.conn and dst in _stations_covering(b):
			return true
	return false


func _available(src: Dictionary, c: String) -> float:
	var a: float = src.stock.get(c, 0.0)
	if src.conn:
		a += maxf(0.0, stock.get(c, 0.0) - cap_of(c) * 0.5)
	return a


func _load(v: Dictionary, src: Dictionary, dst: Dictionary) -> void:
	if src.type == "town":
		return
	var cap: float = Defs.VEHICLES[v.kind]["cap"]
	var best := ""
	var best_val := 0.0
	for c in Defs.CARGO_ORDER:
		if not _accepts(dst, c):
			continue
		var a := minf(_available(src, c), cap)
		var val: float = a * Defs.CARGO[c]["price"]
		if a >= 1.0 and val > best_val:
			best_val = val
			best = c
	if best == "":
		return
	var want := minf(_available(src, best), cap)
	var from_st := minf(src.stock.get(best, 0.0), want)
	src.stock[best] = src.stock.get(best, 0.0) - from_st
	var from_pool := take_stock(best, want - from_st)
	v.cargo = best
	v.amt = from_st + from_pool


func _arrive(v: Dictionary, r: Dictionary) -> void:
	var dst: Dictionary = buildings.get(v.to, {})
	var src: Dictionary = buildings.get(v.at, {})
	if v.amt > 0 and not dst.is_empty():
		var c: String = v.cargo
		var price: float = Defs.CARGO[c]["price"]
		var dist := 0.0
		if not src.is_empty():
			dist = absf(src.x - dst.x) + absf(src.y - dst.y)
		var pay := 0.0
		if dst.type == "town":
			var mult: float = dst.get("mult", {}).get(c, 1.0)
			var timef := clampf(1.25 - v.trip / 80.0, 0.4, 1.25)
			pay = v.amt * price * mult * (0.5 + dist / 50.0) * timef
			if policies.has("open_trade"):
				pay *= 1.2
		else:
			if dst.conn:
				add_stock(c, v.amt)
			else:
				dst.stock[c] = minf(dst.stock.get(c, 0.0) + v.amt, 500.0)
			pay = v.amt * price * dist / 100.0
		money += pay
		trade_month += pay
		r.income += pay
		r.total += pay
	v.cargo = ""
	v.amt = 0.0
	var a: int = v.at
	v.at = v.to
	v.to = a
	v.state = "load"
	v.wait = 2.0


# ───────────────────────── 政務 ─────────────────────────

func toggle_policy(id: String) -> String:
	if policies.has(id):
		policies.erase(id)
		log_msg("廢止「%s」。" % Defs.POLICIES[id]["name"], 0)
		return ""
	if Defs.POLICIES[id]["rank"] > rank:
		return "品級不足"
	policies[id] = true
	log_msg("頒行「%s」。" % Defs.POLICIES[id]["name"], 1)
	return ""


# ───────────────────────── 資訊文字 ─────────────────────────

## 以下資訊文字供介面顯示：{i:名} 為行內圖示，[b] 標出數值與名稱。
const C_GOOD := "#3f7a57"
const C_BAD := "#b1372a"
const C_NOTE := "#8b7d6e"


static func _head(text: String) -> String:
	return "[font_size=18][color=#29241f][b]%s[/b][/color][/font_size]" % text


func tile_info(x: int, y: int) -> String:
	if not inb(x, y):
		return ""
	var i := idx(x, y)
	var tn: String = ["平地", "水域", "林地", "丘陵", "山嶺"][terrain[i]]
	if canal[i] > 0:
		tn = "運河"
	var s := "[b]%s[/b]　[color=%s]%d, %d[/color]\n" % [tn, C_NOTE, x, y]
	if road[i] > 0:
		var kind := "%s%s" % ["橋 · " if terrain[i] == Defs.T.WATER else "", "土路" if road[i] == 1 else "石板路"]
		if conn_road(i):
			s += "{i:road} %s　[color=%s]通達縣衙[/color]，沿路 [b]%d[/b] 格\n" % [kind, C_GOOD, road_dist[i]]
		else:
			s += "{i:road} %s　[color=%s]不通縣衙[/color]\n" % [kind, C_BAD]
	if wall[i] > 0:
		s += "城牆%s\n" % ("（城門）" if road[i] > 0 else "")
	if zone[i] > 0:
		s += "{i:zone} 分區 [b]%s[/b]\n" % Defs.ZONE_NAMES[zone[i]]
	s = "[stats]land,%d,地價;grain,%d%%,肥力[/stats]" % [int(lv[i]), int(fert[i] * 100)] + s
	s += _cover_line(i)
	return s


func _cover_line(i: int) -> String:
	var names := {"water": "水", "security": "治安", "health": "醫", "fire": "防火", "edu": "教化", "faith": "信仰", "fun": "娛樂", "market": "市集"}
	var have := []
	for k in names:
		if cover[k][i] > 0:
			have.append("[b]%s[/b]" % names[k])
	var s := "照應　%s" % ("・".join(have) if have.size() > 0 else "[color=%s]無[/color]" % C_NOTE)
	if cover["pollution"][i] > 0.3:
		s += "\n[color=%s]煙塵 [b]%.1f[/b][/color]" % [C_BAD, cover["pollution"][i]]
	return s


## 一項條件：達成者淡色打勾，未達成者紅叉，可附數值門檻。
static func _need(ok: bool, text: String) -> String:
	if ok:
		return "{i:check} [color=%s]%s[/color]\n" % [C_NOTE, text.replace("[b]", "").replace("[/b]", "")]
	return "{i:cross} %s\n" % text


func building_info(b: Dictionary) -> String:
	var i := idx(b.x, b.y)
	var s := ""
	var l: int = b.level - 1
	# 第一行：最要緊的狀態
	if b.fire > 0:
		s += "{i:fire} [warn]正在燃燒：望火樓可撲救[/warn]\n\n"
	elif b.age < 6:
		s += "{i:note} [color=%s]興建中……[/color]\n" % C_NOTE
	elif b.type != "town" and b.type != "yamen" and not b.conn:
		s += "{i:bad} [warn]未通達：須以道路連接縣衙[/warn]\n\n"
	match b.type:
		"house":
			s += "[stats]people,%d,居民;%s,%d,民心,%s;land,%d,地價[/stats]" % [
				Defs.GROW.house.pop[l], "mood_good" if b.happy >= 65 else ("mood_bad" if b.happy < 40 else "mood"), int(b.happy), C_BAD if b.happy < 40 else "", int(lv[i])]
			if b.level < 3:
				s += "\n" + _head("升為%s還缺" % Defs.GROW.house.names[b.level]) + "\n"
				var rows := []
				if b.level == 1:
					rows = [[cover["water"][i] > 0, "[b]水井[/b]"], [cover["market"][i] > 0, "[b]市集[/b]"], [b.happy >= 50, "民心 [b]%d[/b]／50" % int(b.happy)]]
				else:
					rows = [[cover["edu"][i] > 0, "[b]私塾[/b]或[b]書院[/b]"], [cover["faith"][i] > 0 or cover["fun"][i] > 0, "[b]寺廟[/b]或[b]戲樓[/b]"],
						[lv[i] >= 45, "地價 [b]%d[/b]／45" % int(lv[i])], [_lux_stock() >= 3, "城中有[b]綢緞、瓷器或茶[/b]"], [b.happy >= 62, "民心 [b]%d[/b]／62" % int(b.happy)]]
				rows.sort_custom(func(a, c): return not a[0] and c[0])
				for r in rows:
					s += _need(r[0], r[1])
			else:
				s += "[color=%s]已是最高一階。[/color]\n" % C_NOTE
		"shop":
			var gr := int(goods_ratio * 100)
			s += "[stats]people,%d,伙計;store,%d%%,貨源,%s;land,%d,地價[/stats]" % [
				Defs.GROW.shop.jobs[l], gr, C_GOOD if gr >= 60 else C_BAD, int(lv[i])]
			if gr < 60:
				s += "{i:hint} [b]貨源不足[/b]：多設[k]作坊[/k]，或經商路運入器物、綢緞。\n"
		"workshop":
			var ws := int(ws_supplied * 100)
			s += "[stats]people,%d,匠人;store,%d%%,原料,%s[/stats]" % [Defs.GROW.workshop.jobs[l], ws, C_GOOD if ws >= 50 else C_BAD]
			s += "[k]絲[/k] → 綢緞　[k]鐵[/k]、[k]木[/k] → 器物\n[color=%s]無料時只能手作少量器物[/color]\n" % C_NOTE
		"farm":
			s += "[stats]people,%d,農人;land,%d%%,肥力;grain,%.0f,上月收成[/stats]" % [Defs.GROW.farm.jobs[l], int(fert[i] * 100), b.last]
		"town":
			var m: Dictionary = b.get("mult", {})
			var parts := []
			for c in m:
				parts.append("[b]%s[/b] [color=%s]×%.1f[/color]" % [Defs.cargo_name(c), C_GOOD, m[c]])
			s += "收購一切貨物，[k]路途愈遠，獲利愈豐[/k]。\n{i:silver} 高價收購　%s\n" % "、".join(parts)
		_:
			var d: Dictionary = Defs.B.get(b.type, {})
			var st := []
			if d.has("produce"):
				st.append("industry,%.0f,上月產出" % b.last)
			if d.get("jobs", 0) > 0:
				st.append("people,%d,職缺" % d.jobs)
			if d.upkeep > 0:
				st.append("silver,%d,月費" % d.upkeep)
			if not st.is_empty():
				s += "[stats]%s[/stats]" % ";".join(st)
			s += "[color=#5d5147]%s[/color]\n" % d.get("desc", "")
			if d.has("produce") and not b.conn:
				s += "[color=%s]未通達縣衙，貨物須經驛站或碼頭外運。[/color]\n" % C_NOTE
	if b.get("combo", "") != "":
		s += "\n{i:good} 格局「[k]%s[/k]」成立中\n" % Defs.combo(b.combo).get("name", "")
	if not b.stock.is_empty():
		var parts := []
		for c in Defs.CARGO_ORDER:
			if b.stock.get(c, 0.0) >= 0.5:
				parts.append("[b]%s[/b] %d" % [Defs.cargo_name(c), int(b.stock[c])])
		if parts.size() > 0:
			s += "{i:store} 存貨　%s\n" % "、".join(parts)
	if is_stop(b):
		var rs := []
		for r in routes.values():
			if r.a == b.id or r.b == b.id:
				rs.append("{i:route} [b]%s[/b] 至 [b]%s[/b]" % [bname(buildings[r.a]), bname(buildings[r.b])])
		s += "\n" + _head("商路") + "\n" + ("[color=%s]尚無，點下方按鈕開闢。[/color]" % C_NOTE if rs.is_empty() else "\n".join(rs)) + "\n"
	return s.strip_edges()


# ───────────────────────── 存檔 ─────────────────────────

const SAVE_PATH := "user://save.dat"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var vs := {}
	for v in vehicles.values():
		var c: Dictionary = v.duplicate()
		c.path = []
		if c.state == "move":
			c.state = "load"
			c.wait = 1.0
			# 在途之貨就地送返起點
			c.amt = 0.0
			c.cargo = ""
		vs[v.id] = c
	var data := {
		"version": 1, "terrain": terrain, "road": road, "zone": zone, "wall": wall, "canal": canal,
		"tree_var": tree_var, "fert": fert, "buildings": buildings, "routes": routes, "vehicles": vs,
		"next_id": next_id, "next_route": next_route, "next_veh": next_veh, "yamen_id": yamen_id,
		"station_count": station_count, "city_name": city_name, "era": era, "year": year, "month": month,
		"day": day, "rank": rank, "money": money, "stock": stock, "policies": policies, "tax": tax,
		"stats": stats, "drought": drought, "log": log_lines, "quests": quests_done, "combos": combos_found, "history": history, "seed": map_seed, "rng": rng.state,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)
	f.close()
	log_msg("已存檔。", 0)
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var d = f.get_var()
	f.close()
	if typeof(d) != TYPE_DICTIONARY or d.get("version", 0) != 1:
		return false
	_reset()
	terrain = d.terrain
	road = d.road
	zone = d.zone
	wall = d.wall
	canal = d.canal
	tree_var = d.tree_var
	fert = d.fert
	buildings = d.buildings
	routes = d.routes
	vehicles = d.vehicles
	next_id = d.next_id
	next_route = d.next_route
	next_veh = d.next_veh
	yamen_id = d.yamen_id
	station_count = d.station_count
	city_name = d.city_name
	era = d.era
	year = d.year
	month = d.month
	day = d.day
	rank = d.rank
	money = d.money
	stock = d.stock
	policies = d.policies
	tax = d.tax
	stats.merge(d.stats, true)
	drought = d.drought
	log_lines = d.log
	quests_done = d.get("quests", {})
	combos_found = d.get("combos", {})
	history = d.get("history", [])
	map_seed = d.seed
	rng.state = d.rng
	for b in buildings.values():
		if b.type == "town" and b.name == "長安":
			b.name = "洛陽"
		for dy in b.size:
			for dx in b.size:
				bld[idx(b.x + dx, b.y + dy)] = b.id
		if b.fire > 0:
			burning[b.id] = true
	_finish_setup()
	log_msg("已讀取存檔。", 0)
	return true
