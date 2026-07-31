#!/usr/bin/env python3
"""Turn the annotated anatomy SVG into the app's BodyDiagram.json.

The app does not render SVG. Xcode's asset-catalog importer mangles this
drawing (gradients, clip paths, <use>), and an imported picture cannot be
hit-tested per muscle anyway. So the geometry is extracted here and drawn by
SwiftUI as ordinary paths — which is why the gradients, clip paths and <use>
elements in the source simply do not matter: none of them is read.

What comes out is deliberately dumb, so the Swift side stays small:

  * absolute coordinates only — every relative command (m, c, l, h, v) is
    resolved here, and group transforms are baked in;
  * only M, L, C and Z survive — H and V become L;
  * coordinates normalised to 0..1 within each figure's own box, so the app can
    scale to any size without knowing the original units.

Each path carries the muscle group it belongs to, taken from its Inkscape label
or its enclosing group's label. Anything unlabelled is body: drawn, but not
selectable.

Usage:  tools/svg-to-bodydiagram.py <input.svg> [-o workout_aicode/BodyDiagram.json]
"""
import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET

SVG = "{http://www.w3.org/2000/svg}"
# Everything that puts ink on the page, and everything that legitimately does
# not. Anything in neither list is reported, so a shape can never again be
# dropped without saying so.
DRAWABLE = {"path", "ellipse", "circle", "rect", "line", "polyline", "polygon"}
IGNORED = {"svg", "g", "defs", "metadata", "namedview", "RDF", "Work", "format",
           "type", "title", "desc", "linearGradient", "radialGradient", "stop",
           "clipPath", "path-effect", "use", "style", "sodipodi", "grid"}
INK = "{http://www.inkscape.org/namespaces/inkscape}"
NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?')
TOKEN = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?)')

# Label in the SVG -> MuscleGroup raw value in the app.
#
# Several muscles are visible from both sides, and each view needs its own path
# because the two are drawn on different figures. Those carry a _front/_back
# suffix in the drawing and are mapped to one group here, so the labelling stays
# convenient in Inkscape without the app knowing about halves.
GROUP_MAP = {
    "Chest": "chest",
    "Back": "back",
    "Traps": "traps",
    "Traps_front": "traps",
    "Front Delts": "frontDelts",
    "Side Delts": "sideDelts",
    "Side Delts_front": "sideDelts",
    "Side Delts_back": "sideDelts",
    "Rear Delts": "rearDelts",
    "Biceps": "biceps",
    "Triceps": "triceps",
    "Forearms": "forearms",
    "Forearms_front": "forearms",
    "Forearms_back": "forearms",
    "Quads": "quads",
    # The drawing covers the whole upper/lower leg so any part of the limb is
    # clickable; the app's names for the groups are unchanged.
    "Quads/ul": "quads",
    "Hamstrings": "hamstrings",
    "Glutes": "glutes",
    "Calves": "calves",
    "Calves/ll": "calves",
    "Calves/ll_front": "calves",
    "Calves/ll_back": "calves",
    "Abs/Core": "absCore",
    "Lower Back": "lowerBack",
}


# ---------------------------------------------------------------- transforms

def parse_transform(text):
    m = (1, 0, 0, 1, 0, 0)
    if not text:
        return m
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', text):
        v = [float(x) for x in NUM.findall(args)]
        if name == 'translate':
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == 'scale':
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == 'matrix':
            t = tuple(v[:6])
        else:
            print(f"  ! ignoring unsupported transform: {name}", file=sys.stderr)
            continue
        m = compose(m, t)
    return m


def compose(m, n):
    a1, b1, c1, d1, e1, f1 = m
    a2, b2, c2, d2, e2, f2 = n
    return (a1 * a2 + c1 * b2, b1 * a2 + d1 * b2,
            a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
            a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1)


def apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


# --------------------------------------------------------- primitive shapes

# Circles, ellipses and rectangles drawn in Inkscape are NOT <path> elements,
# and an earlier version of this script quietly ignored them — six ellipses
# added to fill gaps in the body simply never reached the app. Anything
# drawable is converted here, and anything still unrecognised is reported
# rather than dropped.

KAPPA = 0.5522847498307936      # circular arc as a cubic, standard constant


def ellipse_segments(cx, cy, rx, ry):
    kx, ky = KAPPA * rx, KAPPA * ry
    return [
        ('M', [cx + rx, cy]),
        ('C', [cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry]),
        ('C', [cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy]),
        ('C', [cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry]),
        ('C', [cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy]),
        ('Z', []),
    ]


def rect_segments(x, y, w, h, rx, ry):
    if rx <= 0 and ry <= 0:
        return [('M', [x, y]), ('L', [x + w, y]), ('L', [x + w, y + h]),
                ('L', [x, y + h]), ('Z', [])]
    rx = min(rx or ry, w / 2)
    ry = min(ry or rx, h / 2)
    kx, ky = KAPPA * rx, KAPPA * ry
    return [
        ('M', [x + rx, y]),
        ('L', [x + w - rx, y]),
        ('C', [x + w - rx + kx, y, x + w, y + ry - ky, x + w, y + ry]),
        ('L', [x + w, y + h - ry]),
        ('C', [x + w, y + h - ry + ky, x + w - rx + kx, y + h, x + w - rx, y + h]),
        ('L', [x + rx, y + h]),
        ('C', [x + rx - kx, y + h, x, y + h - ry + ky, x, y + h - ry]),
        ('L', [x, y + ry]),
        ('C', [x, y + ry - ky, x + rx - kx, y, x + rx, y]),
        ('Z', []),
    ]


def shape_segments(el):
    """Absolute segments for any drawable element, or None if it is not one."""
    def f(name, default=0.0):
        try:
            return float(el.get(name, default))
        except (TypeError, ValueError):
            return default

    tag = el.tag.replace(SVG, "")
    if tag == "path":
        return to_absolute(el.get("d")) if el.get("d") else None
    if tag == "ellipse":
        return ellipse_segments(f("cx"), f("cy"), f("rx"), f("ry"))
    if tag == "circle":
        r = f("r")
        return ellipse_segments(f("cx"), f("cy"), r, r)
    if tag == "rect":
        return rect_segments(f("x"), f("y"), f("width"), f("height"), f("rx"), f("ry"))
    if tag in ("line", "polyline", "polygon"):
        pts = [float(v) for v in NUM.findall(el.get("points", "") or "")]
        if tag == "line":
            return [('M', [f("x1"), f("y1")]), ('L', [f("x2"), f("y2")])]
        if len(pts) < 4:
            return None
        segs = [('M', pts[0:2])] + [('L', pts[i:i + 2]) for i in range(2, len(pts) - 1, 2)]
        if tag == "polygon":
            segs.append(('Z', []))
        return segs
    return None


# ------------------------------------------------------------------- arcs

def arc_to_cubics(x0, y0, rx, ry, phi_deg, large_arc, sweep, x, y):
    """SVG elliptical arc -> a list of cubic segments [(c1, c2, end), ...].

    SwiftUI has no elliptical-arc path command matching SVG's, and drawing one
    as a straight line would visibly flatten whatever it curves. The conversion
    is the standard endpoint -> centre parameterisation from the SVG spec
    (implementation notes F.6), split into pieces of at most 90 degrees, each
    of which a cubic approximates to well under a pixel here.
    """
    import math
    if rx == 0 or ry == 0 or (x0 == x and y0 == y):
        return [((x0, y0), (x, y), (x, y))]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(phi_deg)
    cosp, sinp = math.cos(phi), math.sin(phi)

    dx2, dy2 = (x0 - x) / 2.0, (y0 - y) / 2.0
    x1p = cosp * dx2 + sinp * dy2
    y1p = -sinp * dx2 + cosp * dy2

    # Scale the radii up if they are too small to span the two points.
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s

    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    factor = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large_arc == sweep:
        factor = -factor
    cxp = factor * rx * y1p / ry
    cyp = -factor * ry * x1p / rx
    cx = cosp * cxp - sinp * cyp + (x0 + x) / 2.0
    cy = sinp * cxp + cosp * cyp + (y0 + y) / 2.0

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        n = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1.0, min(1.0, dot / n))) if n else 0.0
        return -a if ux * vy - uy * vx < 0 else a

    theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                   (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep and dtheta < 0:
        dtheta += 2 * math.pi

    steps = max(1, int(math.ceil(abs(dtheta) / (math.pi / 2))))
    delta = dtheta / steps
    t = 4.0 / 3.0 * math.tan(delta / 4.0)

    def point(th):
        return (cx + rx * math.cos(th) * cosp - ry * math.sin(th) * sinp,
                cy + rx * math.cos(th) * sinp + ry * math.sin(th) * cosp)

    def derivative(th):
        return (-rx * math.sin(th) * cosp - ry * math.cos(th) * sinp,
                -rx * math.sin(th) * sinp + ry * math.cos(th) * cosp)

    out = []
    th = theta1
    px, py = point(th)
    for _ in range(steps):
        th2 = th + delta
        ex, ey = point(th2)
        d1x, d1y = derivative(th)
        d2x, d2y = derivative(th2)
        out.append(((px + t * d1x, py + t * d1y),
                    (ex - t * d2x, ey - t * d2y),
                    (ex, ey)))
        th, px, py = th2, ex, ey
    return out


# --------------------------------------------------------------- path parsing

def tokens(d):
    for cmd, num in TOKEN.findall(d):
        yield ('c', cmd) if cmd else ('n', float(num))


def to_absolute(d):
    """[(cmd, [x, y, ...]), ...] with only M, L, C, Z, in absolute coordinates."""
    out = []
    it = list(tokens(d))
    i = 0
    cx = cy = 0.0
    sx = sy = 0.0
    cmd = None
    while i < len(it):
        kind, val = it[i]
        if kind == 'c':
            cmd = val
            i += 1
            if cmd in 'Zz':
                out.append(('Z', []))
                cx, cy = sx, sy
                continue
        if cmd is None:
            i += 1
            continue

        def take(n):
            nonlocal i
            vals = []
            while len(vals) < n and i < len(it) and it[i][0] == 'n':
                vals.append(it[i][1])
                i += 1
            return vals

        rel = cmd.islower()
        up = cmd.upper()
        if up == 'M':
            v = take(2)
            if len(v) < 2:
                break
            x, y = (cx + v[0], cy + v[1]) if rel else (v[0], v[1])
            out.append(('M', [x, y]))
            cx, cy, sx, sy = x, y, x, y
            # Further pairs after an M are implicit L (SVG spec).
            cmd = 'l' if rel else 'L'
        elif up == 'L':
            v = take(2)
            if len(v) < 2:
                break
            x, y = (cx + v[0], cy + v[1]) if rel else (v[0], v[1])
            out.append(('L', [x, y]))
            cx, cy = x, y
        elif up == 'H':
            v = take(1)
            if not v:
                break
            x = cx + v[0] if rel else v[0]
            out.append(('L', [x, cy]))
            cx = x
        elif up == 'V':
            v = take(1)
            if not v:
                break
            y = cy + v[0] if rel else v[0]
            out.append(('L', [cx, y]))
            cy = y
        elif up == 'C':
            v = take(6)
            if len(v) < 6:
                break
            pts = []
            for j in range(0, 6, 2):
                x, y = (cx + v[j], cy + v[j + 1]) if rel else (v[j], v[j + 1])
                pts += [x, y]
            out.append(('C', pts))
            cx, cy = pts[4], pts[5]
        elif up == 'A':
            v = take(7)
            if len(v) < 7:
                break
            ex, ey = (cx + v[5], cy + v[6]) if rel else (v[5], v[6])
            for c1, c2, end in arc_to_cubics(cx, cy, v[0], v[1], v[2],
                                             int(v[3]) != 0, int(v[4]) != 0, ex, ey):
                out.append(('C', [c1[0], c1[1], c2[0], c2[1], end[0], end[1]]))
            cx, cy = ex, ey
        else:
            raise SystemExit(f"unsupported path command {cmd!r} — extend the converter")
    return out


# ------------------------------------------------------------------- walking

def collect(el, matrix, group, out):
    if el.tag in (SVG + "defs", SVG + "clipPath", SVG + "mask"):
        return                                   # never drawn where declared
    matrix = compose(matrix, parse_transform(el.get("transform")))
    label = el.get(INK + "label")
    if label in GROUP_MAP:
        group = GROUP_MAP[label]

    # Local name: metadata elements come from other namespaces, and comparing
    # the full "{uri}name" would report every one of them as a mystery.
    tag = el.tag.rsplit("}", 1)[-1]
    if tag in DRAWABLE:
        segs = shape_segments(el)
        if segs is None:
            print(f"  ! skipped a <{tag}> this script cannot read "
                  f"(id={el.get('id')})", file=sys.stderr)
        else:
            segs = [(c, [v for j in range(0, len(vals), 2)
                         for v in apply(matrix, vals[j], vals[j + 1])])
                    for c, vals in segs]
            out.append({"group": group, "segments": segs})
    elif tag not in IGNORED:
        print(f"  ! ignoring <{tag}> (id={el.get('id')}) — nothing is drawn for it",
              file=sys.stderr)
    for child in el:
        collect(child, matrix, group, out)


def bounds(paths):
    xs, ys = [], []
    for p in paths:
        for _, vals in p["segments"]:
            xs += vals[0::2]
            ys += vals[1::2]
    return min(xs), min(ys), max(xs), max(ys)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("svg")
    ap.add_argument("-o", "--out", default="workout_aicode/BodyDiagram.json")
    args = ap.parse_args()

    root = ET.parse(args.svg).getroot()
    paths = []
    collect(root, (1, 0, 0, 1, 0, 0), None, paths)
    paths = [p for p in paths if p["segments"]]
    print(f"  {len(paths)} paths")

    # Split into the two figures on the empty column between them.
    centres = sorted((min(v for _, vals in p["segments"] for v in vals[0::2]) +
                      max(v for _, vals in p["segments"] for v in vals[0::2])) / 2
                     for p in paths)
    gap, split = 0, centres[len(centres) // 2]
    for a, b in zip(centres, centres[1:]):
        if b - a > gap:
            gap, split = b - a, (a + b) / 2
    print(f"  figures split at x={split:.1f} (largest gap {gap:.1f})")

    figures = {}
    for name, keep in (("front", lambda c: c < split), ("back", lambda c: c >= split)):
        sel = [p for p in paths
               if keep((min(v for _, vals in p["segments"] for v in vals[0::2]) +
                        max(v for _, vals in p["segments"] for v in vals[0::2])) / 2)]
        x0, y0, x1, y1 = bounds(sel)
        w, h = x1 - x0, y1 - y0
        norm = []
        for p in sel:
            # One compact string per path, in normalised coordinates: "M x,y",
            # "L x,y", "C x,y x,y x,y", "Z". Absolute only, four commands only —
            # the Swift side is then a twenty-line scanner rather than an SVG
            # implementation.
            parts = []
            for c, vals in p["segments"]:
                if c == 'Z':
                    parts.append('Z')
                    continue
                nums = []
                for j, v in enumerate(vals):
                    n = (v - x0) / w if j % 2 == 0 else (v - y0) / h
                    nums.append(f"{n:.4f}".rstrip('0').rstrip('.') or "0")
                pairs = " ".join(f"{nums[k]},{nums[k+1]}" for k in range(0, len(nums), 2))
                parts.append(f"{c}{pairs}")
            norm.append({"group": p["group"], "d": "".join(parts)})
        figures[name] = {"aspect": round(w / h, 5), "paths": norm}
        named = sum(1 for p in norm if p["group"])
        print(f"  {name}: {len(norm)} paths ({named} in a muscle group), aspect {w/h:.3f}")

    groups = sorted({p["group"] for f in figures.values() for p in f["paths"] if p["group"]})
    print(f"  groups found: {', '.join(groups)}")
    missing = sorted(set(GROUP_MAP.values()) - set(groups))
    if missing:
        print(f"  ! not in the drawing yet: {', '.join(missing)}")

    with open(args.out, "w") as f:
        json.dump({"figures": figures}, f, separators=(",", ":"))
    print(f"  wrote {args.out}")


if __name__ == "__main__":
    main()
