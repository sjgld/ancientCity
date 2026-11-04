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
const ROOF_G := Color(0.43, 0.48, 0.53)   # 青灰瓦：比純灰略帶青，和牆面、地面拉開明暗
const ROOF_T := Color(0.72, 0.6, 0.36)
const ROOF_GL := Color(0.25, 0.48, 0.38)
const ROOF_Y := Color(0.8, 0.6, 0.18)
const STONE := Color(0.62, 0.6, 0.56)
const BRICK := Color(0.52, 0.5, 0.48)
const GOLD := Color(0.9, 0.75, 0.35)
const SIGN := Color(0.99, 0.86, 0.48)   # 匾額金字：比 GOLD 亮一點，黑底上更醒目
const WATER := Color(0.42, 0.6, 0.62)

static var season := 0
# 界畫墨線：建築一律以墨線勾勒。外輪廓 1.4、結構線 1.0、細節（窗格、瓦壟、小擺設）不描。
const INK_LINE := Color(0.14, 0.1, 0.08, 0.9)
const W_OUT := 1.4
const W_MID := 1.0
const BUILDING_SCALE := 1.1   # 建築本體放大，街面更飽滿（台基不放大）
static var no_ink := false     # 畫半透明疊加層（簷下陰影、高光帶）時暫時關掉描邊
const PLINTH_H := 3.0
const PLINTH_TYPES := ["house", "shop", "workshop", "granary", "warehouse", "constable", "clinic", "firewatch", "school", "theater", "station"]


## 立在石砌台基上的建築：台基畫在地面層，建築本體要抬高台基的高度。
static func on_plinth(b: Dictionary) -> bool:
	return b.size == 1 and b.type in PLINTH_TYPES


## 建築本體的畫法變換：以地面中心 c 放大，並抬到台基上。回傳 [位移, 縮放]，供 draw_set_transform 用。
static func body_xf(b: Dictionary, c: Vector2, off: Vector2 = Vector2.ZERO) -> Array:
	var k := BUILDING_SCALE
	var lift := Vector2(0, -PLINTH_H) if on_plinth(b) else Vector2.ZERO
	return [c + off + lift - c * k, Vector2(k, k)]
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
	if col.a >= 0.9:
		ink_edge(ci, clean)


## 面的結構線：面夠大才描，窗格、瓦當這類小塊不描。
static func ink_edge(ci, pts: PackedVector2Array, w: float = W_MID) -> void:
	if no_ink or pts.size() < 3:
		return
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	if r.size.x * r.size.y < 60.0 or minf(r.size.x, r.size.y) < 3.0:
		return
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), INK_LINE, w, true)


static func grad(ci, pts: Array, cols: Array) -> void:
	ci.draw_polygon(PackedVector2Array(pts), PackedColorArray(cols))
	ink_edge(ci, PackedVector2Array(pts))


## OUT（舊的半透明褐線）一律換成墨線。
static func line(ci, pts: Array, col: Color = OUT, w: float = 1.0) -> void:
	if col == OUT:
		col = INK_LINE
		w = maxf(w, W_MID)
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
		line(ci, [W + up, Nn + up, E + up], OUT, W_OUT)
	line(ci, [W + up, W, S, E, E + up], OUT, W_OUT)
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


## 屋頂。kind: "hip" 廡殿（四坡，最尊）、"xieshan" 歇山（下四坡、上露山花）、"gable" 懸山、"pyramid" 攢尖。ax: 屋脊沿 x 軸。
## 等級依宋制：京城廡殿；衙署大堂、寺院大殿、城樓歇山；民居、商號、作坊懸山。
static func roof(ci, c: Vector2, a: float, b: float, z: float, rh: float, col: Color,
		kind: String = "hip", ax: bool = true, o: float = 0.1, curl: float = 3.0) -> void:
	var thatch := col.is_equal_approx(ROOF_T)
	col = snowy(col)
	# 簷下陰影落在牆上
	if z >= 6.0:
		var sc := Color(0, 0, 0, 0.2)
		no_ink = true
		frect(ci, c, a, b, 0, 1, z - 4.5, z, sc, true)
		frect(ci, c, a, b, 0, 1, z - 4.5, z, sc, false)
		no_ink = false
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
		"xieshan":
			R = maxf(A - B * 0.4, 0.06)
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
	var edge := INK_LINE
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
	no_ink = true
	poly(ci, front + tmp, c_vpos.lightened(0.06))
	no_ink = false
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
		if kind == "xieshan":
			# 山花：屋脊兩端立起的三角牆面，下緣一道搏風，與四坡相接處即「歇」
			var hb := z + rh * 0.48
			var s1: Vector2 = f.call(R + 0.02, B * 0.55, hb)
			var s2: Vector2 = f.call(R + 0.02, -B * 0.55, hb)
			poly(ci, [s1, s2, r2], WALL_W.darkened(0.12) if ax else WALL_W.darkened(0.22))
			ci.draw_line(s1, s2, INK_LINE, W_MID)
			ci.draw_line(s1.lerp(r2, 0.5), s2.lerp(r2, 0.5), Color(WOOD.darkened(0.3), 0.6), 1.0)
			line(ci, [s1, r2, s2], INK_LINE, 2.0)
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
	no_ink = true
	poly(ci, front + fas2, col.darkened(0.55))
	if not side.is_empty():
		var s2 := side.duplicate()
		s2.reverse()
		var s3 := []
		for p in s2:
			s3.append(p + Vector2(0, 2.2))
		poly(ci, side + s3, col.darkened(0.45))
	no_ink = false
	# 簷口一道淺色高光（瓦當反光），再以墨線勾出屋簷外緣
	if not thatch:
		var hi := []
		for p in front:
			hi.append((p as Vector2) + Vector2(0, -0.8))
		ci.draw_polyline(PackedVector2Array(hi), Color(1, 1, 1, 0.35), 1.0, true)
	var outer := []
	for p in front:
		outer.append((p as Vector2) + Vector2(0, 2.2))
	ci.draw_polyline(PackedVector2Array(outer), INK_LINE, W_OUT, true)
	if not side.is_empty():
		var so := []
		for p in side:
			so.append((p as Vector2) + Vector2(0, 2.2))
		ci.draw_polyline(PackedVector2Array(so), INK_LINE, W_OUT, true)
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
	hall(ci, c + iso(-0.04, -0.25), 0.3, 0.12, 14, WALL_W, ROOF_G, "gable", true, 12)
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
	var boards := ["綢莊", "茶肆", "米行", "錢莊", "香鋪", "書坊", "繡坊", "油坊"]
	var awn: Color = [Color(0.3, 0.42, 0.62), RED, Color(0.75, 0.6, 0.3), Color(0.35, 0.55, 0.4)][v % 4]
	match lvl:
		1:
			# 傘攤：清明上河圖街邊常見的大傘下攤桌，後有小棚
			var p := c + iso(-0.2, -0.2)
			box(ci, p, 0.18, 0.15, 8, WOOD_L)
			timber(ci, p, 0.18, 0.15, 0, 8, 2)
			frect(ci, p, 0.18, 0.15, 0.12, 0.88, 0, 7, Color(0.22, 0.15, 0.11), true)
			roof(ci, p, 0.18, 0.15, 8, 7, ROOF_T, "gable", true, 0.05, 0.8)
			var tc := c + iso(0.12, 0.14)
			box(ci, tc, 0.17, 0.09, 4.5, WOOD)
			_goods(ci, P(tc, -0.04, 0, 4.5), v)
			_goods(ci, P(tc, 0.08, 0.02, 4.5), v + 2)
			box(ci, c + iso(0.36, -0.12), 0.05, 0.05, 3, WOOD_L, 0, true, false)
			_parasol(ci, P(c, 0.1, 0.12), 21, 15, [Color(0.93, 0.88, 0.74), awn][v % 2])
		2:
			# 商號：兩層店面，卸下的門板疊在一旁，簷下垂掛布幌
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
			roof(ci, p, 0.28, 0.22, 24, 11, ROOF_G, "gable", true, 0.09, 3.0)
			var bp := P(p, 0.0, 0.33, 12.5)
			ci.draw_rect(Rect2(bp - Vector2(14, 5.5), Vector2(28, 11)), Color(0.13, 0.09, 0.07))
			ci.draw_rect(Rect2(bp - Vector2(14, 5.5), Vector2(28, 11)), GOLD.darkened(0.2), false, 1.0)
			label(ci, bp + Vector2(0, -0.3), boards[v % boards.size()], 9, SIGN)
			for k in 3:
				box(ci, c + iso(0.4, -0.18 + k * 0.03), 0.02, 0.1, 9 - k, WOOD.darkened(0.1), 0, false, false)
			_huang(ci, P(p, 0.38, 0.33, 20), awn, boards[v % boards.size()].substr(0, 1))
		_:
			# 酒樓：門前紮起「彩樓歡門」，旁立酒旗（見清明上河圖孫羊正店）
			var p := c + iso(-0.06, -0.06)
			shadow(ci, p, 0.4, 0.34, 44)
			box(ci, p, 0.43, 0.37, 3, STONE, 0, true, false)
			box(ci, p, 0.4, 0.34, 10, WOOD_L, 3, false, false)
			frect(ci, p, 0.4, 0.34, 0.06, 0.94, 3, 11, Color(0.22, 0.14, 0.1), true)
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
			roof(ci, p, 0.36, 0.3, 27, 14, ROOF_G, "gable", true, 0.11, 5.0)
			_cailou(ci, p, 0.44, 0.42)
			_wineflag(ci, P(c, 0.47, 0.1), 46)


static func _banner(ci, base: Vector2, ch: String, h: float) -> void:
	ci.draw_line(base, base - Vector2(0, h), WOOD.darkened(0.3), 1.5)
	var r := Rect2(base - Vector2(-1, h - 1), Vector2(10, 14))
	ci.draw_rect(r, Color(0.96, 0.94, 0.86))
	ci.draw_rect(r, RED, false, 1.0)
	label(ci, r.get_center() + Vector2(0, -1), ch, 9, RED.darkened(0.35))


static func workshop(ci, c: Vector2, lvl: int, v: int) -> void:
	match lvl:
		1:
			# 染坊：瓦頂小坊、染缸，門前高架晾著長幅染布
			var p := c + iso(-0.22, -0.16)
			box(ci, p, 0.2, 0.16, 9, WALL_M)
			timber(ci, p, 0.2, 0.16, 0, 9, 2)
			face_l(ci, p, 0.2, 0.16, 0.3, 0.7, 0, 7, Color(0.2, 0.14, 0.1))
			roof(ci, p, 0.2, 0.16, 9, 8, ROOF_G, "gable", true, 0.06, 1.0)
			_vat(ci, P(c, -0.02, 0.3), Color(0.2, 0.3, 0.55))
			_vat(ci, P(c, 0.14, 0.38), Color(0.6, 0.18, 0.15))
			_dyerack(ci, P(c, 0.02, 0.0), P(c, 0.44, -0.06), 26, 3, v)
		2:
			# 鐵匠鋪：敞棚下爐火通紅，磚砌煙囪
			var p := c + iso(-0.08, -0.08)
			shadow(ci, p, 0.32, 0.24, 28)
			box(ci, p, 0.34, 0.26, 2, STONE, 0, true, false)
			poly(ci, [P(p, -0.32, -0.24, 2), P(p, 0.32, -0.24, 2), P(p, 0.32, -0.24, 13), P(p, -0.32, -0.24, 13)], BRICK)
			poly(ci, [P(p, -0.32, -0.24, 2), P(p, -0.32, 0.24, 2), P(p, -0.32, 0.24, 13), P(p, -0.32, -0.24, 13)], BRICK.darkened(0.2))
			var fc := p + iso(-0.14, 0.08)
			box(ci, fc, 0.11, 0.1, 8, BRICK.darkened(0.1), 2, true, false)
			ell(ci, P(fc, 0, 0.1, 6), 4.2, 3.0, Color(1.0, 0.5, 0.12))
			ell(ci, P(fc, 0, 0.1, 6), 2.4, 1.7, Color(1.0, 0.86, 0.45))
			ell(ci, P(fc, 0, 0, 10), 5.0, 2.0, Color(1.0, 0.6, 0.2, 0.35))
			var av := p + iso(0.14, 0.18)
			box(ci, av, 0.035, 0.035, 4, WOOD.darkened(0.2), 2, false, false)
			poly(ci, [P(av, -0.08, 0, 6), P(av, 0.07, 0, 6), P(av, 0.05, 0, 8), P(av, -0.05, 0, 8)], Color(0.25, 0.25, 0.28))
			for q in [[-0.33, 0.25], [0.33, 0.25], [0.33, -0.25]]:
				ci.draw_line(P(p, q[0], q[1], 2), P(p, q[0], q[1], 14), WOOD.darkened(0.2), 2.0)
			roof(ci, p, 0.34, 0.26, 14, 10, ROOF_G, "gable", true, 0.08, 1.5)
			var ch := c + iso(0.2, -0.26)
			box(ci, ch, 0.05, 0.05, 32, BRICK, 0)
			_smoke(ci, P(ch, 0, 0, 34), v)
			for k in 3:
				ci.draw_line(P(c, 0.18 + k * 0.05, 0.36), P(c, 0.32 + k * 0.05, 0.3), Color(0.3, 0.3, 0.33), 2.0)
		_:
			# 織染工場：長廠房、成排晾布架、煙囪
			var p := c + iso(-0.16, -0.18)
			shadow(ci, p, 0.36, 0.2, 30)
			box(ci, p, 0.36, 0.2, 13, WALL_W)
			timber(ci, p, 0.36, 0.2, 0, 13, 5)
			for k in 4:
				window(ci, p, 0.36, 0.2, 0.08 + k * 0.23, 0.2 + k * 0.23, 5, 10, true)
			roof(ci, p, 0.36, 0.2, 13, 11, ROOF_G, "gable", true, 0.07, 1.5)
			box(ci, c + iso(0.3, -0.36), 0.05, 0.05, 34, BRICK)
			_smoke(ci, P(c, 0.3, -0.36, 36), v)
			_dyerack(ci, P(c, -0.42, 0.34), P(c, 0.12, 0.34), 24, 4, v)
			_dyerack(ci, P(c, 0.2, 0.42), P(c, 0.46, 0.06), 24, 2, v + 2)
			_vat(ci, P(c, 0.38, 0.3), Color(0.2, 0.3, 0.55))


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
	# 京城：黃琉璃廡殿；其餘衙署：青灰瓦歇山
	hall(ci, c + iso(-0.2, -0.35), 0.5, 0.26, 18, WALL_W, ROOF_Y if rank >= 5 else ROOF_G, "hip" if rank >= 5 else "xieshan", true, 18)
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
	roof(ci, g, 0.26, 0.1, 14, 9, ROOF_G, "gable", true, 0.07, 3.0)
	var names := ["里署", "鎮署", "縣衙", "州衙", "府衙", "皇城"]
	var bp := P(g, 0, 0.12, 17)
	ci.draw_rect(Rect2(bp - Vector2(13, 5.5), Vector2(26, 11)), Color(0.12, 0.08, 0.06))
	ci.draw_rect(Rect2(bp - Vector2(13, 5.5), Vector2(26, 11)), GOLD.darkened(0.2), false, 1.0)
	label(ci, bp + Vector2(0, -0.3), names[rank], 9, SIGN)
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
		# 重簷歇山、石綠琉璃：黃琉璃為皇家專用，縣城寺院不用
		hall(ci, m, 0.42, 0.28, 13, RED.lightened(0.1), ROOF_GL, "hip", true, 6)
		box(ci, m, 0.32, 0.2, 7, RED.lightened(0.1), 17)
		roof(ci, m, 0.32, 0.2, 24, 13, ROOF_GL, "xieshan", true, 0.1, 4.0)
		var bp := P(c, 0.35, 0.35)
		box(ci, bp, 0.07, 0.07, 6, BRICK.darkened(0.2))
		ci.draw_circle(bp - Vector2(0, 7), 3.0, BRICK.darkened(0.3)))
	var g := c + iso(0.0, 0.92)
	box(ci, g, 0.2, 0.07, 12, RED)
	roof(ci, g, 0.2, 0.08, 12, 7, ROOF_GL, "gable", true, 0.06, 2.5)


static func academy(ci, c: Vector2, v: int) -> void:
	walled(ci, c, 0.92, WALL_W, 8, func():
		hall(ci, c + iso(-0.25, -0.4), 0.45, 0.2, 14, WALL_W, ROOF_G, "xieshan", true, 13)
		tree_pine(ci, P(c, -0.6, 0.3), 1.0)
		tree_round(ci, P(c, 0.5, -0.5), 1.0, v)
		hall(ci, c + iso(0.15, 0.25), 0.35, 0.18, 11, WALL_W, ROOF_G, "gable", true, 10))
	var g := c + iso(0.0, 0.92)
	box(ci, g, 0.18, 0.06, 11, WALL_W)
	face_l(ci, g, 0.18, 0.06, 0.3, 0.7, 0, 8, Color(0.3, 0.2, 0.15))
	roof(ci, g, 0.18, 0.08, 11, 6, ROOF_G, "gable", true, 0.05, 2.0)
	var bp := P(g, 0, 0.1, 14)
	ci.draw_rect(Rect2(bp - Vector2(13, 5.5), Vector2(26, 11)), Color(0.12, 0.08, 0.06))
	ci.draw_rect(Rect2(bp - Vector2(13, 5.5), Vector2(26, 11)), GOLD.darkened(0.2), false, 1.0)
	label(ci, bp + Vector2(0, -0.3), "書院", 9, SIGN)


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
	roof(ci, c, 0.3, 0.3, z2 + 11, 17, ROOF_GL, "xieshan", true, 0.13, 5.0)

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
	label(ci, bp, "旌表", 7, SIGN)
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
	# 勾欄：欄杆圍起的演出場，後設戲臺與戲房，前有層層升高的看棚（腰棚），門口立招子
	var e := 0.44
	poly(ci, [P(c, -e, -e), P(c, e, -e), P(c, e, e), P(c, -e, e)], Color(0.72, 0.66, 0.56))
	# 戲房與戲臺
	var bk := c + iso(-0.24, -0.3)
	box(ci, bk, 0.2, 0.12, 12, WALL_W)
	roof(ci, bk, 0.2, 0.12, 12, 8, ROOF_G, "gable", true, 0.05, 1.5)
	var st := c + iso(-0.1, -0.08)
	box(ci, st, 0.24, 0.18, 6, STONE, 0, true, false)
	poly(ci, [P(st, -0.22, -0.16, 6), P(st, 0.22, -0.16, 6), P(st, 0.22, -0.16, 19), P(st, -0.22, -0.16, 19)], RED.darkened(0.1))
	for q in [[-0.23, 0.17], [0.23, 0.17], [0.23, -0.15]]:
		ci.draw_line(P(st, q[0], q[1], 6), P(st, q[0], q[1], 19), RED, 2.2)
	for k in 2:
		var q := P(st, -0.05 + k * 0.14, 0.0, 6)
		ci.draw_line(q, q - Vector2(0, 6), [Color(0.85, 0.2, 0.15), Color(0.2, 0.4, 0.7)][k], 3.0)
		ci.draw_circle(q - Vector2(0, 7.5), 1.5, Color(0.95, 0.85, 0.75))
	roof(ci, st, 0.24, 0.18, 19, 11, ROOF_G, "xieshan", true, 0.1, 5.0)
	# 腰棚：三層看席
	for k in 3:
		var sp := c + iso(0.18 + k * 0.08, 0.06 + k * 0.08)
		box(ci, sp, 0.05, 0.3, 2.5 + k * 2.5, WOOD_L, 0, true, false)
	# 欄杆
	var rc := RED.darkened(0.05)
	var corners := [P(c, -e, e), P(c, e, e), P(c, e, -e)]
	for i in 2:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		for k in 9:
			var q := a.lerp(b, k / 8.0)
			ci.draw_line(q, q - Vector2(0, 6), rc, 1.2)
		ci.draw_line(a - Vector2(0, 6), b - Vector2(0, 6), rc, 1.5)
		ci.draw_line(a - Vector2(0, 3), b - Vector2(0, 3), rc.darkened(0.2), 1.0)
	# 招子：門口兩竿長幡
	for k in 2:
		var bp := P(c, e + 0.04, 0.08 + k * 0.22)
		ci.draw_line(bp, bp - Vector2(0, 34), WOOD.darkened(0.3), 1.5)
		var col: Color = [Color(0.85, 0.3, 0.2), Color(0.25, 0.45, 0.65)][(k + v) % 2]
		poly(ci, [bp - Vector2(0, 33), bp + Vector2(6, -33), bp + Vector2(7, -12), bp + Vector2(3.5, -15), bp + Vector2(0, -12)], col)


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
	roof(ci, p, 0.3, 0.24, 14, 12, ROOF_G, "gable", true, 0.09, 3.0)
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
	# 望火樓：高處磚砌望樓，樓上有人瞭望，下有官屋，備水桶、梯子（見《東京夢華錄》）
	var t := c + iso(-0.16, -0.16)
	shadow(ci, t, 0.16, 0.16, 60)
	var bc := Color(0.6, 0.5, 0.45)
	var z := 0.0
	for k in 4:
		var a := 0.15 - k * 0.012
		box(ci, t, a, a, 9, bc.lightened(k * 0.02), z, false, k == 0)
		for left in [true, false]:
			ci.draw_line(fpt(t, a, a, 0, z + 9, left), fpt(t, a, a, 1, z + 9, left), bc.darkened(0.35), 1.0)
		z += 9
	var top := z
	box(ci, t, 0.13, 0.13, 2, STONE, top, true, false)
	for q in [[-0.12, 0.12], [0.12, 0.12], [0.12, -0.12]]:
		ci.draw_line(P(t, q[0], q[1], top + 2), P(t, q[0], q[1], top + 11), RED.darkened(0.2), 1.6)
	line(ci, [P(t, -0.12, 0.12, top + 5), P(t, 0.12, 0.12, top + 5), P(t, 0.12, -0.12, top + 5)], WOOD, 1.2)
	var wt := P(t, 0.03, 0.05, top + 2)
	ci.draw_line(wt, wt - Vector2(0, 5), Color(0.25, 0.3, 0.45), 2.4)
	ci.draw_circle(wt - Vector2(0, 6.5), 1.4, Color(0.92, 0.78, 0.62))
	roof(ci, t, 0.14, 0.14, top + 11, 9, ROOF_G, "pyramid", true, 0.08, 3.0)
	# 官屋
	var sh := c + iso(0.24, 0.0)
	box(ci, sh, 0.18, 0.14, 9, WALL_W)
	timber(ci, sh, 0.18, 0.14, 0, 9, 2)
	door(ci, sh, 0.18, 0.14, 0.55, 0.3, 7, true, 0, false, WOOD.darkened(0.2))
	roof(ci, sh, 0.18, 0.14, 9, 7, ROOF_G, "gable", true, 0.05, 1.0)
	# 水桶、梯子
	for k in 3:
		var q := P(c, -0.06 + k * 0.1, 0.42)
		box(ci, q, 0.03, 0.03, 4, WOOD_L, 0, true, false)
	var l0 := P(c, 0.42, 0.3)
	ci.draw_line(l0, l0 + Vector2(6, -20), WOOD, 1.2)
	ci.draw_line(l0 + Vector2(4, 0), l0 + Vector2(10, -20), WOOD, 1.2)
	for k in 5:
		var u := (k + 0.5) / 5.0
		ci.draw_line(l0 + Vector2(6, -20) * u, l0 + Vector2(4, 0) + Vector2(6, -20) * u, WOOD, 1.0)


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
	# 塌房：長而低的貨棧，大門敞開見貨，門前堆麻袋、木箱，停一輛太平車
	var p := c + iso(-0.08, -0.14)
	shadow(ci, p, 0.42, 0.22, 22)
	box(ci, p, 0.45, 0.25, 4, STONE, 0, true, false)
	box(ci, p, 0.42, 0.22, 9, WOOD_L, 4, false, false)
	timber(ci, p, 0.42, 0.22, 4, 9, 5)
	for u in [0.22, 0.58]:
		frect(ci, p, 0.42, 0.22, u, u + 0.2, 4, 12, Color(0.18, 0.13, 0.1), true)
		for k in 3:
			ell(ci, fpt(p, 0.42, 0.22, u + 0.05 + k * 0.05, 6, true), 2.0, 1.6, Color(0.82, 0.76, 0.6))
	roof(ci, p, 0.42, 0.22, 13, 9, ROOF_G, "gable", true, 0.07, 1.0)
	for k in 4:
		ell(ci, P(c, -0.34 + k * 0.08, 0.38) + Vector2(0, -2.5), 3.2, 2.6, Color(0.86, 0.8, 0.64))
	ell(ci, P(c, -0.3, 0.38) + Vector2(2, -6), 3.2, 2.4, Color(0.88, 0.82, 0.66))
	box(ci, c + iso(0.06, 0.4), 0.06, 0.06, 5, WOOD_L, 0, true, false)
	box(ci, c + iso(0.06, 0.4), 0.05, 0.05, 4, WOOD_L.lightened(0.1), 5, true, false)
	# 太平車
	var cp := c + iso(0.36, 0.22)
	box(ci, cp, 0.12, 0.06, 3, WOOD, 4, true, false)
	for s in [-1.0, 1.0]:
		ell(ci, P(cp, s * 0.07, 0.07, 3), 1.6, 3.2, WOOD.darkened(0.3))
	ci.draw_line(P(cp, -0.12, 0, 6), P(cp, -0.3, 0.02, 4), WOOD, 1.2)


static func lumber(ci, c: Vector2, v: int) -> void:
	# 鋸木場：敞棚、鋸架上架著原木與大鋸，木料成堆
	var sh := c + iso(-0.22, -0.2)
	for q in [[-0.18, 0.13], [0.18, 0.13], [0.18, -0.13], [-0.18, -0.13]]:
		ci.draw_line(P(sh, q[0], q[1]), P(sh, q[0], q[1], 11), WOOD.darkened(0.2), 1.6)
	roof(ci, sh, 0.18, 0.13, 11, 6, ROOF_T, "gable", true, 0.05, 0.5)
	box(ci, sh + iso(-0.05, -0.02), 0.12, 0.08, 3, WOOD_L, 0, true, false)
	var sp := P(c, 0.1, 0.18)
	for s in [-1.0, 1.0]:
		ci.draw_line(sp + Vector2(s * 9 - 3, 0), sp + Vector2(s * 9, -7), WOOD.darkened(0.3), 1.4)
		ci.draw_line(sp + Vector2(s * 9 + 3, 0), sp + Vector2(s * 9, -7), WOOD.darkened(0.3), 1.4)
	poly(ci, [sp + Vector2(-14, -7), sp + Vector2(14, -10), sp + Vector2(14, -13), sp + Vector2(-14, -10)], WOOD_L)
	ell(ci, sp + Vector2(14, -11.5), 1.6, 1.6, Color(0.8, 0.65, 0.4))
	ci.draw_line(sp + Vector2(2, -22), sp + Vector2(4, -4), Color(0.5, 0.5, 0.52), 1.2)
	ci.draw_line(sp + Vector2(-1, -22), sp + Vector2(5, -22), WOOD, 2.0)
	for k in 2:
		_logs(ci, P(c, 0.28 + k * 0.1, -0.12 - k * 0.12))
	for k in 3:
		box(ci, c + iso(-0.28 + k * 0.03, 0.34), 0.16, 0.025, 2 + k * 2, WOOD_L.lightened(0.08), 0, true, false)
	tree_pine(ci, P(c, 0.4, -0.38), 0.85)


static func quarry(ci, c: Vector2, v: int) -> void:
	for k in 3:
		var p := c + iso(-0.25 + k * 0.15, -0.25 + k * 0.15)
		box(ci, p, 0.32 - k * 0.06, 0.32 - k * 0.06, 12 - k * 4, STONE.lightened(k * 0.06), 0, true)
	# 桔槔吊石
	var bp := P(c, 0.32, 0.3)
	ci.draw_line(bp, bp - Vector2(0, 18), WOOD.darkened(0.25), 2.0)
	var piv := bp - Vector2(0, 17)
	ci.draw_line(piv + Vector2(-16, -8), piv + Vector2(10, 5), WOOD, 1.6)
	ci.draw_line(piv + Vector2(-16, -8), piv + Vector2(-16, 2), INK, 0.8)
	box(ci, P(c, 0.32, 0.3) + Vector2(-16, 4), 0.04, 0.04, 3, STONE.lightened(0.15), 0, true, false)
	for q in [[0.42, 0.06], [0.1, 0.42]]:
		box(ci, c + iso(q[0], q[1]), 0.05, 0.05, 4, STONE.lightened(0.15), 0, true)


static func mine(ci, c: Vector2, v: int) -> void:
	var p := P(c, 0.05, 0.25)
	poly(ci, [p + Vector2(-7, 0), p + Vector2(-7, -9), p + Vector2(0, -13), p + Vector2(7, -9), p + Vector2(7, 0)], Color(0.1, 0.08, 0.07))
	ci.draw_line(p + Vector2(-8, 0), p + Vector2(-8, -12), WOOD, 2.0)
	ci.draw_line(p + Vector2(8, 0), p + Vector2(8, -12), WOOD, 2.0)
	ci.draw_line(p + Vector2(-10, -12), p + Vector2(10, -12), WOOD, 2.5)
	var cp := P(c, 0.35, 0.3)
	box(ci, cp, 0.07, 0.05, 4, WOOD, 2)
	ci.draw_circle(P(cp, 0, 0, 7), 2.5, Color(0.3, 0.3, 0.35))
	# 冶鐵爐：磚砌圓爐，爐口火光
	var fp := P(c, -0.3, 0.22)
	var fc := Color(0.55, 0.4, 0.32)
	poly(ci, [fp + Vector2(-7, 0), fp + Vector2(7, 0), fp + Vector2(4.5, -20), fp + Vector2(-4.5, -20)], fc)
	poly(ci, [fp + Vector2(0, 0), fp + Vector2(7, 0), fp + Vector2(4.5, -20), fp + Vector2(0, -20)], fc.lightened(0.08))
	ell(ci, fp + Vector2(0, -20), 4.5, 1.8, Color(0.25, 0.15, 0.1))
	ell(ci, fp + Vector2(0, -20.5), 3.0, 1.0, Color(1.0, 0.55, 0.2))
	ell(ci, fp + Vector2(0, -4), 2.6, 2.6, Color(1.0, 0.6, 0.2))
	_smoke(ci, fp + Vector2(0, -24), v)


static func mulberry(ci, c: Vector2, v: int) -> void:
	# 蠶室：屋旁竹架上疊放蠶匾
	var hp := c + iso(-0.3, -0.3)
	box(ci, hp, 0.14, 0.11, 9, WALL_W)
	roof(ci, hp, 0.14, 0.11, 9, 7, ROOF_G, "gable", true, 0.04, 0.8)
	var rp := P(c, -0.1, -0.36)
	for s in [-1.0, 1.0]:
		ci.draw_line(rp + Vector2(s * 6, 0), rp + Vector2(s * 6, -14), WOOD, 1.2)
	for k in 3:
		ell(ci, rp + Vector2(0, -3 - k * 4.5), 7.0, 2.2, Color(0.8, 0.7, 0.48))
		ell(ci, rp + Vector2(0, -3.6 - k * 4.5), 5.0, 1.3, Color(0.92, 0.9, 0.84))
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
	# 罾：岸邊立竿，以槓桿吊起方形大網；旁有小棚與曬魚架
	var p := c + iso(-0.22, -0.18)
	box(ci, p, 0.14, 0.11, 8, WOOD_L)
	roof(ci, p, 0.14, 0.11, 8, 6, ROOF_T, "gable", true, 0.04, 0.6)
	var bp := P(c, 0.1, 0.1)
	ci.draw_line(bp, bp - Vector2(0, 14), WOOD.darkened(0.3), 2.0)
	var piv := bp - Vector2(0, 13)
	var tip := piv + Vector2(22, -6)
	ci.draw_line(piv + Vector2(-8, 5), tip, WOOD, 1.6)
	var nc := tip + Vector2(0, 12)
	ci.draw_line(tip, nc - Vector2(0, 4), INK, 0.8)
	var a := Vector2(12, 0)
	var b := Vector2(0, 5)
	var net := [nc - a, nc - b, nc + a, nc + b]
	poly(ci, net, Color(0.3, 0.32, 0.3, 0.35))
	for k in 5:
		var u := k / 4.0
		ci.draw_line((nc - a).lerp(nc - b, u), (nc + b).lerp(nc + a, u), Color(0.25, 0.25, 0.25, 0.6), 0.8)
		ci.draw_line((nc - a).lerp(nc + b, u), (nc - b).lerp(nc + a, u), Color(0.25, 0.25, 0.25, 0.6), 0.8)
	for q in net:
		ci.draw_line(nc - Vector2(0, 4), q, WOOD.lightened(0.2), 1.0)
	var rp := P(c, -0.34, 0.3)
	ci.draw_line(rp, rp - Vector2(0, 10), WOOD, 1.2)
	ci.draw_line(rp + Vector2(14, -4), rp + Vector2(14, -14), WOOD, 1.2)
	ci.draw_line(rp - Vector2(0, 9), rp + Vector2(14, -13), WOOD, 1.0)
	for k in 4:
		var q := (rp - Vector2(0, 9)).lerp(rp + Vector2(14, -13), (k + 0.5) / 4.0)
		ell(ci, q + Vector2(0, 3), 1.0, 2.6, Color(0.6, 0.65, 0.68))


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
	# 成品瓷器：宋代名窯以青瓷為主（青花是元明以後）
	box(ci, c + iso(0.1, 0.4), 0.18, 0.05, 3, WOOD, 0, true, false)
	for k in 4:
		var q := P(c, -0.02 + k * 0.08, 0.4, 3)
		ell(ci, q - Vector2(0, 2.5), 2.4, 2.6, Color(0.64, 0.79, 0.69) if k % 2 == 0 else Color(0.86, 0.9, 0.86))
		ci.draw_line(q - Vector2(1.2, 4.2), q - Vector2(-0.4, 4.6), Color(1, 1, 1, 0.6), 1.0)
	ell(ci, P(c, -0.3, 0.38) + Vector2(0, -2), 4.0, 2.4, Color(0.8, 0.78, 0.72))

static func station(ci, c: Vector2, v: int) -> void:
	# 驛站：驛館、側旁敞開的馬廄與馬槽，門前黃旗
	var p := c + iso(-0.16, -0.14)
	shadow(ci, p, 0.24, 0.2, 26)
	box(ci, p, 0.27, 0.23, 3, STONE, 0, true, false)
	box(ci, p, 0.24, 0.2, 10, WALL_W, 3, false, false)
	timber(ci, p, 0.24, 0.2, 3, 10, 3)
	door(ci, p, 0.24, 0.2, 0.5, 0.3, 8, true, 3, false, WOOD.darkened(0.2))
	roof(ci, p, 0.24, 0.2, 13, 11, ROOF_G, "gable", true, 0.08, 3.0)
	# 馬廄
	var st := c + iso(0.26, 0.04)
	for q in [[-0.16, 0.12], [0.16, 0.12], [0.16, -0.12], [-0.16, -0.12]]:
		ci.draw_line(P(st, q[0], q[1]), P(st, q[0], q[1], 10), WOOD.darkened(0.2), 1.5)
	box(ci, st + iso(0.0, -0.1), 0.16, 0.02, 6, WOOD, 0, false, false)
	roof(ci, st, 0.17, 0.13, 10, 4, ROOF_T, "gable", true, 0.03, 0.2)
	box(ci, st + iso(0.02, 0.22), 0.12, 0.03, 2.5, WOOD_L, 0, true, false)
	for k in 2:
		var hc: Color = [Color(0.45, 0.3, 0.2), Color(0.85, 0.82, 0.75), Color(0.25, 0.2, 0.18)][(v + k) % 3]
		_horse(ci, P(st, -0.1 + k * 0.17, 0.3), hc)
	var fp := P(c, 0.02, 0.42)
	ci.draw_line(fp, fp - Vector2(0, 32), INK, 1.5)
	poly(ci, [fp - Vector2(0, 32), fp - Vector2(-13, 30), fp - Vector2(-13, 20), fp - Vector2(0, 22)], Color(0.92, 0.75, 0.25))
	label(ci, fp - Vector2(-6.5, 26), "驛", 9, RED.darkened(0.3))


static func dock(ci, c: Vector2, v: int, wdir: Vector2i) -> void:
	# 碼頭：伸入水中的木棧橋，旁泊小船，岸上小貨棚與吊杆
	var d := Vector2(wdir)
	var ax := wdir.x != 0
	var pc := c + iso(d.x * 0.45, d.y * 0.45)
	var a := 0.55 if ax else 0.18
	var b := 0.18 if ax else 0.55
	for u in [-1.0, 1.0]:
		for w in [-1.0, 1.0]:
			ci.draw_line(P(pc, a * u * 0.8, b * w * 0.8), P(pc, a * u * 0.8, b * w * 0.8, -6), WOOD.darkened(0.3), 2.0)
	box(ci, pc, a, b, 3, WOOD_L, 0, true)
	for k in 5:
		var t := -0.8 + k * 0.4
		var p0 := P(pc, a * t, -b, 3) if ax else P(pc, -a, b * t, 3)
		var p1 := P(pc, a * t, b, 3) if ax else P(pc, a, b * t, 3)
		ci.draw_line(p0, p1, WOOD.darkened(0.15), 1.0)
	_boat(ci, P(pc, 0.0 if ax else 0.36, 0.36 if ax else 0.0, 1), ax)
	for k in 2:
		ell(ci, P(pc, (k * 0.1 - 0.05) if ax else 0.05, 0.05 if ax else (k * 0.1 - 0.05), 3) + Vector2(0, -2.5), 3.0, 2.4, Color(0.85, 0.8, 0.64))
	var hp := c + iso(-d.x * 0.2 - 0.05, -d.y * 0.2 - 0.05)
	box(ci, hp, 0.16, 0.13, 9, WOOD_L)
	timber(ci, hp, 0.16, 0.13, 0, 9, 2)
	roof(ci, hp, 0.16, 0.13, 9, 7, ROOF_T, "gable", ax, 0.05, 0.8)
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
	roof(ci, g, 0.22, 0.1, 27, 10, ROOF_G, "xieshan", true, 0.08, 4.0)
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
		roof(ci, c, a * 0.85, b * 0.85, 29, 10, ROOF_G, "xieshan", not road_ax_x, 0.08, 3.5)
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


## 平橋。high：架在通航水面上，改為高腳木橋，橋面抬到 14 像素，船可從橋下過（橋面高度須與 world_view.gd 的 deck_at() 一致）。
static func bridge(ci, c: Vector2, ax_x: bool, stone: bool, ramp_neg: bool = false, ramp_pos: bool = false, high: bool = false) -> void:
	var col := STONE.lightened(0.05) if stone else WOOD_L
	var a := 0.5 if ax_x else 0.22
	var b := 0.22 if ax_x else 0.5
	var top := 14.0 if high else 7.0
	# 臨岸一端加斜板，接到岸上路面
	var f := func(u: float, w: float, h: float) -> Vector2:
		return P(c, u, w, h) if ax_x else P(c, w, u, h)
	for e in [[ramp_neg, -1.0], [ramp_pos, 1.0]]:
		if not e[0]:
			continue
		var sg: float = e[1]
		poly(ci, [f.call(0.5 * sg, -0.22, top), f.call(0.82 * sg, -0.22, 0), f.call(0.82 * sg, 0.22, 0), f.call(0.5 * sg, 0.22, top)], col.darkened(0.05))
		poly(ci, [f.call(0.5 * sg, 0.22, top), f.call(0.82 * sg, 0.22, 0), f.call(0.82 * sg, 0.22, -2), f.call(0.5 * sg, 0.22, top - 3)], col.darkened(0.3))
	# 橋柱：高腳橋每格兩對，柱下加一道斜撐
	for u in [-0.3, 0.3]:
		for w in ([-0.18, 0.18] if high else [0.0]):
			var q := P(c, u, w) if ax_x else P(c, w, u)
			ci.draw_line(q + Vector2(0, 2), q - Vector2(0, top - 2), col.darkened(0.35), 2.4 if high else 3.0)
	if high:
		for w in [-0.18, 0.18]:
			var q0 := P(c, -0.3, w, 1) if ax_x else P(c, w, -0.3, 1)
			var q1 := P(c, 0.3, w, top - 4) if ax_x else P(c, w, 0.3, top - 4)
			ci.draw_line(q0, q1, col.darkened(0.4), 1.2)
	box(ci, c, a, b, 3, col, top - 3, true)
	var r0 := P(c, -a, b, top + 2) if ax_x else P(c, a, -b, top + 2)
	var r1 := P(c, a, b, top + 2)
	line(ci, [r0, r1], col.darkened(0.3), 1.5)
	for k in 5:
		var q := r0.lerp(r1, k / 4.0)
		ci.draw_line(q, q + Vector2(0, 3), col.darkened(0.3), 1.0)


## 石拱橋：江南常見的駝峰石橋，整段一次畫成。c 為最前一格的中心，n 為跨水格數。
## 跨三格以內一孔，四到六格三孔，再長五孔；拱洞與水中倒影合成一圈。
static func stone_arch(ci, c: Vector2, ax_x: bool, n: int, v: int) -> void:
	var f := func(u: float, w: float, h: float) -> Vector2:
		return P(c, u, w, h) if ax_x else P(c, w, u, h)
	var u0 := -(n - 1) - 0.5 - 0.34
	var u1 := 0.5 + 0.34
	var span := u1 - u0
	var H := clampf(8.0 + n * 6.0, 16.0, 36.0)
	var deck := func(u: float) -> float:
		var t := clampf((u - u0) / span, 0.0, 1.0)
		return H * pow(sin(PI * t), 0.75)
	var wd := 0.26
	var stone := STONE.lightened(0.04)
	var face := STONE.darkened(0.1)
	var steps := 8 * n + 10
	var us := []
	for j in steps + 1:
		us.append(lerpf(u0, u1, float(j) / steps))
	# 兩岸金剛牆
	for e in [u0 + 0.14, u1 - 0.14]:
		var bc: Vector2 = f.call(e, 0.0, 0.0)
		box(ci, bc, 0.15 if ax_x else wd + 0.04, wd + 0.04 if ax_x else 0.15, 3, face, -1.0, true, false)
	# 遠側欄板
	var far := []
	for u in us:
		far.append(f.call(u, -wd, deck.call(u) + 5.0))
	line(ci, far, stone.darkened(0.3), 1.2)
	for j in range(0, us.size(), 3):
		ci.draw_line(f.call(us[j], -wd, deck.call(us[j])), far[j], stone.darkened(0.3), 1.0)
	# 橋面（踏步）
	var top := []
	for u in us:
		top.append(f.call(u, -wd, deck.call(u)))
	for j in range(us.size() - 1, -1, -1):
		top.append(f.call(us[j], wd, deck.call(us[j])))
	var tcol := snowy(stone.lightened(0.08), 0.6)
	poly(ci, top, tcol)
	for j in range(1, steps, 2):
		ci.draw_line(f.call(us[j], -wd, deck.call(us[j])), f.call(us[j], wd, deck.call(us[j])), tcol.darkened(0.14), 1.0)
	# 近側橋身：橋面到水面
	var body := []
	for u in us:
		body.append(f.call(u, wd, deck.call(u)))
	body.append(f.call(u1, wd, -1.0))
	body.append(f.call(u0, wd, -1.0))
	poly(ci, body, face)
	# 拱洞與倒影
	var holes := 1 if n <= 3 else (3 if n <= 6 else 5)
	var main_r := minf(span * 0.26, 1.2) if holes == 1 else span / (holes * 2.6)
	for k in holes:
		var off := float(k - (holes - 1) * 0.5)
		var uc := (u0 + u1) * 0.5 + off * span / (holes + 0.6)
		var rr: float = main_r * (1.0 if k == (holes - 1) / 2 else 0.72)
		var rh: float = minf(H * 0.78, rr * 26.0) * (1.0 if k == (holes - 1) / 2 else 0.8)
		var hole := []
		var ring := []
		var refl := []
		for a in 13:
			var th := PI * a / 12.0
			hole.append(f.call(uc + cos(th) * rr, wd, sin(th) * rh))
			ring.append(f.call(uc + cos(th) * (rr + 0.06), wd, sin(th) * (rh + 3.0)))
			refl.append(f.call(uc + cos(th) * rr, wd, -sin(th) * rh * 0.8))
		poly(ci, hole, Color(0.16, 0.2, 0.21))
		poly(ci, refl, Color(0.16, 0.22, 0.24, 0.35))
		line(ci, ring, stone.darkened(0.32), 1.4)
		# 拱石縫
		for a in range(1, 12, 2):
			var th := PI * a / 12.0
			ci.draw_line(f.call(uc + cos(th) * rr, wd, sin(th) * rh), f.call(uc + cos(th) * (rr + 0.06), wd, sin(th) * (rh + 3.0)), stone.darkened(0.3), 1.0)
	# 近側欄板：望柱加扶手
	var near := []
	for u in us:
		near.append(f.call(u, wd, deck.call(u) + 5.5))
	for j in range(0, us.size(), 3):
		ci.draw_line(f.call(us[j], wd, deck.call(us[j])), f.call(us[j], wd, deck.call(us[j]) + 7.0), stone.darkened(0.35), 1.6)
	line(ci, near, stone.darkened(0.28), 1.6)
	line(ci, body.slice(0, us.size()), stone.darkened(0.4), 1.2)


## 虹橋：整段一次畫成。c 為最前（最近觀者）一格的中心，n 為跨水格數。
## 仿《清明上河圖》木構疊梁拱：兩岸石砌橋臺，橋面由岸邊緩起成一道弧，
## 橋下兩套長短不同的直梁交錯成拱，橋上兩側有傘下攤販與行人。
static func rainbow_bridge(ci, c: Vector2, ax_x: bool, n: int, v: int) -> void:
	var f := func(u: float, w: float, h: float) -> Vector2:
		return P(c, u, w, h) if ax_x else P(c, w, u, h)
	var u0 := -(n - 1) - 0.5 - 0.32
	var u1 := 0.5 + 0.32
	var span := u1 - u0
	var H := clampf(9.0 + n * 4.5, 14.0, 30.0)
	var deck := func(u: float) -> float:
		return H * sin(PI * clampf((u - u0) / span, 0.0, 1.0))
	var wd := 0.27
	var wood := Color(0.55, 0.37, 0.22)
	var dark := wood.darkened(0.42)
	var steps := 10 * n + 10
	var us := []
	for j in steps + 1:
		us.append(lerpf(u0, u1, float(j) / steps))
	# 兩岸橋臺
	for e in [u0 + 0.16, u1 - 0.16]:
		var bc: Vector2 = f.call(e, 0.0, 0.0)
		box(ci, bc, 0.16 if ax_x else wd + 0.05, wd + 0.05 if ax_x else 0.16, 4, STONE, -1.5, true, false)
	# 遠側拱梁與欄杆
	_rainbow_ribs(ci, f, us, u0, span, -wd, deck, dark.darkened(0.15), 1.0)
	var far := []
	for u in us:
		far.append(f.call(u, -wd, deck.call(u) + 6.0))
	for j in range(0, us.size(), 4):
		ci.draw_line(f.call(us[j], -wd, deck.call(us[j])), far[j], wood.darkened(0.35), 1.0)
	line(ci, far, wood.darkened(0.3), 1.3)
	# 橋面與橫鋪木板
	var dcol := snowy(WOOD_L.lightened(0.06), 0.6)
	var top := []
	for u in us:
		top.append(f.call(u, -wd, deck.call(u)))
	for j in range(steps, -1, -1):
		top.append(f.call(us[j], wd, deck.call(us[j])))
	poly(ci, top, dcol)
	for j in range(2, steps - 1, 2):
		ci.draw_line(f.call(us[j], -wd, deck.call(us[j])), f.call(us[j], wd, deck.call(us[j])), dcol.darkened(0.12), 1.0)
	# 橋上攤販與行人（靠遠側，不擋欄杆）
	if n >= 2:
		var cols := [Color(0.93, 0.88, 0.74), RED, Color(0.35, 0.5, 0.62)]
		for k in 2:
			var su := lerpf(u0, u1, 0.24 + k * 0.52)
			var sp: Vector2 = f.call(su, -0.1, deck.call(su))
			ci.draw_rect(Rect2(sp - Vector2(4, 3), Vector2(8, 3)), wood.darkened(0.2))
			_parasol(ci, sp, 11, 7, cols[(v + k) % cols.size()])
		var people := [Color(0.3, 0.35, 0.5), Color(0.55, 0.3, 0.25), Color(0.4, 0.45, 0.35), Color(0.75, 0.72, 0.65)]
		for k in mini(2 + n, 6):
			var pu := lerpf(u0, u1, 0.12 + (k * 0.37 + v * 0.11 - floorf(k * 0.37 + v * 0.11)) * 0.76)
			var pp: Vector2 = f.call(pu, 0.06 if k % 2 == 0 else -0.04, deck.call(pu))
			ci.draw_line(pp, pp - Vector2(0, 5), people[(k + v) % people.size()], 2.2)
			ci.draw_circle(pp - Vector2(0, 6.4), 1.3, Color(0.85, 0.72, 0.58))
	# 近側橋面厚度
	var side := []
	for u in us:
		side.append(f.call(u, wd, deck.call(u)))
	for j in range(steps, -1, -1):
		side.append(f.call(us[j], wd, deck.call(us[j]) - 3.0))
	poly(ci, side, wood.darkened(0.15))
	# 近側拱梁
	_rainbow_ribs(ci, f, us, u0, span, wd, deck, dark, 1.0)
	# 近側欄杆
	var near := []
	for u in us:
		near.append(f.call(u, wd, deck.call(u) + 6.0))
	for j in range(0, us.size(), 4):
		ci.draw_line(f.call(us[j], wd, deck.call(us[j])), near[j], wood.darkened(0.35), 1.2)
	line(ci, near, wood.darkened(0.32), 1.6)
	var mid := []
	for u in us:
		mid.append(f.call(u, wd, deck.call(u) + 3.0))
	line(ci, mid, wood.darkened(0.2), 1.0)


## 虹橋拱梁：一套三節、一套四節的直梁交錯成拱，梁頭以橫木相扣，再以短柱撐住橋面。
static func _rainbow_ribs(ci, f: Callable, us: Array, u0: float, span: float, w: float, deck: Callable, col: Color, k: float) -> void:
	var a0 := u0 + span * 0.1
	var a1 := u0 + span * 0.9
	var sets := [[0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0], [0.0, 0.25, 0.5, 0.75, 1.0]]
	for si in sets.size():
		var pts := []
		for t in sets[si]:
			var u := lerpf(a0, a1, t)
			var h := -1.0
			if t > 0.0 and t < 1.0:
				h = deck.call(u) - (6.0 if si == 0 else 9.0)
			pts.append(f.call(u, w, h))
		line(ci, pts, col, 2.6)
		for j in range(1, pts.size() - 1):
			ci.draw_circle(pts[j], 1.8, col.darkened(0.2))
	for j in range(2, us.size() - 2, 3):
		var u: float = us[j]
		var t := (u - a0) / (a1 - a0)
		if t <= 0.05 or t >= 0.95:
			continue
		ci.draw_line(f.call(u, w, deck.call(u) - 3.0), f.call(u, w, deck.call(u) - 7.0), col.lightened(0.15), 1.0)


## 格局成立後加在建築上的點綴。
static func combo_deco(ci, kind: String, c: Vector2, size: int, v: int, btype: String = "", quad: int = -1) -> void:
	match kind:
		"wazi":
			# 簷下張掛成串燈籠與彩旗
			var a := 0.42 * size
			var hgt := 19.0
			var corners := [P(c, -a, a, hgt), P(c, a, a, hgt), P(c, a, -a, hgt)]
			for e in 2:
				var p0: Vector2 = corners[e]
				var p1: Vector2 = corners[e + 1]
				var pts := []
				for j in 9:
					var t := j / 8.0
					pts.append(p0.lerp(p1, t) + Vector2(0, sin(t * PI) * 4.0))
				line(ci, pts, INK, 0.8)
				for j in range(1, 8, 2):
					var q: Vector2 = pts[j]
					ell(ci, q + Vector2(0, 2.4), 1.7, 2.1, Color(0.95, 0.25, 0.12))
					ci.draw_line(q + Vector2(-1, 0.6), q + Vector2(1, 0.6), GOLD, 0.8)
				for j in range(2, 8, 2):
					var q: Vector2 = pts[j]
					poly(ci, [q, q + Vector2(3, 0.5), q + Vector2(0.5, 4)], [GOLD, Color(0.3, 0.55, 0.4), Color(0.3, 0.45, 0.7)][(j / 2 + v) % 3])
		"caoyun":
			# 多泊一艘漕船，岸上堆糧袋，立「漕」字旗
			_boat(ci, P(c, 0.75, 0.55), true)
			for j in 5:
				ell(ci, P(c, -0.3 + (j % 3) * 0.09, 0.42) + Vector2(0, -2.5 - (j / 3) * 3.5), 3.0, 2.4, Color(0.86, 0.78, 0.55))
			var fp := P(c, -0.42, 0.1)
			ci.draw_line(fp, fp - Vector2(0, 34), INK, 1.5)
			poly(ci, [fp - Vector2(0, 34), fp - Vector2(-12, 32), fp - Vector2(-12, 22), fp - Vector2(0, 24)], RED)
			label(ci, fp - Vector2(-6, 28), "漕", 8, Color(0.98, 0.92, 0.8))
		"siheyuan":
			# 院牆只畫看得見的前側兩面；左前一座開門樓，後方一座在院心種樹
			var rx := quad % 2
			var ry := quad / 2
			var wc := Color(0.93, 0.91, 0.86)
			if quad == 0:
				tree_round(ci, P(c, 0.5, 0.5), 0.95, v)
			if rx == 1:
				box(ci, c + iso(0.47, 0), 0.03, 0.5, 8, wc, 0, true, false)
				roof(ci, c + iso(0.47, 0), 0.03, 0.5, 8, 2.5, ROOF_G, "gable", false, 0.02, 0.0)
			if ry == 1:
				box(ci, c + iso(0, 0.47), 0.5, 0.03, 8, wc, 0, true, false)
				roof(ci, c + iso(0, 0.47), 0.5, 0.03, 8, 2.5, ROOF_G, "gable", true, 0.02, 0.0)
			if quad == 2:
				var g := c + iso(0.12, 0.47)
				box(ci, g, 0.13, 0.06, 13, wc)
				face_l(ci, g, 0.13, 0.06, 0.25, 0.75, 0, 9, RED.darkened(0.15))
				roof(ci, g, 0.15, 0.08, 13, 6, ROOF_G, "gable", true, 0.04, 1.5)
				lantern(ci, P(g, -0.1, 0.1, 13))
				lantern(ci, P(g, 0.1, 0.1, 13))
		"fansha":
			if btype == "temple":
				# 殿前香爐煙起，門外兩竿經幡
				for k in 2:
					var bp := P(c, 1.02, 0.55) if k == 0 else P(c, 0.55, 1.02)
					ci.draw_line(bp, bp - Vector2(0, 46), WOOD.darkened(0.35), 1.6)
					var col: Color = [Color(0.92, 0.75, 0.25), RED][k]
					poly(ci, [bp - Vector2(0, 45), bp + Vector2(5, -45), bp + Vector2(6, -14), bp + Vector2(2.5, -17), bp + Vector2(0, -14)], col)
			elif btype == "pagoda":
				# 每層簷角掛風鈴
				var z := 4.0
				for k in 7:
					var a := 0.3 - k * 0.028
					z += 11.0 - k * 0.7
					for q in [P(c, a + 0.09, a + 0.09, z), P(c, -a - 0.09, a + 0.09, z), P(c, a + 0.09, -a - 0.09, z)]:
						ci.draw_line(q, q + Vector2(0, 2.5), INK, 0.8)
						ci.draw_circle(q + Vector2(0, 3.5), 1.2, GOLD)
					z += 2.0
		"yashu":
			if btype == "yamen":
				# 門前照壁、兩根旗杆
				var sw := c + iso(0, 1.5)
				box(ci, sw, 0.42, 0.05, 14, RED.darkened(0.15))
				roof(ci, sw, 0.44, 0.07, 14, 5, ROOF_G, "hip", true, 0.03, 1.5)
				var fc := fpt(sw, 0.42, 0.05, 0.5, 7.5, true)
				ell(ci, fc, 5.0, 3.6, GOLD.darkened(0.1))
				ell(ci, fc, 3.2, 2.2, RED.darkened(0.2))
				for sgn in [-1.0, 1.0]:
					var bp := P(c, sgn * 0.62, 1.12)
					ci.draw_line(bp, bp - Vector2(0, 50), INK, 1.6)
					ci.draw_line(bp - Vector2(3, 34), bp - Vector2(-3, 34), INK, 1.2)
					poly(ci, [bp - Vector2(0, 49), bp + Vector2(6, -49), bp + Vector2(6, -24), bp + Vector2(0, -27)], RED)
			elif btype == "archway":
				# 坊頂紮紅綢彩球
				var t := P(c, 0, 0, 41)
				ci.draw_circle(t, 4.2, Color(0.88, 0.16, 0.12))
				ci.draw_circle(t + Vector2(-1.2, -1.2), 1.6, Color(1.0, 0.45, 0.35))
				for sgn in [-1.0, 1.0]:
					line(ci, [t + Vector2(sgn * 3, 1), t + Vector2(sgn * 10, 5), t + Vector2(sgn * 14, 12)], Color(0.88, 0.16, 0.12), 1.6)
		"sangji":
			if btype == "mulberry":
				# 龍骨水車：斜槽與踏輪
				var wp := P(c, 0.42, 0.4)
				line(ci, [wp, wp + Vector2(-14, -8)], WOOD, 2.2)
				for k in 5:
					var q := wp.lerp(wp + Vector2(-14, -8), k / 4.0)
					ci.draw_line(q, q + Vector2(0, -2.5), WOOD.darkened(0.3), 1.0)
				var wc2 := wp + Vector2(-15, -11)
				var ring := []
				for k in 13:
					ring.append(wc2 + Vector2(cos(k * TAU / 12), sin(k * TAU / 12)) * 4.0)
				line(ci, ring, WOOD.darkened(0.3), 1.4)
				for k in 4:
					var ang := k * PI / 4
					ci.draw_line(wc2 - Vector2(cos(ang), sin(ang)) * 4, wc2 + Vector2(cos(ang), sin(ang)) * 4, WOOD.darkened(0.3), 1.0)
		"chama":
			if btype == "station":
				# 馱茶馬隊，紅旗書「茶」
				for k in 3:
					var hp := P(c, 0.05 + k * 0.17, 0.5)
					var hc: Color = [Color(0.45, 0.3, 0.2), Color(0.3, 0.22, 0.17), Color(0.6, 0.45, 0.3)][k]
					_horse(ci, hp, hc)
					ci.draw_rect(Rect2(hp + Vector2(-3, -11), Vector2(7, 4)), Color(0.35, 0.5, 0.3))
					ci.draw_rect(Rect2(hp + Vector2(-3, -11), Vector2(7, 4)), Color(0.2, 0.3, 0.18), false, 0.8)
				var fp := P(c, -0.45, 0.45)
				ci.draw_line(fp, fp - Vector2(0, 30), INK, 1.5)
				poly(ci, [fp - Vector2(0, 30), fp - Vector2(-12, 28), fp - Vector2(-12, 18), fp - Vector2(0, 20)], RED)
				label(ci, fp - Vector2(-6, 24), "茶", 8, Color(0.98, 0.92, 0.8))
			elif btype == "tea":
				for k in 3:
					var q := P(c, -0.2 + k * 0.2, 0.42)
					ell(ci, q + Vector2(0, -3), 3.0, 3.4, Color(0.62, 0.45, 0.25))
					ell(ci, q + Vector2(0, -6), 2.6, 1.2, Color(0.35, 0.55, 0.3))
		"guanyao":
			if btype == "kiln":
				# 窯煙兩柱、成品架、黃旗書「官」
				for col in [Vector2(0.47, -0.12), Vector2(0.1, -0.1)]:
					var sp := P(c, col.x, col.y, 32 if col.x > 0.3 else 18)
					for k in 6:
						ell(ci, sp + Vector2(k * 2.0, -k * 7.0), 3.0 + k, 2.4 + k * 0.7, Color(0.75, 0.75, 0.75, 0.5 - k * 0.07))
				box(ci, c + iso(-0.3, 0.45), 0.16, 0.05, 3, WOOD, 0, true, false)
				for k in 4:
					var q := P(c, -0.42 + k * 0.08, 0.45, 3)
					ell(ci, q - Vector2(0, 3), 2.2, 3.0, Color(0.64, 0.79, 0.69) if k % 2 == 0 else Color(0.86, 0.9, 0.86))
					ci.draw_line(q - Vector2(1.0, 4.8), q - Vector2(-0.4, 5.2), Color(1, 1, 1, 0.6), 1.0)
				var fp := P(c, -0.5, -0.1)
				ci.draw_line(fp, fp - Vector2(0, 34), INK, 1.5)
				poly(ci, [fp - Vector2(0, 34), fp - Vector2(-12, 32), fp - Vector2(-12, 22), fp - Vector2(0, 24)], Color(0.92, 0.75, 0.25))
				label(ci, fp - Vector2(-6, 28), "官", 8, RED.darkened(0.2))
			elif btype == "quarry":
				for k in 4:
					box(ci, c + iso(0.25 + (k % 2) * 0.1, 0.4 - (k / 2) * 0.1), 0.04, 0.04, 3.5, Color(0.95, 0.94, 0.9), (k / 2) * 3.5, true, false)


## 相鄰同類建築之間的連接：民居以粉牆相連成院，市肆以廊棚相連成街。d 指向鄰格。
static func link(ci, c: Vector2, d: Vector2i, type: String, lvl: int) -> void:
	var ax := d.x != 0
	var m := c + iso(d.x * 0.5, d.y * 0.5)
	if type == "house":
		var wc := WALL_W if lvl >= 2 else WALL_M
		var fr := m + (iso(0, 0.26) if ax else iso(0.26, 0))
		var a := 0.2 if ax else 0.025
		var b := 0.025 if ax else 0.2
		box(ci, fr, a, b, 7, wc, 0, true, false)
		roof(ci, fr, a, b, 7, 2.5, ROOF_G if lvl >= 2 else ROOF_T, "gable", ax, 0.02, 0.0)
	else:
		var fr := m + (iso(0, 0.2) if ax else iso(0.2, 0))
		var a := 0.22 if ax else 0.12
		var b := 0.12 if ax else 0.22
		for s2 in [-1.0, 1.0]:
			var q := P(fr, (s2 * a * 0.9) if ax else b * 0.8, (b * 0.8) if ax else s2 * a * 0.9)
			ci.draw_line(q, q - Vector2(0, 10), WOOD.darkened(0.25), 1.5)
		roof(ci, fr, a, b, 10, 4, ROOF_G, "gable", ax, 0.03, 0.5)
		for k in 3:
			var q := P(fr, (-0.12 + k * 0.12) if ax else b, b if ax else (-0.12 + k * 0.12), 8)
			lantern(ci, q)


## 格局成立後畫在建築底下的部分（如桑基魚塘的塘）。
static func combo_under(ci, kind: String, c: Vector2, v: int, btype: String = "") -> void:
	if kind == "sangji" and btype == "mulberry":
		for i in 2:
			for j in 2:
				var q := c + iso(-0.18 + i * 0.3, -0.18 + j * 0.3)
				poly(ci, [P(q, 0, -0.1), P(q, 0.1, 0), P(q, 0, 0.1), P(q, -0.1, 0)], WATER.lightened(0.05))
				ci.draw_circle(P(q, 0.02, 0.01) + Vector2(1, 0), 0.9, Color(0.85, 0.5, 0.3))


## 傘：竿、傘面分瓣明暗。
static func _parasol(ci, base: Vector2, h: float, r: float, col: Color) -> void:
	var top := base - Vector2(0, h)
	ci.draw_line(base, top, WOOD.darkened(0.3), 1.4)
	var apex := top - Vector2(0, r * 0.38)
	var n := 12
	var pts := []
	for k in n + 1:
		var t := PI * 2.0 * k / n
		pts.append(top + Vector2(cos(t) * r, sin(t) * r * 0.42))
	for k in n:
		var shade := 0.0 if k % 2 == 0 else 0.1
		if sin(PI * 2.0 * (k + 0.5) / n) < 0:
			shade += 0.2
		poly(ci, [apex, pts[k], pts[k + 1]], col.darkened(shade))
	line(ci, pts.slice(0, n / 2 + 1), col.darkened(0.45), 1.0)
	ci.draw_circle(apex, 1.2, WOOD.darkened(0.3))


static func _huang(ci, p: Vector2, col: Color, ch: String) -> void:
	var tip := p + Vector2(9, -3)
	ci.draw_line(p, tip, WOOD.darkened(0.3), 1.4)
	var r := Rect2(tip + Vector2(-4, 0), Vector2(8, 17))
	poly(ci, [r.position, r.position + Vector2(r.size.x, 0), r.end + Vector2(0.8, 0), r.position + Vector2(-0.4, r.size.y)], col)
	label(ci, r.get_center() + Vector2(0, -2), ch, 8, Color(1.0, 0.97, 0.9))


static func _cailou(ci, p: Vector2, a: float, b: float) -> void:
	var post := Color(0.55, 0.38, 0.22)
	var l := P(p, -a, b + 0.06)
	var rr := P(p, a, b + 0.06)
	var hs := [0.0, 14.0, 24.0, 34.0]
	for q in [l, rr]:
		ci.draw_line(q, q - Vector2(0, 38), post, 2.0)
	for h in hs.slice(1):
		ci.draw_line(l - Vector2(0, h), rr - Vector2(0, h), post, 1.5)
	for k in 2:
		var h0: float = hs[k + 1]
		var h1: float = hs[k + 2]
		for s in 4:
			var u0 := s / 4.0
			var u1 := (s + 1) / 4.0
			ci.draw_line(l.lerp(rr, u0) - Vector2(0, h0), l.lerp(rr, u1) - Vector2(0, h1), post.lightened(0.15), 1.0)
			ci.draw_line(l.lerp(rr, u1) - Vector2(0, h0), l.lerp(rr, u0) - Vector2(0, h1), post.lightened(0.15), 1.0)
	var flags := [RED, Color(0.25, 0.5, 0.35), GOLD, Color(0.3, 0.42, 0.65)]
	for k in 9:
		var q := l.lerp(rr, k / 8.0) - Vector2(0, 38)
		poly(ci, [q, q + Vector2(5, 2), q + Vector2(0, 5)], flags[k % 4])
	for k in 5:
		var q := l.lerp(rr, (k + 0.5) / 5.0) - Vector2(0, 24)
		ci.draw_line(q, q + Vector2(0, 7), flags[(k + 1) % 4], 2.0)


static func _wineflag(ci, base: Vector2, h: float) -> void:
	ci.draw_line(base, base - Vector2(0, h), WOOD.darkened(0.35), 1.8)
	var t := base - Vector2(0, h - 2)
	var pts := [t, t + Vector2(-14, 2), t + Vector2(-15, 24), t + Vector2(-1, 22)]
	poly(ci, pts, Color(0.95, 0.93, 0.86))
	line(ci, pts + [pts[0]], Color(0.25, 0.4, 0.62), 1.5)
	label(ci, t + Vector2(-7.5, 11), "酒", 10, RED.darkened(0.2))


static func _vat(ci, p: Vector2, dye: Color) -> void:
	ell(ci, p + Vector2(0, -3), 4.2, 3.6, Color(0.42, 0.3, 0.22))
	ell(ci, p + Vector2(0, -6.4), 4.0, 1.6, Color(0.25, 0.18, 0.14))
	ell(ci, p + Vector2(0, -6.3), 3.2, 1.1, dye)


static func _dyerack(ci, a: Vector2, b: Vector2, h: float, n: int, v: int) -> void:
	var post := WOOD.darkened(0.2)
	ci.draw_line(a, a - Vector2(0, h), post, 1.8)
	ci.draw_line(b, b - Vector2(0, h), post, 1.8)
	ci.draw_line(a - Vector2(0, h), b - Vector2(0, h), post, 1.5)
	var dyes := [Color(0.2, 0.3, 0.58), Color(0.68, 0.2, 0.17), Color(0.78, 0.62, 0.25), Color(0.32, 0.45, 0.7), Color(0.4, 0.55, 0.38)]
	for k in n:
		var t := (k + 0.6) / (n + 0.2)
		var q := a.lerp(b, t) - Vector2(0, h)
		var w := 4.0
		var ln := h - 5.0 - (k % 2) * 3.0
		var sway := 1.5 if k % 2 == 0 else -1.0
		var col: Color = dyes[(v + k) % dyes.size()]
		poly(ci, [q + Vector2(-w * 0.5, 0), q + Vector2(w * 0.5, 0), q + Vector2(w * 0.5 + sway, ln), q + Vector2(-w * 0.5 + sway, ln)], col)
		ci.draw_line(q + Vector2(w * 0.5, 0), q + Vector2(w * 0.5 + sway, ln), col.darkened(0.25), 1.0)


static func _smoke(ci, p: Vector2, v: int) -> void:
	for k in 3:
		ell(ci, p + Vector2(k * 2.5 + (v % 3), -k * 5.0), 2.8 + k, 2.2 + k * 0.6, Color(0.85, 0.85, 0.85, 0.5 - k * 0.12))


static func constable(ci, c: Vector2, v: int) -> void:
	var p := c + iso(-0.08, -0.08)
	shadow(ci, p, 0.3, 0.24, 28)
	box(ci, p, 0.33, 0.27, 4, STONE.darkened(0.08), 0, true, false)
	box(ci, p, 0.3, 0.24, 10, Color(0.8, 0.78, 0.74), 4, false, false)
	timber(ci, p, 0.3, 0.24, 4, 10, 3, Color(0.12, 0.1, 0.09))
	door(ci, p, 0.3, 0.24, 0.5, 0.26, 9, true, 4, false, Color(0.12, 0.1, 0.09))
	window(ci, p, 0.3, 0.24, 0.32, 0.68, 7, 12, false)
	roof(ci, p, 0.3, 0.24, 14, 12, ROOF_G, "gable", true, 0.08, 1.5)
	for s in [-1.0, 1.0]:
		lantern(ci, P(p, s * 0.18, 0.3, 14))
	# 鼓架
	var dp := P(c, -0.32, 0.36)
	for s in [-1.0, 1.0]:
		ci.draw_line(dp + Vector2(s * 5, 0), dp + Vector2(s * 5, -13), WOOD.darkened(0.3), 1.6)
	ci.draw_line(dp + Vector2(-6, -12), dp + Vector2(6, -12), WOOD.darkened(0.3), 1.6)
	ell(ci, dp + Vector2(0, -8), 4.4, 5.0, RED.darkened(0.05))
	ell(ci, dp + Vector2(1.2, -8), 3.0, 4.0, Color(0.9, 0.82, 0.62))
	# 兵器架：三支長槍，紅纓
	var wp := P(c, 0.36, 0.2)
	ci.draw_line(wp + Vector2(-7, -3), wp + Vector2(7, -3), WOOD.darkened(0.3), 1.6)
	for k in 3:
		var x := -5.0 + k * 5.0
		ci.draw_line(wp + Vector2(x, 0), wp + Vector2(x, -22), WOOD, 1.2)
		poly(ci, [wp + Vector2(x - 1.2, -22), wp + Vector2(x + 1.2, -22), wp + Vector2(x, -26)], Color(0.82, 0.84, 0.86))
		ci.draw_circle(wp + Vector2(x, -21), 1.5, RED)


static func clinic(ci, c: Vector2, v: int) -> void:
	var p := c + iso(-0.1, -0.1)
	shadow(ci, p, 0.28, 0.22, 26)
	box(ci, p, 0.31, 0.25, 3, STONE, 0, true, false)
	box(ci, p, 0.28, 0.22, 10, WALL_W, 3, false, false)
	timber(ci, p, 0.28, 0.22, 3, 10, 3)
	frect(ci, p, 0.28, 0.22, 0.15, 0.85, 3, 10, Color(0.24, 0.17, 0.12), true)
	frect(ci, p, 0.28, 0.22, 0.15, 0.85, 3, 6, WOOD_L, true)
	for k in 5:
		var q := fpt(p, 0.28, 0.22, 0.2 + k * 0.15, 8.5, true)
		box(ci, q, 0.012, 0.012, 2.4, [Color(0.85, 0.82, 0.75), Color(0.55, 0.4, 0.3)][k % 2], 0, true, false)
	window(ci, p, 0.28, 0.22, 0.3, 0.7, 6, 10, false)
	roof(ci, p, 0.28, 0.22, 13, 11, ROOF_G, "gable", true, 0.08, 1.5)
	# 懸壺
	var hk := P(p, 0.32, 0.26, 17)
	ci.draw_line(hk, hk + Vector2(10, -3), WOOD.darkened(0.3), 1.5)
	var g := hk + Vector2(10, 4)
	ci.draw_line(hk + Vector2(10, -3), g - Vector2(0, 4), INK, 0.8)
	ell(ci, g, 2.6, 2.8, Color(0.85, 0.62, 0.22))
	ell(ci, g + Vector2(0, 5.5), 4.0, 4.4, Color(0.88, 0.66, 0.24))
	ell(ci, g + Vector2(-1.2, 4.5), 1.4, 1.8, Color(0.98, 0.85, 0.5))
	ci.draw_line(g + Vector2(-2.6, 1.8), g + Vector2(2.6, 1.8), RED, 1.4)
	# 曬藥竹匾
	for k in 3:
		var tp := P(c, -0.1 + k * 0.17, 0.4 - k * 0.04)
		ci.draw_line(tp, tp - Vector2(0, 3), WOOD, 1.2)
		ell(ci, tp - Vector2(0, 4), 5.5, 2.4, Color(0.78, 0.66, 0.42))
		for j in 4:
			ci.draw_circle(tp - Vector2(3 - j * 2.0, 4.2 - (j % 2)), 0.8, [Color(0.4, 0.5, 0.25), Color(0.55, 0.3, 0.2)][(k + j) % 2])
	_huang(ci, P(p, -0.34, 0.26, 12), Color(0.3, 0.5, 0.38), "藥")


static func school(ci, c: Vector2, v: int) -> void:
	var hp := c + iso(-0.14, -0.16)
	hall(ci, hp, 0.24, 0.18, 12, WALL_W, ROOF_G, "gable", true, 10, false)
	var wc := Color(0.93, 0.91, 0.86)
	var e := 0.44
	box(ci, c + iso(0, e), e, 0.025, 8, wc, 0, true, false)
	box(ci, c + iso(e, 0), 0.025, e, 8, wc, 0, true, false)
	for side in [[c + iso(0, e), true], [c + iso(e, 0), false]]:
		roof(ci, side[0], e if side[1] else 0.025, 0.025 if side[1] else e, 8, 2.5, ROOF_G, "gable", side[1], 0.02, 0.0)
	# 月洞門
	var gc := P(c, -0.08, e + 0.025, 4.2)
	var pts := []
	for k in 17:
		var t := PI * 2 * k / 16.0
		pts.append(gc + Vector2(cos(t) * 4.6, sin(t) * 4.2) + Vector2(cos(t) * 0, 0))
	poly(ci, pts, Color(0.32, 0.36, 0.3))
	line(ci, pts, Color(0.55, 0.52, 0.48), 1.2)
	# 竹
	var bp := P(c, 0.3, 0.28)
	var bc := Color(0.3, 0.55, 0.3) if season != 3 else Color(0.45, 0.55, 0.45)
	for k in 5:
		var x := -4.0 + k * 2.0
		var h := 20.0 + (k * 7 % 5) * 2.0
		ci.draw_line(bp + Vector2(x, 0), bp + Vector2(x + 1.5, -h), bc.darkened(0.15), 1.0)
		for j in 3:
			var q := bp + Vector2(x + 1.5 * (h - 6 - j * 5) / h, -(h - 4 - j * 5))
			poly(ci, [q, q + Vector2(5, 1), q + Vector2(1, 2)], bc)
			poly(ci, [q, q + Vector2(-4, 2), q + Vector2(-1, 2.5)], bc.lightened(0.1))
	_banner(ci, P(c, 0.1, 0.48), "塾", 20)


static func _horse(ci, p: Vector2, col: Color) -> void:
	for x in [-4.0, -2.0, 3.0, 5.0]:
		ci.draw_line(p + Vector2(x, -4), p + Vector2(x, 0), col.darkened(0.3), 1.2)
	ell(ci, p + Vector2(0.5, -5.5), 5.2, 2.4, col)
	ci.draw_line(p + Vector2(4.5, -6), p + Vector2(7, -10), col, 2.2)
	ell(ci, p + Vector2(8, -10.4), 1.8, 1.1, col)
	ci.draw_line(p + Vector2(-4.5, -6), p + Vector2(-6.5, -2.5), col.darkened(0.35), 1.2)


static func _boat(ci, p: Vector2, ax: bool) -> void:
	var u := iso(1, 0).normalized() if ax else iso(0, 1).normalized()
	var w := iso(0, 1).normalized() if ax else iso(1, 0).normalized()
	var hull := [p + u * 13 - Vector2(0, 3), p + u * 9 + w * 4, p - u * 10 + w * 4, p - u * 13 - Vector2(0, 2), p - u * 10 - w * 4, p + u * 9 - w * 4]
	poly(ci, hull, Color(0.45, 0.3, 0.2))
	line(ci, hull + [hull[0]], INK, 1.0)
	var cab := p - u * 3
	poly(ci, [cab - u * 4 + w * 3 - Vector2(0, 1), cab + u * 4 + w * 3 - Vector2(0, 1), cab + u * 4 - Vector2(0, 8), cab - u * 4 - Vector2(0, 8)], Color(0.32, 0.26, 0.2))
	ell(ci, p + u * 6 - Vector2(0, 3), 2.4, 1.6, Color(0.85, 0.78, 0.6))


## 依類型繪製建築（碼頭與外邑另由世界畫面處理）。工具列縮圖與地圖共用。
static func building(ci, type: String, c: Vector2, lvl: int, v: int) -> void:
	match type:
		"house":
			house(ci, c, lvl, v)
		"shop":
			shop(ci, c, lvl, v)
		"workshop":
			workshop(ci, c, lvl, v)
		"farm":
			farmhouse(ci, c, lvl, v)
		"yamen":
			yamen(ci, c, v)
		"temple":
			temple(ci, c, v)
		"academy":
			academy(ci, c, v)
		"belltower":
			belltower(ci, c, v)
		"pagoda":
			pagoda(ci, c, v)
		"archway":
			archway(ci, c, v)
		"garden":
			garden(ci, c, v)
		"theater":
			theater(ci, c, v)
		"well":
			well(ci, c, v)
		"constable":
			constable(ci, c, v)
		"clinic":
			clinic(ci, c, v)
		"school":
			school(ci, c, v)
		"firewatch":
			firewatch(ci, c, v)
		"granary":
			granary(ci, c, v)
		"warehouse":
			warehouse(ci, c, v)
		"lumber":
			lumber(ci, c, v)
		"quarry":
			quarry(ci, c, v)
		"mine":
			mountain(ci, c, v | 7)
			mine(ci, c, v)
		"mulberry":
			mulberry(ci, c, v)
		"tea":
			tea(ci, c, v)
		"fishery":
			fishery(ci, c, v)
		"kiln":
			kiln(ci, c, v)
		"station":
			station(ci, c, v)
		"dock":
			dock(ci, c, v, Vector2i(1, 0))


# ───────────────────────── 車船人物 ─────────────────────────

## mast：福船桅杆，1 豎起、0 放倒（過橋時）。
static func vehicle(ci, kind: String, dir: Vector2i, cargo_col: Color, loaded: bool, mast: float = 1.0) -> void:
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
				if mast >= 0.99:
					ci.draw_line(m, m - Vector2(0, 30), WOOD.darkened(0.3), 1.5)
					poly(ci, [m - Vector2(0, 29) + w * 1, m - Vector2(0, 9) + w * 1, m - Vector2(0, 9) - u * 9 + w * 1, m - Vector2(0, 27) - u * 7 + w * 1], Color(0.7, 0.4, 0.25))
					for k in 4:
						ci.draw_line(m - Vector2(0, 12 + k * 4.5), m - Vector2(0, 12 + k * 4.5) - u * 8, Color(0.4, 0.2, 0.1), 0.8)
				else:
					# 落桅：帆收攏捆在桅上，桅杆向船尾放倒
					var top := m + Vector2(0, -30).lerp(-u * 22 - Vector2(0, 6), 1.0 - mast)
					ci.draw_line(m, top, WOOD.darkened(0.3), 1.5)
					ci.draw_line(m.lerp(top, 0.3), m.lerp(top, 0.9), Color(0.62, 0.36, 0.22), 3.0)


# ───────────────────────── 行人 ─────────────────────────

const SKIN := Color(0.87, 0.72, 0.57)
const HAIR := Color(0.12, 0.1, 0.09)
const GREY_HAIR := Color(0.82, 0.8, 0.76)
const STRAW := Color(0.8, 0.68, 0.42)
const SHOE := Color(0.2, 0.16, 0.13)
const FIG_COATS := {
	"farmer": [Color(0.3, 0.36, 0.5), Color(0.52, 0.4, 0.28), Color(0.42, 0.46, 0.38)],
	"porter": [Color(0.7, 0.62, 0.45), Color(0.48, 0.42, 0.36), Color(0.36, 0.42, 0.52)],
	"peddler": [Color(0.38, 0.44, 0.55), Color(0.55, 0.36, 0.26), Color(0.44, 0.5, 0.42)],
	"scholar": [Color(0.9, 0.88, 0.82), Color(0.66, 0.76, 0.82), Color(0.78, 0.8, 0.72)],
	"woman": [Color(0.78, 0.32, 0.3), Color(0.38, 0.6, 0.5), Color(0.86, 0.62, 0.66), Color(0.5, 0.5, 0.7)],
	"child": [Color(0.85, 0.3, 0.22), Color(0.3, 0.6, 0.4), Color(0.9, 0.7, 0.25)],
	"elder": [Color(0.46, 0.4, 0.34), Color(0.36, 0.38, 0.4)],
	"official": [Color(0.25, 0.42, 0.32), Color(0.62, 0.16, 0.14), Color(0.3, 0.3, 0.5)],
	"monk": [Color(0.72, 0.52, 0.24), Color(0.5, 0.48, 0.44)],
}
const SKIRTS := [Color(0.9, 0.86, 0.76), Color(0.3, 0.36, 0.5), Color(0.62, 0.22, 0.24), Color(0.4, 0.55, 0.45)]
const WARES := [Color(0.85, 0.72, 0.3), Color(0.4, 0.62, 0.32), Color(0.8, 0.25, 0.25), Color(0.4, 0.55, 0.85)]


## 弧上之點（度），供髮、帽之輪廓。
static func _arc(c: Vector2, r: float, a0: float, a1: float, n: int = 8) -> Array:
	var pts := []
	for k in n + 1:
		var t := deg_to_rad(lerpf(a0, a1, k / float(n)))
		pts.append(c + Vector2(cos(t), sin(t)) * r)
	return pts


## 行人：腳底為原點，畫成向右行；flip 鏡像為向左，front 為面向鏡頭（否則見背影）。
## ph 為步伐相位（0..1）。
static func figure(ci, role: String, v: int, front: bool, flip: bool, ph: float, at: Vector2 = Vector2.ZERO) -> void:
	var k := 1.0
	var lean := 0.0
	match role:
		"child":
			k = 0.68
		"woman":
			k = 0.93
		"elder":
			k = 0.92
			lean = 0.12
	var fx := -1.0 if flip else 1.0
	var s := sin(ph * TAU)
	var lift := (1.0 - absf(s)) * 0.5
	var ly := lift / k
	ci.draw_set_transform(at, 0.0, Vector2(fx * k, k))
	ell(ci, Vector2(0, 0.2), 3.0, 1.1, Color(0.1, 0.08, 0.04, 0.2))
	ci.draw_set_transform(at + Vector2(0, -lift), lean * fx, Vector2(fx * k, k))
	var cols: Array = FIG_COATS.get(role, FIG_COATS.farmer)
	var coat: Color = cols[v % cols.size()]
	var winter := season == 3
	if winter and role in ["farmer", "porter", "peddler", "child"]:
		coat = coat.darkened(0.12)
	var robed := role in ["scholar", "official", "monk", "elder"]
	var hc := Vector2(0.35, -10.5)
	var bb := s * 0.5
	# 身後之物
	if role == "porter":
		_basket(ci, -5.6, -bb, v)
	if role == "peddler" and front:
		_pack(ci, v)
	# 後臂
	var back_hand := Vector2(0.2 + s * 1.3, -5.0)
	match role:
		"porter":
			back_hand = Vector2(-0.8, -9.0)
		"scholar", "official":
			back_hand = Vector2(1.2, -6.4)
	ci.draw_line(Vector2(0.2, -8.4), back_hand, coat.darkened(0.25), 1.3)
	# 腿腳
	if robed or role == "woman":
		for side in [-1, 1]:
			var fp: float = side * s * 1.2
			ci.draw_line(Vector2(fp - 0.2, ly - 0.4), Vector2(fp + 1.1, ly - 0.4), SHOE, 1.1)
	else:
		var trousers := coat.darkened(0.3) if role != "porter" else Color(0.35, 0.33, 0.3)
		var bare := role in ["farmer", "porter", "child"] and not winter
		for side in [-1, 1]:
			var fp: float = side * s * 1.7
			var hip := Vector2(side * 0.4, -4.6)
			var foot := Vector2(fp, ly - 0.6)
			var col: Color = trousers if side == 1 else trousers.darkened(0.2)
			ci.draw_line(hip, foot, col, 1.5)
			if bare:
				ci.draw_line(hip.lerp(foot, 0.55), foot, SKIN.darkened(0.08 if side == 1 else 0.25), 1.2)
			ci.draw_line(Vector2(fp - 0.3, ly - 0.3), Vector2(fp + 1.0, ly - 0.3), SHOE, 1.0)
	# 身
	var dark := coat.darkened(0.4)
	if robed:
		poly(ci, [Vector2(-1.6, -8.9), Vector2(1.6, -8.9), Vector2(2.5, -0.5), Vector2(-2.5, -0.5)], coat)
		ci.draw_line(Vector2(-2.45, -1.0), Vector2(2.45, -1.0), dark, 0.9)
		ci.draw_line(Vector2(-1.75, -5.6), Vector2(1.95, -5.6), Color(0.85, 0.7, 0.3) if role == "official" else dark, 0.8)
		if role == "monk":
			ci.draw_line(Vector2(-1.4, -8.8), Vector2(1.9, -3.0), Color(0.55, 0.2, 0.15), 1.2)
	elif role == "woman":
		poly(ci, [Vector2(-1.5, -5.8), Vector2(1.5, -5.8), Vector2(2.4, -0.4), Vector2(-2.4, -0.4)], SKIRTS[(v / 4) % SKIRTS.size()])
		poly(ci, [Vector2(-1.5, -8.6), Vector2(1.5, -8.6), Vector2(1.9, -3.8), Vector2(-1.9, -3.8)], coat)
		ci.draw_line(Vector2(1.1, -8.5), Vector2(1.5, -3.9), dark, 0.7)
	else:
		poly(ci, [Vector2(-1.6, -8.9), Vector2(1.6, -8.9), Vector2(1.9, -4.0), Vector2(-1.9, -4.0)], coat)
		ci.draw_line(Vector2(-1.85, -5.0), Vector2(1.85, -5.0), dark, 0.8)
	if front:
		ci.draw_line(Vector2(-0.5, -8.9), Vector2(1.3, -6.6), dark, 0.7)
	if role == "farmer" and winter:
		# 蓑衣
		var cape := Color(0.55, 0.47, 0.3)
		poly(ci, [Vector2(-2.2, -9.1), Vector2(1.4, -9.1), Vector2(2.6, -3.0), Vector2(-2.8, -3.0)], cape)
		for q in 3:
			ci.draw_line(Vector2(-1.6 + q * 1.3, -8.4), Vector2(-2.0 + q * 1.7, -3.2), cape.darkened(0.3), 0.6)
	if role == "peddler" and not front:
		_pack(ci, v)
	# 頭
	var hair := GREY_HAIR if role == "elder" else HAIR
	if role == "monk":
		ci.draw_circle(hc, 1.75, SKIN if front else SKIN.darkened(0.12))
	elif front:
		ci.draw_circle(hc, 1.75, SKIN)
		poly(ci, _arc(hc, 1.8, 120, 300), hair)
	else:
		ci.draw_circle(hc, 1.8, hair)
	match role:
		"farmer":
			var hat := snowy(STRAW, 0.6)
			poly(ci, [Vector2(-3.9, -11.0), Vector2(4.6, -11.0), Vector2(0.35, -14.0)], hat)
			ci.draw_line(Vector2(-3.9, -11.0), Vector2(4.6, -11.0), hat.darkened(0.35), 0.7)
		"porter":
			ci.draw_line(Vector2(-1.4, -11.2), Vector2(2.1, -11.4), Color(0.92, 0.9, 0.84), 1.3)
			ci.draw_line(Vector2(-1.5, -11.2), Vector2(-2.6, -10.0), Color(0.92, 0.9, 0.84), 0.8)
		"peddler":
			poly(ci, _arc(hc + Vector2(0, -0.3), 1.9, 180, 360), Color(0.2, 0.2, 0.22))
		"scholar":
			poly(ci, [Vector2(-1.3, -11.6), Vector2(1.9, -11.6), Vector2(1.7, -13.0), Vector2(-1.1, -13.1)], HAIR)
			ci.draw_line(Vector2(-1.2, -11.9), Vector2(-2.6, -10.2), HAIR, 0.45)
			ci.draw_line(Vector2(-1.0, -11.7), Vector2(-2.1, -9.8), HAIR, 0.45)
		"official":
			poly(ci, [Vector2(-1.6, -11.3), Vector2(2.1, -11.3), Vector2(1.9, -13.5), Vector2(-1.4, -13.5)], HAIR)
			ci.draw_line(Vector2(-5.5, -12.1), Vector2(6.0, -12.1), HAIR, 0.7)
		"woman":
			ci.draw_circle(hc + Vector2(-0.6, -2.0), 1.15, HAIR)
			ci.draw_line(hc + Vector2(-2.2, -2.3), hc + Vector2(0.7, -1.7), GOLD, 0.5)
			if v % 3 == 0:
				ci.draw_circle(hc + Vector2(0.4, -2.4), 0.5, Color(0.9, 0.3, 0.35))
		"child":
			ci.draw_circle(hc + Vector2(-1.0, -1.7), 0.75, HAIR)
			ci.draw_circle(hc + Vector2(0.9, -1.8), 0.75, HAIR)
		"elder":
			ci.draw_circle(hc + Vector2(-0.3, -1.9), 0.7, GREY_HAIR)
			if front:
				poly(ci, [Vector2(1.0, -9.4), Vector2(2.1, -9.4), Vector2(1.4, -7.4)], GREY_HAIR)
	# 前臂與手中之物
	var hand := Vector2(0.2 - s * 1.3, -5.0)
	match role:
		"farmer":
			hand = Vector2(1.3, -8.8)
		"porter":
			hand = Vector2(1.6, -9.0)
		"peddler":
			hand = Vector2(2.2, -6.6)
		"scholar":
			hand = Vector2(1.6, -6.2)
		"official":
			hand = Vector2(1.7, -6.4)
		"monk":
			hand = Vector2(1.5, -7.2)
		"elder":
			hand = Vector2(2.4, -5.6)
		"woman":
			hand = Vector2(1.4, -5.4) if v % 2 == 0 else Vector2(0.2 - s * 0.8, -5.0)
		"child":
			hand = Vector2(0.2 - s * 1.8, -5.4)
	ci.draw_line(Vector2(0.2, -8.4), hand, coat.darkened(0.05), 1.4)
	ci.draw_circle(hand, 0.55, SKIN)
	match role:
		"farmer":
			ci.draw_line(Vector2(-3.8, -7.0), Vector2(3.2, -11.0), WOOD_L, 0.8)
			poly(ci, [Vector2(-3.8, -7.0), Vector2(-4.6, -5.6), Vector2(-3.5, -5.4)], Color(0.45, 0.45, 0.48))
		"porter":
			ci.draw_line(Vector2(-6.2, -9.4), Vector2(6.6, -9.4), WOOD_L, 1.0)
			_basket(ci, 5.6, bb, v + 1)
		"peddler":
			ci.draw_line(hand, hand + Vector2(0.4, -2.4), WOOD, 0.5)
			ci.draw_circle(hand + Vector2(0.4, -2.9), 0.8, RED)
		"official":
			ci.draw_line(Vector2(1.7, -6.0), Vector2(2.1, -9.2), Color(0.92, 0.9, 0.8), 0.7)
		"elder":
			ci.draw_line(Vector2(2.4, -5.8), Vector2(3.0, ly), WOOD, 0.6)
		"woman":
			if v % 2 == 0:
				poly(ci, [Vector2(0.6, -5.0), Vector2(2.6, -5.0), Vector2(2.3, -3.4), Vector2(0.9, -3.4)], STRAW.darkened(0.15))
				line(ci, _arc(Vector2(1.6, -5.0), 1.0, 180, 360, 6), STRAW.darkened(0.35), 0.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 挑擔之筐，x 為其中心，dy 為晃動。
static func _basket(ci, x: float, dy: float, v: int) -> void:
	var top := -5.2 + dy
	ci.draw_line(Vector2(x, -9.4), Vector2(x - 1.2, top), OUT, 0.5)
	ci.draw_line(Vector2(x, -9.4), Vector2(x + 1.2, top), OUT, 0.5)
	poly(ci, [Vector2(x - 1.5, top), Vector2(x + 1.5, top), Vector2(x + 1.1, top + 2.8), Vector2(x - 1.1, top + 2.8)], STRAW.darkened(0.25))
	ell(ci, Vector2(x, top - 0.1), 1.4, 0.6, WARES[v % WARES.size()])


## 貨郎背上之貨架。
static func _pack(ci, v: int) -> void:
	poly(ci, [Vector2(-4.4, -12.6), Vector2(-1.4, -12.6), Vector2(-1.4, -4.2), Vector2(-4.4, -4.2)], WOOD_L)
	for q in 3:
		var y := -10.4 + q * 2.4
		ci.draw_line(Vector2(-4.4, y), Vector2(-1.4, y), WOOD.darkened(0.3), 0.6)
		for j in 2:
			ci.draw_circle(Vector2(-3.6 + j * 1.4, y - 0.9), 0.6, WARES[(v + q + j) % WARES.size()])
	line(ci, [Vector2(-4.4, -12.6), Vector2(-1.4, -12.6), Vector2(-1.4, -4.2), Vector2(-4.4, -4.2), Vector2(-4.4, -12.6)], OUT, 0.6)
