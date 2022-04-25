#version 120

#define SPOT_WIDTH 0.95
#define SPOT_HEIGHT 0.65

#define LORES_SCANLINE_STRENGTH_MIN 0.88
#define LORES_SCANLINE_STRENGTH_MAX 0.95
#define LORES_COLOR_BOOST_EVEN 7.0
#define LORES_COLOR_BOOST_ODD 1.9
#define LORES_MASK_STRENGTH 0.5
#define LORES_GAMMA_INPUT 2.2
#define LORES_GAMMA_OUTPUT 2.2

#define HIRES_SCANLINE_STRENGTH_MIN 0.88
#define HIRES_SCANLINE_STRENGTH_MAX 0.95
#define HIRES_COLOR_BOOST_EVEN 11.0
#define HIRES_COLOR_BOOST_ODD 2.1
#define HIRES_MASK_STRENGTH 0.3
#define HIRES_GAMMA_INPUT 2.2
#define HIRES_GAMMA_OUTPUT 2.35

/////////////////////////////////////////////////////////////////////////////

uniform vec2 rubyInputSize;
uniform vec2 rubyOutputSize;
uniform vec2 rubyTextureSize;

varying vec2 v_texCoord_hires;
varying vec2 v_texCoord_lores;
varying vec2 onex;
varying vec2 oney;
varying vec2 prescale;

#define SourceSize vec4(rubyTextureSize, 1.0 / rubyTextureSize)


#if defined(VERTEX)

attribute vec4 a_position;

void main() {
	gl_Position = a_position;

  v_texCoord_lores = vec2(a_position.x + 1.0, 1.0 - a_position.y) / 2.0 * rubyInputSize;
	v_texCoord_hires = v_texCoord_lores / rubyTextureSize;

  prescale = ceil(rubyOutputSize / rubyInputSize);

	onex = vec2(SourceSize.z, 0.0);
	oney = vec2(0.0, SourceSize.w);
}


#elif defined(FRAGMENT)

uniform sampler2D rubyTexture;

#define LORES_GAMMA_IN(color)   pow(color, vec4(LORES_GAMMA_INPUT))
#define HIRES_GAMMA_IN(color)   pow(color, vec4(HIRES_GAMMA_INPUT))

#define TEX2D(coords)	HIRES_GAMMA_IN(texture2D(rubyTexture, coords))

// Macro for weights computing
#define WEIGHT(w) \
	if (w > 1.0) w = 1.0; \
  w = 1.0 - w * w; \
  w = w * w;


vec3 mask_weights(vec2 coord, float mask_strength) {
  float on = 1.;
  float off = 1.-mask_strength;
  vec3 green   = vec3(off, on,  off);
  vec3 magenta = vec3(on,  off, on );

  vec3 aperture_weights = mix(magenta, green, floor(mod(coord.x, 2.0)));
  vec3 inverse_aperture = mix(green, magenta, floor(mod(coord.x, 2.0)));
  vec3 weights = mix(aperture_weights, inverse_aperture, floor(mod(coord.y, 2.0)));
  return weights;
}

vec4 add_vga_overlay(vec4 color, float scanlineStrengthMin, float scanlineStrengthMax, float color_boost_even, float color_boost_odd, float mask_strength) {
  // scanlines
  vec2 mask_coords = gl_FragCoord.xy;

  vec3 lum_factors = vec3(0.2126, 0.7152, 0.0722);
  float luminance = dot(lum_factors, color.rgb);

  float even_odd = floor(mod(mask_coords.y, 2.0));
  float dim_factor = mix(1.0 - scanlineStrengthMax, 1.0 - scanlineStrengthMin, luminance);
  float scanline_dim = clamp(even_odd + dim_factor, 0.0, 1.0);

  color.rgb *= vec3(scanline_dim);

  // color boost
  color.rgb *= mix(vec3(color_boost_even), vec3(color_boost_odd), even_odd);

  float saturation = mix(1.2, 1.03, even_odd);
  float l = length(color);
  color.r = pow(color.r + 1e-5, saturation);
  color.g = pow(color.g + 1e-5, saturation);
  color.b = pow(color.b + 1e-5, saturation);
  color = normalize(color)*l;

  // mask
  color.rgb *= mask_weights(mask_coords, mask_strength);
  return color;
}

vec4 render_hires() {
  vec2 coords = v_texCoord_hires.xy * SourceSize.xy;
  vec2 pixel_center = floor(coords) + vec2(0.5, 0.5);
  vec2 texture_coords = pixel_center * SourceSize.zw;

  vec4 color = TEX2D(texture_coords);

  float dx = coords.x - pixel_center.x;

  float h_weight_00 = dx / SPOT_WIDTH;
  WEIGHT(h_weight_00);

  color *= vec4(h_weight_00, h_weight_00, h_weight_00, h_weight_00);

  // get closest horizontal neighbour to blend
  vec2 coords01;
  if (dx > 0.0) {
    coords01 = onex;
    dx = 1.0 - dx;
  } else {
    coords01 = -onex;
    dx = 1.0 + dx;
  }
  vec4 colorNB = TEX2D(texture_coords + coords01);

  float h_weight_01 = dx / SPOT_WIDTH;
  WEIGHT(h_weight_01);

  color = color + colorNB * vec4(h_weight_01);

  //////////////////////////////////////////////////////
  // Vertical Blending
  float dy = coords.y - pixel_center.y;
  float v_weight_00 = dy / SPOT_HEIGHT;
  WEIGHT(v_weight_00);
  color *= vec4(v_weight_00);

  // get closest vertical neighbour to blend
  vec2 coords10;
  if (dy > 0.0) {
    coords10 = oney;
    dy = 1.0 - dy;
  } else {
    coords10 = -oney;
    dy = 1.0 + dy;
  }
  colorNB = TEX2D(texture_coords + coords10);

  float v_weight_10 = dy / SPOT_HEIGHT;
  WEIGHT(v_weight_10);

  color = color + colorNB * vec4(v_weight_10 * h_weight_00, v_weight_10 * h_weight_00, v_weight_10 * h_weight_00, v_weight_10 * h_weight_00);

  colorNB = TEX2D(texture_coords + coords01 + coords10);

  color = color + colorNB * vec4(v_weight_10 * h_weight_01, v_weight_10 * h_weight_01, v_weight_10 * h_weight_01, v_weight_10 * h_weight_01);

  color = add_vga_overlay(
    color,
    HIRES_SCANLINE_STRENGTH_MIN, HIRES_SCANLINE_STRENGTH_MAX,
    HIRES_COLOR_BOOST_EVEN, HIRES_COLOR_BOOST_ODD,
    HIRES_MASK_STRENGTH
  );

  color = pow(color, vec4(1.0 / HIRES_GAMMA_OUTPUT));
  return clamp(color, 0.0, 1.0);
}


vec4 tex2D_linear(in sampler2D sampler, in vec2 uv) {

	// subtract 0.5 here and add it again after the floor to centre the texel
	vec2 texCoord = uv * rubyTextureSize - vec2(0.5);
	vec2 s0t0 = floor(texCoord) + vec2(0.5);
	vec2 s0t1 = s0t0 + vec2(0.0, 1.0);
	vec2 s1t0 = s0t0 + vec2(1.0, 0.0);
	vec2 s1t1 = s0t0 + vec2(1.0);

	vec2 invTexSize = 1.0 / rubyTextureSize;
	vec4 c_s0t0 = LORES_GAMMA_IN(texture2D(sampler, s0t0 * invTexSize));
	vec4 c_s0t1 = LORES_GAMMA_IN(texture2D(sampler, s0t1 * invTexSize));
	vec4 c_s1t0 = LORES_GAMMA_IN(texture2D(sampler, s1t0 * invTexSize));
	vec4 c_s1t1 = LORES_GAMMA_IN(texture2D(sampler, s1t1 * invTexSize));

	vec2 weight = fract(texCoord);

	vec4 c0 = c_s0t0 + (c_s1t0 - c_s0t0) * weight.x;
	vec4 c1 = c_s0t1 + (c_s1t1 - c_s0t1) * weight.x;

	return (c0 + (c1 - c0) * weight.y);
}

vec4 render_lores() {
  const vec2 halfp = vec2(0.5);
  vec2 texel_floored = floor(v_texCoord_lores);
  vec2 s = fract(v_texCoord_lores);
  vec2 region_range = halfp - halfp / prescale;

  vec2 center_dist = s - halfp;
  vec2 f = (center_dist - clamp(center_dist, -region_range, region_range)) * prescale + halfp;

  vec2 mod_texel = min(texel_floored + f, rubyInputSize-halfp);
  vec4 color = tex2D_linear(rubyTexture, mod_texel / rubyTextureSize);

  color = add_vga_overlay(
    color,
    LORES_SCANLINE_STRENGTH_MIN, LORES_SCANLINE_STRENGTH_MAX,
    LORES_COLOR_BOOST_EVEN, LORES_COLOR_BOOST_ODD,
    LORES_MASK_STRENGTH
  );

  color = pow(color, vec4(1.0 / LORES_GAMMA_OUTPUT));
  return clamp(color, 0.0, 1.0);
}

void main()
{
  if (rubyInputSize.y >= 400) {
    gl_FragColor = render_hires();
  } else {
    gl_FragColor = render_lores();
  }
}

#endif
