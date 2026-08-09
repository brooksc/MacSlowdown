# App icon

Direction **3b — "trace with an incident band"** (TASK-65.18). The product owner's
decision; 3c and 3e were considered and rejected, and that is not re-opened here.

`3a.png` … `3f.png` are the designer's six direction sketches. Everything else in
this directory is the artwork cut from direction 3b.

| File | What it is |
|---|---|
| `icon-large.svg` | Full-detail artwork. Rasterised for 64 px and above. |
| `icon-small.svg` | Simplified artwork for 16 and 32 px. |
| `layers/*.svg` | The same artwork split into layers, for Icon Composer. |
| `build.sh` | Renders both SVGs into `MacSlowdown/Resources/Assets.xcassets/AppIcon.appiconset`. |
| `contact-sheet.png` | 128 / 64 / 32 / 16 px at true size. |
| `zoom-16.png`, `zoom-32.png` | The small sizes magnified with no smoothing. |

Regenerate with `design/icons/build.sh`. Never hand-edit the PNGs.

## The reduction problem, and what was done about it

The designer's own risk note on 3b: *the band vanishes below 32 pt, leaving a
common chart-line icon.* The band is the concept — a slowdown is an interval, not
an instant — so an icon that loses it at 16 pt has shipped a generic squiggle.

Three changes were made to the sketch, all aimed at that:

1. **The band runs the full height of the tile.** In the sketch it is a small
   inset rectangle floating behind the trace: a detail, and details are the first
   thing a 16 px raster destroys. Edge to edge, it is a silhouette instead — the
   tile is visibly divided into three columns even when nothing else survives.
2. **The trace rises and falls on the band's two edges.** The sketch's trace
   steps up inside the band and stays up. Here it is settled, rises at the
   leading edge, is elevated across the interval, falls at the trailing edge, and
   is settled again. The interval is now stated twice — by the column and by the
   shape of the trace — so neither alone has to carry it. It also means the icon
   depicts a slowdown that **ended**, which is what keeps it from reading as a
   permanent alarm state (acceptance criterion #4, FR-013).
3. **The band's contrast against the slate was raised**, from roughly 26% amber
   in the sketch to 48%/38%. Renders at 16 px of 0.26, 0.42 and 0.55 were
   compared directly; 0.26 is legible but faint, and the chosen value is clearly
   present without the tile ceasing to read as slate.

Two artworks are drawn, which is standard Apple practice rather than a
compromise. Below 64 px the large trace's undulation is noise and it eats the
contrast the band needs, so the small artwork drops it for a clean pulse.

`icon-small.svg` is drawn entirely on multiples of 64 units, so at 16 px every
edge lands exactly on a pixel boundary (64 units = 1 px at 16 px, and at 32 px
too). The 2 px trace and the 6 px band are therefore rasterised without being
smeared across two rows — which is most of why they still read. `zoom-16.png`
shows the result.

**The crossover is at 32/64 px.** Practically every display is Retina, so the
16 pt icon is drawn from the 32 px asset and the 32 pt icon from the 64 px one:
16 pt gets the simplified art, everything from 32 pt up gets the trace. The one
seam is 32 px at 1x (a non-Retina 32 pt icon), which gets the simplified art
while its 2x sibling gets the trace. Accepted: the deployment target is macOS 26
on Apple Silicon, where a non-Retina display is close to nonexistent.

## Why this does not duplicate the menu bar glyph

The menu bar item is a **live state indicator** (TASK-65.17 / design 2d) — it
changes to report the current condition. The app icon is a fixed mark and must
not compete with it. It shares no form with the menu bar glyph, and it is drawn
in the past tense: an interval that began, lasted and ended. It reports nothing
about the machine right now, so there is no size at which a user could mistake it
for status.

## Format

Full-bleed, fully opaque, **no squircle baked in**. macOS 26+ applies its own
rounded-rect mask and material. The trap here is that macOS decides whether an
icon is "modern" from its edge alpha: an edge pixel at alpha ≤ 252 makes the
system treat the icon as legacy and shrink it inside a grey squircle instead of
clipping it. `build.sh` therefore flattens every render to a fully opaque PNG
with no alpha channel at all, and the corner pixel of the built `.icns` was
checked to confirm alpha 1.0 survives the asset-catalog compiler.

What ships today is a conventional `AppIcon.appiconset` with all ten macOS
entries, wired up by `ASSETCATALOG_COMPILER_APPICON_NAME` in `Project.swift`.
The built bundle carries `CFBundleIconName`, `CFBundleIconFile`, an `AppIcon.icns`
and ten `Icon Image` entries in `Assets.car`, verified with `assetutil`.

### What still needs a human, in Icon Composer

macOS 26 introduced a layered `.icon` format with light, dark, tinted and clear
appearances. Icon Composer is a GUI app that ships with Xcode; a `.icon` bundle
cannot be authored or validated from the command line, so none was faked here.
To produce one:

1. Open Icon Composer (Xcode ▸ Open Developer Tool ▸ Icon Composer), new
   document, 1024 × 1024, macOS.
2. Set the **background** in Icon Composer itself — a linear gradient at 135°,
   `#5E6D90` → `#242C3C`. Do not import a background layer; Apple's guidance is
   that flat backgrounds are added in the app.
3. Import `layers/1-band.svg`, then `layers/2-trace.svg`, in that Z order. Both
   are full-canvas with no mask, as required.
4. Set the band layer's opacity to **48%**. The shipped raster additionally fades
   it to 38% at the bottom; Icon Composer has no per-layer gradient opacity, so
   either accept the flat 48% or import the band as a PNG with the gradient baked
   in.
5. Leave the specular / blur / shadow effects at their defaults for the trace
   layer and check the result in each appearance. **The dark and tinted
   appearances need a person to look at them** — a slate tile with an amber trace
   is already dark, and the tinted appearance discards colour entirely, so the
   band's contrast against the slate must be re-judged there. That check was not
   possible here.
6. Save as `AppIcon.icon` at the repository root of the app target, drag it into
   the Xcode **project navigator** (not the asset catalog), and keep
   `ASSETCATALOG_COMPILER_APPICON_NAME` set to `AppIcon`. Xcode uses the `.icon`
   in preference to the `.appiconset` and generates the legacy sizes from it.
   Note that at that point the hand-tuned 16 px artwork above is **replaced by a
   downscale of the layered icon** — check 16 px again before keeping it, and
   consider keeping the `.appiconset` for the small sizes if it loses.
7. Tuist wires files by glob, so a `.icon` needs a line in `Project.swift`;
   confirm `tuist generate` places it as a resource of the app target.

## Sources consulted

- Apple, *Create icons with Icon Composer* (WWDC25 session 361) — canvas size,
  full-canvas layer export, "never include a rounded rectangle or circle mask in
  your exports", flat opaque source artwork.
- Apple Developer Forums thread 797971 — the measured macOS 26 edge-alpha
  threshold (≥ 253 gets the rounded clip, ≤ 252 gets the grey squircle frame).
  Reverse-engineered, not documented by Apple; treat as the best available
  explanation rather than a guarantee.
