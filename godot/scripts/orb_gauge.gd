class_name OrbGauge
extends Control
## A life/mana globe: a glass sphere of swirling liquid whose surface sways at the
## current fill height, set in a forged bronze ring with an ember crest, a wing
## on the outer side and a plaque showing "current / max".
## Recent losses linger as a pale band that drains away after a moment.
## The share held by auras is sealed off at the top of the glass behind a frosted, banded lid.

const RAD := 66.0          # radius of the glass
const LIQUID := """
shader_type canvas_item;
uniform float level = 1.0;    // displayed fill, 0..1
uniform float trail = 1.0;    // recently lost fill, >= level
uniform vec4 deep : source_color;
uniform vec4 bright : source_color;
uniform float pulse = 0.0;    // extra glow, e.g. at low life
uniform float seed = 0.0;
uniform float reserve = 0.0;  // share of the globe held by auras, sealed at the top

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;           // -1..1, y points down
	float r = length(p);
	float t = TIME + seed;
	float mask = 1.0 - smoothstep(1.0 - fwidth(r) * 1.5, 1.0, r);

	// the surface sways less when the globe is nearly empty or full
	float calm = 0.35 + 0.65 * sin(clamp(level, 0.0, 1.0) * 3.14159);
	float wave = (sin(p.x * 4.6 + t * 1.8) * 0.04 + sin(p.x * 9.3 - t * 2.7) * 0.017) * calm;
	float surf = 1.0 - 2.0 * level + wave;
	float tsurf = 1.0 - 2.0 * trail + wave * 0.6;
	float edge = fwidth(p.y) * 1.2;
	float in_l = level > 0.001 ? smoothstep(surf - edge, surf + edge, p.y) : 0.0;
	float in_t = trail > 0.001 ? smoothstep(tsurf - edge, tsurf + edge, p.y) : 0.0;

	// empty glass: smoky and faintly tinted
	vec3 col = deep.rgb * 0.18 + vec3(0.02, 0.018, 0.02);
	col += deep.rgb * 0.25 * fbm(p * 2.0 + vec2(t * 0.05, 0.0));
	col *= 1.0 - 0.55 * r * r;

	// the band just lost, pale and see-through
	col = mix(col, mix(bright.rgb, vec3(1.0, 0.95, 0.85), 0.45) * 0.6, in_t * (1.0 - in_l) * 0.75);

	// liquid: swirling currents, darker with depth, lit from the middle
	vec2 q = p * 1.7;
	float n = fbm(q + vec2(t * 0.12, -t * 0.2) + 1.6 * vec2(fbm(q * 1.2 - vec2(0.0, t * 0.25)), fbm(q * 1.2 + vec2(t * 0.18, 3.1))));
	float depth = clamp((p.y - surf) / max(0.05, 1.0 - surf), 0.0, 1.0);
	vec3 liq = mix(bright.rgb, deep.rgb, smoothstep(0.0, 1.0, 0.15 + depth * 0.85));
	liq = mix(liq, bright.rgb * 1.35, smoothstep(0.42, 0.8, n) * 0.6);
	liq *= 0.4 + 0.75 * (1.0 - r * r);
	liq += bright.rgb * pulse * 0.45 * (1.0 - r);
	// rising bubbles
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float sp = 0.12 + hash(vec2(fi, 2.0)) * 0.18;
		vec2 b = vec2(hash(vec2(fi, 1.0)) * 1.4 - 0.7 + sin(t * 1.3 + fi * 2.1) * 0.05, 1.0 - fract(t * sp + hash(vec2(fi, 3.0))) * 2.2);
		float br = 0.022 + hash(vec2(fi, 4.0)) * 0.025;
		float d = length(p - b);
		float ring = smoothstep(br, br * 0.55, d) - smoothstep(br * 0.6, br * 0.2, d) * 0.6;
		liq += bright.rgb * ring * 0.9 * step(surf + 0.04, b.y);
	}
	col = mix(col, liq, in_l);

	// reserved share: a frosted lid with slanted bands drifting slowly, behind a bright seal line
	float rsurf = -1.0 + 2.0 * reserve;
	float in_r = reserve > 0.001 ? 1.0 - smoothstep(rsurf - edge, rsurf + edge, p.y) : 0.0;
	float band = smoothstep(0.35, 0.5, fract((p.x - p.y) * 5.0 + t * 0.06)) * smoothstep(1.0, 0.65, fract((p.x - p.y) * 5.0 + t * 0.06));
	vec3 res = mix(deep.rgb * 0.5 + vec3(0.07, 0.065, 0.06), mix(bright.rgb, vec3(0.9, 0.85, 0.75), 0.55) * 0.55, band * 0.55);
	res += vec3(0.9, 0.85, 0.75) * 0.12 * fbm(p * 5.0 + vec2(0.0, t * 0.1));
	res *= 1.0 - 0.45 * r * r;
	col = mix(col, res, in_r);
	col += vec3(1.0, 0.86, 0.55) * exp(-abs(p.y - rsurf) * 70.0) * step(0.001, reserve) * 0.9;

	// bright meniscus where the liquid meets the air
	float men = exp(-abs(p.y - surf) * 55.0) * step(0.004, level) * step(level, 0.996);
	col += mix(bright.rgb, vec3(1.0), 0.4) * men * 0.75;

	// glass: dark rim, highlight on top left, caustic crescent on bottom right
	col *= mix(1.0, 0.35, smoothstep(0.72, 1.0, r));
	vec2 h = (p - vec2(-0.3, -0.48)) * vec2(1.0, 1.75);
	col += vec3(1.0, 0.97, 0.92) * smoothstep(0.36, 0.0, length(h)) * 0.32;
	col += vec3(1.0) * smoothstep(0.085, 0.0, length(p - vec2(-0.42, -0.55))) * 0.55;
	float cres = smoothstep(0.78, 0.9, r) * smoothstep(0.99, 0.92, r) * smoothstep(0.35, 0.95, (p.x + p.y) * 0.7071);
	col += mix(bright.rgb, vec3(1.0), 0.5) * cres * 0.45;
	COLOR = vec4(col, mask);
}
"""
static var _shader: Shader

var value := 1.0           # fill to show, 0..1
var text := ""
var deep := Color.DARK_RED
var bright := Color.RED
var gem := Color.ORANGE    # crest colour
var side := -1             # -1: wing on the left (life), 1: on the right (mana)
var low_pulse := false     # glow and throb when the fill is low
var reserve := 0.0         # share of the max held by auras, 0..1, sealed at the top
var reserve_text := ""     # shown on the sealed band when it is tall enough
var shown := 1.0
var trail := 1.0
var _hold := 0.0
var _liquid := ColorRect.new()
var _front := Front.new()
var _mat := ShaderMaterial.new()


func _init() -> void:
	custom_minimum_size = Vector2(200, 184)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(deep_c: Color, bright_c: Color, gem_c: Color, wing_side: int, seed: float) -> void:
	deep = deep_c
	bright = bright_c
	gem = gem_c
	side = wing_side
	if _shader == null:
		_shader = Shader.new()
		_shader.code = LIQUID
	_mat.shader = _shader
	_mat.set_shader_parameter("deep", deep)
	_mat.set_shader_parameter("bright", bright)
	_mat.set_shader_parameter("seed", seed)


func _ready() -> void:
	_liquid.material = _mat
	_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_liquid)
	_front.orb = self
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_front)
	resized.connect(_layout)
	_layout()


func center() -> Vector2:
	return Vector2(size.x / 2.0 - side * 14.0, RAD + 24.0)


func _layout() -> void:
	_liquid.position = center() - Vector2(RAD, RAD)
	_liquid.size = Vector2(RAD, RAD) * 2.0


func _process(delta: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	shown = lerpf(shown, v, 1.0 - exp(-delta * 14.0))
	if v >= trail:
		trail = v
		_hold = 0.0
	else:
		_hold += delta
		if _hold > 0.45:
			trail = move_toward(trail, v, delta * maxf(0.35, (trail - v) * 2.5))
	var pulse := 0.0
	if low_pulse and v < 0.3:
		# a slow, soft throb (#53: was 0.1..1.0 about once a second); not scaled by the 被ダメージ演出 option, so
		# low life stays readable on the orb even with the screen effects off
		pulse = (0.6 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * TAU / Hud.LOW_PERIOD)) * (1.0 - v / 0.3)
	_mat.set_shader_parameter("level", shown)
	_mat.set_shader_parameter("trail", maxf(trail, shown))
	_mat.set_shader_parameter("pulse", pulse)
	_mat.set_shader_parameter("reserve", clampf(reserve, 0.0, 1.0))
	_front.queue_redraw()


func _draw() -> void:
	var c := center()
	# soft shadow and the wing behind the ring
	for i in 4:
		draw_circle(c + Vector2(0, 4), RAD + 16.0 - i * 3.0, Color(0, 0, 0, 0.12))
	_draw_wing(c)


## three tapering blades sweeping outward and down from the ring
func _draw_wing(c: Vector2) -> void:
	var s := float(side)
	for k in 3:
		var a0 := deg_to_rad(-40.0 + k * 28.0)          # angle along the ring, measured from the outer side
		var base := c + Vector2(cos(a0) * s, sin(a0)) * (RAD + 6.0)
		var dir := Vector2(cos(a0 + 0.35) * s, sin(a0 + 0.35))
		var length := 42.0 - k * 8.0
		var tip := base + dir * length + Vector2(0, k * 3.0)
		var nrm := Vector2(-dir.y, dir.x) * (9.0 - k * 1.5)
		var pts := PackedVector2Array([base - nrm, base + dir * length * 0.55 - nrm * 0.7, tip, base + dir * length * 0.6 + nrm * 0.5, base + nrm])
		draw_colored_polygon(pts, Color("#2a1d10"))
		var inner := PackedVector2Array([base - nrm * 0.55, base + dir * length * 0.5 - nrm * 0.35, tip - dir * 3.0, base + nrm * 0.3])
		draw_colored_polygon(inner, Color("#8a6532").lerp(Color("#5a3f1e"), k * 0.3))
		draw_line(base, tip - dir * 2.0, Color("#d8b46a", 0.6), 1.0, true)


## ring, rivets, crest and the number plaque, drawn over the liquid
class Front extends Control:
	var orb: OrbGauge

	func _draw() -> void:
		var c := orb.center()
		var r := OrbGauge.RAD
		# forged ring: dark bed, bronze band lit from above, dark inner lip
		draw_arc(c, r + 5.0, 0, TAU, 96, Color("#140d06"), 13.0, true)
		draw_arc(c, r + 5.0, 0, TAU, 96, Color("#6e4f26"), 9.0, true)
		draw_arc(c, r + 7.0, deg_to_rad(195), deg_to_rad(345), 48, Color("#d9b36a"), 2.0, true)
		draw_arc(c, r + 3.0, deg_to_rad(20), deg_to_rad(160), 48, Color("#3a2812"), 3.0, true)
		draw_arc(c, r + 0.5, 0, TAU, 96, Color("#0a0604"), 2.0, true)
		draw_arc(c, r + 10.5, 0, TAU, 96, Color("#a07a3e", 0.8), 1.2, true)
		# rivets
		for i in 10:
			var a := TAU * i / 10.0 + PI / 10.0
			var q := c + Vector2(cos(a), sin(a)) * (r + 5.0)
			draw_circle(q, 2.6, Color("#24170a"))
			draw_circle(q, 1.9, Color("#b38a48"))
			draw_circle(q + Vector2(-0.6, -0.6), 0.8, Color("#f0d79a"))
		# crest: a faceted ember gem in a pointed setting at the top
		var top := c + Vector2(0, -r - 6.0)
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, -17), top + Vector2(13, 1), top + Vector2(0, 9), top + Vector2(-13, 1)]), Color("#1c1208"))
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, -14), top + Vector2(10, 1), top + Vector2(0, 7), top + Vector2(-10, 1)]), Color("#9a7238"))
		var g := orb.gem
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, -10), top + Vector2(6, 0), top + Vector2(0, 4), top + Vector2(-6, 0)]), g)
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, -10), top + Vector2(6, 0), top + Vector2(0, 0)]), g.lightened(0.45))
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, 4), top + Vector2(-6, 0), top + Vector2(0, 0)]), g.darkened(0.45))
		# plaque with the numbers, hanging off the bottom of the ring
		var pw := 104.0
		var pr := Rect2(c.x - pw / 2.0, c.y + r + 2.0, pw, 22.0)
		draw_rect(pr.grow(2.0), Color("#140d06"))
		draw_rect(pr, Color("#1e150c"))
		draw_rect(pr, Color("#8a6532"), false, 1.5)
		draw_line(pr.position + Vector2(3, 2), pr.position + Vector2(pw - 3, 2), Color("#d9b36a", 0.35), 1.0)
		for sx in [-1.0, 1.0]:
			var e := Vector2(c.x + sx * (pw / 2.0 + 2.0), pr.position.y + 11.0)
			draw_colored_polygon(PackedVector2Array([e + Vector2(0, -8), e + Vector2(sx * 8, 0), e + Vector2(0, 8)]), Color("#8a6532"))
		var ty := pr.position.y + 16.5
		draw_string_outline(Data.ui_font, Vector2(pr.position.x, ty), orb.text, HORIZONTAL_ALIGNMENT_CENTER, pw, 15, 4, Color.BLACK)
		draw_string(Data.ui_font, Vector2(pr.position.x, ty), orb.text, HORIZONTAL_ALIGNMENT_CENTER, pw, 15, orb.bright.lerp(Color.WHITE, 0.7))
		# what the auras hold, written on the sealed band (or just under its seal when the band is thin)
		if orb.reserve > 0.001 and orb.reserve_text != "":
			var by := c.y - r + 2.0 * r * orb.reserve
			var ly := by - 5.0 if orb.reserve > 0.2 else by + 15.0
			draw_string_outline(Data.ui_font, Vector2(c.x - r, ly), orb.reserve_text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, 4, Color.BLACK)
			draw_string(Data.ui_font, Vector2(c.x - r, ly), orb.reserve_text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, Color("#ffe2a8"))
