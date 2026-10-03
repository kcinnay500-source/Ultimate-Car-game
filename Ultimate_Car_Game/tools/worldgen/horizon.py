"""Weltrand und Horizont der Stadt (3.0): natürlicher Rand, Fernboden, Skyline.

* build_edge(ground, lib)   (aus ground_roads.border_trees) City.Ground.Naturrand:
    Huegel   geschlossener Ring aus liegenden Gras-Zylindern (runde Kuppe, 26..32 hoch, ~90 breit), an jeder Stoßstelle
             eine Gras-Kugel "Kuppe" (höher, verdeckt die Zylinder-Enden) -> sanft rollende Hügelkette rund um die
             ganze befahrbare Welt (Stadt, Teststrecke bis Z 560, Große Werkstatt bis X -647)
    Felsen   Felsgruppen (3 gedrehte Granit-/Schieferblöcke) am Hügelfuß
    Baeume   dichte Baumreihe auf dem Kamm (Stamm + Kronenkugel) und Baumgruppen bei den Felsen
    Grenze   4 unsichtbare Sicherheitswände (Y -1.1..150) knapp außerhalb des Kamms - nur als letzte Sicherung hinter
             der natürlichen Schicht (checks.py erlaubt unsichtbare kollidierende Parts nur mit dem Namen "Grenze")
* build(city, lib, zone_rects)   (aus worldgen.apply nach allen Zonen) City.Horizon:
    Boden    Fernboden (Gras, Oberseite -1.10 wie die Grasplatte) bis ±1500 / -1450..1550 um die Grasplatte herum,
             ausgespart für Lobby/Tycoon, wenn diese Zonen im Place stehen (keine Überschneidung, kein Loch)
    Skyline  ferne Hochhäuser in zwei versetzten Reihen rundum (60..260 hoch): Körper, Glasfront zur Stadt
             (NightNeon für die Nachtschaltung), 2 Gesimsbänder, Dachaufbau, bei hohen Türmen Antenne + Warnlicht.
             Alle Parts CanCollide/CanTouch/CanQuery/CastShadow false; Lobby- und Tycoon-Fläche bleiben frei.
Höhen: Grasplatte/Fernboden -1.10, Hügel/Felsen/Bäume stehen auf dem Gras.
"""
import math
import random

from .lib import CF, GRASS, STEEL, TRUNK, set_attrs, Color3

# ---------------------------------------------------------------- Maße
Y_GRASS = -1.10
# Grasplatte der Stadt (ground_roads.build_ground)
GROUND = (-800.0, 800.0, -580.0, 698.0)
# Kammlinie des Hügelrings (Rechteck); Hügelfuß innen 45 davor: X ±690, Z -470 / +590. Die AABBs der Hügel reichen
# bis ~60 hinter den Kamm (Kugelradius) und bleiben so vor den Zonen Lobby (Z <= -600) und Tycoon (Z >= 700).
CREST = (-735.0, 735.0, -515.0, 635.0)
HILL_HALF = 45.0              # halbe Fußbreite der Hügel-Zylinder
WALL_OUT = 12.0               # Grenze: so weit hinter dem Kamm (außen)
WALL_TOP = 150.0
# innerer Hügelfuß (für Tests/Prüfungen): alles Befahrbare liegt innerhalb
INNER = (CREST[0] + HILL_HALF + 6, CREST[1] - HILL_HALF - 6, CREST[2] + HILL_HALF + 6, CREST[3] - HILL_HALF - 6)
# Fernboden
FAR = (-1500.0, 1500.0, -1450.0, 1550.0)
FAR_THICK = 1.8
# Skyline: vordere Reihe auf diesem Rechteck, hintere Reihe BACK_OFF weiter außen
SKY_FRONT = (-900.0, 900.0, -720.0, 830.0)
BACK_OFF = 130.0
SKY_SPACING = 118.0
SKY_BUDGET = 700
# Flächen der Zonen Lobby / Tycoon (lobby.py / tycoon.py, Grasplatten) - die Skyline hält Abstand
ZONE_KEEP_OUT = [(-100.0, 100.0, -780.0, -600.0), (-220.0, 220.0, 700.0, 1000.0)]
ZONE_MARGIN = 60.0

HILL_GREENS = [(73, 91, 64), (78, 98, 66), (70, 88, 60), (82, 102, 70)]
ROCKS = [(118, 116, 110), (104, 102, 98), (132, 128, 120), (96, 98, 96)]
CROWNS = [(58, 96, 56), (66, 108, 60), (52, 88, 52), (74, 112, 64), (61, 100, 65)]
BODIES = [(52, 64, 78), (70, 78, 90), (96, 104, 112), (120, 116, 108), (84, 92, 104), (60, 70, 84),
          (140, 136, 128), (108, 100, 92)]
GLASSES = [(60, 86, 110), (74, 110, 140), (46, 70, 92), (88, 120, 136)]
WIN_NIGHT = (255, 214, 150)
WARN = (230, 30, 30)


# ---------------------------------------------------------------- Hügelring (Geometrie, auch für Tests)
def ring_points():
    """Stoßstellen (x, z, Kuppenhöhe) der Hügelkette im Uhrzeigersinn, geschlossen (erster Punkt nicht doppelt)."""
    rng = random.Random(3011)
    x0, x1, z0, z1 = CREST
    corners = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    pts = []
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        ln = math.dist(a, b)
        n = max(1, int(round(ln / 105.0)))
        ux, uz = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        nx, nz = uz, -ux                    # nach außen (Ring im Uhrzeigersinn, Karte Norden oben)
        for k in range(n):
            t = ln * k / n
            off = 0.0 if k == 0 else -rng.uniform(0.0, 8.0)       # nur nach innen (AABB bleibt vor den Zonen)
            pts.append((a[0] + ux * t + nx * off, a[1] + uz * t + nz * off))
    caps = [rng.uniform(26.0, 32.0) for _ in pts]
    return pts, caps


def _cyl_radius(cap, half=HILL_HALF):
    """Radius eines Zylinders, dessen Kappe (Höhe cap über dem Gras) die Fußbreite 2*half hat"""
    return (half * half + cap * cap) / (2 * cap)


def hill_shapes():
    """[("cyl", a, b, R, cy, cap) | ("ball", c, R, cy, cap)] des Hügelrings (Welt-XZ, Achsenhöhe cy)."""
    pts, caps = ring_points()
    n = len(pts)
    out = []
    radii = []
    for i in range(n):
        cap = caps[i]
        R = _cyl_radius(cap)
        radii.append((R, cap))
        out.append(("cyl", pts[i], pts[(i + 1) % n], R, Y_GRASS + cap - R, cap))
    for i in range(n):
        Ra, ca = radii[i - 1]
        Rb, cb = radii[i]
        rs = max(Ra, Rb) + 7.0
        cap = max(ca, cb) + 5.0
        out.append(("ball", pts[i], rs, Y_GRASS + cap - rs, cap))
    return out


def surface_height(x, z, shapes=None):
    """Höhe der Hügeloberfläche bei (x, z) (Y_GRASS, wenn kein Hügel)"""
    best = Y_GRASS
    for s in shapes or hill_shapes():
        if s[0] == "cyl":
            a, b, R, cy = s[1], s[2], s[3], s[4]
            dx, dz = b[0] - a[0], b[1] - a[1]
            ln2 = dx * dx + dz * dz
            t = ((x - a[0]) * dx + (z - a[1]) * dz) / ln2
            if t < 0 or t > 1:
                continue
            d = math.hypot(x - a[0] - dx * t, z - a[1] - dz * t)
            if d < R:
                best = max(best, cy + math.sqrt(R * R - d * d))
        else:
            c, R, cy = s[1], s[2], s[3]
            d = math.hypot(x - c[0], z - c[1])
            if d < R:
                best = max(best, cy + math.sqrt(R * R - d * d))
    return best


def wall_rects():
    """Grenz-Wände (x0, x1, z0, z1): Nord/Süd über die volle Breite, Ost/West dazwischen"""
    x0, x1, z0, z1 = CREST
    wx0, wx1, wz0, wz1 = x0 - WALL_OUT, x1 + WALL_OUT, z0 - WALL_OUT, z1 + WALL_OUT
    return [(wx0 - 1, wx1 + 1, wz0 - 1, wz0 + 1), (wx0 - 1, wx1 + 1, wz1 - 1, wz1 + 1),
            (wx0 - 1, wx0 + 1, wz0 + 1, wz1 - 1), (wx1 - 1, wx1 + 1, wz0 + 1, wz1 - 1)]


# ---------------------------------------------------------------- Bausteine
def _rock(lib, parent, x, z, size, rot, color):
    """gedrehter Block, Unterkante -2.5 (im Gras), Oberseite je nach Drehung"""
    cf0 = CF(0, 0, 0) * CF.angles(*rot)
    h = [s / 2 for s in size]
    ey = sum(abs(cf0.R[1][j]) * h[j] for j in range(3))
    cf = CF(x, -2.5 + ey, z) * CF.angles(*rot)
    return lib.part(parent, "Fels", size, cf, color, "Slate" if color[0] < 110 else "Granite")


def _tree(lib, parent, x, y, z, s, crown, two=False, name="Randbaum"):
    """Kugelbaum: Stamm (kollidiert) + 1-2 Kronenkugeln (ohne Kollision, damit niemand hängen bleibt)"""
    m = lib.model(parent, name)
    th = 9.0 * s
    lib.cylinder(m, "Stamm", (x, y + th / 2, z), th, 1.5 * s, "Y", TRUNK, "Wood")
    d = 11.0 * s
    lib.ball(m, "Krone", (x, y + th + d * 0.3, z), d, crown, "Grass", deco=True)
    if two:
        d2 = d * 0.72
        lib.ball(m, "Krone", (x + d * 0.3, y + th + d * 0.75, z - d * 0.15), d2, crown, "Grass", deco=True)
    return m


# ---------------------------------------------------------------- natürlicher Rand
def build_edge(ground, lib):
    rng = random.Random(1907)
    edge = lib.model(ground, "Naturrand")
    hills = lib.model(edge, "Huegel")
    shapes = hill_shapes()
    for i, s in enumerate(shapes):
        col = HILL_GREENS[i % len(HILL_GREENS)]
        if s[0] == "cyl":
            a, b, R, cy = s[1], s[2], s[3], s[4]
            ln = math.dist(a, b)
            mid = ((a[0] + b[0]) / 2, cy, (a[1] + b[1]) / 2)
            # Zylinderachse = lokales X: von a nach b
            yaw = math.degrees(math.atan2(-(b[1] - a[1]), b[0] - a[0]))
            lib.part(hills, "Huegel", (ln, 2 * R, 2 * R), CF(*mid) * CF.yaw(yaw), col, "Grass", shape="Cylinder")
        else:
            c, R, cy = s[1], s[2], s[3]
            lib.ball(hills, "Kuppe", (c[0], cy, c[1]), 2 * R, col, "Grass")
    # Felsgruppen am inneren Hügelfuß (alle ~130 Studs), mit 1-2 Bäumen daneben
    rocks = lib.model(edge, "Felsen")
    trees = lib.model(edge, "Baeume")
    pts, caps = ring_points()
    n = len(pts)
    cx, cz = (CREST[0] + CREST[1]) / 2, (CREST[2] + CREST[3]) / 2
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        if True:
            f = 0.5 + rng.uniform(-0.15, 0.15)
            px, pz = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
            # nach innen (zur Stadtmitte) senkrecht zur Kette
            ux, uz = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(ux, uz)
            nx, nz = -uz / ln, ux / ln
            if nx * (cx - px) + nz * (cz - pz) < 0:
                nx, nz = -nx, -nz
            d = HILL_HALF + rng.uniform(1.0, 5.0)
            rx, rz = px + nx * d, pz + nz * d
            g = lib.model(rocks, "Felsgruppe")
            for k in range(3):
                sz = (rng.uniform(9, 15), rng.uniform(7, 12), rng.uniform(8, 13)) if k == 0 else \
                    (rng.uniform(4, 8), rng.uniform(3, 7), rng.uniform(4, 8))
                ox = rng.uniform(-7, 7) if k else 0
                oz = rng.uniform(-7, 7) if k else 0
                tx, tz = -nz, nx
                x = rx + tx * ox * 1.4 + nx * oz * 0.6
                z = rz + tz * ox * 1.4 + nz * oz * 0.6
                rot = (rng.uniform(-0.35, 0.35), rng.uniform(0, math.pi), rng.uniform(-0.35, 0.35))
                _rock(lib, g, x, z, sz, rot, ROCKS[(i + k) % len(ROCKS)])
            # Baumgruppe neben den Felsen (auf dem Gras vor dem Hügel)
            for k in range(1 + (i % 2)):
                side = -1 if k == 0 else 1
                tx, tz = -nz, nx
                x = rx + tx * side * rng.uniform(14, 22) + nx * rng.uniform(-2, 4)
                z = rz + tz * side * rng.uniform(14, 22) + nz * rng.uniform(-2, 4)
                y = surface_height(x, z, shapes) - 0.6
                _tree(lib, trees, x, y, z, rng.uniform(1.1, 1.5), CROWNS[(i + k) % len(CROWNS)], two=True)
    # Baumreihe auf dem Kamm (alle ~36 Studs, leicht versetzt)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        ln = math.dist(a, b)
        k_n = max(1, int(ln // 36))
        for k in range(k_n):
            f = (k + 0.5) / k_n
            ux, uz = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
            off = rng.uniform(-6, 6)
            x = a[0] + (b[0] - a[0]) * f - uz * off
            z = a[1] + (b[1] - a[1]) * f + ux * off
            y = surface_height(x, z, shapes) - 0.6
            _tree(lib, trees, x, y, z, rng.uniform(0.9, 1.3), CROWNS[(i + k) % len(CROWNS)], two=(k % 3 == 0),
                  name="Kammbaum")
    # unsichtbare Sicherheitswände knapp hinter dem Kamm
    for x0, x1, z0, z1 in wall_rects():
        lib.box(edge, "Grenze", x0, x1, Y_GRASS, WALL_TOP, z0, z1, (61, 100, 65), "SmoothPlastic", transparency=1,
                cast_shadow=False, query=False, touch=False)
    return edge


# ---------------------------------------------------------------- Fernboden + Skyline
def _subtract(rect, cuts):
    pieces = [rect]
    for c in cuts:
        nxt = []
        for (x0, x1, z0, z1) in pieces:
            cx0, cx1, cz0, cz1 = c
            if cx1 <= x0 or cx0 >= x1 or cz1 <= z0 or cz0 >= z1:
                nxt.append((x0, x1, z0, z1))
                continue
            if cx0 > x0:
                nxt.append((x0, cx0, z0, z1))
            if cx1 < x1:
                nxt.append((cx1, x1, z0, z1))
            ix0, ix1 = max(x0, cx0), min(x1, cx1)
            if cz0 > z0:
                nxt.append((ix0, ix1, z0, cz0))
            if cz1 < z1:
                nxt.append((ix0, ix1, cz1, z1))
        pieces = nxt
    return [p for p in pieces if p[1] - p[0] > 0.01 and p[3] - p[2] > 0.01]


def _split(rect, maxlen=2000.0):
    x0, x1, z0, z1 = rect
    nx = max(1, int(math.ceil((x1 - x0) / maxlen)))
    nz = max(1, int(math.ceil((z1 - z0) / maxlen)))
    out = []
    for i in range(nx):
        for j in range(nz):
            out.append((x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx,
                        z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz))
    return out


def far_ground_rects(zone_rects=()):
    out = []
    for r in _subtract(FAR, [GROUND] + list(zone_rects)):
        out += _split(r)
    return out


def _hits(a, b, gap=0.0):
    return a[0] < b[1] + gap and b[0] < a[1] + gap and a[2] < b[3] + gap and b[2] < a[3] + gap


def tower_plan():
    """[(x0, x1, z0, z1, h, face (nx, nz) zur Stadt, Reihe)] - deterministisch, ohne Überschneidung, außerhalb der
    Zonenflächen (mit Rand)."""
    rng = random.Random(2024)
    keep = [(r[0] - ZONE_MARGIN, r[1] + ZONE_MARGIN, r[2] - ZONE_MARGIN, r[3] + ZONE_MARGIN) for r in ZONE_KEEP_OUT]
    placed = []
    for row, off in ((0, 0.0), (1, BACK_OFF)):
        x0, x1, z0, z1 = SKY_FRONT
        x0, x1, z0, z1 = x0 - off, x1 + off, z0 - off, z1 + off
        sides = [((x0, z0), (x1, z0), (0, 1)), ((x1, z0), (x1, z1), (-1, 0)), ((x1, z1), (x0, z1), (0, -1)),
                 ((x0, z1), (x0, z0), (1, 0))]
        for a, b, face in sides:
            ln = math.dist(a, b)
            n = int(ln // SKY_SPACING)
            for k in range(n + 1):
                t = (k + (0.5 if row else 0.0)) * ln / n if n else 0
                if t > ln:
                    continue
                px = a[0] + (b[0] - a[0]) * t / ln
                pz = a[1] + (b[1] - a[1]) * t / ln
                w = rng.uniform(40, 76)
                d = rng.uniform(36, 60)
                h = rng.uniform(70, 175) if row == 0 else rng.uniform(125, 260)
                # Breite entlang der Seite, Tiefe nach außen
                if face[0] == 0:
                    sx, sz = w, d
                else:
                    sx, sz = d, w
                for step in range(12):
                    ox, oz = -face[0] * step * 45.0, -face[1] * step * 45.0
                    fp = (px + ox - sx / 2, px + ox + sx / 2, pz + oz - sz / 2, pz + oz + sz / 2)
                    if not any(_hits(fp, k_) for k_ in keep):
                        break
                else:
                    continue
                if any(_hits(fp, q[:4], 10.0) for q in placed):
                    continue
                if not (FAR[0] + 20 < fp[0] and fp[1] < FAR[1] - 20 and FAR[2] + 20 < fp[2] and fp[3] < FAR[3] - 20):
                    continue
                placed.append((fp[0], fp[1], fp[2], fp[3], round(h, 1), face, row))
    return placed


def _tower(lib, parent, i, t):
    x0, x1, z0, z1, h, (fx, fz), row = t
    rng = random.Random(500 + i)
    m = lib.model(parent, "Turm_%d" % (i + 1))
    body = BODIES[rng.randrange(len(BODIES))]
    glass = GLASSES[rng.randrange(len(GLASSES))]
    kw = dict(deco=True)
    lib.box(m, "Koerper", x0, x1, Y_GRASS, h, z0, z1, body, "Concrete" if i % 3 else "SmoothPlastic", **kw)
    # Glasfront auf der Stadtseite (0.4 dick, 0.2 vor der Fassade), 2 Gesimsbänder davor
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    y0, y1 = 6.0, h - 6.0
    if fx:
        fxp = x1 if fx > 0 else x0
        gx0, gx1 = sorted((fxp, fxp + fx * 0.4))
        gz0, gz1 = z0 + 3, z1 - 3
    else:
        fzp = z1 if fz > 0 else z0
        gz0, gz1 = sorted((fzp, fzp + fz * 0.4))
        gx0, gx1 = x0 + 3, x1 - 3
    win = lib.box(m, "Fenster", gx0, gx1, y0, y1, gz0, gz1, glass, "Glass", **kw)
    set_attrs(win, {"NightNeon": True, "NightColor": Color3(*WIN_NIGHT), "NightTransparency": 0.35})
    band = tuple(min(255, c + 30) for c in body)
    for f in (0.36, 0.7):
        yb = y0 + (y1 - y0) * f
        if fx:
            bx0, bx1 = sorted((fxp - fx * 0.3, fxp + fx * 0.7))
            lib.box(m, "Gesims", bx0, bx1, yb - 1.2, yb + 1.2, gz0 - 0.5, gz1 + 0.5, band, "Concrete", **kw)
        else:
            bz0, bz1 = sorted((fzp - fz * 0.3, fzp + fz * 0.7))
            lib.box(m, "Gesims", gx0 - 0.5, gx1 + 0.5, yb - 1.2, yb + 1.2, bz0, bz1, band, "Concrete", **kw)
    # Dachaufbau (Technikgeschoss)
    w, d = x1 - x0, z1 - z0
    rh = rng.uniform(5, 12)
    lib.box(m, "Dachaufbau", cx - w * 0.28, cx + w * 0.28, h, h + rh, cz - d * 0.28, cz + d * 0.28, band, "Concrete",
            **kw)
    if h > 170:
        ah = rng.uniform(18, 34)
        lib.cylinder(m, "Antenne", (cx, h + rh + ah / 2, cz), ah, 0.9, "Y", STEEL, "Metal", **kw)
        lib.ball(m, "Warnlicht", (cx, h + rh + ah + 0.6, cz), 1.8, WARN, "Neon", **kw)
    return m


def build(city, lib, zone_rects=()):
    """Fernboden (ohne die Flächen der Zonen im Place) und Skyline unter City.Horizon."""
    hz = lib.model(city, "Horizon", attrs={"Skyline": True})
    with lib.section("Horizont (Fernboden)"):
        bf = lib.model(hz, "Boden")
        for x0, x1, z0, z1 in far_ground_rects(zone_rects):
            lib.box(bf, "Fernboden", x0, x1, Y_GRASS - FAR_THICK, Y_GRASS, z0, z1, GRASS, "Grass")
    with lib.section("Horizont (Skyline)"):
        sk = lib.model(hz, "Skyline")
        n0 = lib.counts.get("Horizont (Skyline)", 0)
        for i, t in enumerate(tower_plan()):
            if lib.counts.get("Horizont (Skyline)", 0) - n0 + 8 > SKY_BUDGET:
                break
            _tower(lib, sk, i, t)
    return hz
