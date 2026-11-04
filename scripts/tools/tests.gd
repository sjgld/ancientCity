extends Node
## 規則測試：不開視窗、不跑整局，幾秒內驗證路、橋、轄境、大事記與存讀檔。
##   godot --headless --path . -- --test            全部
##   godot --headless --path . -- --test=bridge,reach  只跑指定幾項
## 每項在一塊清空的地上自己布置場景；結束時印出結果，有失敗則以代碼 1 結束。

var main
var fails := 0
var passes := 0


func run(only: Array) -> void:
	await get_tree().process_frame
	main.title_mode = false
	main.ui.show_title(false)
	var all := ["bridge", "reach", "arch", "numbers", "annals"]
	for name in all:
		if not only.is_empty() and name not in only:
			continue
		print("── ", name)
		_reset()
		call("test_" + name)
	print("TESTS %s：%d 過，%d 失敗" % ["OK" if fails == 0 else "FAILED", passes, fails])
	get_tree().quit(1 if fails > 0 else 0)


func check(name: String, cond: bool, info: Variant = "") -> void:
	if cond:
		passes += 1
		print("  PASS ", name)
	else:
		fails += 1
		print("  FAIL ", name, "　", info)


## 一塊乾淨的地：縣衙在 (50,50)，周圍 40 格清成平地，河在 x = 60..63。
func _reset(river := true) -> void:
	Game.new_game("清河", 4242)
	Game.speed = 0
	Game.money = 1e7
	for b in Game.buildings.values().duplicate():
		if b.type != "yamen" and b.type != "town":
			Game.remove_building(b.id)
	var y: Dictionary = Game.buildings[Game.yamen_id]
	for i in Game.N * Game.N:
		if Game.bld[i] >= 0:
			continue
		Game.road[i] = 0
		Game.zone[i] = 0
		Game.wall[i] = 0
		Game.canal[i] = 0
		Game.terrain[i] = Defs.T.GRASS
	# 縣衙搬到 (50,50) 一帶：直接改座標，重填佔地
	for dy in y.size:
		for dx in y.size:
			Game.bld[Game.idx(y.x + dx, y.y + dy)] = -1
	y.x = 50
	y.y = 50
	for dy in y.size:
		for dx in y.size:
			Game.bld[Game.idx(50 + dx, 50 + dy)] = y.id
	if river:
		for yy in Game.N:
			for x in range(60, 64):
				Game.terrain[Game.idx(x, yy)] = Defs.T.WATER
	Game._finish_setup()
	Game.money = 1e7
	Game._update_connectivity()


func _line(a: Vector2i, b: Vector2i, kind := 1) -> void:
	Game.build_roads(main.line_cells(a, b), kind)


# ───────────────────────── 各項 ─────────────────────────

func test_bridge() -> void:
	_line(Vector2i(57, 40), Vector2i(66, 40))
	var straight := true
	for x in range(57, 67):
		straight = straight and Game.road[Game.idx(x, 40)] > 0
	check("筆直跨河可修", straight)
	_line(Vector2i(61, 40), Vector2i(61, 44))
	check("橋中間不能岔出", Game.road[Game.idx(61, 41)] == 0)
	_line(Vector2i(57, 41), Vector2i(66, 41))
	var side := 0
	for x in range(60, 64):
		side += 1 if Game.road[Game.idx(x, 41)] > 0 else 0
	check("不能緊貼著並排", side == 0, side)
	_line(Vector2i(57, 30), Vector2i(61, 33))
	check("不能在水上轉彎", Game.road[Game.idx(61, 30)] > 0 and Game.road[Game.idx(61, 31)] == 0)
	_line(Vector2i(57, 46), Vector2i(66, 46))
	check("隔幾格再修一座可以", Game.road[Game.idx(62, 46)] > 0)
	Game.rank = 1
	_line(Vector2i(57, 46), Vector2i(66, 46), 2)
	check("土橋可升石板", Game.road[Game.idx(62, 46)] == 2)
	var planned := {}
	var bad := []
	for c in main.line_cells(Vector2i(57, 20), Vector2i(61, 23)):
		var cost: int = Game.road_cost(c.x, c.y, 1, planned)
		if cost == -2:
			bad.append(c)
		elif cost >= 0:
			planned[Game.idx(c.x, c.y)] = true
	check("預覽標出轉彎格", not bad.is_empty(), bad)


func test_reach() -> void:
	# 縣衙東側一條路，向東延伸
	_line(Vector2i(52, 51), Vector2i(58, 51))
	check("修完路立刻通達（不必等下一天）", Game.conn_road(Game.idx(58, 51)))
	# 設施：水井離路兩格可通，三格不通
	var w1 := Game.place_building("well", 55, 53)
	var b1 := Game.building_at(55, 53)
	check("水井兩格內有路即通", w1 == "" and b1.conn, w1)
	Game.place_building("well", 55, 55)
	var b2 := Game.building_at(55, 55)
	check("水井三格外不通", not b2.conn)
	check("說明寫附近沒有路", Game.conn_reason(b2).begins_with("附近沒有路"), Game.conn_reason(b2))
	# 民居仍須緊貼：斜角不算
	var hid := Game.add_building("house", 53, 52, {"age": 30})
	check("民居緊貼路才通", Game.buildings[hid].conn)
	var hid2 := Game.add_building("house", 59, 52, {"age": 30})
	check("民居只碰斜角不通", not Game.buildings[hid2].conn, Game.conn_reason(Game.buildings[hid2]))
	# 沒接上縣衙的路
	_line(Vector2i(40, 40), Vector2i(44, 40))
	Game.place_building("well", 42, 41)
	var b3 := Game.building_at(42, 41)
	check("路沒接縣衙", not b3.conn and Game.conn_reason(b3) == "旁邊的路沒有接到縣衙", Game.conn_reason(b3))
	# 轄境是圓：村 18 格。沿路繞遠但直線在圈內者仍算通達
	_line(Vector2i(51, 49), Vector2i(51, 38))
	_line(Vector2i(51, 38), Vector2i(57, 38))
	_line(Vector2i(57, 38), Vector2i(57, 44))
	var i := Game.idx(57, 44)
	check("繞路但在圈內仍通達", Game.conn_road(i), "沿路 %d 格" % Game.road_dist[i])
	_line(Vector2i(51, 38), Vector2i(51, 30))
	check("圈外的路不通達", not Game.conn_road(Game.idx(51, 30)) and Game.road_dist[Game.idx(51, 30)] >= 0)
	Game.place_building("well", 52, 30)
	var b4 := Game.building_at(52, 30)
	check("說明寫在轄境之外", Game.conn_reason(b4).begins_with("在轄境之外"), Game.conn_reason(b4))
	Game.rank = 2
	Game._update_connectivity()
	check("晉升後轄境擴大", Game.conn_road(Game.idx(51, 30)))


func test_arch() -> void:
	Game.rank = 1
	_line(Vector2i(57, 45), Vector2i(66, 45), 2)
	check("河上的石板橋畫成石拱橋", Game.arch_bridge(61, 45))
	_line(Vector2i(57, 55), Vector2i(66, 55), 1)
	check("土橋仍是平橋", not Game.arch_bridge(61, 55))
	# 小池塘：不通航
	for y in range(30, 33):
		for x in range(40, 43):
			Game.terrain[Game.idx(x, y)] = Defs.T.WATER
	Game._compute_shore()
	_line(Vector2i(39, 31), Vector2i(43, 31), 2)
	check("小池塘上的石橋是平橋", Game.road[Game.idx(41, 31)] == 2 and not Game.arch_bridge(41, 31))
	var sp := Game.bridge_span(62, 45)
	check("橋段長四格", sp.size() == 3 and sp[1] == 4, sp)


func test_numbers() -> void:
	var cases := {0: "〇", 7: "七", 15: "十五", 300: "三百", 835: "八百三十五", 1500: "一千五百",
		10005: "一萬〇五", 73649: "七萬三千六百四十九"}
	for n in cases:
		check("cn_big(%d)" % n, Defs.cn_big(n) == cases[n], Defs.cn_big(n))


func test_annals() -> void:
	check("開城入大事記", Game.annals.size() == 1 and Game.annals[0].kind == "found")
	Game.chronicle("rank", "人口超過三百，升為鎮。")
	Game.scrolls.append({"file": "user://x.jpg", "title": "清河鎮圖", "date": "開元元年正月", "rank": 1, "pop": 300, "w": 1, "h": 1})
	Game.save_game()
	Game.new_game("別處", 1)
	Game.load_game()
	check("大事記隨存檔", Game.annals.size() == 2 and Game.annals[1].kind == "rank", Game.annals.size())
	check("卷匣隨存檔", Game.scrolls.size() == 1)
