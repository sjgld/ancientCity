extends Control
## 看卷：全螢幕把一卷長卷鋪在漆木案上，先由右往左展開，再以滾輪、拖曳、方向鍵一段一段地看。
## 兩端畫成捲起的軸，粗細隨未看部分的長短變化；底部縮圖可點選跳轉。

const UIArt = preload("res://scripts/ui/ui_art.gd")

var ui
var index := 0
var tex: Texture2D
var img_size := Vector2.ONE
var ox := 0.0           # 目前畫面左緣在原圖中的 x
var target_ox := 0.0
var open_t := 0.0       # 開卷動畫進度 0..1
var dragging := false
var mini_drag := false
var saved_speed := 1
var btn_row: HBoxContainer
var prev_btn: Button
var next_btn: Button
const OPEN_TIME := 1.4
const MARGIN := 70.0
const ROD := 18.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _ready() -> void:
	saved_speed = Game.speed
	Game.speed = 0
	btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	add_child(btn_row)
	prev_btn = ui._button("上一卷", func(): _show(index - 1), "較早的一卷")
	next_btn = ui._button("下一卷", func(): _show(index + 1), "較晚的一卷")
	btn_row.add_child(prev_btn)
	btn_row.add_child(next_btn)
	btn_row.add_child(ui._button("存為圖片", _export, "把整卷存成 PNG 圖片"))
	btn_row.add_child(ui._button("收卷", close, "Esc"))
	grab_focus()
	_show(index)


func _show(k: int) -> void:
	if k < 0 or k >= Game.scrolls.size():
		return
	index = k
	var e: Dictionary = Game.scrolls[k]
	var img := Image.load_from_file(e.file)
	if img == null or img.is_empty():
		ui.toast("找不到這一卷的圖檔", true)
		return
	img.generate_mipmaps()
	tex = ImageTexture.create_from_image(img)
	img_size = Vector2(img.get_size())
	open_t = 0.0
	ox = maxf(0.0, img_size.x - _view_w() / _scale())
	target_ox = ox
	prev_btn.disabled = k <= 0
	next_btn.disabled = k >= Game.scrolls.size() - 1
	Sfx.play("click")
	queue_redraw()


func close() -> void:
	Game.speed = saved_speed
	ui.scroll_viewer = null
	queue_free()


# ───────────────────────── 版面 ─────────────────────────

func _disp_h() -> float:
	return minf(size.y * 0.62, img_size.y)


func _scale() -> float:
	return _disp_h() / img_size.y


func _view_w() -> float:
	return size.x - MARGIN * 2.0


func _top() -> float:
	return (size.y - _disp_h()) * 0.46


func _max_ox() -> float:
	return maxf(0.0, img_size.x - _view_w() / _scale())


func _mini_rect() -> Rect2:
	var w := minf(size.x * 0.6, 900.0)
	var h := clampf(w / (img_size.x / img_size.y), 18.0, 60.0)
	w = h * img_size.x / img_size.y
	return Rect2((size.x - w) * 0.5, _top() + _disp_h() + 44.0, w, h)


# ───────────────────────── 輸入 ─────────────────────────

func _process(delta: float) -> void:
	btn_row.reset_size()
	btn_row.position = Vector2(size.x - MARGIN - btn_row.size.x, maxf(16.0, _top() - btn_row.size.y - 30.0))
	if open_t < 1.0:
		open_t = minf(1.0, open_t + delta / OPEN_TIME)
		queue_redraw()
		return
	target_ox = clampf(target_ox, 0.0, _max_ox())
	if absf(target_ox - ox) > 0.5:
		ox = lerpf(ox, target_ox, minf(1.0, delta * 10.0))
		queue_redraw()
	elif ox != target_ox:
		ox = target_ox
		queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		var step := _view_w() / _scale() * 0.18
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
			target_ox -= step
			open_t = 1.0
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
			target_ox += step
			open_t = 1.0
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed:
				dragging = false
				mini_drag = false
			elif _mini_rect().grow(6).has_point(mb.position):
				mini_drag = true
				_mini_jump(mb.position.x)
			else:
				dragging = true
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if mini_drag:
			_mini_jump(mm.position.x)
		elif dragging:
			open_t = 1.0
			target_ox -= mm.relative.x / _scale()
			ox = target_ox
			queue_redraw()
		accept_event()


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed:
		return
	var step := _view_w() / _scale() * 0.6
	match k.keycode:
		KEY_ESCAPE:
			close()
		KEY_LEFT, KEY_A:
			target_ox -= step
			open_t = 1.0
		KEY_RIGHT, KEY_D:
			target_ox += step
			open_t = 1.0
		KEY_HOME:
			target_ox = _max_ox()
		KEY_END:
			target_ox = 0.0
		_:
			return
	get_viewport().set_input_as_handled()


func _mini_jump(x: float) -> void:
	var mr := _mini_rect()
	var f := clampf((x - mr.position.x) / mr.size.x, 0.0, 1.0)
	open_t = 1.0
	target_ox = clampf(f * img_size.x - _view_w() / _scale() * 0.5, 0.0, _max_ox())


func _export() -> void:
	var e: Dictionary = Game.scrolls[index]
	var img := Image.load_from_file(e.file)
	if img == null:
		ui.toast("存圖失敗", true)
		return
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "" or OS.has_environment("SCROLL_EXPORT_DIR"):
		dir = OS.get_environment("SCROLL_EXPORT_DIR") if OS.has_environment("SCROLL_EXPORT_DIR") else OS.get_user_data_dir()
	dir = dir.path_join("水村山郭")
	DirAccess.make_dir_recursive_absolute(dir)
	var name: String = "%s_%s.png" % [e.title, e.date]
	var path := dir.path_join(name)
	if img.save_png(path) != OK:
		ui.toast("存圖失敗", true)
		return
	ui.toast("已存至 %s" % path)
	if DisplayServer.get_name() != "headless" and not OS.has_environment("SCROLL_EXPORT_DIR"):
		OS.shell_show_in_file_manager(path)


# ───────────────────────── 畫 ─────────────────────────

func _draw() -> void:
	# 漆木案
	draw_rect(Rect2(Vector2.ZERO, size), UIArt.WOOD_D)
	draw_texture_rect(UIArt.wood_tex(), Rect2(Vector2.ZERO, size), true, Color(1, 1, 1, 0.5))
	if tex == null:
		return
	var s := _scale()
	var dh := _disp_h()
	var top := _top()
	var vw := _view_w()
	var e: Dictionary = Game.scrolls[index]
	# 卷名
	var tf := UIArt.font("title")
	UIArt.text_l(self, tf, MARGIN, top - 50.0, e.title, 30, UIArt.IVORY)
	var tw := tf.get_string_size(e.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	UIArt.text_l(self, UIArt.font("body"), MARGIN + tw + 16.0, top - 47.0,
		"%s　第%s卷，共%s卷" % [e.date, Defs.cn_big(index + 1), Defs.cn_big(Game.scrolls.size())], 16, UIArt.IVORY_2)
	# 開卷：展開的寬度由右往左增加
	var ease := 1.0 - pow(1.0 - open_t, 3.0)
	var shown := minf(vw, img_size.x * s) * ease if open_t < 1.0 else minf(vw, img_size.x * s)
	var right := MARGIN + minf(vw, img_size.x * s) + (vw - minf(vw, img_size.x * s)) * 0.5
	var left := right - shown
	var src_x := ox if open_t >= 1.0 else img_size.x - shown / s
	# 陰影與卷面
	draw_rect(Rect2(left + 4, top + 7, shown, dh), Color(0, 0, 0, 0.45))
	if shown > 1.0:
		draw_texture_rect_region(tex, Rect2(left, top, shown, dh), Rect2(src_x, 0, shown / s, img_size.y))
	# 兩端的軸：已看過的捲在右，未看的捲在左，粗細隨長度
	var rest_l := src_x / img_size.x
	var rest_r := (img_size.x - src_x - shown / s) / img_size.x
	_rod(left, top, dh, rest_l)
	_rod(right, top, dh, rest_r)
	# 縮圖與目前位置
	var mr := _mini_rect()
	draw_rect(mr.grow(2), Color(0, 0, 0, 0.4))
	draw_texture_rect(tex, mr, false, Color(1, 1, 1, 0.85))
	var fx := mr.position.x + src_x / img_size.x * mr.size.x
	var fw := shown / s / img_size.x * mr.size.x
	draw_rect(Rect2(fx, mr.position.y - 3, fw, mr.size.y + 6), UIArt.GOLD, false, 2.0)
	UIArt.text_c(self, UIArt.font("body"), Vector2(size.x * 0.5, mr.end.y + 24.0),
		"手卷由右往左看　滾輪、拖曳或 ← → 展卷　點縮圖跳轉　Esc 收卷", 14, UIArt.IVORY_2)


## 捲起的軸：木桿加上捲起的紙，rest 為該側未展開部分佔全卷的比例。
func _rod(x: float, top: float, dh: float, rest: float) -> void:
	var w := ROD + 26.0 * clampf(rest, 0.0, 1.0)
	var paper := Rect2(x - w * 0.5, top - 4.0, w, dh + 8.0)
	# 捲起的紙：由亮到暗幾條，像圓柱
	var cols := [Color("b8a77f"), Color("d9c9a2"), Color("efe2c0"), Color("d5c49c"), Color("a99671")]
	var n := cols.size()
	for k in n:
		draw_rect(Rect2(paper.position.x + paper.size.x * k / n, paper.position.y, paper.size.x / n + 0.5, paper.size.y), cols[k])
	# 木桿露出上下兩頭
	for yy in [top - 18.0, top + dh + 4.0]:
		var rr := Rect2(x - ROD * 0.35, yy, ROD * 0.7, 14.0)
		draw_rect(rr, Color("5b4330"))
		draw_rect(Rect2(rr.position.x + rr.size.x * 0.25, rr.position.y, rr.size.x * 0.2, rr.size.y), Color("7d5f45"))
