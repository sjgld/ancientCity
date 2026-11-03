extends CanvasLayer
## 介面：頂欄、工具列、資訊欄、邸報、各式視窗與開場畫面。

var main
var root: Control
var top_city: Label
var top_date: Label
var top_money: Label
var top_pop: Label
var top_happy: Label
var top_food: Label
var demand: DemandBars
var speed_btns: Array = []
var palette_wrap: CenterContainer
var palette: HBoxContainer
var cat_btns := {}
var cur_cat := ""
var tool_group := ButtonGroup.new()
var info_panel: PanelContainer
var info_title: Label
var info_body: RichTextLabel
var info_btns: HBoxContainer
var log_box: RichTextLabel
var toast_panel: PanelContainer
var toast_label: Label
var toast_t := 0.0
var windows := {}
var win_bodies := {}
var cur_win := ""
var title_root: Control
var name_edit: LineEdit
var seed_edit: LineEdit
var load_btn: Button
var refresh_t := 0.0
var bold_font: SystemFont
var top_panel: PanelContainer
var bottom_v: VBoxContainer
var log_panel: PanelContainer
var quest_panel: PanelContainer
var quest_box: RichTextLabel
var minimap: MiniMap
var mini_panel: PanelContainer
var hover_tip: PanelContainer
var hover_label: Label
var chart: Chart
var music_btn: Button

const INK := Color(0.22, 0.14, 0.09)
const VERM := Color(0.66, 0.2, 0.15)


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top()
	_build_bottom()
	_build_info()
	_build_log()
	_build_quests()
	_build_minimap()
	_build_toast()
	_build_hover()
	_build_windows()
	_build_title()
	Game.message.connect(_on_message)
	Game.rank_changed.connect(_on_rank)
	Game.month_passed.connect(func(): main.world.overlay.queue_redraw())
	Game.quest_done.connect(func(_id): Sfx.play("coin"))


# ───────────────────────── 樣式 ─────────────────────────

func _sb(bg: Color, border: Color, bw: int, radius: int, mx: int = 8, my: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = Defs.font
	th.default_font_size = 16
	bold_font = SystemFont.new()
	bold_font.font_names = Defs.font.font_names
	bold_font.font_weight = 700
	var paper := _sb(Color(0.95, 0.91, 0.81, 0.96), Color(0.45, 0.3, 0.18), 2, 6, 12, 8)
	paper.shadow_color = Color(0, 0, 0, 0.25)
	paper.shadow_size = 5
	th.set_stylebox("panel", "PanelContainer", paper)
	th.set_stylebox("panel", "TooltipPanel", _sb(Color(0.98, 0.95, 0.86), Color(0.45, 0.3, 0.18), 1, 4, 8, 6))
	th.set_color("font_color", "TooltipLabel", INK)
	var bn := _sb(Color(0.89, 0.82, 0.67), Color(0.55, 0.4, 0.25), 1, 4)
	var bh := _sb(Color(0.97, 0.92, 0.78), Color(0.6, 0.42, 0.25), 1, 4)
	var bp := _sb(VERM, Color(0.4, 0.1, 0.06), 1, 4)
	var bd := _sb(Color(0.82, 0.79, 0.72, 0.7), Color(0.65, 0.6, 0.55), 1, 4)
	th.set_stylebox("normal", "Button", bn)
	th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", bp)
	th.set_stylebox("hover_pressed", "Button", bp)
	th.set_stylebox("disabled", "Button", bd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_focus_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", Color(1, 0.96, 0.88))
	th.set_color("font_hover_pressed_color", "Button", Color(1, 0.96, 0.88))
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.46, 0.42))
	th.set_color("font_color", "Label", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_font("bold_font", "RichTextLabel", bold_font)
	th.set_stylebox("normal", "LineEdit", _sb(Color(1, 0.98, 0.92), Color(0.55, 0.4, 0.25), 1, 3, 8, 4))
	th.set_stylebox("focus", "LineEdit", _sb(Color(1, 0.98, 0.92), VERM, 2, 3, 8, 4))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_color", "CheckButton", INK)
	th.set_color("font_hover_color", "CheckButton", INK)
	th.set_color("font_pressed_color", "CheckButton", VERM)
	th.set_color("font_hover_pressed_color", "CheckButton", VERM)
	th.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("hover_pressed", "CheckButton", StyleBoxEmpty.new())
	return th


func _label(text: String, size: int = 16, col: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.pressed.connect(func(): Sfx.play("click"))
	b.pressed.connect(cb)
	return b


# ───────────────────────── 頂欄 ─────────────────────────

func _build_top() -> void:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	p.offset_left = 8
	p.offset_right = -8
	p.offset_top = 6
	root.add_child(p)
	top_panel = p
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var seal := PanelContainer.new()
	seal.add_theme_stylebox_override("panel", _sb(VERM, Color(0.4, 0.08, 0.05), 2, 3, 10, 2))
	top_city = _label("", 20, Color(1, 0.95, 0.85))
	seal.add_child(top_city)
	h.add_child(seal)
	top_date = _label("", 17)
	h.add_child(top_date)
	top_money = _label("", 17)
	top_money.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(top_money)
	top_pop = _label("", 17)
	top_pop.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(top_pop)
	top_happy = _label("", 17)
	h.add_child(top_happy)
	top_food = _label("", 17)
	top_food.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(top_food)
	demand = DemandBars.new()
	demand.tooltip_text = "需求：民居、市肆、作坊、農田"
	h.add_child(demand)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	var names := ["❚❚", "▶", "▶▶", "▶▶▶"]
	var g := ButtonGroup.new()
	for k in 4:
		var b := _button(names[k], set_speed.bind(k), ["暫停（空白鍵）", "常速（1）", "二倍速（2）", "四倍速（3）"][k])
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(44, 0)
		h.add_child(b)
		speed_btns.append(b)
	h.add_child(_button("倉儲", open_window.bind("stock"), "城中各色貨物存量"))
	h.add_child(_button("政務", open_window.bind("policy"), "稅率、政令、收支"))
	h.add_child(_button("路線", open_window.bind("routes"), "貨運路線與車船"))
	h.add_child(_button("存檔", _save, "F5"))
	h.add_child(_button("統計", open_window.bind("stats"), "人丁、銀兩、民心之歷年走勢"))
	h.add_child(_button("說明", open_window.bind("help")))
	music_btn = _button("樂", _toggle_music, "配樂開關")
	music_btn.toggle_mode = true
	music_btn.button_pressed = true
	h.add_child(music_btn)
	h.add_child(_button("返回", func(): show_title(true), "回到開場畫面"))


func _toggle_music() -> void:
	Sfx.set_music(music_btn.button_pressed)


func _save() -> void:
	toast("已存檔" if Game.save_game() else "存檔失敗")


func _close_info() -> void:
	main.selected = -1
	main.selected_tile = Vector2i(-1, -1)
	show_info()


func set_speed(k: int) -> void:
	Game.speed = k
	speed_btns[k].button_pressed = true


func _update_top() -> void:
	var s: Dictionary = Game.stats
	top_city.text = "%s · %s" % [Game.city_name, Game.rank_name()]
	top_date.text = Game.date_str()
	top_money.text = "銀 %s 兩" % _fmt(int(Game.money))
	top_money.add_theme_color_override("font_color", VERM if Game.money < 0 else INK)
	var net: float = Game.report.get("net", 0.0)
	top_money.tooltip_text = "上月結餘：%+d 兩" % int(net)
	var nxt := ""
	if Game.rank < Defs.RANKS.size() - 1:
		nxt = " / %d" % Defs.RANKS[Game.rank + 1]["pop"]
	top_pop.text = "人丁 %d%s" % [s.pop, nxt]
	top_pop.tooltip_text = "勞力 %d　職缺 %d　失業 %d%%\n人丁達標可晉升品級" % [s.labor, s.jobs, int(s.unemp * 100)]
	top_happy.text = "民心 %d" % int(s.happy)
	top_happy.add_theme_color_override("font_color", VERM if s.happy < 40 else (Color(0.2, 0.45, 0.2) if s.happy >= 65 else INK))
	var food: float = Game.stock.get("grain", 0.0) + Game.stock.get("fish", 0.0)
	top_food.text = "糧 %d" % int(food)
	top_food.tooltip_text = "糧倉容量 %d　每月食用約 %d" % [int(Game.cap_of("grain")), int(s.pop * 0.2)]
	top_food.add_theme_color_override("font_color", VERM if Game.food_short > 0.1 else INK)
	demand.vals = [s.dR, s.dC, s.dI, s.dF]
	demand.queue_redraw()
	if not speed_btns[Game.speed].button_pressed:
		speed_btns[Game.speed].button_pressed = true


static func _fmt(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


# ───────────────────────── 工具列 ─────────────────────────

func _build_bottom() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(v)
	bottom_v = v
	palette_wrap = CenterContainer.new()
	palette_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(palette_wrap)
	var pp := PanelContainer.new()
	palette_wrap.add_child(pp)
	palette = HBoxContainer.new()
	palette.add_theme_constant_override("separation", 6)
	pp.add_child(palette)
	palette_wrap.visible = false
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cc)
	var bar := PanelContainer.new()
	cc.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	bar.add_child(h)
	var cats: Array = Defs.CATEGORIES.duplicate()
	cats.append({"id": "view", "name": "圖層"})
	var g := ButtonGroup.new()
	g.allow_unpress = true
	for c in cats:
		var b := _button(c.name, _on_cat.bind(c.id))
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(76, 42)
		b.add_theme_font_size_override("font_size", 19)
		h.add_child(b)
		cat_btns[c.id] = b
	tool_group.allow_unpress = true


func _on_cat(id: String) -> void:
	if cur_cat == id:
		cur_cat = ""
		palette_wrap.visible = false
		return
	cur_cat = id
	_fill_palette()


func _fill_palette() -> void:
	for c in palette.get_children():
		c.queue_free()
	if cur_cat == "":
		palette_wrap.visible = false
		return
	palette_wrap.visible = true
	var items := []
	match cur_cat:
		"road":
			for t in Defs.ROAD_TOOLS:
				items.append({"id": t.id, "name": t.name, "cost": t.get("cost", -1), "rank": t.rank, "desc": t.desc})
		"zone":
			for t in Defs.ZONE_TOOLS:
				items.append({"id": t.id, "name": t.name, "cost": -1, "rank": t.rank, "desc": t.desc})
		"view":
			for m in [["", "無"], ["lv", "地價"], ["water", "水源"], ["security", "治安"], ["health", "醫療"], ["fire", "防火"],
					["edu", "教化"], ["faith", "信仰"], ["fun", "娛樂"], ["market", "市集"], ["pollution", "煙塵"], ["fert", "肥力"], ["conn", "通達"]]:
				var b := _button(m[1], _on_view.bind(m[0]))
				b.toggle_mode = true
				b.button_pressed = main.world.overlay.mode == m[0]
				b.custom_minimum_size = Vector2(56, 40)
				palette.add_child(b)
			return
		_:
			for k in Defs.B:
				var d: Dictionary = Defs.B[k]
				if d.cat == cur_cat:
					var desc: String = d.desc
					if d.has("produce"):
						var parts := []
						for c in d.produce:
							parts.append("%s %d" % [Defs.cargo_name(c), int(d.produce[c])])
						desc += "\n每月產出：%s　職缺 %d" % ["、".join(parts), d.get("jobs", 0)]
					if d.has("cover"):
						desc += "\n影響半徑：%d 格" % int(d.cover.values()[0])
					desc += "\n每月維護：%d 兩" % d.upkeep
					items.append({"id": "b:" + k, "name": d.name, "cost": d.cost, "rank": d.rank, "desc": desc})
			if cur_cat == "transport":
				items.append({"id": "route", "name": "開闢路線", "cost": -1, "rank": 0,
					"desc": "先點起點、再點終點（驛站、碼頭或外邑），即購一輛車船往返載貨。"})
	for it in items:
		var locked: bool = it.rank > Game.rank
		var txt: String = it.name
		if locked:
			txt += "\n（%s）" % Defs.RANKS[it.rank]["name"]
		elif it.cost > 0:
			txt += "\n%d 兩" % it.cost
		var b := _button(txt, _on_tool.bind(it.id), it.desc)
		b.toggle_mode = true
		b.button_group = tool_group
		b.disabled = locked
		b.button_pressed = main.tool == it.id
		b.custom_minimum_size = Vector2(70, 50)
		b.add_theme_font_size_override("font_size", 15)
		palette.add_child(b)


func _on_tool(id: String) -> void:
	if main.tool == id:
		main.set_tool("")
		clear_tool()
	else:
		main.set_tool(id)


func _on_view(mode: String) -> void:
	main.world.overlay.mode = mode
	main.world.overlay.queue_redraw()
	_fill_palette()


func pick_tool(id: String) -> void:
	main.set_tool(id)
	for b in palette.get_children():
		if b is Button:
			b.button_pressed = false


func clear_tool() -> void:
	var p := tool_group.get_pressed_button()
	if p:
		p.button_pressed = false


func _on_rank(_r: int) -> void:
	_fill_palette()
	Sfx.play("gong")
	banner("聖旨：晉為「%s」" % Game.rank_name())


# ───────────────────────── 資訊欄 ─────────────────────────

func _build_info() -> void:
	info_panel = PanelContainer.new()
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.offset_left = -350
	info_panel.offset_right = -8
	info_panel.offset_top = 64
	info_panel.custom_minimum_size = Vector2(340, 0)
	root.add_child(info_panel)
	var v := VBoxContainer.new()
	info_panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	info_title = _label("", 22, VERM)
	info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info_title)
	h.add_child(_button("✕", _close_info))
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.fit_content = true
	info_body.scroll_active = false
	info_body.custom_minimum_size = Vector2(320, 0)
	info_body.add_theme_font_size_override("normal_font_size", 15)
	info_body.add_theme_font_size_override("bold_font_size", 15)
	v.add_child(info_body)
	info_btns = HBoxContainer.new()
	v.add_child(info_btns)
	info_panel.visible = false


func show_info() -> void:
	for c in info_btns.get_children():
		c.queue_free()
	var vid: int = main.selected_vehicle
	if vid >= 0 and Game.vehicles.has(vid):
		var v: Dictionary = Game.vehicles[vid]
		info_panel.visible = true
		info_title.text = Defs.VEHICLES[v.kind]["name"]
		info_body.text = _vehicle_text(v)
		info_btns.add_child(_button("查看路線", func(): open_window("routes")))
		info_btns.add_child(_button("賣出", func():
			Game.vehicles.erase(vid)
			Game.money += Defs.VEHICLES[v.kind]["cost"] * 0.4
			main.selected_vehicle = -1
			show_info()))
		return
	var sel: int = main.selected
	if sel >= 0 and Game.buildings.has(sel):
		var b: Dictionary = Game.buildings[sel]
		info_panel.visible = true
		info_title.text = Game.bname(b)
		if b.type == "yamen":
			info_title.text = "%s · %s" % [Game.city_name, ["里署", "鎮署", "縣衙", "州衙", "府衙", "皇城"][Game.rank]]
		info_body.text = _yamen_text() if b.type == "yamen" else Game.building_info(b)
		if Game.is_stop(b):
			info_btns.add_child(_button("由此開闢路線", func():
				main.set_tool("route")
				main.route_first = b.id
				toast("起點：%s。再點選終點。" % Game.bname(b))))
		if b.type not in ["yamen", "town"]:
			info_btns.add_child(_button("拆除", func():
				Game.bulldoze(b.x, b.y)
				main.selected = -1
				show_info()))
		return
	var t: Vector2i = main.selected_tile
	if Game.inb(t.x, t.y):
		info_panel.visible = true
		info_title.text = "地塊"
		info_body.text = Game.tile_info(t.x, t.y)
		return
	info_panel.visible = false


func _vehicle_text(v: Dictionary) -> String:
	var d: Dictionary = Defs.VEHICLES[v.kind]
	var r: Dictionary = Game.routes.get(v.route, {})
	var t := ""
	if not r.is_empty():
		t += "路線：%s ⇄ %s\n" % [Game.bname(Game.buildings[r.a]), Game.bname(Game.buildings[r.b])]
	var st := {"move": "行進中", "load": "裝卸中", "lost": "[color=#a02818]無路可通[/color]"}
	t += "狀態：%s\n" % st.get(v.state, v.state)
	if Game.buildings.has(v.to):
		t += "前往：%s\n" % Game.bname(Game.buildings[v.to])
	if v.amt > 0:
		t += "載貨：%s %d / %d\n" % [Defs.cargo_name(v.cargo), int(v.amt), d.cap]
	else:
		t += "載貨：空載（容量 %d）\n" % d.cap
	t += "速度：每日 %.1f 格　月費 %d 兩\n" % [d.speed, d.upkeep]
	return t


func _yamen_text() -> String:
	var s: Dictionary = Game.stats
	var t := "人丁：%d　戶數：%d\n" % [s.pop, s.houses]
	t += "勞力：%d　職缺：%d（到崗 %d%%）\n" % [s.labor, s.jobs, int(s.staff * 100)]
	t += "失業：%d%%　民心：%d\n" % [int(s.unemp * 100), int(s.happy)]
	t += "轄境：沿路 %d 格內\n" % Game.radius()
	if Game.rank < Defs.RANKS.size() - 1:
		var nx: Dictionary = Defs.RANKS[Game.rank + 1]
		t += "晉升「%s」尚需人丁：%d\n" % [nx.name, maxi(0, nx.pop - s.pop)]
	t += "\n[b]施政提要[/b]\n"
	var tips := []
	if s.pop < 30:
		tips.append("沿路劃設民居與農田，百姓自會遷入。")
	if Game.food_short > 0.05:
		tips.append("[color=#a03020]糧食不足[/color]：多劃農田、建漁場，並修糧倉存秋糧。")
	if s.dC > 50:
		tips.append("市肆需求高，劃設市肆。")
	if s.dI > 50:
		tips.append("作坊需求高，劃設作坊。")
	if s.unemp > 0.15:
		tips.append("失業者眾，多設市肆、作坊或產業。")
	if Game.stats.houses > 8 and Game._avg_cover_houses("water") < 0.6:
		tips.append("許多民居缺水，廣鑿水井。")
	if Game.rank >= 1 and Game._avg_cover_houses("health") < 0.5:
		tips.append("醫館不足，恐生疫病。")
	if Game.routes.is_empty() and Game.rank >= 1:
		tips.append("建驛站並開闢通往外邑的路線，以貨物換銀兩。")
	if tips.is_empty():
		tips.append("政通人和，可擴建城池、經營商路。")
	t += "・" + "\n・".join(tips)
	return t


# ───────────────────────── 邸報與提示 ─────────────────────────

func _build_log() -> void:
	var p := PanelContainer.new()
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 8
	p.offset_top = -190
	p.offset_bottom = -72
	p.offset_right = 400
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.self_modulate = Color(1, 1, 1, 0.85)
	root.add_child(p)
	log_panel = p
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(_label("邸報", 15, VERM))
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_active = false
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(log_box)


func _on_message(_text: String, kind: int) -> void:
	if kind == 2 and not main.title_mode:
		Sfx.play("bad")
	var s := ""
	var n := 0
	for l in Game.log_lines:
		var col := "#3a2a1a"
		if l.kind == 1:
			col = "#2f6a2a"
		elif l.kind == 2:
			col = "#a02818"
		s += "[color=#8a7050]%s[/color] [color=%s]%s[/color]\n" % [_short_date(l.t), col, l.text]
		n += 1
		if n >= 5:
			break
	log_box.text = s


static func _short_date(t: String) -> String:
	var parts := t.split(" ")
	return parts[0] + parts[parts.size() - 1] if parts.size() >= 3 else t


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.offset_top = 70
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_panel)
	toast_label = _label("", 18)
	toast_panel.add_child(toast_label)
	toast_panel.visible = false


func toast(text: String, bad: bool = false) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", VERM if bad else INK)
	toast_panel.visible = true
	toast_panel.reset_size()
	toast_panel.offset_left = -toast_panel.size.x * 0.5
	toast_panel.offset_right = toast_panel.size.x * 0.5
	toast_t = 2.5


func banner(text: String) -> void:
	var b := PanelContainer.new()
	b.add_theme_stylebox_override("panel", _sb(Color(0.66, 0.18, 0.13, 0.95), Color(0.95, 0.8, 0.45), 3, 8, 30, 14))
	var l := _label(text, 34, Color(1, 0.94, 0.8))
	b.add_child(l)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(b)
	b.reset_size()
	b.position = Vector2((root.size.x - b.size.x) * 0.5, root.size.y * 0.3)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(b, "modulate:a", 0.0, 1.0)
	tw.tween_callback(b.queue_free)


func typing() -> bool:
	var f := root.get_viewport().gui_get_focus_owner()
	return f is LineEdit


func _process(delta: float) -> void:
	if toast_t > 0:
		toast_t -= delta
		if toast_t <= 0:
			toast_panel.visible = false
	refresh_t -= delta
	if refresh_t <= 0:
		refresh_t = 0.4
		_update_top()
		_update_quests()
		if info_panel.visible and main.selected_vehicle >= 0:
			if Game.vehicles.has(main.selected_vehicle):
				info_body.text = _vehicle_text(Game.vehicles[main.selected_vehicle])
			else:
				main.selected_vehicle = -1
				show_info()
		elif info_panel.visible:
			var sel: int = main.selected
			if sel >= 0 and Game.buildings.has(sel):
				var b: Dictionary = Game.buildings[sel]
				info_body.text = _yamen_text() if b.type == "yamen" else Game.building_info(b)
			elif sel >= 0:
				main.selected = -1
				show_info()
		if cur_win == "stats" and chart != null:
			chart.queue_redraw()
		if cur_win in ["stock", "routes", "policy"]:
			_fill_window(cur_win)


# ───────────────────────── 視窗 ─────────────────────────

func _build_windows() -> void:
	for w in [["stock", "倉儲"], ["policy", "政務"], ["routes", "貨運路線"], ["help", "築城須知"], ["stats", "統計"]]:
		var p := PanelContainer.new()
		p.set_anchors_preset(Control.PRESET_CENTER)
		root.add_child(p)
		var v := VBoxContainer.new()
		p.add_child(v)
		var h := HBoxContainer.new()
		v.add_child(h)
		var t := _label(w[1], 24, VERM)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(_button("✕", close_windows))
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(620, 440)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sc)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 6)
		sc.add_child(body)
		p.visible = false
		windows[w[0]] = p
		win_bodies[w[0]] = body


func window_open(id: String) -> bool:
	return cur_win == id


func open_window(id: String) -> void:
	if cur_win == id:
		close_windows()
		return
	close_windows()
	cur_win = id
	var p: PanelContainer = windows[id]
	p.visible = true
	p.move_to_front()
	_fill_window(id, true)
	p.reset_size()
	p.position = (root.size - p.size) * 0.5


func close_windows() -> void:
	for k in windows:
		windows[k].visible = false
	cur_win = ""


func _clear(body: Control) -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()


func _fill_window(id: String, full: bool = false) -> void:
	var body: VBoxContainer = win_bodies[id]
	match id:
		"stock":
			_clear(body)
			for c in Defs.CARGO_ORDER:
				var h := HBoxContainer.new()
				body.add_child(h)
				var sw := ColorRect.new()
				sw.color = Defs.CARGO[c]["color"]
				sw.custom_minimum_size = Vector2(16, 16)
				h.add_child(sw)
				var l := _label("%s" % Defs.cargo_name(c), 17)
				l.custom_minimum_size = Vector2(70, 0)
				h.add_child(l)
				var cap := Game.cap_of(c)
				var pb := ProgressBar.new()
				pb.max_value = cap
				pb.value = Game.stock.get(c, 0.0)
				pb.show_percentage = false
				pb.custom_minimum_size = Vector2(300, 18)
				pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(pb)
				h.add_child(_label("%d / %d　（價 %d）" % [int(Game.stock.get(c, 0.0)), int(cap), int(Defs.CARGO[c]["price"])], 15))
			body.add_child(_rich("\n[color=#6a5040]作坊以絲織綢緞，以鐵、木製器物；市肆售器物綢緞瓷器茶葉；宅院需奢侈品。\n存量過半之貨物，驛站與碼頭方可外運。糧倉、貨棧可擴充容量。[/color]"))
		"policy":
			if not full:
				_update_budget(body)
				return
			_clear(body)
			body.add_child(_label("稅率", 19, VERM))
			for k in [["res", "戶稅"], ["com", "商稅"], ["ind", "工稅"], ["farm", "田賦"]]:
				var h := HBoxContainer.new()
				body.add_child(h)
				var l := _label(k[1], 16)
				l.custom_minimum_size = Vector2(60, 0)
				h.add_child(l)
				var s := HSlider.new()
				s.min_value = 0
				s.max_value = 25
				s.step = 1
				s.value = Game.tax[k[0]]
				s.custom_minimum_size = Vector2(300, 20)
				s.focus_mode = Control.FOCUS_NONE
				h.add_child(s)
				var vl := _label("%d%%" % Game.tax[k[0]], 16)
				h.add_child(vl)
				s.value_changed.connect(func(val):
					Game.tax[k[0]] = int(val)
					vl.text = "%d%%" % int(val))
			body.add_child(_rich("[color=#6a5040]戶稅過一成則民心漸失。[/color]"))
			body.add_child(_label("政令", 19, VERM))
			for p in Defs.POLICIES:
				var d: Dictionary = Defs.POLICIES[p]
				var cb := CheckButton.new()
				cb.text = "%s — %s（月費 %d 兩）%s" % [d.name, d.desc, d.upkeep, "" if d.rank <= Game.rank else "　需「%s」" % Defs.RANKS[d.rank]["name"]]
				cb.button_pressed = Game.policies.has(p)
				cb.disabled = d.rank > Game.rank and not Game.policies.has(p)
				cb.focus_mode = Control.FOCUS_NONE
				cb.add_theme_font_size_override("font_size", 15)
				cb.toggled.connect(func(_on): Game.toggle_policy(p))
				body.add_child(cb)
			body.add_child(_label("上月收支", 19, VERM))
			var bl := _rich("")
			bl.name = "Budget"
			body.add_child(bl)
			_update_budget(body)
		"routes":
			_clear(body)
			body.add_child(_rich("[color=#6a5040]先在產業或城中旁建驛站（車）或碼頭（船），再開闢通往外邑或另一站的路線。\n車船自動裝載起點之貨，運往終點販售；外邑路途愈遠、出價愈高。[/color]"))
			var hb := HBoxContainer.new()
			body.add_child(hb)
			hb.add_child(_button("開闢新路線", func():
				close_windows()
				main.set_tool("route")))
			if Game.routes.is_empty():
				body.add_child(_label("尚無路線。", 16))
			for r in Game.routes.values():
				var a: Dictionary = Game.buildings.get(r.a, {})
				var b: Dictionary = Game.buildings.get(r.b, {})
				if a.is_empty() or b.is_empty():
					continue
				var vs := Game.route_vehicles(r.id)
				var row := HBoxContainer.new()
				body.add_child(row)
				var sw := ColorRect.new()
				sw.color = r.color
				sw.custom_minimum_size = Vector2(10, 40)
				row.add_child(sw)
				var cargo := []
				var lost := 0
				for v in vs:
					if v.amt > 0:
						cargo.append("%s%d" % [Defs.cargo_name(v.cargo), int(v.amt)])
					if v.state == "lost":
						lost += 1
				var kinds := {}
				for v in vs:
					kinds[Defs.VEHICLES[v.kind]["name"]] = kinds.get(Defs.VEHICLES[v.kind]["name"], 0) + 1
				var ks := []
				for k in kinds:
					ks.append("%s×%d" % [k, kinds[k]])
				var txt := "[b]%s ⇄ %s[/b]（%s）\n%s　上月 %d 兩　累計 %d 兩%s" % [Game.bname(a), Game.bname(b),
					"車道" if r.mode == "road" else "水道", "、".join(ks), int(r.last), int(r.total),
					("　載：" + "、".join(cargo)) if cargo.size() > 0 else ""]
				if lost > 0:
					txt += "\n[color=#a02818]%d 輛無路可通！[/color]" % lost
				var rl := _rich(txt)
				rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(rl)
				var best := Game.best_vehicle(r.mode)
				var rid: int = r.id
				row.add_child(_button("+%s" % Defs.VEHICLES[best]["name"], func():
					var e := Game.add_vehicle(rid, best)
					if e != "":
						toast(e, true), "購置 %d 兩" % Defs.VEHICLES[best]["cost"]))
				row.add_child(_button("−", func(): Game.remove_vehicle(rid), "賣出一輛（回收四成）"))
				row.add_child(_button("撤", func(): Game.delete_route(rid), "撤銷路線"))
		"stats":
			if not full:
				return
			_clear(body)
			chart = Chart.new()
			body.add_child(chart)
			body.add_child(_rich("[color=#6a5040]每月記錄一次，最多二十年。[/color]"))
		"help":
			if not full:
				return
			_clear(body)
			body.add_child(_rich(_help_text()))


func _update_budget(body: Control) -> void:
	var bl: RichTextLabel = body.get_node_or_null("Budget")
	if bl == null:
		return
	var r: Dictionary = Game.report
	var s := "[table=2]"
	for k in r.get("income", {}):
		s += "[cell]%s[/cell][cell][color=#2f6a2a]+%d[/color][/cell]" % [k, int(r.income[k])]
	for k in r.get("expense", {}):
		s += "[cell]%s[/cell][cell][color=#a02818]-%d[/color][/cell]" % [k, int(r.expense[k])]
	s += "[cell][b]結餘[/b][/cell][cell][b]%+d[/b][/cell][/table]" % int(r.get("net", 0.0))
	bl.text = s


func _rich(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.custom_minimum_size = Vector2(560, 0)
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 15)
	return r


func _help_text() -> String:
	return """[b]操作[/b]
・左鍵：使用工具／選取建築。道路、運河、城牆可拖曳成線；分區與拆除可拖曳成片。
・右鍵拖曳或中鍵：平移。滾輪：縮放。WASD／方向鍵：平移。
・右鍵輕點或 Esc：取消工具。空白鍵：暫停。1、2、3：調速。B：拆除。F5 存檔，F9 讀檔。

[b]築城之道[/b]
・[color=#a03020]道路須連通縣衙[/color]，且在轄境（沿路距離）之內，民居、市肆、作坊方能興起。農田距路三格內即可。
・頂欄四條需求柱分別為民、市、工、農。百姓需要職缺，市肆作坊需要人手，人人都要吃糧。
・秋收時節糧產最豐，冬季幾無收成——修建糧倉，方能熬過寒冬。
・茅舍得水井與市集即升為瓦屋；瓦屋若有教化、信仰或娛樂，地價夠高，城中又有綢緞、瓷器或茶，便成宅院。
・人丁增長可晉升品級：村→鎮→縣→州→府→京，每晉一級，轄境擴大，並解鎖新建築、政令與車船。

[b]產業與貨運（仿 OpenTTD）[/b]
・伐木場、採石場、鐵礦、茶園等須建於林地、丘陵、山嶺。若道路可達縣衙，產物自動入城；否則堆積於產地。
・在產地旁建驛站（車）或碼頭（船），再以「開闢路線」連到城中驛站或外邑。
・外邑（洛陽、揚州、成都）收購一切貨物，各有偏好的高價貨。路途愈遠，運費愈高；但行程拖太久會折價。
・城中存量過半的貨物，可經城內驛站外銷。
・瓷窯以石料燒製瓷器，是最賺錢的貨物。

[b]災異[/b]
・火災：望火樓可撲救。疫病：醫館可防。盜匪：捕快房可禦。洪水：「興修水利」可防。旱災則只能靠存糧。"""


# ───────────────────────── 開場 ─────────────────────────

func _build_title() -> void:
	title_root = Control.new()
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_root)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.05, 0.25)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.add_child(cc)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(Color(0.96, 0.92, 0.82, 0.95), Color(0.45, 0.3, 0.18), 3, 10, 50, 30))
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := _label("上河築城", 72, VERM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := _label("一河兩岸　百業千家", 22, Color(0.35, 0.25, 0.15))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var st2 := _label("修路劃區、興建民政，經營車馬漕運，自一村而至京師", 16, Color(0.45, 0.35, 0.25))
	st2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st2)
	v.add_child(HSeparator.new())
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	v.add_child(g)
	g.add_child(_label("城名", 18))
	name_edit = LineEdit.new()
	name_edit.text = "清河"
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.max_length = 6
	g.add_child(name_edit)
	g.add_child(_label("地圖", 18))
	var sh := HBoxContainer.new()
	g.add_child(sh)
	seed_edit = LineEdit.new()
	seed_edit.text = str(randi() % 100000)
	seed_edit.custom_minimum_size = Vector2(180, 0)
	sh.add_child(seed_edit)
	sh.add_child(_button("換一幅", func():
		seed_edit.text = str(randi() % 100000)
		Game.new_game(name_edit.text, int(seed_edit.text))
		Game.speed = 0))
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 16)
	v.add_child(bh)
	var nb := _button("開始築城", func():
		var n := name_edit.text.strip_edges()
		main.start_new(n if n != "" else "清河", int(seed_edit.text)))
	nb.custom_minimum_size = Vector2(150, 50)
	nb.add_theme_font_size_override("font_size", 22)
	bh.add_child(nb)
	load_btn = _button("讀取存檔", func():
		if not main.load_saved():
			toast("讀檔失敗", true))
	load_btn.custom_minimum_size = Vector2(150, 50)
	load_btn.add_theme_font_size_override("font_size", 22)
	bh.add_child(load_btn)
	var hb := _button("說明", func(): open_window("help"))
	hb.custom_minimum_size = Vector2(90, 50)
	hb.add_theme_font_size_override("font_size", 22)
	bh.add_child(hb)


func show_title(on: bool) -> void:
	title_root.visible = on
	main.title_mode = on
	if on:
		Game.speed = 0
		load_btn.disabled = not Game.has_save()
		close_windows()
	top_panel.visible = not on
	bottom_v.visible = not on
	log_panel.visible = not on
	quest_panel.visible = not on
	mini_panel.visible = not on
	hover_tip.visible = false
	info_panel.visible = false
	toast_panel.visible = false
	if not on:
		_update_top()
		_on_message("", 0)
		cur_cat = ""
		palette_wrap.visible = false


# ───────────────────────── 詔令、小地圖、懸停 ─────────────────────────

func _build_quests() -> void:
	quest_panel = PanelContainer.new()
	quest_panel.offset_left = 8
	quest_panel.offset_top = 64
	quest_panel.custom_minimum_size = Vector2(300, 0)
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.self_modulate = Color(1, 1, 1, 0.9)
	root.add_child(quest_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(v)
	v.add_child(_label("詔令", 16, VERM))
	quest_box = RichTextLabel.new()
	quest_box.bbcode_enabled = true
	quest_box.fit_content = true
	quest_box.scroll_active = false
	quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_box.custom_minimum_size = Vector2(280, 0)
	quest_box.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(quest_box)


func _update_quests() -> void:
	if main.title_mode:
		return
	var qs := Game.current_quests(3)
	if qs.is_empty():
		quest_panel.visible = false
		return
	quest_panel.visible = true
	var t := ""
	for q in qs:
		t += "・%s" % q.text
		if q.reward > 0:
			t += "　[color=#8a6a20]賞 %d 兩[/color]" % q.reward
		t += "\n"
	t += "[color=#8a7a60]已成 %d / %d[/color]" % [Game.quests_done.size(), Defs.QUESTS.size()]
	quest_box.text = t
	quest_panel.reset_size()


func _build_minimap() -> void:
	mini_panel = PanelContainer.new()
	mini_panel.anchor_left = 1.0
	mini_panel.anchor_right = 1.0
	mini_panel.anchor_top = 1.0
	mini_panel.anchor_bottom = 1.0
	mini_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mini_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mini_panel.offset_right = -8
	mini_panel.offset_bottom = -8
	root.add_child(mini_panel)
	minimap = MiniMap.new()
	minimap.main = main
	mini_panel.add_child(minimap)


func _build_hover() -> void:
	hover_tip = PanelContainer.new()
	hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tip.add_theme_stylebox_override("panel", _sb(Color(0.98, 0.95, 0.86, 0.92), Color(0.45, 0.3, 0.18), 1, 4, 8, 4))
	root.add_child(hover_tip)
	hover_label = _label("", 14)
	hover_tip.add_child(hover_label)
	hover_tip.visible = false


func set_hover(text: String, at: Vector2) -> void:
	if text == "" or main.title_mode:
		hover_tip.visible = false
		return
	hover_label.text = text
	hover_tip.visible = true
	hover_tip.reset_size()
	var p := at + Vector2(18, 18)
	if p.x + hover_tip.size.x > root.size.x:
		p.x = at.x - hover_tip.size.x - 8
	hover_tip.position = p


class MiniMap extends Control:
	const S := 1.4
	var main
	var tex: ImageTexture
	var img: Image
	var t := 0.0
	var dragging := false

	func _init() -> void:
		custom_minimum_size = Vector2(Defs.N * 2 * S, Defs.N * S)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "小地圖：點擊或拖曳以移動視野"

	func _process(delta: float) -> void:
		t -= delta
		if t <= 0 and is_visible_in_tree() and Game.running:
			t = 2.0
			_rebuild()
		queue_redraw()

	func _rebuild() -> void:
		var g = Game
		var N: int = g.N
		if img == null:
			img = Image.create(N * 2, N, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var tc := [Color(0.62, 0.72, 0.48), Color(0.36, 0.55, 0.6), Color(0.3, 0.48, 0.32), Color(0.68, 0.64, 0.45), Color(0.4, 0.46, 0.5)]
		var bc := {"house": Color(0.78, 0.62, 0.42), "shop": Color(0.35, 0.45, 0.75), "workshop": Color(0.85, 0.6, 0.2),
			"farm": Color(0.88, 0.78, 0.4), "town": Color(0.75, 0.15, 0.1), "yamen": Color(0.75, 0.15, 0.1)}
		for j in N:
			for i in N * 2:
				var u := i - N + 0.5
				var v := 2.0 * j + 1.0
				var x := int(round((u + v) * 0.5 - 0.5))
				var y := int(round((v - u) * 0.5 - 0.5))
				if not g.inb(x, y):
					continue
				var k: int = g.idx(x, y)
				var c: Color = tc[g.terrain[k]]
				if g.bld[k] >= 0:
					c = bc.get(g.buildings[g.bld[k]].type, Color(0.65, 0.3, 0.25))
				elif g.road[k] > 0:
					c = Color(0.55, 0.45, 0.32)
				elif g.zone[k] > 0:
					c = c.lerp(Defs.ZONE_COLORS[g.zone[k]], 0.5)
				img.set_pixel(i, j, c)
		if tex == null:
			tex = ImageTexture.create_from_image(img)
		else:
			tex.update(img)

	func _draw() -> void:
		if tex == null:
			return
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		var cam: Camera2D = main.cam
		var vs: Vector2 = get_viewport_rect().size / cam.zoom
		var c: Vector2 = cam.get_screen_center_position()
		var r := Rect2(_to_map(c - vs * 0.5), vs / 32.0 * S)
		draw_rect(r, Color(0.66, 0.2, 0.15), false, 1.5)

	func _to_map(w: Vector2) -> Vector2:
		# 世界座標 (u*32, v*16) → 小地圖像素 ((u+N)*S, v/2*S)
		return Vector2((w.x / 32.0 + Defs.N) * S, w.y / 32.0 * S)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				dragging = mb.pressed
				if dragging:
					_jump(mb.position)
		elif ev is InputEventMouseMotion and dragging:
			_jump((ev as InputEventMouseMotion).position)

	func _jump(p: Vector2) -> void:
		var cam: Camera2D = main.cam
		cam.position = Vector2((p.x / S - Defs.N) * 32.0, p.y / S * 32.0)
		main._clamp_cam()


class Chart extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(600, 360)

	func _draw() -> void:
		var h: Array = Game.history
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.98, 0.92, 0.6))
		var series := [["pop", "人丁", Color(0.3, 0.5, 0.25)], ["money", "銀兩", Color(0.75, 0.55, 0.1)],
			["happy", "民心", Color(0.66, 0.2, 0.15)], ["trade", "貿易", Color(0.25, 0.4, 0.7)]]
		var f: Font = Defs.font
		if h.size() < 2:
			draw_string(f, Vector2(20, 40), "資料不足，過幾個月再來看。", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 0.3, 0.2))
			return
		var band := (size.y - 20) / series.size()
		for si in series.size():
			var key: String = series[si][0]
			var col: Color = series[si][2]
			var y0 := 10 + si * band
			var lo := INF
			var hi := -INF
			for e in h:
				lo = minf(lo, e.get(key, 0.0))
				hi = maxf(hi, e.get(key, 0.0))
			if hi - lo < 1.0:
				hi = lo + 1.0
			draw_line(Vector2(70, y0 + band - 6), Vector2(size.x - 10, y0 + band - 6), Color(0.6, 0.5, 0.4, 0.4), 1.0)
			var pts := PackedVector2Array()
			for k in h.size():
				var x := 70 + (size.x - 80) * k / float(h.size() - 1)
				var v: float = (h[k].get(key, 0.0) - lo) / (hi - lo)
				pts.append(Vector2(x, y0 + (band - 12) * (1.0 - v) + 4))
			draw_polyline(pts, col, 2.0, true)
			draw_string(f, Vector2(6, y0 + band * 0.5), series[si][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
			draw_string(f, Vector2(6, y0 + band * 0.5 + 18), str(int(h.back().get(key, 0.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.3, 0.2))


# ───────────────────────── 需求柱 ─────────────────────────

class DemandBars extends Control:
	var vals := [0.0, 0.0, 0.0, 0.0]

	func _init() -> void:
		custom_minimum_size = Vector2(108, 30)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var cols := [Color(0.3, 0.65, 0.3), Color(0.3, 0.45, 0.8), Color(0.85, 0.6, 0.15), Color(0.6, 0.4, 0.2)]
		var names := ["民", "市", "工", "農"]
		for k in 4:
			var x := k * 27.0
			var v: float = clampf(vals[k], 0.0, 100.0) / 100.0
			draw_rect(Rect2(x + 2, 2, 12, 26), Color(0, 0, 0, 0.12))
			draw_rect(Rect2(x + 2, 2 + 26 * (1.0 - v), 12, 26 * v), cols[k])
			draw_string(Defs.font, Vector2(x + 15, 22), names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.2, 0.1))
