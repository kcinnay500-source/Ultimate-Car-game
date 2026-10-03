"""Boden, Rand, Straßen, Markierungen, Zebrastreifen, Kreisel, Laternen, Ampeln und Verkehrsschleifen
(CITY_SPEC §1.2, §2, §3, §6 "Spielermeile dressing" (Tore, Kreisel-Skulpturen), §9.1).

Höhen-Stapel (§1.2, nie zwei überlappende Oberseiten auf gleicher Höhe):
  Gras-Platte -1.10 | Bodenplatten -1.00 | Kreiselscheibe -1.00 (Spec -0.98; 0.05 unter der Fahrbahn, die über
  ihr endet) | Fahrbahn -0.95 | Markierungen -0.90 | Gehwege/Platz -0.50 (auch der Kreisel-Gehwegring: Trapez-Sektoren
  ohne Überlappung) | Inselgras -0.45
"""
import math

from .lib import (CF, AMBER, APRON, ASPHALT, BLACK, GRASS, HEDGE, PLAZA, RED, SIDEWALK, SLATE, STEEL, TEAL,
                  WHITE, Vec3, is_basepart, name_of, set_attrs, yaw_towards)

Y_GRASS = -1.10
Y_GROUND = -1.00
Y_DISC = -1.00
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
    ("Spielermeile West", -484, -175, -13, 13),
    ("Spielermeile Mitte", -129, 129, -13, 13),
    ("Spielermeile Ost", 175, 484, -13, 13),
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
    ("Meile Nord West", -484, -175, -23, -13), ("Meile Nord Mitte", -129, 129, -23, -13),
    ("Meile Nord Ost", 175, 484, -23, -13),
    ("Meile Sued West", -484, -175, 13, 23), ("Meile Sued Mitte", -129, 129, 13, 23),
    ("Meile Sued Ost", 175, 484, 13, 23),
    ("Markt West W Nord", -174, -165, -320, -23), ("Markt West W Sued", -174, -165, 23, 178),
    ("Markt West O Nord", -139, -130, -320, -23), ("Markt West O Sued", -139, -130, 23, 178),
    ("Markt Ost W Nord", 130, 139, -320, -23), ("Markt Ost W Sued", 130, 139, 23, 178),
    ("Markt Ost O Nord", 165, 174, -320, -23), ("Markt Ost O Sued", 165, 174, 23, 178),
    ("Nordring N", -130, 130, -364, -355), ("Nordring S", -130, 130, -329, -320),
    ("Suedring N", -130, 130, 178, 187), ("Suedring S", -130, 130, 213, 222),
]

# Aussparungen in den Bezirks-Bodenplatten (x0,x1,z0,z1): dort liegt ein eigener Belag mit Oberseite -1.00
GROUND_INSETS = {
    "Autohaus-Gelaende": [(-126, -68, 30, 150)],          # Gebrauchtwagen-Belag (dealer_track)
    "Tuning-Gelaende": [(350, 450, -300, -190)],          # Treffbelag (tuning)
    "Schrottplatz-Boden": [(-310, -178, -209, -193)],     # Betonzufahrt (scrapyard)
}

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
LAMP_CLEAR = 2.0      # Abstand Mastmitte - Rand einer Bordsteinabsenkung (Sockel 1.2 breit + Luft)


def _cut_rects():
    return [c[1:5] for c in CURB_CUTS + plot_cuts()]


def off_cuts_x(x, z, clear=LAMP_CLEAR, rects=None):
    """X eines Gehweg-Objekts so verschieben, dass es neben jeder Bordsteinabsenkung steht (§9.1: 0 Laternen in
    Einfahrten). Liegt (x, z) in einer Absenkung, rückt es auf die nähere Seite (x0 - clear | x1 + clear)."""
    rects = _cut_rects() if rects is None else rects
    for _ in range(4):
        hit = next((r for r in rects if r[0] - clear < x < r[1] + clear and r[2] - clear < z < r[3] + clear), None)
        if hit is None:
            return x
        lo, hi = hit[0] - clear, hit[1] + clear
        dl, dh = abs(x - lo), abs(x - hi)
        # bei Gleichstand nach außen (weg von X 0), damit die Stadt symmetrisch bleibt
        x = lo if dl < dh - 1e-9 or (abs(dl - dh) <= 1e-9 and x < 0) else hi
    return x


def street_lamps():
    out = []
    rects = _cut_rects()
    meile = [(306, -14.5), (-306, 14.5), (-310, -14.5), (310, 14.5), (336, -14.5), (456, -14.5), (-336, 14.5),
             (-456, 14.5), (-460, -14.5), (-340, -14.5), (460, 14.5), (340, 14.5), (-100, -14.5), (-100, 14.5),
             (-20, 14.5), (-20, -14.5), (20, -14.5), (20, 14.5), (100, 14.5), (100, -14.5)]
    for x, z in meile:
        # (100, 14.5) läge in der Absenkung Übergabe-Halle (X 92..108) -> X 110
        out.append(("Meile", off_cuts_x(x, z, rects=rects), z, 0, 1 if z < 0 else -1))
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
            if sg > 0 and z == 175:
                z = 180          # nicht in der Tankstellen-Einfahrt (Bordsteinabsenkung Z 164..176)
            dx = -1 if x in (-137.5, 166.5) else 1
            out.append(("Markt" + ("W" if sg < 0 else "O"), x, z, dx, 0))
    for x in (-100, -35, 35, 100):
        # X -100 läge in der Parkplatz-Einfahrt (X -110..-90) -> -112; Südring X 100 in der Absenkung
        # Autohaus hinten (X 92..108) -> 110
        out.append(("Nordring", off_cuts_x(x, -327.5, rects=rects), -327.5, 0, -1))
        out.append(("Suedring", off_cuts_x(x, 185.5, rects=rects), 185.5, 0, 1))
    for grp, x, z, dx, dz in out:
        assert not any(r[0] - 0.6 < x < r[1] + 0.6 and r[2] - 0.6 < z < r[3] + 0.6 for r in rects), \
            "Laterne %s (%g,%g) in einer Bordsteinabsenkung" % (grp, x, z)
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
    # 3.0: keine Verkehrsschleife mehr auf der Teststrecke: die Verkehrsautos haben lokal eine feste Kollisionsbox,
    # und ein schnelleres Zeitfahr-Auto würde von hinten auf sie auffahren (checks.vehicle_checks prüft, dass keine
    # Schleife die Streckenfläche berührt)
    return [("A", "Meile-Schleife", A, 26), ("B1", "Innenstadtring innen", B1, 24),
            ("B2", "Innenstadtring aussen", B2, 24)]


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


# ---------------------------------------------------------------- Polygon-Helfer (Kreisel-Sektoren)
def _clip_half(poly, f):
    """Konvexes Polygon auf die Halbebene f(p) >= 0 beschneiden"""
    out = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        fp, fq = f(p), f(q)
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    # doppelte Punkte entfernen
    res = []
    for p in out:
        if not res or math.dist(p, res[-1]) > 1e-6:
            res.append(p)
    if len(res) > 1 and math.dist(res[0], res[-1]) <= 1e-6:
        res.pop()
    return res


def _poly_area(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))) / 2


def _ccw(poly):
    a = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
            for i in range(len(poly)))
    return poly if a > 0 else list(reversed(poly))


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
            lib.street_lamp(lamps, x, z, Y_WALK, dx, dz, name="Laterne_" + grp)
    with lib.section("Ampeln"):
        build_signals(animated, lib)
    with lib.section("Verkehr (Wegpunkte)"):
        loops = build_loops(animated, lib)
    with lib.section("Verkehr (Lite-Autos + Bus)"):
        build_traffic_cars(animated, lib, loops)


def build_ground(ground, lib):
    # 3.0: Grasplatte bis unter den natürlichen Rand (Hügelring horizon.CREST, Teststrecke bis Z 560, Große
    # Werkstatt bis X -647); der alte Heckenring X ±590 / Z -390..470 mit unsichtbarer Grenze entfällt - den Rand
    # bilden jetzt Hügel, Felsen und Bäume (border_trees -> horizon.build_edge), dahinter Fernboden und Skyline.
    from .horizon import GROUND
    gx0, gx1, gz0, gz1 = GROUND
    lib.box(ground, "Grasplatte", gx0, gx1, Y_GRASS - 4, Y_GRASS, gz0, gz1, GRASS, "Grass")
    # Bodenplatten der Bezirke (0,3 dick, Oberseite -1.00). Flächen mit eigenem Belag (GROUND_INSETS) werden
    # ausgespart; die Bezirke setzen ihren Belag bündig (-1.30..-1.00) in die Lücke statt 0.02-0.03 darüber.
    y0, y1 = Y_GROUND - 0.3, Y_GROUND
    for nm, x0, x1, z0, z1, col, mat in (
            ("Schrottplatz-Boden", -468, -178, -364, -159, DIRT, "Pebble"),
            ("Tuning-Gelaende", 178, 468, -364, -159, TUNING_GROUND, "Concrete"),
            ("Tankstellen-Gelaende", 178, 400, 159, 260, APRON, "Concrete"),
            ("Autohaus-Gelaende", -130, 130, 23, 178, APRON, "Concrete"),
            ("Parkplatz-Chaos-Flaeche", -130, 130, -320, -229, ASPHALT, "Asphalt")):
        for p in subtract((x0, x1, z0, z1), GROUND_INSETS.get(nm, [])):
            lib.box(ground, nm, p[0], p[1], y0, y1, p[2], p[3], col, mat)
    # Altstadt-Pflaster (Stadtplatz, Frontstreifen, Querachse-Promenaden, Hallenvorfeld), Oberseite -0.50
    lib.box(ground, "Altstadt-Pflaster", -130, 130, BOTTOM, Y_WALK, -229, -23, PLAZA, "Slate")
    # Gassen-Fußwege X ±320..±326 (Schrottgasse / Tuninggasse, §4.2)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 320, sx * 326))
        lib.box(ground, "Gassenweg", x0, x1, BOTTOM, Y_WALK, -159, -23, SIDEWALK, "Concrete")
        lib.box(ground, "Gassenweg", x0, x1, BOTTOM, Y_WALK, 23, 159, SIDEWALK, "Concrete")


def border_trees(ground, lib):
    # 3.0: natürlicher Weltrand statt Randbäumen am Heckenring: Hügelkette, Felsgruppen, Baumreihen und dahinter
    # eine unsichtbare Sicherheitswand "Grenze" (horizon.py)
    from .horizon import build_edge
    return build_edge(ground, lib)


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
            rects = _cut_rects()
            for sd in (-1, 1):
                # hinter dem Band; liegt der Platz in einer Absenkung (Z15 Ost: Tankstellen-Einfahrt), vor dem Band
                for along in (hi + 1.3, lo - 1.3):
                    px, pz = (along, c + sd * 15.5) if ax == "x" else (c + sd * 15.5, along)
                    if not any(r[0] - 0.4 < px < r[1] + 0.4 and r[2] - 0.4 < pz < r[3] + 0.4 for r in rects):
                        break
                else:
                    raise SystemExit("Zebra %s: kein Platz für die Bake" % cid)
                lib.cylinder(m, "BakenMast", (px, Y_WALK + 3.25, pz), 6.5, 0.35, "Y", WHITE, "SmoothPlastic")
                lib.ball(m, "Bake", (px, Y_WALK + 7.1, pz), 1.2, AMBER, "Neon", deco=True)


def build_kreisel(roads, animated, lib):
    kf = lib.folder(roads, "Kreisel")
    for nm, cx, cz in KREISEL:
        m = lib.model(kf, nm)
        # Ø77.6: reicht bis unter die Ecken des Gehweg-Vielecks (Apothem 38, Ecken r 38.74)
        lib.cylinder(m, "Kreiselscheibe", (cx, Y_DISC - 0.15, cz), 0.3, 77.6, "Y", ASPHALT, "Asphalt")
        lib.cylinder(m, "Inselbord", (cx, (Y_DISC + Y_WALK) / 2, cz), Y_WALK - Y_DISC, 25, "Y", SIDEWALK, "Concrete")
        lib.cylinder(m, "Inselgras", (cx, (Y_DISC - 0.45) / 2, cz), -0.45 - Y_DISC, 23, "Y", GRASS, "Grass")
        # Gehwegring r 38..46 (Apothemen): 16 Trapez-Sektoren à 22.5°, die 2 an der Meile-Mündung fehlen. Jeder
        # Sektor = Quader (innere Sehnenbreite) + 2 Keile für die äußere Aufweitung -> keine Überlappung, alle
        # Oberseiten -0.50. Die beiden Sektoren neben der Mündung werden am Meile-Gehweg (endet bei X ±484)
        # abgeschnitten (konvexe Teilstücke).
        mouth = 180 if cx > 0 else 0
        half = math.radians(11.25)
        ri, ro = 38.0, 46.0
        wi, wo = ri * math.tan(half), ro * math.tan(half)
        sx = 1 if cx > 0 else -1
        xend = sx * 484
        ring_parts = []
        for k in range(16):
            a = 11.25 + 22.5 * k
            dm = abs((a - mouth + 180) % 360 - 180)
            if dm < 22.5:
                continue
            r = math.radians(a)
            ux, uz = math.cos(r), math.sin(r)            # radial nach außen
            tx, tz = -uz, ux                             # tangential

            def w(rad, t):
                return (cx + ux * rad + tx * t, cz + uz * rad + tz * t)
            quad = [w(ri, -wi), w(ro, -wo), w(ro, wo), w(ri, wi)]
            if dm < 45:
                # Meile-Gehweg (X bis ±484, |Z| 13..23) herausschneiden: Teil jenseits X ±484 + Teil |Z| > 23
                zs = 1 if uz > 0 else -1
                beyond = _clip_half(quad, lambda p: sx * (p[0] - xend))
                outside = _clip_half(_clip_half(quad, lambda p: -sx * (p[0] - xend)), lambda p: zs * p[1] - 23)
                for piece in (beyond, outside):
                    if len(piece) >= 3 and _poly_area(piece) > 0.05:
                        ring_parts += lib.convex_slab(m, "Ringgehweg", _ccw(piece), BOTTOM, Y_WALK, SIDEWALK,
                                                      "Concrete")
                continue
            yaw = yaw_towards(ux, uz)                    # lokales -Z zeigt radial nach außen
            ring_parts.append(lib.part(m, "Ringgehweg", (2 * wi, Y_WALK - BOTTOM, ro - ri),
                                       CF.at(cx + ux * (ri + ro) / 2, (Y_WALK + BOTTOM) / 2, cz + uz * (ri + ro) / 2,
                                             yaw), SIDEWALK, "Concrete"))
            for sgn in (-1, 1):
                ring_parts.append(lib.flat_tri(m, "Ringgehweg", w(ro, sgn * wi), w(ri, sgn * wi), w(ro, sgn * wo),
                                               BOTTOM, Y_WALK, SIDEWALK, "Concrete"))
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
    # PrimaryPart ohne Drehung (der Zylinder liegt um Z gedreht): CityClient dreht um die Hochachse des Pivots
    piv = lib.part(tt, "Pivot", (1, 0.2, 1), CF(cx, -0.2, 0), transparency=1, deco=True)
    lib.set_primary(tt, piv)
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
        inner = "SPIELERMEILE · Nr. " + ("1–4" if sx < 0 else "5–8")
        outer = "ZUM STADTPLATZ"
        # Innenseite (zur Stadtmitte) und Außenseite (zu den Werkstätten)
        yaw_in = 90 if sx < 0 else -90
        lib.sign(m, inner, (30, 3.2), CF.at(x - sx * 1.1, 20, 0, yaw_in), AMBER, SLATE, name="Torschild")
        lib.sign(m, outer, (30, 3.2), CF.at(x + sx * 1.1, 20, 0, -yaw_in), AMBER, SLATE, name="Torschild")


# ---------------------------------------------------------------- Ampeln (§3.6)
# 3.0 (Verkehr/Ampeln): Programm (CityClient.SignalState, 32 s): Meile grün 0-11,5 / gelb -14,5 / alles rot -16,
# Markt grün 16-27,5 / gelb -30,5 / alles rot -32. Fußgänger "NS" (queren die Marktstraße / Querachse) grün 0,5-10,5,
# "WE" (queren die Meile: Plaza, K-Arme West/Ost) grün 16-26.
# Jeder Mast trägt PedPhase ausdrücklich; der Fußgängerkopf blickt über "seinen" Zebrastreifen zu den Wartenden auf der
# anderen Seite (vorher zeigten die Köpfe vom Zebra weg und die Phase hing am Fahrzeugstrom des Masts -> an NW/SO
# zeigte der Kopf über die Meile "Gehen", während die Meile grün hatte). Die Querachse hat jetzt Fahrzeugköpfe
# (vorher hielten die Autos dort an einer unsichtbaren Ampel).
# (Name, x, z, Gruppe, Serves, Ausleger (dx,dz) oder None, Fahrzeugkopf-Yaw oder None, Fußgänger-Yaw, PedPhase)
# Yaw wie CF.at: lokales +Z (Linsenseite) zeigt nach (sin yaw, cos yaw): 0 Süden (+Z), 180 Norden, 90 Osten, -90 Westen
def signal_masts():
    out = []
    for group, cx in (("K-West", -152), ("K-Ost", 152)):
        # Fahrzeugköpfe: NW für die Marktstraße südwärts (Blick nach Norden), SO nordwärts, SW für die Meile
        # ostwärts (Blick nach Westen), NO westwärts. Fußgängerköpfe im Kreis: NW über den Nordarm (Blick Osten),
        # NO über den Ostarm (Blick Süden), SO über den Südarm (Blick Westen), SW über den Westarm (Blick Norden).
        out += [(group + " NW", cx - 20, -20, group, "Markt", (1, 0), 180, 90, "NS"),
                (group + " NO", cx + 20, -20, group, "Meile", (0, 1), 90, 0, "WE"),
                (group + " SO", cx + 20, 20, group, "Markt", (-1, 0), 0, -90, "NS"),
                (group + " SW", cx - 20, 20, group, "Meile", (0, -1), -90, 180, "WE")]
    # Plaza (Z1): Masten ohne Ausleger mit Meile-Fahrzeugköpfen; Fußgängerköpfe über die Meile zur Gegenseite
    for x, z in ((-9, -19), (9, -19), (-9, 19), (9, 19)):
        out.append(("Plaza %s%s" % ("N" if z < 0 else "S", "W" if x < 0 else "O"), x, z, "Plaza", "Meile", None,
                    90 if z < 0 else -90, 0 if z < 0 else 180, "WE"))
    # Querachse (Z12/Z13): Fahrzeugköpfe am Ausleger über dem Bordstein (W-Mast 4 nördlich verschoben, weil
    # (-171,-193) im Schrott-Tor liegt); Fußgängerköpfe blicken über die Fahrbahn zur Gegenseite
    for nm, x, z, arm, face, ped in (("Querachse W1", -133, -209, (-1, 0), 0, -90),
                                     ("Querachse W2", -171, -189, (1, 0), 180, 90),
                                     ("Querachse O1", 133, -209, (1, 0), 180, 90),
                                     ("Querachse O2", 171, -193, (-1, 0), 0, -90)):
        out.append((nm, x, z, nm[:-1].replace(" ", "-"), "Markt", arm, face, ped, "NS"))
    return out


def _signal_mast(parent, lib, name, x, z, group, serves, arm_dir, face_yaw, ped_yaw, ped_phase):
    """Mast mit Fahrzeugkopf (Red/Amber/Green, face_yaw None = ohne) und Fußgängerkopf (PedRed/PedGreen)."""
    m = lib.model(parent, name, attrs={"Anim": "signal", "Group": group, "Serves": serves, "PedPhase": ped_phase})
    y = Y_WALK
    lib.box(m, "Sockel", x - 0.6, x + 0.6, y, y + 0.6, z - 0.6, z + 0.6, BLACK, "Metal")
    lib.cylinder(m, "Mast", (x, y + 0.6 + 3.5, z), 7, 0.4, "Y", STEEL, "Metal")
    top = y + 0.6 + 7
    hx, hz = x, z
    if arm_dir:
        hx, hz = x + arm_dir[0] * 6, z + arm_dir[1] * 6
        lib.beam(m, "Ausleger", (x, top - 0.3, z), (hx, top - 0.3, hz), 0.3, STEEL, "Metal", deco=True)
    if face_yaw is not None:
        # am Ausleger: Kopf-Oberkante bündig mit der Auslegerunterseite (top - 0.45), sonst schwebt er
        hy = top - 0.45 - 1.6 if arm_dir else top - 1.8
        head_cf = CF.at(hx, hy, hz, face_yaw)
        lib.part(m, "Signalkopf", (1.1, 3.2, 0.8), head_cf, BLACK, "SmoothPlastic", deco=True)
        for i, (nm, col, tr) in enumerate((("Red", (255, 50, 40), 0), ("Amber", (255, 170, 30), 0.7),
                                            ("Green", (60, 230, 90), 0.7))):
            lib.cylinder(m, nm, head_cf.point((0, 1.0 - i * 1.0, 0.45)), 0.12, 0.75, "Z", col, "Neon",
                         yaw=face_yaw, transparency=tr, deco=True)
    ped_cf = CF.at(x, y + 0.6 + 3.4, z, ped_yaw) * CF(0, 0, 0.45)
    # Gehäuse am Mast (Mast r 0.2, Gehäuse 0.2 tief -> liegt an), Lampen davor
    lib.part(m, "PedKopf", (0.9, 1.7, 0.2), ped_cf * CF(0, 0, -0.15), BLACK, "SmoothPlastic", deco=True)
    lib.part(m, "PedRed", (0.7, 0.7, 0.25), ped_cf * CF(0, 0.4, 0.075), (255, 60, 50), "Neon", deco=True)
    lib.part(m, "PedGreen", (0.7, 0.7, 0.25), ped_cf * CF(0, -0.4, 0.075), (60, 230, 90), "Neon", transparency=0.7,
             deco=True)
    return m


def build_signals(animated, lib):
    sf = lib.folder(animated, "Ampeln")
    for name, x, z, group, serves, arm, face, ped, phase in signal_masts():
        _signal_mast(sf, lib, name, x, z, group, serves, arm, face, ped, phase)
    problems = signal_coverage()
    assert not problems, "Ampeln: " + "; ".join(problems)


# ---------------------------------------------------------------- Verkehr (§3.7)
# 3.0: Haltelinien statt Haltepunkten. Attribut StopLines am Schleifen-Ordner: "x,z,Serves;…" = Punkt der Schleife
# auf der weißen Haltelinie (Linienmitte, 2,3 vor dem Zebra). CityClient hält die Fahrzeugfront STOP_MARGIN (3,5)
# davor an (vorher: feste Fahrzeugmitte 7 vor der Linie bei 16 langen Autos -> die Front stand 1 Stud ÜBER der Linie).
# Abgeleitet aus CROSSWALKS (Art "signal") und den Schleifen: jede Fahrtrichtung, die eine Haltelinie in ihrer Spur
# kreuzt, bekommt sie; Serves "Meile" für die Meile (Achse x, Z 0), sonst "Markt".
STOP_OFFSET = 2.3       # Haltelinie vor dem Zebraband (build_crosswalks)


def stop_line_specs():
    """[(Zebra-Id, Achse, Linienkoordinate, Fahrtrichtung +1/-1, Spur (lo, hi) quer, Serves)]"""
    out = []
    for cid, ax, c, lo, hi, app, kind in CROSSWALKS:
        if kind != "signal":
            continue
        serves = "Meile" if ax == "x" and c == 0 else "Markt"
        for sd in {"lo": [-1], "hi": [1], "both": [-1, 1]}[app]:
            line = (lo - STOP_OFFSET) if sd < 0 else (hi + STOP_OFFSET)
            # wie build_crosswalks: Achse x - von Westen (+X) südlich der Mitte; Achse z - von Norden (+Z) westlich
            if ax == "x":
                lane = (c + 0.3, c + 12.05) if sd < 0 else (c - 12.05, c - 0.3)
            else:
                lane = (c - 12.05, c - 0.3) if sd < 0 else (c + 0.3, c + 12.05)
            out.append((cid, ax, line, -sd, lane, serves))
    return out


def loop_stop_lines(pts):
    """Haltelinien, die die geschlossene Schleife pts in Fahrtrichtung in ihrer Spur kreuzt: [(x, z, Serves, cid)]"""
    out = []
    n = len(pts)
    for cid, ax, line, direction, lane, serves in stop_line_specs():
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            k = 0 if ax == "x" else 1                    # Koordinate längs der Fahrt
            q = 1 - k
            da = a[k] - line
            db = b[k] - line
            if (b[k] - a[k]) * direction <= 0 or da * db > 0 or da == db:
                continue
            f = da / (da - db)
            cross = a[q] + (b[q] - a[q]) * f
            if lane[0] <= cross <= lane[1]:
                p = (line, cross) if ax == "x" else (cross, line)
                out.append((round(p[0], 2), round(p[1], 2), serves, cid))
    return out


def signal_coverage():
    """Jede Haltelinie einer Ampel wird von mindestens einer Schleife befahren und hat einen Fahrzeugkopf desselben
    Stroms, der der Fahrtrichtung entgegenblickt (höchstens 45 Studs entfernt, nicht hinter der Linie)."""
    problems = []
    used = set()
    for key, title, pts, speed in traffic_loops():
        for x, z, serves, cid in loop_stop_lines(pts):
            used.add((cid, x, z))
    heads = []
    for name, x, z, group, serves, arm, face, ped, phase in signal_masts():
        if face is None:
            continue
        hx, hz = (x + arm[0] * 6, z + arm[1] * 6) if arm else (x, z)
        heads.append((name, hx, hz, serves, math.sin(math.radians(face)), math.cos(math.radians(face))))
    specs = stop_line_specs()
    for cid, ax, line, direction, lane, serves in specs:
        mid = (lane[0] + lane[1]) / 2
        px, pz = (line, mid) if ax == "x" else (mid, line)
        tx, tz = (direction, 0) if ax == "x" else (0, direction)
        if not any(u[0] == cid and abs((u[1] if ax == "x" else u[2]) - line) < 0.01 for u in used):
            problems.append("Haltelinie %s %s=%g wird von keiner Verkehrsschleife befahren" % (cid, ax, line))
        ok = False
        for name, hx, hz, hs, fx, fz in heads:
            if hs != serves or fx * tx + fz * tz > -0.9:
                continue
            if math.hypot(hx - px, hz - pz) <= 45 and (hx - px) * tx + (hz - pz) * tz > -1:
                ok = True
                break
        if not ok:
            problems.append("Haltelinie %s %s=%g (%s) ohne Fahrzeugkopf" % (cid, ax, line, serves))
    return problems


def build_loops(animated, lib):
    # 3.0: Wegpunkte als String-Attribut Waypoints ("x,y,z;…", CityClient-Vertrag) statt 0,5er-Parts WP1..n
    # (spart ~110 Parts für Querachsen-Fahrzeugköpfe und die längere Teststrecke)
    lf = lib.folder(animated, "TrafficLoops")
    out = {}
    for key, title, pts, speed in traffic_loops():
        f = lib.folder(lf, "Loop_" + key)
        attrs = {"Title": title, "Speed": speed, "Waypoints": ";".join("%.3f,%.2f,%.3f" % (x, Y_ROAD, z)
                                                                       for x, z in pts)}
        stops = loop_stop_lines(pts)
        if stops:
            attrs["StopLines"] = ";".join("%.2f,%.2f,%s" % (x, z, serves) for x, z, serves, cid in stops)
        set_attrs(f, attrs)
        out[key] = (f, pts, speed)
    return out


# Verkehr §3.7: "Lite"-Autos (~35 Parts, aus den CarTemplates abgeleitet) 6 / 3 / 3 / 2 je Schleife mit gleichmäßig
# verteilter Phase, dazu 1 Bus (Schleife A, 6 s Halt an der Haltestelle "Markt"). CityClient bewegt sie lokal
# (kinematisch: Anfahren, Bremsweg, Abstand, Kurven, Ampeln, Spieler) und gibt jedem Auto eine unsichtbare
# Kollisionsbox (CanCollide), damit niemand durch Autos läuft.
TRAFFIC = {
    "A": [("hot_hatch", (200, 50, 50)), ("sedan", (235, 238, 240)), ("compact", (38, 78, 140)),
          ("wagon", (170, 176, 180)), ("crossover", (40, 110, 200)), ("electric", (47, 169, 163))],
    "B1": [("compact", (240, 190, 40)), ("sedan", (60, 64, 70)), ("hot_hatch", (235, 238, 240))],
    "B2": [("wagon", (110, 30, 40)), ("crossover", (224, 214, 190)), ("electric", (135, 75, 196))],
}
PHASE0 = {"A": 0.03, "B1": 0.11, "B2": 0.21}
BUS_PHASE = 0.03 + 0.5 / 6          # auf Schleife A genau zwischen zwei Autos
# Haltestelle "Markt" (Buchten Nord X 74..86 / Süd X -86..-74): westwärts auf Z -6.5 bei X 80, ostwärts auf Z 6.5
# bei X -80 (vor den Wartehäuschen (80,-20) / (-80,20))
BUS_STOPS = [(80, -6.5), (-80, 6.5)]
BUS_LEN = 24


def car_dims(lib, template):
    """(Front, Heck, Breite) der Lite-Teile einer Vorlage, gemessen ab dem Pivot (Root, Nase lokal -Z)"""
    from .lib import aabb
    src = lib.templates()[template]
    bb = [aabb(it) for it in src.iter("Item") if is_basepart(it)
          and (name_of(it) in lib.LITE_KEEP or name_of(it).endswith("Tire"))]
    return (round(-min(b[4] for b in bb), 2), round(max(b[5] for b in bb), 2),
            round(max(b[1] for b in bb) - min(b[0] for b in bb), 2))


def build_traffic_cars(animated, lib, loops):
    tf = lib.folder(animated, "Verkehr")
    n = 0
    for key, cars in TRAFFIC.items():
        f, pts, speed = loops[key]
        for k, (body, color) in enumerate(cars):
            n += 1
            phase = round((PHASE0[key] + k / len(cars)) % 1.0, 4)
            (x, z), (dx, dz), total = path_point(pts, phase * path_point(pts, 0)[2])
            cf = CF.at(x, Y_ROAD, z, yaw_towards(dx, dz))
            front, rear, width = car_dims(lib, body)
            lib.lite_car(tf, body, cf, color, name="Verkehr_%s_%d" % (key, n),
                         attrs={"Anim": "traffic", "Loop": key, "Path": "Loop_" + key, "Speed": speed,
                                "Phase": phase, "Length": round(front + rear, 2), "Front": front, "Rear": rear,
                                "Width": width})
    f, pts, speed = loops["A"]
    (x, z), (dx, dz), total = path_point(pts, BUS_PHASE * path_point(pts, 0)[2])
    build_bus(tf, lib, CF.at(x, Y_ROAD, z, yaw_towards(dx, dz)),
              {"Anim": "traffic", "Loop": "A", "Path": "Loop_A", "Speed": 20, "Phase": round(BUS_PHASE, 4),
               "Length": BUS_LEN + 0.8, "Front": BUS_LEN / 2 + 0.4, "Rear": BUS_LEN / 2 + 0.4, "Width": 8.3,
               "Dwell": 6, "DwellAt": ";".join("%g,%g" % p for p in BUS_STOPS), "StopName": "Markt"})


def build_bus(parent, lib, cf, attrs):
    """Stadtbus Linie A (~32 Parts), Nase lokal -Z, Räder auf lokal Y 0 (wie die CarTemplates), PrimaryPart Root."""
    m = lib.model(parent, "Bus_Linie_A", attrs=attrs)
    L = BUS_LEN / 2
    W = 4.0
    teal, cream, glass = TEAL, (236, 232, 220), (60, 86, 100)

    def b(name, x0, x1, y0, y1, z0, z1, color, material="SmoothPlastic", **kw):
        return lib.part(m, name, (x1 - x0, y1 - y0, z1 - z0), cf * CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
                        color, material, **kw)
    root = b("Root", -0.5, 0.5, 0.5, 1.5, -0.5, 0.5, SLATE, transparency=1, collide=False, touch=False,
             query=False, cast_shadow=False)
    lib.set_primary(m, root)
    b("Unterbau", -3.7, 3.7, 1.0, 2.0, -L + 0.4, L - 0.4, BLACK, "Metal")
    body = b("Karosserie", -W, W, 2.0, 5.2, -L, L, teal, "Metal")
    lib.surface_text(body, "LINIE A · MEILE-SCHLEIFE", face="Right", text_color=(255, 255, 255))
    lib.surface_text(body, "LINIE A · MEILE-SCHLEIFE", face="Left", text_color=(255, 255, 255), name="Links")
    b("Zierband", -W - 0.05, W + 0.05, 4.6, 5.0, -L - 0.05, L + 0.05, AMBER, "SmoothPlastic", collide=False)
    b("Fensterband", -W + 0.1, W - 0.1, 5.2, 8.6, -L + 1.6, L - 1.2, glass, "Glass", transparency=0.3)
    for z in (-L + 5.5, -L + 10.0, -L + 14.5, -L + 19.0):
        b("Fensterpfosten", -W, W, 5.2, 8.6, z - 0.25, z + 0.25, BLACK, "Metal")
    b("Frontkappe", -W, W, 5.2, 8.6, -L, -L + 1.6, teal, "Metal")
    b("Heckkappe", -W, W, 5.2, 8.6, L - 1.2, L, teal, "Metal")
    b("Dach", -W, W, 8.6, 9.4, -L, L, cream, "SmoothPlastic")
    b("Klimaanlage", -2.4, 2.4, 9.4, 10.2, 1.0, 7.0, STEEL, "Metal")
    b("Frontscheibe", -3.6, 3.6, 4.9, 8.3, -L - 0.12, -L, glass, "Glass", transparency=0.2)
    sign = b("Zielanzeige", -2.8, 2.8, 8.65, 9.3, -L - 0.12, -L, BLACK, "SmoothPlastic")
    lib.surface_text(sign, "A  MARKT · MEILE", face="Front", text_color=AMBER)
    b("Heckscheibe", -3.0, 3.0, 5.8, 8.2, L, L + 0.1, glass, "Glass", transparency=0.2)
    for sx in (-1, 1):
        b("Scheinwerfer", sx * 2.2 - 0.9, sx * 2.2 + 0.9, 2.8, 3.4, -L - 0.12, -L, (226, 247, 255), "Neon")
        b("Ruecklicht", sx * 3.0 - 0.6, sx * 3.0 + 0.6, 3.0, 4.2, L, L + 0.1, (240, 78, 65), "Neon")
        b("Spiegel", sx * (W + 0.5) - 0.2, sx * (W + 0.5) + 0.2, 6.4, 7.6, -L + 0.6, -L + 1.0, BLACK, "Metal")
    b("Stossfaenger", -W, W, 1.4, 2.4, -L - 0.4, -L, BLACK, "Metal")
    b("Stossfaenger", -W, W, 1.4, 2.4, L, L + 0.4, BLACK, "Metal")
    # Türen rechts (Bordsteinseite, lokal +X)
    for z0, z1 in ((-L + 1.8, -L + 4.8), (0.5, 3.5)):
        b("Tuer", W, W + 0.08, 1.9, 8.4, z0, z1, glass, "Glass", transparency=0.15)
    # 4 Räder (Zylinder, Achse lokal X), Reifen auf Y 0
    for z in (-L + 4.0, L - 5.0):
        for sx in (-1, 1):
            lib.part(m, "Rad", (1.1, 3.0, 3.0), cf * CF(sx * (W - 0.45), 1.5, z), BLACK, "SmoothPlastic",
                     shape="Cylinder")
            lib.part(m, "Radkappe", (0.1, 1.6, 1.6), cf * CF(sx * (W + 0.15), 1.5, z), STEEL, "Metal",
                     shape="Cylinder", collide=False)
    set_attrs(m, {"Body": "bus", "Lite": True})
    return m
