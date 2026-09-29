#!/usr/bin/env python3
"""PNG-Vorschauen der gebauten Stadt (matplotlib, ohne Roblox).

  python3 tools/worldgen/render.py [place] [--plots] [--district NAME | --rect x0 x1 z0 z1] [--out DIR]

* ohne --district/--rect: Draufsicht der ganzen Stadt -> city_top.png (Parts als gedrehte Grundrisse,
  Farbe = Color3, von unten nach oben gezeichnet; Stationen/Ankunft als Marker)
* mit --district/--rect: Draufsicht (<name>_top.png) und isometrische Ansicht von Südost (<name>_iso.png)
* --plots: die getrimmte Werkstatt-Vorlage (4 Hallen) an allen 8 Slots mitzeichnen (ohne Vacant-Kits)
* --cut Y: Schnitt bei Höhe Y (Dächer/Decken darüber entfallen) -> Innenansicht <name>_cut<Y>_iso.png
"""
import math
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.collections import PolyCollection  # noqa: E402
from matplotlib.patches import Circle, Polygon  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from worldgen import scan  # noqa: E402
from worldgen.lib import child, children, name_of, read_cf  # noqa: E402

OUT = Path("/tmp/claude-0/renders")
DISTRICTS = {
    "altstadt": (-140, 140, -370, -10), "plaza": (-75, 75, -235, -15), "halle": (-50, 50, -226, -176),
    "schrott": (-480, -170, -370, -150), "tuning": (170, 480, -370, -150), "autohaus": (-140, 140, 10, 230),
    "track": (-175, 175, 215, 430), "park": (-480, -170, 150, 350), "tankstelle": (170, 410, 150, 270),
    "kreisel_w": (-575, -455, -60, 60), "kreisel_o": (455, 575, -60, 60), "k_west": (-200, -104, -48, 48),
    "meile_w": (-480, -170, -160, 160), "meile_o": (170, 480, -160, 160), "parkplatz": (-140, 140, -370, -220),
}


def footprint(p):
    """2D-Grundriss (x,z) eines Parts: konvexe Hülle der Ecken, Kreis für stehende Zylinder/Kugeln"""
    if p.cls == "Part" and p.shape in (0, 2):
        ax = p.cf.vector((1, 0, 0))
        if p.shape == 0 or abs(ax[1]) > 0.95:
            r = p.size[1] / 2 if p.shape == 2 else p.size[0] / 2
            c = p.cf.p
            return [(c[0] + r * math.cos(a), c[2] + r * math.sin(a)) for a in (k * math.pi / 10 for k in range(20))]
    return hull([(q[0], q[2]) for q in p.corners()])


def hull(pts):
    pts = sorted(set((round(a, 4), round(b, 4)) for a, b in pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for q in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], q) <= 0:
            lo.pop()
        lo.append(q)
    for q in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], q) <= 0:
            hi.pop()
        hi.append(q)
    return lo[:-1] + hi[:-1]


def rgba(p, shade=1.0):
    a = 1.0 - p.transp
    if p.material == "Glass":
        a = min(a, 0.55)
    return tuple(min(1.0, c / 255.0 * shade) for c in p.color) + (max(0.08, a),)


def gather(tree, with_plots):
    city, parts = scan.city_parts(tree)
    if with_plots:
        parts = [p for p in parts if ".Vacant." not in p.path]
        parts += scan.plot_parts(tree)
        parts += stage_parts(tree)
    return city, [p for p in parts if p.transp < 0.97]


def stage_parts(tree):
    """WorkshopExtensions Stage_2..4 an allen Slots (maximaler Ausbau)"""
    from worldgen.plots import SLOTS, slot_cf
    root = tree.getroot()
    ss = next(i for i in root.findall("Item") if i.get("class") == "ServerStorage")
    ext = child(ss, "WorkshopExtensions")
    out = []
    for slot, house, px, pz, rot in SLOTS:
        for st in children(ext):
            scan.walk(st, "Plot%d.%s" % (slot, name_of(st)), False, slot_cf(px, pz, rot), out)
    return out


def overlays(tree, city, with_plots=False):
    """Umrisse der unsichtbaren Fahrzeug-Parts: CarSpawns als Auto-Stellfläche mit Nasen-Pfeil (orange),
    Checkpoints (gelb), Ziel (rot); mit --plots auch der Werkstatt-CarSpawn an allen Slots."""
    from worldgen import drive
    out = []

    def car(nm, cf):
        lk = cf.look
        rt = (-lk[2], lk[0])
        c = cf.p
        hw, hl = drive.CAR_HALF_W, drive.CAR_HALF_L
        pts = [(c[0] + rt[0] * a * hw + lk[0] * b * hl, c[2] + rt[1] * a * hw + lk[2] * b * hl)
               for a, b in ((-1, -1), (1, -1), (1, 1), (0, 1.35), (-1, 1))]
        out.append((nm, pts, "#ff9f1a"))
    f = child(city, "CarSpawns")
    for it in children(f) if f is not None else []:
        car(name_of(it), read_cf(it))
    tr = child(city, "Track")
    if tr is not None:
        for it in tr.iter("Item"):
            if it.get("class") == "Part":
                p = scan.record(it, name_of(it))
                out.append((p.name, hull([(q[0], q[2]) for q in p.corners()]),
                            "#ff3030" if p.name == "Ziel" else "#ffe02a"))
    if with_plots:
        from worldgen.plots import SLOTS, slot_cf
        wk = child(scan.workspace(tree), "Werkstatt")
        cs = child(wk, "CarSpawn") if wk is not None else None
        if cs is not None:
            for slot, house, px, pz, rot in SLOTS:
                car("Plot%d" % slot, slot_cf(px, pz, rot) * read_cf(cs))
    return out


def markers(city):
    out = []
    for folder, col in (("Stations", "#ff2d95"), ("Arrivals", "#00e5ff")):
        f = child(city, folder)
        for it in children(f) if f is not None else []:
            out.append((name_of(it), read_cf(it).p, col))
    sp = child(city, "CitySpawn")
    if sp is not None:
        out.append(("CitySpawn", read_cf(sp).p, "#ffffff"))
    return out


def top_view(parts, rect, path, marks=(), title="", px_per_stud=3.0, labels=True, overlays=()):
    x0, x1, z0, z1 = rect
    sel = []
    for p in parts:
        b = p.aabb()
        if b[1] < x0 or b[0] > x1 or b[5] < z0 or b[4] > z1:
            continue
        sel.append(p)
    sel.sort(key=lambda p: (p.top, -p.size[0] * p.size[2]))
    w_in = max(6.0, (x1 - x0) * px_per_stud / 100)
    h_in = max(4.0, (z1 - z0) * px_per_stud / 100)
    fig = plt.figure(figsize=(w_in, h_in), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_facecolor((0.12, 0.14, 0.16))
    polys = [footprint(p) for p in sel]
    cols = [rgba(p) for p in sel]
    edge = [tuple(c * 0.6 for c in col[:3]) + (min(1, col[3] + 0.2),) for col in cols]
    ax.add_collection(PolyCollection(polys, facecolors=cols, edgecolors=edge, linewidths=0.15))
    for nm, poly, col in overlays:
        ax.add_patch(Polygon(poly, closed=True, fill=False, edgecolor=col, linewidth=0.9, zorder=5))
    for nm, (x, y, z), col in marks:
        if x0 <= x <= x1 and z0 <= z <= z1:
            ax.add_patch(Circle((x, z), 1.6, color=col, zorder=5))
            if labels:
                ax.text(x + 2, z - 2, nm, color=col, fontsize=5 if (x1 - x0) > 500 else 7, zorder=6)
    ax.set_xlim(x0, x1)
    ax.set_ylim(z1, z0)   # Norden oben
    ax.set_aspect("equal")
    ax.axis("off")
    if title:
        ax.text(x0 + 3, z0 + 8, title, color="white", fontsize=10, zorder=7)
    fig.savefig(path)
    plt.close(fig)


# isometrische Ansicht von Südost, leicht von oben
_CAM = (1.0, 1.1, 1.3)


def _iso_axes():
    c = _CAM
    ln = math.sqrt(sum(v * v for v in c))
    f = tuple(-v / ln for v in c)                      # Blickrichtung
    r = (-f[2], 0.0, f[0])                            # rechts = f x up
    rl = math.sqrt(r[0] ** 2 + r[2] ** 2)
    r = (r[0] / rl, 0.0, r[2] / rl)
    u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])
    u = tuple(-v for v in u) if u[1] < 0 else u
    return f, r, u


def _round_faces(p, hx, hy, hz, n=16):
    """Zylinder (Achse lokal X) bzw. Kugel als n-Eck-Prisma"""
    out = {}
    r = hy
    ring = [(math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r) for k in range(n)]
    if p.shape == 0:
        hx = r * 0.8
    for s in (-1, 1):
        out[(s, 0, 0)] = [(s * hx, a, b) for a, b in ring]
    for k in range(n):
        a0, b0 = ring[k]
        a1, b1 = ring[(k + 1) % n]
        am, bm = (a0 + a1) / 2, (b0 + b1) / 2
        ln = math.hypot(am, bm) or 1
        out[(0, am / ln, bm / ln + 1e-9 * k)] = [(-hx, a0, b0), (hx, a0, b0), (hx, a1, b1), (-hx, a1, b1)]
    return out


def _clip_rect(poly, rect):
    """3D-Polygon an den senkrechten Ebenen x0/x1/z0/z1 abschneiden"""
    x0, x1, z0, z1 = rect
    for axis, lim, keep_ge in ((0, x0, True), (0, x1, False), (2, z0, True), (2, z1, False)):
        out = []
        for i in range(len(poly)):
            p, q = poly[i], poly[(i + 1) % len(poly)]
            pin = p[axis] >= lim if keep_ge else p[axis] <= lim
            qin = q[axis] >= lim if keep_ge else q[axis] <= lim
            if pin:
                out.append(p)
            if pin != qin:
                t = (lim - p[axis]) / (q[axis] - p[axis])
                out.append(tuple(p[j] + (q[j] - p[j]) * t for j in range(3)))
        poly = out
        if not poly:
            break
    return poly


def _clip_y(poly, ymax):
    """3D-Polygon an der waagrechten Ebene y = ymax abschneiden (unteren Teil behalten)"""
    out = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        pin, qin = p[1] <= ymax, q[1] <= ymax
        if pin:
            out.append(p)
        if pin != qin:
            t = (ymax - p[1]) / (q[1] - p[1])
            out.append(tuple(p[j] + (q[j] - p[j]) * t for j in range(3)))
    return out


def iso_view(parts, rect, path, title="", ymax=None):
    """Isometrische Ansicht von Südost; ymax schneidet alles oberhalb ab (Innenansicht ohne Dach)."""
    x0, x1, z0, z1 = rect
    f, r, u = _iso_axes()
    sel = []
    for p in parts:
        b = p.aabb()
        if b[1] < x0 or b[0] > x1 or b[5] < z0 or b[4] > z1:
            continue
        if ymax is not None and b[2] >= ymax:
            continue
        sel.append(p)
    light = (0.35, 0.85, 0.4)

    def proj(q):
        return (sum(q[i] * r[i] for i in range(3)), sum(q[i] * u[i] for i in range(3)))

    faces = []
    for p in sel:
        cs = p.corners()
        hx, hy, hz = p.size[0] / 2, p.size[1] / 2, p.size[2] / 2
        if p.cls == "Part" and p.shape in (0, 2):
            loc = _round_faces(p, hx, hy, hz)
        elif p.cls == "WedgePart":
            loc = {(-1, 0, 0): [(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz)],
                   (1, 0, 0): [(hx, -hy, -hz), (hx, -hy, hz), (hx, hy, hz)],
                   (0, 0, 1): [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)],
                   (0, 1, -1): [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, hz), (-hx, hy, hz)],
                   (0, -1, 0): [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)]}
        else:
            loc = {}
            for a in range(3):
                for s in (-1, 1):
                    n = [0, 0, 0]
                    n[a] = s
                    o = [i for i in range(3) if i != a]
                    pts = []
                    for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                        v = [0.0, 0.0, 0.0]
                        v[a] = s * (hx, hy, hz)[a]
                        v[o[0]] = sa * (hx, hy, hz)[o[0]]
                        v[o[1]] = sb * (hx, hy, hz)[o[1]]
                        pts.append(tuple(v))
                    loc[tuple(n)] = pts
        for n, pts in loc.items():
            wn = p.cf.vector(n)
            ln = math.sqrt(sum(v * v for v in wn)) or 1
            wn = tuple(v / ln for v in wn)
            if sum(wn[i] * -f[i] for i in range(3)) <= 0.02:
                continue
            wp = _clip_rect([p.cf.point(q) for q in pts], rect)
            if ymax is not None and len(wp) >= 3:
                wp = _clip_y(wp, ymax)
            if len(wp) < 3:
                continue
            depth = sum(sum(q[i] for q in wp) / len(wp) * f[i] for i in range(3))
            shade = 0.55 + 0.45 * max(0.0, sum(wn[i] * light[i] for i in range(3)))
            height = p.top - p.aabb()[2]
            # Böden (auch Hallenböden -1..0) zuerst zeichnen, sonst übermalen ihre Oberseiten die Einrichtung
            flat = p.top <= -0.4 or height < 0.3 or (p.top <= 0.35 and height <= 1.2)
            key = (0, p.top, 0) if flat else (1, 0, -depth)
            faces.append((key, [proj(q) for q in wp], rgba(p, shade)))
    faces.sort(key=lambda t: t[0])
    allp = [q for _, poly, _ in faces for q in poly]
    if not allp:
        return
    xs = [q[0] for q in allp]
    ys = [q[1] for q in allp]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    scale = 2600 / max(w, h)
    fig = plt.figure(figsize=(max(4, w * scale / 100), max(3, h * scale / 100)), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_facecolor((0.55, 0.68, 0.8))
    ax.add_collection(PolyCollection([poly for _, poly, _ in faces], facecolors=[c for _, _, c in faces],
                                     edgecolors=[(0, 0, 0, 0.25)] * len(faces), linewidths=0.1))
    ax.set_xlim(min(xs), max(xs))
    ax.set_ylim(min(ys), max(ys))
    ax.set_aspect("equal")
    ax.axis("off")
    if title:
        ax.text(min(xs) + 2, max(ys) - 6, title, color="black", fontsize=10)
    fig.savefig(path)
    plt.close(fig)


def main(argv):
    args = list(argv)
    place = scan.DEFAULT_PLACE
    out = OUT
    with_plots = "--plots" in args
    rect = None
    cut = None
    name = "city"
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--district":
            name = args[i + 1]
            rect = DISTRICTS[name]
            i += 2
            continue
        if a == "--rect":
            rect = tuple(float(v) for v in args[i + 1:i + 5])
            name = "rect_%d_%d" % (rect[0], rect[2])
            i += 5
            continue
        if a == "--cut":
            cut = float(args[i + 1])
            i += 2
            continue
        if a == "--out":
            out = Path(args[i + 1])
            i += 2
            continue
        if not a.startswith("--"):
            place = a
        i += 1
    out.mkdir(parents=True, exist_ok=True)
    tree = scan.load(place)
    city, parts = gather(tree, with_plots)
    marks = markers(city)
    ovl = overlays(tree, city, with_plots)
    suffix = "_plots" if with_plots else ""
    if rect is None:
        p = out / ("city_top%s.png" % suffix)
        top_view(parts, (-665, 665, -475, 545), p, marks, "Werkstattmeile - Draufsicht", px_per_stud=3.2,
                 labels=False, overlays=ovl)
        print(p)
    else:
        p1 = out / ("%s_top%s.png" % (name, suffix))
        top_view(parts, rect, p1, marks, name, px_per_stud=max(4.0, 2400 / max(rect[1] - rect[0], rect[3] - rect[2])),
                 overlays=ovl)
        if cut is not None:
            p2 = out / ("%s_cut%g_iso%s.png" % (name, cut, suffix))
            iso_view(parts, rect, p2, "%s (Schnitt Y %g)" % (name, cut), ymax=cut)
        else:
            p2 = out / ("%s_iso%s.png" % (name, suffix))
            iso_view(parts, rect, p2, name)
        print(p1)
        print(p2)


if __name__ == "__main__":
    main(sys.argv[1:])
