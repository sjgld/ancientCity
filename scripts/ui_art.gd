extends RefCounted
## 介面畫具：常駐框用深色漆木，彈出物用宣紙。材質（紙紋、木紋、毛邊、印泥）與圖示皆以程式產生。

# 漆木：天頭、地頭、書冊外框
const WOOD := Color("33271f")
const WOOD_D := Color("241b15")
const WOOD_L := Color("4a382b")
const GOLD := Color("b8975a")
const IVORY := Color("efe6d2")
const IVORY_2 := Color("bfb29b")
# 宣紙：冊頁、提示、詔令、邸報、托板
const PAPER := Color("ede5d1")
const PAPER_2 := Color("e2d6bc")
const HUANG := Color("e2cd96")
const INK := Color("29241f")
const INK_2 := Color("5d5147")
const INK_3 := Color("8b7d6e")
# 語意色：紙上與木上各一組
const GOOD := Color("3f7a57")
const GOOD_W := Color("8cc29b")
const BAD := Color("b1372a")
const BAD_W := Color("e2735f")
const ZHU := Color("b1372a")
const SHIQING := Color("2e5a6f")
const NIJIN := Color("a5854c")
const SEAL_TEXT := Color("f6e9d6")
const LIFT := Color(0.12, 0.09, 0.06, 0.3)   # 紙之硬陰影
# 分區色：與地圖上塗分區一致
const ZONE := [Color(0, 0, 0, 0), Color("5aa55a"), Color("4d7fd6"), Color("e0ad35"), Color("a5733a")]

const FONT_FILES := {
	"title": "res://fonts/NotoSerifTC-Black.otf",
	"num": "res://fonts/NotoSerifTC-SemiBold.otf",
	"body": "res://fonts/LXGWWenKaiTC-Regular.ttf",
	"body_b": "res://fonts/LXGWWenKaiTC-Medium.ttf",
}
static var _fonts := {}
static var _tex := {}


## title：題、匾、印；num：數字；body：敘述；body_b：敘述加重。
static func font(kind: String) -> Font:
	if not _fonts.has(kind):
		var f: Font = load(FONT_FILES[kind])
		if f == null:
			f = SystemFont.new()
		_fonts[kind] = f
	return _fonts[kind]


# ───────────────────────── 材質貼圖 ─────────────────────────

## 宣紙紋：低頻明暗起伏加細長纖維，可平鋪。存於 alpha，疊在底色上用。
static func paper_tex() -> Texture2D:
	if _tex.has("paper"):
		return _tex["paper"]
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.06
	n.fractal_octaves = 5
	var base := n.get_seamless_image(256, 256)
	var fb := FastNoiseLite.new()
	fb.seed = 19
	fb.frequency = 0.22
	fb.fractal_octaves = 2
	var fib := fb.get_seamless_image(256, 128)
	fib.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var v := base.get_pixel(x, y).r
			var f := fib.get_pixel(x, y).r
			# 淡淡的雲紋起伏，加上偶見的細纖維
			var a := absf(v - 0.5) * 0.22 + maxf(f - 0.72, 0.0) * 0.9
			img.set_pixel(x, y, Color(0.32, 0.25, 0.17, clampf(a, 0.0, 0.3)))
	var t := ImageTexture.create_from_image(img)
	_tex["paper"] = t
	return t


## 漆木紋：橫向拉長的木理，可平鋪。
static func wood_tex() -> Texture2D:
	if _tex.has("wood"):
		return _tex["wood"]
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.05
	n.fractal_octaves = 3
	var g := n.get_seamless_image(128, 128)
	g.resize(512, 48, Image.INTERPOLATE_BILINEAR)
	var img := Image.create(512, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 512:
			var v := g.get_pixel(x, y).r
			var stripe := 0.5 + 0.5 * sin(v * 26.0)
			img.set_pixel(x, y, Color(0.05, 0.03, 0.02, clampf(stripe * 0.55 + (v - 0.5) * 0.4, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_tex["wood"] = t
	return t


## 印泥：朱色底帶不均勻的缺損與顆粒。
static func seal_tex() -> Texture2D:
	if _tex.has("seal"):
		return _tex["seal"]
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.09
	n.fractal_octaves = 3
	var g := n.get_image(96, 96)
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var v := g.get_pixel(x, y).r
			var edge := minf(minf(x, 95 - x), minf(y, 95 - y)) / 6.0
			var a := 1.0
			if v > 0.78:
				a = 0.55
			if edge < 1.0 and v > 0.55:
				a = 0.0
			var c := ZHU.lerp(Color("c64a35"), (v - 0.5) * 0.8)
			img.set_pixel(x, y, Color(c, a))
	var t := ImageTexture.create_from_image(img)
	_tex["seal"] = t
	return t


# ───────────────────────── 面 ─────────────────────────

## 確定性之小抖動，用於毛邊。
static func _jit(i: int, seed_v: int) -> float:
	return fposmod(sin(i * 12.9898 + seed_v * 78.233) * 43758.5453, 1.0) - 0.5


## 矩形外框點；deckle 時四邊每 7 像素抖動一次，像裁下的紙。
static func outline_pts(r: Rect2, deckle: bool, seed_v: int = 0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not deckle:
		pts.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		return pts
	var step := 7.0
	var amp := 2.2
	var k := 0
	var x := r.position.x
	while x < r.end.x:
		pts.append(Vector2(x, r.position.y + _jit(k, seed_v) * amp))
		x += step
		k += 1
	var y := r.position.y
	while y < r.end.y:
		pts.append(Vector2(r.end.x + _jit(k, seed_v) * amp, y))
		y += step
		k += 1
	x = r.end.x
	while x > r.position.x:
		pts.append(Vector2(x, r.end.y + _jit(k, seed_v) * amp))
		x -= step
		k += 1
	y = r.end.y
	while y > r.position.y:
		pts.append(Vector2(r.position.x + _jit(k, seed_v) * amp, y))
		y -= step
		k += 1
	# 太小或抖動後自交的紙，退回直邊，免得無法三角化
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return outline_pts(r, false)
	return pts


## 紙面：底色、紙紋、可選毛邊與硬陰影。ci 為畫布 RID。
static func paper_rid(ci: RID, r: Rect2, col: Color = PAPER, shadow: float = 3.0, deckle: bool = false, seed_v: int = 0, grain: float = 0.55) -> void:
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var rs := RenderingServer
	rs.canvas_item_set_default_texture_repeat(ci, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED)
	var pts := outline_pts(r, deckle, seed_v)
	if shadow > 0:
		var sp := PackedVector2Array()
		for p in pts:
			sp.append(p + Vector2(shadow * 0.7, shadow))
		rs.canvas_item_add_polygon(ci, sp, PackedColorArray([LIFT]))
	rs.canvas_item_add_polygon(ci, pts, PackedColorArray([col]))
	if grain > 0:
		var uv := PackedVector2Array()
		for p in pts:
			uv.append(p / 256.0)
		rs.canvas_item_add_polygon(ci, pts, PackedColorArray([Color(1, 1, 1, grain)]), uv, paper_tex().get_rid())


## 漆木面：上亮下暗之漸層加木理。edge 為鑲金線之邊（"top"、"bottom"、"all" 或 ""）。
static func wood_rid(ci: RID, r: Rect2, edge: String = "") -> void:
	var rs := RenderingServer
	rs.canvas_item_set_default_texture_repeat(ci, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var top := Color("3d2f25")
	var bot := Color("271e17")
	rs.canvas_item_add_polygon(ci, pts, PackedColorArray([top, top, bot, bot]))
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(Vector2(p.x / 512.0, p.y / 48.0))
	rs.canvas_item_add_polygon(ci, pts, PackedColorArray([Color(1, 1, 1, 0.9)]), uv, wood_tex().get_rid())
	match edge:
		"bottom":
			rs.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y - 1, r.size.x, 1), GOLD)
			rs.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y, r.size.x, 2), Color(0.08, 0.05, 0.03, 0.55))
		"top":
			rs.canvas_item_add_rect(ci, Rect2(r.position.x, r.position.y, r.size.x, 1), GOLD)
			rs.canvas_item_add_rect(ci, Rect2(r.position.x, r.position.y - 2, r.size.x, 2), Color(0.08, 0.05, 0.03, 0.55))
		"all":
			_frame(ci, r.grow(-0.5), GOLD)


static func _frame(ci: RID, r: Rect2, col: Color, w: float = 1.0) -> void:
	var a := r.position
	var b := r.end
	RenderingServer.canvas_item_add_polyline(ci, PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]), PackedColorArray([col]), w)


# CanvasItem 便捷版
static func band(ci: CanvasItem, r: Rect2, edge: String) -> void:
	wood_rid(ci.get_canvas_item(), r, edge)


static func slip(ci: CanvasItem, r: Rect2, col: Color = PAPER, shadow: float = 3.0, deckle: bool = false, seed_v: int = 0) -> void:
	paper_rid(ci.get_canvas_item(), r, col, shadow, deckle, seed_v)


# ───────────────────────── 面板樣式 ─────────────────────────

## 面板底：kind 為 paper（宣紙）、wood（漆木）、book（木框紙心）、flat（純色）。
class Box extends StyleBox:
	var kind := "paper"
	var bg := Color.WHITE
	var shadow := 3.0
	var deckle := false
	var border := Color(0, 0, 0, 0)
	var underline := Color(0, 0, 0, 0)
	var seed_v := 0

	func _draw(ci: RID, r: Rect2) -> void:
		var UA = load("res://scripts/ui_art.gd")
		match kind:
			"paper":
				UA.paper_rid(ci, r, bg, shadow, deckle, seed_v)
			"wood":
				if shadow > 0:
					RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(2, 3), r.size), Color(0.08, 0.05, 0.03, 0.45))
				UA.wood_rid(ci, r, "all")
			"book":
				RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(6, 10), r.size), Color(0.08, 0.05, 0.03, 0.4))
				UA.wood_rid(ci, r, "all")
				UA.paper_rid(ci, r.grow(-16), UA.PAPER, 0.0)
				UA._frame(ci, r.grow(-15.5), UA.GOLD)
			_:
				if shadow > 0:
					RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(shadow, shadow), r.size), UA.LIFT)
				if bg.a > 0:
					RenderingServer.canvas_item_add_rect(ci, r, bg)
		if border.a > 0:
			UA._frame(ci, r.grow(-0.5), border)
		if underline.a > 0:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y - 2, r.size.x, 2), underline)


static func box(kind: String, bg: Color, mx: float, my: float, shadow: float = 3.0, deckle: bool = false, border: Color = Color(0, 0, 0, 0)) -> Box:
	var b := Box.new()
	b.kind = kind
	b.bg = bg
	b.shadow = shadow
	b.deckle = deckle
	b.border = border
	b.seed_v = randi() % 1000
	b.content_margin_left = mx
	b.content_margin_right = mx
	b.content_margin_top = my
	b.content_margin_bottom = my
	return b


static func book_box(mx: float = 30.0, my: float = 24.0) -> Box:
	return box("book", PAPER, mx + 16, my + 16, 0.0)


# ───────────────────────── 字與印 ─────────────────────────

static func _char(ci: CanvasItem, f: Font, c: Vector2, ch: String, size: int, col: Color) -> void:
	var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	ci.draw_string(f, c + Vector2(-w.x * 0.5, (f.get_ascent(size) - f.get_descent(size)) * 0.5 - size * 0.04), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## 置中寫一行字。
static func text_c(ci: CanvasItem, f: Font, c: Vector2, text: String, size: int, col: Color) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(f, c + Vector2(-w * 0.5, (f.get_ascent(size) - f.get_descent(size)) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## 自左緣起寫一行字，垂直置中於 cy；回傳寬度。
static func text_l(ci: CanvasItem, f: Font, x: float, cy: float, text: String, size: int, col: Color) -> float:
	ci.draw_string(f, Vector2(x, cy + (f.get_ascent(size) - f.get_descent(size)) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 直排文字。
static func vtext(ci: CanvasItem, f: Font, top: Vector2, text: String, size: int, col: Color, gap: float = 0.08) -> void:
	var y := top.y + size * 0.5
	for ch in text:
		_char(ci, f, Vector2(top.x, y), ch, size, col)
		y += size * (1.0 + gap)


## 朱印：印泥材質，一字。rot 為微斜。
static func seal(ci: CanvasItem, r: Rect2, ch: String, rot: float = 0.0) -> void:
	ci.draw_set_transform(r.get_center(), rot, Vector2.ONE)
	var half := r.size * 0.5
	ci.draw_texture_rect(seal_tex(), Rect2(-half, r.size), false)
	_char(ci, font("title"), Vector2.ZERO, ch, int(r.size.y * 0.64), Color(SEAL_TEXT, 0.95))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 朱文小印：朱框朱字，用於鎖定之品級。
static func seal_outline(ci: CanvasItem, r: Rect2, ch: String, col: Color = ZHU) -> void:
	ci.draw_rect(r.grow(-0.75), col, false, 1.5)
	_char(ci, font("title"), r.get_center(), ch, int(r.size.y * 0.64), col)


# ───────────────────────── 圖示 ─────────────────────────

static func _shape(ci: CanvasItem, pts: Array, fill: Color, line: Color, w: float = 1.4) -> void:
	var p := PackedVector2Array(pts)
	if fill.a > 0:
		ci.draw_colored_polygon(p, fill)
	if line.a > 0:
		p.append(p[0])
		ci.draw_polyline(p, line, w, true)


static func _ring(ci: CanvasItem, c: Vector2, r: float, fill: Color, line: Color, w: float = 1.4) -> void:
	if fill.a > 0:
		ci.draw_circle(c, r, fill)
	if line.a > 0:
		ci.draw_arc(c, r, 0, TAU, 28, line, w, true)


static func _pl(ci: CanvasItem, pts: Array, col: Color, w: float = 1.4) -> void:
	ci.draw_polyline(PackedVector2Array(pts), col, w, true)


## 在 r 中畫一枚圖示（以 24 格為準）。line 為墨線色：紙上用墨，木上用象牙白。
static func icon(ci: CanvasItem, kind: String, r: Rect2, line: Color = INK) -> void:
	var s := r.size.x / 24.0
	ci.draw_set_transform(r.position, 0.0, Vector2(s, s))
	match kind:
		"silver":
			_shape(ci, [Vector2(2.5, 14), Vector2(4.2, 10.9), Vector2(6.4, 9.5), Vector2(9.1, 10.5), Vector2(10.4, 8.4), Vector2(12, 7.7),
				Vector2(13.6, 8.4), Vector2(14.9, 10.5), Vector2(17.6, 9.5), Vector2(19.8, 10.9), Vector2(21.5, 14), Vector2(17, 16.3),
				Vector2(12, 16.9), Vector2(7, 16.3)], Color("cfc9bb"), line)
			_pl(ci, [Vector2(9.2, 10.6), Vector2(12, 11.6), Vector2(14.8, 10.6)], line, 1.1)
			_pl(ci, [Vector2(5, 13.2), Vector2(8, 14.2), Vector2(11, 14.6)], Color(1, 1, 1, 0.6), 1.0)
		"people":
			_ring(ci, Vector2(9, 7), 3, Color("d9c3a3"), line)
			_shape(ci, [Vector2(3.5, 20.5), Vector2(4.4, 16.5), Vector2(6.5, 14), Vector2(9, 13.1), Vector2(11.5, 14), Vector2(13.6, 16.5), Vector2(14.5, 20.5)], Color("8e7f6c"), line)
			_ring(ci, Vector2(16.5, 8.5), 2.4, Color("d9c3a3"), line, 1.2)
			_pl(ci, [Vector2(14.8, 13.4), Vector2(18, 14), Vector2(19.8, 16.5), Vector2(20.5, 19.7)], line, 1.2)
		"mood_good", "mood", "mood_bad":
			var fc: Color = {"mood_good": Color("9cc79c"), "mood": Color("e6c87a"), "mood_bad": Color("e09a86")}[kind]
			_ring(ci, Vector2(12, 12), 9, fc, line)
			ci.draw_circle(Vector2(8, 10.2), 1.25, line)
			ci.draw_circle(Vector2(16, 10.2), 1.25, line)
			match kind:
				"mood_good":
					_pl(ci, [Vector2(8, 13.6), Vector2(10, 15.4), Vector2(12, 15.9), Vector2(14, 15.4), Vector2(16, 13.6)], line, 1.5)
				"mood":
					_pl(ci, [Vector2(8.2, 14.4), Vector2(15.8, 14.4)], line, 1.5)
				_:
					_pl(ci, [Vector2(8, 16.2), Vector2(10, 14.7), Vector2(12, 14.3), Vector2(14, 14.7), Vector2(16, 16.2)], line, 1.5)
		"grain":
			_shape(ci, [Vector2(4, 11), Vector2(20, 11), Vector2(17.6, 20.5), Vector2(6.4, 20.5)], Color("9a7444"), line)
			_shape(ci, [Vector2(4.8, 11), Vector2(7, 8.6), Vector2(12, 7.6), Vector2(17, 8.6), Vector2(19.2, 11)], Color("e6c565"), line, 1.2)
			_pl(ci, [Vector2(8, 15), Vector2(16, 15)], Color(line, 0.5), 1.0)
		"pause":
			ci.draw_rect(Rect2(6.5, 5, 4, 14), line)
			ci.draw_rect(Rect2(13.5, 5, 4, 14), line)
		"play1":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(8, 5), Vector2(19, 12), Vector2(8, 19)]), line)
		"play2":
			for x0 in [3.5, 12.5]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, 6), Vector2(x0 + 9, 12), Vector2(x0, 18)]), line)
		"play3":
			for x0 in [1.0, 8.5, 16.0]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, 7), Vector2(x0 + 7, 12), Vector2(x0, 17)]), line)
		"spring":
			for k in 5:
				var a := -PI / 2 + k * TAU / 5
				_ring(ci, Vector2(12, 12) + Vector2(cos(a), sin(a)) * 4.6, 3.6, Color("eab0bd"), Color(line, 0.6), 1.0)
			ci.draw_circle(Vector2(12, 12), 2, Color("e6c565"))
		"summer":
			_ring(ci, Vector2(12, 12), 5, Color("e6b84a"), Color(0, 0, 0, 0))
			for k in 8:
				var a := k * TAU / 8
				_pl(ci, [Vector2(12, 12) + Vector2(cos(a), sin(a)) * 7.5, Vector2(12, 12) + Vector2(cos(a), sin(a)) * 10], Color("e6b84a"), 1.6)
		"autumn":
			_shape(ci, [Vector2(12, 3), Vector2(14.5, 8), Vector2(20, 7), Vector2(17, 12), Vector2(21, 15), Vector2(14.5, 15), Vector2(12, 20),
				Vector2(9.5, 15), Vector2(3, 15), Vector2(7, 12), Vector2(4, 7), Vector2(9.5, 8)], Color("cf7a3c"), Color(0, 0, 0, 0))
			_pl(ci, [Vector2(12, 7), Vector2(12, 22)], Color("7a3e1c"), 1.2)
		"winter":
			var sc := Color("dfe8ee")
			_pl(ci, [Vector2(12, 3), Vector2(12, 21)], sc, 1.6)
			_pl(ci, [Vector2(4.2, 7.5), Vector2(19.8, 16.5)], sc, 1.6)
			_pl(ci, [Vector2(4.2, 16.5), Vector2(19.8, 7.5)], sc, 1.6)
			_pl(ci, [Vector2(10, 4.8), Vector2(12, 6.6), Vector2(14, 4.8)], sc, 1.2)
			_pl(ci, [Vector2(10, 19.2), Vector2(12, 17.4), Vector2(14, 19.2)], sc, 1.2)
		"gov":
			_shape(ci, [Vector2(7, 15), Vector2(7, 9.5), Vector2(8.2, 6.8), Vector2(10, 5.4), Vector2(12, 5), Vector2(14, 5.4), Vector2(15.8, 6.8), Vector2(17, 9.5), Vector2(17, 15)], Color("4a4a4a"), line, 1.3)
			_pl(ci, [Vector2(1.5, 12.5), Vector2(8.5, 12.5)], line, 1.6)
			_pl(ci, [Vector2(15.5, 12.5), Vector2(22.5, 12.5)], line, 1.6)
			_shape(ci, [Vector2(5, 15), Vector2(19, 15), Vector2(19, 18.5), Vector2(5, 18.5)], Color("6b5a44"), line, 1.3)
		"store":
			_shape(ci, [Vector2(3, 10), Vector2(12, 4), Vector2(21, 10)], Color("7a6a58"), line, 1.3)
			_shape(ci, [Vector2(5, 10), Vector2(19, 10), Vector2(19, 20), Vector2(5, 20)], Color("c9b48a"), line, 1.3)
			_shape(ci, [Vector2(10, 20), Vector2(10, 15), Vector2(14, 15), Vector2(14, 20)], Color("6b5a44"), line, 1.2)
		"route":
			_shape(ci, [Vector2(2.5, 15), Vector2(21.5, 15), Vector2(18.5, 19.5), Vector2(5.5, 19.5)], Color("8c6a48"), line, 1.3)
			_shape(ci, [Vector2(12, 4.5), Vector2(18.5, 13), Vector2(12, 13)], Color("e7dcc4"), line, 1.3)
			_pl(ci, [Vector2(12, 3.5), Vector2(12, 15)], line, 1.3)
		"chart":
			_shape(ci, [Vector2(4, 3.5), Vector2(16.5, 3.5), Vector2(20, 7), Vector2(20, 20.5), Vector2(4, 20.5)], Color("e7dcc4"), line, 1.3)
			_pl(ci, [Vector2(6.5, 16.5), Vector2(10, 12.5), Vector2(13, 15), Vector2(17.5, 9)], ZHU, 1.6)
		"menu":
			for y in [7.0, 12.0, 17.0]:
				_pl(ci, [Vector2(5, y), Vector2(19, y)], line, 1.7)
		"road":
			_shape(ci, [Vector2(2, 18), Vector2(9, 6), Vector2(15, 6), Vector2(22, 18)], Color("b39468"), line, 1.3)
			for seg in [[7.5, 9.7], [11.8, 14.2], [16.3, 18.0]]:
				_pl(ci, [Vector2(12, seg[0]), Vector2(12, seg[1])], IVORY, 1.5)
		"zone":
			_shape(ci, [Vector2(12, 3), Vector2(21, 8), Vector2(12, 13), Vector2(3, 8)], ZONE[1], line, 1.2)
			_pl(ci, [Vector2(3, 12.5), Vector2(12, 17.5), Vector2(21, 12.5)], line, 1.2)
			_pl(ci, [Vector2(3, 16.5), Vector2(12, 21.5), Vector2(21, 16.5)], Color(line, 0.6), 1.2)
		"civic":
			_shape(ci, [Vector2(5, 11), Vector2(19, 11), Vector2(19, 20), Vector2(5, 20)], Color("8a7c6a"), line, 1.3)
			_pl(ci, [Vector2(6, 4), Vector2(6, 11)], line, 1.5)
			_pl(ci, [Vector2(18, 4), Vector2(18, 11)], line, 1.5)
			_pl(ci, [Vector2(4, 7.5), Vector2(20, 7.5)], line, 1.5)
			_pl(ci, [Vector2(12, 7.5), Vector2(12, 12)], line, 1.2)
			var e := []
			for k in 16:
				var a := k * TAU / 16
				e.append(Vector2(12 + cos(a) * 7, 11 + sin(a) * 2))
			_shape(ci, e, Color("6f9fb0"), line, 1.2)
		"industry":
			_shape(ci, [Vector2(4, 13), Vector2(17, 13), Vector2(15, 16), Vector2(6, 16)], Color("5e5e62"), line, 1.3)
			_shape(ci, [Vector2(8, 16), Vector2(13, 16), Vector2(13, 20), Vector2(8, 20)], Color("5e5e62"), line, 1.3)
			_shape(ci, [Vector2(14, 4.5), Vector2(19, 9.5), Vector2(17, 11.5), Vector2(12, 6.5)], Color("a58655"), line, 1.2)
			_pl(ci, [Vector2(15, 9.5), Vector2(9, 15.5)], line, 1.8)
		"transport":
			_shape(ci, [Vector2(11, 11), Vector2(19, 11), Vector2(19, 15.5), Vector2(11, 15.5)], Color("a07a50"), line, 1.3)
			_ring(ci, Vector2(8, 16), 4, Color(0, 0, 0, 0), line, 1.5)
			_pl(ci, [Vector2(8, 12), Vector2(8, 20)], line, 1.0)
			_pl(ci, [Vector2(4, 16), Vector2(12, 16)], line, 1.0)
			_pl(ci, [Vector2(3, 11), Vector2(18, 11), Vector2(20.5, 8)], line, 1.5)
		"deco":
			_shape(ci, [Vector2(2.5, 9.5), Vector2(7, 7.6), Vector2(12, 3), Vector2(17, 7.6), Vector2(21.5, 9.5)], Color("3f6b55"), line, 1.3)
			_pl(ci, [Vector2(6, 9.5), Vector2(6, 19.5)], line, 1.5)
			_pl(ci, [Vector2(18, 9.5), Vector2(18, 19.5)], line, 1.5)
			_pl(ci, [Vector2(3.5, 19.5), Vector2(20.5, 19.5)], line, 1.5)
			_pl(ci, [Vector2(6, 13), Vector2(18, 13)], ZHU, 1.5)
		"layer":
			_shape(ci, [Vector2(12, 4), Vector2(21, 8.5), Vector2(12, 13), Vector2(3, 8.5)], Color("e6c565"), line, 1.2)
			_pl(ci, [Vector2(3, 12.5), Vector2(12, 17), Vector2(21, 12.5)], line, 1.2)
			_pl(ci, [Vector2(3, 16.5), Vector2(12, 21), Vector2(21, 16.5)], line, 1.2)
		"check":
			_pl(ci, [Vector2(4, 12.6), Vector2(6.3, 14.4), Vector2(8.3, 17.4), Vector2(13, 10), Vector2(20, 4.4)], GOOD, 2.6)
		"cross":
			_pl(ci, [Vector2(6, 6), Vector2(18, 18)], BAD, 2.4)
			_pl(ci, [Vector2(18, 6), Vector2(6, 18)], BAD, 2.4)
		"todo":
			_ring(ci, Vector2(12, 12), 6.5, Color(0, 0, 0, 0), INK_3, 1.6)
		"locate":
			_ring(ci, Vector2(12, 12), 6.5, Color(0, 0, 0, 0), line, 1.5)
			for d in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
				_pl(ci, [Vector2(12, 12) + d * 4.5, Vector2(12, 12) + d * 9.5], line, 1.5)
		"good":
			ci.draw_circle(Vector2(12, 12), 8, GOOD)
			_pl(ci, [Vector2(8, 12.3), Vector2(10.7, 15), Vector2(16.4, 9)], Color("f3ecda"), 2.0)
		"bad":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(12, 3), Vector2(21.5, 20), Vector2(2.5, 20)]), BAD)
			_pl(ci, [Vector2(12, 9), Vector2(12, 14.5)], Color("f3ecda"), 2.2)
			ci.draw_circle(Vector2(12, 17.3), 1.2, Color("f3ecda"))
		"note":
			ci.draw_circle(Vector2(12, 12), 8, INK_2)
			ci.draw_circle(Vector2(12, 8.2), 1.2, Color("f3ecda"))
			_pl(ci, [Vector2(12, 11), Vector2(12, 16.5)], Color("f3ecda"), 2.2)
		"hint":
			_pl(ci, [Vector2(9, 18), Vector2(15, 18)], line, 1.5)
			_pl(ci, [Vector2(10, 21), Vector2(14, 21)], line, 1.5)
			var b := []
			for k in 13:
				var a := PI * 0.8 - k * PI * 1.6 / 12.0
				b.append(Vector2(12, 9) + Vector2(cos(a), -sin(a)) * 6)
			b.append(Vector2(15.5, 16))
			b.append(Vector2(8.5, 16))
			_shape(ci, b, Color("e6c565"), line, 1.3)
		"bookmark":
			_shape(ci, [Vector2(6, 3), Vector2(18, 3), Vector2(18, 21), Vector2(12, 16.5), Vector2(6, 21)], Color("c9b48a"), line, 1.3)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ───────────────────────── 工具縮圖 ─────────────────────────

## 道路、分區等非建築工具之縮圖。c 為地塊中心。
static func tool_thumb(ci: CanvasItem, id: String, c: Vector2, s: float) -> void:
	var dia := func(col: Color, line: Color) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -16) * s, c + Vector2(32, 0) * s, c + Vector2(0, 16) * s, c + Vector2(-32, 0) * s])
		if col.a > 0:
			ci.draw_colored_polygon(pts, col)
		pts.append(pts[0])
		ci.draw_polyline(pts, line, 1.2, true)
	match id:
		"road_dirt":
			dia.call(Color("b99a6c"), Color("8a6e48"))
			ci.draw_line(c + Vector2(-20, -6) * s, c + Vector2(20, 6) * s, Color("d4bb8e"), 2.0)
		"road_stone":
			dia.call(Color("a7a197"), Color("6f6a62"))
			for k in 4:
				ci.draw_rect(Rect2(c + Vector2(-12 + k * 8, -4 + k * 2.6) * s, Vector2(6, 3) * s), Color("c9c3b8"))
		"canal":
			dia.call(Color("7fa1a6"), Color("4d7277"))
			ci.draw_line(c + Vector2(-12, -2) * s, c + Vector2(0, 2) * s, Color(1, 1, 1, 0.5), 1.2)
		"wall":
			dia.call(Color(0, 0, 0, 0), Color("8b7d6e"))
			var p := c + Vector2(-20, 0) * s
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -2) * s, p + Vector2(40, -2) * s, p + Vector2(40, -14) * s, p + Vector2(0, -16) * s]), Color("8f8a82"))
			for k in 5:
				ci.draw_rect(Rect2(p + Vector2(2 + k * 8, -20) * s, Vector2(4, 4) * s), Color("7a756e"))
		"bulldoze":
			seal_outline(ci, Rect2(c - Vector2(15, 15), Vector2(30, 30)), "拆")
		"route":
			var a := c + Vector2(-22, 6) * s
			var b := c + Vector2(22, -6) * s
			for k in 7:
				if k % 2 == 0:
					ci.draw_line(a.lerp(b, k / 7.0), a.lerp(b, (k + 1) / 7.0), SHIQING, 2.0)
			ci.draw_circle(a, 4.0, ZHU)
			ci.draw_circle(b, 4.0, ZHU)
		_:
			if id.begins_with("zone_"):
				var z := int(id.substr(5))
				if z == 0:
					dia.call(Color(0, 0, 0, 0), INK_3)
					ci.draw_line(c + Vector2(-10, -5) * s, c + Vector2(10, 5) * s, ZHU, 1.6)
				else:
					var col: Color = ZONE[z]
					dia.call(Color(col, 0.8), col.darkened(0.3))
					text_c(ci, font("title"), c, Defs.ZONE_NAMES[z].substr(0, 1), int(16 * s + 4), INK)
