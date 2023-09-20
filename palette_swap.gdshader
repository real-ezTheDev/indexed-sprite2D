shader_type canvas_item;

uniform vec4 color : source_color;
uniform usampler2D index_as_r;

void fragment() {
	// Place fragment code here.
	vec2 uv = UV;
	uint palette_index = texture(index_as_r, vec2(uv)).r;
	if (palette_index == uint(2)) {
		COLOR = color;
	}
}
