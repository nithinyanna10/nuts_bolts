shader_type spatial;
render_mode unshaded, cull_disabled;
// Inspect-view measuring tools, drawn at the same scale as the object (1 mm = units_per_mm meters).
// Ruler / caliper strip: mm ticks from one edge. Gauge leaf (pitch_mm > 0): sawtooth edge at that thread pitch.

uniform vec3 panel_color : source_color = vec3(0.1, 0.11, 0.13);
uniform vec3 tick_color : source_color = vec3(0.95, 0.9, 0.6);
uniform float length_mm = 90.0;
uniform bool horizontal = false;
uniform float pitch_mm = 0.0;

void fragment() {
	float a = horizontal ? UV.x : UV.y; // along the scale
	float c = horizontal ? 1.0 - UV.y : UV.x; // distance from the edge the ticks grow from
	float m = a * length_mm;
	vec3 col = panel_color;
	if (pitch_mm > 0.0) {
		float tooth = 1.0 - abs(2.0 * fract(m / pitch_mm) - 1.0);
		if (c > 0.45 + 0.5 * tooth) {
			discard;
		}
		col = tick_color;
	} else {
		float nearest = floor(m + 0.5);
		bool major = mod(nearest, 10.0) < 0.5;
		bool mid = mod(nearest, 5.0) < 0.5;
		float len = major ? 0.62 : (mid ? 0.42 : 0.25);
		if (abs(m - nearest) < (major ? 0.16 : 0.1) && c < len) {
			col = tick_color;
		}
	}
	ALBEDO = col;
}
