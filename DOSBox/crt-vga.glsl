#version 120

varying vec2 v_texCoord;
uniform vec2 rubyInputSize;
uniform vec2 rubyOutputSize;
uniform vec2 rubyTextureSize;
varying vec2 prescale; // const set by vertex shader


#define SCANLINE_STRENGTH_MIN 0.88
#define SCANLINE_STRENGTH_MAX 0.95
#define COLOR_BOOST_EVEN 7.7
#define COLOR_BOOST_ODD 1.9
#define MASK_STRENGTH 0.3
#define MASK_TYPE 2.0
#define GAMMA_INPUT 2.2
#define GAMMA_OUTPUT 2.2

#define GAMMA_IN(color)     pow(color, vec4(GAMMA_INPUT, GAMMA_INPUT, GAMMA_INPUT, GAMMA_INPUT))
#define GAMMA_OUT(color)    pow(color, vec4(1.0 / GAMMA_OUTPUT, 1.0 / GAMMA_OUTPUT, 1.0 / GAMMA_OUTPUT, 1.0 / GAMMA_OUTPUT))


#if defined(VERTEX)

attribute vec4 a_position;

void main() {
	gl_Position = a_position;
	v_texCoord = vec2(a_position.x+1.0,1.0-a_position.y)/2.0*rubyInputSize;
	prescale = ceil(rubyOutputSize / rubyInputSize);
}

#elif defined(FRAGMENT)

uniform sampler2D rubyTexture;


vec3 mask_weights(vec2 coord, float mask_strength, int mask_type)
{
   vec3 weights = vec3(1.,1.,1.);
   float on = 1.;
   float off = 1.-mask_strength;
   vec3 red     = vec3(on,  off, off);
   vec3 green   = vec3(off, on,  off);
   vec3 blue    = vec3(off, off, on );
   vec3 magenta = vec3(on,  off, on );
   vec3 yellow  = vec3(on,  on,  off);
   vec3 cyan    = vec3(off, on,  on );
   vec3 black   = vec3(off, off, off);
   vec3 white   = vec3(on,  on,  on );
   int w, z = 0;

   // This pattern is used by a few layouts, so we'll define it here
   vec3 aperture_weights = mix(magenta, green, floor(mod(coord.x, 2.0)));

   if(mask_type == 0) return weights;

   else if(mask_type == 1){
      // classic aperture for RGB panels; good for 1080p, too small for 4K+
      // aka aperture_1_2_bgr
      weights  = aperture_weights;
      return weights;
   }

   else if(mask_type == 2){
      // 2x2 shadow mask for RGB panels; good for 1080p, too small for 4K+
      // aka delta_1_2x1_bgr
      vec3 inverse_aperture = mix(green, magenta, floor(mod(coord.x, 2.0)));
      weights               = mix(aperture_weights, inverse_aperture, floor(mod(coord.y, 2.0)));
      return weights;
   }

   else if(mask_type == 3){
      // slot mask for RGB panels; looks okay at 1080p, looks better at 4K
      // {magenta, green, black,   black},
      // {magenta, green, magenta, green},
      // {black,   black, magenta, green}

      // GLSL can't do 2D arrays until version 430, so do this stupid thing instead for compatibility's sake:
      // First lay out the horizontal pixels in arrays
      vec3 slotmask_x1[4] = vec3[](magenta, green, black,   black);
      vec3 slotmask_x2[4] = vec3[](magenta, green, magenta, green);
      vec3 slotmask_x3[4] = vec3[](black,   black, magenta, green);

      // find the vertical index
      w = int(floor(mod(coord.y, 3.0)));

      // find the horizontal index
      z = int(floor(mod(coord.x, 4.0)));

      // do a big, dumb comparison in place of a 2D array
      weights = (w == 1) ? slotmask_x1[z] : (w == 2) ? slotmask_x2[z] :  slotmask_x3[z];
    }

   if(mask_type == 4){
      // classic aperture for RBG panels; good for 1080p, too small for 4K+
      weights  = mix(yellow, blue, floor(mod(coord.x, 2.0)));
      return weights;
   }

   else if(mask_type == 5){
      // 2x2 shadow mask for RBG panels; good for 1080p, too small for 4K+
      vec3 inverse_aperture = mix(blue, yellow, floor(mod(coord.x, 2.0)));
      weights               = mix(mix(yellow, blue, floor(mod(coord.x, 2.0))), inverse_aperture, floor(mod(coord.y, 2.0)));
      return weights;
   }

   else if(mask_type == 6){
      // aperture_1_4_rgb; good for simulating lower
      vec3 ap4[4] = vec3[](red, green, blue, black);

      z = int(floor(mod(coord.x, 4.0)));

      weights = ap4[z];
      return weights;
   }

   else if(mask_type == 7){
      // aperture_2_5_bgr
      vec3 ap3[5] = vec3[](red, magenta, blue, green, green);

      z = int(floor(mod(coord.x, 5.0)));

      weights = ap3[z];
      return weights;
   }

   else if(mask_type == 8){
      // aperture_3_6_rgb

      vec3 big_ap[7] = vec3[](red, red, yellow, green, cyan, blue, blue);

      w = int(floor(mod(coord.x, 7.)));

      weights = big_ap[w];
      return weights;
   }

   else if(mask_type == 9){
      // reduced TVL aperture for RGB panels
      // aperture_2_4_rgb

      vec3 big_ap_rgb[4] = vec3[](red, yellow, cyan, blue);

      w = int(floor(mod(coord.x, 4.)));

      weights = big_ap_rgb[w];
      return weights;
   }

   else if(mask_type == 10){
      // reduced TVL aperture for RBG panels

      vec3 big_ap_rbg[4] = vec3[](red, magenta, cyan, green);

      w = int(floor(mod(coord.x, 4.)));

      weights = big_ap_rbg[w];
      return weights;
   }

   else if(mask_type == 11){
      // delta_1_4x1_rgb; dunno why this is called 4x1 when it's obviously 4x2 /shrug
      vec3 delta_1_1[4] = vec3[](red, green, blue, black);
      vec3 delta_1_2[4] = vec3[](blue, black, red, green);

      w = int(floor(mod(coord.y, 2.0)));
      z = int(floor(mod(coord.x, 4.0)));

      weights = (w == 1) ? delta_1_1[z] : delta_1_2[z];
      return weights;
   }

   else if(mask_type == 12){
      // delta_2_4x1_rgb
      vec3 delta_2_1[4] = vec3[](red, yellow, cyan, blue);
      vec3 delta_2_2[4] = vec3[](cyan, blue, red, yellow);

      z = int(floor(mod(coord.x, 4.0)));

      weights = (w == 1) ? delta_2_1[z] : delta_2_2[z];
      return weights;
   }

   else if(mask_type == 13){
      // delta_2_4x2_rgb
      vec3 delta_1[4] = vec3[](red, yellow, cyan, blue);
      vec3 delta_2[4] = vec3[](red, yellow, cyan, blue);
      vec3 delta_3[4] = vec3[](cyan, blue, red, yellow);
      vec3 delta_4[4] = vec3[](cyan, blue, red, yellow);

      w = int(floor(mod(coord.y, 4.0)));
      z = int(floor(mod(coord.x, 4.0)));

      weights = (w == 1) ? delta_1[z] : (w == 2) ? delta_2[z] : (w == 3) ? delta_3[z] : delta_4[z];
      return weights;
   }

   else if(mask_type == 14){
      // slot mask for RGB panels; too low-pitch for 1080p, looks okay at 4K, but wants 8K+
      // {magenta, green, black, black,   black, black},
      // {magenta, green, black, magenta, green, black},
      // {black,   black, black, magenta, green, black}
      vec3 slot2_1[6] = vec3[](magenta, green, black, black,   black, black);
      vec3 slot2_2[6] = vec3[](magenta, green, black, magenta, green, black);
      vec3 slot2_3[6] = vec3[](black,   black, black, magenta, green, black);

      w = int(floor(mod(coord.y, 3.0)));
      z = int(floor(mod(coord.x, 6.0)));

      weights = (w == 1) ? slot2_1[z] : (w == 2) ? slot2_2[z] : slot2_3[z];
      return weights;
   }

   else if(mask_type == 15){
      // slot_2_4x4_rgb
      // {red,   yellow, cyan,  blue,  red,   yellow, cyan,  blue },
      // {red,   yellow, cyan,  blue,  black, black,  black, black},
      // {red,   yellow, cyan,  blue,  red,   yellow, cyan,  blue },
      // {black, black,  black, black, red,   yellow, cyan,  blue }
      vec3 slotmask_RBG_x1[8] = vec3[](red,   yellow, cyan,  blue,  red,   yellow, cyan,  blue );
      vec3 slotmask_RBG_x2[8] = vec3[](red,   yellow, cyan,  blue,  black, black,  black, black);
      vec3 slotmask_RBG_x3[8] = vec3[](red,   yellow, cyan,  blue,  red,   yellow, cyan,  blue );
      vec3 slotmask_RBG_x4[8] = vec3[](black, black,  black, black, red,   yellow, cyan,  blue );

      // find the vertical index
      w = int(floor(mod(coord.y, 4.0)));

      // find the horizontal index
      z = int(floor(mod(coord.x, 8.0)));

      weights = (w == 1) ? slotmask_RBG_x1[z] : (w == 2) ? slotmask_RBG_x2[z] : (w == 3) ? slotmask_RBG_x3[z] : slotmask_RBG_x4[z];
      return weights;
    }

   else if(mask_type == 16){
      // slot mask for RBG panels; too low-pitch for 1080p, looks okay at 4K, but wants 8K+
      // {yellow, blue,  black,  black},
      // {yellow, blue,  yellow, blue},
      // {black,  black, yellow, blue}
      vec3 slot2_1[4] = vec3[](yellow, blue,  black,  black);
      vec3 slot2_2[4] = vec3[](yellow, blue,  yellow, blue);
      vec3 slot2_3[4] = vec3[](black,  black, yellow, blue);

      w = int(floor(mod(coord.y, 3.0)));
      z = int(floor(mod(coord.x, 4.0)));

      weights = (w == 1) ? slot2_1[z] : (w == 2) ? slot2_2[z] : slot2_3[z];
      return weights;
   }

   else if(mask_type == 17){
      // slot_2_5x4_bgr
      // {red,   magenta, blue,  green, green, red,   magenta, blue,  green, green},
      // {black, blue,    blue,  green, green, red,   red,     black, black, black},
      // {red,   magenta, blue,  green, green, red,   magenta, blue,  green, green},
      // {red,   red,     black, black, black, black, blue,    blue,  green, green}
      vec3 slot_1[10] = vec3[](red,   magenta, blue,  green, green, red,   magenta, blue,  green, green);
      vec3 slot_2[10] = vec3[](black, blue,    blue,  green, green, red,   red,     black, black, black);
      vec3 slot_3[10] = vec3[](red,   magenta, blue,  green, green, red,   magenta, blue,  green, green);
      vec3 slot_4[10] = vec3[](red,   red,     black, black, black, black, blue,    blue,  green, green);

      w = int(floor(mod(coord.y, 4.0)));
      z = int(floor(mod(coord.x, 10.0)));

      weights = (w == 1) ? slot_1[z] : (w == 2) ? slot_2[z] : (w == 3) ? slot_3[z] : slot_4[z];
      return weights;
   }

   else if(mask_type == 18){
      // same as above but for RBG panels
      // {red,   yellow, green, blue,  blue,  red,   yellow, green, blue,  blue },
      // {black, green,  green, blue,  blue,  red,   red,    black, black, black},
      // {red,   yellow, green, blue,  blue,  red,   yellow, green, blue,  blue },
      // {red,   red,    black, black, black, black, green,  green, blue,  blue }
      vec3 slot_1[10] = vec3[](red,   yellow, green, blue,  blue,  red,   yellow, green, blue,  blue );
      vec3 slot_2[10] = vec3[](black, green,  green, blue,  blue,  red,   red,    black, black, black);
      vec3 slot_3[10] = vec3[](red,   yellow, green, blue,  blue,  red,   yellow, green, blue,  blue );
      vec3 slot_4[10] = vec3[](red,   red,    black, black, black, black, green,  green, blue,  blue );

      w = int(floor(mod(coord.y, 4.0)));
      z = int(floor(mod(coord.x, 10.0)));

      weights = (w == 1) ? slot_1[z] : (w == 2) ? slot_2[z] : (w == 3) ? slot_3[z] : slot_4[z];
      return weights;
   }

   else if(mask_type == 19){
      // slot_3_7x6_rgb
      // {red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue},
      // {red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue},
      // {red,   red,   yellow, green, cyan,  blue,  blue,  black, black, black,  black,  black, black, black},
      // {red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue},
      // {red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue},
      // {black, black, black,  black, black, black, black, black, red,   red,    yellow, green, cyan,  blue}

      vec3 slot_1[14] = vec3[](red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue);
      vec3 slot_2[14] = vec3[](red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue);
      vec3 slot_3[14] = vec3[](red,   red,   yellow, green, cyan,  blue,  blue,  black, black, black,  black,  black, black, black);
      vec3 slot_4[14] = vec3[](red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue);
      vec3 slot_5[14] = vec3[](red,   red,   yellow, green, cyan,  blue,  blue,  red,   red,   yellow, green,  cyan,  blue,  blue);
      vec3 slot_6[14] = vec3[](black, black, black,  black, black, black, black, black, red,   red,    yellow, green, cyan,  blue);

      w = int(floor(mod(coord.y, 6.0)));
      z = int(floor(mod(coord.x, 14.0)));

      weights = (w == 1) ? slot_1[z] : (w == 2) ? slot_2[z] : (w == 3) ? slot_3[z] : (w == 4) ? slot_4[z] : (w == 5) ? slot_5[z] : slot_6[z];
      return weights;
   }

   else return weights;
}


void main() {
  // scaling
	const vec2 halfp = vec2(0.5);
	vec2 texel_floored = floor(v_texCoord);
	vec2 s = fract(v_texCoord);
	vec2 region_range = halfp - halfp / prescale;

	vec2 center_dist = s - halfp;

	vec2 f = (center_dist - clamp(center_dist, -region_range, region_range)) * prescale + halfp;
	vec2 mod_texel = min(texel_floored + f, rubyInputSize-halfp);
  vec4 color = GAMMA_IN(texture2D(rubyTexture, mod_texel / rubyTextureSize));

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
  color.rgb *= mask_weights(mask_coords, MASK_STRENGTH, int(MASK_TYPE));

	gl_FragColor = clamp(GAMMA_OUT(color), 0.0, 1.0);
}

#endif
