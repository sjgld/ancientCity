extends Node
## 遊戲中所有靜態資料：地形、貨物、建築、品級、政令、車船。

const N := 100            # 地圖邊長（格）
const DAY_SEC := 0.5      # 一倍速下一日的秒數

enum T { GRASS, WATER, FOREST, HILL, MOUNTAIN }
enum Z { NONE, RES, COM, IND, FARM }

const ZONE_NAMES := ["", "民居", "市肆", "作坊", "農田"]
const ZONE_COLORS := [
	Color(0, 0, 0, 0),
	Color(0.35, 0.75, 0.35, 0.32),
	Color(0.3, 0.5, 0.9, 0.32),
	Color(0.9, 0.7, 0.2, 0.32),
	Color(0.65, 0.45, 0.2, 0.32),
]

const CARGO := {
	"grain":     {"name": "糧", "price": 2.0,  "color": Color(0.85, 0.72, 0.3)},
	"fish":      {"name": "魚", "price": 3.0,  "color": Color(0.5, 0.7, 0.8)},
	"wood":      {"name": "木", "price": 3.0,  "color": Color(0.55, 0.38, 0.2)},
	"stone":     {"name": "石", "price": 3.0,  "color": Color(0.6, 0.6, 0.6)},
	"iron":      {"name": "鐵", "price": 5.0,  "color": Color(0.35, 0.35, 0.4)},
	"silk":      {"name": "絲", "price": 8.0,  "color": Color(0.95, 0.92, 0.8)},
	"tea":       {"name": "茶", "price": 9.0,  "color": Color(0.35, 0.6, 0.3)},
	"ware":      {"name": "器物", "price": 7.0, "color": Color(0.7, 0.5, 0.3)},
	"cloth":     {"name": "綢緞", "price": 16.0, "color": Color(0.8, 0.25, 0.25)},
	"porcelain": {"name": "瓷器", "price": 22.0, "color": Color(0.4, 0.55, 0.85)},
}
const CARGO_ORDER := ["grain", "fish", "wood", "stone", "iron", "silk", "tea", "ware", "cloth", "porcelain"]
const FOOD := ["grain", "fish"]
const LUXURY := ["cloth", "porcelain", "tea"]

const RANKS := [
	{"name": "村", "pop": 0,     "radius": 22, "reward": 0},
	{"name": "鎮", "pop": 300,   "radius": 30, "reward": 1500},
	{"name": "縣", "pop": 1000,  "radius": 38, "reward": 3000},
	{"name": "州", "pop": 2500,  "radius": 48, "reward": 6000},
	{"name": "府", "pop": 6000,  "radius": 62, "reward": 12000},
	{"name": "京", "pop": 15000, "radius": 90, "reward": 30000},
]

# 自然生長的分區建築，各三級
const GROW := {
	"house":    {"zone": Z.RES, "names": ["茅舍", "瓦屋", "宅院"],   "pop": [5, 12, 24]},
	"shop":     {"zone": Z.COM, "names": ["攤鋪", "商號", "酒樓"],   "jobs": [3, 6, 12], "sell": [1.0, 2.0, 4.0]},
	"workshop": {"zone": Z.IND, "names": ["作坊", "工坊", "大工場"], "jobs": [4, 8, 14], "make": [3.0, 6.0, 10.0]},
	"farm":     {"zone": Z.FARM, "names": ["田畝", "農莊", "莊園"],  "jobs": [2, 3, 4],  "yield": [8.0, 11.0, 14.0]},
}
const ZONE_GROW := ["", "house", "shop", "workshop", "farm"]

# 玩家建造的建築
# cat: civic 民政 / industry 產業 / transport 交通 / deco 景觀
# cover: 服務範圍；produce: 每月產出（滿員）；jobs: 職缺
const B := {
	"yamen":     {"name": "縣衙", "cat": "", "size": 2, "cost": 0, "upkeep": 10, "rank": 0, "jobs": 6,
		"cover": {"security": 9, "beauty": 5}, "desc": "一城之治所，道路由此通達四方。"},
	"well":      {"name": "水井", "cat": "civic", "size": 1, "cost": 80, "upkeep": 2, "rank": 0,
		"cover": {"water": 5}, "desc": "供附近民居汲水，瓦屋以上必備。"},
	"granary":   {"name": "糧倉", "cat": "civic", "size": 1, "cost": 250, "upkeep": 4, "rank": 0, "jobs": 2,
		"store": {"food": 600}, "desc": "增加糧食儲量，秋收方能過冬。"},
	"warehouse": {"name": "貨棧", "cat": "civic", "size": 1, "cost": 250, "upkeep": 4, "rank": 1, "jobs": 2,
		"store": {"goods": 300}, "desc": "增加各類貨物儲量。"},
	"constable": {"name": "捕快房", "cat": "civic", "size": 1, "cost": 300, "upkeep": 10, "rank": 1, "jobs": 4,
		"cover": {"security": 9}, "desc": "緝捕盜賊，維持治安。"},
	"clinic":    {"name": "醫館", "cat": "civic", "size": 1, "cost": 350, "upkeep": 12, "rank": 1, "jobs": 4,
		"cover": {"health": 8}, "desc": "懸壺濟世，減少疫病。"},
	"firewatch": {"name": "望火樓", "cat": "civic", "size": 1, "cost": 300, "upkeep": 10, "rank": 1, "jobs": 4,
		"cover": {"fire": 9}, "desc": "登高望火，及早撲救。"},
	"school":    {"name": "私塾", "cat": "civic", "size": 1, "cost": 400, "upkeep": 12, "rank": 1, "jobs": 3,
		"cover": {"edu": 8}, "desc": "教化子弟，宅院與酒樓所需。"},
	"temple":    {"name": "寺廟", "cat": "civic", "size": 2, "cost": 800, "upkeep": 18, "rank": 1, "jobs": 5,
		"cover": {"faith": 12, "beauty": 4}, "desc": "晨鐘暮鼓，安定民心。"},
	"theater":   {"name": "戲樓", "cat": "civic", "size": 1, "cost": 600, "upkeep": 15, "rank": 2, "jobs": 6,
		"cover": {"fun": 10, "beauty": 3}, "desc": "鑼鼓喧天，百姓同樂。"},
	"academy":   {"name": "書院", "cat": "civic", "size": 2, "cost": 1500, "upkeep": 40, "rank": 3, "jobs": 8,
		"cover": {"edu": 18, "beauty": 6}, "desc": "名儒講學之所，教化遠播。"},

	"lumber":    {"name": "伐木場", "cat": "industry", "size": 1, "cost": 200, "upkeep": 4, "rank": 0, "jobs": 5,
		"produce": {"wood": 12.0}, "place": "forest", "pollute": 1, "desc": "需建於林地旁（周圍至少四格林木）。"},
	"quarry":    {"name": "採石場", "cat": "industry", "size": 1, "cost": 250, "upkeep": 5, "rank": 0, "jobs": 6,
		"produce": {"stone": 10.0}, "place": "hill", "pollute": 4, "desc": "需建於丘陵上。"},
	"fishery":   {"name": "漁場", "cat": "industry", "size": 1, "cost": 150, "upkeep": 3, "rank": 0, "jobs": 3,
		"produce": {"fish": 10.0}, "place": "shore", "pollute": 0, "desc": "需建於水邊。"},
	"mine":      {"name": "鐵礦", "cat": "industry", "size": 1, "cost": 400, "upkeep": 8, "rank": 1, "jobs": 8,
		"produce": {"iron": 8.0}, "place": "mountain", "pollute": 6, "desc": "需建於山上。"},
	"mulberry":  {"name": "桑園", "cat": "industry", "size": 1, "cost": 200, "upkeep": 4, "rank": 1, "jobs": 4,
		"produce": {"silk": 6.0}, "place": "grass", "pollute": 0, "desc": "種桑養蠶，產生絲。"},
	"tea":       {"name": "茶園", "cat": "industry", "size": 1, "cost": 300, "upkeep": 5, "rank": 2, "jobs": 4,
		"produce": {"tea": 6.0}, "place": "hill", "pollute": 0, "desc": "需建於丘陵上。"},
	"kiln":      {"name": "瓷窯", "cat": "industry", "size": 1, "cost": 600, "upkeep": 10, "rank": 3, "jobs": 8,
		"produce": {"porcelain": 6.0}, "consume": {"stone": 6.0}, "place": "land", "pollute": 6,
		"desc": "以石料（瓷土）燒製瓷器，價高利厚。"},

	"station":   {"name": "驛站", "cat": "transport", "size": 1, "cost": 150, "upkeep": 3, "rank": 0,
		"place": "road", "catch": 4, "desc": "車馬貨運站，須臨道路。可收發周圍四格內產業之貨。"},
	"dock":      {"name": "碼頭", "cat": "transport", "size": 1, "cost": 300, "upkeep": 5, "rank": 1,
		"place": "shore", "catch": 4, "desc": "船運碼頭，須臨水。"},

	"garden":    {"name": "園林", "cat": "deco", "size": 1, "cost": 60, "upkeep": 2, "rank": 0,
		"cover": {"beauty": 4}, "desc": "亭臺池石，提升周圍地價。"},
	"archway":   {"name": "牌坊", "cat": "deco", "size": 1, "cost": 300, "upkeep": 3, "rank": 2,
		"cover": {"beauty": 6}, "desc": "旌表之坊，壯一城之觀。"},
	"pagoda":    {"name": "寶塔", "cat": "deco", "size": 1, "cost": 1200, "upkeep": 12, "rank": 3,
		"cover": {"beauty": 11, "faith": 6}, "desc": "七級浮屠，遠近可見。"},
	"belltower": {"name": "鐘鼓樓", "cat": "deco", "size": 2, "cost": 2200, "upkeep": 25, "rank": 4,
		"cover": {"beauty": 14, "fun": 8}, "desc": "晨鐘暮鼓，報時全城。"},

	"town":      {"name": "外邑", "cat": "", "size": 2, "cost": 0, "upkeep": 0, "rank": 0, "desc": "遠方大城，收購各色貨物。"},
}

const CATEGORIES := [
	{"id": "road", "name": "道路"},
	{"id": "zone", "name": "分區"},
	{"id": "civic", "name": "民政"},
	{"id": "industry", "name": "產業"},
	{"id": "transport", "name": "交通"},
	{"id": "deco", "name": "景觀"},
]

const ROAD_TOOLS := [
	{"id": "road_dirt", "name": "土路", "cost": 5, "rank": 0, "desc": "每格五兩，過水成橋（二十五兩）。"},
	{"id": "road_stone", "name": "石板路", "cost": 15, "rank": 1, "desc": "車行更快，地價更高。"},
	{"id": "canal", "name": "運河", "cost": 40, "rank": 1, "desc": "開鑿水道，令船隻深入內陸。"},
	{"id": "wall", "name": "城牆", "cost": 20, "rank": 1, "desc": "城牆跨路處自成城門，略增治安與地價。"},
	{"id": "bulldoze", "name": "拆除", "cost": 2, "rank": 0, "desc": "拆除建築、道路、城牆或填平運河。"},
]
const ZONE_TOOLS := [
	{"id": "zone_1", "name": "民居", "rank": 0, "desc": "百姓安居之所。須臨道路。"},
	{"id": "zone_2", "name": "市肆", "rank": 0, "desc": "商鋪酒肆，售賣器物綢緞。須臨道路。"},
	{"id": "zone_3", "name": "作坊", "rank": 0, "desc": "將木、鐵、絲加工為器物、綢緞。須臨道路。"},
	{"id": "zone_4", "name": "農田", "rank": 0, "desc": "產糧。距道路三格內皆可，近水更肥沃。"},
	{"id": "zone_0", "name": "撤銷分區", "rank": 0, "desc": "撤銷分區並拆除其上之民間建築。"},
]

const VEHICLES := {
	"oxcart":    {"name": "牛車", "mode": "road",  "cap": 15, "speed": 0.8, "cost": 300,  "upkeep": 6,  "rank": 0},
	"horsecart": {"name": "馬車", "mode": "road",  "cap": 25, "speed": 1.4, "cost": 650,  "upkeep": 12, "rank": 2},
	"barge":     {"name": "漕船", "mode": "water", "cap": 60, "speed": 1.0, "cost": 900,  "upkeep": 15, "rank": 1},
	"junk":      {"name": "福船", "mode": "water", "cap": 120, "speed": 1.3, "cost": 1900, "upkeep": 28, "rank": 3},
}

const POLICIES := {
	"light_tax":  {"name": "輕徭薄賦", "rank": 0, "upkeep": 0,  "desc": "稅收減兩成，民心大悅。"},
	"farming":    {"name": "勸課農桑", "rank": 0, "upkeep": 30, "desc": "農田與桑園產量增兩成五。"},
	"fire_ban":   {"name": "禁火令",   "rank": 1, "upkeep": 20, "desc": "火災機率減半，民心略減。"},
	"water_work": {"name": "興修水利", "rank": 1, "upkeep": 60, "desc": "防範洪水，農田增產一成。"},
	"open_trade": {"name": "開市通商", "rank": 2, "upkeep": 40, "desc": "商稅與外邑貿易收入增兩成。"},
	"education":  {"name": "興學重教", "rank": 2, "upkeep": 50, "desc": "教化範圍擴大，宅院更易興起。"},
	"baojia":     {"name": "保甲連坐", "rank": 2, "upkeep": 25, "desc": "治安大增，然民心稍減。"},
	"grand_canal":{"name": "漕運總督", "rank": 3, "upkeep": 80, "desc": "船隻航速增三成。"},
}

const TOWNS := [
	{"name": "洛陽", "mult": {"porcelain": 1.6, "cloth": 1.5, "tea": 1.3, "grain": 1.2}},
	{"name": "揚州", "mult": {"silk": 1.5, "grain": 1.4, "fish": 1.2, "ware": 1.2}},
	{"name": "成都", "mult": {"iron": 1.5, "ware": 1.4, "porcelain": 1.3, "stone": 1.2}},
]

# 格局：特定建築擺在一起即成立，外形隨之改變，並收入圖鑑。史實從寬，重在畫面與氛圍。
# income：每處每月額外收入（兩）
const COMBOS := [
	{"id": "hongqiao", "name": "虹橋", "income": 30,
		"verse": "飛梁跨汴，舟過其下，市在其上。",
		"text": "《清明上河圖》正中那座橋。不立橋柱，以短木交錯疊成拱，大船可直接從橋下駛過；橋面兩側擺滿攤販，是全城最熱鬧的地方。",
		"rule": "跨水兩格以上的橋，兩頭三格內共有兩家以上市肆"},
	{"id": "wazi", "name": "瓦子", "income": 25,
		"verse": "勾欄瓦舍，燈火通宵。",
		"text": "宋代城裡的娛樂區。勾欄裡說書、雜劇、傀儡戲輪番上演，周圍酒樓茶肆林立，入夜張燈結綵，是市民的夜生活所在。",
		"rule": "戲樓三格內有兩家商號或酒樓"},
	{"id": "caoyun", "name": "漕運", "income": 40,
		"verse": "千艘銜尾，歲漕百萬。",
		"text": "汴河連接江南與京城，南方的糧米經漕船源源北上。碼頭邊倉廒林立，縴夫、腳夫、帳房日夜不停，是一座城的命脈。",
		"rule": "碼頭三格內有糧倉或貨棧，且碼頭開有水路"},
]


# 詔令：依序達成，可得賞銀
const QUESTS := [
	{"id": "res", "text": "劃設民居十格", "reward": 200},
	{"id": "farm", "text": "開墾農田五畝", "reward": 200},
	{"id": "well", "text": "鑿一口水井", "reward": 100},
	{"id": "pop50", "text": "人丁達五十", "reward": 300},
	{"id": "granary", "text": "修建糧倉", "reward": 200},
	{"id": "shop", "text": "市肆開張三家", "reward": 300},
	{"id": "tile", "text": "出現第一座瓦屋", "reward": 300},
	{"id": "zhen", "text": "晉升為鎮", "reward": 500},
	{"id": "route", "text": "開闢第一條貨運路線", "reward": 500},
	{"id": "temple", "text": "修建寺廟", "reward": 500},
	{"id": "trade", "text": "單月貿易收入百兩", "reward": 800},
	{"id": "court", "text": "出現第一座宅院", "reward": 1000},
	{"id": "xian", "text": "晉升為縣", "reward": 1500},
	{"id": "lux", "text": "城中積存綢緞或瓷器二十", "reward": 1000},
	{"id": "zhou", "text": "晉升為州", "reward": 3000},
	{"id": "pagoda", "text": "修建寶塔", "reward": 2000},
	{"id": "fu", "text": "晉升為府", "reward": 5000},
	{"id": "jing", "text": "晉升為京師", "reward": 0},
]

const ERAS := ["開元", "元豐", "宣和", "景德", "太平", "天聖", "熙寧", "大觀"]
const MONTHS := ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "臘月"]
const SEASONS := ["春", "夏", "秋", "冬"]
const STEMS := ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
# 各月農作係數（秋收）
const HARVEST := [0.2, 0.4, 0.6, 0.8, 1.0, 1.0, 1.4, 2.2, 2.0, 0.6, 0.2, 0.1]

var font: Font


func _init() -> void:
	font = load("res://fonts/LXGWWenKaiTC-Medium.ttf")


static func cn_num(n: int) -> String:
	var d := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n < 0:
		return "負" + cn_num(-n)
	if n < 10:
		return d[n]
	if n < 20:
		return "十" + ("" if n == 10 else d[n % 10])
	if n < 100:
		return d[n / 10] + "十" + ("" if n % 10 == 0 else d[n % 10])
	return str(n)


static func cargo_name(c: String) -> String:
	return CARGO[c]["name"] if CARGO.has(c) else c


static func season_of(month: int) -> int:
	return month / 3


static func combo(id: String) -> Dictionary:
	for c in COMBOS:
		if c.id == id:
			return c
	return {}
