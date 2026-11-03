extends RefCounted
## 程式繪製之畫具：等角投影、屋宇、樹木、山巒、車船。色調仿青綠山水與界畫。

const TW := 64.0
const TH := 32.0

const INK := Color(0.16, 0.12, 0.1)
const OUT := Color(0.16, 0.11, 0.08, 0.55)
const WALL_W := Color(0.91, 0.88, 0.8)
const WALL_M := Color(0.78, 0.67, 0.5)
const WOOD := Color(0.55, 0.36, 0.22)
const WOOD_L := Color(0.68, 0.5, 0.32)
const RED := Color(0.66, 0.22, 0.17)
const ROOF_G := Color(0.36, 0.38, 0.41)
const ROOF_T := Color(0.72, 0.6, 0.36)
const ROOF_GL := Color(0.25, 0.48, 0.38)
const ROOF_Y := Color(0.8, 0.6, 0.18)
const STONE := Color(0.62, 0.6, 0.56)
const BRICK := Color(0.52, 0.5, 0.48)
const GOLD := Color(0.9, 0.75, 0.35)
const WATER := Color(0.42, 0.6, 0.62)

static var season := 0
static var rank := 0


static func iso(dx: float, dy: float) -> Vector2:
	return Vector2((dx - dy) * TW * 0.5, (dx + dy) * TH * 0.5)


static func P(c: Vector2, dx: float, dy: float, h: float = 0.0) -> Vector2:
	return c + iso(dx, dy) - Vector2(0, h)


static func poly(ci, pts: Array, col: Color) -> void:
	var clean := PackedVector2Array()
	for p in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_squared_to(p) > 0.01:
			clean.append(p)
	if clean.size() > 2 and clean[0].distance_squared_to(clean[clean.size() - 1]) < 0.01:
		clean.remove_at(clean.size() - 1)
	if clean.size() < 3:
		return
	# 直接畫在節點上（車船）時，自交多邊形改用外殼
	if ci is CanvasItem and Geometry2D.triangulate_polygon(clean).is_empty():
		clean = Geometry2D.convex_hull(clean)
		if clean.size() < 4:
			return
		clean.remove_at(clean.size() - 1)
	ci.draw_colored_polygon(clean, col)


static func grad(ci, pts: Array, cols: Array) -> void:
	ci.draw_polygon(PackedVector2Array(pts), PackedColorArray(cols))


static func line(ci, pts: Array, col: Color = OUT, w: float = 1.0) -> void:
	ci.draw_polyline(PackedVector2Array(pts), col, w, true)


static func snowy(col: Color, amt: float = 0.55) -> Color:
	return col.lerp(Color(0.95, 0.96, 0.98), amt) if season == 3 else col


static func label(ci, p: Vector2, text: String, size: int, col: Color) -> void:
	var f: Font = Defs.font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(f, p - Vector2(w * 0.5, -size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ───────────────────────── 基本體塊 ─────────────────────────

## 地面投影：光自右上而來，影落左下（+y 方向）。
static func shadow(ci, c: Vector2, a: float, b: float, h: float) -> void:
	var k := clampf(h * 0.017, 0.05, 0.9)
	var pts := PackedVector2Array()
	for q in [[-a, -b], [a, -b], [a, b], [-a, b]]:
		pts.append(P(c, q[0], q[1]))
		pts.append(P(c, q[0] - k * 0.3, q[1] + k))
	var hull := Geometry2D.convex_hull(pts)
	hull.remove_at(hull.size() - 1)
	ci.draw_colored_polygon(hull, Color(0.1, 0.08, 0.04, 0.16))


static func ell(ci, p: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 14:
		var t := k / 14.0 * TAU
		pts.append(p + Vector2(cos(t) * rx, sin(t) * ry))
	ci.draw_colored_polygon(pts, col)


## 長方體：c 為地面中心，a、b 為沿 x、y 之半長（格），h 為高（像素），z 為底高。
static func box(ci, c: Vector2, a: float, b: float, h: float, col: Color, z: float = 0.0, top: bool = false, shade: bool = true) -> void:
	if shade and z == 0.0 and h >= 5.0:
		shadow(ci, c, a, b, h)
	var W := P(c, -a, b, z)
	var S := P(c, a, b, z)
	var E := P(c, a, -b, z)
	var Nn := P(c, -a, -b, z)
	var up := Vector2(0, -h)
	grad(ci, [W, S, S + up, W + up], [col.darkened(0.3), col.darkened(0.3), col.darkened(0.16), col.darkened(0.16)])
	grad(ci, [S, E, E + up, S + up], [col.darkened(0.08), col.darkened(0.08), col.lightened(0.04), col.lightened(0.04)])
	if top:
		poly(ci, [Nn + up, E + up, S + up, W + up], col.lightened(0.12))
		line(ci, [W + up, Nn + up, E + up], OUT)
	line(ci, [W + up, W, S, E, E + up], OUT)
	line(ci, [S, S + up], OUT)


## 牆面上的點：left 為左前（+y）面，u 沿 W→S；否則為右前（+x）面，u 沿 S→E。
static func fpt(c: Vector2, a: float, b: float, u: float, h: float, left: bool) -> Vector2:
	var p0 := P(c, -a, b) if left else P(c, a, b)
	var p1 := P(c, a, b) if left else P(c, a, -b)
	return p0.lerp(p1, u) - Vector2(0, h)


static func frect(ci, c: Vector2, a: float, b: float, u0: float, u1: float, h0: float, h1: float, col: Color, left: bool = true) -> void:
	poly(ci, [fpt(c, a, b, u0, h0, left), fpt(c, a, b, u1, h0, left), fpt(c, a, b, u1, h1, left), fpt(c, a, b, u0, h1, left)], col)


## 在左前（+y）牆面上畫一個矩形（門窗）。u 沿 W→S，h 為高度。
static func face_l(ci, c: Vector2, a: float, b: float, u0: float, u1: float, h0: float, h1: float, col: Color, z: float = 0.0) -> void:
	frect(ci, c, a, b, u0, u1, h0 + z, h1 + z, col, true)


## 在右前（+x）牆面上畫矩形。u 沿 S→E。
static func face_r(ci, c: Vector2, a: float, b: float, u0: float, u1: float, h0: float, h1: float, col: Color, z: float = 0.0) -> void:
	frect(ci, c, a, b, u0, u1, h0 + z, h1 + z, col, false)


## 雙扇板門，可貼春聯。
static func door(ci, c: Vector2, a: float, b: float, u: float, w: float, h: float, left: bool = true, z: float = 0.0,
		couplet: bool = false, col: Color = RED.darkened(0.15)) -> void:
	var fw := 0.03
	frect(ci, c, a, b, u - w * 0.5 - fw, u + w * 0.5 + fw, z, z + h + 1.5, WOOD.darkened(0.45), left)
	frect(ci, c, a, b, u - w * 0.5, u + w * 0.5, z, z + h, col, left)
	ci.draw_line(fpt(c, a, b, u, z, left), fpt(c, a, b, u, z + h, left), col.darkened(0.45), 1.0)
	if h >= 6:
		ci.draw_circle(fpt(c, a, b, u - w * 0.12, z + h * 0.5, left), 0.8, GOLD)
		ci.draw_circle(fpt(c, a, b, u + w * 0.12, z + h * 0.5, left), 0.8, GOLD)
	if couplet:
		var cr := Color(0.85, 0.15, 0.1)
		frect(ci, c, a, b, u - w * 0.5 - 0.075, u - w * 0.5 - 0.045, z + 1, z + h, cr, left)
		frect(ci, c, a, b, u + w * 0.5 + 0.045, u + w * 0.5 + 0.075, z + 1, z + h, cr, left)
		frect(ci, c, a, b, u - w * 0.4, u + w * 0.4, z + h + 2, z + h + 3.5, cr, left)


## 格子窗。
static func window(ci, c: Vector2, a: float, b: float, u0: float, u1: float, h0: float, h1: float, left: bool = true) -> void:
	frect(ci, c, a, b, u0 - 0.015, u1 + 0.015, h0 - 0.8, h1 + 0.8, WOOD.darkened(0.3), left)
	frect(ci, c, a, b, u0, u1, h0, h1, Color(0.22, 0.17, 0.13), left)
	var lc := Color(0.68, 0.52, 0.32)
	for k in range(1, 3):
		var u := lerpf(u0, u1, k / 3.0)
		ci.draw_line(fpt(c, a, b, u, h0, left), fpt(c, a, b, u, h1, left), lc, 1.0)
	ci.draw_line(fpt(c, a, b, u0, (h0 + h1) * 0.5, left), fpt(c, a, b, u1, (h0 + h1) * 0.5, left), lc, 1.0)


## 木構：柱與額枋。
static func timber(ci, c: Vector2, a: float, b: float, z: float, h: float, posts: int = 3, col: Color = WOOD.darkened(0.25)) -> void:
	for left in [true, false]:
		for k in posts:
			var u := float(k) / (posts - 1)
			ci.draw_line(fpt(c, a, b, u, z, left), fpt(c, a, b, u, z + h, left), col, 1.6)
		ci.draw_line(fpt(c, a, b, 0, z + h - 1, left), fpt(c, a, b, 1, z + h - 1, left), col, 2.0)
		ci.draw_line(fpt(c, a, b, 0, z + 0.5, left), fpt(c, a, b, 1, z + 0.5, left), col, 1.2)


static func lantern(ci, p: Vector2) -> void:
	ci.draw_line(p, p + Vector2(0, 3), INK, 1.0)
	ell(ci, p + Vector2(0, 5.5), 2.4, 2.8, Color(0.92, 0.22, 0.12))
	ci.draw_line(p + Vector2(-1.6, 3), p + Vector2(1.6, 3), GOLD, 1.0)
	ci.draw_line(p + Vector2(0, 8), p + Vector2(0, 10), GOLD, 1.0)


static func jar(ci, p: Vector2) -> void:
	ell(ci, p + Vector2(0, -3), 3.6, 3.6, Color(0.36, 0.26, 0.2))
	ell(ci, p + Vector2(0, -6.2), 3.0, 1.2, Color(0.22, 0.16, 0.12))
	ell(ci, p + Vector2(0, -6.1), 2.2, 0.8, WATER.darkened(0.2))


static func potted(ci, p: Vector2, v: int) -> void:
	box(ci, p, 0.035, 0.035, 2.5, Color(0.55, 0.35, 0.25), 0, true, false)
	var col := Color(0.3, 0.55, 0.3) if season != 3 else Color(0.45, 0.45, 0.4)
	ci.draw_circle(p - Vector2(0, 5), 2.8, col)
	if season == 0 and v % 2 == 0:
		ci.draw_circle(p - Vector2(1, 6), 1.0, Color(0.95, 0.6, 0.7))


## 屋頂。kind: "hip" 廡殿/歇山、"gable" 懸山、"pyramid" 攢尖。ax: 屋脊沿 x 軸。
static func roof(ci, c: Vector2, a: float, b: float, z: float, rh: float, col: Color,
		kind: String = "hip", ax: bool = true, o: float = 0.1, curl: float = 3.0) -> void:
	var thatch := col.is_equal_approx(ROOF_T)
	col = snowy(col)
	# 簷下陰影落在牆上
	if z >= 6.0:
		var sc := Color(0, 0, 0, 0.2)
		frect(ci, c, a, b, 0, 1, z - 4.5, z, sc, true)
		frect(ci, c, a, b, 0, 1, z - 4.5, z, sc, false)
	var A := a if ax else b
	var B := b if ax else a
	var f := func(u: float, v: float, h: float) -> Vector2:
		return P(c, u, v, h) if ax else P(c, v, u, h)
	var R := 0.0
	match kind:
		"gable":
			R = A + o
		"hip":
			R = maxf(A - B * 0.75, 0.04)
		_:
			R = 0.0
	var steps := 8
	var eave := func(u0: float, v0: float, u1: float, v1: float) -> Array:
		var pts := []
		for k in steps + 1:
			var t := float(k) / steps
			var hh: float = z + curl * pow(2.0 * t - 1.0, 4)
			pts.append(f.call(lerpf(u0, u1, t), lerpf(v0, v1, t), hh))
		return pts
	var EA := A + o
	var EB := B + o
	var top := z + rh
	var r1: Vector2 = f.call(-R, 0.0, top)
	var r2: Vector2 = f.call(R, 0.0, top)
	var lit := col.lightened(0.12)
	var shade := col.darkened(0.1)
	var back := col.darkened(0.28)
	var c_vpos: Color = shade if ax else lit
	var c_upos: Color = lit if ax else shade
	var edge := col.darkened(0.55)
	# 背面
	if kind != "gable":
		poly(ci, eave.call(-EA, EB, -EA, -EB) + [r1], back)
	poly(ci, eave.call(-EA, -EB, EA, -EB) + [r2, r1], back)
	# 前坡（簷口較亮、近脊較暗，見弧度）
	var front: Array = eave.call(-EA, EB, EA, EB)
	poly(ci, front + [r2, r1], c_vpos)
	var rr2 := []
	for k in steps + 1:
		rr2.append(r1.lerp(r2, float(k) / steps))
	var band := []
	for k in steps + 1:
		band.append((front[k] as Vector2).lerp(rr2[k], 0.35))
	var tmp := band.duplicate()
	tmp.reverse()
	poly(ci, front + tmp, c_vpos.lightened(0.06))
	# 側面
	var side: Array = []
	if kind == "gable":
		var g1: Vector2 = f.call(EA - 0.02, EB, z)
		var g2: Vector2 = f.call(EA - 0.02, -EB, z)
		poly(ci, [g1, g2, r2], WALL_W.darkened(0.1) if ax else WALL_W.darkened(0.25))
		ci.draw_line(g1.lerp(r2, 0.55), g2.lerp(r2, 0.55), WOOD.darkened(0.3), 1.0)
		line(ci, [g1, r2, g2], edge, 2.0)
	else:
		side = eave.call(EA, EB, EA, -EB)
		poly(ci, side + [r2], c_upos)
	# 瓦壟或茅草
	if thatch:
		for k in 14:
			var t := (k + 0.5) / 14.0
			var e: Vector2 = (front[0] as Vector2).lerp(front[steps], t)
			var rr := r1.lerp(r2, t) if R > 0.05 else r1
			var q := e.lerp(rr, 0.15 + (k * 37 % 5) * 0.12)
			ci.draw_line(q, q.lerp(rr, 0.25), col.darkened(0.25), 1.0)
	elif kind != "pyramid" and rh > 5:
		var n := clampi(int((front[0] as Vector2).distance_to(front[steps]) / 3.2), 4, 18)
		for k in range(1, n):
			var t := float(k) / n
			var e: Vector2 = (front[0] as Vector2).lerp(front[steps], t)
			e.y -= curl * pow(2.0 * t - 1.0, 4)
			var rr := r1.lerp(r2, t)
			ci.draw_line(e, e.lerp(rr, 0.92), Color(col.darkened(0.35), 0.55), 1.0)
	# 簷口厚度
	var fas := front.duplicate()
	fas.reverse()
	var fas2 := []
	for p in fas:
		fas2.append(p + Vector2(0, 2.2))
	poly(ci, front + fas2, edge)
	if not side.is_empty():
		var s2 := side.duplicate()
		s2.reverse()
		var s3 := []
		for p in s2:
			s3.append(p + Vector2(0, 2.2))
		poly(ci, side + s3, edge.lightened(0.1))
	# 垂脊
	if kind != "gable":
		ci.draw_line(front[0], r1, edge, 1.5)
		ci.draw_line(front[steps], r2, edge, 1.8)
		if not side.is_empty():
			ci.draw_line(side[steps], r2, edge, 1.5)
	# 正脊與鴟吻
	if R > 0.05:
		ci.draw_line(r1 + Vector2(0, 0.5), r2 + Vector2(0, 0.5), edge, 2.8)
		if not thatch:
			line(ci, [r1, r1 + Vector2(-1.5, -2.5), r1 + Vector2(-0.5, -4.5)], edge, 1.8)
			line(ci, [r2, r2 + Vector2(1.5, -2.5), r2 + Vector2(0.5, -4.5)], edge, 1.8)
	elif kind == "pyramid":
		ci.draw_line(r1, r1 - Vector2(0, 4), edge, 1.5)
		ci.draw_circle(r1 - Vector2(0, 5), 1.6, GOLD)


static func hall(ci, c: Vector2, a: float, b: float, h: float, wall: Color, rcol: Color,
		kind: String = "hip", ax: bool = true, rh: float = -1.0, pillars: bool = true, z: float = 0.0) -> void:
	var rr := rh if rh > 0 else (a + b) * 22.0
	if z == 0.0:
		shadow(ci, c, a + 0.06, b + 0.06, h + rr * 0.6)
	box(ci, c, a + 0.05, b + 0.05, 3, STONE, z, true, false)
	box(ci, c, a, b, h - 3, wall, z + 3, false, false)
	if pillars:
		for left in [true, false]:
			var n := 4 if left else 3
			for k in n:
				var u := (k + 0.5) / n
				frect(ci, c, a, b, u - 0.025, u + 0.025, z + 3, z + h, RED, left)
			frect(ci, c, a, b, 0, 1, z + h - 3, z + h, RED.darkened(0.35), left)
	else:
		timber(ci, c, a, b, z + 3, h - 3, 3)
	var wh := h - 3
	door(ci, c, a, b, 0.5, 0.2, wh * 0.72, true, z + 3, false)
	if a >= 0.2:
		window(ci, c, a, b, 0.14, 0.3, z + 3 + wh * 0.35, z + 3 + wh * 0.75, true)
		window(ci, c, a, b, 0.7, 0.86, z + 3 + wh * 0.35, z + 3 + wh * 0.75, true)
	if b >= 0.12:
		window(ci, c, a, b, 0.35, 0.65, z + 3 + wh * 0.35, z + 3 + wh * 0.75, false)
	roof(ci, c, a, b, z + h, rr, rcol, kind, ax)

static func tree_round(ci, p: Vector2, s: float, v: int) -> void:
	ell(ci, p + Vector2(-4, 1) * s, 7 * s, 3 * s, Color(0.1, 0.08, 0.04, 0.14))
	ci.draw_line(p, p - Vector2(0, 7 * s), WOOD.darkened(0.3), 2.0 * s)
	if season == 3:
		for k in 4:
			var ang := -PI * 0.5 + (k - 1.5) * 0.5
			ci.draw_line(p - Vector2(0, 6 * s), p - Vector2(0, 6 * s) + Vector2(cos(ang), sin(ang)) * 7 * s, WOOD.darkened(0.3), 1.0)
		return
	var cols := [Color(0.45, 0.62, 0.32), Color(0.3, 0.5, 0.26), Color(0.78, 0.5, 0.2), Color(0.6, 0.6, 0.6)]
	var col: Color = cols[season]
	if season == 2 and v % 3 == 0:
		col = Color(0.72, 0.3, 0.18)
	var blossom := season == 0 and v % 4 == 0
	if blossom:
		col = Color(0.93, 0.72, 0.78)
	var top := p - Vector2(0, 11 * s)
	ci.draw_circle(top + Vector2(-3, 2) * s, 5.5 * s, col.darkened(0.15))
	ci.draw_circle(top + Vector2(3, 2) * s, 5.0 * s, col.darkened(0.05))
	ci.draw_circle(top + Vector2(0, -2) * s, 5.5 * s, col)
	ci.draw_circle(top + Vector2(-1, -4) * s, 2.5 * s, col.lightened(0.15))


static func tree_pine(ci, p: Vector2, s: float) -> void:
	ell(ci, p + Vector2(-4, 1) * s, 7 * s, 3 * s, Color(0.1, 0.08, 0.04, 0.14))
	ci.draw_line(p, p - Vector2(0, 6 * s), WOOD.darkened(0.4), 2.0 * s)
	var col := Color(0.17, 0.36, 0.3)
	for k in 3:
		var y := p.y - (5 + k * 5) * s
		var w := (8 - k * 2) * s
		var tip := Vector2(p.x, y - 8 * s)
		poly(ci, [Vector2(p.x - w, y), Vector2(p.x + w, y), tip], col.lightened(k * 0.06))
		if season == 3:
			poly(ci, [Vector2(p.x - w * 0.5, y - 4 * s), Vector2(p.x + w * 0.4, y - 4 * s), tip], Color(0.94, 0.95, 0.97))


static func tree_willow(ci, p: Vector2, s: float) -> void:
	ell(ci, p + Vector2(-4, 1) * s, 9 * s, 3.5 * s, Color(0.1, 0.08, 0.04, 0.14))
	var top := p - Vector2(0, 14 * s)
	ci.draw_line(p, top, WOOD.darkened(0.35), 2.0 * s)
	var col: Color = [Color(0.62, 0.78, 0.38), Color(0.42, 0.62, 0.3), Color(0.7, 0.66, 0.3), Color(0.45, 0.38, 0.3)][season]
	for k in 7:
		var dx := (k - 3) * 2.2 * s
		var pts := []
		for t in 5:
			var tt := t / 4.0
			pts.append(top + Vector2(dx * (0.4 + tt), -2 * s + tt * tt * 15 * s - sin(tt * PI) * 3 * s))
		line(ci, pts, col, 1.3)


static func trees(ci, c: Vector2, v: int, willow: bool, n: int = -1) -> void:
	if n < 0:
		n = 2 + v % 3
	var pts := []
	for k in n:
		var h := (v * 31 + k * 97) % 1000
		pts.append(Vector2(((h % 10) / 10.0 - 0.45) * 0.7, (((h / 10) % 10) / 10.0 - 0.45) * 0.7))
	pts.sort_custom(func(p, q): return p.x + p.y < q.x + q.y)
	for k in pts.size():
		var p := c + iso(pts[k].x, pts[k].y)
		var s := 0.85 + ((v + k * 13) % 5) * 0.08
		if willow:
			tree_willow(ci, p, s)
		elif (v + k) % 3 == 0:
			tree_round(ci, p, s, v + k)
		else:
			tree_pine(ci, p, s)


static func mountain(ci, c: Vector2, v: int) -> void:
	var hgt := 30.0 + (v % 37)
	var peak := c + iso(((v >> 2) % 5 - 2) * 0.07, ((v >> 4) % 5 - 2) * 0.07) - Vector2(0, hgt)
	var e := 0.62
	var W := c + iso(-e, e)
	var S := c + iso(e, e)
	var E := c + iso(e, -e)
	var Nn := c + iso(-e, -e)
	var base := Color(0.45, 0.56, 0.4)
	var blue := Color(0.22, 0.38, 0.47)
	var green := Color(0.28, 0.5, 0.4)
	if season == 3:
		blue = Color(0.85, 0.88, 0.92)
		green = Color(0.6, 0.66, 0.66)
	grad(ci, [W, peak, Nn], [base, blue.lightened(0.1), base])
	grad(ci, [Nn, peak, E], [base, blue.lightened(0.15), base])
	grad(ci, [W, S, peak], [base.darkened(0.15), green.darkened(0.15), blue.darkened(0.2)])
	grad(ci, [S, E, peak], [green, base.lightened(0.1), blue.lightened(0.05)])
	if hgt > 50 or season == 3:
		var sc := Color(0.95, 0.96, 0.98)
		poly(ci, [peak, peak.lerp(W, 0.22), peak.lerp(S, 0.16), peak.lerp(E, 0.22)], sc)
	line(ci, [W, peak, E], Color(0.12, 0.18, 0.2, 0.55), 1.3)
	line(ci, [peak, peak.lerp(S, 0.7)], Color(0.12, 0.18, 0.2, 0.3), 1.0)
	for k in 3:
		var t := 0.3 + k * 0.18
		var q := peak.lerp(W.lerp(S, 0.3 + k * 0.2), t)
		ci.draw_line(q, q + Vector2(-4, 6), Color(0.1, 0.15, 0.18, 0.35), 1.0)


static func hill(ci, c: Vector2, v: int) -> void:
	var h := 9.0 + (v % 9)
	var pts := []
	var cols := []
	var base := Color(0.62, 0.62, 0.42) if season != 3 else Color(0.88, 0.88, 0.86)
	var top := Color(0.5, 0.62, 0.38) if season != 3 else Color(0.95, 0.95, 0.96)
	if season == 2:
		top = Color(0.7, 0.6, 0.34)
	var W := c + iso(-0.55, 0.55)
	var E := c + iso(0.55, -0.55)
	for k in 13:
		var t := k / 12.0
		var p := W.lerp(E, t)
		p.y -= sin(t * PI) * h + sin(t * PI * 2 + v) * 1.5
		pts.append(p)
		cols.append(base.lerp(top, sin(t * PI)))
	pts.append(c + iso(0.55, 0.55))
	cols.append(base.darkened(0.08))
	grad(ci, pts, cols)
	line(ci, pts.slice(0, 13), Color(0.2, 0.25, 0.15, 0.4), 1.0)


# ───────────────────────── 民間建築 ─────────────────────────

static func house(ci, c: Vector2, lvl: int, v: int) -> void:
	var ax := v % 2 == 0
	match lvl:
		1:
			var p := c + iso(-0.07, -0.07)
			var a := 0.26 if ax else 0.2
			var b := 0.2 if ax else 0.26
			if v % 3 == 0:
				# 竹籬
				for k in 4:
					var q := P(c, 0.43, -0.36 + k * 0.24)
					ci.draw_line(q, q - Vector2(0, 5), WOOD_L.darkened(0.2), 1.0)
				line(ci, [P(c, 0.43, -0.38, 3.5), P(c, 0.43, 0.38, 3.5), P(c, -0.2, 0.43, 3.5)], WOOD_L.darkened(0.2), 1.0)
			box(ci, p, a, b, 9, WALL_M)
			timber(ci, p, a, b, 0, 9, 2, WOOD.darkened(0.15))
			door(ci, p, a, b, 0.6, 0.2, 7, true, 0, false, WOOD.darkened(0.1))
			window(ci, p, a, b, 0.35, 0.62, 4, 7, false)
			roof(ci, p, a, b, 9, 10, ROOF_T, "gable", ax, 0.09, 1.0)
			match v % 4:
				0:
					jar(ci, P(c, 0.3, 0.32))
				1:
					_logs(ci, P(c, 0.32, 0.3))
				2:
					jar(ci, P(c, 0.34, 0.2))
					potted(ci, P(c, 0.12, 0.38), v)
		2:
			var p := c + iso(-0.05, -0.05)
			var a := 0.32 if ax else 0.24
			var b := 0.24 if ax else 0.32
			if v % 3 == 1:
				var sp := c + iso(0.3, -0.3)
				box(ci, sp, 0.1, 0.1, 7, WOOD_L)
				roof(ci, sp, 0.1, 0.1, 7, 5, ROOF_G, "gable", true, 0.04, 0.5)
			shadow(ci, p, a, b, 24)
			box(ci, p, a + 0.035, b + 0.035, 3, STONE, 0, true, false)
			box(ci, p, a, b, 10, WALL_W, 3, false, false)
			timber(ci, p, a, b, 3, 10, 3)
			door(ci, p, a, b, 0.5, 0.18, 7.5, true, 3, true)
			window(ci, p, a, b, 0.12, 0.28, 7, 11, true)
			window(ci, p, a, b, 0.72, 0.88, 7, 11, true)
			window(ci, p, a, b, 0.32, 0.68, 7, 11, false)
			roof(ci, p, a, b, 13, 12, ROOF_G, "gable", ax, 0.09, 2.5)
			if v % 4 == 0:
				lantern(ci, fpt(p, a, b, 0.33, 13, true) + Vector2(0, 2))
				lantern(ci, fpt(p, a, b, 0.67, 13, true) + Vector2(0, 2))
			elif v % 4 == 2:
				potted(ci, P(c, 0.32, 0.36), v)
		_:
			courtyard(ci, c, v)


static func courtyard(ci, c: Vector2, v: int) -> void:
	var e := 0.44
	var wc := WALL_W.darkened(0.04)
	poly(ci, [P(c, -e, -e), P(c, e, -e), P(c, e, e), P(c, -e, e)], Color(0.74, 0.72, 0.67))
	for k in range(1, 4):
		var t := -e + k * e * 0.5
		ci.draw_line(P(c, -e, t), P(c, e, t), Color(0.62, 0.6, 0.56, 0.6), 1.0)
		ci.draw_line(P(c, t, -e), P(c, t, e), Color(0.62, 0.6, 0.56, 0.6), 1.0)
	# 後牆
	box(ci, c + iso(0, -e), e, 0.025, 7, wc)
	box(ci, c + iso(-e, 0), 0.025, e, 7, wc)
	# 正房與廂房
	hall(ci, c + iso(-0.04, -0.25), 0.3, 0.12, 14, WALL_W, ROOF_G, "hip", true, 12)
	hall(ci, c + iso(-0.27, 0.1), 0.1, 0.17, 11, WALL_W, ROOF_G, "gable", false, 9, false)
	if v % 2 == 0:
		tree_round(ci, c + iso(0.12, 0.1), 0.75, v)
	else:
		hall(ci, c + iso(0.25, -0.02), 0.1, 0.15, 11, WALL_W, ROOF_G, "gable", false, 9, false)
		jar(ci, P(c, 0.08, 0.18))
	# 前牆與門樓
	box(ci, c + iso(e, 0), 0.025, e, 7, wc)
	box(ci, c + iso(0, e), e, 0.025, 7, wc)
	line(ci, [P(c, -e, e, 7.5), P(c, e, e, 7.5), P(c, e, -e, 7.5)], ROOF_G.darkened(0.25), 2.5)
	var g := c + iso(0.12, e)
	box(ci, g, 0.09, 0.04, 9, wc, 0, false, false)
	door(ci, g, 0.09, 0.04, 0.5, 0.6, 7, true, 0, true)
	roof(ci, g, 0.11, 0.06, 9, 5, ROOF_G, "gable", true, 0.04, 1.5)
	if v % 3 == 0:
		lantern(ci, fpt(g, 0.11, 0.06, 0.1, 9, true) + Vector2(0, 1))
		lantern(ci, fpt(g, 0.11, 0.06, 0.9, 9, true) + Vector2(0, 1))


static func _goods(ci, p: Vector2, v: int) -> void:
	var gc := [Color(0.85, 0.72, 0.3), Color(0.75, 0.3, 0.25), Color(0.4, 0.55, 0.8), Color(0.45, 0.65, 0.35), Color(0.9, 0.9, 0.85)]
	for k in 4:
		ci.draw_circle(p + Vector2(k * 3.2 - 5, -1 - (k % 2)), 1.5, gc[(v + k) % gc.size()])


static func shop(ci, c: Vector2, lvl: int, v: int) -> void:
	var signs := ["茶", "酒", "布", "米", "藥", "餅", "當", "油"]
	var boards := ["綢莊", "茶肆", "米行", "錢莊", "藥鋪", "書坊", "香鋪", "繡坊"]
	var awn: Color = [Color(0.3, 0.42, 0.62), RED, Color(0.75, 0.6, 0.3), Color(0.35, 0.55, 0.4)][v % 4]
	match lvl:
		1:
			var p := c + iso(-0.08, -0.08)
			box(ci, p, 0.26, 0.22, 10, WOOD_L)
			timber(ci, p, 0.26, 0.22, 0, 10, 2)
			frect(ci, p, 0.26, 0.22, 0.1, 0.9, 0, 8, Color(0.22, 0.15, 0.11), true)
			window(ci, p, 0.26, 0.22, 0.35, 0.65, 4, 7.5, false)
			roof(ci, p, 0.26, 0.22, 10, 9, ROOF_G, "gable", true, 0.07, 1.5)
			var a0 := P(p, -0.26, 0.22, 9)
			var a1 := P(p, 0.26, 0.22, 9)
			var d := iso(0, 0.22) + Vector2(0, 5)
			poly(ci, [a0, a1, a1 + d, a0 + d], awn)
			for k in 4:
				var t := (k + 0.5) / 4.0
				ci.draw_line(a0.lerp(a1, t), (a0 + d).lerp(a1 + d, t), awn.lightened(0.25), 1.5)
			line(ci, [a0 + d, a1 + d], awn.darkened(0.35), 1.0)
			var tc := c + iso(0.12, 0.3)
			box(ci, tc, 0.13, 0.06, 4, WOOD)
			_goods(ci, P(tc, 0, 0, 4), v)
			_banner(ci, P(c, 0.36, 0.3), signs[v % signs.size()], 22)
		2:
			var p := c + iso(-0.04, -0.04)
			shadow(ci, p, 0.32, 0.26, 34)
			box(ci, p, 0.35, 0.29, 2.5, STONE, 0, true, false)
			box(ci, p, 0.32, 0.26, 9, WOOD_L, 2.5, false, false)
			frect(ci, p, 0.32, 0.26, 0.08, 0.92, 2.5, 10, Color(0.22, 0.15, 0.11), true)
			for k in 3:
				_goods(ci, fpt(p, 0.32, 0.26, 0.2 + k * 0.3, 5, true), v + k)
			timber(ci, p, 0.32, 0.26, 2.5, 9, 3)
			window(ci, p, 0.32, 0.26, 0.3, 0.7, 5, 9, false)
			roof(ci, p, 0.32, 0.26, 11.5, 4, ROOF_G, "hip", true, 0.08, 2.0)
			box(ci, p, 0.28, 0.22, 10, WALL_W, 14, false, false)
			timber(ci, p, 0.28, 0.22, 14, 10, 3)
			for k in 3:
				window(ci, p, 0.28, 0.22, 0.1 + k * 0.3, 0.28 + k * 0.3, 16, 22, true)
			window(ci, p, 0.28, 0.22, 0.3, 0.7, 16, 22, false)
			line(ci, [P(p, -0.32, 0.3, 17), P(p, 0.32, 0.3, 17), P(p, 0.32, -0.26, 17)], WOOD.darkened(0.2), 1.5)
			roof(ci, p, 0.28, 0.22, 24, 11, ROOF_G, "hip", true, 0.09, 3.0)
			var bp := P(p, 0.0, 0.33, 12.5)
			ci.draw_rect(Rect2(bp - Vector2(12, 4.5), Vector2(24, 9)), Color(0.15, 0.1, 0.08))
			ci.draw_rect(Rect2(bp - Vector2(12, 4.5), Vector2(24, 9)), GOLD.darkened(0.3), false, 1.0)
			label(ci, bp, boards[v % boards.size()], 7, GOLD)
			lantern(ci, P(p, -0.36, 0.34, 24))
			lantern(ci, P(p, 0.36, 0.34, 24))
		_:
			var p := c + iso(-0.02, -0.02)
			shadow(ci, p, 0.4, 0.34, 44)
			box(ci, p, 0.43, 0.37, 3, STONE, 0, true, false)
			box(ci, p, 0.4, 0.34, 10, WOOD_L, 3, false, false)
			frect(ci, p, 0.4, 0.34, 0.06, 0.94, 3, 11, Color(0.22, 0.14, 0.1), true)
			for k in 5:
				var u := 0.05 + k * 0.225
				frect(ci, p, 0.4, 0.34, u - 0.015, u + 0.015, 3, 13, RED, true)
			for k in 3:
				_goods(ci, fpt(p, 0.4, 0.34, 0.18 + k * 0.32, 6, true), v + k)
			window(ci, p, 0.4, 0.34, 0.2, 0.45, 6, 11, false)
			window(ci, p, 0.4, 0.34, 0.55, 0.8, 6, 11, false)
			roof(ci, p, 0.4, 0.34, 13, 4, ROOF_G, "hip", true, 0.08, 3.0)
			box(ci, p, 0.36, 0.3, 11, RED.lightened(0.15), 16, false, false)
			for k in 4:
				window(ci, p, 0.36, 0.3, 0.06 + k * 0.235, 0.2 + k * 0.235, 18, 25, true)
			window(ci, p, 0.36, 0.3, 0.15, 0.45, 18, 25, false)
			window(ci, p, 0.36, 0.3, 0.55, 0.85, 18, 25, false)
			line(ci, [P(p, -0.4, 0.38, 18), P(p, 0.4, 0.38, 18), P(p, 0.44, -0.3, 18)], WOOD.darkened(0.2), 1.5)
			for k in 9:
				var q := P(p, -0.4, 0.38, 18).lerp(P(p, 0.4, 0.38, 18), k / 8.0)
				ci.draw_line(q, q + Vector2(0, 3.5), WOOD.darkened(0.2), 1.0)
			roof(ci, p, 0.36, 0.3, 27, 14, ROOF_G, "hip", true, 0.11, 5.0)
			for q in [P(p, -0.47, 0.44, 26), P(p, 0.47, 0.44, 26), P(p, 0.47, -0.4, 26), P(p, 0.0, 0.44, 25)]:
				lantern(ci, q)
			_banner(ci, P(c, 0.46, 0.42), "酒", 40)


static func _banner(ci, base: Vector2, ch: String, h: float) -> void:
	ci.draw_line(base, base - Vector2(0, h), WOOD.darkened(0.3), 1.5)
	var r := Rect2(base - Vector2(-1, h - 1), Vector2(8, 13))
	ci.draw_rect(r, Color(0.95, 0.93, 0.85))
	ci.draw_rect(r, RED, false, 1.0)
	label(ci, r.get_center() + Vector2(0, -1), ch, 8, RED.darkened(0.3))


static func workshop(ci, c: Vector2, lvl: int, v: int) -> void:
	match lvl:
		1:
			var p := c + iso(-0.08, -0.04)
			box(ci, p, 0.28, 0.2, 9, WOOD)
			face_l(ci, p, 0.28, 0.2, 0.3, 0.7, 0, 7, Color(0.2, 0.14, 0.1))
			roof(ci, p, 0.28, 0.2, 9, 9, ROOF_T, "gable", true, 0.08, 1.0)
			_logs(ci, P(c, 0.28, 0.3))
		2:
			var p := c + iso(-0.05, -0.05)
			box(ci, p, 0.34, 0.26, 12, WOOD_L)
			face_l(ci, p, 0.34, 0.26, 0.25, 0.6, 0, 10, Color(0.2, 0.14, 0.1))
			box(ci, P(p, 0.18, -0.1), 0.05, 0.05, 26, BRICK, 0)
			roof(ci, p, 0.34, 0.26, 12, 11, ROOF_G, "gable", true, 0.08, 1.5)
			box(ci, c + iso(0.3, 0.32), 0.07, 0.07, 6, WOOD_L, 0, true)
			box(ci, c + iso(0.12, 0.36), 0.06, 0.06, 5, WOOD_L, 0, true)
		_:
			box(ci, c + iso(-0.2, -0.1), 0.2, 0.3, 13, WOOD_L)
			roof(ci, c + iso(-0.2, -0.1), 0.2, 0.3, 13, 11, ROOF_G, "gable", false, 0.06, 1.5)
			box(ci, c + iso(0.18, -0.22), 0.06, 0.06, 32, BRICK)
			box(ci, c + iso(0.2, 0.12), 0.2, 0.18, 11, WALL_W)
			face_l(ci, c + iso(0.2, 0.12), 0.2, 0.18, 0.3, 0.7, 0, 8, Color(0.2, 0.14, 0.1))
			roof(ci, c + iso(0.2, 0.12), 0.2, 0.18, 11, 9, ROOF_G, "hip", true, 0.07, 2.0)
			_logs(ci, P(c, -0.25, 0.38))


static func _logs(ci, p: Vector2) -> void:
	for k in 3:
		ci.draw_circle(p + Vector2(k * 4 - 4, 0), 2.2, WOOD_L)
		ci.draw_circle(p + Vector2(k * 4 - 4, 0), 1.0, WOOD.darkened(0.2))
	for k in 2:
		ci.draw_circle(p + Vector2(k * 4 - 2, -3.5), 2.2, WOOD_L)


static func farmhouse(ci, c: Vector2, lvl: int, v: int) -> void:
	if lvl >= 2:
		var p := c + iso(-0.3, -0.3)
		box(ci, p, 0.14, 0.12, 8, WALL_M if lvl == 2 else WALL_W)
		roof(ci, p, 0.14, 0.12, 8, 7, ROOF_T if lvl == 2 else ROOF_G, "gable", true, 0.05, 1.0)
	if season == 2 or (lvl == 3 and season != 0):
		for k in (2 if lvl == 3 else 1):
			var q := P(c, 0.15 + k * 0.18, 0.2 - k * 0.1)
			poly(ci, [q + Vector2(-5, 0), q + Vector2(5, 0), q + Vector2(3, -6), q + Vector2(0, -9), q + Vector2(-3, -6)], Color(0.82, 0.68, 0.32))
	elif lvl == 1 and v % 5 == 0:
		var q := P(c, 0.1, 0.1)
		ci.draw_line(q, q - Vector2(0, 10), WOOD, 1.0)
		ci.draw_line(q - Vector2(4, 7), q - Vector2(-4, 7), WOOD, 1.0)
		ci.draw_circle(q - Vector2(0, 11), 2.0, ROOF_T)


static func scaffold(ci, c: Vector2) -> void:
	var col := Color(0.6, 0.48, 0.3)
	box(ci, c, 0.26, 0.22, 4, STONE)
	for u in [-0.3, 0.0, 0.3]:
		for w in [-0.25, 0.25]:
			ci.draw_line(P(c, u, w), P(c, u, w, 18), col, 1.0)
	for h in [6.0, 12.0, 18.0]:
		line(ci, [P(c, -0.3, 0.25, h), P(c, 0.3, 0.25, h), P(c, 0.3, -0.25, h)], col, 1.0)


# ───────────────────────── 公共建築 ─────────────────────────

static func yamen(ci, c: Vector2, v: int) -> void:
	var e := 0.92
	poly(ci, [P(c, -e, -e), P(c, e, -e), P(c, e, e), P(c, -e, e)], Color(0.7, 0.68, 0.64))
	var wc := Color(0.62, 0.26, 0.2)
	box(ci, c + iso(0, -e), e, 0.04, 10, wc)
	box(ci, c + iso(-e, 0), 0.04, e, 10, wc)
	hall(ci, c + iso(-0.2, -0.35), 0.5, 0.26, 18, WALL_W, ROOF_G, "hip", true, 18)
	hall(ci, c + iso(-0.62, 0.25), 0.16, 0.3, 11, WALL_W, ROOF_G, "gable", false, 9, false)
	hall(ci, c + iso(0.55, -0.0), 0.16, 0.3, 11, WALL_W, ROOF_G, "gable", false, 9, false)
	# 旗桿
	var fp := P(c, 0.3, 0.45)
	ci.draw_line(fp, fp - Vector2(0, 46), INK, 1.5)
	poly(ci, [fp - Vector2(0, 46), fp - Vector2(-14, 42), fp - Vector2(0, 37)], Color(0.85, 0.2, 0.15))
	box(ci, c + iso(e, 0), 0.04, e, 10, wc)
	box(ci, c + iso(0, e), e, 0.04, 10, wc)
	line(ci, [P(c, -e, e, 10), P(c, e, e, 10), P(c, e, -e, 10)], ROOF_G.darkened(0.2), 2.5)
	var g := c + iso(0.0, e)
	box(ci, g, 0.26, 0.08, 14, RED)
	face_l(ci, g, 0.26, 0.08, 0.3, 0.7, 0, 10, Color(0.35, 0.1, 0.08))
	roof(ci, g, 0.26, 0.1, 14, 9, ROOF_G, "hip", true, 0.07, 3.0)
	var names := ["里署", "鎮署", "縣衙", "州衙", "府衙", "皇城"]
	var bp := P(g, 0, 0.12, 17)
	ci.draw_rect(Rect2(bp - Vector2(11, 4.5), Vector2(22, 9)), Color(0.12, 0.08, 0.06))
	label(ci, bp, names[rank], 7, GOLD)
	for s in [-1, 1]:
		var lp := P(c, 0.0 + s * 0.38, e + 0.2)
		box(ci, lp, 0.05, 0.05, 3, STONE)
		ci.draw_circle(lp - Vector2(0, 6), 2.5, STONE.lightened(0.1))


static func walled(ci, c: Vector2, e: float, wcol: Color, h: float, inner: Callable) -> void:
	poly(ci, [P(c, -e, -e), P(c, e, -e), P(c, e, e), P(c, -e, e)], Color(0.72, 0.7, 0.64))
	box(ci, c + iso(0, -e), e, 0.04, h, wcol)
	box(ci, c + iso(-e, 0), 0.04, e, h, wcol)
	inner.call()
	box(ci, c + iso(e, 0), 0.04, e, h, wcol)
	box(ci, c + iso(0, e), e, 0.04, h, wcol)
	line(ci, [P(c, -e, e, h), P(c, e, e, h), P(c, e, -e, h)], ROOF_G.darkened(0.2), 2.5)


static func temple(ci, c: Vector2, v: int) -> void:
	var yc := Color(0.82, 0.62, 0.32)
	walled(ci, c, 0.92, yc, 9, func():
		var m := c + iso(-0.15, -0.2)
		box(ci, m, 0.5, 0.36, 4, STONE, 0, true)
		hall(ci, m, 0.42, 0.28, 13, RED.lightened(0.1), ROOF_Y, "hip", true, 6)
		box(ci, m, 0.32, 0.2, 7, RED.lightened(0.1), 17)
		roof(ci, m, 0.32, 0.2, 24, 13, ROOF_Y, "hip", true, 0.1, 4.0)
		var bp := P(c, 0.35, 0.35)
		box(ci, bp, 0.07, 0.07, 6, BRICK.darkened(0.2))
		ci.draw_circle(bp - Vector2(0, 7), 3.0, BRICK.darkened(0.3)))
	var g := c + iso(0.0, 0.92)
	box(ci, g, 0.2, 0.07, 12, RED)
	roof(ci, g, 0.2, 0.08, 12, 7, ROOF_Y, "hip", true, 0.06, 2.5)


static func academy(ci, c: Vector2, v: int) -> void:
	walled(ci, c, 0.92, WALL_W, 8, func():
		hall(ci, c + iso(-0.25, -0.4), 0.45, 0.2, 14, WALL_W, ROOF_G, "hip", true, 13)
		tree_pine(ci, P(c, -0.6, 0.3), 1.0)
		tree_round(ci, P(c, 0.5, -0.5), 1.0, v)
		hall(ci, c + iso(0.15, 0.25), 0.35, 0.18, 11, WALL_W, ROOF_G, "gable", true, 10))
	var g := c + iso(0.0, 0.92)
	box(ci, g, 0.18, 0.06, 11, WALL_W)
	face_l(ci, g, 0.18, 0.06, 0.3, 0.7, 0, 8, Color(0.3, 0.2, 0.15))
	roof(ci, g, 0.18, 0.08, 11, 6, ROOF_G, "gable", true, 0.05, 2.0)
	var bp := P(g, 0, 0.1, 14)
	ci.draw_rect(Rect2(bp - Vector2(11, 4.5), Vector2(22, 9)), Color(0.12, 0.08, 0.06))
	label(ci, bp, "書院", 7, GOLD)


static func _arch(ci, c: Vector2, a: float, b: float, u0: float, u1: float, h: float, left: bool) -> void:
	var pts := [fpt(c, a, b, u0, 0, left)]
	for k in 9:
		var t := k / 8.0
		pts.append(fpt(c, a, b, lerpf(u0, u1, t), h + sin(t * PI) * h * 0.35, left))
	pts.append(fpt(c, a, b, u1, 0, left))
	poly(ci, pts, Color(0.14, 0.11, 0.1))
	line(ci, pts.slice(1, 10), STONE.lightened(0.15), 1.5)


static func belltower(ci, c: Vector2, v: int) -> void:
	var e := 0.72
	var th := 22.0
	shadow(ci, c, e, e, 70)
	box(ci, c, e, e, th, BRICK, 0, true, false)
	for k in 4:
		var hh := 4.0 + k * 4.5
		line(ci, [P(c, -e, e, hh), P(c, e, e, hh), P(c, e, -e, hh)], BRICK.darkened(0.12), 1.0)
	_arch(ci, c, e, e, 0.4, 0.6, 9, true)
	_arch(ci, c, e, e, 0.4, 0.6, 9, false)
	# 垛口
	for k in 7:
		var u := (k + 0.5) / 7.0
		box(ci, P(c, lerpf(-e, e, u), e, 0) - Vector2(0, 0) + Vector2(0, 0), 0.04, 0.03, 3, BRICK.lightened(0.08), th, true, false)
		box(ci, P(c, e, lerpf(e, -e, u), 0), 0.03, 0.04, 3, BRICK.lightened(0.08), th, true, false)
	# 下層樓閣
	hall(ci, c, 0.42, 0.42, 15, RED, ROOF_GL, "hip", true, 8, true, th)
	# 上層樓閣（重檐）
	var z2 := th + 15 + 5
	box(ci, c, 0.3, 0.3, 11, RED, z2, false, false)
	for left in [true, false]:
		for k in 3:
			var u := (k + 0.5) / 3.0
			frect(ci, c, 0.3, 0.3, u - 0.03, u + 0.03, z2, z2 + 11, RED.darkened(0.2), left)
		window(ci, c, 0.3, 0.3, 0.38, 0.62, z2 + 3, z2 + 9, left)
	roof(ci, c, 0.3, 0.3, z2 + 11, 17, ROOF_GL, "hip", true, 0.13, 5.0)

static func pagoda(ci, c: Vector2, v: int) -> void:
	var z := 0.0
	box(ci, c, 0.38, 0.38, 4, STONE, 0, true)
	z = 4.0
	for k in 7:
		var a := 0.3 - k * 0.028
		var h := 11.0 - k * 0.7
		box(ci, c, a, a, h, WALL_W.darkened(0.05) if k % 2 == 0 else WALL_W, z)
		face_l(ci, c, a, a, 0.4, 0.6, z + 2, z + h - 2, Color(0.25, 0.18, 0.15))
		z += h
		roof(ci, c, a, a, z, 4.0, ROOF_G, "pyramid", true, 0.1, 2.5)
		z += 2.0
	var tip := P(c, 0, 0, z)
	ci.draw_line(tip + Vector2(0, 2), tip - Vector2(0, 16), INK, 1.5)
	for k in 3:
		ci.draw_circle(tip - Vector2(0, 4 + k * 4), 2.0 - k * 0.4, GOLD)


static func archway(ci, c: Vector2, v: int) -> void:
	var ax := v % 2 == 0
	var f := func(u: float, h: float) -> Vector2:
		return P(c, u, 0.0, h) if ax else P(c, 0.0, u, h)
	var pil := [-0.42, -0.15, 0.15, 0.42]
	var red := RED.darkened(0.05)
	var beam := Color(0.2, 0.42, 0.45)
	shadow(ci, c, 0.45 if ax else 0.08, 0.08 if ax else 0.45, 48)
	# 柱與抱鼓石
	for u in pil:
		var b: Vector2 = f.call(u, 0)
		var hh := 37.0 if absf(u) < 0.2 else 24.0
		for s in [-1.0, 1.0]:
			var drum: Vector2 = (P(c, u, s * 0.07) if ax else P(c, s * 0.07, u)) - Vector2(0, 4)
			ell(ci, drum, 3.2, 3.6, STONE.darkened(0.05))
			ell(ci, drum - Vector2(0.5, 0.8), 2.0, 2.3, STONE.lightened(0.12))
		box(ci, b - Vector2(0, 0), 0.035, 0.035, 3, STONE, 0, true, false)
		ci.draw_line(b, b - Vector2(0, hh), red.darkened(0.2), 4.0)
		ci.draw_line(b + Vector2(1, 0), b - Vector2(-1, hh), red, 2.0)
	# 額枋：邊間與明間
	for s in [-1.0, 1.0]:
		var u0: float = 0.15 * s
		var u1: float = 0.45 * s
		ci.draw_line(f.call(u0, 15), f.call(u1, 15), beam, 2.5)
		ci.draw_line(f.call(u0, 19), f.call(u1, 19), beam.darkened(0.15), 3.0)
		ci.draw_line(f.call(u0, 20.5), f.call(u1, 20.5), RED.darkened(0.3), 1.5)
	ci.draw_line(f.call(-0.17, 24), f.call(0.17, 24), beam, 3.0)
	ci.draw_line(f.call(-0.17, 34), f.call(0.17, 34), beam.darkened(0.15), 3.0)
	ci.draw_line(f.call(-0.17, 35.5), f.call(0.17, 35.5), RED.darkened(0.3), 1.5)
	# 匾額
	var bp: Vector2 = f.call(0, 29)
	ci.draw_rect(Rect2(bp - Vector2(7.5, 4), Vector2(15, 8)), Color(0.12, 0.2, 0.32))
	ci.draw_rect(Rect2(bp - Vector2(7.5, 4), Vector2(15, 8)), GOLD, false, 1.0)
	label(ci, bp, "旌表", 6, GOLD)
	# 屋頂：邊樓低、明樓高
	var ra := 0.12
	var rb := 0.09
	var side := func(sg: float) -> void:
		var oo: Vector2 = f.call(0.31 * sg, 0) - c
		roof(ci, c + oo, ra if ax else rb, rb if ax else ra, 21, 7, ROOF_GL, "hip", ax, 0.04, 2.5)
	side.call(-1.0)
	var oc: Vector2 = f.call(0, 0) - c
	roof(ci, c + oc, 0.19 if ax else rb, rb if ax else 0.19, 37, 9, ROOF_GL, "hip", ax, 0.06, 3.0)
	side.call(1.0)

static func garden(ci, c: Vector2, v: int) -> void:
	var pond := []
	for k in 14:
		var ang := k / 14.0 * TAU
		pond.append(P(c, -0.12 + cos(ang) * 0.25, 0.12 + sin(ang) * 0.2))
	poly(ci, pond, WATER.lerp(Color.WHITE, 0.3 if season == 3 else 0.0))
	line(ci, pond + [pond[0]], STONE.darkened(0.2), 1.0)
	var r := P(c, 0.25, 0.25)
	poly(ci, [r + Vector2(-5, 0), r + Vector2(4, 0), r + Vector2(6, -8), r + Vector2(1, -15), r + Vector2(-4, -9)], STONE.darkened(0.1))
	var pv := c + iso(-0.2, -0.2)
	for u in [[-0.1, -0.1], [0.1, -0.1], [0.1, 0.1], [-0.1, 0.1]]:
		ci.draw_line(P(pv, u[0], u[1]), P(pv, u[0], u[1], 10), RED, 1.5)
	roof(ci, pv, 0.1, 0.1, 10, 9, ROOF_G, "pyramid", true, 0.08, 3.0)
	tree_willow(ci, P(c, 0.3, -0.25), 0.9)


static func theater(ci, c: Vector2, v: int) -> void:
	# 後臺
	var bk := c + iso(-0.2, -0.2)
	box(ci, bk, 0.22, 0.2, 13, WALL_W)
	timber(ci, bk, 0.22, 0.2, 0, 13, 2)
	roof(ci, bk, 0.22, 0.2, 13, 10, ROOF_G, "gable", true, 0.06, 2.0)
	# 戲臺
	var st := c + iso(0.1, 0.05)
	shadow(ci, st, 0.34, 0.28, 30)
	box(ci, st, 0.34, 0.28, 7, STONE, 0, true, false)
	var back := [P(st, -0.28, -0.22, 7), P(st, 0.28, -0.22, 7), P(st, 0.28, -0.22, 22), P(st, -0.28, -0.22, 22)]
	poly(ci, back, RED.darkened(0.1))
	line(ci, [P(st, -0.28, -0.22, 22), P(st, 0.28, -0.22, 22)], GOLD.darkened(0.2), 2.0)
	for q in [[-0.3, 0.24], [0.3, 0.24], [0.3, -0.2]]:
		ci.draw_line(P(st, q[0], q[1], 7), P(st, q[0], q[1], 22), RED, 2.5)
	line(ci, [P(st, -0.3, 0.24, 21), P(st, 0.3, 0.24, 21), P(st, 0.3, -0.2, 21)], GOLD.darkened(0.15), 2.0)
	# 臺上伶人
	for k in 2:
		var q := P(st, -0.05 + k * 0.18, 0.02, 7)
		ci.draw_line(q, q - Vector2(0, 6), [Color(0.85, 0.2, 0.15), Color(0.2, 0.4, 0.7)][k], 3.0)
		ci.draw_circle(q - Vector2(0, 7.5), 1.5, Color(0.95, 0.85, 0.75))
	roof(ci, st, 0.34, 0.28, 22, 13, ROOF_G, "hip", true, 0.12, 6.0)
	lantern(ci, P(st, -0.38, 0.32, 21))
	lantern(ci, P(st, 0.38, 0.32, 21))

static func small_office(ci, c: Vector2, sg: String, wall: Color, v: int) -> void:
	var p := c + iso(-0.05, -0.05)
	shadow(ci, p, 0.3, 0.24, 28)
	box(ci, p, 0.33, 0.27, 4, STONE, 0, true, false)
	box(ci, p, 0.3, 0.24, 10, wall, 4, false, false)
	timber(ci, p, 0.3, 0.24, 4, 10, 3)
	door(ci, p, 0.3, 0.24, 0.5, 0.18, 8, true, 4, true)
	window(ci, p, 0.3, 0.24, 0.12, 0.28, 7, 12, true)
	window(ci, p, 0.3, 0.24, 0.72, 0.88, 7, 12, true)
	window(ci, p, 0.3, 0.24, 0.32, 0.68, 7, 12, false)
	roof(ci, p, 0.3, 0.24, 14, 12, ROOF_G, "hip", true, 0.09, 3.0)
	for k in 2:
		var sp := P(c, 0.1 + k * 0.2, 0.38)
		box(ci, sp, 0.025, 0.025, 2, STONE, 0, true, false)
	_banner(ci, P(c, 0.38, 0.32), sg, 26)


static func well(ci, c: Vector2, v: int) -> void:
	box(ci, c, 0.14, 0.14, 5, STONE, 0, true)
	ci.draw_circle(P(c, 0, 0, 5), 3.0, Color(0.15, 0.2, 0.25))
	for s in [-1, 1]:
		ci.draw_line(P(c, -0.16 * s, 0.16 * s), P(c, -0.16 * s, 0.16 * s, 16), WOOD, 1.5)
	ci.draw_line(P(c, -0.16, 0.16, 15), P(c, 0.16, -0.16, 15), WOOD, 1.5)
	roof(ci, c, 0.2, 0.08, 16, 5, ROOF_G, "gable", false, 0.04, 1.0)
	box(ci, c + iso(0.25, 0.2), 0.05, 0.05, 4, WOOD_L)


static func firewatch(ci, c: Vector2, v: int) -> void:
	var t := c + iso(-0.14, -0.14)
	var top := 40.0
	shadow(ci, t, 0.17, 0.17, 60)
	var g := 0.17
	var w := 0.11
	var wood := WOOD.darkened(0.1)
	var order := [[-1, -1], [1, -1], [-1, 1], [1, 1]]
	for q in order:
		ci.draw_line(P(t, q[0] * g, q[1] * g), P(t, q[0] * w, q[1] * w, top), wood, 2.4)
	# 斜撐：左前與右前兩面
	for seg in 3:
		var h0 := seg * top / 3.0
		var h1 := (seg + 1) * top / 3.0
		var s0 := lerpf(g, w, h0 / top)
		var s1 := lerpf(g, w, h1 / top)
		for pair in [[[-1, 1], [1, 1]], [[1, 1], [1, -1]]]:
			var a0: Array = pair[0]
			var a1: Array = pair[1]
			ci.draw_line(P(t, a0[0] * s0, a0[1] * s0, h0), P(t, a1[0] * s1, a1[1] * s1, h1), wood.lightened(0.1), 1.2)
			ci.draw_line(P(t, a1[0] * s0, a1[1] * s0, h0), P(t, a0[0] * s1, a0[1] * s1, h1), wood.lightened(0.1), 1.2)
			ci.draw_line(P(t, a0[0] * s1, a0[1] * s1, h1), P(t, a1[0] * s1, a1[1] * s1, h1), wood, 1.5)
	# 望臺
	box(ci, t, 0.16, 0.16, 2, WOOD_L, top, true, false)
	for q in [[-0.16, 0.16], [0.16, 0.16], [0.16, -0.16]]:
		ci.draw_line(P(t, q[0], q[1], top + 2), P(t, q[0], q[1], top + 12), wood, 1.5)
	line(ci, [P(t, -0.16, 0.16, top + 6), P(t, 0.16, 0.16, top + 6), P(t, 0.16, -0.16, top + 6)], wood, 1.2)
	ell(ci, P(t, 0, 0, top + 7), 2.6, 3.2, GOLD.darkened(0.25))
	ci.draw_line(P(t, 0, 0, top + 10), P(t, 0, 0, top + 12), INK, 1.0)
	roof(ci, t, 0.16, 0.16, top + 12, 9, ROOF_G, "pyramid", true, 0.08, 3.0)
	# 前方小屋
	var sh := c + iso(0.24, -0.02)
	box(ci, sh, 0.17, 0.13, 9, WOOD_L)
	timber(ci, sh, 0.17, 0.13, 0, 9, 2)
	door(ci, sh, 0.17, 0.13, 0.55, 0.3, 7, true, 0, false, WOOD.darkened(0.2))
	roof(ci, sh, 0.17, 0.13, 9, 7, ROOF_G, "gable", true, 0.05, 1.0)
	for k in 2:
		jar(ci, P(c, -0.05 + k * 0.14, 0.4))

static func _silo(ci, p: Vector2, r: float, h: float) -> void:
	var pts := []
	var cols := []
	var base := WALL_M.darkened(0.05)
	for k in 9:
		var t := k / 8.0
		var ang := PI - t * PI
		pts.append(p + Vector2(cos(ang) * r, sin(ang) * r * 0.45))
		cols.append(base.darkened(0.25 * (1.0 - t)))
	pts.append(p + Vector2(r, -h))
	cols.append(base.lightened(0.05))
	pts.append(p + Vector2(-r, -h))
	cols.append(base.darkened(0.2))
	grad(ci, pts, cols)
	for k in 5:
		var x := -r + (k + 0.5) * r * 2.0 / 5.0
		ci.draw_line(p + Vector2(x, -h + 1), p + Vector2(x, sqrt(maxf(r * r - x * x, 0.0)) * 0.45 - 1), Color(0.45, 0.35, 0.2, 0.5), 1.0)
	line(ci, pts.slice(0, 9), OUT, 1.0)
	var rc := snowy(ROOF_T)
	var apex := p + Vector2(0, -h - r * 1.3)
	poly(ci, [p + Vector2(-r - 3, -h + 1), p + Vector2(0, -h + r * 0.35), p + Vector2(r + 3, -h + 1), apex], rc)
	poly(ci, [p + Vector2(0, -h + r * 0.35), p + Vector2(r + 3, -h + 1), apex], rc.lightened(0.1))
	for k in 6:
		var t := (k + 0.5) / 6.0
		var e := (p + Vector2(-r - 3, -h + 1)).lerp(p + Vector2(r + 3, -h + 1), t)
		e.y += sin(t * PI) * r * 0.3
		ci.draw_line(e, e.lerp(apex, 0.6), rc.darkened(0.25), 1.0)
	ci.draw_circle(apex, 1.5, WOOD.darkened(0.3))


static func granary(ci, c: Vector2, v: int) -> void:
	shadow(ci, c, 0.42, 0.36, 22)
	box(ci, c, 0.45, 0.39, 3, STONE, 0, true, false)
	var bc := c + iso(-0.16, -0.22)
	box(ci, bc, 0.26, 0.12, 9, WOOD_L, 3, false, false)
	timber(ci, bc, 0.26, 0.12, 3, 9, 3)
	door(ci, bc, 0.26, 0.12, 0.5, 0.25, 7, true, 3, false, WOOD.darkened(0.2))
	roof(ci, bc, 0.26, 0.12, 12, 8, ROOF_G, "gable", true, 0.06, 1.5)
	_silo(ci, P(c, -0.26, 0.16, 3), 7.5, 11)
	_silo(ci, P(c, 0.2, 0.2, 3), 8.0, 12)
	for k in 3:
		ell(ci, P(c, 0.36 - k * 0.07, 0.36, 3) + Vector2(0, -2), 2.6, 2.0, Color(0.82, 0.74, 0.5))

static func warehouse(ci, c: Vector2, v: int) -> void:
	shadow(ci, c, 0.42, 0.26, 26)
	box(ci, c, 0.45, 0.29, 3, STONE, 0, true, false)
	box(ci, c, 0.42, 0.26, 11, WOOD_L, 3, false, false)
	timber(ci, c, 0.42, 0.26, 3, 11, 4)
	door(ci, c, 0.42, 0.26, 0.3, 0.2, 9, true, 3, false, WOOD.darkened(0.25))
	door(ci, c, 0.42, 0.26, 0.7, 0.2, 9, true, 3, false, WOOD.darkened(0.25))
	window(ci, c, 0.42, 0.26, 0.35, 0.65, 8, 12, false)
	roof(ci, c, 0.42, 0.26, 14, 12, ROOF_G, "gable", true, 0.07, 1.5)
	var cp := c + iso(0.3, 0.42)
	box(ci, cp, 0.06, 0.06, 5, WOOD_L, 0, true, false)
	box(ci, cp + iso(-0.13, 0), 0.06, 0.06, 5, WOOD_L, 0, true, false)
	box(ci, cp + iso(-0.065, 0), 0.06, 0.06, 4.5, WOOD_L.lightened(0.1), 5, true, false)
	for k in 2:
		ell(ci, P(c, -0.25 + k * 0.1, 0.42) + Vector2(0, -2.5), 3.0, 2.6, Color(0.85, 0.8, 0.65))

static func lumber(ci, c: Vector2, v: int) -> void:
	box(ci, c + iso(-0.2, -0.2), 0.2, 0.15, 9, WOOD)
	roof(ci, c + iso(-0.2, -0.2), 0.2, 0.15, 9, 7, ROOF_T, "gable", true, 0.05, 1.0)
	for k in 3:
		_logs(ci, P(c, 0.1 + k * 0.12, 0.25 - k * 0.15))
	ci.draw_circle(P(c, -0.3, 0.3), 3.0, WOOD_L)
	tree_pine(ci, P(c, 0.35, -0.35), 0.9)


static func quarry(ci, c: Vector2, v: int) -> void:
	for k in 3:
		var p := c + iso(-0.25 + k * 0.15, -0.25 + k * 0.15)
		box(ci, p, 0.32 - k * 0.06, 0.32 - k * 0.06, 12 - k * 4, STONE.lightened(k * 0.06), 0, true)
	for q in [[0.3, 0.2], [0.2, 0.36], [0.38, 0.0]]:
		box(ci, P(c, q[0], q[1]) - c + c, 0.05, 0.05, 4, STONE.lightened(0.15), 0, true)


static func mine(ci, c: Vector2, v: int) -> void:
	var p := P(c, 0.05, 0.25)
	poly(ci, [p + Vector2(-7, 0), p + Vector2(-7, -9), p + Vector2(0, -13), p + Vector2(7, -9), p + Vector2(7, 0)], Color(0.1, 0.08, 0.07))
	ci.draw_line(p + Vector2(-8, 0), p + Vector2(-8, -12), WOOD, 2.0)
	ci.draw_line(p + Vector2(8, 0), p + Vector2(8, -12), WOOD, 2.0)
	ci.draw_line(p + Vector2(-10, -12), p + Vector2(10, -12), WOOD, 2.5)
	var cp := P(c, 0.35, 0.3)
	box(ci, cp, 0.07, 0.05, 4, WOOD, 2)
	ci.draw_circle(P(cp, 0, 0, 7), 2.5, Color(0.3, 0.3, 0.35))
	box(ci, c + iso(-0.3, 0.2), 0.12, 0.1, 7, WOOD)
	roof(ci, c + iso(-0.3, 0.2), 0.12, 0.1, 7, 5, ROOF_T, "gable", true, 0.04, 0.5)


static func mulberry(ci, c: Vector2, v: int) -> void:
	box(ci, c + iso(-0.3, -0.3), 0.13, 0.1, 8, WALL_M)
	roof(ci, c + iso(-0.3, -0.3), 0.13, 0.1, 8, 6, ROOF_T, "gable", true, 0.04, 0.5)
	for i in 3:
		for j in 3:
			if i == 0 and j == 0:
				continue
			var p := P(c, -0.33 + i * 0.3, -0.33 + j * 0.3)
			ci.draw_line(p, p - Vector2(0, 4), WOOD, 1.5)
			var col: Color = [Color(0.45, 0.65, 0.32), Color(0.3, 0.52, 0.25), Color(0.6, 0.55, 0.25), Color(0.5, 0.45, 0.4)][season]
			ci.draw_circle(p - Vector2(0, 7), 4.0, col)


static func tea(ci, c: Vector2, v: int) -> void:
	hill(ci, c, v)
	var col := Color(0.25, 0.5, 0.28) if season != 3 else Color(0.5, 0.6, 0.5)
	for k in 5:
		var t := -0.35 + k * 0.17
		var pts := []
		for s in 9:
			var u := -0.42 + s * 0.105
			pts.append(P(c, u, t, 6.0 + sin((u + 0.5) * PI) * 4.0 - absf(t) * 6.0))
		line(ci, pts, col, 3.0)
	var hp := c + iso(0.3, 0.3)
	box(ci, hp, 0.1, 0.08, 7, WALL_W)
	roof(ci, hp, 0.1, 0.08, 7, 5, ROOF_G, "gable", true, 0.04, 0.5)


static func fishery(ci, c: Vector2, v: int) -> void:
	var p := c + iso(-0.12, -0.12)
	for u in [[-0.15, -0.12], [0.15, -0.12], [0.15, 0.12], [-0.15, 0.12]]:
		ci.draw_line(P(p, u[0], u[1]), P(p, u[0], u[1], 6), WOOD, 1.5)
	box(ci, p, 0.17, 0.13, 8, WOOD_L, 6)
	roof(ci, p, 0.17, 0.13, 14, 7, ROOF_T, "gable", true, 0.05, 1.0)
	var np := P(c, 0.28, 0.2)
	for k in 3:
		ci.draw_line(np + Vector2(-8 + k * 8, 0), np + Vector2(-8 + k * 8, -12), WOOD, 1.0)
	for k in 4:
		ci.draw_line(np + Vector2(-8, -11 + k * 3), np + Vector2(8, -11 + k * 3), Color(0.3, 0.3, 0.3, 0.6), 1.0)


static func kiln(ci, c: Vector2, v: int) -> void:
	shadow(ci, c, 0.44, 0.18, 22)
	# 龍窯：依坡而上的磚砌窯室
	var brick := Color(0.62, 0.38, 0.27)
	for k in 6:
		var p := c + iso(-0.38 + k * 0.15, 0.0)
		var z := k * 1.6
		box(ci, p, 0.08, 0.13, 5 + z, brick, 0, false, false)
		var t := P(p, 0, 0, 5 + z)
		ell(ci, t, 6.0, 3.2, brick.lightened(0.05))
		ell(ci, t + Vector2(0, -0.8), 4.4, 2.0, brick.lightened(0.15))
	ell(ci, P(c, -0.45, 0.12, 2), 2.5, 3.0, Color(1.0, 0.55, 0.15))
	# 窯棚
	for q in [[-0.45, 0.2], [0.0, 0.2], [0.45, 0.2]]:
		ci.draw_line(P(c, q[0], q[1]), P(c, q[0], q[1], 17), WOOD.darkened(0.2), 1.5)
	roof(ci, c, 0.46, 0.2, 17, 7, ROOF_G, "gable", true, 0.05, 1.0)
	box(ci, c + iso(0.47, -0.12), 0.05, 0.05, 30, BRICK)
	# 成品瓷器
	box(ci, c + iso(0.1, 0.4), 0.18, 0.05, 3, WOOD, 0, true, false)
	for k in 4:
		var q := P(c, -0.02 + k * 0.08, 0.4, 3)
		ell(ci, q - Vector2(0, 2.5), 2.4, 2.6, Color(0.92, 0.94, 0.96))
		ci.draw_line(q - Vector2(1.6, 3), q - Vector2(-1.6, 3), Color(0.25, 0.4, 0.75), 1.2)
	ell(ci, P(c, -0.3, 0.38) + Vector2(0, -2), 4.0, 2.4, Color(0.8, 0.78, 0.72))

static func station(ci, c: Vector2, v: int) -> void:
	var p := c + iso(-0.08, -0.08)
	shadow(ci, p, 0.3, 0.24, 26)
	box(ci, p, 0.33, 0.27, 3, STONE, 0, true, false)
	box(ci, p, 0.3, 0.24, 10, WALL_W, 3, false, false)
	timber(ci, p, 0.3, 0.24, 3, 10, 3)
	door(ci, p, 0.3, 0.24, 0.5, 0.3, 8, true, 3, false, WOOD.darkened(0.2))
	window(ci, p, 0.3, 0.24, 0.32, 0.68, 6, 10, false)
	roof(ci, p, 0.3, 0.24, 13, 12, ROOF_G, "hip", true, 0.08, 3.0)
	# 拴馬樁與馬
	var hp := P(c, 0.35, 0.12)
	ci.draw_line(hp, hp - Vector2(0, 8), WOOD, 2.0)
	ci.draw_line(hp - Vector2(5, 7), hp - Vector2(-5, 7), WOOD, 1.5)
	var hc := Color(0.45, 0.3, 0.2) if v % 2 == 0 else Color(0.85, 0.82, 0.75)
	ell(ci, hp + Vector2(-8, -5), 4.5, 2.2, hc)
	ci.draw_line(hp + Vector2(-11, -4), hp + Vector2(-11, 0), hc.darkened(0.3), 1.0)
	ci.draw_line(hp + Vector2(-5, -4), hp + Vector2(-5, 0), hc.darkened(0.3), 1.0)
	ci.draw_line(hp + Vector2(-4, -6), hp + Vector2(-2, -9), hc, 2.0)
	var fp := P(c, 0.3, 0.38)
	ci.draw_line(fp, fp - Vector2(0, 32), INK, 1.5)
	poly(ci, [fp - Vector2(0, 32), fp - Vector2(-13, 30), fp - Vector2(-13, 20), fp - Vector2(0, 22)], Color(0.92, 0.75, 0.25))
	label(ci, fp - Vector2(-6.5, 26), "驛", 8, RED.darkened(0.2))


static func dock(ci, c: Vector2, v: int, wdir: Vector2i) -> void:
	var d := Vector2(wdir)
	var ax := wdir.x != 0
	var pc := c + iso(d.x * 0.45, d.y * 0.45)
	var a := 0.55 if ax else 0.18
	var b := 0.18 if ax else 0.55
	for u in [-1.0, 1.0]:
		for w in [-1.0, 1.0]:
			ci.draw_line(P(pc, a * u * 0.8, b * w * 0.8), P(pc, a * u * 0.8, b * w * 0.8, -6), WOOD.darkened(0.3), 2.0)
	box(ci, pc, a, b, 3, WOOD_L, 0, true)
	var hp := c + iso(-d.x * 0.18 - 0.05, -d.y * 0.18 - 0.05)
	box(ci, hp, 0.2, 0.17, 10, WOOD_L)
	roof(ci, hp, 0.2, 0.17, 10, 9, ROOF_G, "gable", ax, 0.06, 1.5)
	var cr := P(c, d.x * 0.6 + 0.15, d.y * 0.6 + 0.15, 3)
	ci.draw_line(cr, cr - Vector2(0, 26), WOOD, 2.0)
	ci.draw_line(cr - Vector2(0, 24), cr - Vector2(0, 24) + iso(d.x, d.y) * 0.5, WOOD, 1.5)
	box(ci, c + iso(0.25 - d.x * 0.1, 0.25 - d.y * 0.1), 0.06, 0.06, 5, WOOD, 0, true)


static func town(ci, c: Vector2, name: String) -> void:
	var e := 0.95
	var wc := Color(0.55, 0.53, 0.5)
	walled(ci, c, e, wc, 14, func():
		for q in [[-0.4, -0.4], [0.2, -0.45], [-0.45, 0.2], [0.15, 0.15]]:
			var p := c + iso(q[0], q[1])
			box(ci, p, 0.2, 0.16, 10, WALL_W)
			roof(ci, p, 0.2, 0.16, 10, 9, ROOF_G, "hip", true, 0.06, 2.0)
		var t := c + iso(-0.1, -0.1)
		pagoda_small(ci, t))
	var g := c + iso(0.0, e)
	box(ci, g, 0.25, 0.1, 18, wc)
	face_l(ci, g, 0.25, 0.1, 0.35, 0.65, 0, 11, Color(0.12, 0.1, 0.08))
	box(ci, g, 0.2, 0.08, 9, RED, 18)
	roof(ci, g, 0.22, 0.1, 27, 10, ROOF_G, "hip", true, 0.08, 4.0)
	var lp := P(c, 0, 0, 70)
	var f: Font = Defs.font
	var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 14
	ci.draw_rect(Rect2(lp - Vector2(w * 0.5, 11), Vector2(w, 22)), Color(0.66, 0.16, 0.12, 0.92))
	ci.draw_rect(Rect2(lp - Vector2(w * 0.5, 11), Vector2(w, 22)), Color(0.95, 0.85, 0.6), false, 1.5)
	label(ci, lp, name, 16, Color(0.98, 0.94, 0.85))


static func pagoda_small(ci, c: Vector2) -> void:
	var z := 0.0
	for k in 4:
		var a := 0.12 - k * 0.015
		box(ci, c, a, a, 8, WALL_W, z)
		z += 8
		roof(ci, c, a, a, z, 3, ROOF_G, "pyramid", true, 0.06, 1.5)
		z += 1.5


static func wall_tile(ci, c: Vector2, conn: Array, gate: bool, road_ax_x: bool) -> void:
	# conn: [+x, -x, +y, -y]
	var col := Color(0.58, 0.56, 0.52)
	var h := 13.0
	var t := 0.13
	if conn[1]:
		box(ci, c + iso(-0.25, 0), 0.25, t, h, col)
	if conn[3]:
		box(ci, c + iso(0, -0.25), t, 0.25, h, col)
	if gate:
		var a := 0.3 if not road_ax_x else 0.2
		var b := 0.2 if not road_ax_x else 0.3
		box(ci, c, a, b, 20, col)
		if road_ax_x:
			face_r(ci, c, a, b, 0.3, 0.7, 0, 12, Color(0.1, 0.08, 0.07))
		else:
			face_l(ci, c, a, b, 0.3, 0.7, 0, 12, Color(0.1, 0.08, 0.07))
		box(ci, c, a * 0.85, b * 0.85, 9, RED, 20)
		roof(ci, c, a * 0.85, b * 0.85, 29, 10, ROOF_G, "hip", not road_ax_x, 0.08, 3.5)
	else:
		box(ci, c, t + 0.02, t + 0.02, h + 2, col.darkened(0.05), 0, true)
	if conn[0]:
		box(ci, c + iso(0.25, 0), 0.25, t, h, col)
		for k in 2:
			box(ci, c + iso(0.12 + k * 0.22, 0), 0.04, t, 3, col, h, true)
	if conn[2]:
		box(ci, c + iso(0, 0.25), t, 0.25, h, col)
		for k in 2:
			box(ci, c + iso(0, 0.12 + k * 0.22), t, 0.04, 3, col, h, true)


static func bridge(ci, c: Vector2, ax_x: bool, stone: bool) -> void:
	var col := STONE.lightened(0.05) if stone else WOOD_L
	var a := 0.5 if ax_x else 0.22
	var b := 0.22 if ax_x else 0.5
	for u in [-0.3, 0.3]:
		var q := P(c, u if ax_x else 0.0, 0.0 if ax_x else u)
		ci.draw_line(q + Vector2(0, 2), q - Vector2(0, 5), col.darkened(0.35), 3.0)
	box(ci, c, a, b, 3, col, 4, true)
	var r0 := P(c, -a, b, 9) if ax_x else P(c, a, -b, 9)
	var r1 := P(c, a, b, 9)
	line(ci, [r0, r1], col.darkened(0.3), 1.5)
	for k in 5:
		var q := r0.lerp(r1, k / 4.0)
		ci.draw_line(q, q + Vector2(0, 3), col.darkened(0.3), 1.0)


# ───────────────────────── 車船人物 ─────────────────────────

static func vehicle(ci, kind: String, dir: Vector2i, cargo_col: Color, loaded: bool) -> void:
	var u := iso(dir.x, dir.y).normalized()
	var w := iso(-dir.y, dir.x).normalized()
	match kind:
		"oxcart", "horsecart":
			var body := Color(0.45, 0.3, 0.18) if kind == "oxcart" else Color(0.3, 0.2, 0.15)
			var ap := u * 8
			ci.draw_line(ap - u * 3, ap + u * 4, body, 5.0 if kind == "oxcart" else 3.5)
			ci.draw_circle(ap + u * 5 - Vector2(0, 2), 2.2, body.darkened(0.1))
			for s in [-1, 1]:
				ci.draw_line(ap + w * s * 1.5, ap + w * s * 1.5 + Vector2(0, 3), body.darkened(0.2), 1.0)
			ci.draw_line(Vector2.ZERO, ap - u * 2, WOOD, 1.0)
			var c0 := -u * 5
			var pts := [c0 - u * 5 - w * 4, c0 + u * 4 - w * 4, c0 + u * 4 + w * 4, c0 - u * 5 + w * 4]
			for k in 4:
				pts[k] -= Vector2(0, 4)
			poly(ci, pts, WOOD_L)
			line(ci, pts + [pts[0]], OUT)
			if kind == "horsecart":
				poly(ci, [pts[0] - Vector2(0, 2), pts[1] - Vector2(0, 2), pts[2] - Vector2(0, 2), pts[3] - Vector2(0, 2), c0 - Vector2(0, 12)], Color(0.25, 0.25, 0.3))
			elif loaded:
				ci.draw_circle(c0 - Vector2(0, 7), 3.5, cargo_col)
			for s in [-1, 1]:
				ci.draw_circle(c0 + w * 4.5 * s - Vector2(0, 2), 2.5, WOOD.darkened(0.3))
		"barge", "junk":
			var big := kind == "junk"
			var L := 13.0 if big else 10.0
			var Wd := 5.0 if big else 3.5
			var hull := [u * L - Vector2(0, 4), u * (L - 4) + w * Wd, -u * (L - 2) + w * Wd, -u * L - Vector2(0, 3),
				-u * (L - 2) - w * Wd, u * (L - 4) - w * Wd]
			poly(ci, hull, Color(0.45, 0.3, 0.2))
			line(ci, hull + [hull[0]], INK, 1.0)
			if loaded:
				ci.draw_circle(u * 3 - Vector2(0, 3), 3.0, cargo_col)
				ci.draw_circle(u * 7 - Vector2(0, 2.5), 2.5, cargo_col)
			var cab := -u * 5
			poly(ci, [cab - w * 3 - u * 3, cab - w * 3 + u * 3, cab - w * 3 + u * 3 - Vector2(0, 6), cab - w * 3 - u * 3 - Vector2(0, 6)], Color(0.2, 0.18, 0.16))
			poly(ci, [cab + w * 3 - u * 3, cab + w * 3 + u * 3, cab + u * 3 - Vector2(0, 9), cab - u * 3 - Vector2(0, 9)], Color(0.28, 0.24, 0.2))
			if big:
				var m := u * 2
				ci.draw_line(m, m - Vector2(0, 30), WOOD.darkened(0.3), 1.5)
				poly(ci, [m - Vector2(0, 29) + w * 1, m - Vector2(0, 9) + w * 1, m - Vector2(0, 9) - u * 9 + w * 1, m - Vector2(0, 27) - u * 7 + w * 1], Color(0.7, 0.4, 0.25))
				for k in 4:
					ci.draw_line(m - Vector2(0, 12 + k * 4.5), m - Vector2(0, 12 + k * 4.5) - u * 8, Color(0.4, 0.2, 0.1), 0.8)


static func walker(ci, v: int) -> void:
	var cols := [Color(0.3, 0.35, 0.5), Color(0.55, 0.3, 0.25), Color(0.4, 0.45, 0.35), Color(0.75, 0.72, 0.65), Color(0.35, 0.3, 0.3)]
	var col: Color = cols[v % cols.size()]
	ci.draw_line(Vector2(0, 0), Vector2(0, -5), col, 2.5)
	ci.draw_circle(Vector2(0, -6.5), 1.4, Color(0.85, 0.72, 0.58))
	if v % 3 == 0:
		poly(ci, [Vector2(-3.5, -6.5), Vector2(3.5, -6.5), Vector2(0, -9.5)], Color(0.8, 0.68, 0.4))
	else:
		ci.draw_circle(Vector2(0, -7.5), 1.3, Color(0.1, 0.08, 0.08))
