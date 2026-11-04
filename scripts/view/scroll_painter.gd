extends Node
## 長卷繪製：離屏畫出城市（主城＋城外段，在地圖上互不重疊）、絹本調色、段與段以雲煙相接，
## 再裱上引首、隔水、畫心款印、拖尾題跋與騎縫印，輸出一張由右往左讀的長圖。
## 只讀模擬資料，不改模擬。
##   var p := ScrollPainter.new(); add_child(p)
##   var res: Dictionary = await p.paint()     # {"image": Image, "title": String, "date": String}

const WorldView = preload("res://scripts/view/world_view.gd")
const UIArt = preload("res://scripts/ui/ui_art.gd")
const SILK_SHADER = preload("res://scripts/view/silk.gdshader")

const SILK := Color(0.90, 0.84, 0.70)
const TUO := Color(0.93, 0.89, 0.79)        # 拖尾用紙，比畫絹白
const LING := Color("c9b78f")               # 裱綾
const LING_D := Color("ad9a70")
const INK := Color("2b251f")
const INK_2 := Color("675a4c")
const TILE := Vector2i(1600, 1000)          # 離屏截圖每塊大小
const MAX_HUAXIN := 9000.0                  # 畫心最寬，超過則縮小繪製
const MAX_TOTAL := 16000.0                  # 整卷最寬（貼圖上限 16384）
const OUT_TYPES := ["lumber", "quarry", "mine", "kiln", "tea", "mulberry", "fishery", "station", "dock", "warehouse", "pagoda", "temple"]
const KIND_HEAD := {"found": "開城", "rank": "晉升", "route": "商路", "fire": "失火", "drought": "大旱",
	"plague": "瘟疫", "bandit": "盜匪", "flood": "水災", "now": "今貌"}
const DISASTER := ["flood", "plague", "fire", "drought", "bandit"]


## 繪一卷。回傳 {"image", "title", "date"}。
func paint() -> Dictionary:
	var plan := _plan()
	var z: float = plan.zoom
	var raws: Array = await _render_world(plan.rects, z)
	var fade := roundf(260.0 * z)
	var huaxin: Image = await _compose(raws, fade)
	var title := "%s%s圖" % [Game.city_name, Game.rank_name()]
	var img: Image = await _mount(huaxin, title)
	return {"image": img, "title": title, "date": _date_short(Game.date_str())}


# ───────────────────────── 取景 ─────────────────────────

## 找主城與城外段（世界座標矩形，由左至右），並決定縮放。
func _plan() -> Dictionary:
	var groups := _clusters()
	var main_g: Array = []
	for g in groups:
		if Game.yamen_id in g:
			main_g = g
	if main_g.is_empty() and not groups.is_empty():
		main_g = groups[0]
	var bb := _bbox(main_g)
	if bb.size == Vector2.ZERO:
		var y: Dictionary = Game.buildings.get(Game.yamen_id, {})
		var c := WorldView.tile_pos(y.get("x", 50), y.get("y", 50))
		bb = Rect2(c - Vector2(300, 150), Vector2(600, 300))
	# 屋頂高出地塊，上方多留一些
	var H := maxf(bb.size.y + 300.0, 760.0)
	var cy := bb.get_center().y - 40.0
	var W := maxf(bb.size.x + 840.0, H * 2.6)
	var main_r := Rect2(bb.get_center().x - W * 0.5, cy - H * 0.5, W, H)
	var rects := [main_r]
	# 城外段：互不重疊、帶產業的聚落，最多兩處
	var cands := []
	for g in groups:
		if g == main_g:
			continue
		var notable := false
		for id in g:
			if Game.buildings[id].type in OUT_TYPES:
				notable = true
		if not notable and g.size() < 3:
			continue
		cands.append(g)
	cands.sort_custom(func(a, b): return a.size() > b.size())
	for g in cands:
		if rects.size() >= 3:
			break
		var gb := _bbox(g)
		var w := clampf(gb.size.x + 600.0, H * 0.9, H * 1.6)
		var x0 := gb.get_center().x - w * 0.5
		# 先試置中；與已取的段重疊時，改貼在那一段的正上方或正下方
		var ys := [gb.get_center().y - 40.0 - H * 0.5]
		for o in rects:
			ys.append(o.position.y - H)
			ys.append(o.end.y)
		for y0 in ys:
			var r := Rect2(x0, y0, w, H)
			# 聚落須落在雲煙以內的安全區
			if gb.position.y - 60.0 < y0 + H * 0.2 or gb.end.y > y0 + H * 0.85:
				continue
			var clash := false
			for o in rects:
				if o.intersects(r):
					clash = true
			if not clash:
				rects.append(r)
				break
	rects.sort_custom(func(a, b): return a.position.x < b.position.x)
	var total := 0.0
	for r in rects:
		total += r.size.x
	var zoom := clampf(MAX_HUAXIN / total, 0.45, 1.0)
	return {"rects": rects, "zoom": zoom}


## 建築聚落：相距三格內者相連（外邑不算）。回傳 [[id...], ...]，大者在前。
func _clusters() -> Array:
	var occ := {}
	for b in Game.buildings.values():
		if b.type == "town":
			continue
		for dy in b.size:
			for dx in b.size:
				occ[Game.idx(b.x + dx, b.y + dy)] = b.id
	var seen := {}
	var groups := []
	for b in Game.buildings.values():
		if b.type == "town" or seen.has(b.id):
			continue
		var members := [b.id]
		seen[b.id] = true
		var q := [b.id]
		while not q.is_empty():
			var cur: Dictionary = Game.buildings[q.pop_back()]
			for y in range(cur.y - 3, cur.y + cur.size + 3):
				for x in range(cur.x - 3, cur.x + cur.size + 3):
					if not Game.inb(x, y):
						continue
					var id: int = occ.get(Game.idx(x, y), -1)
					if id >= 0 and not seen.has(id):
						seen[id] = true
						members.append(id)
						q.append(id)
		groups.append(members)
	groups.sort_custom(func(a, b): return a.size() > b.size())
	return groups


## 一群建築在螢幕（世界）座標的外接框。
func _bbox(ids: Array) -> Rect2:
	if ids.is_empty():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in ids:
		var b: Dictionary = Game.buildings[id]
		for p in [WorldView.tile_pos(b.x - 0.5, b.y - 0.5), WorldView.tile_pos(b.x + b.size - 0.5, b.y + b.size - 0.5),
				WorldView.tile_pos(b.x + b.size - 0.5, b.y - 0.5), WorldView.tile_pos(b.x - 0.5, b.y + b.size - 0.5)]:
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2(lo, hi - lo)


# ───────────────────────── 離屏繪製 ─────────────────────────

## 另起一份地圖畫面，攝影機逐塊移動截圖，拼成各段原圖。
func _render_world(rects: Array, z: float) -> Array:
	var vp := SubViewport.new()
	vp.size = TILE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera2D.new()
	vp.add_child(cam)
	cam.make_current()
	var wv = WorldView.new()
	wv.offscreen = true
	vp.add_child(wv)
	wv.setup(cam)
	cam.zoom = Vector2(z, z)
	for f in 3:
		await RenderingServer.frame_post_draw
	var out := []
	var step := Vector2(TILE) / z
	for r in rects:
		var img := Image.create(int(ceil(r.size.x * z)), int(ceil(r.size.y * z)), false, Image.FORMAT_RGBA8)
		var ty := 0.0
		while ty < r.size.y:
			var tx := 0.0
			while tx < r.size.x:
				cam.position = r.position + Vector2(tx, ty) + step * 0.5
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var shot := vp.get_texture().get_image()
				shot.convert(Image.FORMAT_RGBA8)
				img.blit_rect(shot, Rect2i(Vector2i.ZERO, TILE), Vector2i(roundi(tx * z), roundi(ty * z)))
				tx += step.x
			ty += step.y
		out.append(img)
	vp.queue_free()
	return out


## 各段調成絹本、左右淡出，交疊排在絹底上，交疊處即成雲煙。
func _compose(raws: Array, fade: float) -> Image:
	var H := 0
	var W := 0.0
	for k in raws.size():
		H = maxi(H, raws[k].get_height())
		W += raws[k].get_width() - (fade if k > 0 else 0.0)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(W), H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = SILK * 1.02
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var x := 0.0
	for k in raws.size():
		var img: Image = raws[k]
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture = ImageTexture.create_from_image(img)
		spr.position = Vector2(x, (H - img.get_height()) * 0.5)
		var m := ShaderMaterial.new()
		m.shader = SILK_SHADER
		m.set_shader_parameter("silk", SILK)
		m.set_shader_parameter("fade_l", fade * (1.0 if k > 0 else 0.7))
		m.set_shader_parameter("fade_r", fade * (1.0 if k < raws.size() - 1 else 0.7))
		m.set_shader_parameter("seed", float(k * 977 + Game.map_seed % 1000))
		spr.material = m
		vp.add_child(spr)
		x += img.get_width() - fade
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	out.convert(Image.FORMAT_RGB8)
	vp.queue_free()
	return out


# ───────────────────────── 裱卷 ─────────────────────────

## 裱成一卷：圖片由左至右為 拖尾｜隔水｜畫心｜隔水｜引首（畫卷由右往左讀）。
func _mount(huaxin: Image, title: String) -> Image:
	var m := Mount.new()
	m.huaxin = ImageTexture.create_from_image(huaxin)
	m.H = huaxin.get_height()
	m.title = title
	m.entries = _entries()
	m.layout()
	var vp := SubViewport.new()
	vp.size = Vector2i(mini(int(m.total_w), int(MAX_TOTAL)), int(m.total_h))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	m.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	vp.add_child(m)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	out.convert(Image.FORMAT_RGB8)
	vp.queue_free()
	return out


## 拖尾題跋：開城、晉升、格局、第一條商路全收；災異每種只收第一次、最多三則；最後一則寫今貌。
func _entries() -> Array:
	var out := []
	var dis := {}
	for a in Game.annals:
		if a.kind in DISASTER:
			if dis.has(a.kind) or dis.size() >= 3:
				continue
			dis[a.kind] = true
		var head: String = KIND_HEAD.get(a.kind, "")
		if a.kind == "combo":
			head = Defs.combo(a.ref).get("name", "格局") if a.get("ref", "") != "" else "格局"
		elif a.kind == "rank":
			head = "升" + _rank_in(a.text)
		out.append({"head": head, "text": "%s，%s" % [_date_short(a.t), a.text], "kind": a.kind})
	var s: Dictionary = Game.stats
	var now := "%s畫成此卷。這時%s有人口%s，存銀%s兩，民心%s，商路%s條，已成格局%s種。" % [
		_date_short(Game.date_str()), Game.city_name, Defs.cn_big(int(s.pop)), Defs.cn_big(int(Game.money)),
		Defs.cn_big(int(s.happy)), Defs.cn_big(Game.routes.size()), Defs.cn_big(Game.combos_found.size())]
	out.append({"head": "今貌", "text": now, "kind": "now"})
	return out


static func _rank_in(text: String) -> String:
	for r in Defs.RANKS:
		if ("升為" + r.name) in text:
			return r.name
	return ""


## 「宣和四年 冬 冬月」→「宣和四年冬月」
static func _date_short(t: String) -> String:
	var p := t.split(" ")
	return p[0] + p[p.size() - 1] if p.size() >= 3 else t


# ───────────────────────── 裱卷畫面 ─────────────────────────

class Mount extends Node2D:
	const UA = preload("res://scripts/ui/ui_art.gd")
	const VPUNCT := {"「": "﹁", "」": "﹂", "『": "﹃", "』": "﹄", "（": "︵", "）": "︶", "—": "︱", "…": "︙"}
	const CORNER := "，。、；：！？"
	var huaxin: Texture2D
	var H := 1000.0
	var title := ""
	var entries: Array = []
	# 版面（像素）
	var b := 0.0          # 上下綾邊
	var gs := 0.0         # 隔水寬
	var yin_w := 0.0      # 引首寬
	var tuo_w := 0.0      # 拖尾寬
	var total_w := 0.0
	var total_h := 0.0
	var cs := 0.0         # 題跋字大小
	var cols: Array = []  # 拖尾每一行：[{ch, font, col, size}]
	var col_entry: Array = []

	func layout() -> void:
		b = roundf(H * 0.045)
		gs = roundf(H * 0.05)
		cs = roundf(H * 0.036)
		var n := title.length()
		var ts := minf(H * 0.19, H * 0.8 / (n * 1.06))
		yin_w = maxf(H * 0.6, ts * 2.4)
		_flow()
		var colw := cs * 1.75
		tuo_w = H * 0.1 * 2.0 + cols.size() * colw + H * 0.25
		total_w = tuo_w + gs + huaxin.get_width() + gs + yin_w
		total_h = H + b * 2.0

	## 把題跋排成直行：每則以標題起頭，字滿一行換下一行，則與則之間空一行。
	func _flow() -> void:
		cols.clear()
		var pad := H * 0.09
		var per := int((H - pad * 2.0) / (cs * 1.12))
		for ei in entries.size():
			var e: Dictionary = entries[ei]
			var toks := []
			for ch in e.head:
				toks.append({"ch": ch, "font": "title", "col": INK, "size": cs * 1.08})
			toks.append({"ch": "　", "font": "body", "col": INK, "size": cs})
			for ch in e.text:
				toks.append({"ch": VPUNCT.get(ch, ch), "font": "body", "col": INK if e.kind != "now" else INK, "size": cs})
			var cur := []
			for t in toks:
				# 避頭：標點與後引號不放行首，掛在上一行末
				if cur.size() >= per and not (t.ch in CORNER or t.ch in "﹂﹄︶·"):
					cols.append(cur)
					cur = []
				cur.append(t)
			if e.kind in ["found", "rank", "now", "combo"]:
				# 印約佔兩字半高；行末放不下就另起一行
				if cur.size() + 3 > per:
					cols.append(cur)
					cur = []
				cur.append({"seal": true, "kind": e.kind})
			cols.append(cur)
			if ei < entries.size() - 1:
				cols.append([])

	func _draw() -> void:
		var hx := tuo_w + gs
		var yx := hx + huaxin.get_width() + gs
		# 綾邊與隔水
		draw_rect(Rect2(0, 0, total_w, total_h), LING)
		_ling_pattern(Rect2(0, 0, total_w, total_h))
		# 拖尾
		var tr := Rect2(0, b, tuo_w, H)
		draw_rect(tr, TUO)
		draw_texture_rect(UA.paper_tex(), tr, true, Color(1, 1, 1, 0.8))
		_draw_colophons(tr)
		# 畫心
		draw_texture(huaxin, Vector2(hx, b))
		# 引首
		var yr := Rect2(yx, b, yin_w, H)
		draw_rect(yr, SILK.lightened(0.04))
		draw_texture_rect(UA.paper_tex(), yr, true, Color(1, 1, 1, 0.55))
		_draw_yinshou(yr)
		# 接縫細線
		for x in [tuo_w, hx, hx + huaxin.get_width(), yx]:
			draw_line(Vector2(x, b), Vector2(x, b + H), Color(0.35, 0.28, 0.2, 0.35), 1.0)
		draw_line(Vector2(0, b), Vector2(total_w, b), Color(0.35, 0.28, 0.2, 0.35), 1.0)
		draw_line(Vector2(0, b + H), Vector2(total_w, b + H), Color(0.35, 0.28, 0.2, 0.35), 1.0)
		# 畫心款印：畫家在左端落款
		_draw_kuan(Vector2(hx + H * 0.07, b + H * 0.08))
		# 騎縫印：壓在畫心與兩側隔水的接縫上
		var ss := H * 0.07
		_seal4(Rect2(hx - ss * 0.5 - gs * 0.5, b + H * 0.62, ss, ss), Game.city_name.left(2) + "珍藏", false, 0.78, -0.04)
		_seal4(Rect2(yx - gs * 0.5 - ss * 0.5, b + H * 0.3, ss, ss), Game.city_name.left(2) + "珍藏", false, 0.78, 0.05)

	## 綾的暗花：淡淡的斜方格。
	func _ling_pattern(r: Rect2) -> void:
		var step := H * 0.03
		var c := Color(LING_D, 0.25)
		var x := r.position.x - r.size.y
		while x < r.end.x:
			draw_line(Vector2(x, r.position.y), Vector2(x + r.size.y, r.end.y), c, 1.0)
			draw_line(Vector2(x + r.size.y, r.position.y), Vector2(x, r.end.y), c, 1.0)
			x += step

	func _draw_yinshou(r: Rect2) -> void:
		var n := title.length()
		var ts := minf(H * 0.19, H * 0.8 / (n * 1.06))
		var top := r.position.y + (H - n * ts * 1.06) * 0.5
		var f := UA.font("title")
		for k in n:
			_vchar(f, Vector2(r.get_center().x, top + ts * (k * 1.06 + 0.5)), title[k], ts, INK)
		# 引首章（右上，長方白文）與題款（左下）
		var sw := H * 0.05
		_seal_col(Rect2(r.end.x - sw - H * 0.05, r.position.y + H * 0.06, sw, sw * 2.0), "水村", true)
		var kf := UA.font("body")
		var kt: String = Game.era + _yr() + "年" + Defs.SEASONS[Game.season()] + "　題"
		var ks := H * 0.03
		var ky: float = r.end.y - H * 0.08 - kt.length() * ks * 1.08
		for k in kt.length():
			_vchar(kf, Vector2(r.position.x + H * 0.07, ky + ks * (k * 1.08 + 0.5)), kt[k], ks, INK_2)

	func _draw_kuan(at: Vector2) -> void:
		var kf := UA.font("body")
		var ks := H * 0.032
		var kt: String = ScrollPainterRef.date_short(Game.date_str()) + "　" + Game.city_name + Game.rank_name() + "　繪"
		var y := at.y
		for ch in kt:
			_vchar(kf, Vector2(at.x, y + ks * 0.5), ch, ks, Color(0.2, 0.17, 0.14))
			y += ks * 1.1
		var ss := H * 0.062
		_seal4(Rect2(at.x - ss * 0.5, y + ks * 0.4, ss, ss), _seal_name(), true, 0.92, 0.0)

	func _seal_name() -> String:
		var c: String = Game.city_name
		if c.length() >= 2:
			return c.left(2) + "之印"
		return c + Game.rank_name() + "之印"

	func _draw_colophons(r: Rect2) -> void:
		var pad := H * 0.09
		var colw := cs * 1.75
		var x := r.end.x - H * 0.1 - colw * 0.5
		var bf := UA.font("body")
		var tf := UA.font("title")
		for col in cols:
			var y := r.position.y + pad
			for t in col:
				if t.has("seal"):
					var ss := cs * 1.7
					if t.kind == "now":
						_seal4(Rect2(x - ss * 0.5, y + cs * 0.3, ss, ss), _seal_name(), true, 0.9, 0.0)
					elif t.kind == "rank":
						_seal4(Rect2(x - ss * 0.42, y + cs * 0.3, ss * 0.84, ss * 0.84), Game.rank_name(), false, 0.85, 0.0)
					else:
						_seal_col(Rect2(x - cs * 0.5, y + cs * 0.3, cs, cs * 2.0), "記事" if t.kind != "combo" else "格局", false)
					continue
				_vchar(tf if t.font == "title" else bf, Vector2(x, y + t.size * 0.5), t.ch, t.size, t.col)
				y += cs * 1.12
			x -= colw

	## 直排的一個字；逗號、句號放在字格右上。
	func _vchar(f: Font, c: Vector2, ch: String, size: float, col: Color) -> void:
		var s := int(size)
		var p := c
		if ch in CORNER:
			p += Vector2(size * 0.28, -size * 0.28)
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, s)
		draw_string(f, p + Vector2(-w.x * 0.5, (f.get_ascent(s) - f.get_descent(s)) * 0.5 - s * 0.04), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, s, col)

	## 方印：四字作兩行、由右往左讀；一、兩字則一行。bai 為白文（朱底白字），否則朱文（朱框朱字）。
	func _seal4(r: Rect2, text: String, bai: bool, alpha: float, rot: float) -> void:
		draw_set_transform(r.get_center(), rot, Vector2.ONE)
		var half := r.size * 0.5
		var rr := Rect2(-half, r.size)
		var red := Color(UA.ZHU, alpha)
		if bai:
			draw_texture_rect(UA.seal_tex(), rr, false, Color(1, 1, 1, alpha))
		else:
			draw_rect(rr.grow(-r.size.x * 0.04), red, false, maxf(1.5, r.size.x * 0.06))
		var tc := Color(UA.SEAL_TEXT, alpha) if bai else red
		var f := UA.font("title")
		var n := text.length()
		if n >= 3:
			var cs2 := r.size.x * 0.4
			# 右行先讀：第一、二字在右，第三、四字在左
			var pos := [Vector2(0.24, -0.23), Vector2(0.24, 0.23), Vector2(-0.24, -0.23), Vector2(-0.24, 0.23)]
			for k in mini(n, 4):
				_vchar(f, pos[k] * r.size.x, text[k], cs2, tc)
		elif n == 2:
			var cs2 := r.size.x * 0.42
			_vchar(f, Vector2(0, -r.size.y * 0.22), text[0], cs2, tc)
			_vchar(f, Vector2(0, r.size.y * 0.22), text[1], cs2, tc)
		elif n == 1:
			_vchar(f, Vector2.ZERO, text, r.size.x * 0.66, tc)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## 長方印：直排兩字。
	func _seal_col(r: Rect2, text: String, bai: bool) -> void:
		var red := Color(UA.ZHU, 0.9)
		if bai:
			draw_texture_rect(UA.seal_tex(), r, false, Color(1, 1, 1, 0.92))
		else:
			draw_rect(r.grow(-r.size.x * 0.05), red, false, maxf(1.5, r.size.x * 0.08))
		var f := UA.font("title")
		var tc := Color(UA.SEAL_TEXT, 0.95) if bai else red
		var cs2 := r.size.x * 0.66
		for k in text.length():
			_vchar(f, Vector2(r.get_center().x, r.position.y + r.size.y * (k + 0.5) / text.length()), text[k], cs2, tc)

	func _yr() -> String:
		return "元" if Game.year == 1 else Defs.cn_big(Game.year)


## 給內部類別用的靜態入口。
class ScrollPainterRef:
	static func date_short(t: String) -> String:
		var p := t.split(" ")
		return p[0] + p[p.size() - 1] if p.size() >= 3 else t
