"""Große Werkstatt (öffentliche Werkstatt für alle Spieler) am Westende der Spielermeile, hinter dem Kreisel West.

Gelände X -640..-500, Z -70..+70 (Hallen, Teile-Ankauf, Vorplatz X -646..-552; der Kreisel West mit Mitte X -518
belegt den Rest). Aufbau (Höhen-Stapel CITY_SPEC §1.2: Gras -1.10, Vorplatz -1.00, Fahrbahn -0.95, Markierung -0.90,
Hallenboden -0.90, Hallen-Markierung -0.85, Gehweg -0.50, Ankauf-Boden 0):
  City.Districts.Grosswerkstatt
    Vorplatz                 Betonfläche X -604..-566 (ohne Hallen-Grundriss), Parklinien, geparktes Lite-Auto,
                             Hoflaterne (1 Licht), Wegweiser-Pylon an der Zufahrt
    Zufahrt                  Fahrbahn-Stummel X -566..-552 (|Z| < 13) mit Gehwegen (|Z| 13..23) in die neue
                             Westmündung des Kreisels; Wartelinie, Rand- und Mittelmarkierung. Der Kreisel bekommt die
                             Mündung wie an der Meile-Seite: die 4 Ringgehweg-Sektoren um 180° werden ersetzt (die beiden
                             mittleren entfallen, die beiden äußeren werden an X -552 / |Z| 23 beschnitten).
    Halle                    44 x 96 x 18, Boden -0.90, 4 offene Reparatur-Hallen (Rolltore 16 x 12 hochgerollt) mit
                             Hebebühnen, Werkbank, Werkzeugwand, Rollwagen; Reifenstapel; 2 Deckenlampen (2 Lichter);
                             Schild „GROSSE WERKSTATT“ (SurfaceGui) auf dem Dach (zur Meile, +X) und Hallen-Nummern
    TeileAnkauf              Anbau 26 x 18 an der Nordseite mit Verkaufsfenster nach Osten (Theke), Schild
                             „TEILE-ANKAUF“, Regale, Lampe (1 Licht)
    Hof                      Grünfläche hinter/neben der Halle: Bäume, Reifenlager, Teilecontainer
    Einfriedung              Hecke + unsichtbare Grenze um das Gelände (Nord/West/Süd) - nur nötig, weil die
                             Stadtgrenze (Hecke X -590) das Gelände kreuzt; siehe clear_site()
  City.Animated.Grosswerkstatt.Rundumleuchte   Anim=beacon auf dem Annahme-Terminal
Stationen grosswerkstatt (Annahme-Terminal am Mittelpfeiler, Spieler östlich davor) und teileankauf (Theke) sowie
die Ankunftspunkte baut contract.py; hier bekommen die Ankunftspunkte nur ihren deutschen DisplayName (MapUI).

clear_site(): Das Gelände liegt teilweise außerhalb der bisherigen Stadtgrenze. Vor dem Bau wird es frei geräumt -
nur, was dort wirklich steht (andere Teams dürfen Grenze/Skyline verschieben, dann passiert hier nichts):
  * lange, achsparallele Grenzteile, die das Gelände in Z ganz durchqueren (Hecke, unsichtbare Grenze), werden an
    der Einfriedung aufgetrennt; die Einfriedung schließt die Lücke (gleiche Farbe/Material/Höhe/Transparenz).
  * hohe Modelle (Skyline-Türme) werden nach Norden/Süden aus dem Gelände verschoben (frei geprüft), sonst entfernt.
  * kleine Modelle (Bäume, Laternen, Findlinge) und einzelne Deko-Teile im Gelände werden entfernt.
  Nicht angefasst: Straßen/Kreisel (eigene Mündungslogik), Stationen, Ankunftspunkte, Verkehr, Bodenplatten
  (Oberseite <= -1.0, z. B. Grasplatte).
"""
import copy
import math

from ..lib import (CF, AMBER, APRON, ASPHALT, BLACK, GLASS, GRAPHITE, GRASS, HEDGE, LAMP, SIDEWALK, SLATE, STEEL,
                   TEAL, WHITE, children, child, get_attrs, is_basepart, name_of, read_cf, read_size, set_attrs,
                   write_cf, write_size, aabb)
from .. import ground_roads as GR

NAME = "Grosswerkstatt"
BUDGET = (900, 4)                 # Parts, Lichter (Vorgabe: < 900 Parts, <= 4 Lichter)

SITE = (-640.0, -500.0, -70.0, 70.0)
Y_GRASS = -1.10
Y_APRON = -1.00
Y_ROAD = -0.95
Y_MARK = -0.90
Y_WALK = -0.50
BOTTOM = -1.25
Y_FLOOR = -0.90                   # Hallenboden (0,1 über dem Vorplatz: befahrbar)

HALL = (-640.0, -596.0, -48.0, 48.0)          # x0, x1, z0, z1
HALL_H = 18.0
WALL = 1.0
BAYS = [-36.0, -12.0, 12.0, 36.0]             # Mitte jeder Halle (Z)
DOOR_W = 16.0
DOOR_H = 12.0
CAR_X = -620.0                                # Auto-Mitte in der Halle

ANNEX = (-630.0, -604.0, -66.0, -48.0)        # Teile-Ankauf
ANNEX_H = 8.0
WINDOW = (-62.0, -54.0)                       # Verkaufsfenster (Z) in der Ostwand
APRON_RECT = (-604.0, -566.0, -66.0, 66.0)    # Vorplatz (ohne Hallen-Grundriss)
STUB = (-566.0, -552.0)                       # Zufahrt X (Kreisel-Mündung bei X -552 = Mitte - 34)

# Einfriedung: Mittellinien (Nord/Süd Z, West X)
FENCE_Z = 71.5
FENCE_X = -643.5
CLEAR = (-647.0, -566.0, -75.0, 75.0)         # geräumter Bereich (Gelände + Einfriedung)

CREAM = (224, 214, 190)
EPOXY = (88, 96, 104)
PEG = (58, 66, 74)
TOOLRED = (190, 52, 46)
YELLOW = (240, 196, 48)
CONTAINER = (46, 110, 150)

ARRIVAL_NAMES = {"grosswerkstatt": "Große Werkstatt", "teileankauf": "Große Werkstatt · Teile-Ankauf"}


def build(city, lib, tree):
    districts = lib.folder(city, "Districts")
    anim_root = lib.folder(city, "Animated")
    with lib.section("D15 Große Werkstatt (Räumen)"):
        log = clear_site(city, lib)
    with lib.section("D15 Große Werkstatt"):
        dm = lib.model(districts, NAME, attrs={"District": "D15", "Title": "Große Werkstatt"})
        an = lib.model(anim_root, NAME)
        build_apron(dm, lib)
        mouth = build_access(city, dm, lib)
        build_hall(dm, an, lib)
        build_annex(dm, lib)
        build_yard(dm, lib)
        build_fence(dm, lib, log["splits"])
        name_arrivals(city)
    set_attrs(dm, {"KreiselMuendung": bool(mouth), "Geraeumt": len(log["removed"]), "Verschoben": len(log["moved"]),
                   "Getrennt": len(log["splits"])})
    return dm


# ---------------------------------------------------------------- Gelände räumen
def _parents(root):
    par = {}
    for it in root.iter("Item"):
        for c in it.findall("Item"):
            par[c] = it
    return par


def _path(item, par):
    names = []
    cur = item
    while cur is not None and cur.get("class") != "Workspace":
        names.append(name_of(cur) or "")
        cur = par.get(cur)
    return ".".join(reversed(names))


def _hits(b, rect):
    x0, x1, z0, z1 = rect
    return b[1] > x0 and b[0] < x1 and b[5] > z0 and b[4] < z1


def _is_axis(item):
    cf = read_cf(item)
    if cf is None:
        return False
    R = cf.R
    return all(abs(R[i][j] - (1.0 if i == j else 0.0)) < 1e-6 for i in range(3) for j in range(3))


def _model_aabb(item):
    lo = [1e18, 1e18, 1e18]
    hi = [-1e18, -1e18, -1e18]
    n = 0
    for it in item.iter("Item"):
        if is_basepart(it):
            b = aabb(it)
            for k in range(3):
                lo[k] = min(lo[k], b[2 * k])
                hi[k] = max(hi[k], b[2 * k + 1])
            n += 1
    return (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]), n


PROTECTED = ("City.Roads", "City.Stations", "City.Arrivals", "City.Animated.TrafficLoops", "City.Animated.Verkehr",
             "City.Missions", "City.CarSpawns", "City.Track", "City.PlotSlots", "City.CitySpawn",
             "City.Districts." + NAME, "City.Animated." + NAME)


def clear_site(city, lib):
    """Räumt CLEAR frei (siehe Modul-Doku). Rückgabe {removed, moved, splits}; splits = [(xc, w, y0, y1, Vorlage)]."""
    log = {"removed": [], "moved": [], "splits": []}
    ws_root = lib.root
    par = _parents(ws_root)
    candidates = []
    for it in city.iter("Item"):
        if not is_basepart(it):
            continue
        b = aabb(it)
        if not _hits(b, CLEAR) or b[3] <= Y_APRON + 1e-6:
            continue                # außerhalb oder Bodenplatte (Grasplatte, Bezirksplatten)
        if (b[1] - b[0]) * (b[5] - b[4]) > 40000:
            continue                # riesige Bodenteile
        path = _path(it, par)
        if path.startswith(PROTECTED):
            continue
        candidates.append((it, b, path))
    done = set()
    for it, b, path in candidates:
        if id(it) in done:
            continue
        # 1) Grenzteil, das das Gelände in Z ganz durchquert: auftrennen
        if b[4] < CLEAR[2] and b[5] > CLEAR[3] and (b[1] - b[0]) <= 12 and _is_axis(it):
            split_part(it, b, par[it], lib, log)
            done.add(id(it))
            continue
        # 2) Einheit bestimmen: direktes Eltern-Model (Baum, Turm, Laterne), sonst das Teil selbst
        parent = par.get(it)
        unit = it
        if parent is not None and parent.get("class") == "Model" and name_of(par.get(parent)) != "Districts":
            mb, n = _model_aabb(parent)
            if n <= 60:
                unit = parent
        if unit is not it:
            for x in unit.iter("Item"):
                done.add(id(x))
        else:
            done.add(id(it))
        ub, _ = _model_aabb(unit) if unit is not it else (b, 1)
        if ub[3] - ub[2] > 30 and move_out(unit, ub, city, lib, par):
            log["moved"].append(_path(unit, par))
            continue
        log["removed"].append(_path(unit, par))
        par[unit].remove(unit)
    return log


def split_part(it, b, parent, lib, log):
    """Achsparalleles Grenzteil in einen Nord- und einen Südteil außerhalb der Einfriedung trennen."""
    x0, x1, y0, y1, z0, z1 = b
    w = x1 - x0
    xc = (x0 + x1) / 2
    cut_n = -FENCE_Z + w / 2          # Nordteil endet hier (Ecke gehört zum Grenzteil)
    cut_s = FENCE_Z - w / 2
    south = copy.deepcopy(it)
    for x in south.iter("Item"):
        x.set("referent", lib.ref())
    parent.append(south)
    cf = read_cf(it)
    for item, a, c in ((it, z0, cut_n), (south, cut_s, z1)):
        size = read_size(item)
        write_size(item, (size[0], size[1], c - a))
        write_cf(item, CF(cf.p[0], cf.p[1], (a + c) / 2, cf.R))
    log["splits"].append((xc, w, y0, y1, it))


def move_out(unit, ub, city, lib, par):
    """Hohes Modell (Skyline) aus dem Gelände nach Norden/Süden schieben, wenn dort frei ist."""
    zc = (ub[4] + ub[5]) / 2
    sign = -1 if zc <= 0 else 1
    others = []
    for it in city.iter("Item"):
        if is_basepart(it):
            b = aabb(it)
            if b[3] > Y_APRON + 1e-6 and (b[1] - b[0]) * (b[5] - b[4]) <= 40000:
                others.append((it, b))
    mine = {id(x) for x in unit.iter("Item")}
    del par
    for step in range(6):
        edge = FENCE_Z + 12 + step * 20
        dz = (-edge - ub[5]) if sign < 0 else (edge - ub[4])
        nb = (ub[0] - 1, ub[1] + 1, ub[4] + dz - 1, ub[5] + dz + 1)
        if all(id(o) in mine or not _hits(b, nb) for o, b in others):
            for x in unit.iter("Item"):
                if is_basepart(x):
                    cf = read_cf(x)
                    write_cf(x, CF(cf.p[0], cf.p[1], cf.p[2] + dz, cf.R))
            return True
    return False


# ---------------------------------------------------------------- Vorplatz
def build_apron(dm, lib):
    m = lib.model(dm, "Vorplatz")
    x0, x1, z0, z1 = APRON_RECT
    hall = (HALL[0], HALL[1], HALL[2], HALL[3])
    annex = (ANNEX[0], ANNEX[1], ANNEX[2], ANNEX[3])
    for p in GR.subtract((x0, x1, z0, z1), [hall, annex]):
        lib.box(m, "Vorplatz", p[0], p[1], Y_APRON - 0.3, Y_APRON, p[2], p[3], APRON, "Concrete")
    # Parklinien (Süd: 3 Stellplätze, Nord: 2), Nase zur Halle; 0,05 auf dem Beton
    y0, y1 = Y_APRON, Y_APRON + 0.05
    for zs, xs in ((1, (-603.0, -592.0, -581.0)), (-1, (-589.0, -578.0))):
        zz0, zz1 = (52.0, 65.0) if zs > 0 else (-65.0, -52.0)
        for k, xa in enumerate(xs + (xs[-1] + 11.0,)):
            lib.box(m, "Parklinie", xa - 0.2, xa + 0.2, y0, y1, zz0, zz1, WHITE, "SmoothPlastic", deco=True)
    # Spur zu den Hallen: Pfeil-Streifen vor jedem Tor
    for zc in BAYS:
        lib.box(m, "Torpfeil", -594.0, -586.0, y0, y1, zc - 0.3, zc + 0.3, AMBER, "SmoothPlastic", deco=True)
    # geparktes Lite-Auto (Süden, Nase zur Halle = Süden ... hier Nase nach Norden aus dem Stellplatz)
    lib.lite_car(m, "sedan", CF.at(-586.5, Y_APRON, 58.0, 0), (60, 110, 170), name="Kundenauto",
                 attrs={"Display": "Grosswerkstatt"})
    # Hoflaterne am Vorplatz (1 Licht), Ausleger zur Halle
    lib.street_lamp(m, -570.0, -30.0, Y_APRON, -1, 0, name="Hoflaterne", range_=34, brightness=0.9)
    return m


# ---------------------------------------------------------------- Zufahrt + Kreisel-Mündung
def _kreisel_center():
    for nm, cx, cz in GR.KREISEL:
        if nm == "Kreisel West":
            return cx, cz
    return -518.0, 0.0


def _sector(cx, cz, k, ri=38.0, ro=46.0):
    a = 11.25 + 22.5 * k
    r = math.radians(a)
    ux, uz = math.cos(r), math.sin(r)
    tx, tz = -uz, ux
    half = math.radians(11.25)
    wi, wo = ri * math.tan(half), ro * math.tan(half)

    def w(rad, t):
        return (cx + ux * rad + tx * t, cz + uz * rad + tz * t)
    quad = [w(ri, -wi), w(ro, -wo), w(ro, wo), w(ri, wi)]
    rm = (ri + ro) / 2
    centers = [(cx + ux * rm, cz + uz * rm)]
    for sgn in (-1, 1):
        a3, b3 = w(ri, sgn * wi), w(ro, sgn * wo)
        centers.append(((a3[0] + b3[0]) / 2, (a3[1] + b3[1]) / 2))
    return quad, centers, uz


def build_access(city, dm, lib):
    """Zufahrt X -566..-552 und neue Westmündung des Kreisels. Rückgabe True, wenn die Mündung gebaut wurde."""
    m = lib.model(dm, "Zufahrt")
    cx, cz = _kreisel_center()
    xend = cx - 34.0
    roads = child(city, "Roads")
    kf = child(roads, "Kreisel") if roads is not None else None
    kw = child(kf, "Kreisel West") if kf is not None else None
    found = []
    sectors = [_sector(cx, cz, k) for k in (6, 7, 8, 9)]
    if kw is not None:
        # Sektor eines Ringteils: Quader über die Mitte, Keile über ihre rechtwinklige Ecke (die Keile zweier
        # Nachbarsektoren haben dieselbe Mitte, ihre rechte Ecke liegt aber im eigenen Sektor)
        wanted = []
        for quad, centers, uz in sectors:
            wanted += centers
        for it in children(kw):
            if not is_basepart(it) or name_of(it) != "Ringgehweg":
                continue
            cf = read_cf(it)
            p = cf.p
            if not any(abs(p[0] - px) < 0.02 and abs(p[2] - pz) < 0.02 for px, pz in wanted):
                continue
            q = (p[0], p[2])
            if it.get("class") == "WedgePart":
                size = read_size(it)
                up = (cf.R[0][1], cf.R[1][1], cf.R[2][1])
                back = (cf.R[0][2], cf.R[1][2], cf.R[2][2])
                q = (p[0] - up[0] * size[1] / 2 + back[0] * size[2] / 2, p[2] - up[2] * size[1] / 2 + back[2] * size[2] / 2)
            ang = math.degrees(math.atan2(q[1] - cz, q[0] - cx)) % 360.0
            if int(ang // 22.5) in (6, 7, 8, 9):
                found.append(it)
    mouth = kw is not None and len(found) == 12 and len(set(id(x) for x in found)) == 12
    x_in = xend if mouth else cx - 46.95          # ohne Mündung: bis an den Ringgehweg (Bordstein 0,45)
    lib.box(m, "Fahrbahn", STUB[0], x_in, BOTTOM, Y_ROAD, -13.0, 13.0, ASPHALT, "Asphalt")
    for zs in (-1, 1):
        za, zb = sorted((zs * 13.0, zs * 23.0))
        lib.box(m, "Gehweg", STUB[0], x_in, BOTTOM, Y_WALK, za, zb, SIDEWALK, "Concrete")
    if mouth:
        for it in found:
            kw.remove(it)
        for (quad, centers, uz), k in zip(sectors, (6, 7, 8, 9)):
            if k in (7, 8):
                continue                           # mittlere Sektoren entfallen (Fahrbahn + Gehweg liegen dort)
            zs = 1 if uz > 0 else -1
            beyond = GR._clip_half(quad, lambda p: p[0] - xend)
            outside = GR._clip_half(GR._clip_half(quad, lambda p: xend - p[0]), lambda p: zs * p[1] - 23.0)
            for piece in (beyond, outside):
                if len(piece) >= 3 and GR._poly_area(piece) > 0.05:
                    lib.convex_slab(m, "Ringgehweg", GR._ccw(piece), BOTTOM, Y_WALK, SIDEWALK, "Concrete")
    # Markierungen (nur mit Mündung): Wartelinie (Einfahrtsspur Süd, gestrichelt wie an der Meile), Randlinien,
    # Mittelstrich
    x = cx - 39.5 if mouth else STUB[0] - 100.0
    z = 0.4
    while mouth and z + 1.4 <= 12.0 + 0.01:
        lib.box(m, "Wartelinie", x - 0.3, x + 0.3, Y_ROAD, Y_MARK, z, z + 1.4, WHITE, "SmoothPlastic", deco=True)
        z += 2.9
    for side in ((-1, 1) if mouth else ()):
        e = side * (13 - 0.7)
        lib.box(m, "Randlinie", STUB[0] + 0.5, x - 1.0, Y_ROAD, Y_MARK, e - 0.2, e + 0.2, WHITE, "SmoothPlastic",
                deco=True)
    if mouth:
        lib.box(m, "Mittelstrich", STUB[0] + 1.0, STUB[0] + 6.0, Y_ROAD, Y_MARK, -0.25, 0.25, AMBER, "SmoothPlastic",
                deco=True)
    # Wegweiser-Pylon südlich der Zufahrt (auf dem Gras), Schild zur Kreisel-Seite und zur Zufahrt
    px, pz = -561.0, 33.0
    lib.box(m, "Pylon", px - 0.8, px + 0.8, Y_GRASS, Y_GRASS + 15.0, pz - 0.8, pz + 0.8, SLATE, "Metal")
    lib.sign(m, "GROSSE WERKSTATT", (9.0, 3.2), CF.at(px + 0.9, 11.0, pz, 90), AMBER, SLATE, name="Wegweiser",
             sub="Reparatur · Teile-Ankauf", sub_color=WHITE, bolts=False)
    return mouth


# ---------------------------------------------------------------- Halle
def build_hall(dm, an, lib):
    m = lib.model(dm, "Halle")
    x0, x1, z0, z1 = HALL
    h = HALL_H
    lib.box(m, "Hallenboden", x0, x1, Y_FLOOR - 0.4, Y_FLOOR, z0, z1, EPOXY, "Concrete")
    lib.box(m, "Rueckwand", x0, x0 + WALL, Y_FLOOR, h, z0, z1, CREAM, "Concrete")
    lib.box(m, "Wand_Nord", x0 + WALL, x1 - WALL, Y_FLOOR, h, z0, z0 + WALL, CREAM, "Concrete")
    lib.box(m, "Wand_Sued", x0 + WALL, x1 - WALL, Y_FLOOR, h, z1 - WALL, z1, CREAM, "Concrete")
    # Fassade: Pfeiler zwischen den Toren, Sturz darüber
    edges = [z0]
    for zc in BAYS:
        edges += [zc - DOOR_W / 2, zc + DOOR_W / 2]
    edges.append(z1)
    for k in range(0, len(edges), 2):
        lib.box(m, "Pfeiler", x1 - WALL, x1, Y_FLOOR, DOOR_H, edges[k], edges[k + 1], SLATE, "Concrete")
    lib.box(m, "Sturz", x1 - WALL, x1, DOOR_H, h, z0, z1, SLATE, "Concrete")
    lib.box(m, "Dach", x0 - 1.0, x1 + 1.0, h, h + 0.8, z0 - 1.0, z1 + 1.0, GRAPHITE, "Metal")
    lib.box(m, "Dachkante", x1 + 1.0, x1 + 1.2, h, h + 0.8, z0 - 1.0, z1 + 1.0, AMBER, "Neon", deco=True)
    # Schild auf dem Dach (zur Meile): Träger + Tafel
    for zp in (-18.0, 18.0):
        lib.box(m, "Schildtraeger", -601.0, -600.4, h + 0.8, h + 9.2, zp - 0.3, zp + 0.3, STEEL, "Metal")
    lib.sign(m, "GROSSE WERKSTATT", (52.0, 7.0), CF.at(-600.2, h + 5.0, 0.0, 90), AMBER, SLATE, name="Dachschild",
             thickness=0.4, sub="Reparieren · Teile verkaufen · für alle", sub_color=WHITE)
    for i, zc in enumerate(BAYS, start=1):
        build_bay(m, lib, i, zc)
    # Reifenstapel an den Innenseiten der Pfeiler
    for zc in (-24.0, 24.0):
        for k in range(4):
            lib.cylinder(m, "Reifen", (-599.0, Y_FLOOR + 0.45 + k * 0.9, zc), 0.9, 2.6, "Y", BLACK, "Plastic")
    # Deckenlampen (2 Lichter)
    for zc in (-24.0, 24.0):
        lamp = lib.box(m, "Deckenlampe", -626.0, -612.0, h - 0.4, h, zc - 0.6, zc + 0.6, LAMP, "Neon", deco=True)
        lib.point_light(lamp, 46, 1.2, LAMP, name="Hallenlicht")
    build_terminal(m, an, lib)
    return m


def build_bay(m, lib, i, zc):
    b = lib.model(m, "Halle_%d" % i, attrs={"Bay": i})
    x1 = HALL[1]
    # Bodenmarkierung (Seitenlinien) und Nummer über dem Tor
    for side in (-1, 1):
        zl = zc + side * 7.5
        lib.box(b, "Bodenlinie", -636.0, -600.0, Y_FLOOR, Y_FLOOR + 0.05, zl - 0.2, zl + 0.2, YELLOW, "SmoothPlastic",
                deco=True)
    lib.sign(b, str(i), (2.4, 2.4), CF.at(x1 + 0.1, 13.6, zc, 90), AMBER, SLATE, name="Hallennummer", bolts=False)
    # Rolltor (hochgerollt): Wickelwelle unter dem Sturz, Panzer-Rest, Führungsschienen
    lib.cylinder(b, "Rolltorwelle", (x1 - 1.8, DOOR_H - 0.8, zc), DOOR_W - 0.6, 1.6, "Z", (150, 156, 160), "Metal")
    lib.box(b, "Rolltor", x1 - 1.3, x1 - 1.0, DOOR_H - 2.0, DOOR_H - 0.8, zc - DOOR_W / 2 + 0.5,
            zc + DOOR_W / 2 - 0.5, (170, 176, 180), "Metal")
    for side in (-1, 1):
        za = zc + side * (DOOR_W / 2 - 0.15)
        lib.box(b, "Fuehrung", x1 - 1.6, x1 - 1.0, Y_FLOOR, DOOR_H - 0.8, za - 0.15, za + 0.15, STEEL, "Metal")
    # Hebebühne (2 Säulen, Arme): Halle 1 mit gehobenem Auto, Halle 4 mit Auto am Boden, 2 und 3 frei zum Reinfahren
    lift_y = 4.0 if i == 1 else Y_FLOOR
    for side in (-1, 1):
        zp = zc + side * 6.6
        lib.box(b, "Saeule", CAR_X - 0.6, CAR_X + 0.6, Y_FLOOR, Y_FLOOR + 10.5, zp - 0.6, zp + 0.6, (60, 120, 180),
                "Metal")
        if i == 1:
            # Tragarm von der Säule unter den Schweller (Wagenmitte zwischen den Achsen, trägt das Auto)
            za, zb = sorted((zc + side * 1.5, zp - side * 0.6))
            lib.box(b, "Tragarm", CAR_X - 0.3, CAR_X + 0.3, lift_y + 1.0, lift_y + 1.4, za, zb, BLACK, "Metal")
        else:
            # eingeklappte Arme längs an der Säule (aus der Fahrspur)
            zz = zc + side * 5.6
            lib.box(b, "Tragarm", CAR_X - 3.0, CAR_X + 3.0, Y_FLOOR, Y_FLOOR + 0.3, zz - 0.3, zz + 0.3, BLACK, "Metal")
    if i == 1:
        lib.lite_car(b, "sedan", CF.at(CAR_X, lift_y, zc, 90), (214, 160, 72), name="Auto_Buehne",
                     attrs={"Display": "Grosswerkstatt"})
    elif i == 4:
        lib.lite_car(b, "compact", CF.at(CAR_X, Y_FLOOR, zc, 90), (180, 60, 50), name="Auto_Boden",
                     attrs={"Display": "Grosswerkstatt"})
    # Werkzeugwand (Lochblech) mit Werkzeugen, Werkbank, Rollwagen
    x0 = HALL[0] + WALL
    lib.box(b, "Werkzeugwand", x0, x0 + 0.2, 3.0, 9.0, zc - 7.0, zc + 7.0, PEG, "Metal")
    tools = [((-5.0, 6.8), (0.3, 3.2)), ((-3.0, 6.4), (0.3, 2.4)), ((-1.0, 6.0), (0.5, 1.6)),
             ((1.5, 6.6), (1.6, 0.4)), ((4.0, 6.2), (0.3, 3.0))]
    for (dz, yc), (tw, th) in tools:
        lib.box(b, "Werkzeug", x0 + 0.2, x0 + 0.35, yc - th / 2, yc + th / 2, zc + dz - tw / 2, zc + dz + tw / 2,
                (196, 204, 210), "Metal", deco=True)
    lib.box(b, "Werkbank", x0, x0 + 2.6, Y_FLOOR, 2.2, zc - 6.0, zc + 2.0, (96, 74, 52), "Wood")
    lib.box(b, "Werkbankplatte", x0, x0 + 2.8, 2.2, 2.5, zc - 6.2, zc + 2.2, (130, 96, 64), "WoodPlanks")
    lib.box(b, "Rollwagen", x0 + 1.0, x0 + 3.4, Y_FLOOR, 3.2, zc + 3.6, zc + 6.0, TOOLRED, "Metal")
    return b


def build_terminal(m, an, lib):
    """Annahme-Terminal am Mittelpfeiler (Station grosswerkstatt steht davor), Rundumleuchte obendrauf."""
    x1 = HALL[1]
    t = lib.model(m, "Annahme")
    body = lib.box(t, "Terminal", x1, x1 + 0.8, Y_APRON, 4.2, -1.5, 1.5, SLATE, "Metal")
    screen = lib.part(t, "Bildschirm", (2.6, 2.0, 0.1), CF.at(x1 + 0.85, 2.6, 0.0, 90), (20, 30, 40), "Neon",
                      deco=True)
    gui = lib.surface_text(screen, None, name="Anzeige", canvas=(260, 200))
    lib.text_label(gui, "ANNAHME", AMBER, "GothamBlack", "Title", None, (0.9, 0.3), (0.05, 0.08))
    lib.text_label(gui, "Auto reparieren · E drücken", WHITE, "GothamBold", "Sub", None, (0.9, 0.4), (0.05, 0.48))
    del body
    a = lib.model(an, "Rundumleuchte_Modell")
    ball = lib.ball(a, "Rundumleuchte", (x1 + 0.4, 4.7, 0.0), 1.0, AMBER, "Neon", deco=True)
    set_attrs(ball, {"Anim": "beacon", "Period": 1.2})
    return t


# ---------------------------------------------------------------- Teile-Ankauf
def build_annex(dm, lib):
    m = lib.model(dm, "TeileAnkauf")
    x0, x1, z0, z1 = ANNEX
    h = ANNEX_H
    t = 0.5
    wz0, wz1 = WINDOW
    lib.box(m, "Boden", x0, x1, Y_APRON - 0.3, 0.0, z0, z1, APRON, "Concrete")
    lib.box(m, "Wand_W", x0, x0 + t, 0.0, h, z0, z1, (176, 120, 70), "Brick")
    lib.box(m, "Wand_N", x0 + t, x1, 0.0, h, z0, z0 + t, (176, 120, 70), "Brick")
    lib.box(m, "Wand_O_N", x1 - t, x1, 0.0, h, z0 + t, wz0, (176, 120, 70), "Brick")
    lib.box(m, "Wand_O_S", x1 - t, x1, 0.0, h, wz1, z1, (176, 120, 70), "Brick")
    lib.box(m, "Bruestung", x1 - t, x1, 0.0, 2.6, wz0, wz1, (176, 120, 70), "Brick")
    lib.box(m, "Sturz", x1 - t, x1, 5.4, h, wz0, wz1, (176, 120, 70), "Brick")
    lib.box(m, "Theke", x1 - t, x1 + 1.0, 2.6, 2.9, wz0, wz1, (96, 74, 52), "Wood")
    lib.box(m, "Dach", x0 - 1.0, x1 + 1.0, h, h + 0.6, z0 - 1.0, z1, GRAPHITE, "Metal")
    lib.sign(m, "TEILE-ANKAUF", (9.0, 2.0), CF.at(x1 + 0.1, 6.6, -58.0, 90), AMBER, SLATE, name="Schild",
             sub="Altteile · gute Preise", sub_color=WHITE, bolts=False)
    head = lib.box(m, "Lampe", x1, x1 + 1.2, h - 0.4, h, -64.5, -63.0, LAMP, "Neon", deco=True)
    set_attrs(head, {"NightNeon": True})
    lib.point_light(head, 22, 0.9, LAMP, name="Thekenlicht")
    # Regale mit Teilen (durchs Fenster sichtbar)
    lib.box(m, "Regal", x0 + t, x0 + t + 2.0, 0.0, 6.0, -64.0, -50.0, (120, 128, 136), "Metal")
    for k, (zc, col) in enumerate(((-61.0, TOOLRED), (-57.0, TEAL), (-53.0, YELLOW))):
        lib.box(m, "Teilekiste", x0 + t + 2.0, x0 + t + 3.4, 2.0, 3.2, zc - 1.0, zc + 1.0, col, "Plastic")
    lib.box(m, "Ladentisch", x1 - 3.5, x1 - t, 0.0, 2.6, wz0 + 0.5, wz1 - 0.5, (96, 74, 52), "Wood")
    for k in range(3):
        lib.cylinder(m, "Reifen", (x1 + 2.5, Y_APRON + 0.45 + k * 0.9, -64.8), 0.9, 2.6, "Y", BLACK, "Plastic",
                     deco=True)
    return m


# ---------------------------------------------------------------- Hof
def build_yard(dm, lib):
    m = lib.model(dm, "Hof")
    # Teilecontainer und Reifenlager südlich der Halle
    c = lib.box(m, "Teilecontainer", -634.0, -618.0, Y_GRASS, 7.0, 54.0, 62.0, CONTAINER, "CorrodedMetal")
    del c
    lib.sign(m, "ERSATZTEILE", (6.0, 1.6), CF.at(-617.9, 4.5, 58.0, 90), WHITE, CONTAINER, name="Containerschild",
             bolts=False)
    for zc in (-4.0, 0.0, 4.0):
        for k in range(3):
            lib.cylinder(m, "Reifen", (-612.0, Y_GRASS + 0.45 + k * 0.9, 60.0 + zc), 0.9, 2.6, "Y", BLACK, "Plastic")
    # Bäume (natürlicher Abschluss zur Einfriedung)
    for i, (x, z) in enumerate(((-637.0, -62.0), (-637.0, 64.0), (-607.0, 64.0))):
        lib.tree_lite(m, x, Y_GRASS, z, scale=1.2, seed=60 + i, name="Hofbaum")
    return m


# ---------------------------------------------------------------- Einfriedung
def build_fence(dm, lib, splits):
    """Hecke (3 x 5) + unsichtbare Grenze entlang Nord (Z -71.5), West (X -643.5), Süd (Z 71.5). Wurde die
    Stadtgrenze aufgetrennt, schließen die Stücke genau an sie an (gleiches Aussehen); sonst Hecke bis X -589."""
    m = lib.model(dm, "Einfriedung")
    specs = []
    for xc, w, y0, y1, tpl in splits:
        specs.append((xc, w, y0, y1, tpl))
    if not any(_looks_hedge(t) for _, _, _, _, t in specs):
        specs.append((-590.0, 3.0, Y_GRASS, Y_GRASS + 5.0, None))
    if not any(_invisible(t) for _, _, _, _, t in specs if t is not None):
        specs.append((-590.0, 1.0, Y_GRASS, Y_GRASS + 60.0, "grenze"))
    for xc, w, y0, y1, tpl in specs:
        hw = w / 2
        pieces = [(FENCE_X - hw, FENCE_X + hw, -FENCE_Z - hw, FENCE_Z + hw),
                  (FENCE_X + hw, xc - hw, -FENCE_Z - hw, -FENCE_Z + hw),
                  (FENCE_X + hw, xc - hw, FENCE_Z - hw, FENCE_Z + hw)]
        for (a0, a1, b0, b1) in pieces:
            if a1 - a0 < 0.05:
                continue
            if tpl is None:
                lib.box(m, "Hecke", a0, a1, y0, y1, b0, b1, HEDGE, "Grass")
            elif tpl == "grenze":
                lib.box(m, "Grenze", a0, a1, y0, y1, b0, b1, HEDGE, "SmoothPlastic", transparency=1,
                        cast_shadow=False, query=False, touch=False)
            else:
                _clone_box(m, lib, tpl, a0, a1, y0, y1, b0, b1)
    return m


def _transp(item):
    from ..lib import get_prop
    e = get_prop(item, "Transparency")
    try:
        return float(e.text) if e is not None else 0.0
    except ValueError:
        return 0.0


def _invisible(item):
    return item is not None and item != "grenze" and _transp(item) >= 0.95


def _looks_hedge(item):
    return item is not None and item != "grenze" and not _invisible(item)


def _clone_box(m, lib, tpl, x0, x1, y0, y1, z0, z1):
    c = copy.deepcopy(tpl)
    for x in c.iter("Item"):
        x.set("referent", lib.ref())
    write_size(c, (x1 - x0, y1 - y0, z1 - z0))
    write_cf(c, CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    m.append(c)
    return c


# ---------------------------------------------------------------- Ankunftspunkte
def name_arrivals(city):
    ar = child(city, "Arrivals")
    st = child(city, "Stations")
    for key, title in ARRIVAL_NAMES.items():
        a = child(ar, key) if ar is not None else None
        if a is not None:
            set_attrs(a, {"DisplayName": title})
    del st
