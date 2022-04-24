#version 120

/*
	 Phosphor shader - Copyright (C) 2011 caligari.

	 Ported by Hyllian.

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

*/

/*

// Parameter lines go here:
// 0.5 = the spot stays inside the original pixel
// 1.0 = the spot bleeds up to the center of next pixel
#pragma parameter SPOT_WIDTH "CRTCaligari Spot Width" 0.9 0.1 1.5 0.05
#pragma parameter SPOT_HEIGHT "CRTCaligari Spot Height" 0.65 0.1 1.5 0.05
// Constants used with gamma correction.
#pragma parameter GAMMA_INPUT "CRTCaligari Input Gamma" 2.4 0.0 5.0 0.1
#pragma parameter GAMMA_OUTPUT "CRTCaligari Output Gamma" 2.2 0.0 5.0 0.1

*/

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 a_position;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec2 v_texCoord;
COMPAT_VARYING vec2 v_texCoord2;
COMPAT_VARYING vec2 onex;
COMPAT_VARYING vec2 oney;
COMPAT_VARYING vec2 prescale; // const set by vertex shader

vec4 _oPosition1;
uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int rubyFrameCount;
uniform COMPAT_PRECISION vec2 rubyOutputSize;
uniform COMPAT_PRECISION vec2 rubyTextureSize;
uniform COMPAT_PRECISION vec2 rubyInputSize;



#define SourceSize vec4(rubyTextureSize, 1.0 / rubyTextureSize) //either rubyTextureSize or rubyInputSize

void main()
{
	gl_Position = a_position;
	v_texCoord = vec2(a_position.x + 1.0, 1.0 - a_position.y) / 2.0 * rubyInputSize / rubyTextureSize;
  v_texCoord2 = vec2(a_position.x+1.0,1.0-a_position.y)/2.0*rubyInputSize;
  prescale = ceil(rubyOutputSize / rubyInputSize);

	onex = vec2(SourceSize.z, 0.0);
	oney = vec2(0.0, SourceSize.w);
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int rubyFrameCount;
uniform COMPAT_PRECISION vec2 rubyOutputSize;
uniform COMPAT_PRECISION vec2 rubyTextureSize;
uniform COMPAT_PRECISION vec2 rubyInputSize;
uniform sampler2D rubyTexture;
COMPAT_VARYING vec2 v_texCoord;
COMPAT_VARYING vec2 v_texCoord2;
COMPAT_VARYING vec2 onex;
COMPAT_VARYING vec2 oney;
COMPAT_VARYING vec2 prescale; // const set by vertex shader

// compatibility #defines
#define Source rubyTexture
#define vTexCoord v_texCoord.xy

#define SourceSize vec4(rubyTextureSize, 1.0 / rubyTextureSize) //either rubyTextureSize or rubyInputSize
#define rubyOutputSize vec4(rubyOutputSize, 1.0 / rubyOutputSize)

#ifdef PARAMETER_UNIFORM
// All parameter floats need to have COMPAT_PRECISION in front of them
uniform COMPAT_PRECISION float SPOT_WIDTH;
uniform COMPAT_PRECISION float SPOT_HEIGHT;
uniform COMPAT_PRECISION float GAMMA_INPUT;
uniform COMPAT_PRECISION float GAMMA_OUTPUT;
#else
#define SPOT_WIDTH 0.95
#define SPOT_HEIGHT 0.65

#define SCANLINE_STRENGTH_MIN 0.88
#define SCANLINE_STRENGTH_MAX 0.95
#define COLOR_BOOST_EVEN 11.0
#define COLOR_BOOST_ODD 2.1
#define MASK_STRENGTH 0.3

#define GAMMA_INPUT 2.2
#define GAMMA_OUTPUT 2.35
#endif

#define GAMMA_IN(color)     pow(color,vec4(GAMMA_INPUT))
#define GAMMA_OUT(color)    pow(color, vec4(1.0 / GAMMA_OUTPUT))

#define TEX2D(coords)	GAMMA_IN( COMPAT_TEXTURE(Source, coords) )

// Macro for weights computing
#define WEIGHT(w) \
	if(w>1.0) w=1.0; \
w = 1.0 - w * w; \
w = w * w;


vec3 mask_weights(vec2 coord, float mask_strength)
{
   float on = 1.;
   float off = 1.-mask_strength;
   vec3 green   = vec3(off, on,  off);
   vec3 magenta = vec3(on,  off, on );

   vec3 aperture_weights = mix(magenta, green, floor(mod(coord.x, 2.0)));
   vec3 inverse_aperture = mix(green, magenta, floor(mod(coord.x, 2.0)));
   vec3 weights = mix(aperture_weights, inverse_aperture, floor(mod(coord.y, 2.0)));
   return weights;
}

vec4 render_hires() {
    vec2 coords = ( vTexCoord * SourceSize.xy );
    vec2 pixel_center = floor( coords ) + vec2(0.5, 0.5);
    vec2 texture_coords = pixel_center * SourceSize.zw;

    vec4 color = TEX2D( texture_coords );

    float dx = coords.x - pixel_center.x;

    float h_weight_00 = dx / SPOT_WIDTH;
    WEIGHT( h_weight_00 );

    color *= vec4( h_weight_00, h_weight_00, h_weight_00, h_weight_00  );

    // get closest horizontal neighbour to blend
    vec2 coords01;
    if (dx>0.0) {
      coords01 = onex;
      dx = 1.0 - dx;
    } else {
      coords01 = -onex;
      dx = 1.0 + dx;
    }
    vec4 colorNB = TEX2D( texture_coords + coords01 );

    float h_weight_01 = dx / SPOT_WIDTH;
    WEIGHT( h_weight_01 );

    color = color + colorNB * vec4( h_weight_01 );

    //////////////////////////////////////////////////////
    // Vertical Blending
    float dy = coords.y - pixel_center.y;
    float v_weight_00 = dy / SPOT_HEIGHT;
    WEIGHT( v_weight_00 );
    color *= vec4( v_weight_00 );

    // get closest vertical neighbour to blend
    vec2 coords10;
    if (dy>0.0) {
      coords10 = oney;
      dy = 1.0 - dy;
    } else {
      coords10 = -oney;
      dy = 1.0 + dy;
    }
    colorNB = TEX2D( texture_coords + coords10 );

    float v_weight_10 = dy / SPOT_HEIGHT;
    WEIGHT( v_weight_10 );

    color = color + colorNB * vec4( v_weight_10 * h_weight_00, v_weight_10 * h_weight_00, v_weight_10 * h_weight_00, v_weight_10 * h_weight_00 );

    colorNB = TEX2D(  texture_coords + coords01 + coords10 );

    color = color + colorNB * vec4( v_weight_10 * h_weight_01, v_weight_10 * h_weight_01, v_weight_10 * h_weight_01, v_weight_10 * h_weight_01 );

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

    return clamp(GAMMA_OUT(color), 0.0, 1.0);
}

vec4 render_lores() {
    const vec2 halfp = vec2(0.5);
    vec2 texel_floored = floor(v_texCoord2);
    vec2 s = fract(v_texCoord2);
    vec2 region_range = halfp - halfp / prescale;

    vec2 center_dist = s - halfp;
    vec2 f = (center_dist - clamp(center_dist, -region_range, region_range)) * prescale + halfp;

    vec2 mod_texel = min(texel_floored + f, rubyInputSize-halfp);
    return texture2D(rubyTexture, mod_texel / rubyTextureSize);
}

void main()
{
  if (rubyInputSize.y >= 350) {
    gl_FragColor = render_hires();

  } else {
    gl_FragColor = render_lores();
  }
}

#endif
