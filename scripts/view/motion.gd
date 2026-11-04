extends RefCounted
## 動態：全局的三個時鐘與「動態：全／簡」設定。
##
## - 介面時鐘 ui_t：實際時間，暫停也照走。用於介面動效、印、橫幅。
## - 世界時鐘 world_t：隨一、二、四倍速，暫停即停。用於人、車船、匠人、火。
## - 環境時鐘 ambient_t：風、水、雲、紙籤輕擺；暫停時以三成速度慢動，畫面不至於死掉。
##
## 「簡」只保留回饋類動畫（落成、拆除、印），去掉環境循環與裝飾性的過場。
## 動畫只讀模擬，不寫模擬，也不用 Game.rng。

static var full := true
static var ui_t := 0.0
static var world_t := 0.0
static var ambient_t := 0.0


static func tick(delta: float) -> void:
	ui_t += delta
	var sp: float = Game.SPEEDS[Game.speed] if Game.running else 0.0
	world_t += delta * sp
	ambient_t += delta * maxf(0.3, sp)


## 世界時鐘的倍率（暫停為零）；匠人揮錘、車輪等用。
static func world_rate() -> float:
	return float(Game.SPEEDS[Game.speed]) if Game.running else 0.0


## 「簡」模式下過場時長歸零。
static func dur(sec: float) -> float:
	return sec if full else 0.0


static func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * t
