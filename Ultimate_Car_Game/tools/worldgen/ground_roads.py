"""Boden, Rand, Straßen, Markierungen, Zebrastreifen, Kreisel, Laternen, Ampeln und Verkehrsschleifen
(CITY_SPEC §1.2, §2, §3, §6 "Werkstattmeile dressing" (Tore, Kreisel-Skulpturen), §9.1).

Höhen-Stapel (§1.2, nie zwei überlappende Oberseiten auf gleicher Höhe):
  Gras-Platte -1.10 | Bodenplatten -1.00 | Kreiselscheibe -0.98 | Fahrbahn -0.95 | Markierungen -0.90
  | Gehwege/Platz -0.50 (Kreisel-Gehwegring abwechselnd -0.52/-0.54, Inselgras -0.45)
"""
import math

from .lib import (CF, AMBER, APRON, ASPHALT, BLACK, GRASS, HEDGE, PLAZA, RED, SIDEWALK, SLATE, STEEL, TEAL,
                  WHITE, Vec3, set_attrs, yaw_towards)

Y_GRASS = -1.10
Y_GROUND = -1.00
Y_DISC = -0.98
Y_ROAD = -0.95
Y_MARK = -0.90
Y_WALK = -0.50
BOTTOM = -1.25
ZEBRA = (235, 238, 240)
RUST = (140, 70, 40)
DIRT = (92, 84, 72)
TUNING_GROUND = (52, 58, 66)

# ---------------------------------------------------------------- Geometrie-Daten (§3)
# Fahrbahn-Stücke außerhalb der Knoten (x0,x1,z0,z1)
CARRIAGEWAYS = [
    ("Werkstattmeile West", -484, -175, -13, 13),
    ("Werkstattmeile Mitte", -129, 129, -13, 13),
    ("Werkstattmeile Ost", 175, 484, -13, 13),
    ("Marktstrasse West Nord", -165, -139, -320, -23),
    ("Marktstrasse West Sued", -165, -139, 23, 178),
    ("Marktstrasse Ost Nord", 139, 165, -320, -23),
    ("Marktstrasse Ost Sued", 139, 165, 23, 178),
    ("Nordring", -130, 130, -355, -329),
    ("Suedring", -130, 130, 187, 213),
    ("Boxengasse", 88, 112, 222, 258),
    ("Autohaus-Zufahrt", 92, 108, 96, 178),
    ("Dragstrip", 174, 450, -350, -326),
]
K_NODES = [("K-West", -152, 0), ("K-Ost", 152, 0)]
L_NODES = [("Ecke Nordwest", -152, -342, 1, 1), ("Ecke Nordost", 152, -342, -1, 1),
           ("Ecke Suedwest", -152, 200, 1, -1), ("Ecke Suedost", 152, 200, -1, -1)]
KREISEL = [("Kreisel West", -518, 0), ("Kreisel Ost", 518, 0)]

# Gehweg-Streifen außerhalb der Knoten (Name, x0,x1,z0,z1)
SIDEWALKS = [
    ("Meile Nord West", -480, -175, -23, -13), ("Meile Nord Mitte", -129, 129, -23, -13),
    ("Meile Nord Ost", 175, 480, -23, -13),
    ("Meile Sued West", -480, -175, 13, 23), ("Meile Sued Mitte", -129, 129, 13, 23),
    ("Meile Sued Ost", 175, 480, 13, 23),
    ("Markt West W Nord", -174, -165, -320, -23), ("Markt West W Sued", -174, -165, 23, 178),
    ("Markt West O Nord", -139, -130, -320, -23), ("Markt West O Sued", -139, -130, 23, 178),
    ("Markt Ost W Nord", 130, 139, -320, -23), ("Markt Ost W Sued", 130, 139, 23, 178),
    ("Markt Ost O Nord", 165, 174, -320, -23), ("Markt Ost O Sued", 165, 174, 23, 178),
    ("Nordring N", -130, 130, -364, -355), ("Nordring S", -130, 130, -329, -320),
    ("Suedring N", -130, 130, 178, 187), ("Suedring S", -130, 130, 213, 222),
]

# Absenkungen (§3.4): (Name, x0,x1,z0,z1, Vorfeld über den Grasstreifen oder None)
CURB_CUTS = [
    ("Tankstelle Einfahrt", 165, 174, 164, 176, (174, 178, 164, 176)),
    ("Tankstelle Ausfahrt", 165, 174, 206, 216, (174, 178, 206, 216)),
    ("Parkplatz Einfahrt", -110, -90, -329, -320, None),
    ("Schrottplatz Tor", -174, -165, -211, -191, (-178, -174, -211, -191)),
    ("Tuning Rolltor", 165, 174, -258, -240, (174, 178, -258, -240)),
    ("Uebergabe-Halle", 92, 108, 13, 23, None),
    ("Autohaus hinten", 92, 108, 178, 187, None),
    ("Boxengasse", 88, 112, 213, 222, None),
    ("Dragstrip", 165, 174, -350, -326, None),
]

# Zebrastreifen (§3.5): (Id, Straße-Achse, lo, hi) - 'x': Band in X über eine O-W-Straße (Mittellinie z),
# 'z': Band in Z über eine N-S-Straße (Mittellinie x). approach: welche Seite eine Haltelinie bekommt.
CROSSWALKS = [
    ("Z1", "x", 0, -6, 6, "both", "signal"),
    ("Z2", "x", 0, -327, -319, "both", "zebra"),
    ("Z3", "x", 0, 319, 327, "both", "zebra"),
    ("Z4", "x", 0, -183, -175, "lo", "signal"),
    ("Z5", "x", 0, -129, -121, "hi", "signal"),
    ("Z6", "z", -152, -31, -23, "lo", "signal"),
    ("Z7", "z", -152, 23, 31, "hi", "signal"),
    ("Z8", "x", 0, 175, 183, "hi", "signal"),
    ("Z9", "x", 0, 121, 129, "lo", "signal"),
    ("Z10", "z", 152, -31, -23, "lo", "signal"),
    ("Z11", "z", 152, 23, 31, "hi", "signal"),
    ("Z12", "z", -152, -207, -195, "both", "signal"),
    ("Z13", "z", 152, -207, -195, "both", "signal"),
    ("Z14", "z", -152, 161, 169, "both", "zebra"),
    ("Z15", "z", 152, 161, 169, "both", "zebra"),
    ("Z16", "x", 200, -5, 5, "both", "zebra"),
]

# Straßenlaternen (§9.1): (Gruppe, x, z, Auslegerrichtung)
def street_lamps():
    out = []
    meile = [(306, -14.5), (-306, 14.5), (-310, -14.5), (310, 14.5), (336, -14.5), (456, -14.5), (-336, 14.5),
             (-456, 14.5), (-460, -14.5), (-340, -14.5), (460, 14.5), (340, 14.5), (-100, -14.5), (-100, 14.5),
             (-20, 14.5), (-20, -14.5), (20, -14.5), (20, 14.5), (100, 14.5), (100, -14.5)]
    for x, z in meile:
        out.append(("Meile", x, z, 0, 1 if z < 0 else -1))
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * 545, sz * 32.2
            cx = sx * 518
            d = math.hypot(cx - x, -z)
            out.append(("Kreisel", x, z, (cx - x) / d, -z / d))
    zs = [-305, -265, -215, -145, -80, 45, 105, 175]
    for sg in (-1, 1):
        for i, z in enumerate(zs):
            x = sg * (137.5 if i % 2 == 0 else 166.5)
            dx = -1 if x in (-137.5, 166.5) else 1
            out.append(("Markt" + ("W" if sg < 0 else "O"), x, z, dx, 0))
    for x in (-100, -35, 35, 100):
        out.append(("Nordring", x, -327.5, 0, -1))
        out.append(("Suedring", x, 185.5, 0, 1))
    return out


# ---------------------------------------------------------------- Verkehrsschleifen (§3.7, wie design/check.py)
def _ring(cx, cz, r, a0, a1, step):
    n = max(1, int(round(abs(a1 - a0) / step)))
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
             cz + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


def _rect_loop(xl, xr, zt, zb, r, cw, step=15):
    p = []
    if cw:
        p += [(xl + r, zt), (xr - r, zt)] + _ring(xr - r, zt + r, r, -90, 0, step)[1:] + [(xr, zb - r)]
        p += _ring(xr - r, zb - r, r, 0, 90, step)[1:]
        p += [(xl + r, zb)] + _ring(xl + r, zb - r, r, 90, 180, step)[1:] + [(xl, zt + r)]
        p += _ring(xl + r, zt + r, r, 180, 270, step)[1:-1]
    else:
        p += [(xr - r, zt), (xl + r, zt)] + _ring(xl + r, zt + r, r, 270, 180, step)[1:] + [(xl, zb - r)]
        p += _ring(xl + r, zb - r, r, 180, 90, step)[1:]
        p += [(xr - r, zb)] + _ring(xr - r, zb - r, r, 90, 0, step)[1:] + [(xr, zt + r)]
        p += _ring(xr - r, zt + r, r, 0, -90, step)[1:-1]
    return p


def traffic_loops():
    L = 25
    ex = math.sqrt(L * L - 6.5 * 6.5)
    th = math.degrees(math.atan2(6.5, -ex))
    A = [(-518 + ex, 6.5), (-186, 6.5), (-9, 6.5), (118, 6.5), (518 - ex, 6.5)] + _ring(518, 0, L, th, -th, 30)[1:]
    A += [(186, -6.5), (9, -6.5), (-118, -6.5)]
    A += _ring(-518, 0, L, -(180 - th), -(180 - th) - (360 - 2 * (180 - th)), 30)
    B1 = _rect_loop(-145.5, 145.5, -335.5, 193.5, 14, True)
    B2 = _rect_loop(-158.5, 158.5, -348.5, 206.5, 27, False)
    T = [(-85, 270), (85, 270)] + _ring(85, 340, 70, -90, 90, 15)[1:] + [(-85, 410)]
    T += _ring(-85, 340, 70, 90, 270, 15)[1:-1]
    return [("A", "Meile-Schleife", A, 26), ("B1", "Innenstadtring innen", B1, 24),
            ("B2", "Innenstadtring aussen", B2, 24), ("T", "Teststrecke", T, 45)]


def path_point(pts, d):
    """Punkt und Richtung bei Strecke d auf der geschlossenen Schleife"""
    segs = []
    total = 0.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        ln = math.dist(a, b)
        segs.append((a, b, ln, total))
        total += ln
    d %= total
    for a, b, ln, st in segs:
        if st <= d <= st + ln and ln > 0:
            f = (d - st) / ln
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f), ((b[0] - a[0]) / ln, (b[1] - a[1]) / ln), total
    a, b, ln, st = segs[-1]
    return b, ((b[0] - a[0]) / ln, (b[1] - a[1]) / ln), total


# ---------------------------------------------------------------- Rechteck-Helfer
def subtract(rect, cuts):
    """rect minus Liste von Rechtecken -> Liste disjunkter Rechtecke (x0,x1,z0,z1)"""
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


def intersect(a, b):
    x0, x1, z0, z1 = max(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3])
    if x1 - x0 > 0.01 and z1 - z0 > 0.01:
        return (x0, x1, z0, z1)
    return None


def plot_cuts():
    """Plot-Einfahrten und Rolltor-Zufahrten auf den Meile-Gehwegen (§4.2, §4.3) aus plots.SLOTS"""
    from .plots import SLOTS, loc2world
    out = []
    for slot, house, px, pz, rot in SLOTS:
        zs = (-23, -13) if pz < 0 else (13, 23)
        apron = (-25, -23) if pz < 0 else (23, 25)
        for nm, lx0, lx1 in (("Einfahrt", -30, 30), ("Rolltor", -53, -33)):
            xa = loc2world(px, pz, rot, lx0, 0)[0]
            xb = loc2world(px, pz, rot, lx1, 0)[0]
            x0, x1 = min(xa, xb), max(xa, xb)
            out.append(("Nr. %d %s" % (house, nm), x0, x1, zs[0], zs[1], (x0, x1, apron[0], apron[1])))
    return out


# ---------------------------------------------------------------- Bau
def build(city, lib, tree):
    ground = lib.folder(city, "Ground")
    roads = lib.folder(city, "Roads")
    lights = lib.folder(city, "Lights")
    animated = lib.folder(city, "Animated")
    with lib.section("Boden & Rand"):
        build_ground(ground, lib)
    with lib.section("Randbäume"):
        border_trees(ground, lib)
    with lib.section("Straßen & Markierungen"):
        build_roads(roads, lib)
    with lib.section("Zebrastreifen"):
        build_crosswalks(roads, lib)
    with lib.section("Kreisel & Tore"):
        build_kreisel(roads, animated, lib)
        build_arches(roads, lights, lib)
    with lib.section("Straßenlaternen"):
        lamps = lib.folder(lights, "Strassenlaternen")
        for grp, x, z, dx, dz in street_lamps():
            y = -0.5 if grp != "Kreisel" else -0.52
            lib.street_lamp(lamps, x, z, y, dx, dz, name="Laterne_" + grp)
    with lib.section("Ampeln"):
        build_signals(animated, lib)
    with lib.section("Verkehr (Wegpunkte)"):
        loops = build_loops(animated, lib)
    with lib.section("Verkehr (Autos, außer Budget)"):
        build_traffic_cars(animated, lib, loops)


def build_ground(ground, lib):
    lib.box(ground, "Grasplatte", -660, 660, Y_GRASS - 4, Y_GRASS, -470, 540, GRASS, "Grass")
    # Heckenring 3 breit x 5 hoch; Nord/Süd zwischen den Ost/West-Hecken (keine Überlappung)
    hy0, hy1 = Y_GRASS, Y_GRASS + 5
    lib.box(ground, "Hecke", -591.5, -588.5, hy0, hy1, -391.5, 471.5, HEDGE, "Grass")
    lib.box(ground, "Hecke", 588.5, 591.5, hy0, hy1, -391.5, 471.5, HEDGE, "Grass")
    lib.box(ground, "Hecke", -588.5, 588.5, hy0, hy1, -391.5, -388.5, HEDGE, "Grass")
    lib.box(ground, "Hecke", -588.5, 588.5, hy0, hy1, 468.5, 471.5, HEDGE, "Grass")
    for x0, x1, z0, z1 in ((-590.5, -589.5, -390, 470), (589.5, 590.5, -390, 470),
                           (-590, 590, -390.5, -389.5), (-590, 590, 469.5, 470.5)):
        lib.box(ground, "Grenze", x0, x1, Y_GRASS, Y_GRASS + 60, z0, z1, HEDGE, "SmoothPlastic", transparency=1,
                cast_shadow=False, query=False, touch=False)
    # Bodenplatten der Bezirke (0,3 dick, Oberseite -1.00)
    y0, y1 = Y_GROUND - 0.3, Y_GROUND
    lib.box(ground, "Schrottplatz-Boden", -468, -178, y0, y1, -364, -159, DIRT, "Pebble")
    lib.box(ground, "Tuning-Gelaende", 178, 468, y0, y1, -364, -159, TUNING_GROUND, "Concrete")
    lib.box(ground, "Tankstellen-Gelaende", 178, 400, y0, y1, 159, 260, APRON, "Concrete")
    lib.box(ground, "Autohaus-Gelaende", -130, 130, y0, y1, 23, 178, APRON, "Concrete")
    lib.box(ground, "Parkplatz-Chaos-Flaeche", -130, 130, y0, y1, -320, -229, ASPHALT, "Asphalt")
    # Altstadt-Pflaster (Stadtplatz, Frontstreifen, Querachse-Promenaden, Hallenvorfeld), Oberseite -0.50
    lib.box(ground, "Altstadt-Pflaster", -130, 130, BOTTOM, Y_WALK, -229, -23, PLAZA, "Slate")
    # Gassen-Fußwege X ±320..±326 (Schrottgasse / Tuninggasse, §4.2)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 320, sx * 326))
        lib.box(ground, "Gassenweg", x0, x1, BOTTOM, Y_WALK, -159, -23, SIDEWALK, "Concrete")
        lib.box(ground, "Gassenweg", x0, x1, BOTTOM, Y_WALK, 23, 159, SIDEWALK, "Concrete")


def border_trees(ground, lib):
    m = lib.folder(ground, "Randbaeume")
    pts = [(x, -378) for x in (-540, -420, -300, -180, -60, 60, 180, 300, 420, 540)]
    for z in (-330, -200, 60, 200, 380):
        pts += [(-575, z), (575, z)]
    for i, (x, z) in enumerate(pts):
        lib.tree_lite(m, x, Y_GRASS, z, scale=1.5, seed=i, name="Randbaum")


def build_roads(roads, lib):
    asphalt = lib.folder(roads, "Fahrbahn")
    walks = lib.folder(roads, "Gehwege")
    marks = lib.folder(roads, "Markierungen")
    cuts = CURB_CUTS + plot_cuts()
    for nm, x0, x1, z0, z1 in CARRIAGEWAYS:
        lib.box(asphalt, nm, x0, x1, BOTTOM, Y_ROAD, z0, z1, ASPHALT, "Asphalt")
    # Knotenplatten: K-Knoten 46 x 46 (Fahrbahn + Gehwege), L-Ecken 44 x 44
    for nm, cx, cz in K_NODES:
        lib.box(asphalt, nm, cx - 23, cx + 23, BOTTOM, Y_ROAD, cz - 23, cz + 23, ASPHALT, "Asphalt")
    for nm, cx, cz, ix, iz in L_NODES:
        lib.box(asphalt, nm, cx - 22, cx + 22, BOTTOM, Y_ROAD, cz - 22, cz + 22, ASPHALT, "Asphalt")
    # Gehwege (volle Dicke) minus Absenkungen; Absenkungen werden Fahrbahn-Stücke
    for nm, x0, x1, z0, z1 in SIDEWALKS:
        rect = (x0, x1, z0, z1)
        my = [c[1:5] for c in cuts]
        for p in subtract(rect, my):
            lib.box(walks, "Gehweg " + nm, p[0], p[1], BOTTOM, Y_WALK, p[2], p[3], SIDEWALK, "Concrete")
        for c in cuts:
            hit = intersect(rect, c[1:5])
            if hit:
                lib.box(asphalt, "Absenkung " + c[0], hit[0], hit[1], BOTTOM, Y_ROAD, hit[2], hit[3], ASPHALT,
                        "Asphalt")
    for c in cuts:
        if c[5]:
            x0, x1, z0, z1 = c[5]
            lib.box(asphalt, "Vorfeld " + c[0], x0, x1, BOTTOM, Y_ROAD, z0, z1, ASPHALT, "Asphalt")
    # Gehweg-Eckstücke in den Knoten (liegen auf der Knotenplatte: -0.95..-0.50) mit 45°-Fasen
    node_cuts = [c[1:5] for c in cuts]

    def node_walk(nm, x0, x1, z0, z1):
        for p in subtract((min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)), node_cuts):
            lib.box(walks, nm, p[0], p[1], Y_ROAD, Y_WALK, p[2], p[3], SIDEWALK, "Concrete")

    def chamfer_corner(nm, cx, cz, sx, sz, outer):
        """Eckquadrat von der Bordsteinecke c=(cx,cz) aus nach (sx,sz), Kantenlänge outer, Fase 8"""
        ox, oz = cx + sx * outer, cz + sz * outer
        fx, fz = cx + sx * 8, cz + sz * 8
        node_walk(nm, fx, ox, cz, oz)                     # Streifen außen in X
        node_walk(nm, cx, fx, fz, oz)                     # Streifen außen in Z
        lib.flat_tri(walks, nm + " Fase", (fx, fz), (fx, cz), (cx, fz), Y_ROAD, Y_WALK, SIDEWALK, "Concrete")

    for nm, cx, cz in K_NODES:
        for sx in (-1, 1):
            for sz in (-1, 1):
                chamfer_corner("Ecke " + nm, cx + sx * 13, cz + sz * 13, sx, sz, 10)
    for nm, cx, cz, ix, iz in L_NODES:
        chamfer_corner("Ecke " + nm, cx + ix * 13, cz + iz * 13, ix, iz, 9)
        # äußeres L
        node_walk("Ecke " + nm, cx - 22, cx + 22, cz - iz * 22, cz - iz * 13)
        node_walk("Ecke " + nm, cx - ix * 22, cx - ix * 13, cz - iz * 13, cz + iz * 22)
    build_markings(marks, lib)


def _skip_ranges_x():
    """X-Bereiche auf der Meile ohne Markierung (Knoten, Zebras)"""
    out = [(-175, -129), (129, 175)]
    for cid, ax, c, lo, hi, app, kind in CROSSWALKS:
        if ax == "x" and c == 0:
            out.append((lo, hi))
    return out


def _free(a, b, skips, margin=1.0):
    """Intervall [a,b] minus Sperrbereiche (mit Rand)"""
    segs = [(a, b)]
    for s0, s1 in skips:
        s0, s1 = s0 - margin, s1 + margin
        nxt = []
        for x0, x1 in segs:
            if s1 <= x0 or s0 >= x1:
                nxt.append((x0, x1))
                continue
            if s0 > x0:
                nxt.append((x0, s0))
            if s1 < x1:
                nxt.append((s1, x1))
        segs = nxt
    return [s for s in segs if s[1] - s[0] > 1.0]


def build_markings(marks, lib):
    my0, my1 = Y_ROAD, Y_MARK
    # Straßen: (Name, Achse der Fahrtrichtung, Mittellinie, von, bis, Sperrbereiche)
    cw_x = {c: [] for c in (0, 200, -342)}
    cw_z = {-152: [], 152: []}
    for cid, ax, c, lo, hi, app, kind in CROSSWALKS:
        (cw_x if ax == "x" else cw_z)[c].append((lo, hi))
    roads = [
        ("Meile", "x", 0, -480, 480, [(-175, -129), (129, 175)] + cw_x[0]),
        ("Nordring", "x", -342, -130, 130, []),
        ("Suedring", "x", 200, -130, 130, cw_x[200]),
        ("Markt West", "z", -152, -320, 178, [(-23, 23)] + cw_z[-152]),
        ("Markt Ost", "z", 152, -320, 178, [(-23, 23)] + cw_z[152]),
    ]
    for nm, ax, c, a, b, skips in roads:
        # Mittelstriche 9 x 0,5 alle 20
        k0 = math.ceil((a + 5) / 20)
        t = k0 * 20
        while t + 4.5 <= b - 1:
            ok = all(not (t + 4.5 > s0 - 1.5 and t - 4.5 < s1 + 1.5) for s0, s1 in skips)
            if ok:
                if ax == "x":
                    lib.box(marks, "Mittelstrich", t - 4.5, t + 4.5, my0, my1, c - 0.25, c + 0.25, AMBER, "SmoothPlastic",
                            deco=True)
                else:
                    lib.box(marks, "Mittelstrich", c - 0.25, c + 0.25, my0, my1, t - 4.5, t + 4.5, AMBER, "SmoothPlastic",
                            deco=True)
            t += 20
        # weiße Randlinien 0,4 breit, 0,7 innerhalb des Bordsteins
        for s0, s1 in _free(a, b, skips, 0.5):
            for side in (-1, 1):
                e = c + side * (13 - 0.7)
                if ax == "x":
                    lib.box(marks, "Randlinie", s0, s1, my0, my1, e - 0.2, e + 0.2, WHITE, "SmoothPlastic", deco=True)
                else:
                    lib.box(marks, "Randlinie", e - 0.2, e + 0.2, my0, my1, s0, s1, WHITE, "SmoothPlastic", deco=True)
    # Wartelinien (gestrichelt) an den Kreiselmündungen, nur Einfahrtsspur
    for nm, cx, cz in KREISEL:
        s = 1 if cx > 0 else -1
        x = cx - s * 39.5
        zlane = (0.4, 12.0) if s > 0 else (-12.0, -0.4)
        z = zlane[0]
        while z + 1.4 <= zlane[1] + 0.01:
            lib.box(marks, "Wartelinie", x - 0.3, x + 0.3, my0, my1, z, z + 1.4, WHITE, "SmoothPlastic", deco=True)
            z += 2.9


def build_crosswalks(roads, lib):
    zf = lib.folder(roads, "Zebrastreifen")
    for cid, ax, c, lo, hi, app, kind in CROSSWALKS:
        m = lib.model(zf, cid, attrs={"Crosswalk": cid, "Control": kind, "BandLo": lo, "BandHi": hi,
                                      "Axis": ax, "Center": c})
        width = hi - lo
        mid = (lo + hi) / 2
        for k in range(8):
            off = -11.2 + 3.2 * k
            if ax == "x":
                lib.box(m, "Balken", lo, hi, Y_ROAD, Y_MARK, c + off - 0.8, c + off + 0.8, ZEBRA, "SmoothPlastic",
                        deco=True)
            else:
                lib.box(m, "Balken", c + off - 0.8, c + off + 0.8, Y_ROAD, Y_MARK, lo, hi, ZEBRA, "SmoothPlastic",
                        deco=True)
        # Haltelinien 2 vor dem Zebra, je Anfahrtsspur (Rechtsverkehr)
        sides = {"lo": [-1], "hi": [1], "both": [-1, 1]}[app]
        for sd in sides:
            if ax == "x":
                x = (lo - 2.3) if sd < 0 else (hi + 2.3)
                # von Westen kommend (Richtung +X) fährt man südlich der Mitte
                z0, z1 = (c + 0.3, c + 12.05) if sd < 0 else (c - 12.05, c - 0.3)
                lib.box(m, "Haltelinie", x - 0.3, x + 0.3, Y_ROAD, Y_MARK, z0, z1, WHITE, "SmoothPlastic", deco=True)
            else:
                z = (lo - 2.3) if sd < 0 else (hi + 2.3)
                # von Norden kommend (Richtung +Z) fährt man westlich der Mitte
                x0, x1 = (c - 12.05, c - 0.3) if sd < 0 else (c + 0.3, c + 12.05)
                lib.box(m, "Haltelinie", x0, x1, Y_ROAD, Y_MARK, z - 0.3, z + 0.3, WHITE, "SmoothPlastic", deco=True)
        # Blinklicht-Masten an Zebras ohne Ampel (Z2/Z3/Z14-16)
        if kind == "zebra":
            for sd in (-1, 1):
                if ax == "x":
                    px, pz = hi + 1.3, c + sd * 15.5
                else:
                    px, pz = c + sd * 15.5, hi + 1.3
                lib.cylinder(m, "BakenMast", (px, Y_WALK + 3.25, pz), 6.5, 0.35, "Y", WHITE, "SmoothPlastic")
                lib.ball(m, "Bake", (px, Y_WALK + 7.1, pz), 1.2, AMBER, "Neon", deco=True)


def build_kreisel(roads, animated, lib):
    kf = lib.folder(roads, "Kreisel")
    for nm, cx, cz in KREISEL:
        m = lib.model(kf, nm)
        lib.cylinder(m, "Kreiselscheibe", (cx, Y_DISC - 0.15, cz), 0.3, 76, "Y", ASPHALT, "Asphalt")
        lib.cylinder(m, "Inselbord", (cx, (Y_DISC + Y_WALK) / 2, cz), Y_WALK - Y_DISC, 25, "Y", SIDEWALK, "Concrete")
        lib.cylinder(m, "Inselgras", (cx, (Y_DISC - 0.45) / 2, cz), -0.45 - Y_DISC, 23, "Y", GRASS, "Grass")
        # Gehwegring r 38..46: 16 Sektoren, die 2 an der Meile-Mündung fehlen (abwechselnd -0.52/-0.54)
        mouth = 180 if cx > 0 else 0
        seq = []
        for k in range(16):
            a = 11.25 + 22.5 * k
            dm = abs((a - mouth + 180) % 360 - 180)
            if dm < 22.5:
                continue
            seq.append(a)
        seq.sort(key=lambda a: (a - mouth) % 360)
        for i, a in enumerate(seq):
            top = -0.52 if i % 2 == 0 else -0.54
            r = math.radians(a)
            px, pz = cx + 42 * math.cos(r), cz + 42 * math.sin(r)
            yaw = yaw_towards(math.cos(r), math.sin(r))   # lokales -Z zeigt radial nach außen
            lib.part(m, "Ringgehweg", (18.5, top - BOTTOM, 8), CF.at(px, (top + BOTTOM) / 2, pz, yaw), SIDEWALK,
                     "Concrete")
    # Skulptur West: Schrottturm (rostige Säule, 6 gepresste Würfel, Rundumleuchte)
    cx = -518
    sk = lib.model(kf, "Schrottturm")
    lib.cylinder(sk, "Rostsaeule", (cx, -0.45 + 10, 0), 20, 3, "Y", RUST, "CorrodedMetal")
    cols = [(120, 60, 40), (90, 96, 104), (150, 120, 60), (70, 90, 110), (130, 50, 45), (104, 110, 114)]
    for i in range(6):
        a = math.radians(i * 72 + (30 if i == 5 else 0))
        h = -0.45 + (i // 2) * 3.2
        r = 3.6 if i < 5 else 0
        cfc = CF(cx + r * math.cos(a), h + 1.5, r * math.sin(a)) * CF.angles(0.05 * (i % 3), math.radians(i * 37), 0.04)
        if i == 5:
            cfc = CF(cx + 2.0, 12.5, 1.0) * CF.angles(0.1, 0.6, -0.08)
        lib.part(sk, "Pressling", (4, 3, 4), cfc, cols[i], "CorrodedMetal")
    lib.box(sk, "Stahlkappe", cx - 2, cx + 2, 19.55, 20.15, -2, 2, (240, 190, 40), "Metal")
    kan = lib.folder(animated, "Kreisel")
    bk = lib.ball(kan, "Rundumleuchte", (cx, 20.85, 0), 1.4, AMBER, "Neon", deco=True)
    set_attrs(bk, {"Anim": "beacon"})
    # Skulptur Ost: Drehteller Ø14 mit Vorlagen-Sport in Petrol (Anim turntable)
    cx = 518
    tt = lib.model(kan, "KreiselDrehteller", attrs={"Anim": "turntable", "Speed": 15})
    disc = lib.cylinder(tt, "Drehteller", (cx, -0.2, 0), 0.5, 14, "Y", (36, 40, 46), "Metal")
    lib.cylinder(tt, "Leuchtring", (cx, -0.225, 0), 0.45, 14.6, "Y", AMBER, "Neon", deco=True)
    lib.set_primary(tt, disc)
    with lib.section("Kreisel & Tore (Auto)"):
        lib.clone_car(tt, "sport", CF.at(cx, 0.05, 0, 135), TEAL, name="Sport_Kreisel")


def build_arches(roads, lights, lib):
    tf = lib.folder(roads, "Tore")
    lamps = lib.folder(lights, "Torlaternen")
    for sx in (-1, 1):
        x = sx * 186
        m = lib.model(tf, "Tor_" + ("West" if sx < 0 else "Ost"))
        for sz in (-1, 1):
            z = sz * 18
            lib.box(m, "Pfeiler", x - 1, x + 1, Y_WALK, 22, z - 1, z + 1, AMBER, "Metal")
            lib.box(m, "Pfeilerfuss", x - 1.4, x + 1.4, Y_WALK, Y_WALK + 1.2, z - 1.4, z + 1.4, SLATE, "Metal")
            head = lib.box(lamps, "Torlaterne", x - 0.8, x + 0.8, 22, 23.4, z - 0.8, z + 0.8, (255, 224, 169),
                           "SmoothPlastic", deco=True)
            set_attrs(head, {"NightNeon": True})
            lib.point_light(head, 26, 0.9)
        lib.box(m, "Torbalken", x - 1, x + 1, 18, 22, -17, 17, SLATE, "Metal")
        lib.box(m, "Neonkante", x - 0.8, x + 0.8, 17.8, 18, -17, 17, AMBER, "Neon", deco=True)
        inner = "WERKSTATTMEILE · Nr. " + ("1–4" if sx < 0 else "5–8")
        outer = "ZUM STADTPLATZ"
        # Innenseite (zur Stadtmitte) und Außenseite (zu den Werkstätten)
        yaw_in = 90 if sx < 0 else -90
        lib.sign(m, inner, (30, 3.2), CF.at(x - sx * 1.1, 20, 0, yaw_in), AMBER, SLATE, name="Torschild")
        lib.sign(m, outer, (30, 3.2), CF.at(x + sx * 1.1, 20, 0, -yaw_in), AMBER, SLATE, name="Torschild")


# ---------------------------------------------------------------- Ampeln (§3.6)
def _signal_mast(parent, lib, name, x, z, group, serves, arm_dir, face_yaw, ped_yaw, vehicle=True, arm=True):
    """Mast mit Fahrzeugkopf (Red/Amber/Green) und Fußgängerkopf (PedRed/PedGreen)."""
    m = lib.model(parent, name, attrs={"Anim": "signal", "Group": group, "Serves": serves})
    y = Y_WALK
    lib.box(m, "Sockel", x - 0.6, x + 0.6, y, y + 0.6, z - 0.6, z + 0.6, BLACK, "Metal")
    lib.cylinder(m, "Mast", (x, y + 0.6 + 3.5, z), 7, 0.4, "Y", STEEL, "Metal")
    top = y + 0.6 + 7
    hx, hz = x, z
    if arm:
        hx, hz = x + arm_dir[0] * 6, z + arm_dir[1] * 6
        lib.beam(m, "Ausleger", (x, top - 0.3, z), (hx, top - 0.3, hz), 0.3, STEEL, "Metal", deco=True)
    if vehicle:
        hy = top - 2.2 if arm else top - 1.8
        head_cf = CF.at(hx, hy, hz, face_yaw)
        lib.part(m, "Signalkopf", (1.1, 3.2, 0.8), head_cf, BLACK, "SmoothPlastic", deco=True)
        for i, (nm, col, tr) in enumerate((("Red", (255, 50, 40), 0), ("Amber", (255, 170, 30), 0.7),
                                            ("Green", (60, 230, 90), 0.7))):
            lib.cylinder(m, nm, head_cf.point((0, 1.0 - i * 1.0, 0.45)), 0.12, 0.75, "Z", col, "Neon",
                         yaw=face_yaw, transparency=tr, deco=True)
    ped_cf = CF.at(x, y + 0.6 + 3.4, z, ped_yaw) * CF(0, 0, 0.45)
    lib.part(m, "PedRed", (0.7, 0.7, 0.25), ped_cf * CF(0, 0.4, 0), (255, 60, 50), "Neon", deco=True)
    lib.part(m, "PedGreen", (0.7, 0.7, 0.25), ped_cf * CF(0, -0.4, 0), (60, 230, 90), "Neon", transparency=0.7,
             deco=True)
    return m


def build_signals(animated, lib):
    sf = lib.folder(animated, "Ampeln")
    for group, cx in (("K-West", -152), ("K-Ost", 152)):
        # NW: Ausleger +X, Kopf nach Norden (Markt südwärts); SE: Ausleger -X, Kopf nach Süden (Markt nordwärts)
        # SW: Ausleger -Z, Kopf nach Westen (Meile ostwärts); NE: Ausleger +Z, Kopf nach Osten (Meile westwärts)
        _signal_mast(sf, lib, group + " NW", cx - 20, -20, group, "Markt", (1, 0), 180, 180)
        _signal_mast(sf, lib, group + " SO", cx + 20, 20, group, "Markt", (-1, 0), 0, 0)
        _signal_mast(sf, lib, group + " SW", cx - 20, 20, group, "Meile", (0, -1), -90, 0)
        _signal_mast(sf, lib, group + " NO", cx + 20, -20, group, "Meile", (0, 1), 90, 180)
    # Plaza (Z1): Fußgängermasten mit Meile-Fahrzeugköpfen (ohne Ausleger)
    for x, z in ((-9, -19), (9, -19), (-9, 19), (9, 19)):
        _signal_mast(sf, lib, "Plaza %s%s" % ("N" if z < 0 else "S", "W" if x < 0 else "O"), x, z, "Plaza", "Meile",
                     (0, 0), 90 if z < 0 else -90, 180 if z < 0 else 0, vehicle=True, arm=False)
    # Querachse: reine Fußgängermasten (W-Mast 4 nördlich verschoben, weil (-171,-193) im Schrott-Tor liegt)
    for nm, x, z, py in (("Querachse W1", -133, -209, 90), ("Querachse W2", -171, -189, -90),
                         ("Querachse O1", 133, -209, -90), ("Querachse O2", 171, -193, 90)):
        _signal_mast(sf, lib, nm, x, z, nm[:-1].replace(" ", "-"), "Fussgaenger", (0, 0), 0, py, vehicle=False,
                     arm=False)


# ---------------------------------------------------------------- Verkehr (§3.7)
def build_loops(animated, lib):
    lf = lib.folder(animated, "TrafficLoops")
    out = {}
    for key, title, pts, speed in traffic_loops():
        f = lib.folder(lf, "Loop_" + key)
        set_attrs(f, {"Title": title, "Speed": speed, "Waypoints": len(pts)})
        for i, (x, z) in enumerate(pts):
            lib.part(f, "WP%d" % (i + 1), (0.5, 0.5, 0.5), CF(x, Y_ROAD, z), AMBER, "SmoothPlastic",
                     transparency=1, deco=True)
        out[key] = (f, pts, speed)
    return out


TRAFFIC_CARS = [("A", "hot_hatch", (200, 50, 50), 0.05), ("A", "sedan", (235, 238, 240), 0.55),
                ("B1", "compact", (38, 78, 140), 0.3), ("B2", "wagon", (170, 176, 180), 0.7),
                ("T", "gt_coupe", (247, 176, 63), 0.1)]


def build_traffic_cars(animated, lib, loops):
    tf = lib.folder(animated, "Verkehr")
    for i, (key, body, color, phase) in enumerate(TRAFFIC_CARS):
        f, pts, speed = loops[key]
        (x, z), (dx, dz), total = path_point(pts, 0)
        (x, z), (dx, dz), total = path_point(pts, phase * total)
        cf = CF.at(x, Y_ROAD, z, yaw_towards(dx, dz))
        lib.clone_car(tf, body, cf, color, name="Verkehr_%s_%d" % (key, i + 1),
                      attrs={"Anim": "traffic", "Loop": key, "Path": "Loop_" + key, "Speed": speed,
                             "Phase": phase})
