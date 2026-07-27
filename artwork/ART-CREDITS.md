# Artwork credits

## Muscle diagram (`body-front`, `body-back` in Assets.xcassets)

**Title:** Muscles front and back
**Authors:** OpenStax, Tomáš Kebert, umimeto.org
**Source:** https://commons.wikimedia.org/wiki/File:Muscles_front_and_back.svg
**Licence:** Creative Commons Attribution-ShareAlike 4.0 International
(CC BY-SA 4.0) — https://creativecommons.org/licenses/by-sa/4.0/

### Changes made
The original single SVG shows both figures side by side on a white page. For
this app it was:

1. rendered to a bitmap, with the viewBox padded to a square first (the only
   SVG renderer to hand always emits a square image, so a square source keeps
   the proportions honest);
2. split into two images, one per figure, cropped to the drawing with a small
   margin;
3. given a transparent background in place of the white page, so the figures
   sit correctly on both light and dark backgrounds;
4. resized to 1x/2x/3x assets.

Nothing was redrawn: the anatomy is the original artists' work.

The unmodified original is kept beside this file as
`muscles-front-and-back-original.svg`.

### What this means for reuse
CC BY-SA 4.0 is *share-alike*: these two derived images remain under
CC BY-SA 4.0 rather than this app's GPL-3.0, and anyone redistributing them —
modified or not — must credit the authors as above and keep the same licence.
The rest of the app is unaffected; including a CC BY-SA work in a larger
program is a collection, not an adaptation of it. (CC BY-SA 4.0 is in any case
one-way compatible with GPLv3.)
