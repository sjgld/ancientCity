extends RefCounted
## 生成地形：平原居中、四周丘山、一條大河穿城而過，外邑分處邊陲。


static func generate(g, seed_v: int) -> void:
	var N: int = g.N
	var T = Defs.T
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var hn := FastNoiseLite.new()
	hn.seed = seed_v
	hn.frequency = 0.035
	hn.fractal_octaves = 4
	var mn := FastNoiseLite.new()
	mn.seed = seed_v + 7
	mn.frequency = 0.06
	var fn := FastNoiseLite.new()
	fn.seed = seed_v + 13
	fn.frequency = 0.05
	var half := N * 0.5
	for y in N:
		for x in N:
			var i: int = y * N + x
			var d := Vector2(x - half, y - half).length() / half
			var h := hn.get_noise_2d(x, y) + d * 0.4 - 0.12
			var t: int = T.GRASS
			if h > 0.4:
				t = T.MOUNTAIN
			elif h > 0.24:
				t = T.HILL
			elif mn.get_noise_2d(x, y) > 0.15 and d > 0.2:
				t = T.FOREST
			g.terrain[i] = t
			g.tree_var[i] = rng.randi() % 256
			g.fert[i] = clampf(0.78 + fn.get_noise_2d(x, y) * 0.5, 0.5, 1.05)

	# 大河：自北而南
	var x0 := float(rng.randi_range(int(N * 0.28), int(N * 0.4)))
	var x1 := float(rng.randi_range(int(N * 0.58), int(N * 0.72)))
	var phase := rng.randf() * TAU
	var cx := int(x0)
	var river_x := []
	for y in N:
		var target := lerpf(x0, x1, y / float(N - 1)) + sin(y * 0.11 + phase) * 6.0
		var nx := int(round(target))
		while cx != nx:
			_water(g, cx, y)
			_water(g, cx + 1, y)
			cx += signi(nx - cx)
		_water(g, cx, y)
		_water(g, cx + 1, y)
		river_x.append(cx)

	# 支流：自西匯入
	var ty := rng.randi_range(int(N * 0.62), int(N * 0.8))
	var yy := float(ty)
	var join: int = river_x[ty]
	var cy := ty
	for x in join:
		var target := int(round(yy + sin(x * 0.17 + phase) * 3.0))
		while cy != target:
			_water(g, x, cy)
			cy += signi(target - cy)
		_water(g, x, cy)
	# 湖泊
	var lake := Vector2(rng.randi_range(15, N - 15), rng.randi_range(12, 30))
	var lr := rng.randf_range(2.5, 4.5)
	for y in N:
		for x in N:
			if Vector2(x, y).distance_to(lake) <= lr * (1.0 + 0.25 * sin(x * 0.9 + y * 0.7)):
				_water(g, x, y)

	# 肥力：近水者沃
	for y in N:
		for x in N:
			var i: int = y * N + x
			if g.terrain[i] == T.WATER:
				continue
			var near := 9.0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					if g.inb(x + dx, y + dy) and g.terrain[(y + dy) * N + x + dx] == T.WATER:
						near = minf(near, absf(dx) + absf(dy))
			if near <= 4:
				g.fert[i] = minf(1.4, g.fert[i] + 0.4 * (1.0 - (near - 1) / 4.0))
				if near <= 1 and g.terrain[i] == T.GRASS and rng.randf() < 0.18:
					g.terrain[i] = T.FOREST

	# 縣衙：大河東岸
	var my := int(half) - 1
	var mx: int = river_x[my] + 5
	for y in range(my - 8, my + 10):
		for x in range(mx - 6, mx + 12):
			if not g.inb(x, y):
				continue
			var i: int = y * N + x
			var d := Vector2(x - mx, y - my).length()
			if g.terrain[i] == T.WATER:
				continue
			if d < 9 and (g.terrain[i] == T.MOUNTAIN or g.terrain[i] == T.HILL):
				g.terrain[i] = T.GRASS
			if d < 6 and g.terrain[i] == T.FOREST:
				g.terrain[i] = T.GRASS
	for y in range(my, my + 2):
		for x in range(mx, mx + 2):
			g.terrain[y * N + x] = T.GRASS
	g.yamen_id = g.add_building("yamen", mx, my)
	_road_line(g, Vector2i(mx - 3, my + 2), Vector2i(mx + 7, my + 2))
	_road_line(g, Vector2i(mx + 2, my - 4), Vector2i(mx + 2, my + 7))

	# 外邑
	var towns := Defs.TOWNS.duplicate(true)
	# 揚州：大河下游
	var bx: int = river_x[N - 3] + 2
	_town(g, towns[1], Vector2i(bx, N - 3), Vector2i(bx + 1, N - 4), Vector2i(bx + 1, N - 14))
	# 洛陽：西陲
	var ay := rng.randi_range(14, 32)
	_town(g, towns[0], Vector2i(0, ay), Vector2i(2, ay), Vector2i(14, ay))
	# 成都：東陲
	var cy2 := rng.randi_range(22, 44)
	_town(g, towns[2], Vector2i(N - 2, cy2), Vector2i(N - 3, cy2 + 1), Vector2i(N - 16, cy2 + 1))


static func _water(g, x: int, y: int) -> void:
	if not g.inb(x, y):
		return
	var i: int = y * g.N + x
	g.terrain[i] = Defs.T.WATER
	g.fert[i] = 0.0


static func _road_line(g, a: Vector2i, b: Vector2i) -> void:
	var cells := []
	var c := a
	cells.append(c)
	while c.x != b.x:
		c.x += signi(b.x - c.x)
		cells.append(c)
	while c.y != b.y:
		c.y += signi(b.y - c.y)
		cells.append(c)
	for p in cells:
		if not g.inb(p.x, p.y):
			continue
		var i: int = p.y * g.N + p.x
		if g.bld[i] >= 0:
			continue
		var t: int = g.terrain[i]
		if t == Defs.T.MOUNTAIN:
			g.terrain[i] = Defs.T.HILL
		elif t == Defs.T.FOREST:
			g.terrain[i] = Defs.T.GRASS
		g.road[i] = 1


static func _town(g, def: Dictionary, at: Vector2i, road_from: Vector2i, road_to: Vector2i) -> void:
	var N: int = g.N
	at.x = clampi(at.x, 0, N - 2)
	at.y = clampi(at.y, 0, N - 2)
	for dy in 2:
		for dx in 2:
			var i: int = (at.y + dy) * N + at.x + dx
			g.terrain[i] = Defs.T.GRASS
	g.add_building("town", at.x, at.y, {"name": def.name, "mult": def.mult})
	_road_line(g, road_from, road_to)
