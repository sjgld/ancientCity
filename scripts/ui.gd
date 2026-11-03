extends CanvasLayer
## 介面：常駐的天頭、地頭為深色漆木；冊頁、提示、詔令、邸報、案牘為宣紙。

const UIArt = preload("res://scripts/ui_art.gd")
const Art = preload("res://scripts/art.gd")

const TOP_H := 50.0
const BOTTOM_H := 66.0
const INK := UIArt.INK
const VERM := UIArt.ZHU
const CATS := [
	{"id": "road", "icon": "road", "name": "道路"},
	{"id": "zone", "icon": "zone", "name": "分區"},
	{"id": "civic", "icon": "civic", "name": "民政"},
	{"id": "industry", "icon": "industry", "name": "產業"},
	{"id": "transport", "icon": "transport", "name": "交通"},
	{"id": "deco", "icon": "deco", "name": "景觀"},
	{"id": "view", "icon": "layer", "name": "圖層"},
]
const BOOK_TABS := [["policy", "政務", "gov"], ["stock", "倉廩", "store"], ["routes", "商路", "route"], ["stats", "年鑑", "chart"], ["combos", "圖鑑", "deco"], ["help", "須知", "bookmark"]]
const SEASON_ICON := ["spring", "summer", "autumn", "winter"]
const COVER_NAME := {"water": "水", "health": "醫", "security": "治安", "fire": "防火", "edu": "教化", "faith": "信仰", "fun": "娛樂"}

var main
var root: Control
var top_band: TopBand
var plaque: Plaque
var top_date: DateBox
var top_money: Acct
var top_pop: Acct
var top_happy: Acct
var top_food: Acct
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
var log_panel: LogStrip
var toast_panel: PanelContainer
var toast_label: Label
var toast_t := 0.0
var windows := {}
var win_bodies := {}
var cur_win := ""
var book: PanelContainer
var book_title: Label
var book_dim: ColorRect
var book_marks: VBoxContainer
var mark_btns := {}
var title_root: Control
var name_edit: LineEdit
var seed_edit: LineEdit
var load_btn: Button
var refresh_t := 0.0
var top_panel: Control
var bottom_v: Control
var quest_panel: PanelContainer
var quest_now: Label
var quest_reward: Label
var quest_next: Label
var quest_count: Label
var minimap: MiniMap
var mini_panel: PanelContainer
var hover_tip: PanelContainer
var hover_label: Label
var chart: Chart
var music_on := true
var menu_panel: PanelContainer
var music_btn: MenuRow
var dock_btns := {}


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	root.theme = _make_theme()
	add_child(root)
	_build_log()
	_build_quests()
	_build_minimap()
	_build_info()
	_build_bottom()
	_build_top()
	_build_toast()
	_build_hover()
	_build_windows()
	_build_title()
	Game.message.connect(_on_message)
	Game.rank_changed.connect(_on_rank)
	Game.month_passed.connect(func(): main.world.overlay.queue_redraw())
	Game.quest_done.connect(func(_id): Sfx.play("coin"))
	Game.combo_found.connect(_on_combo)


# ───────────────────────── 樣式 ─────────────────────────

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = UIArt.font("body")
	th.default_font_size = 16
	th.set_stylebox("panel", "PanelContainer", UIArt.box("paper", UIArt.PAPER, 12, 10))
	th.set_stylebox("panel", "TooltipPanel", UIArt.box("paper", UIArt.PAPER, 12, 9, 3.0, false, Color(INK, 0.5)))
	th.set_color("font_color", "TooltipLabel", INK)
	th.set_font("font", "TooltipLabel", UIArt.font("body"))
	th.set_font_size("font_size", "TooltipLabel", 15)
	# 紙上按鈕
	th.set_stylebox("normal", "Button", UIArt.box("flat", UIArt.PAPER_2, 12, 4, 0.0, false, Color(INK, 0.4)))
	th.set_stylebox("hover", "Button", UIArt.box("flat", UIArt.PAPER, 12, 4, 0.0, false, Color(INK, 0.75)))
	th.set_stylebox("pressed", "Button", UIArt.box("flat", UIArt.PAPER_2, 12, 4, 0.0, false, INK))
	th.set_stylebox("hover_pressed", "Button", UIArt.box("flat", UIArt.PAPER, 12, 4, 0.0, false, INK))
	th.set_stylebox("disabled", "Button", UIArt.box("flat", Color(UIArt.PAPER_2, 0.45), 12, 4, 0.0, false, Color(INK, 0.15)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(k, "Button", INK)
	th.set_color("font_disabled_color", "Button", UIArt.INK_3)
	# 平鈕：自繪之元件用
	th.set_type_variation("Flat", "Button")
	for k in ["normal", "pressed", "disabled", "focus", "hover", "hover_pressed"]:
		th.set_stylebox(k, "Flat", StyleBoxEmpty.new())
	th.set_color("font_color", "Label", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_font("bold_font", "RichTextLabel", UIArt.font("body_b"))
	th.set_stylebox("normal", "LineEdit", UIArt.box("flat", Color("f6f1e4"), 8, 4, 0.0, false, Color(INK, 0.5)))
	th.set_stylebox("focus", "LineEdit", UIArt.box("flat", Color("f6f1e4"), 8, 4, 0.0, false, UIArt.SHIQING))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("caret_color", "LineEdit", INK)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(k, "CheckButton", INK)
	th.set_color("font_disabled_color", "CheckButton", UIArt.INK_3)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		th.set_stylebox(k, "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("slider", "HSlider", UIArt.box("flat", Color(INK, 0.2), 0, 2, 0.0))
	th.set_stylebox("grabber_area", "HSlider", UIArt.box("flat", INK, 0, 2, 0.0))
	th.set_stylebox("grabber_area_highlight", "HSlider", UIArt.box("flat", INK, 0, 2, 0.0))
	th.set_stylebox("background", "ProgressBar", UIArt.box("flat", Color(INK, 0.12), 0, 0, 0.0))
	th.set_stylebox("fill", "ProgressBar", UIArt.box("flat", Color(INK, 0.8), 0, 0, 0.0))
	th.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return th


func _label(text: String, size: int = 16, col: Color = INK, kind: String = "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIArt.font(kind))
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


# ───────────────────────── 天頭 ─────────────────────────

func _build_top() -> void:
	top_band = TopBand.new()
	top_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = TOP_H
	root.add_child(top_band)
	top_panel = top_band
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -10
	h.add_theme_constant_override("separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_band.add_child(h)
	plaque = Plaque.new()
	h.add_child(plaque)
	top_money = Acct.new("silver")
	top_pop = Acct.new("people")
	top_happy = Acct.new("mood")
	top_food = Acct.new("grain")
	for a in [top_money, top_pop, top_happy, top_food]:
		h.add_child(a)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	top_date = DateBox.new()
	h.add_child(top_date)
	var speed := SpeedWell.new()
	h.add_child(speed)
	var g := ButtonGroup.new()
	for k in 4:
		var b := SpeedButton.new()
		b.kind = ["pause", "play1", "play2", "play3"][k]
		b.tooltip_text = ["暫停（空白鍵）", "常速（1）", "二倍速（2）", "四倍速（3）"][k]
		b.button_group = g
		b.pressed.connect(set_speed.bind(k))
		b.pressed.connect(func(): Sfx.play("click"))
		speed.box.add_child(b)
		speed_btns.append(b)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 2)
	h.add_child(dock)
	for w in BOOK_TABS.slice(0, 5):
		var d := DockButton.new()
		d.label = w[1]
		d.kind = w[2]
		d.tooltip_text = {"policy": "政務：稅率、政令、收支", "stock": "倉廩：各色貨物存量", "routes": "商路：路線與車船", "stats": "年鑑：歷月走勢", "combos": "圖鑑：城中已成的格局"}[w[0]]
		dock_btns[w[0]] = d
		d.pressed.connect(func():
			Sfx.play("click")
			open_window(w[0]))
		dock.add_child(d)
	var mb := MenuButton2.new()
	mb.tooltip_text = "存檔、讀檔、配樂、須知、返回開場"
	mb.pressed.connect(_toggle_menu)
	h.add_child(mb)
	_build_menu()


func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.PAPER, 6, 6, 3.0, false, Color(INK, 0.45)))
	menu_panel.anchor_left = 1.0
	menu_panel.anchor_right = 1.0
	menu_panel.offset_left = -190
	menu_panel.offset_right = -10
	menu_panel.offset_top = TOP_H + 6
	root.add_child(menu_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	menu_panel.add_child(v)
	var items := [["存檔", "F5", _save], ["讀檔", "F9", func():
		if not main.load_saved():
			toast("讀檔失敗", true)], ["配樂", "", _toggle_music], ["須知", "", func(): open_window("help")],
		["返回開場", "", func(): show_title(true)]]
	for it in items:
		var b := MenuRow.new()
		b.label = it[0]
		b.key = it[1]
		b.pressed.connect(func():
			Sfx.play("click")
			menu_panel.visible = false
			it[2].call())
		v.add_child(b)
		if it[0] == "配樂":
			music_btn = b
	menu_panel.visible = false


func _toggle_menu() -> void:
	Sfx.play("click")
	menu_panel.visible = not menu_panel.visible
	menu_panel.move_to_front()
	if music_btn:
		music_btn.key = "開" if music_on else "關"
		music_btn.queue_redraw()


func _toggle_music() -> void:
	music_on = not music_on
	Sfx.set_music(music_on)
	toast("配樂已%s" % ("開" if music_on else "關"))


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
	plaque.set_data(Game.city_name, Game.rank_name())
	top_date.set_data("%s%s年 %s" % [Game.era, "元" if Game.year == 1 else Defs.cn_num(Game.year), Defs.MONTHS[Game.month]],
		SEASON_ICON[Game.season()], Game.day / 30.0, Game.speed == 0)
	# 銀兩：上月結餘
	var net: float = Game.report.get("net", 0.0)
	var dm := ""
	if Game.report.has("net"):
		dm = ("▲%d" if net >= 0 else "▼%d") % absi(int(net))
	top_money.set_data(_fmt(int(Game.money)), dm, net >= 0, "", -1.0, Game.money < 0)
	top_money.tooltip_text = _money_tip()
	# 人丁：晉升進度
	if Game.rank < Defs.RANKS.size() - 1:
		var nx: Dictionary = Defs.RANKS[Game.rank + 1]
		var p0: int = Defs.RANKS[Game.rank]["pop"]
		top_pop.set_data(_fmt(s.pop), "", true, "距晉%s\n尚欠 %d" % [nx.name, maxi(0, nx.pop - s.pop)],
			clampf(float(s.pop - p0) / maxf(1, nx.pop - p0), 0, 1), false, "／%s" % _fmt(nx.pop))
	else:
		top_pop.set_data(_fmt(s.pop), "", true, "", -1.0)
	top_pop.tooltip_text = "人丁 %d\n勞力 %d　職缺 %d\n失業 %d%%" % [s.pop, s.labor, s.jobs, int(s.unemp * 100)]
	# 民心：三態臉與月變化
	var hp := int(s.happy)
	top_happy.icon_kind = "mood_good" if hp >= 65 else ("mood_bad" if hp < 40 else "mood")
	var dh := ""
	var hdelta := 0
	if Game.history.size() >= 2:
		hdelta = int(Game.history[-1].happy) - int(Game.history[-2].happy)
		if hdelta != 0:
			dh = ("▲%d" if hdelta > 0 else "▼%d") % absi(hdelta)
	top_happy.set_data(str(hp), dh, hdelta >= 0, "", -1.0, hp < 40)
	top_happy.tooltip_text = "民心 %d\n六十五以上安居樂業；四十以下百姓怨懟，民居會敗落" % hp
	# 存糧：換算可食月數
	var food: float = Game.stock.get("grain", 0.0) + Game.stock.get("fish", 0.0)
	var per: float = maxf(1.0, s.pop * 0.2)
	var months := int(food / per)
	var mtxt := "存糧充裕" if months >= 24 else "可食\n%s個月" % Defs.cn_num(months)
	top_food.set_data(_fmt(int(food)), "", true, mtxt, -1.0, months < 3 or Game.food_short > 0.1)
	top_food.tooltip_text = "存糧 %d（糧與魚）\n每月食用約 %d　糧倉容量 %d\n秋收最豐，冬季幾無收成" % [int(food), int(per), int(Game.cap_of("grain"))]
	demand.vals = [s.dR, s.dC, s.dI, s.dF]
	demand.queue_redraw()
	if not speed_btns[Game.speed].button_pressed:
		speed_btns[Game.speed].button_pressed = true


func _money_tip() -> String:
	var r: Dictionary = Game.report
	if not r.has("net"):
		return "府庫銀兩\n月底結帳後顯示收支"
	var rows := []
	for k in r.income:
		rows.append([k, r.income[k]])
	for k in r.expense:
		rows.append([k, -r.expense[k]])
	rows.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	var t := "上月收支\n"
	for row in rows:
		if absf(row[1]) >= 1:
			t += "%s　%+d\n" % [row[0], int(row[1])]
	t += "結餘　%+d 兩" % int(r.net)
	return t


static func _fmt(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


# ───────────────────────── 地頭與托板 ─────────────────────────

func _build_bottom() -> void:
	bottom_v = Control.new()
	bottom_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_v)
	palette_wrap = CenterContainer.new()
	palette_wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	palette_wrap.offset_top = -BOTTOM_H - 10
	palette_wrap.offset_bottom = -BOTTOM_H - 10
	palette_wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	palette_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_v.add_child(palette_wrap)
	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.PAPER, 12, 10, 3.0, true))
	palette_wrap.add_child(tray)
	palette = HBoxContainer.new()
	palette.add_theme_constant_override("separation", 4)
	tray.add_child(palette)
	palette_wrap.visible = false
	var band := BottomBand.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -BOTTOM_H
	bottom_v.add_child(band)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	tabs.anchor_left = 0.5
	tabs.anchor_right = 0.5
	tabs.anchor_top = 0.0
	tabs.anchor_bottom = 1.0
	tabs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	band.add_child(tabs)
	var g := ButtonGroup.new()
	g.allow_unpress = true
	for c in CATS:
		var b := CatTab.new()
		b.kind = c.icon
		b.label = c.name
		b.button_group = g
		b.pressed.connect(_on_cat.bind(c.id))
		b.pressed.connect(func(): Sfx.play("click"))
		tabs.add_child(b)
		cat_btns[c.id] = b
	tool_group.allow_unpress = true
	demand = DemandBars.new()
	demand.anchor_left = 0.5
	demand.anchor_right = 0.5
	demand.anchor_top = 0.0
	demand.anchor_bottom = 1.0
	var half := CATS.size() * 38.0
	demand.offset_left = -half - 140
	demand.offset_right = -half - 24
	band.add_child(demand)


func _on_cat(id: String) -> void:
	if cur_cat == id:
		cur_cat = ""
		palette_wrap.visible = false
		cat_btns[id].button_pressed = false
		_place_log()
		return
	cur_cat = id
	if cat_btns.has(id):
		cat_btns[id].button_pressed = true
	_fill_palette()


func _fill_palette() -> void:
	for c in palette.get_children():
		palette.remove_child(c)
		c.queue_free()
	if cur_cat == "":
		palette_wrap.visible = false
		_place_log()
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
				var b := ViewChip.new()
				b.text = m[1]
				b.toggle_mode = true
				b.button_pressed = main.world.overlay.mode == m[0]
				b.pressed.connect(_on_view.bind(m[0]))
				palette.add_child(b)
			_place_log()
			return
		_:
			for k in Defs.B:
				var d: Dictionary = Defs.B[k]
				if d.cat == cur_cat:
					items.append({"id": "b:" + k, "name": d.name, "cost": d.cost, "rank": d.rank, "desc": d.desc, "btype": k})
			if cur_cat == "transport":
				items.append({"id": "route", "name": "開闢路線", "cost": -1, "rank": 0,
					"desc": "先點起點、再點終點（驛站、碼頭或外邑），即購一輛車船往返載貨。"})
	for it in items:
		var b := ToolCard.new()
		b.tool_id = it.id
		b.btype = it.get("btype", "")
		b.title = it.name
		b.cost = it.cost
		b.desc = it.desc
		b.lock_rank = it.rank if it.rank > Game.rank else -1
		b.tooltip_text = it.name
		b.button_group = tool_group
		b.disabled = it.rank > Game.rank
		b.button_pressed = main.tool == it.id
		b.pressed.connect(_on_tool.bind(it.id))
		b.pressed.connect(func(): Sfx.play("click"))
		palette.add_child(b)
	_place_log()


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
	banner("晉為「%s」" % Game.rank_name())


# ───────────────────────── 冊頁（選中物） ─────────────────────────

func _build_info() -> void:
	info_panel = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.PAPER, 20, 16))
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.offset_left = -368
	info_panel.offset_right = -12
	info_panel.offset_top = TOP_H + 12
	root.add_child(info_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	info_panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	info_title = _label("", 26, INK, "title")
	info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info_title)
	var cb := _button("收起", _close_info)
	cb.theme_type_variation = "Flat"
	cb.add_theme_color_override("font_color", UIArt.INK_3)
	cb.add_theme_color_override("font_hover_color", INK)
	cb.add_theme_font_size_override("font_size", 14)
	h.add_child(cb)
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.fit_content = true
	info_body.scroll_active = false
	info_body.custom_minimum_size = Vector2(316, 0)
	info_body.add_theme_font_size_override("normal_font_size", 16)
	info_body.add_theme_font_size_override("bold_font_size", 16)
	info_body.add_theme_constant_override("line_separation", 4)
	v.add_child(info_body)
	info_btns = HBoxContainer.new()
	info_btns.add_theme_constant_override("separation", 10)
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
		info_btns.add_child(_button("查看商路", func(): open_window("routes")))
		info_btns.add_child(_button("賣出", func():
			Game.vehicles.erase(vid)
			Game.money += Defs.VEHICLES[v.kind]["cost"] * 0.4
			main.selected_vehicle = -1
			show_info()))
		info_panel.reset_size()
		return
	var sel: int = main.selected
	if sel >= 0 and Game.buildings.has(sel):
		var b: Dictionary = Game.buildings[sel]
		info_panel.visible = true
		info_title.text = Game.bname(b)
		if b.type == "yamen":
			info_title.text = "%s%s" % [Game.city_name, ["里署", "鎮署", "縣衙", "州衙", "府衙", "皇城"][Game.rank]]
		info_body.text = _yamen_text() if b.type == "yamen" else Game.building_info(b)
		if Game.is_stop(b):
			info_btns.add_child(_button("由此開闢商路", func():
				main.set_tool("route")
				main.route_first = b.id
				toast("起點：%s。再點選終點。" % Game.bname(b))))
		if b.type not in ["yamen", "town"]:
			var del := _button("拆除", func():
				Game.bulldoze(b.x, b.y)
				main.selected = -1
				show_info())
			del.add_theme_color_override("font_color", UIArt.BAD)
			del.add_theme_color_override("font_hover_color", UIArt.BAD)
			info_btns.add_child(del)
		info_panel.reset_size()
		return
	var t: Vector2i = main.selected_tile
	if Game.inb(t.x, t.y):
		info_panel.visible = true
		info_title.text = "地塊"
		info_body.text = Game.tile_info(t.x, t.y)
		info_panel.reset_size()
		return
	info_panel.visible = false


func _vehicle_text(v: Dictionary) -> String:
	var d: Dictionary = Defs.VEHICLES[v.kind]
	var r: Dictionary = Game.routes.get(v.route, {})
	var t := ""
	if not r.is_empty():
		t += "商路：%s 至 %s\n" % [Game.bname(Game.buildings[r.a]), Game.bname(Game.buildings[r.b])]
	var st := {"move": "行進中", "load": "裝卸中", "lost": "[color=#b1372a]無路可通[/color]"}
	t += "狀態：%s\n" % st.get(v.state, v.state)
	if Game.buildings.has(v.to):
		t += "前往：%s\n" % Game.bname(Game.buildings[v.to])
	if v.amt > 0:
		t += "載貨：%s %d／%d\n" % [Defs.cargo_name(v.cargo), int(v.amt), d.cap]
	else:
		t += "載貨：空載（容量 %d）\n" % d.cap
	t += "速度：每日 %.1f 格　月費 %d 兩\n" % [d.speed, d.upkeep]
	return t


func _yamen_text() -> String:
	var s: Dictionary = Game.stats
	var t := "人丁 %d　戶數 %d\n" % [s.pop, s.houses]
	t += "勞力 %d　職缺 %d　到崗 %d%%\n" % [s.labor, s.jobs, int(s.staff * 100)]
	t += "失業 %d%%　民心 %d\n" % [int(s.unemp * 100), int(s.happy)]
	t += "轄境：沿路 %d 格內\n" % Game.radius()
	if Game.rank < Defs.RANKS.size() - 1:
		var nx: Dictionary = Defs.RANKS[Game.rank + 1]
		t += "晉升「%s」尚需人丁 %d\n" % [nx.name, maxi(0, nx.pop - s.pop)]
	t += "\n[b]施政提要[/b]\n"
	var tips := []
	if s.pop < 30:
		tips.append("沿路劃設民居與農田，百姓自會遷入。")
	if Game.food_short > 0.05:
		tips.append("[color=#b1372a]糧食不足[/color]：多劃農田、建漁場，並修糧倉存秋糧。")
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
		tips.append("建驛站並開闢通往外邑的商路，以貨物換銀兩。")
	if tips.is_empty():
		tips.append("政通人和，可擴建城池、經營商路。")
	t += "\n".join(tips)
	return t


# ───────────────────────── 邸報與提示 ─────────────────────────

func _build_log() -> void:
	log_panel = LogStrip.new()
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 14
	log_panel.offset_right = 494
	root.add_child(log_panel)
	_place_log()


## 托板升起時，邸報往上讓位。
func _place_log() -> void:
	if log_panel == null:
		return
	var lift := 0.0
	if palette_wrap and palette_wrap.visible:
		lift = palette_wrap.get_combined_minimum_size().y + 10
	log_panel.offset_bottom = -BOTTOM_H - 10 - lift
	log_panel.offset_top = log_panel.offset_bottom - 112


func _on_message(_text: String, kind: int) -> void:
	if kind == 2 and not main.title_mode:
		Sfx.play("bad")
	var lines := []
	for l in Game.log_lines:
		lines.append({"date": _short_date(l.t), "text": l.text, "kind": l.kind})
		if lines.size() >= 3:
			break
	log_panel.lines = lines
	log_panel.age = 0.0
	log_panel.queue_redraw()


static func _short_date(t: String) -> String:
	var parts := t.split(" ")
	return parts[parts.size() - 1] if parts.size() >= 3 else t


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.PAPER, 18, 8, 3.0, true))
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.offset_top = TOP_H + 16
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_panel)
	toast_label = _label("", 17)
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


## 大事：黃紙橫幅。
func banner(text: String) -> void:
	var b := PanelContainer.new()
	b.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.HUANG, 48, 20, 6.0, true))
	var l := _label(text, 40, INK, "title")
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
		for c in palette.get_children():
			c.queue_redraw()


# ───────────────────────── 案牘 ─────────────────────────

func _build_windows() -> void:
	book_dim = ColorRect.new()
	book_dim.color = Color(0.12, 0.09, 0.06, 0.45)
	book_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	book_dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close_windows())
	root.add_child(book_dim)
	book = PanelContainer.new()
	book.add_theme_stylebox_override("panel", UIArt.book_box())
	root.add_child(book)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	book.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	book_title = _label("", 28, INK, "title")
	book_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(book_title)
	var shut := _button("闔上", close_windows, "Esc")
	shut.theme_type_variation = "Flat"
	shut.add_theme_color_override("font_color", UIArt.INK_3)
	shut.add_theme_color_override("font_hover_color", INK)
	shut.add_theme_font_size_override("font_size", 14)
	h.add_child(shut)
	for w in BOOK_TABS:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(840, 560)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sc)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 8)
		sc.add_child(body)
		sc.visible = false
		windows[w[0]] = sc
		win_bodies[w[0]] = body
	book_marks = VBoxContainer.new()
	book_marks.add_theme_constant_override("separation", 6)
	root.add_child(book_marks)
	for w in BOOK_TABS:
		var m := BookMark.new()
		m.label = w[1]
		m.kind = w[2]
		m.pressed.connect(func():
			Sfx.play("click")
			_show_page(w[0]))
		book_marks.add_child(m)
		mark_btns[w[0]] = m
	book_dim.visible = false
	book.visible = false
	book_marks.visible = false


func window_open(id: String) -> bool:
	return cur_win == id


func open_window(id: String) -> void:
	if cur_win == id:
		close_windows()
		return
	menu_panel.visible = false
	book_dim.visible = true
	book.visible = true
	book_marks.visible = true
	book_dim.move_to_front()
	book.move_to_front()
	book_marks.move_to_front()
	_show_page(id)


func _show_page(id: String) -> void:
	cur_win = id
	if dock_btns.has(id) and dock_btns[id].badge:
		dock_btns[id].badge = false
		dock_btns[id].queue_redraw()
	for k in windows:
		windows[k].visible = k == id
		mark_btns[k].on = k == id
		mark_btns[k].queue_redraw()
	for w in BOOK_TABS:
		if w[0] == id:
			book_title.text = w[1]
	_fill_window(id, true)
	book.reset_size()
	book.position = Vector2(maxf(40, (root.size.x - book.size.x) * 0.5 - 30), maxf(TOP_H + 16, (root.size.y - book.size.y) * 0.5))
	book_marks.position = Vector2(book.position.x + book.size.x + 2, book.position.y + 44)


func close_windows() -> void:
	book_dim.visible = false
	book.visible = false
	book_marks.visible = false
	cur_win = ""


func _clear(body: Control) -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()


func _section(body: Control, text: String) -> void:
	body.add_child(_label(text, 20, INK, "title"))


func _fill_window(id: String, full: bool = false) -> void:
	var body: VBoxContainer = win_bodies[id]
	match id:
		"stock":
			_clear(body)
			for c in Defs.CARGO_ORDER:
				var h := HBoxContainer.new()
				h.add_theme_constant_override("separation", 12)
				body.add_child(h)
				var sw := ColorRect.new()
				sw.color = Defs.CARGO[c]["color"]
				sw.custom_minimum_size = Vector2(14, 14)
				sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(sw)
				var l := _label("%s" % Defs.cargo_name(c), 18)
				l.custom_minimum_size = Vector2(56, 0)
				h.add_child(l)
				var cap := Game.cap_of(c)
				var pb := ProgressBar.new()
				pb.max_value = cap
				pb.value = Game.stock.get(c, 0.0)
				pb.show_percentage = false
				pb.custom_minimum_size = Vector2(360, 8)
				pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(pb)
				h.add_child(_label("%d／%d　價 %d" % [int(Game.stock.get(c, 0.0)), int(cap), int(Defs.CARGO[c]["price"])], 15, UIArt.INK_2, "num"))
			body.add_child(_rich("\n[color=#5d5147]作坊以絲織綢緞，以鐵、木製器物；市肆售器物綢緞瓷器茶葉；宅院需奢侈品。\n存量過半之貨物，驛站與碼頭方可外運。糧倉、貨棧可擴充容量。[/color]"))
		"policy":
			if not full:
				_update_budget(body)
				return
			_clear(body)
			_section(body, "稅")
			for k in [["res", "戶稅"], ["com", "商稅"], ["ind", "工稅"], ["farm", "田賦"]]:
				var h := HBoxContainer.new()
				h.add_theme_constant_override("separation", 12)
				body.add_child(h)
				var l := _label(k[1], 17)
				l.custom_minimum_size = Vector2(56, 0)
				h.add_child(l)
				var s := HSlider.new()
				s.min_value = 0
				s.max_value = 25
				s.step = 1
				s.value = Game.tax[k[0]]
				s.custom_minimum_size = Vector2(320, 20)
				s.focus_mode = Control.FOCUS_NONE
				h.add_child(s)
				var vl := _label("%d%%" % Game.tax[k[0]], 16, INK, "num")
				h.add_child(vl)
				s.value_changed.connect(func(val):
					Game.tax[k[0]] = int(val)
					vl.text = "%d%%" % int(val))
			body.add_child(_rich("[color=#5d5147]戶稅過一成則民心漸失。[/color]"))
			_section(body, "政令")
			for p in Defs.POLICIES:
				var d: Dictionary = Defs.POLICIES[p]
				var cb := CheckButton.new()
				cb.text = "%s　%s　月費 %d 兩%s" % [d.name, d.desc, d.upkeep, "" if d.rank <= Game.rank else "　需「%s」" % Defs.RANKS[d.rank]["name"]]
				cb.button_pressed = Game.policies.has(p)
				cb.disabled = d.rank > Game.rank and not Game.policies.has(p)
				cb.focus_mode = Control.FOCUS_NONE
				cb.add_theme_font_size_override("font_size", 16)
				cb.toggled.connect(func(_on): Game.toggle_policy(p))
				body.add_child(cb)
			_section(body, "上月收支")
			var bl := _rich("")
			bl.name = "Budget"
			body.add_child(bl)
			_update_budget(body)
		"routes":
			_clear(body)
			body.add_child(_rich("[color=#5d5147]先在產業或城中旁建驛站（車）或碼頭（船），再開闢通往外邑或另一站的商路。\n車船自動裝載起點之貨，運往終點販售；外邑路途愈遠、出價愈高。[/color]"))
			var hb := HBoxContainer.new()
			body.add_child(hb)
			hb.add_child(_button("開闢新商路", func():
				close_windows()
				main.set_tool("route")))
			if Game.routes.is_empty():
				body.add_child(_label("尚無商路。", 16, UIArt.INK_2))
			for r in Game.routes.values():
				var a: Dictionary = Game.buildings.get(r.a, {})
				var b: Dictionary = Game.buildings.get(r.b, {})
				if a.is_empty() or b.is_empty():
					continue
				var vs := Game.route_vehicles(r.id)
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 10)
				body.add_child(row)
				var sw := ColorRect.new()
				sw.color = r.color
				sw.custom_minimum_size = Vector2(6, 44)
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
					ks.append("%s%d" % [k, kinds[k]])
				var txt := "[b]%s 至 %s[/b]　%s\n%s　上月 %d 兩　累計 %d 兩%s" % [Game.bname(a), Game.bname(b),
					"車道" if r.mode == "road" else "水道", "、".join(ks), int(r.last), int(r.total),
					("　載：" + "、".join(cargo)) if cargo.size() > 0 else ""]
				if lost > 0:
					txt += "\n[color=#b1372a]%d 輛無路可通[/color]" % lost
				var rl := _rich(txt)
				rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(rl)
				var best := Game.best_vehicle(r.mode)
				var rid: int = r.id
				row.add_child(_button("添%s" % Defs.VEHICLES[best]["name"], func():
					var e := Game.add_vehicle(rid, best)
					if e != "":
						toast(e, true), "購置 %d 兩" % Defs.VEHICLES[best]["cost"]))
				row.add_child(_button("減", func(): Game.remove_vehicle(rid), "賣出一輛（回收四成）"))
				row.add_child(_button("撤", func(): Game.delete_route(rid), "撤銷商路"))
		"stats":
			if not full:
				return
			_clear(body)
			chart = Chart.new()
			body.add_child(chart)
			body.add_child(_rich("[color=#5d5147]每月記錄一次，最多二十年。[/color]"))
		"help":
			if not full:
				return
			_clear(body)
			body.add_child(_rich(_help_text()))
		"combos":
			if not full:
				return
			_clear(body)
			body.add_child(_rich("[color=#5d5147]把特定的建築擺在一起，就會形成古代城市裡的經典格局：外觀隨之改變，每月另有收入。已成%s種，共%s種。[/color]" % [Defs.cn_num(Game.combos_found.size()), Defs.cn_num(Defs.COMBOS.size())]))
			for c in Defs.COMBOS:
				body.add_child(_combo_card(c))


## 圖鑑中的一則格局：左圖右文；未成者圖淡去，並寫明條件。
func _combo_card(c: Dictionary) -> Control:
	var found: bool = Game.combos_found.has(c.id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var art := ComboArt.new()
	art.combo_id = c.id
	art.found = found
	h.add_child(art)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := HBoxContainer.new()
	v.add_child(t)
	var head := _label(c.name, 24, INK if found else UIArt.INK_3, "title")
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_child(head)
	var n: int = Game.combo_count.get(c.id, 0)
	if found:
		t.add_child(_label("%s成　現有 %d 處　每處月入 %d 兩" % [Game.combos_found[c.id].split(" ")[0], n, c.income], 13, UIArt.INK_3, "num"))
	v.add_child(_label(c.verse, 17, UIArt.INK_2 if found else UIArt.INK_3))
	var body := _label(c.text if found else "尚未成局。", 15, INK if found else UIArt.INK_3)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	v.add_child(body)
	v.add_child(_label("條件：" + c.rule, 14, UIArt.SHIQING if not found else UIArt.INK_3))
	return h


func _on_combo(id: String) -> void:
	Sfx.play("gong")
	banner("格局成立：%s" % Defs.combo(id).name)
	if dock_btns.has("combos"):
		dock_btns["combos"].badge = true
		dock_btns["combos"].queue_redraw()


func _update_budget(body: Control) -> void:
	var bl: RichTextLabel = body.get_node_or_null("Budget")
	if bl == null:
		return
	var r: Dictionary = Game.report
	var s := "[table=2]"
	for k in r.get("income", {}):
		s += "[cell]%s　[/cell][cell][color=#3f7a57]+%d[/color][/cell]" % [k, int(r.income[k])]
	for k in r.get("expense", {}):
		s += "[cell]%s　[/cell][cell][color=#5d5147]-%d[/color][/cell]" % [k, int(r.expense[k])]
	var net: float = r.get("net", 0.0)
	s += "[cell][b]結餘[/b][/cell][cell][b][color=%s]%+d[/color][/b][/cell][/table]" % ["#3f7a57" if net >= 0 else "#b1372a", int(net)]
	bl.text = s


func _rich(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.custom_minimum_size = Vector2(560, 0)
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 16)
	r.add_theme_constant_override("line_separation", 4)
	return r


func _help_text() -> String:
	return """[b]操作[/b]
左鍵：使用工具、選取建築。道路、運河、城牆可拖曳成線；分區與拆除可拖曳成片。
右鍵拖曳或中鍵：平移。滾輪：縮放。WASD、方向鍵：平移。
右鍵輕點或 Esc：取消工具。空白鍵：暫停。1、2、3：調速。B：拆除。F5 存檔，F9 讀檔。

[b]築城之道[/b]
[color=#b1372a]道路須連通縣衙[/color]，且在轄境（沿路距離）之內，民居、市肆、作坊方能興起。農田距路三格內即可。
地頭左側四根需求條分別為民、市、工、農，顏色與地圖上的分區相同。百姓需要職缺，市肆作坊需要人手，人人都要吃糧。
秋收時節糧產最豐，冬季幾無收成。修建糧倉，方能熬過寒冬。
茅舍得水井與市集即升為瓦屋；瓦屋若有教化、信仰或娛樂，地價夠高，城中又有綢緞、瓷器或茶，便成宅院。
人丁增長可晉升品級：村、鎮、縣、州、府、京，每晉一級，轄境擴大，並解鎖新建築、政令與車船。

[b]產業與貨運[/b]
伐木場、採石場、鐵礦、茶園等須建於林地、丘陵、山嶺。若道路可達縣衙，產物自動入城；否則堆積於產地。
在產地旁建驛站（車）或碼頭（船），再以「開闢路線」連到城中驛站或外邑。
外邑（洛陽、揚州、成都）收購一切貨物，各有偏好的高價貨。路途愈遠，運費愈高；但行程拖太久會折價。
城中存量過半的貨物，可經城內驛站外銷。瓷窯以石料燒製瓷器，是最賺錢的貨物。

[b]災異[/b]
火災：望火樓可撲救。疫病：醫館可防。盜匪：捕快房可禦。洪水：「興修水利」可防。旱災則只能靠存糧。"""


# ───────────────────────── 開場 ─────────────────────────

func _build_title() -> void:
	title_root = Control.new()
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_root)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.09, 0.06, 0.2)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.add_child(cc)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIArt.book_box(46, 30))
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := _label("上河築城", 76, INK, "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := _label("一河兩岸　百業千家", 22, UIArt.INK_2)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var st2 := _label("修路劃區、興建民政，經營車馬漕運，自一村而至京師", 16, UIArt.INK_3)
	st2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st2)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	g.add_child(_label("城名", 18, INK, "num"))
	name_edit = LineEdit.new()
	name_edit.text = "清河"
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.max_length = 6
	g.add_child(name_edit)
	g.add_child(_label("山水", 18, INK, "num"))
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
	nb.add_theme_font_override("font", UIArt.font("title"))
	nb.add_theme_font_size_override("font_size", 22)
	bh.add_child(nb)
	load_btn = _button("讀取存檔", func():
		if not main.load_saved():
			toast("讀檔失敗", true))
	load_btn.custom_minimum_size = Vector2(150, 50)
	load_btn.add_theme_font_override("font", UIArt.font("title"))
	load_btn.add_theme_font_size_override("font_size", 22)
	bh.add_child(load_btn)
	var hb := _button("須知", func(): open_window("help"))
	hb.custom_minimum_size = Vector2(90, 50)
	hb.add_theme_font_override("font", UIArt.font("title"))
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
	menu_panel.visible = false
	hover_tip.visible = false
	info_panel.visible = false
	toast_panel.visible = false
	if not on:
		_update_top()
		_on_message("", 0)
		cur_cat = ""
		palette_wrap.visible = false
		for k in cat_btns:
			cat_btns[k].button_pressed = false
		_place_log()


# ───────────────────────── 詔令、小地圖、懸停 ─────────────────────────

func _build_quests() -> void:
	quest_panel = PanelContainer.new()
	quest_panel.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.HUANG, 14, 10, 3.0, true))
	quest_panel.position = Vector2(14, TOP_H + 14)
	quest_panel.custom_minimum_size = Vector2(276, 0)
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(quest_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := _label("詔令", 15, VERM, "title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	quest_count = _label("", 12, Color("6b5226"))
	h.add_child(quest_count)
	quest_now = _label("", 18)
	quest_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_now.custom_minimum_size = Vector2(248, 0)
	v.add_child(quest_now)
	quest_reward = _label("", 14, Color("6b5226"))
	v.add_child(quest_reward)
	quest_next = _label("", 13, UIArt.INK_3)
	quest_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_next.custom_minimum_size = Vector2(248, 0)
	v.add_child(quest_next)


func _update_quests() -> void:
	if main.title_mode:
		return
	var qs := Game.current_quests(3)
	if qs.is_empty():
		quest_panel.visible = false
		return
	quest_panel.visible = true
	quest_count.text = "第%s道，共%s道" % [Defs.cn_num(Game.quests_done.size() + 1), Defs.cn_num(Defs.QUESTS.size())]
	quest_now.text = qs[0].text
	quest_reward.text = ("賞銀 %s 兩" % _fmt(qs[0].reward)) if qs[0].reward > 0 else ""
	var rest := []
	for k in range(1, qs.size()):
		rest.append(qs[k].text)
	quest_next.text = ("其後：" + "、".join(rest)) if rest.size() > 0 else ""
	quest_next.visible = rest.size() > 0
	quest_panel.reset_size()


func _build_minimap() -> void:
	mini_panel = PanelContainer.new()
	mini_panel.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.PAPER, 8, 8))
	mini_panel.anchor_left = 1.0
	mini_panel.anchor_right = 1.0
	mini_panel.anchor_top = 1.0
	mini_panel.anchor_bottom = 1.0
	mini_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mini_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mini_panel.offset_right = -12
	mini_panel.offset_bottom = -BOTTOM_H - 10
	root.add_child(mini_panel)
	minimap = MiniMap.new()
	minimap.main = main
	mini_panel.add_child(minimap)


func _build_hover() -> void:
	hover_tip = PanelContainer.new()
	hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tip.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.PAPER, 10, 6, 3.0, false, Color(INK, 0.5)))
	root.add_child(hover_tip)
	hover_label = _label("", 15)
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
	if p.y + hover_tip.size.y > root.size.y - BOTTOM_H:
		p.y = at.y - hover_tip.size.y - 8
	hover_tip.position = p


# ───────────────────────── 天頭元件 ─────────────────────────

class TopBand extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		UIArt.band(self, Rect2(Vector2.ZERO, size), "bottom")


class BottomBand extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		UIArt.band(self, Rect2(Vector2.ZERO, size), "top")


## 城名牌匾：深木匾、雙金框、金字，右側朱印寫品級。
class Plaque extends Control:
	var city := ""
	var rank := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tooltip_text = "城名與品級"

	func set_data(c: String, r: String) -> void:
		if c == city and r == rank:
			return
		city = c
		rank = r
		var f := UIArt.font("title")
		custom_minimum_size = Vector2(ceilf(f.get_string_size(city, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + city.length() * 3 + 62), 40)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)])
		draw_polygon(pts, PackedColorArray([UIArt.WOOD_L, UIArt.WOOD_L, Color("2e231b"), Color("2e231b")]))
		draw_rect(r.grow(-0.5), UIArt.GOLD, false, 1.0)
		draw_rect(r.grow(-3.5), Color(UIArt.GOLD, 0.45), false, 1.0)
		var f := UIArt.font("title")
		var x := 14.0
		for ch in city:
			x += UIArt.text_l(self, f, x, size.y * 0.5, ch, 22, Color("e9d6a6")) + 3
		UIArt.seal(self, Rect2(x + 6, (size.y - 24) * 0.5, 24, 24), rank)


## 天頭上之一項數值：圖示、數字、漲跌、兩行小註，可帶晉升進度條。
class Acct extends Control:
	var icon_kind := ""
	var value := ""
	var of := ""
	var delta := ""
	var up := true
	var sub := ""
	var prog := -1.0
	var alarm := false

	func _init(k: String) -> void:
		icon_kind = k
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_data(v: String, d: String, u: bool, s: String, p: float, al: bool = false, o: String = "") -> void:
		value = v
		delta = d
		up = u
		sub = s
		prog = p
		alarm = al
		of = o
		var nf := UIArt.font("num")
		var bf := UIArt.font("body")
		var w := 32.0 + nf.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		if of != "":
			w += 3 + nf.get_string_size(of, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		if delta != "":
			w += 5 + nf.get_string_size(delta, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if sub != "":
			var sw := 0.0
			for line in sub.split("\n"):
				sw = maxf(sw, bf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
			w += 8 + sw
		custom_minimum_size = Vector2(ceilf(w), 40)
		queue_redraw()

	func _draw() -> void:
		var cy := size.y * 0.5
		UIArt.icon(self, icon_kind, Rect2(0, cy - 12, 24, 24), UIArt.IVORY)
		var nf := UIArt.font("num")
		var bf := UIArt.font("body")
		var x := 32.0
		var vy := cy - (3.0 if prog >= 0 else 0.0)
		x += UIArt.text_l(self, nf, x, vy, value, 19, UIArt.BAD_W if alarm else UIArt.IVORY)
		if of != "":
			x += 3 + UIArt.text_l(self, nf, x + 3, vy + 2, of, 12, UIArt.IVORY_2)
		if prog >= 0:
			draw_rect(Rect2(32, cy + 9, x - 32, 3), Color(UIArt.IVORY, 0.18))
			draw_rect(Rect2(32, cy + 9, (x - 32) * prog, 3), UIArt.GOLD)
		if delta != "":
			x += 5 + UIArt.text_l(self, nf, x + 5, cy, delta, 13, UIArt.GOOD_W if up else UIArt.BAD_W)
		if sub != "":
			var lines := sub.split("\n")
			var y0 := cy - (lines.size() - 1) * 7.5
			for i in lines.size():
				UIArt.text_l(self, bf, x + 8, y0 + i * 15, lines[i], 12, UIArt.BAD_W if alarm and i == lines.size() - 1 else UIArt.IVORY_2)


## 日期：季節圖示外一圈本月進度，旁寫年號月份；暫停時變暗。
class DateBox extends Control:
	var text := ""
	var season := "spring"
	var prog := 0.0
	var paused := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tooltip_text = "外圈為本月進度"

	func set_data(t: String, s: String, p: float, pz: bool) -> void:
		if t == text and s == season and absf(p - prog) < 0.01 and pz == paused:
			return
		text = t
		season = s
		prog = p
		paused = pz
		custom_minimum_size = Vector2(36 + UIArt.font("body").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, 40)
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(13, size.y * 0.5)
		var a := 0.5 if paused else 1.0
		draw_arc(c, 11, 0, TAU, 32, Color(UIArt.IVORY, 0.2), 2.4, true)
		draw_arc(c, 11, -PI / 2, -PI / 2 + TAU * maxf(prog, 0.02), 32, Color(UIArt.GOLD, a), 2.4, true)
		UIArt.icon(self, season, Rect2(c - Vector2(7, 7), Vector2(14, 14)), UIArt.IVORY)
		UIArt.text_l(self, UIArt.font("body"), 32, c.y, text, 16, Color(UIArt.IVORY, a))


## 速度鍵之凹槽。
class SpeedWell extends PanelContainer:
	var box: HBoxContainer

	func _init() -> void:
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.25)
		sb.border_color = Color(0, 0, 0, 0.35)
		sb.border_width_top = 1
		sb.set_content_margin_all(3)
		add_theme_stylebox_override("panel", sb)
		box = HBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		add_child(box)


## 速度：暫停與一、二、四倍速，選中者反白。
class SpeedButton extends Button:
	var kind := ""

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		theme_type_variation = "Flat"
		custom_minimum_size = Vector2(34, 30)

	func _draw() -> void:
		var col := UIArt.IVORY_2
		if button_pressed:
			draw_rect(Rect2(Vector2.ZERO, size), UIArt.IVORY)
			col = UIArt.WOOD_D
		elif is_hovered():
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
			col = UIArt.IVORY
		UIArt.icon(self, kind, Rect2(size * 0.5 - Vector2(9, 9), Vector2(18, 18)), col)


## 簿冊入口：圖示在上、二字在下。
class DockButton extends Button:
	var kind := ""
	var label := ""
	var badge := false

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		theme_type_variation = "Flat"
		custom_minimum_size = Vector2(52, 46)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var hov := is_hovered()
		if hov:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		UIArt.icon(self, kind, Rect2(size.x * 0.5 - 11, 3, 22, 22), UIArt.IVORY)
		UIArt.text_c(self, UIArt.font("body"), Vector2(size.x * 0.5, 36), label, 12, UIArt.IVORY if hov else UIArt.IVORY_2)
		if badge:
			draw_circle(Vector2(size.x * 0.5 + 12, 6), 4.0, UIArt.BAD_W)


## 系統選單鍵。
class MenuButton2 extends Button:
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		theme_type_variation = "Flat"
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		custom_minimum_size = Vector2(34, 34)

	func _draw() -> void:
		if is_hovered():
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color(UIArt.GOLD, 0.7), false, 1.0)
		UIArt.icon(self, "menu", Rect2(size * 0.5 - Vector2(10, 10), Vector2(20, 20)), UIArt.IVORY)


## 系統選單之一行。
class MenuRow extends Button:
	var label := ""
	var key := ""

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		theme_type_variation = "Flat"
		custom_minimum_size = Vector2(164, 36)

	func _draw() -> void:
		if is_hovered():
			draw_rect(Rect2(Vector2.ZERO, size), Color(UIArt.PAPER_2, 0.8))
		UIArt.text_l(self, UIArt.font("body"), 12, size.y * 0.5, label, 17, UIArt.INK)
		var nf := UIArt.font("num")
		var w := nf.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		UIArt.text_l(self, nf, size.x - 12 - w, size.y * 0.5, key, 13, UIArt.INK_3)


# ───────────────────────── 地頭元件 ─────────────────────────

## 營建分類：彩繪圖示加兩字；選中者換成紙面抽起。
class CatTab extends Button:
	var kind := ""
	var label := ""

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		theme_type_variation = "Flat"
		custom_minimum_size = Vector2(74, 66)

	func _draw() -> void:
		var top := 0.0
		var line := UIArt.IVORY
		var tc := UIArt.IVORY_2
		if button_pressed:
			top = -10.0
			UIArt.paper_rid(get_canvas_item(), Rect2(0, top, size.x, size.y - top), UIArt.PAPER, 0.0)
			draw_line(Vector2(0, top), Vector2(size.x, top), UIArt.GOLD, 1.0)
			draw_rect(Rect2(size.x, top + 2, 2, size.y - top - 2), UIArt.LIFT)
			line = UIArt.INK
			tc = UIArt.INK
		elif is_hovered():
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.07))
			tc = UIArt.IVORY
		var cy := (size.y + top) * 0.5
		UIArt.icon(self, kind, Rect2(size.x * 0.5 - 14, cy - 22, 28, 28), line)
		UIArt.text_c(self, UIArt.font("body"), Vector2(size.x * 0.5, cy + 17), label, 13, tc)


## 需求條：四根用分區本身的顏色；需求高時頂端出現小箭頭。
class DemandBars extends Control:
	var vals := [0.0, 0.0, 0.0, 0.0]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = "需求：民居、市肆、作坊、農田\n顏色與地圖上的分區相同；條愈高，愈該劃設此類分區"

	func _draw() -> void:
		var names := ["民", "市", "工", "農"]
		var f := UIArt.font("body")
		UIArt.vtext(self, f, Vector2(8, 12), "需求", 12, UIArt.IVORY_2, 0.15)
		for k in 4:
			var x := 28.0 + k * 22.0
			var v: float = clampf(vals[k], 0.0, 100.0) / 100.0
			var r := Rect2(x, 12, 12, 34)
			draw_rect(r, Color(0, 0, 0, 0.3))
			draw_rect(r.grow(-0.5), Color(UIArt.IVORY, 0.12), false, 1.0)
			var col: Color = UIArt.ZONE[k + 1]
			draw_rect(Rect2(x, r.end.y - r.size.y * v, 12, r.size.y * v), col)
			if vals[k] >= 70:
				draw_colored_polygon(PackedVector2Array([Vector2(x + 6, 3), Vector2(x + 11, 9), Vector2(x + 1, 9)]), col)
			UIArt.text_c(self, f, Vector2(x + 6, 55), names[k], 12, UIArt.IVORY_2)


## 托板上之一件工具：建築畫其本身。有平常、滑過、選中、買不起、未解鎖五態；提示為結構化紙卡。
class ToolCard extends Button:
	var tool_id := ""
	var btype := ""
	var title := ""
	var desc := ""
	var cost := -1
	var lock_rank := -1

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		theme_type_variation = "Flat"
		custom_minimum_size = Vector2(94, 112)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var hov := is_hovered() and not disabled
		if button_pressed:
			draw_rect(Rect2(Vector2.ZERO, size), UIArt.PAPER_2)
			draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color(UIArt.INK, 0.55), false, 1.0)
		elif hov:
			draw_rect(Rect2(Vector2.ZERO, size), Color(UIArt.PAPER_2, 0.6))
		var area := Rect2(4, 6, size.x - 8, 60)
		if btype != "":
			var bsz: int = Defs.B[btype]["size"]
			var s := minf(1.1, 78.0 / (64.0 * bsz))
			if btype in ["firewatch", "pagoda", "belltower"]:
				s *= 0.62
			var c := Vector2(area.get_center().x, area.end.y - 12.0 * s * bsz)
			draw_set_transform(c, 0.0, Vector2(s, s))
			Art.building(self, btype, Vector2.ZERO, 2 if btype == "farm" else 1, 37)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			UIArt.tool_thumb(self, tool_id, area.get_center() + Vector2(0, 6), 1.0)
		if lock_rank >= 0:
			draw_rect(Rect2(0, 0, size.x, area.end.y + 4), Color(UIArt.PAPER, 0.62))
			UIArt.seal_outline(self, Rect2(size.x - 23, 5, 18, 18), Defs.RANKS[lock_rank]["name"])
		var f := UIArt.font("body")
		UIArt.text_c(self, f, Vector2(size.x * 0.5, 79), title, 15, UIArt.INK_3 if lock_rank >= 0 else UIArt.INK)
		var nf := UIArt.font("num")
		if lock_rank >= 0:
			UIArt.text_c(self, f, Vector2(size.x * 0.5, 98), "晉%s可建" % Defs.RANKS[lock_rank]["name"], 12, UIArt.INK_3)
		elif cost > 0:
			var t := str(cost)
			var poor := Game.money < cost
			var w := nf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 17
			var x0 := (size.x - w) * 0.5
			UIArt.icon(self, "silver", Rect2(x0, 91, 14, 14))
			UIArt.text_l(self, nf, x0 + 17, 98, t, 13, UIArt.BAD if poor else UIArt.INK_2)

	func _make_custom_tooltip(_for_text: String) -> Object:
		return ToolTipCard.make(self)


## 建造卡之提示：名稱與價格、說明、數值表、限制、對城中之用處。
class ToolTipCard extends PanelContainer:
	static func make(card) -> Control:
		var p := ToolTipCard.new()
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		p.add_theme_stylebox_override("panel", UIArt.box("paper", UIArt.PAPER, 15, 12, 3.0, false, Color(UIArt.INK, 0.45)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 5)
		v.custom_minimum_size = Vector2(270, 0)
		p.add_child(v)
		var h := HBoxContainer.new()
		v.add_child(h)
		var t := _l(card.title, 19, UIArt.INK, "title")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		if card.cost > 0:
			h.add_child(_l("%d 兩" % card.cost, 15, UIArt.BAD if Game.money < card.cost else UIArt.INK_2, "num"))
		var d := _l(card.desc, 14.5, UIArt.INK_2)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(270, 0)
		v.add_child(d)
		if card.btype != "":
			var b: Dictionary = Defs.B[card.btype]
			var g := GridContainer.new()
			g.columns = 2
			g.add_theme_constant_override("h_separation", 14)
			g.add_theme_constant_override("v_separation", 1)
			v.add_child(g)
			var rows := []
			if b.has("produce"):
				var parts := []
				for c in b.produce:
					parts.append("%s %d" % [Defs.cargo_name(c), int(b.produce[c])])
				rows.append(["每月產出", "、".join(parts)])
			if b.has("consume"):
				var parts := []
				for c in b.consume:
					parts.append("%s %d" % [Defs.cargo_name(c), int(b.consume[c])])
				rows.append(["每月耗用", "、".join(parts)])
			if b.has("cover"):
				rows.append(["照應半徑", "%d 格" % int(b.cover.values()[0])])
			if b.get("jobs", 0) > 0:
				rows.append(["職缺", "%d 人" % b.jobs])
			rows.append(["每月維護", "%d 兩" % b.upkeep])
			for r in rows:
				g.add_child(_l(r[0], 13.5, UIArt.INK_3))
				g.add_child(_l(r[1], 13.5, UIArt.INK, "num"))
			var rule := {"road": "須臨道路", "forest": "須在林地旁", "hill": "須建於丘陵", "mountain": "須建於山上", "shore": "須臨水", "grass": "須在平地", "land": "陸地皆可"}
			if b.has("place"):
				v.add_child(_l(rule.get(b.place, ""), 13, UIArt.INK_2))
			if b.has("cover"):
				var key: String = b.cover.keys()[0]
				var names: Dictionary = {"water": "水", "health": "醫", "security": "治安", "fire": "防火", "edu": "教化", "faith": "信仰", "fun": "娛樂"}
				if names.has(key) and Game.stats.get("houses", 0) > 4:
					var share: float = Game._avg_cover_houses(key)
					if share < 0.6:
						var w := _l("城中只有%s成民居有%s" % [Defs.cn_num(int(share * 10)), names[key]], 13.5, UIArt.BAD)
						v.add_child(w)
		if card.lock_rank >= 0:
			v.add_child(_l("晉升為「%s」後可建" % Defs.RANKS[card.lock_rank]["name"], 13.5, UIArt.BAD))
		return p

	static func _l(text: String, size: float, col: Color, kind: String = "body") -> Label:
		var l := Label.new()
		l.text = text
		l.add_theme_font_override("font", UIArt.font(kind))
		l.add_theme_font_size_override("font_size", int(size))
		l.add_theme_color_override("font_color", col)
		return l


## 圖層選單之一枚字籤。
class ViewChip extends Button:
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		theme_type_variation = "Flat"
		custom_minimum_size = Vector2(58, 44)
		add_theme_font_size_override("font_size", 16)
		add_theme_color_override("font_color", UIArt.INK_2)
		add_theme_color_override("font_hover_color", UIArt.INK)
		add_theme_color_override("font_pressed_color", UIArt.INK)
		add_theme_color_override("font_hover_pressed_color", UIArt.INK)

	func _draw() -> void:
		if button_pressed:
			draw_rect(Rect2(Vector2.ZERO, size), UIArt.PAPER_2)
			draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color(UIArt.INK, 0.55), false, 1.0)
		elif is_hovered():
			draw_rect(Rect2(Vector2.ZERO, size), Color(UIArt.PAPER_2, 0.6))


## 案牘右側之書籤：漆木籤，選中者換紙面並與書頁相連。
class BookMark extends Button:
	var label := ""
	var kind := ""
	var on := false

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		theme_type_variation = "Flat"
		custom_minimum_size = Vector2(46, 112)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var line := UIArt.IVORY
		var tc := UIArt.IVORY
		if on:
			r = Rect2(-16, 0, size.x + 16, size.y)
			UIArt.paper_rid(get_canvas_item(), r, UIArt.PAPER, 3.0)
			line = UIArt.INK
			tc = UIArt.INK
		else:
			draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0.08, 0.05, 0.03, 0.4))
			UIArt.wood_rid(get_canvas_item(), r, "all")
			if is_hovered():
				draw_rect(r, Color(1, 1, 1, 0.08))
		UIArt.icon(self, kind, Rect2(size.x * 0.5 - 10, 10, 20, 20), line)
		UIArt.vtext(self, UIArt.font("body"), Vector2(size.x * 0.5, 38), label, 16, tc, 0.2)


## 邸報：紙條底，類型圖示、月份、內文；舊者漸淡，久則隱去。
class LogStrip extends Control:
	var lines: Array = []
	var age := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		var a0 := age
		age += delta
		if a0 < 40.0 and age >= 25.0:
			queue_redraw()

	func _draw() -> void:
		if lines.is_empty():
			return
		var fade := clampf(1.0 - (age - 25.0) / 15.0, 0.0, 1.0)
		if fade <= 0.0:
			return
		var h := 30.0 + lines.size() * 25.0
		var r := Rect2(0, size.y - h, size.x, h)
		modulate.a = fade
		UIArt.paper_rid(get_canvas_item(), r, Color(UIArt.PAPER, 0.96), 3.0, true, 5)
		var f := UIArt.font("body")
		var nf := UIArt.font("num")
		UIArt.text_l(self, UIArt.font("title"), 12, r.position.y + 14, "邸　報", 12, UIArt.INK_3)
		var y := r.end.y - 16.0
		for i in lines.size():
			var l: Dictionary = lines[i]
			var a: float = [1.0, 0.7, 0.5][i]
			var col: Color = UIArt.INK
			var ic := "note"
			if l.kind == 1:
				ic = "good"
			elif l.kind == 2:
				ic = "bad"
				col = UIArt.BAD
			UIArt.icon(self, ic, Rect2(12, y - 8, 16, 16))
			UIArt.text_l(self, nf, 34, y, l.date, 12, Color(UIArt.INK_3, a))
			draw_string(f, Vector2(76, y + (f.get_ascent(15) - f.get_descent(15)) * 0.5), l.text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 88, 15, Color(col, a))
			y -= 25.0


## 圖鑑插圖：以遊戲本身的畫法畫出格局的小景。
class ComboArt extends Control:
	var combo_id := ""
	var found := false

	func _init() -> void:
		custom_minimum_size = Vector2(190, 130)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("dfe3d3"))
		var c := size * 0.5 + Vector2(0, 18)
		var sc: float = {"fansha": 0.46, "yashu": 0.46, "hongqiao": 0.62, "siheyuan": 0.8, "wazi": 0.7}.get(combo_id, 0.95)
		if combo_id in ["fansha", "yashu"]:
			c.y += 14
		draw_set_transform(c, 0.0, Vector2(sc, sc))
		var water := Color("8fb0b2")
		match combo_id:
			"hongqiao":
				var band := PackedVector2Array([Art.iso(-1.5, -1.5), Art.iso(1.5, -1.5), Art.iso(1.5, 1.5), Art.iso(-1.5, 1.5)])
				draw_colored_polygon(band, water)
				Art.building(self, "shop", Art.iso(-2.1, -0.6), 1, 3)
				for k in 3:
					Art.rainbow_bridge(self, Art.iso(k - 1, 0), true, k, 3, 1)
				Art.building(self, "shop", Art.iso(2.1, 0.6), 1, 4)
			"wazi":
				Art.building(self, "shop", Art.iso(-1.0, 0.1), 2, 2)
				Art.combo_deco(self, "wazi", Art.iso(-1.0, 0.1), 1, 0, "shop")
				Art.building(self, "theater", Vector2.ZERO, 1, 1)
				Art.combo_deco(self, "wazi", Vector2.ZERO, 1, 1, "theater")
				Art.building(self, "shop", Art.iso(0.2, 1.1), 3, 4)
				Art.combo_deco(self, "wazi", Art.iso(0.2, 1.1), 1, 2, "shop")
			"caoyun":
				var band := PackedVector2Array([Art.iso(0.2, -2.0), Art.iso(2.2, -2.0), Art.iso(2.2, 2.0), Art.iso(0.2, 2.0)])
				draw_colored_polygon(band, water)
				Art.building(self, "granary", Art.iso(-1.0, -0.4), 1, 1)
				Art.dock(self, Vector2.ZERO, 1, Vector2i(1, 0))
				Art.combo_deco(self, "caoyun", Vector2.ZERO, 1, 1, "dock")
			"siheyuan":
				var qs := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]
				for k in 4:
					var p := Art.iso(qs[k].x, qs[k].y)
					Art.building(self, "house", p, 2, k * 3)
					Art.combo_deco(self, "siheyuan", p, 1, 2, "house", k)
			"fansha":
				Art.building(self, "temple", Art.iso(-0.4, 0.1), 1, 1)
				Art.combo_deco(self, "fansha", Art.iso(-0.4, 0.1), 2, 1, "temple")
				Art.building(self, "pagoda", Art.iso(1.6, -0.9), 1, 1)
				Art.combo_deco(self, "fansha", Art.iso(1.6, -0.9), 1, 1, "pagoda")
			"yashu":
				Art.building(self, "yamen", Art.iso(-0.4, -0.6), 1, 1)
				Art.combo_deco(self, "yashu", Art.iso(-0.4, -0.6), 2, 1, "yamen")
				Art.building(self, "archway", Art.iso(1.7, 1.2), 1, 0)
				Art.combo_deco(self, "yashu", Art.iso(1.7, 1.2), 1, 0, "archway")
			"sangji":
				var band := PackedVector2Array([Art.iso(0.6, -1.6), Art.iso(2.2, -1.6), Art.iso(2.2, 1.6), Art.iso(0.6, 1.6)])
				draw_colored_polygon(band, water)
				Art.combo_under(self, "sangji", Art.iso(-0.4, 0), 1, "mulberry")
				Art.building(self, "mulberry", Art.iso(-0.4, 0), 1, 1)
				Art.combo_deco(self, "sangji", Art.iso(-0.4, 0), 1, 1, "mulberry")
				Art.building(self, "fishery", Art.iso(0.7, 0.3), 1, 1)
			"chama":
				Art.building(self, "tea", Art.iso(-0.9, -0.4), 1, 1)
				Art.combo_deco(self, "chama", Art.iso(-0.9, -0.4), 1, 1, "tea")
				Art.building(self, "station", Art.iso(0.6, 0.4), 1, 1)
				Art.combo_deco(self, "chama", Art.iso(0.6, 0.4), 1, 1, "station")
			"guanyao":
				Art.building(self, "quarry", Art.iso(-1.2, -0.5), 1, 1)
				Art.combo_deco(self, "guanyao", Art.iso(-1.2, -0.5), 1, 1, "quarry")
				Art.building(self, "kiln", Art.iso(0.4, 0.3), 1, 1)
				Art.combo_deco(self, "guanyao", Art.iso(0.4, 0.3), 1, 1, "kiln")
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not found:
			draw_rect(r, Color(UIArt.PAPER, 0.62))
			UIArt.seal_outline(self, Rect2(size.x - 30, 6, 24, 24), "未")
		else:
			UIArt.seal(self, Rect2(size.x - 32, 6, 26, 26), "成", -0.12)
		draw_rect(r.grow(-0.5), Color(UIArt.INK, 0.35), false, 1.0)


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
		tooltip_text = "輿圖：點擊或拖曳以移動視野"

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
		var tc := [Color("b9bf9a"), Color("8fa7a6"), Color("7f927a"), Color("c2b896"), Color("98a09c")]
		var bc := {"house": Color("9b8566"), "shop": Color("6b7c95"), "workshop": Color("a88a55"),
			"farm": Color("c9b783"), "town": UIArt.ZHU, "yamen": UIArt.ZHU}
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
					c = bc.get(g.buildings[g.bld[k]].type, Color("8b6a55"))
				elif g.road[k] > 0:
					c = Color("8f7a5c")
				elif g.zone[k] > 0:
					c = c.lerp(Defs.ZONE_COLORS[g.zone[k]], 0.35)
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
		draw_rect(r, UIArt.ZHU, false, 1.5)
		UIArt.text_c(self, UIArt.font("title"), Vector2(size.x - 12, 12), "北", 13, UIArt.ZHU)

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
		custom_minimum_size = Vector2(820, 420)

	func _draw() -> void:
		var h: Array = Game.history
		var series := [["pop", "人丁", UIArt.INK], ["money", "銀兩", Color("7a5a22")],
			["happy", "民心", UIArt.ZHU], ["trade", "貿易", UIArt.SHIQING]]
		var f := UIArt.font("body")
		var nf := UIArt.font("num")
		var x := 90.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(UIArt.INK, 0.07), 1.0)
			x += 40.0
		if h.size() < 2:
			draw_string(f, Vector2(20, 40), "資料不足，過幾個月再來看。", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIArt.INK_2)
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
			draw_line(Vector2(90, y0 + band - 6), Vector2(size.x - 10, y0 + band - 6), Color(UIArt.INK, 0.25), 1.0)
			var pts := PackedVector2Array()
			for k in h.size():
				var px := 90 + (size.x - 100) * k / float(h.size() - 1)
				var v: float = (h[k].get(key, 0.0) - lo) / (hi - lo)
				pts.append(Vector2(px, y0 + (band - 12) * (1.0 - v) + 4))
			draw_polyline(pts, col, 2.0, true)
			draw_string(UIArt.font("title"), Vector2(6, y0 + band * 0.5), series[si][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
			draw_string(nf, Vector2(6, y0 + band * 0.5 + 20), str(int(h.back().get(key, 0.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIArt.INK_2)
