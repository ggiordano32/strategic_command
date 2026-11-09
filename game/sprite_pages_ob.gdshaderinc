// The oblique soldier sheets are two texture pages (no side over 4096: a WebGL context's MAX_TEXTURE_SIZE, the Tab S7
// drew every man black with one 4096 x 5784 sheet). Frame rects stay in the pages stacked: a frame at y >= ob_split is in
// page 1 (ob_shade1 / ob_mask1) at y - ob_split. Include after `ob_sheet` (page 0's size) is declared. Both reads of a
// pair use one page (a frame never crosses the cut); the branch is on a value constant over a card, and the sample uses
// the gradients taken before it.
uniform sampler2D ob_shade1 : filter_linear_mipmap, repeat_disable;
uniform sampler2D ob_mask1 : filter_linear_mipmap, repeat_disable;
uniform vec2 ob_sheet1 = vec2(1024.0, 1024.0);   // page 1's size
uniform float ob_split = 1048576.0;              // the stacked row where page 1 starts (huge: one page)

vec4 ob_read(sampler2D a, sampler2D b, vec2 p) {
	vec2 gx = dFdx(p);
	vec2 gy = dFdy(p);
	if (p.y >= ob_split) {
		vec2 sz = ob_sheet1;
		return textureGrad(b, vec2(p.x, p.y - ob_split) / sz, gx / sz, gy / sz);
	}
	return textureGrad(a, p / ob_sheet, gx / ob_sheet, gy / ob_sheet);
}

vec4 ob_read_lod0(sampler2D a, sampler2D b, vec2 p) {
	if (p.y >= ob_split) {
		return textureLod(b, vec2(p.x, p.y - ob_split) / ob_sheet1, 0.0);
	}
	return textureLod(a, p / ob_sheet, 0.0);
}
