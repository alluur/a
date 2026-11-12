# Drawing and images

A has a 2D graphics library written in A itself: `gfx` draws into a **surface**, a rectangle of pixels in memory, and `gimg` reads and writes
picture files. Nothing here needs a window or a display server, so every program in this chapter is an ordinary program that draws, prints what it did,
and saves a PNG. The pictures in the chapter are those PNGs.

In this chapter:

* surfaces, pixels and colours;
* lines, circles, rounded rectangles, polygons, arcs and pies;
* gradients, shadows, transparency and clipping;
* text, the built-in fonts, other sizes and your own font files;
* copying pictures, working pixel by pixel, and the picture formats of `gimg`.

Windows and widgets come in the [next chapter](#chap-gui-basics); they use the functions you learn here to paint themselves.

## Surfaces and pixels

A `gfx.Surface` has a width `w`, a height `h` and an array of pixels `px`. A pixel is one `int` of the form `0xAARRGGBB`: alpha, red, green and blue,
eight bits each. Alpha 255 is opaque. The point 0, 0 is the top left corner, x grows to the right and **y grows downwards**.
A new surface is all zeros: transparent black. Every drawing function **clips** to the surface, so drawing outside of it is safe and does nothing. (A width or height below 1 is made 1.)

{{sample gfx/surface_basics}}

{{shot gfx/surface_basics}}

**What to notice**

* `fill(x, y, w, h, c)` is a filled rectangle, `rect` only its outline, `hline` and `vline` take a start and a length.
* `get` outside the surface returns 0 and `put` outside is ignored. Neither stops the program. (`put` also obeys the clip rectangle, see "Clipping" below; `get` does not.)
* A pixel is an `int`, so a surface takes 8 bytes per pixel in memory (`new gfx.Surface(1000, 1000)` is 8 MB). `release()` gives the memory back.
* `gimg.savePng` writes the picture; `savePPM` and `saveBMP` are methods of the surface itself (see "Picture files" below).

## Colours

Colours are plain `int` values; the helper functions build and take them apart. `gfx.rgb(r, g, b)` makes an opaque colour, `gfx.argb(a, r, g, b)` one with
alpha, and `gfx.red`, `green`, `blue` and `alpha` read the parts back. The constants `BLACK`, `WHITE`, `RED`, `GREEN`, `BLUE`, `YELLOW` and `GRAY` are ready to use
(they are the toolkit's colours: `GREEN` is `0xFF30B050`, not pure green).

{{sample gfx/colors}}

{{shot gfx/colors}}

**What to notice**

* `mix(a, b, t)` blends two colours: 0 gives `a`, 255 gives `b`. `lighten(c, t)` and `darken(c, t)` are `mix` with white and with black. The result is always opaque.
* The top bar in the picture is one `vline` per column with `mix(BLUE, YELLOW, x)`: a horizontal gradient is a loop. The other two bars use `lighten` and `darken` the same way.
* `withAlpha(c, a)` keeps the colour and replaces the alpha.

## Lines and circles

`line(x0, y0, x1, y1, c)` draws a line one pixel wide (Bresenham's algorithm, no smoothing). `circle(cx, cy, r, c)` draws the outline and `fillCircle` the disc.

{{sample gfx/lines_circles}}

{{shot gfx/lines_circles}}

**What to notice**

* Shapes drawn later cover earlier ones. The green disc has a white dot on top, drawn with `fillCircle` too.
* A circle with radius 1 is the four pixels around the centre, one with radius 0 a single pixel.
* A colour with alpha below 255 is blended with what is already there; see the section on transparency below.

## Rounded rectangles

`fillRoundRect(x, y, w, h, r, c)` and `roundRect` (outline) draw the shape of a button. A radius that is too big is reduced to half of the smaller side, which gives a "pill".

{{sample gfx/round_rects}}

{{shot gfx/round_rects}}

**What to notice**

* With a radius above 0 the pixels in the corners are not touched, so the background shines through (the first line of output). Radius 0 is a plain rectangle: the yellow one in the picture.
* Draw the fill first and the outline over it, as the first button does.

## Polygons

`fillPolygon(xs, ys, n, c)` fills the polygon whose corners are `xs[i], ys[i]`. It takes 3 to 256 corners (with any other number it draws nothing) and uses the **even-odd rule**: a point is inside when a line
from it to the outside crosses the outline an odd number of times. That is why the middle of the star stays empty.

{{sample gfx/polygons}}

{{shot gfx/polygons}}

**What to notice**

* `icos` and `isin` are integer sine and cosine of an angle in degrees, **multiplied by 1024** (so `1024` means 1.0). The star corners are `centre + radius * icos(angle) / 1024`.
* The five corners are 144 degrees apart, so drawing them in order draws the star in one stroke.
* The corners of a polygon are `int` arrays; an array name is passed as a pointer. Local arrays can be filled with `{ ... }` lists.

## Arcs, ring segments and pies

Angles are in degrees, measured **clockwise from the right** (3 o'clock), because y points down. `arc(cx, cy, r, a0, a1, c)` draws a one pixel outline,
`thickArc(cx, cy, r0, r1, a0, a1, c)` a ring segment between the inner radius `r0` and the outer radius `r1`, and `fillPie(cx, cy, r, a0, a1, c)` a pie slice.

{{sample gfx/arcs_pies}}

{{shot gfx/arcs_pies}}

**What to notice**

* `isin(30)` is 512 and `icos(60)` is 512: half of 1024. `isin` is an approximation (the error is at most 2 out of 1024, about 0.2 %); the section "Plotting with real numbers" at the end shows the exact way.
* Each slice of the pie starts where the previous one ended. Pies and rings are drawn as short straight steps of about 4 degrees, and `arc` as steps of about 2 degrees, so a big pie shows its corners if you look closely.
* A pie of 360 degrees or more is a full disc. The gauges and the pie chart of [the chapter on more widgets](#chap-gui-more-widgets) are made with `thickArc` and `fillPie`.

## Gradients and shadows

`gradientV(x, y, w, h, top, bottom)` fills a rectangle with a vertical gradient. `shadow(x, y, w, h, spread, maxAlpha)` draws `spread` rings of translucent black, one pixel wide each, around a rectangle:
draw it first, then draw the rectangle over it.

{{sample gfx/gradients_shadows}}

{{shot gfx/gradients_shadows}}

**What to notice**

* The first line of output shows the gradient: the top pixel is the first colour and the last row is the second.
* The rings of `shadow` get **darker with the distance** from the rectangle, not lighter: the pixel next to the card is almost the background colour (`0xffededf1`, the ring has alpha 1), the pixel 8 away is darker (`0xffe4e4e8`, alpha 11), and then the shadow stops with a sharp edge.
  A ring at distance `g` from the rectangle (1 is the ring next to it, `spread` the outermost) has the alpha `maxAlpha * g / (spread * spread)`. So `maxAlpha` is not the alpha you see: the darkest ring has `maxAlpha / spread` (11 for 90 and 8). The whole effect is faint. Look at the picture.
* A gradient in another direction is a loop of `vline` or `hline` calls with `mix`, as in the sample above (the red to yellow bar on the right).

## Transparency

A colour whose alpha is below 255 is **blended** with the pixel that is already there, by the drawing functions: `fill`, `line`, `fillCircle`, text, and the others. (`put`, `blit` and `clear` store the colour as it is.)
`blend(x, y, c, cover)` does it for one pixel and scales the alpha by `cover` (0 to 255), which is how the antialiased edges of text are made.
`blitBlend` (see "Copying pictures" below) blends a whole surface.

{{sample gfx/alpha_blending}}

{{shot gfx/alpha_blending}}

**What to notice**

* The overlap of the three circles shows all three colours: each one was blended with what the earlier ones had left.
* `put` stores a colour exactly as it is, alpha included; the drawing functions blend.
* The result of blending is **opaque** (only a colour with alpha 0 changes nothing, so a transparent pixel stays transparent). Drawing a translucent colour onto a transparent pixel (which counts as black) gives a darker opaque pixel (`0xff800000`), not a translucent one.
  So draw translucent shapes over an opaque background, and keep transparent sprites made of opaque shapes on a transparent surface.

## Clipping

`setClip(x, y, w, h)` restricts drawing to a rectangle (cut to the surface); `resetClip()` takes it off; `inside(x, y)` tells whether a point may be drawn. The fields `clipX0`, `clipY0`, `clipX1` and `clipY1` hold the rectangle: the end values are exclusive (`clip: 25,20 to 85,80` in the output below is 60 pixels wide).
The widgets use this: a widget can only draw inside its own rectangle.

{{sample gfx/clipping}}

{{shot gfx/clipping}}

**What to notice**

* The grey circle outline was drawn before the clip and is complete. The blue disc, the text and the red diagonal line were drawn with the clip: only the square part shows.
* `fill`, `line`, text, `put`, `blend`, `blit` and the other drawing functions obey the clip. **`clear` does not**: it always paints the whole surface. `get` does not look at the clip either.
* `setClip` with a rectangle that sticks out is cut to the surface (the third line of output).
* The gradient in the square on the right was asked for with a width of 200, far more than fits, and the clip keeps it inside the black frame.

## Text and fonts

`text(font, x, y, s, c)` draws UTF-8 text and returns the x position after it; **y is the top of the line**. `gfx.textWidth(font, s)` measures a string,
`textCentered(font, x, y, w, h, s, c)` centres it in a rectangle. There are three built-in antialiased fonts, all based on DejaVu: `gfx.sans()`, `gfx.sansBold()` and `gfx.mono()`.
A `gfx.Font` has `height` (the distance between lines) and `ascent` (from the top of the line to the baseline).

{{sample gfx/text_fonts}}

{{shot gfx/text_fonts}}

**What to notice**

* All three fonts have a `height` of 17 pixels (a line of text); `mono` has equal widths (8 pixels a character), the others have proportional widths.
* The return value of `text` lets you continue on the same line with another font, as the first line does.
* The translucent red text is blended like any other drawing.

### Which characters exist

The fonts have the characters 32 to 255 (ISO Latin-1). `text` decodes UTF-8; a code point above 255 is drawn as `?`.

{{sample gfx/text_utf8}}

{{shot gfx/text_utf8}}

**What to notice**

* `strlen` counts bytes (32), `textWidth` counts pixels (131): the first line has 21 characters, and each of its 11 letters with an accent or ring (`Ä`, `é`, `ß` ...) is two bytes in the source file.
* `gfx.nextCode(s, &pos)` reads one code point and advances `pos`: it returns 233 for `é` and moves 2 bytes. For a character that needs three or more bytes (the euro sign) it returns 63, the code of `?`, and moves over all its bytes.
* The euro sign, the Greek letters and the arrows are above 255 and all come out as `?`.

### Where the built-in fonts come from: `gfxfont`

The module `gfxfont` is only data: three functions, `sans()`, `sansBold()` and `mono()`, each returning the glyphs of one font as one long string of hex digits (about 10 000 bytes a font). The file is generated by
`docs/gen_font.py` from the DejaVu fonts (13 pixels, antialiased, Latin-1) and is not meant to be edited. `gfx` imports it, and `gfx.sans()` and the others build their `Font` objects from it, unless a font configuration names other files.
`new gfx.Font(hex)` builds a font from such text yourself.

{{sample gfx/builtin_fonts}}

{{shot gfx/builtin_fonts}}

**What to notice**

* The three data sets are 9 798, 10 570 and 9 770 bytes. A font that is made from the empty string is not `valid` (nothing can be drawn with it).
* You almost never import `gfxfont` yourself: use `gfx.sans()`, `sansBold()` and `mono()`, which also honour `$AFONT_CONF` and `/etc/fonts.conf` (see "Your own font file" below).
* `scaleFont` works on any font object, so a font made by hand can be scaled like the built-in ones (the last line of the picture, drawn at 150 percent).

### Text at other sizes

`gfx.scaleFont(font, percent)` makes a copy of a font at 20 to 400 percent (a smaller or larger number gives `null`). The glyphs are sampled again with integer arithmetic, so the
result is the same on every target. `surface->textScaled(font, x, y, s, c, percent)` draws one string at another size without making a font (it draws the string small on a temporary surface and resamples that, so it is slower than `text`; below 20 percent it draws nothing), and `scaledWidth` measures it.

{{sample gfx/font_scaling}}

{{shot gfx/font_scaling}}

Programs that want a larger or smaller interface change the **shared** fonts: `gfx.setFontScales(uiPercent, monoPercent)` replaces the glyphs of `sans()` and `sansBold()` (first number)
and `mono()` (second number) *in place*. Every widget holds a pointer to the same font objects, so they all have the new size at their next layout.

{{sample gfx/font_ui_scale}}

{{shot gfx/font_ui_scale}}

**What to notice**

* The `ui` pointer was taken once and still shows different sizes (height 17, then 26, then 17 again): the font object itself changed.
* `setFontScales` limits both percentages to 50 to 300. (`scaleFont` accepts 20 to 400.)
* `setFontScales(100, 100)` gives the exact original fonts back. The glyph sets are cached (48 of them), so going back and forth costs no memory after the first visit of a size.
* `gfx.setUiFont("mono")` (or `"sans"`, or the path of a font file) chooses which font `sans()` and `sansBold()` show and returns `false` when a file cannot be used; `gfx.uiFontScale()` and `monoFontScale()` read the current sizes.

### Your own font file

`gfx.loadFont(path)` loads a font from a binary file and returns `null` when the file is missing or damaged, or is 256 KiB (262 144 bytes) or larger. The format is small: a byte for the ascent, a byte for the line height, then for
each code from 32 to 255 five bytes (advance, left bearing, top, width, height; the bearing and the top are signed) followed by `width * height` coverage values of 4 bits, two per byte, the first one in the high nibble.
The sample makes a font that has only the ten digits, written as 5 by 7 bitmaps.

{{sample gfx/font_file}}

{{shot gfx/font_file}}

**What to notice**

* The file is 1302 bytes: 2 header bytes, 224 records of 5 bytes, and 18 bytes of coverage for each of the ten digits.
* Characters without pixels (width and height 0) only move the pen by their advance: letters in this font are blank, and `scaleFont` works on it as on any font.
* `gfx.sans()`, `sansBold()` and `mono()` can come from files too: the lines `sans=/path/font.afont`, `sansbold=...` and `mono=...` in the file named by `$AFONT_CONF`, or else `/etc/fonts.conf`
  (`builtin` keeps DejaVu). A missing or damaged file falls back to the built-in font.

## Copying pictures

`dst->blit(src, sx, sy, w, h, dx, dy)` copies a rectangle of `src` to `dx, dy` as it is, alpha included. `blitBlend(src, sx, sy, w, h, dx, dy, opacity)` composites it over what is there:
transparent parts of the sprite show the background, and `opacity` (0 to 255) makes the whole thing translucent. Both clip to the destination and to the source.

{{sample gfx/blit_sprites}}

{{shot gfx/blit_sprites}}

**What to notice**

* The sprite is a surface that starts transparent (`0`) with opaque shapes drawn on it. `blitBlend` keeps the sky around the circle, five times, and the sixth is a ghost at opacity 110.
* `blit` can copy a surface onto itself: the strip in the lower part is a copy of the upper part.
* `pack` and `unpack` move a rectangle to and from a byte buffer, four bytes per pixel (blue, green, red, alpha): the format of the display protocol.
* `checksum()` gives one number for the whole picture. The drawing code uses only integer arithmetic, so the same program draws the same pixels on every target: the tests of the graphics library print checksums and compare them with one recorded answer on all targets. (For this chapter, 13 of its samples were built for x86-64, ARM64 and RISC-V 64, run on each, and their PNG files were byte for byte equal.)

## Working pixel by pixel

For effects that no function offers, read pixels with `get` and write them with `put`. Both check their arguments, which costs time; a program that touches millions of pixels can use the
public array `s->px[y * s->w + x]` directly.

{{sample gfx/pixel_effects}}

{{shot gfx/pixel_effects}}

**What to notice**

* The grey value is a weighted sum: green counts most, blue least. Red `0xffe03030` becomes the grey `0xff646464`.
* The negative of a colour is `255 - channel` for each channel.
* Integer arithmetic is enough: all the divisions are by constants, and the results are the same on every target.

## Picture files: `gimg`

`import gimg;` reads and writes PNG, BMP and PPM files.

| Function | Does |
|---|---|
| `gimg.load(path)` | loads a PNG, BMP or PPM/PGM file; the format is recognised from the **content**, not the name. `null` when the file is missing or not a picture |
| `gimg.decode(bytes, n)` | the same for a picture in memory |
| `gimg.savePng(surface, path)` | writes an 8-bit RGBA PNG, **not compressed**; returns `false` when it cannot write |
| `gimg.encodePng(surface, &n)` | the PNG as bytes in memory; the length goes to `n` |
| `gimg.scale(surface, w, h)` | a new surface of any size (bilinear smoothing) |
| `gimg.fit(surface, boxW, boxH)` | as large as fits the box, with the same proportions |
| `surface->savePPM(path)`, `saveBMP(path)` | method of `gfx.Surface`: 24-bit PPM (P6) and BMP |

The decoder has its own inflate. It reads PNG of every colour type and bit depth (not interlaced), palettes with transparency, BMP of 1, 4, 8, 24 and 32 bits per pixel without compression,
and PPM/PGM (P2, P3, P5, P6).

{{sample gfx/png_roundtrip}}

{{shot gfx/png_roundtrip}}

**What to notice**

* The file has 28 928 bytes: 120 x 60 x 4 bytes of pixels plus 128 bytes of overhead (the PNG headers, the zlib wrapper and one filter byte for each of the 60 rows).
* Saving and loading gives the same `checksum()`; so does encoding to memory and decoding again. The pixel `put` with alpha 100 survives (`0x640000ff`).
* Garbage and missing files give `null`, never a crash.

{{sample gfx/image_formats}}

{{shot gfx/image_formats}}

**What to notice**

* The sizes follow from the formats: the PPM is the header `P6\n64 40\n255\n` (13 bytes) plus 3 bytes a pixel, the BMP is 54 bytes of header plus rows padded to a multiple of 4, the PNG has 4 bytes a pixel.
* The PPM and BMP files that `savePPM` and `saveBMP` write have no alpha, so `load` gives opaque pixels. The picture used here is opaque, so all three files give the same pixels. (A 32-bit BMP made by another program keeps its alpha byte.)
* A PPM can be written by hand: `P3` is the text form, with the numbers of the pixels as decimal text.

{{sample gfx/image_scale}}

{{shot gfx/image_scale}}

**What to notice**

* `scale` interpolates between the source pixels, so the enlarged circle is smooth. The blocky version next to it is drawn with one `fill` per pixel.
* `fit` keeps the proportions: 96 x 72 into 60 x 60 gives 60 x 45.
* Both functions make a **new** surface; the source is not changed.

## Two larger examples

The Mandelbrot set takes a few lines of integer arithmetic when numbers are fixed-point: 4096 means 1.0, and after each multiplication you divide by 4096 again.

{{sample gfx/mandelbrot}}

{{shot gfx/mandelbrot}}

**What to notice**

* The number of pixels inside the set and the checksum are the same on every target, because the arithmetic is all integer (the PNG was equal on x86-64, ARM64 and RISC-V 64).
* The colour is a `mix` of two colours (in two ranges: dark blue to light blue, then light blue to white), chosen by the number of steps before the point escaped.

A function plot: a grid, labels made with `textCentered`, and one `line` for each step of the curve.

{{sample gfx/plot_function}}

{{shot gfx/plot_function}}

**What to notice**

* The plot is 288 pixels wide for 360 degrees, so `deg = x * 360 / PW` and each step of the curve is one `line` from the last point to the new one.
* Both curves use `isin` and `icos`, which are 1024 times the real value: `isin(deg) * (PH / 2) / 1024` scales the result to half the plot height.
* The grid and the labels are drawn first, so the curves cover them.

## Plotting with real numbers

`isin` and `icos` are integer approximations. When you want exact values, A has a real `double` type and the `dmath` module (`sin`, `cos`, `exp`, `sqrt`, `pow`, ...). They are computed in software, so the
results are bit for bit the same on every target; [the chapter on numbers](#chap-numbers) covers them. A `double` is converted to a pixel position with a cast to `int`, which truncates toward zero.

{{sample gfx/plot_double}}

{{shot gfx/plot_double}}

**What to notice**

* `px / 20.0` is a `double`; `-x / 3` and `4 * x` mix integers and doubles freely.
* The two output lines compare `dmath.sin` with `isin`: 0.173648 against 0.174805. For pictures that is invisible, for numbers it is not.
* `printlnDouble` and `doubleToFixed(d, digits)` print doubles; `printf` itself does not format them.

## Summary

* A `gfx.Surface` is `w * h` pixels of the form `0xAARRGGBB`; y grows downwards; everything clips to the surface and to the clip rectangle (except `clear`).
* Shapes: `fill`, `rect`, `line`, `circle`, `fillCircle`, `roundRect`, `fillRoundRect`, `fillPolygon`, `arc`, `thickArc`, `fillPie`, `gradientV`, `shadow`.
* Colours below alpha 255 are blended and the result is opaque; `put` stores exactly.
* Text: `text` (y is the top), `textWidth`, `textCentered`; Latin-1 only; `scaleFont`, `textScaled` and `setFontScales` change sizes; `loadFont` reads your own font.
* `blit` copies, `blitBlend` composites, `get` / `put` work pixel by pixel, `checksum` compares whole pictures.
* `gimg` loads PNG, BMP and PPM by content and saves PNG (uncompressed); `scale` and `fit` resize smoothly.
* Everything is integer arithmetic (`isin` and `icos` are 1024 times the value), or `double` and `dmath` when you want exact numbers.

## Where next

* [Graphical programs: windows and widgets](#chap-gui-basics) put these pictures into windows.
* [Charts, gauges and more widgets](#chap-gui-more-widgets) use `fillPie` and `thickArc` for their data widgets.
* API references: [`gfx`](#api-gfx), [`gfxfont`](#api-gfxfont), [`gimg`](#api-gimg).
