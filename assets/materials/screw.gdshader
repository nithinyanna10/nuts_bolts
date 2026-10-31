shader_type spatial;
// Per-instance color (MultiMesh): rgb = rust tint, alpha = roughness variation.

uniform float metallic : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_min : hint_range(0.0, 1.0) = 0.3;
uniform float roughness_max : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = metallic;
	ROUGHNESS = mix(roughness_min, roughness_max, COLOR.a);
}
