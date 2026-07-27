# Artwork credits

## Muscle diagram (`body-front`, `body-back` in Assets.xcassets)

**Title:** Muscles front and back
**Authors:** OpenStax, Tomáš Kebert, umimeto.org
**Source:** https://commons.wikimedia.org/wiki/File:Muscles_front_and_back.svg
**Licence:** Creative Commons Attribution-ShareAlike 4.0 International
(CC BY-SA 4.0) — https://creativecommons.org/licenses/by-sa/4.0/

### Changes made
Starting from the original single SVG showing both figures on a white page:

1. the drawing was opened in Inkscape and each of the app's fifteen muscle
   groups was labelled — as a single path where the group is one muscle, or as
   a named group where it is several;
2. the `<use>` elements were removed and each figure was halved left/right,
   since a half body carries the same information in half the screen width;
3. some small paths that added nothing at this size were deleted, while others
   were kept because they carry the body outline;
4. the deltoid and back sheets were split so that side delts and lower back
   exist as separate shapes, which the original does not distinguish;
5. the annotated result (`muscles-annotated.svg`) is converted by
   `tools/svg-to-bodydiagram.py` into `workout_aicode/BodyDiagram.json`: plain
   path geometry in normalised coordinates, tagged per muscle group.

The app draws that geometry itself and colours it — muscle groups warm,
everything else grey — so the original's gradients, clip paths and `<use>`
elements are never read. Nothing was redrawn: the anatomy is the original
artists' work.

The unmodified original is kept beside this file as
`muscles-front-and-back-original.svg`, and the annotated working copy as
`muscles-annotated.svg`.

### What this means for reuse
CC BY-SA 4.0 is *share-alike*: these two derived images remain under
CC BY-SA 4.0 rather than this app's GPL-3.0, and anyone redistributing them —
modified or not — must credit the authors as above and keep the same licence.
The rest of the app is unaffected; including a CC BY-SA work in a larger
program is a collection, not an adaptation of it. (CC BY-SA 4.0 is in any case
one-way compatible with GPLv3.)
