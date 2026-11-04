shader_type canvas_item;
// 長卷畫心的絹本調色：降飽和、偏向絹色、山水提青綠、絹紋斑駁；
// 上下邊緣化入雲煙，左右兩端淡出（段與段交疊處即成雲煙）。

uniform vec4 silk : source_color = vec4(0.90, 0.84, 0.70, 1.0);
uniform float mist_top = 0.15;     // 上緣雲煙占高度比例
uniform float mist_bot = 0.11;
uniform float fade_l = 0.0;        // 左端淡出寬度（像素），0 為不淡出
uniform float fade_r = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 col = mix(silk.rgb, c.rgb, c.a);
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	vec2 sz = 1.0 / TEXTURE_PIXEL_SIZE;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	// 草地、農田等黃綠者多降飽和；山、水等青藍者少降
	float blueish = smoothstep(0.0, 0.12, col.b - col.r);
	col = mix(vec3(l), col, mix(0.45, 0.8, blueish));
	col = mix(col, col * vec3(0.85, 1.02, 1.05), blueish * 0.5);
	// 乘絹色，略壓暗偏暖
	col = col * mix(vec3(1.0), silk.rgb * 1.12, 0.55);
	// 絹紋：細經緯加低頻斑駁
	float weave = sin(px.x * 2.6) * sin(px.y * 2.4) * 0.012;
	float blot = (noise((px + seed) / 90.0) - 0.5) * 0.06 + (noise((px + seed) / 23.0) - 0.5) * 0.025;
	col += weave + blot * vec3(0.9, 0.85, 0.7);
	// 上下雲煙，邊緣隨橫向起伏
	float n = noise(vec2((px.x + seed) / 160.0, 0.0)) * 0.08 + noise(vec2((px.x + seed) / 55.0, 3.0)) * 0.04;
	float top = smoothstep(mist_top + n, 0.0, UV.y);
	float bot = smoothstep(1.0 - mist_bot - n, 1.0, UV.y);
	col = mix(col, silk.rgb * 1.02, clamp(top + bot, 0.0, 1.0));
	// 左右淡出：邊界隨縱向起伏，像一團一團的雲
	float a = 1.0;
	if (fade_l > 0.0) {
		float w = fade_l * (0.75 + 0.5 * noise(vec2(3.0, (px.y + seed) / 70.0)));
		a *= smoothstep(0.0, w, px.x);
	}
	if (fade_r > 0.0) {
		float w = fade_r * (0.75 + 0.5 * noise(vec2(7.0, (px.y + seed) / 70.0)));
		a *= smoothstep(0.0, w, sz.x - px.x);
	}
	COLOR = vec4(col, a);
}
