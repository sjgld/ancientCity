extends RefCounted
## 繪圖批次：與 CanvasItem 同名之 draw_* 介面，將所有圖形併為一個網格，一次繪出。

var verts := PackedVector2Array()
var cols := PackedColorArray()
var texts: Array = []
var off := Vector2.ZERO


func draw_set_transform(p: Vector2, _rot: float = 0.0, _scale: Vector2 = Vector2.ONE) -> void:
	off = p


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	verts.append_array([a + off, b + off, c + off, a + off, c + off, d + off])
	for k in 6:
		cols.append(col)


func draw_colored_polygon(pts: PackedVector2Array, col: Color, _uvs = null, _tex = null) -> void:
	draw_polygon(pts, PackedColorArray([col]))


func draw_polygon(pts: PackedVector2Array, pcols: PackedColorArray, _uvs = null, _tex = null) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() < 4:
			return
		hull.remove_at(hull.size() - 1)
		pts = hull
		pcols = PackedColorArray([pcols[0]])
		idx = Geometry2D.triangulate_polygon(pts)
	var uni := pcols.size() < pts.size()
	for i in idx:
		verts.append(pts[i] + off)
		cols.append(pcols[0] if uni else pcols[i])


func draw_line(a: Vector2, b: Vector2, col: Color, w: float = 1.0, _aa: bool = false) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var n := Vector2(-d.y, d.x) / l * maxf(w, 1.0) * 0.5
	_quad(a + n, b + n, b - n, a - n, col)


func draw_polyline(pts: PackedVector2Array, col: Color, w: float = 1.0, _aa: bool = false) -> void:
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], col, w)


func draw_circle(p: Vector2, r: float, col: Color, _filled: bool = true, _w: float = -1.0, _aa: bool = false) -> void:
	var n := clampi(int(r * 1.2) + 6, 6, 18)
	var c := p + off
	var prev := c + Vector2(r, 0)
	for k in range(1, n + 1):
		var a := k * TAU / n
		var nx := c + Vector2(cos(a), sin(a)) * r
		verts.append_array([c, prev, nx])
		cols.append(col)
		cols.append(col)
		cols.append(col)
		prev = nx


func draw_rect(r: Rect2, col: Color, filled: bool = true, w: float = -1.0, _aa: bool = false) -> void:
	var a := r.position
	var b := r.position + Vector2(r.size.x, 0)
	var c := r.end
	var d := r.position + Vector2(0, r.size.y)
	if filled:
		_quad(a, b, c, d, col)
	else:
		var ww := maxf(w, 1.0)
		draw_polyline(PackedVector2Array([a, b, c, d, a]), col, ww)


func draw_string(font: Font, pos: Vector2, text: String, _align: int = 0, _width: float = -1, size: int = 16, col: Color = Color.WHITE) -> void:
	texts.append([font, pos + off, text, size, col])


## 於 ci 的 _draw 中呼叫：一次畫出全部三角形，再補上文字。
func emit(ci: CanvasItem) -> void:
	if not verts.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_COLOR] = cols
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		ci.set_meta("mesh", m)
		ci.draw_mesh(m, null)
	for t in texts:
		ci.draw_string(t[0], t[1], t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, t[3], t[4])
