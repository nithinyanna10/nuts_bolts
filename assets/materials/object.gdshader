shader_type spatial;
render_mode cull_disabled;
// One shader for every pile object (MultiMesh) and for the single promoted hover/held node.
// Mesh UV.x: 0 = rigid part, 1 = shaft body (stretched to the object's length), 2 = shaft tip (follows the body end).
// Mesh UV.y: 1 = drive mark (dark).
// MultiMesh: COLOR = material tint (rgb) + roughness variation (a); INSTANCE_CUSTOM = (length factor, pitch in mesh units).

uniform float metallic : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_min : hint_range(0.0, 1.0) = 0.3;
uniform float roughness_max : hint_range(0.0, 1.0) = 0.7;
uniform float body_len = 17.0;
uniform float thread_dark : hint_range(0.0, 1.0) = 0.45;
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
uniform bool use_override = false; // single node instead of MultiMesh
uniform vec4 override_color = vec4(1.0); // raw, same as MultiMesh COLOR (no sRGB conversion)
uniform vec4 override_data = vec4(1.0, 1.0, 0.0, 0.0);

varying float v_flag;
varying float v_mark;
varying float v_thread;

void vertex() {
	vec4 d = use_override ? override_data : INSTANCE_CUSTOM;
	v_flag = UV.x;
	v_mark = UV.y;
	if (UV.x > 0.5 && UV.x < 1.5) {
		VERTEX.y *= d.x;
	} else if (UV.x > 1.5) {
		VERTEX.y += body_len * (1.0 - d.x);
	}
	v_thread = UV.x > 0.5 ? -VERTEX.y / max(d.y, 0.01) : 0.0;
}

void fragment() {
	vec4 inst = use_override ? override_color : COLOR;
	vec3 base = inst.rgb;
	float rough = mix(roughness_min, roughness_max, inst.a);
	float met = metallic;
	if (v_flag > 0.5) {
		float groove = smoothstep(0.55, 0.9, abs(fract(v_thread) - 0.5) * 2.0);
		base *= 1.0 - thread_dark * groove;
		rough = mix(rough, 0.9, groove);
	}
	if (v_mark > 0.5) {
		base = vec3(0.025);
		rough = 0.95;
		met = 0.0;
	}
	ALBEDO = base;
	METALLIC = met;
	ROUGHNESS = rough;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = vec3(1.0, 0.85, 0.4) * highlight * (0.25 + rim * 0.9);
}
