#version 120

#define SCANLINE_STRENGTH_MIN 0.88
#define SCANLINE_STRENGTH_MAX 0.95
#define COLOR_BOOST_EVEN 7.0
#define COLOR_BOOST_ODD 1.9
#define MASK_STRENGTH 0.25
#define GAMMA_INPUT 2.2
#define GAMMA_OUTPUT 2.2

/////////////////////////////////////////////////////////////////////////////

uniform vec2 rubyInputSize;
uniform vec2 rubyOutputSize;
uniform vec2 rubyTextureSize;

varying vec2 v_texCoord;
varying vec2 prescale;


#if defined(VERTEX)

attribute vec4 a_position;

void main() {
  gl_Position = a_position;
  v_texCoord = vec2(a_position.x + 1.0, 1.0 - a_position.y) / 2.0 * rubyInputSize;
  prescale = ceil(rubyOutputSize / rubyInputSize);
}


#elif defined(FRAGMENT)

uniform sampler2D rubyTexture;

#define GAMMA_IN(color)   pow(color, vec4(GAMMA_INPUT))
#define GAMMA_OUT(color)  pow(color, vec4(1.0 / GAMMA_OUTPUT))


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

vec4 tex2D_linear(in sampler2D sampler, in vec2 uv) {

	// subtract 0.5 here and add it again after the floor to centre the texel
	vec2 texCoord = uv * rubyTextureSize - vec2(0.5);
	vec2 s0t0 = floor(texCoord) + vec2(0.5);
	vec2 s0t1 = s0t0 + vec2(0.0, 1.0);
	vec2 s1t0 = s0t0 + vec2(1.0, 0.0);
	vec2 s1t1 = s0t0 + vec2(1.0);

	vec2 invTexSize = 1.0 / rubyTextureSize;
	vec4 c_s0t0 = GAMMA_IN(texture2D(sampler, s0t0 * invTexSize));
	vec4 c_s0t1 = GAMMA_IN(texture2D(sampler, s0t1 * invTexSize));
	vec4 c_s1t0 = GAMMA_IN(texture2D(sampler, s1t0 * invTexSize));
	vec4 c_s1t1 = GAMMA_IN(texture2D(sampler, s1t1 * invTexSize));

	vec2 weight = fract(texCoord);

	vec4 c0 = c_s0t0 + (c_s1t0 - c_s0t0) * weight.x;
	vec4 c1 = c_s0t1 + (c_s1t1 - c_s0t1) * weight.x;

	return (c0 + (c1 - c0) * weight.y);
}

vec4 add_vga_overlay(vec4 color) {
  // scanlines
  vec2 mask_coords = gl_FragCoord.xy;

  vec3 lum_factors = vec3(0.2126, 0.7152, 0.0722);
  float luminance = dot(lum_factors, color.rgb);

  float even_odd = floor(mod(mask_coords.y, 2.0));
  float dim_factor = mix(1.0-SCANLINE_STRENGTH_MAX, 1.0-SCANLINE_STRENGTH_MIN, luminance);
  float scanline_dim = clamp(even_odd + dim_factor, 0.0, 1.0);

  color.rgb *= vec3(scanline_dim);

  // color boost
  color.rgb *= mix(vec3(COLOR_BOOST_EVEN), vec3(COLOR_BOOST_ODD), even_odd);

  float saturation = mix(1.2, 1.03, even_odd);
  float l = length(color);
  color.r = pow(color.r + 1e-5, saturation);
  color.g = pow(color.g + 1e-5, saturation);
  color.b = pow(color.b + 1e-5, saturation);
  color = normalize(color)*l;

  // mask
  color.rgb *= mask_weights(mask_coords, MASK_STRENGTH);
  return color;
}


void main() {
  const vec2 halfp = vec2(0.5);
  vec2 texel_floored = floor(v_texCoord);
  vec2 s = fract(v_texCoord);
  vec2 region_range = halfp - halfp / prescale;

  vec2 center_dist = s - halfp;
  vec2 f = (center_dist - clamp(center_dist, -region_range, region_range)) * prescale + halfp;

  vec2 mod_texel = min(texel_floored + f, rubyInputSize-halfp);
  vec4 color = tex2D_linear(rubyTexture, mod_texel / rubyTextureSize);

  color = add_vga_overlay(color);

  gl_FragColor = clamp(GAMMA_OUT(color), 0.0, 1.0);
}

#endif
