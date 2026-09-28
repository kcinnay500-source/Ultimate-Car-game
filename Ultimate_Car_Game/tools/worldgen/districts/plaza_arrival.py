"""Ankunftshalle/Empfang (D2) mit Uhrturm, Stadtplatz (D1) mit Zahnradbrunnen, Kandelabern, Girlanden,
Farbleitsystem, Bestenliste/Infotafel, Wegweisern und Meile-Verzeichnis (CITY_SPEC §5, §6 D1/D2).

Stationen, Ankunftspunkte und CitySpawn baut contract.py - hier nur die Kulisse drumherum.
Animiertes (Anim-Attribut) liegt unter City.Animated.Stadtplatz: Schiebetüren (door), Uhrzeiger (clock),
Zahnradbrunnen mit Fontänen und Zahnradkrone (fountain).

Höhen (§1.2, keine koplanaren Oberseiten):
  Platzpflaster -0.50 (ground_roads) | Bänder -0.47 | Brunnenring -0.46 / Amber-Inlay -0.45 / Innenscheibe -0.44
  | Farbleitlinien draußen -0.40 (Ø3-Endscheiben -0.35) | Hallenboden 0 (Platte -0.5..0 auf dem Pflaster)
  | Startring 0.03 / Medaillon 0.05 = Farbleitlinien innen 0.05 (ohne Überlappung).
Abweichungen vom Spec (begründet):
  * Bänke am Brunnen auf r 23.5 statt 21 (die Farbleitlinien Amber/Weiß bei x ±18.8 laufen daran vorbei).
  * Farbleitlinien an der Südtür neu sortiert (Limette, Magenta, Amber | Weiß, Messing, Violett), damit sich keine
    Linien kreuzen; Amber/Weiß bei x ±18.8 (Brunnenrand 17.6, Tafelstützen 19.6), Amber mit Versatz um den
    Meile-Verzeichnis-Pylon (x -20.5 ab z -40).
  * Oldtimer-Denkmal bei (-40,-100) statt (-40,-112) (dort steht ein Kandelaber).
  * Girlandenmast (0,-168) -> (0,-170), damit die 6-Stud-Fläche um die Ankunft `plaza` (0,-165) frei bleibt.
  * Wegweiser (±132,-20) -> (±126,-18): (±132,-20) ist der Ampelmast an K-West/K-Ost.
  * Tafelstützen der Bestenliste/Infotafel bei x ±10 wie im Spec, aber hinter der Tafel (sonst stünden sie darin).
"""
import math

from ..lib import (CF, AMBER, BLACK, FOLIAGE, FRAME, GLASS, GRAPHITE, SLATE, STEEL, TEAL, TRUNK, WHITE, Vec3,
                   _color3_el, _cross, _len, _norm, _sub, _sub_el, _udim2_el, fnum, props, set_attrs, yaw_towards)

NAME = "Stadtplatz"

# ---------------------------------------------------------------- Farben
RUST_L = (200, 110, 50)
RUST = (140, 70, 40)
MAGENTA = (255, 64, 180)
LIME = (120, 200, 90)
BRASS = (201, 162, 90)
PURPLE = (135, 75, 196)
LWHITE = (235, 238, 240)
BLUE = (40, 110, 200)
WOOD = (181, 153, 112)
CREAM = (224, 214, 190)
SCREEN = (27, 72, 82)
SCREEN_TXT = (121, 225, 206)
WARM = (255, 214, 160)
BULB = (255, 200, 120)
BRONZE = (148, 106, 58)
BRONZE_HI = (176, 132, 78)
FLOOR = (164, 164, 158)
SKIN = (234, 192, 160)

Y_PAVE = -0.50
Y_BAND = -0.47
LINE_OUT = -0.40
LINE_IN = 0.05
LW = 1.2              # Linienbreite

# Halle
HX0, HX1, HZ0, HZ1 = -45.0, 45.0, -221.0, -181.0
WT = 0.8              # Wandstärke
CEIL = 24.0
WALL_TOP = 28.0

FOUNTAIN = (0.0, -100.0)


# ================================================================ Hilfen
def _box(lib, parent, name, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
    return lib.box(parent, name, min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1),
                   color, material, **kw)


def _cyl_y(lib, parent, name, x, y0, y1, z, dia, color, material="SmoothPlastic", **kw):
    return lib.cylinder(parent, name, (x, (y0 + y1) / 2, z), abs(y1 - y0), dia, "Y", color, material, **kw)


def _tri3d(lib, parent, name, R, A, B, t, color, material="Metal", shift=(0.0, 0.0, 0.0), **kw):
    """Rechtwinkliges Dreieck im Raum (rechter Winkel bei R) als WedgePart der Dicke t."""
    ez = _norm(_sub(R, A))
    ey = _norm(_sub(B, R))
    ex = _cross(ey, ez)
    sy, sz = _len(_sub(B, R)), _len(_sub(R, A))
    c = tuple(R[i] + ey[i] * sy / 2 - ez[i] * sz / 2 + shift[i] for i in range(3))
    return lib.part(parent, name, (t, sy, sz), CF.from_axes(c, ex, ey, ez), color, material, cls="WedgePart", **kw)


def _polyline(lib, parent, name, pts, y0, y1, color, w=LW, material="SmoothPlastic"):
    """Achsparallele Linie aus Punkten; Ecken nur einmal belegt (keine koplanaren Überlappungen)."""
    h = w / 2
    n = len(pts)
    out = []
    for i in range(n - 1):
        (ax, az), (bx, bz) = pts[i], pts[i + 1]
        if abs(az - bz) < 1e-9:
            s = 1 if bx > ax else -1
            a = ax + (s * h if i > 0 else 0)
            b = bx + (s * h if i < n - 2 else 0)
            if abs(b - a) < 0.05:
                continue
            out.append(_box(lib, parent, name, a, b, y0, y1, az - h, az + h, color, material, deco=True))
        else:
            s = 1 if bz > az else -1
            a = az + (s * h if i > 0 else 0)
            b = bz + (s * h if i < n - 2 else 0)
            if abs(b - a) < 0.05:
                continue
            out.append(_box(lib, parent, name, ax - h, ax + h, y0, y1, a, b, color, material, deco=True))
    return out


# ---------------------------------------------------------------- GUI
def _gui(lib, part, face="Back", px=40, name="SurfaceGui"):
    return lib.surface_text(part, None, face=face, px_per_stud=px, name=name)


def _frame(lib, g, name, x, y, w, h, color, transp=0.0, z=1):
    f = lib.item(g, "Frame", name)
    p = props(f)
    _udim2_el(p, "Size", w, 0, h, 0)
    _udim2_el(p, "Position", x, 0, y, 0)
    _color3_el(p, "BackgroundColor3", color)
    _sub_el(p, "float", "BackgroundTransparency", fnum(transp))
    _sub_el(p, "int", "BorderSizePixel", "0")
    _sub_el(p, "int", "ZIndex", str(z))
    return f


def _label(lib, g, name, text, x, y, w, h, color=AMBER, font="GothamBold", align=None, z=3, bg=None):
    lab = lib.text_label(g, text, color, font, name, bg, (w, h), (x, y))
    p = props(lab)
    _sub_el(p, "int", "ZIndex", str(z))
    if align:
        _sub_el(p, "token", "TextXAlignment", {"left": "0", "right": "1", "center": "2"}[align])
    return lab


def _draw_map(lib, g, here, rx, ry, rw, rh, here_text="DU BIST HIER"):
    """Stadtplan als Frames (Welt X -600..600, Z -400..460) in das Rechteck (rx,ry,rw,rh) (Skalenanteile)."""
    X0, X1, Z0, Z1 = -600.0, 600.0, -400.0, 460.0

    def fx(x):
        return rx + (x - X0) / (X1 - X0) * rw

    def fz(z):
        return ry + (z - Z0) / (Z1 - Z0) * rh

    def R(nm, x0, x1, z0, z1, col, zi=2, tr=0.0):
        _frame(lib, g, nm, fx(x0), fz(z0), fx(x1) - fx(x0), fz(z1) - fz(z0), col, tr, zi)

    def L(text, x, z, w, h, col=WHITE, zi=6):
        _label(lib, g, "Beschriftung", text, fx(x) - w / 2, fz(z) - h / 2, w, h, col, "GothamBold", "center", zi)

    R("Grund", X0, X1, Z0, Z1, (58, 76, 56), 1)
    R("Hecke", -590, 590, -390, 470, (73, 91, 64), 1, 0.0)
    # Bezirke
    R("Altstadt", -130, 130, -229, -23, (126, 130, 128))
    R("Parkplatz", -130, 130, -320, -229, BLUE)
    R("Autohaus", -130, 130, 23, 178, (205, 208, 212))
    R("Schrottplatz", -468, -178, -364, -159, RUST)
    R("Tuning", 178, 468, -364, -159, (40, 130, 126))
    R("Stadtpark", -468, -178, 159, 340, (86, 132, 74))
    R("Tankstelle", 178, 400, 159, 260, (114, 121, 124))
    R("Teststrecke", -167, 167, 258, 422, (200, 50, 50))
    R("Innenfeld", -143, 143, 282, 398, (73, 91, 64), 3)
    for x0 in (-468, -318, 178, 328):
        R("Werkstatt", x0, x0 + 140, -153, -25, SLATE, 3)
        R("Werkstatt", x0, x0 + 140, 25, 153, SLATE, 3)
    R("Spielhalle", -130, -70, -111, -31, (150, 80, 255), 3)
    R("Meisterschule", -130, -70, -175, -121, (44, 74, 62), 3)
    R("Auktionshaus", 70, 130, -121, -31, (130, 90, 60), 3)
    R("Credit-Center", 70, 130, -175, -129, PURPLE, 3)
    R("Empfang", -45, 45, -221, -181, AMBER, 3)
    R("Brunnen", -17, 17, -117, -83, (60, 150, 160), 3)
    # Straßen
    road = (46, 52, 59)
    R("Meile", -484, 484, -13, 13, road, 4)
    R("Kreisel", -556, -480, -38, 38, road, 4)
    R("Kreisel", 480, 556, -38, 38, road, 4)
    R("Markt", -165, -139, -355, 213, road, 4)
    R("Markt", 139, 165, -355, 213, road, 4)
    R("Nordring", -165, 165, -355, -329, road, 4)
    R("Suedring", -165, 165, 187, 213, road, 4)
    R("Mittellinie", -470, 470, -1.5, 1.5, AMBER, 5)
    # Beschriftung
    lw, lh = 0.2 * rw, 0.045 * rh
    L("WERKSTATTMEILE", -330, 0, 0.22 * rw, 0.04 * rh, AMBER)
    L("SCHROTTPLATZ", -323, -262, lw, lh)
    L("TUNING", 323, -262, lw, lh)
    L("PARKPLATZ", 0, -275, lw * 0.8, lh, WHITE)
    L("STADTPLATZ", 0, -125, lw * 0.8, lh, SLATE)
    L("AUTOHAUS", 0, 100, lw * 0.8, lh, SLATE)
    L("TESTSTRECKE", 0, 340, lw, lh)
    L("STADTPARK", -323, 250, lw, lh)
    L("TANKSTELLE", 289, 210, lw, lh)
    for nr, x, z in ((1, -398, -89), (3, -248, -89), (5, 248, -89), (7, 398, -89),
                     (2, -398, 89), (4, -248, 89), (6, 248, 89), (8, 398, 89)):
        L(str(nr), x, z, 0.05 * rw, 0.07 * rh, AMBER)
    # Standort
    mx, mz = here
    _frame(lib, g, "HierRing", fx(mx) - 0.018 * rw, fz(mz) - 0.025 * rh, 0.036 * rw, 0.05 * rh, WHITE, 0, 7)
    _frame(lib, g, "Hier", fx(mx) - 0.012 * rw, fz(mz) - 0.017 * rh, 0.024 * rw, 0.034 * rh, TEAL, 0, 8)
    _label(lib, g, "HierText", here_text, fx(mx) + 0.02 * rw, fz(mz) - 0.035 * rh, 0.3 * rw, 0.07 * rh, TEAL,
           "GothamBlack", "left", 8, None)


# ================================================================ Bausteine
def _bench(lib, parent, x, z, look_dx, look_dz, floor, length=5.0):
    """Bank, 4 Parts; Sitzfläche schaut in Richtung (look_dx, look_dz)."""
    m = lib.model(parent, "Bank")
    base = CF.at(x, floor, z, yaw_towards(look_dx, look_dz))
    lib.part(m, "Sitz", (length, 0.3, 1.6), base * CF(0, 1.5, 0), WOOD, "Wood")
    lib.part(m, "Lehne", (length, 1.35, 0.25), base * CF(0, 2.325, 0.925), WOOD, "Wood")
    for sx in (-1, 1):
        lib.part(m, "Bein", (0.3, 1.35, 1.4), base * CF(sx * (length / 2 - 0.5), 0.675, 0.05), BLACK, "Metal")
    return m


def _hero_tree(lib, parent, x, z, seed=0, ground=Y_PAVE):
    """Platzbaum (18 Parts): Gitterrost, Stamm, 4 Äste, 3 Laubkronen-Ringe aus je 4 Keilen."""
    m = lib.model(parent, "Platzbaum")
    _box(lib, m, "Baumrost", x - 1.8, x + 1.8, ground, ground + 0.06, z - 1.8, z + 1.8, BLACK, "DiamondPlate")
    _cyl_y(lib, m, "Stamm", x, ground + 0.06, ground + 10.5, z, 1.3, TRUNK, "Wood")
    for k in range(4):
        a = math.radians(seed * 23 + 45 + k * 90)
        lib.beam(m, "Ast", (x, ground + 6.6 + 0.5 * k, z), (x + math.cos(a) * 2.6, ground + 10.2, z + math.sin(a) * 2.6),
                 0.45, TRUNK, "Wood", deco=True)
    for tier, (y0, h, d, rot) in enumerate(((7.4, 5.4, 5.4, seed * 17), (11.2, 4.8, 4.0, seed * 17 + 45),
                                             (14.6, 3.8, 2.6, seed * 17 + 20))):
        for k in range(4):
            a = math.radians(rot + k * 90)
            ox, oz = math.cos(a), math.sin(a)
            cf = CF.at(x + ox * d / 2, ground + y0 + h / 2, z + oz * d / 2, yaw_towards(ox, oz))
            lib.wedge(m, "Laub", (2 * d, h, d), cf, FOLIAGE[(k + tier + seed) % 4], "Grass", deco=True)
    return m


def _planter_box(lib, parent, x0, x1, z0, z1, floor, height=2.5):
    m = lib.model(parent, "Pflanzkuebel")
    _box(lib, m, "Kuebel", x0, x1, floor, floor + height, z0, z1, SLATE, "Metal")
    _box(lib, m, "Hecke", x0 + 0.3, x1 - 0.3, floor + height, floor + height + 1.1, z0 + 0.3, z1 - 0.3,
         FOLIAGE[2], "Grass", deco=True)
    _box(lib, m, "Kante", x0 - 0.05, x1 + 0.05, floor + height - 0.4, floor + height - 0.2, z0 - 0.05, z1 + 0.05,
         AMBER, "Metal", deco=True)
    return m


def _topiary(lib, parent, x, z, floor):
    m = lib.model(parent, "Pflanzkuebel")
    _box(lib, m, "Kuebel", x - 1.25, x + 1.25, floor, floor + 1.8, z - 1.25, z + 1.25, SLATE, "Metal")
    lib.ball(m, "Buchs", (x, floor + 3.0, z), 2.9, FOLIAGE[1], "Grass", deco=True)
    lib.ball(m, "Buchs", (x + 0.2, floor + 4.6, z - 0.1), 1.9, FOLIAGE[3], "Grass", deco=True)
    return m


def _kandelaber(lib, parent, x, z, along_x, light):
    """Doppelkopf-Kandelaber (5 Parts), Köpfe Y 7.9..9.4; gibt die Kopfpositionen (oben) zurück."""
    m = lib.model(parent, "Kandelaber")
    g = Y_PAVE
    _box(lib, m, "Sockel", x - 0.65, x + 0.65, g, g + 1.0, z - 0.65, z + 0.65, BLACK, "Metal")
    _cyl_y(lib, m, "Mast", x, g + 1.0, 9.9, z, 0.5, FRAME, "Metal")
    dx, dz = (2.1, 0.0) if along_x else (0.0, 2.1)
    if along_x:
        _box(lib, m, "Ausleger", x - 2.4, x + 2.4, 9.55, 9.85, z - 0.15, z + 0.15, STEEL, "Metal", deco=True)
    else:
        _box(lib, m, "Ausleger", x - 0.15, x + 0.15, 9.55, 9.85, z - 2.4, z + 2.4, STEEL, "Metal", deco=True)
    heads = []
    for s in (-1, 1):
        hx, hz = x + s * dx, z + s * dz
        hd = _box(lib, m, "Kopf", hx - 0.5, hx + 0.5, 7.9, 9.55, hz - 0.5, hz + 0.5, WARM, "SmoothPlastic",
                  deco=True)
        set_attrs(hd, {"NightNeon": True})
        heads.append((hx, 9.55, hz))
        if light and s == 1:
            lib.point_light(hd, 30, 0.9, (255, 214, 160))
    return heads


def _signpost(lib, parent, x, z, blades, ground=Y_PAVE, name="Wegweiser"):
    """Stahlpfosten mit Amber-auf-Schiefer-Pfeilblättern; blades = [(dx, dz, text)]."""
    m = lib.model(parent, name)
    top = ground + 3.6 + 0.85 * len(blades)
    _box(lib, m, "Fuss", x - 0.5, x + 0.5, ground, ground + 0.5, z - 0.5, z + 0.5, BLACK, "Metal")
    _cyl_y(lib, m, "Pfosten", x, ground + 0.5, top, z, 0.35, STEEL, "Metal")
    lib.ball(m, "Kappe", (x, top + 0.2, z), 0.6, AMBER, "Metal", deco=True)
    for i, (dx, dz, text) in enumerate(blades):
        n = math.hypot(dx, dz)
        dx, dz = dx / n, dz / n
        y = top - 0.55 - i * 0.85
        yaw = math.degrees(math.atan2(-dz, dx))
        cf = CF.at(x + dx * 2.15, y, z + dz * 2.15, yaw)
        blade = lib.part(m, "Pfeil", (3.8, 0.7, 0.12), cf, SLATE, "SmoothPlastic", deco=True)
        lib.surface_text(blade, text + "  ›", face="Back", name="Vorne")
        lib.surface_text(blade, "‹  " + text, face="Front", name="Hinten")
    return m


# ================================================================ Ankunftshalle (D2)
def build_hall(lib, dm, anim):
    h = lib.model(dm, "Ankunftshalle", attrs={"District": "D2", "Title": "EMPFANG"})
    shell = lib.model(h, "Huelle")
    doors = lib.folder(anim, "Tueren")

    # --- Boden (Platte auf dem Pflaster, Stufe 0.5 an allen Türen)
    _box(lib, shell, "Boden", HX0, HX1, Y_PAVE, 0, HZ0, HZ1, FLOOR, "Marble", reflectance=0.04)

    # --- Eckpfeiler (Stahl, stehen 0.4 über)
    for cx in (-1, 1):
        for cz, (z0, z1) in ((HZ0, (HZ0 - 0.4, HZ0 + 1.2)), (HZ1, (HZ1 - 1.2, HZ1 + 0.4))):
            x0, x1 = (HX0 - 0.4, HX0 + 1.2) if cx < 0 else (HX1 - 1.2, HX1 + 0.4)
            _box(lib, shell, "Eckpfeiler", x0, x1, Y_PAVE, WALL_TOP + 0.4, z0, z1, STEEL, "Metal")

    # --- Nordwand (Z -221) mit Tür X -8..8
    nz0, nz1 = HZ0, HZ0 + WT
    _box(lib, shell, "Nordwand", HX0, -8, 0, WALL_TOP, nz0, nz1, SLATE, "Metal")
    _box(lib, shell, "Nordwand", 8, HX1, 0, WALL_TOP, nz0, nz1, SLATE, "Metal")
    _box(lib, shell, "Nordwand Sturz", -8, 8, 12, WALL_TOP, nz0, nz1, SLATE, "Metal")
    for x in (-32, -20, 20, 32):
        _box(lib, shell, "Lisene", x - 0.5, x + 0.5, Y_PAVE, WALL_TOP + 0.2, HZ0 - 0.4, HZ0 + 0.1, FRAME, "Metal")
    _box(lib, shell, "Neonband", HX0 + 1.2, HX1 - 1.2, 23.0, 23.4, HZ0 - 0.2, HZ0, AMBER, "Neon", deco=True)

    # --- West-/Ostwand mit Tür Z -206..-196 und Glasband Y 9..20
    for s in (-1, 1):
        xo = HX0 if s < 0 else HX1                       # Außenfläche
        xi = xo - s * WT                                  # Innenfläche
        wx0, wx1 = sorted((xo, xi))
        gx0, gx1 = sorted((xo - s * 0.25, xo - s * 0.55))
        za, zb = HZ0 + WT, HZ1 - WT                       # -220.2 .. -181.8
        side = "West" if s < 0 else "Ost"
        _box(lib, shell, side + "wand unten", wx0, wx1, 0, 9, za, -206, SLATE, "Metal")
        _box(lib, shell, side + "wand unten", wx0, wx1, 0, 9, -196, zb, SLATE, "Metal")
        _box(lib, shell, side + "wand Sturz", wx0, wx1, 12, 16, -206, -196, SLATE, "Metal")
        _box(lib, shell, side + "wand oben", wx0, wx1, 20, WALL_TOP, za, zb, SLATE, "Metal")
        _box(lib, shell, "Glasband", gx0, gx1, 9, 20, za, -206, GLASS, "Glass", transparency=0.3)
        _box(lib, shell, "Glasband", gx0, gx1, 9, 20, -196, zb, GLASS, "Glass", transparency=0.3)
        _box(lib, shell, "Glasband", gx0, gx1, 16, 20, -206, -196, GLASS, "Glass", transparency=0.3)
        for z in (-214, -188):
            _box(lib, shell, "Lisene", xo - s * 0.1, xo + s * 0.4, Y_PAVE, WALL_TOP + 0.2, z - 0.5, z + 0.5, FRAME,
                 "Metal")
        _box(lib, shell, "Neonband", xo, xo + s * 0.2, 23.0, 23.4, HZ0 + 1.2, HZ1 - 1.2, AMBER, "Neon", deco=True)

    # --- Südfassade (Z -181): Glas-Vorhangfassade, Pfosten alle 10, Kämpfer Y 12, Tür X -10..10
    zo = HZ1
    for x in (-40, -30, -20, 20, 30, 40):
        _box(lib, shell, "Pfosten", x - 0.3, x + 0.3, Y_PAVE, CEIL + 0.4, zo - 0.75, zo + 0.4, SLATE, "Metal")
    for s in (-1, 1):
        _box(lib, shell, "Tuerpfosten", s * 10, s * 10.8, Y_PAVE, 11.6, zo - 0.9, zo + 0.6, AMBER, "Metal")
        _box(lib, shell, "Kaempfer", s * 10.8, s * (HX1 - 1.2), 11.6, 12.4, zo - 0.7, zo + 0.5, SLATE, "Metal")
        _box(lib, shell, "Glasfassade", s * 10.5, s * (HX1 - 1.0), 0, CEIL, zo - 0.35, zo - 0.05, GLASS, "Glass",
             transparency=0.3)
    _box(lib, shell, "Tuersturz", -10.8, 10.8, 11.6, 12.4, zo - 0.9, zo + 0.6, AMBER, "Metal")
    _box(lib, shell, "Glasfassade", -10.5, 10.5, 12.4, CEIL, zo - 0.35, zo - 0.05, GLASS, "Glass", transparency=0.3)
    _box(lib, shell, "Attika", HX0 + 1.2, HX1 - 1.2, CEIL, WALL_TOP, zo - 0.8, zo, SLATE, "Metal")
    _box(lib, shell, "Neonband", HX0 + 1.2, HX1 - 1.2, 23.0, 23.4, zo + 0.4, zo + 0.6, AMBER, "Neon", deco=True)
    lib.sign(shell, "EMPFANG", (40, 4), CF.at(0, 26, zo + 0.1, 0), AMBER, SLATE, "GothamBlack", name="Attikaschild",
             sub="WILLKOMMEN IN DER STADT", sub_color=WHITE)
    # Vordach 26 x 1 x 8 auf zwei Stützen
    _box(lib, shell, "Vordach", -13, 13, 12.5, 13.5, zo + 0.6, zo + 8.6, GRAPHITE, "Metal")
    _box(lib, shell, "Vordach Neon", -13, 13, 12.7, 13.3, zo + 8.6, zo + 8.8, AMBER, "Neon", deco=True)
    for s in (-1, 1):
        _cyl_y(lib, shell, "Vordachstuetze", s * 12.2, Y_PAVE, 12.5, zo + 7.8, 0.5, STEEL, "Metal")

    # --- Dach (24 frei), Attika = Wände bis 28
    _box(lib, shell, "Dach", HX0 + WT, HX1 - WT, CEIL, CEIL + 1, HZ0 + WT, HZ1 - WT, GRAPHITE, "Metal")

    # --- Türrahmen außen (Farbe = Ziel) und Schilder
    def portal(nm, color, axis, c, lo, hi, outer, depth_sign):
        """Farbiger Portalrahmen vor der Außenfläche; axis 'x' = Tür in einer X-Wand (Breite in Z)."""
        o0, o1 = sorted((outer + depth_sign * 0.5, outer + depth_sign * 0.8))
        if axis == "x":
            _box(lib, shell, nm, o0, o1, Y_PAVE, 12, lo - 0.8, lo, color, "Metal")
            _box(lib, shell, nm, o0, o1, Y_PAVE, 12, hi, hi + 0.8, color, "Metal")
            _box(lib, shell, nm, o0, o1, 12, 12.8, lo - 0.8, hi + 0.8, color, "Metal")
        else:
            _box(lib, shell, nm, lo - 0.8, lo, Y_PAVE, 12, o0, o1, color, "Metal")
            _box(lib, shell, nm, hi, hi + 0.8, Y_PAVE, 12, o0, o1, color, "Metal")
            _box(lib, shell, nm, lo - 0.8, hi + 0.8, 12, 12.8, o0, o1, color, "Metal")

    portal("Portal Schrottplatz", RUST, "x", HX0, -206, -196, HX0, -1)
    portal("Portal Tuning", TEAL, "x", HX1, -206, -196, HX1, 1)
    portal("Portal Parkplatz", BLUE, "z", HZ0, -8, 8, HZ0, -1)
    lib.sign(shell, "SCHROTTPLATZ", (9, 2.8), CF.at(HX0 - 0.1, 14.3, -201, -90), CREAM, RUST, name="Tuerschild",
             sub="RECYCLINGHOF · PRESSE · ANKAUF", sub_color=CREAM)
    lib.sign(shell, "TUNING-ZENTRUM", (9, 2.8), CF.at(HX1 + 0.1, 14.3, -201, 90), TEAL, SLATE, name="Tuerschild",
             sub="PRÜFSTAND · PROJEKTE", sub_color=WHITE)
    lib.sign(shell, "PARKPLATZ-CHAOS", (14, 2.8), CF.at(0, 14.3, HZ0 - 0.1, 180), WHITE, BLUE, name="Tuerschild",
             sub="PARKHAUS · RÄTSEL-RASTER", sub_color=WHITE)
    # innen über den Türen
    lib.sign(shell, "SCHROTTPLATZ", (9, 2.8), CF.at(HX0 + WT + 0.1, 14.0, -201, 90), RUST_L, SLATE,
             name="Innenschild", bolts=False, sub="Presse · Ankauf · Zerlegeplatz")
    lib.sign(shell, "TUNING-ZENTRUM", (9, 2.8), CF.at(HX1 - WT - 0.1, 14.0, -201, -90), TEAL, SLATE,
             name="Innenschild", bolts=False, sub="Prüfstand · Projekt-Buchten")
    lib.sign(shell, "PARKPLATZ-CHAOS", (14, 2.8), CF.at(0, 14.0, HZ0 + WT + 0.1, 0), (90, 160, 240), SLATE,
             name="Innenschild", bolts=False, sub="Rätsel-Raster · Parkhaus · Aussicht")
    s_in = lib.sign(shell, "STADTPLATZ · AUTOHAUS · WERKSTATTMEILE", (18, 2.4), CF.at(0, 13.6, zo - 1.0, 180), AMBER,
                    SLATE, name="Innenschild", bolts=False, sub="Brunnen · Bestenliste · Werkstätten Nr. 1–8")
    for s in (-1, 1):
        _cyl_y(lib, shell, "Haenger", s * 7.5, 14.8, CEIL, zo - 1.0, 0.18, STEEL, "Metal", deco=True)

    # --- Schiebetüren (Anim door), je Flügel Glas + Stiel + Sockelleiste
    def leaf(nm, size, center, axis, lift, stile_side, door):
        m = lib.model(doors, nm, attrs={"Anim": "door", "Axis": axis, "Lift": lift, "Period": 10, "Door": door,
                                        "OpenRange": 12, "OpenTime": 0.6, "Mode": "slide"})
        cx, cy, cz = center
        sx, sy, sz = size
        if axis == "X":
            gsize = (sx - 0.1, sy - 0.1, sz)
        else:
            gsize = (sx, sy - 0.1, sz - 0.1)
        gl = lib.part(m, "Glas", gsize, CF(cx, cy, cz), GLASS, "Glass", transparency=0.35, collide=False,
                      cast_shadow=False)
        lib.set_primary(m, gl)
        if axis == "X":
            ex = cx + stile_side * (sx / 2 - 0.2)
            lib.part(m, "Stiel", (0.4, sy, sz + 0.06), CF(ex, cy, cz), STEEL, "Metal", collide=False)
            lib.part(m, "Sockelleiste", (sx - 0.4, 0.4, sz + 0.04), CF(cx - stile_side * 0.2, cy - sy / 2 + 0.2, cz),
                     STEEL, "Metal", collide=False)
            lib.part(m, "Griff", (0.12, 2.6, sz + 0.1), CF(ex - stile_side * 0.5, cy, cz), BLACK, "Metal", deco=True)
        else:
            ez = cz + stile_side * (sz / 2 - 0.2)
            lib.part(m, "Stiel", (sx + 0.06, sy, 0.4), CF(cx, cy, ez), STEEL, "Metal", collide=False)
            lib.part(m, "Sockelleiste", (sx + 0.04, 0.4, sz - 0.4), CF(cx, cy - sy / 2 + 0.2, cz - stile_side * 0.2),
                     STEEL, "Metal", collide=False)
            lib.part(m, "Griff", (sx + 0.1, 2.6, 0.12), CF(cx, cy, ez - stile_side * 0.5), BLACK, "Metal", deco=True)
        return m

    # Süd (innen, Z -182.1), 2 x 10 breit
    leaf("Tuer_Sued_W", (10, 11.4, 0.3), (-5, 0.1 + 5.7, zo - 1.1), "X", -10, 1, "Sued")
    leaf("Tuer_Sued_O", (10, 11.4, 0.3), (5, 0.1 + 5.7, zo - 1.1), "X", 10, -1, "Sued")
    # West/Ost (außen, 0.3 vor der Wand), 2 x 5
    for s, door in ((-1, "West"), (1, "Ost")):
        xc = (HX0 - 0.3) if s < 0 else (HX1 + 0.3)
        leaf("Tuer_%s_N" % door, (0.3, 12.3, 5), (xc, -0.35 + 6.15, -203.5), "Z", -5, 1, door)
        leaf("Tuer_%s_S" % door, (0.3, 12.3, 5), (xc, -0.35 + 6.15, -198.5), "Z", 5, -1, door)
    # Nord (außen), 2 x 8
    leaf("Tuer_Nord_W", (8, 12.3, 0.3), (-4, -0.35 + 6.15, HZ0 - 0.3), "X", -8, 1, "Nord")
    leaf("Tuer_Nord_O", (8, 12.3, 0.3), (4, -0.35 + 6.15, HZ0 - 0.3), "X", 8, -1, "Nord")

    # --- Innenausbau
    inner = lib.model(h, "Innenraum")
    # Holz-Sockelverkleidung Y 0..3
    wi = HZ0 + WT
    _box(lib, inner, "Wandsockel", HX0 + 1.2, -8, 0, 3, wi, wi + 0.2, WOOD, "Wood")
    _box(lib, inner, "Wandsockel", 8, HX1 - 1.2, 0, 3, wi, wi + 0.2, WOOD, "Wood")
    for s in (-1, 1):
        x0, x1 = sorted((s * (HX1 - WT), s * (HX1 - WT - 0.2)))
        _box(lib, inner, "Wandsockel", x0, x1, 0, 3, HZ0 + 1.2, -206, WOOD, "Wood")
        _box(lib, inner, "Wandsockel", x0, x1, 0, 3, -196, HZ1 - 1.2, WOOD, "Wood")

    # Medaillon + Startring (CitySpawn liegt darüber, contract.py)
    lib.cylinder(inner, "Startring", (0, 0.015, -201), 0.03, 17, "Y", AMBER, "Metal", deco=True)
    med = lib.cylinder(inner, "Medaillon", (0, 0.025, -201), 0.05, 14, "Y", TEAL, "Neon", deco=True)
    set_attrs(med, {"Role": "SpawnMedallion"})
    st = lib.part(inner, "Starttext", (7, 0.02, 2.4), CF.at(0, 0.07, -197.6, 180), WHITE, "SmoothPlastic",
                  transparency=1, deco=True)
    lib.surface_text(st, "START", face="Top", text_color=(10, 40, 42), font="GothamBlack")

    # Empfangstresen (3 Segmente, Holz auf Schiefer) bei (-26,0,-212)
    desk = lib.model(inner, "Empfangstresen")
    dz0, dz1 = -211.1, -208.9
    _box(lib, desk, "Tresen", -31, -21, 0, 3.2, dz0, dz1, SLATE, "Metal")
    _box(lib, desk, "Tresenplatte", -31.2, -20.8, 3.2, 3.5, dz0 - 0.1, dz1 + 0.3, WOOD, "Wood")
    for s in (-1, 1):
        fx_ = -26 + s * 5                                       # vordere Ecke
        d = (s * math.cos(math.radians(30)), -math.sin(math.radians(30)))   # entlang des Seitenteils
        n_in = (-s * math.sin(math.radians(30)) * 1, -math.cos(math.radians(30)))  # nach hinten/innen
        yaw = math.degrees(math.atan2(-d[1], d[0]))
        L = 7.0
        cxs = fx_ + d[0] * L / 2 + n_in[0] * 1.1
        czs = dz1 + d[1] * L / 2 + n_in[1] * 1.1
        lib.part(desk, "Tresen", (L, 3.14, 2.2), CF.at(cxs, 1.57, czs, yaw), SLATE, "Metal")
        lib.part(desk, "Tresenplatte", (L, 0.3, 2.6), CF.at(cxs - n_in[0] * 0.2, 3.29, czs - n_in[1] * 0.2, yaw),
                 WOOD, "Wood")
    _box(lib, desk, "Neonleiste", -30.5, -21.5, 0.3, 0.5, dz1, dz1 + 0.1, AMBER, "Neon", deco=True)
    lib.sign(desk, "EMPFANG · INFO", (6, 1.1), CF.at(-26, 2.1, dz1 + 0.06, 0), AMBER, SLATE, name="Tresenschild",
             bolts=False, thickness=0.1)
    _box(lib, desk, "Monitorfuss", -23.2, -22.8, 3.5, 4.2, -210.9, -210.5, BLACK, "Metal", deco=True)
    mon = _box(lib, desk, "Monitor", -24.1, -21.9, 4.1, 5.4, -210.95, -210.75, BLACK, "SmoothPlastic", deco=True)
    lib.surface_text(mon, "ANKUNFT", face="Front", text_color=SCREEN_TXT, bg=None)
    # Empfangsdame (7 Teile, Amber-Weste)
    fig = lib.model(inner, "Empfang_NPC")
    px, pz = -26, -213.3
    _box(lib, fig, "Beine", px - 0.8, px + 0.8, 0, 2.8, pz - 0.4, pz + 0.4, (40, 45, 55), "SmoothPlastic")
    _box(lib, fig, "Hemd", px - 0.9, px + 0.9, 2.8, 4.8, pz - 0.45, pz + 0.45, WHITE, "SmoothPlastic")
    _box(lib, fig, "Weste", px - 0.95, px + 0.95, 3.0, 4.6, pz - 0.475, pz + 0.475, AMBER, "SmoothPlastic",
         deco=True)
    for s in (-1, 1):
        _box(lib, fig, "Arm", px + s * 0.9, px + s * 1.4, 2.9, 4.8, pz - 0.3, pz + 0.3, WHITE, "SmoothPlastic",
             deco=True)
    _box(lib, fig, "Kopf", px - 0.55, px + 0.55, 4.85, 5.95, pz - 0.55, pz + 0.55, SKIN, "SmoothPlastic", deco=True)
    _box(lib, fig, "Haare", px - 0.575, px + 0.575, 5.75, 6.15, pz - 0.575, pz + 0.575, (70, 50, 35),
         "SmoothPlastic", deco=True)

    # Info-Bildschirm hinter dem Empfang (N-Wand X -40..-18, Y 5..13): Türen und Linienfarben
    scr = _box(lib, inner, "Infobildschirm", -40, -18, 5, 13, wi, wi + 0.2, BLACK, "SmoothPlastic")
    g = _gui(lib, scr, "Back", 40)
    _frame(lib, g, "Grund", 0.01, 0.02, 0.98, 0.96, SCREEN, 0, 1)
    _label(lib, g, "Titel", "WILLKOMMEN IN DER WERKSTATTMEILE", 0.03, 0.05, 0.94, 0.14, AMBER, "GothamBlack",
           "center", 3)
    rows = [(AMBER, "SÜDTÜR", "Stadtplatz · Brunnen · Werkstätten Nr. 1–8"),
            (LWHITE, "SÜDTÜR", "Autohaus · Teststrecke"),
            (RUST_L, "WESTTÜR", "Schrottplatz · Presse · Ankauf"),
            (TEAL, "OSTTÜR", "Tuning-Zentrum · Prüfstand"),
            (BLUE, "NORDTÜR", "Parkplatz-Chaos · Parkhaus")]
    for i, (col, door, dest) in enumerate(rows):
        y = 0.24 + i * 0.125
        _frame(lib, g, "Linie", 0.04, y + 0.035, 0.07, 0.04, col, 0, 2)
        _label(lib, g, "Tuer", door, 0.13, y, 0.2, 0.1, col, "GothamBlack", "left", 3)
        _label(lib, g, "Ziel", dest, 0.34, y, 0.62, 0.1, WHITE, "GothamBold", "left", 3)
    _label(lib, g, "Hinweis", "Folge den farbigen Linien am Boden!", 0.05, 0.87, 0.9, 0.09, SCREEN_TXT, "GothamBold",
           "center", 3)

    # Stadtplan-Wand (N-Wand X 12..40, Y 4..16) "DU BIST HIER"
    sp = _box(lib, inner, "Stadtplan", 12, 40, 4, 16, wi, wi + 0.2, SLATE, "SmoothPlastic")
    g = _gui(lib, sp, "Back", 40)
    _frame(lib, g, "Rahmen", 0, 0, 1, 1, (18, 24, 30), 0, 1)
    _label(lib, g, "Titel", "STADTPLAN", 0.02, 0.05, 0.3, 0.14, AMBER, "GothamBlack", "left", 3)
    _label(lib, g, "Untertitel", "Werkstattmeile · Stadtmitte", 0.02, 0.19, 0.3, 0.07, WHITE, "GothamBold", "left", 3)
    legend = [(AMBER, "Werkstattmeile"), (LWHITE, "Autohaus"), (MAGENTA, "Spielhalle"), (LIME, "Meisterschule"),
              (BRASS, "Auktionshaus"), (PURPLE, "Credit-Center"), (RUST_L, "Schrottplatz"), (TEAL, "Tuning"),
              (BLUE, "Parkplatz-Chaos")]
    for i, (col, txt) in enumerate(legend):
        y = 0.31 + i * 0.07
        _frame(lib, g, "Legende", 0.03, y + 0.02, 0.035, 0.03, col, 0, 2)
        _label(lib, g, "Legende", txt, 0.08, y, 0.24, 0.06, WHITE, "GothamBold", "left", 3)
    _draw_map(lib, g, (0, -201), 0.34, 0.03, 0.64, 0.94)

    # Schnellreise-Säule bei (26,0,-212)
    ped = lib.model(inner, "Schnellreise")
    _box(lib, ped, "Fuss", 24.7, 27.3, 0, 0.3, -213.3, -210.7, STEEL, "Metal")
    _box(lib, ped, "Saeule", 25.2, 26.8, 0.3, 3.4, -212.8, -211.2, SLATE, "Metal")
    _box(lib, ped, "Neonring", 25.15, 26.85, 2.9, 3.1, -212.85, -211.15, TEAL, "Neon", deco=True)
    con = lib.part(ped, "Pult", (2.8, 0.25, 2.0), CF(26, 3.75, -211.9) * CF.angles(math.radians(-25), 0, 0), SCREEN,
                   "SmoothPlastic")
    lib.surface_text(con, "SCHNELLREISE", face="Top", text_color=SCREEN_TXT)

    # Tagesziele (O-Wand Z -219..-209, Y 4..12) und Stadtinfo (W-Wand, gespiegelt)
    for s, title, lines, col in (
            (1, "TAGESZIELE", ["Drücke [E] für deine Ziele des Tages", "Belohnung: Credits & Erfahrung",
                               "Neue Ziele jeden Tag um Mitternacht"], AMBER),
            (-1, "STADTINFO", ["Schnellreise: Stadtplan-Säule rechts", "Bestenliste: am Zahnradbrunnen",
                               "Bald: Spielhalle, Auktionshaus, Teststrecke"], TEAL)):
        x0, x1 = sorted((s * (HX1 - WT), s * (HX1 - WT - 0.2)))
        bd = _box(lib, inner, "Tagesziele" if s > 0 else "Stadtinfo", x0, x1, 4, 12, -219, -209, BLACK,
                  "SmoothPlastic")
        g = _gui(lib, bd, "Right" if s < 0 else "Left", 40)
        _frame(lib, g, "Grund", 0.015, 0.03, 0.97, 0.94, SCREEN, 0, 1)
        _label(lib, g, "Titel", title, 0.04, 0.07, 0.92, 0.2, col, "GothamBlack", "center", 3)
        _frame(lib, g, "Strich", 0.1, 0.29, 0.8, 0.012, col, 0, 2)
        for i, t in enumerate(lines):
            _label(lib, g, "Zeile%d" % (i + 1), t, 0.06, 0.36 + i * 0.19, 0.88, 0.14, WHITE, "GothamBold", "left", 3)

    # Deckenleuchten: 3 Neonbalken 20 x 0.4 x 1 unter der Decke, je ein PointLight
    for x in (-28, 0, 28):
        bar = _box(lib, inner, "Deckenleuchte", x - 0.5, x + 0.5, CEIL - 0.4, CEIL, -211, -191, (232, 246, 249),
                   "Neon", deco=True)
        lib.point_light(bar, 30, 0.9, (224, 238, 255))

    # 4 Bänke an der Glasfassade (Z -184), 4 Pflanzkübel
    for x in (-34, -22, 22, 34):
        _bench(lib, inner, x, -184.2, 0, -1, 0)
    for x in (-42.5, -14, 14, 42.5):
        _topiary(lib, inner, x, -184.5, 0)

    # --- Uhrturm (64)
    build_tower(lib, h, anim)
    return h


def build_tower(lib, h, anim):
    t = lib.model(h, "Uhrturm")
    cx, cz = 0.0, -201.0
    y0, y1 = CEIL + 1, 54.0
    _box(lib, t, "Schaft", cx - 7, cx + 7, y0, y1, cz - 7, cz + 7, SLATE, "Metal")
    for sx in (-1, 1):
        for sz in (-1, 1):
            px, pz = cx + sx * 7, cz + sz * 7
            _box(lib, t, "Pilaster", px - 0.5, px + 0.5, y0, 53.6, pz - 0.5, pz + 0.5, STEEL, "Metal")
    # Lichtschlitze und Zifferblätter auf allen 4 Seiten
    hands = lib.model(anim, "Uhrzeiger", attrs={"Anim": "clock", "Faces": 4, "Hub": Vec3(cx, 46, cz)})
    faces = (("N", (0, -1)), ("S", (0, 1)), ("W", (-1, 0)), ("O", (1, 0)))
    for tag, (nx, nz) in faces:
        fx, fz = cx + nx * 7, cz + nz * 7
        if nx == 0:
            sl = _box(lib, t, "Lichtschlitz", fx - 0.7, fx + 0.7, 28, 38, fz, fz + nz * 0.1, WARM, "Glass",
                      transparency=0.25, deco=True)
        else:
            sl = _box(lib, t, "Lichtschlitz", fx, fx + nx * 0.1, 28, 38, fz - 0.7, fz + 0.7, WARM, "Glass",
                      transparency=0.25, deco=True)
        set_attrs(sl, {"NightNeon": True})
        axis = "Z" if nx == 0 else "X"

        def at(off):
            return (fx + nx * off, 46.0, fz + nz * off)
        lib.cylinder(t, "Uhrring", at(0.1), 0.2, 10.8, axis, AMBER, "Metal", deco=True)
        lib.cylinder(t, "Zifferblatt", at(0.35), 0.3, 10, axis, (240, 236, 225), "SmoothPlastic", deco=True)
        lib.cylinder(t, "Nabe", at(0.72), 0.36, 0.8, axis, BLACK, "Metal", deco=True)
        yaw = {"N": 180, "S": 0, "W": -90, "O": 90}[tag]
        pl = lib.part(t, "Ziffern", (9.4, 9.4, 0.02), CF.at(*at(0.52), yaw), WHITE, "SmoothPlastic", transparency=1,
                      deco=True)
        g = _gui(lib, pl, "Back", 30)
        for txt, x, y in (("XII", 0.4, 0.03), ("III", 0.8, 0.43), ("VI", 0.4, 0.83), ("IX", 0.0, 0.43)):
            _label(lib, g, "Ziffer", txt, x, y, 0.2, 0.14, (30, 34, 40), "Garamond", "center", 2)
        # Zeiger (10:10 als Ruhestellung; der Client stellt sie nach der Tageszeit)
        n = (nx, 0.0, nz)
        right = _cross((-nx, 0.0, -nz), (0.0, 1.0, 0.0))     # Blickrichtung x oben = rechts des Betrachters
        for hand, ang, size, off, depth in (("Stunde", 305, (0.5, 3.1, 0.12), 1.15, 0.62),
                                            ("Minute", 60, (0.34, 4.4, 0.1), 1.8, 0.76)):
            a = math.radians(ang)
            d = (right[0] * math.sin(a), math.cos(a), right[2] * math.sin(a))
            hub = at(depth)
            pos = (hub[0] + d[0] * off, hub[1] + d[1] * off, hub[2] + d[2] * off)
            cf = CF.from_axes(pos, _cross(d, n), d, n)
            p = lib.part(hands, "%s_%s" % (hand, tag), size, cf, (22, 26, 31), "Metal", deco=True)
            set_attrs(p, {"Hand": "hour" if hand == "Stunde" else "minute", "Face": tag, "Pivot": Vec3(*hub),
                          "Offset": off})
    # Kranz, Gesims, Pyramide, Spitze
    _box(lib, t, "Neonkranz", cx - 7.2, cx + 7.2, 53.4, 53.9, cz - 7.2, cz + 7.2, AMBER, "Neon", deco=True)
    _box(lib, t, "Gesims", cx - 7.7, cx + 7.7, 54.0, 54.6, cz - 7.7, cz + 7.7, GRAPHITE, "Metal")
    apex = (cx, 62.0, cz)
    yb, a = 54.6, 7.0
    for nx, nz in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        M = (cx + nx * a, yb, cz + nz * a)
        tx, tz = nz, nx                                           # Tangente
        nf = _norm((nx * (62.0 - yb), a, nz * (62.0 - yb)))       # Außennormale der Fläche
        th = 0.12
        shift = (-nf[0] * th / 2, -nf[1] * th / 2, -nf[2] * th / 2)
        for s in (-1, 1):
            C = (M[0] + s * tx * a, yb, M[2] + s * tz * a)
            _tri3d(lib, t, "Pyramide", M, C, apex, th, GRAPHITE, "Metal", shift=shift)
    _cyl_y(lib, t, "Spitze", cx, 61.6, 63.3, cz, 0.5, TEAL, "Metal", deco=True)
    fin = lib.ball(t, "Knauf", (cx, 63.4, cz), 1.2, TEAL, "Neon", deco=True)
    lib.point_light(fin, 24, 1.0, (255, 214, 150))


# ================================================================ Stadtplatz (D1)
def build_plaza(lib, dm, anim):
    p = lib.model(dm, "Platz", attrs={"District": "D1"})
    # Bänder (-0.47): Z -60 / -140 (an den X-Bändern geteilt), X ±30 durchgehend
    bands = lib.model(p, "Pflasterbaender")
    for z in (-60, -140):
        for x0, x1 in ((-60, -31), (-29, 29), (31, 60)):
            _box(lib, bands, "Band", x0, x1, Y_PAVE, Y_BAND, z - 1, z + 1, (96, 100, 102), "Slate")
    for x in (-30, 30):
        _box(lib, bands, "Band", x - 1, x + 1, Y_PAVE, Y_BAND, -175, -23, (96, 100, 102), "Slate")

    build_fountain(lib, p, anim)

    # Kandelaber (8), 4 mit Licht
    kf = lib.model(p, "Kandelaber")
    heads = {}
    for (x, z, along_x, light) in ((-12, -60, True, True), (12, -60, True, True), (-12, -140, True, True),
                                   (12, -140, True, True), (-40, -88, False, False), (40, -88, False, False),
                                   (-40, -112, False, False), (40, -112, False, False)):
        heads[(x, z)] = _kandelaber(lib, kf, x, z, along_x, light)

    # Girlanden: 8 Masten, Drähte mit Durchhang, 40 Birnen
    gf = lib.model(p, "Girlanden")
    masts = [(-50, -100), (50, -100), (0, -170), (-50, -60), (50, -60), (-50, -140), (50, -140), (0, -40)]
    for (x, z) in masts:
        _cyl_y(lib, gf, "Girlandenmast", x, Y_PAVE, 8.5, z, 0.35, FRAME, "Metal")
        lib.ball(gf, "Mastkappe", (x, 8.75, z), 0.6, AMBER, "Metal", deco=True)

    def head_near(k, m):
        hs = heads[k]
        return min(hs, key=lambda q: (q[0] - m[0]) ** 2 + (q[2] - m[1]) ** 2)
    wires = []
    for k, m in (((-12, -60), (0, -40)), ((12, -60), (0, -40)), ((-12, -140), (0, -170)), ((12, -140), (0, -170)),
                 ((-40, -88), (-50, -100)), ((-40, -112), (-50, -100)), ((40, -88), (50, -100)),
                 ((40, -112), (50, -100))):
        wires.append((head_near(k, m), (m[0], 8.4, m[1])))
    for sx in (-50, 50):
        wires.append(((sx, 8.4, -60), (sx, 8.4, -100)))
        wires.append(((sx, 8.4, -140), (sx, 8.4, -100)))
    lengths = [math.dist(a, b) for a, b in wires]
    total = sum(lengths)
    counts = [max(2, round(40 * L / total)) for L in lengths]
    while sum(counts) > 40:
        counts[counts.index(max(counts))] -= 1
    while sum(counts) < 40:
        counts[counts.index(min(counts))] += 1
    for (a, b), n in zip(wires, counts):
        sag = 0.9 + 0.02 * math.dist(a, b)
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - sag, (a[2] + b[2]) / 2)
        lib.beam(gf, "Draht", a, mid, 0.08, BLACK, "Metal", deco=True)
        lib.beam(gf, "Draht", mid, b, 0.08, BLACK, "Metal", deco=True)
        for i in range(n):
            t = (i + 1) / (n + 1)
            x = a[0] + (b[0] - a[0]) * t
            z = a[2] + (b[2] - a[2]) * t
            y = a[1] + (b[1] - a[1]) * t - sag * (1 - (2 * t - 1) ** 2) - 0.35
            bl = lib.ball(gf, "Birne", (x, y, z), 0.6, BULB, "SmoothPlastic", deco=True)
            set_attrs(bl, {"NightNeon": True})

    # Tafeln: Bestenliste (-30) und Infotafel (+30) bei Z -150, Y 2..18
    build_boards(lib, p)

    # Möbel: 8 Bänke um den Brunnen (r 23.5), 4 Pflanzkübel an der Meile, Poller an der Öffnung
    mf = lib.model(p, "Moebel")
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        bx, bz = FOUNTAIN[0] + 23.5 * math.cos(a), FOUNTAIN[1] + 23.5 * math.sin(a)
        _bench(lib, mf, bx, bz, -math.cos(a), -math.sin(a), -0.44)
    for x0, x1 in ((-52, -42), (-32, -22), (22, 32), (42, 52)):
        _planter_box(lib, mf, x0, x1, -28.5, -25.5, Y_PAVE)
    for x in (-13, 13):
        for z in (-24.5, -28.0):
            _cyl_y(lib, mf, "Poller", x, Y_PAVE, 2.7, z, 0.5, AMBER, "Metal")
            _cyl_y(lib, mf, "Pollerband", x, 1.9, 2.2, z, 0.54, BLACK, "Metal", deco=True)

    # 4 Platzbäume
    tf = lib.model(p, "Baeume")
    for i, (x, z) in enumerate(((-50, -40), (50, -40), (-50, -165), (50, -165))):
        _hero_tree(lib, tf, x, z, seed=i)

    build_imbiss(lib, p)
    build_denkmal(lib, p)
    return p


def build_fountain(lib, p, anim):
    fx, fz = FOUNTAIN
    b = lib.model(p, "Zahnradbrunnen")
    # Pflasterring Ø60 (-0.46) mit Amber-Inlay (r 26.5..27.5)
    lib.cylinder(b, "Brunnenring", (fx, -0.48, fz), 0.04, 60, "Y", (138, 141, 138), "Slate")
    lib.cylinder(b, "Inlay", (fx, -0.475, fz), 0.05, 55, "Y", AMBER, "Metal", deco=True)
    lib.cylinder(b, "Brunnenplatz", (fx, -0.47, fz), 0.06, 53, "Y", (132, 135, 132), "Slate")
    # Becken: Boden, Wasser, 12 Wandsegmente, 12 Stahlkanten (abwechselnd 1.80/1.78)
    lib.cylinder(b, "Beckenboden", (fx, (-0.44 + 0.4) / 2, fz), 0.84, 33, "Y", (38, 70, 80), "Slate")
    lib.cylinder(b, "Wasser", (fx, 0.7, fz), 0.6, 32.6, "Y", (60, 150, 160), "Glass", transparency=0.3,
                 reflectance=0.2, collide=False, cast_shadow=False)
    for k in range(12):
        a = math.radians(15 + 30 * k)
        yaw = math.degrees(math.atan2(-math.sin(a), math.cos(a))) + 90
        ytop = 1.5 if k % 2 == 0 else 1.49
        cwx, cwz = fx + 16.6 * math.cos(a), fz + 16.6 * math.sin(a)
        lib.part(b, "Beckenwand", (2 * 17.0 * math.tan(math.radians(15)), ytop + 0.44, 0.8),
                 CF.at(cwx, (ytop - 0.44) / 2, cwz, yaw), SLATE, "Metal")
        ctop = 1.8 if k % 2 == 0 else 1.78
        ccx, ccz = fx + 16.65 * math.cos(a), fz + 16.65 * math.sin(a)
        lib.part(b, "Beckenkante", (2 * 17.3 * math.tan(math.radians(15)), ctop - 1.5, 1.3),
                 CF.at(ccx, (1.5 + ctop) / 2, ccz, yaw), STEEL, "Metal")
    # Schalen und Säulen
    ped = _cyl_y(lib, b, "Saeule", fx, 0.4, 6, fz, 4, SLATE, "Metal", cast_shadow=False)
    _cyl_y(lib, b, "Schale", fx, 6, 7, fz, 14, SLATE, "Metal", cast_shadow=False)
    _cyl_y(lib, b, "Schalenwasser", fx, 7, 7.08, fz, 12.6, (80, 170, 185), "Glass", transparency=0.3,
           reflectance=0.2, deco=True)
    _cyl_y(lib, b, "Saeule", fx, 7.08, 10, fz, 2.5, SLATE, "Metal", cast_shadow=False)
    _cyl_y(lib, b, "Schale", fx, 10, 10.6, fz, 7, STEEL, "Metal", cast_shadow=False)
    _cyl_y(lib, b, "Schalenwasser", fx, 10.6, 10.66, fz, 6.2, (80, 170, 185), "Glass", transparency=0.3,
           reflectance=0.2, deco=True)
    _cyl_y(lib, b, "Kronenstiel", fx, 10.66, 13.4, fz, 0.8, STEEL, "Metal", deco=True)
    # Heldenlicht: Attachment an der Säule auf (0,1.6,-100)
    pcf = CF(fx, 3.2, fz) * CF.angles(0, 0, math.pi / 2)
    loc = pcf.inverse() * CF(fx, 1.6, fz)
    att = lib.attachment(ped, "Brunnenlicht", loc)
    lib.point_light(att, 18, 1.2, (80, 220, 210), shadows=True)

    # Animiert: Fontänen + Zahnradkrone
    am = lib.model(anim, "Zahnradbrunnen", attrs={"Anim": "fountain", "Amplitude": 1 / 3, "Period": 2.4,
                                                    "JetMin": 4, "JetMax": 6, "YawPeriod": 30, "SpinPeriod": 12,
                                                    "Crown": "Zahnradkrone", "Center": Vec3(fx, 17, fz)})
    for k in range(8):
        a = math.radians(45 * k)
        jx, jz = fx + 12 * math.cos(a), fz + 12 * math.sin(a)
        # 12° nach innen geneigt; lokale Y-Achse = Strahlrichtung (Unterkante bleibt beim Pulsieren)
        tilt = math.radians(12)
        d = (-math.cos(a) * math.sin(tilt), math.cos(tilt), -math.sin(a) * math.sin(tilt))
        base = (jx, 1.0, jz)
        c = (base[0] + d[0] * 3, base[1] + d[1] * 3, base[2] + d[2] * 3)
        side = _norm(_cross(d, (0.0, 0.0, 1.0)) if abs(math.sin(a)) > 0.7 else _cross(d, (1.0, 0.0, 0.0)))
        back = _cross(side, d)
        lib.part(am, "Jet%d" % (k + 1), (0.6, 6, 0.6), CF.from_axes(c, side, d, back), (185, 228, 240), "Glass",
                 transparency=0.35, deco=True)
    crown = lib.model(am, "Zahnradkrone")
    gy = 17.0
    lib.cylinder(crown, "Zahnrad", (fx, gy, fz), 1.2, 8, "Z", AMBER, "Metal")
    lib.cylinder(crown, "Zahnradspiegel", (fx, gy, fz), 1.3, 5.6, "Z", (214, 146, 44), "Metal", deco=True)
    lib.cylinder(crown, "Nabe", (fx, gy, fz), 1.6, 2.4, "Z", TEAL, "Metal", deco=True)
    for k in range(8):
        a = math.radians(45 * k + 22.5)
        cf = CF(fx + 4.6 * math.cos(a), gy + 4.6 * math.sin(a), fz) * CF.angles(0, 0, a)
        lib.part(crown, "Zahn%d" % (k + 1), (2.0, 1.6, 1.1), cf, AMBER, "Metal", deco=True)


def build_boards(lib, p):
    bf = lib.model(p, "Tafeln")
    for cx, kind in ((-30, "leader"), (30, "info")):
        z = -150.0
        m = lib.model(bf, "Bestenliste" if kind == "leader" else "Infotafel")
        for s in (-1, 1):
            px = cx + s * 10
            _box(lib, m, "Stuetze", px - 0.4, px + 0.4, Y_PAVE, 18, z - 1.1, z - 0.3, SLATE, "Metal")
            _box(lib, m, "Fuss", px - 0.7, px + 0.7, Y_PAVE, -0.1, z - 1.4, z - 0.1, BLACK, "Metal")
        _box(lib, m, "Dach", cx - 11.4, cx + 11.4, 18, 18.5, z - 1.3, z + 0.5, GRAPHITE, "Metal")
        _box(lib, m, "Neonkante", cx - 11.4, cx + 11.4, 18.1, 18.4, z + 0.5, z + 0.6, AMBER, "Neon", deco=True)
        _box(lib, m, "Neonkante", cx - 11.4, cx + 11.4, 18.1, 18.4, z - 1.4, z - 1.3, AMBER, "Neon", deco=True)
        nm = "LeaderboardBoard" if kind == "leader" else "Infotafel"
        board = _box(lib, m, nm, cx - 11, cx + 11, 2, 18, z - 0.3, z + 0.3, SLATE, "SmoothPlastic")
        front = _gui(lib, board, "Back", 40)
        _frame(lib, front, "Grund", 0.015, 0.02, 0.97, 0.96, (20, 28, 36), 0, 1)
        if kind == "leader":
            set_attrs(board, {"Board": "leaderboard", "Rows": 10})
            _frame(lib, front, "Kopf", 0.015, 0.02, 0.97, 0.15, AMBER, 0, 2)
            _label(lib, front, "Title", "BESTENLISTE", 0.04, 0.035, 0.92, 0.12, SLATE, "GothamBlack", "center", 3)
            _label(lib, front, "Status", "Wird geladen …", 0.04, 0.18, 0.92, 0.06, (224, 231, 230), "GothamBold",
                   "center", 3)
            for i in range(10):
                y = 0.255 + i * 0.071
                if i % 2 == 0:
                    _frame(lib, front, "Streifen", 0.03, y, 0.94, 0.066, (32, 44, 56), 0, 2)
                col = AMBER if i < 3 else WHITE
                _label(lib, front, "Row%d" % (i + 1), "%d.  —" % (i + 1), 0.05, y + 0.006, 0.9, 0.054, col,
                       "GothamBold", "left", 3)
        else:
            _frame(lib, front, "Kopf", 0.015, 0.02, 0.97, 0.15, TEAL, 0, 2)
            _label(lib, front, "Titel", "TAGESZIELE & NEUIGKEITEN", 0.04, 0.035, 0.92, 0.12, WHITE, "GothamBlack",
                   "center", 3)
            news = [(AMBER, "Tagesziele: drücke [E] an dieser Tafel"),
                    (LWHITE, "Autohaus: neue Modelle in der Rotunde"),
                    (MAGENTA, "Spielhalle: Geschick statt Glück – bald"),
                    (BRASS, "Auktionshaus: erste Versteigerung bald"),
                    (RUST_L, "Schrottpresse: Ankauf täglich geöffnet"),
                    (TEAL, "Tuning-Zentrum: Prüfstand ist frei"),
                    (BLUE, "Parkplatz-Chaos: neues Rätsel jeden Tag")]
            for i, (col, txt) in enumerate(news):
                y = 0.22 + i * 0.105
                _frame(lib, front, "Punkt", 0.05, y + 0.03, 0.025, 0.035, col, 0, 2)
                _label(lib, front, "Zeile%d" % (i + 1), txt, 0.1, y, 0.86, 0.08, WHITE, "GothamBold", "left", 3)
        # Rückseite (Norden)
        back = _gui(lib, board, "Front", 40, name="Rueckseite")
        _frame(lib, back, "Grund", 0.015, 0.02, 0.97, 0.96, (20, 28, 36), 0, 1)
        if kind == "leader":
            _label(lib, back, "Titel", "STADTPLAN", 0.03, 0.03, 0.5, 0.09, AMBER, "GothamBlack", "left", 3)
            _draw_map(lib, back, (-30, -150), 0.03, 0.13, 0.94, 0.84)
        else:
            _label(lib, back, "Titel", "WEGWEISER", 0.04, 0.035, 0.92, 0.12, AMBER, "GothamBlack", "center", 3)
            ways = [(AMBER, "Werkstattmeile Nr. 1–8", "Süden · Meile"),
                    (LWHITE, "Autohaus · Teststrecke", "Süden · über die Meile"),
                    (MAGENTA, "Spielhalle", "Westseite des Platzes"),
                    (LIME, "Meisterschule", "Westseite · Nord"),
                    (BRASS, "Auktionshaus", "Ostseite des Platzes"),
                    (PURPLE, "Credit-Center", "Ostseite · Nord"),
                    (RUST_L, "Schrottplatz", "Empfang · Westtür"),
                    (TEAL, "Tuning-Zentrum", "Empfang · Osttür"),
                    (BLUE, "Parkplatz-Chaos", "Empfang · Nordtür")]
            for i, (col, a, b) in enumerate(ways):
                y = 0.2 + i * 0.085
                _frame(lib, back, "Linie", 0.04, y + 0.025, 0.06, 0.03, col, 0, 2)
                _label(lib, back, "Ziel", a, 0.12, y, 0.45, 0.07, WHITE, "GothamBold", "left", 3)
                _label(lib, back, "Weg", b, 0.57, y, 0.39, 0.07, col, "GothamBold", "right", 3)


def build_imbiss(lib, p):
    m = lib.model(p, "Imbiss", attrs={"Title": "Pit-Stop · Currywurst & Co."})
    g = Y_PAVE
    x0, x1, z0, z1 = 43.0, 49.0, -114.0, -106.0
    _box(lib, m, "Wagen", x0, x1, g + 1.0, g + 4.2, z0, z1, SLATE, "Metal")
    _box(lib, m, "Zierstreifen", x0 - 0.02, x1 + 0.02, g + 2.4, g + 2.8, z0 - 0.02, z1 + 0.02, AMBER, "Metal",
         deco=True)
    _box(lib, m, "Theke", x0 - 0.8, x0, g + 3.9, g + 4.1, z0 + 1, z1 - 1, WOOD, "Wood")
    menu = lib.sign(m, "CURRYWURST · POMMES · LIMO", (6.4, 2.0), CF.at(x1 - 0.12, g + 5.6, (z0 + z1) / 2, -90),
                    AMBER, SLATE, name="Speisekarte", bolts=False, sub="Currywurst 3 Cr · Pommes 2 Cr · Limo 1 Cr")
    for x in (x0 + 0.2, x1 - 0.2):
        for z in (z0 + 0.2, z1 - 0.2):
            _cyl_y(lib, m, "Pfosten", x, g + 4.2, g + 7.4, z, 0.3, STEEL, "Metal")
    for i in range(4):
        za = z0 - 0.4 + i * 2.2
        _box(lib, m, "Markise", x0 - 0.8, x1 + 0.4, g + 7.4, g + 7.7, za, za + 2.2, AMBER if i % 2 == 0 else LWHITE,
             "Fabric")
    _box(lib, m, "Volant", x0 - 0.9, x0 - 0.8, g + 6.9, g + 7.7, z0 - 0.4, z1 + 0.4, AMBER, "Fabric", deco=True)
    lib.sign(m, "PIT-STOP", (6.4, 1.9), CF.at(46.0, g + 8.65, (z0 + z1) / 2, -90), AMBER, SLATE, "GothamBlack",
             name="Imbissschild", sub="Currywurst & Co.", sub_color=WHITE)
    for x in (x0 - 0.25, x1 + 0.25):
        lib.cylinder(m, "Rad", (x, g + 1.0, (z0 + z1) / 2), 0.5, 2.0, "X", BLACK, "SmoothPlastic")
    lib.beam(m, "Deichsel", (46, g + 1.3, z1), (46, g + 0.25, z1 + 2.6), 0.3, STEEL, "Metal")
    for tz in (-105.0, -117.0):
        _cyl_y(lib, m, "Stehtisch", 38.5, g, g + 3.6, tz, 0.35, STEEL, "Metal")
        _cyl_y(lib, m, "Tischplatte", 38.5, g + 3.6, g + 3.72, tz, 1.8, WOOD, "Wood")
    return menu


def build_denkmal(lib, p):
    m = lib.model(p, "Oldtimer-Denkmal")
    cx, cz = -40.0, -100.0
    _box(lib, m, "Sockel", cx - 8, cx + 8, Y_PAVE, 2.5, cz - 4, cz + 4, SLATE, "Metal")
    _box(lib, m, "Sockelplatte", cx - 8.3, cx + 8.3, 2.5, 2.8, cz - 4.3, cz + 4.3, FRAME, "Metal")
    lib.sign(m, "OLDTIMER-DENKMAL", (7, 1.8), CF.at(cx + 8.1, 1.2, cz, 90), (52, 36, 20), BRASS, name="Plakette",
             sub="Zu Ehren der ersten Werkstatt der Meile · 1954", sub_color=(60, 42, 24), material="Metal")
    car = lib.model(m, "Bronzeauto", attrs={"Lite": True})
    cy = 2.8

    def P(lx, ly, lz):
        return (cx + lx, cy + ly, cz + lz)

    def blk(nm, c, size, col=BRONZE, rz=0.0, **kw):
        return lib.part(car, nm, size, CF(*P(*c)) * CF.angles(0, 0, math.radians(rz)), col, "Metal",
                        reflectance=0.08, **kw)
    blk("Rahmen", (0, 1.5, 0), (11, 0.4, 4.0))
    blk("Karosserie", (-2.2, 2.7, 0), (6.0, 1.8, 4.4))
    blk("Motorhaube", (3.2, 2.8, 0), (4.0, 1.6, 3.0))
    lib.cylinder(car, "Haubenrundung", P(3.2, 3.1, 0), 3.9, 3.0, "X", BRONZE, "Metal", reflectance=0.08)
    blk("Kuehler", (5.35, 3.1, 0), (0.3, 2.8, 2.8), BRONZE_HI)
    lib.ball(car, "Kuehlerfigur", P(5.35, 4.75, 0), 0.5, BRONZE_HI, "Metal", deco=True)
    for s in (-1, 1):
        lib.cylinder(car, "Scheinwerfer", P(5.2, 3.6, s * 1.9), 0.7, 1.0, "X", BRONZE_HI, "Metal", deco=True)
        blk("Kotfluegel", (3.8, 2.85, s * 2.55), (3.4, 0.3, 1.2), rz=-12, deco=True)
        blk("Kotfluegel", (-3.8, 2.85, s * 2.55), (3.4, 0.3, 1.2), rz=12, deco=True)
        blk("Trittbrett", (0, 1.75, s * 2.55), (4.4, 0.2, 1.1), deco=True)
        for wx in (-4.0, 4.0):
            lib.cylinder(car, "Rad", P(wx, 1.3, s * 2.35), 0.7, 2.6, "Z", BRONZE, "Metal", reflectance=0.08)
            lib.cylinder(car, "Radnabe", P(wx, 1.3, s * 2.45), 0.8, 1.0, "Z", BRONZE_HI, "Metal", deco=True)
        for px in (-0.2, -4.2):
            _cyl_y(lib, car, "Dachstrebe", cx + px, cy + 3.6, cy + 5.8, cz + s * 2.0, 0.25, BRONZE, "Metal",
                   deco=True)
    blk("Dach", (-2.2, 5.9, 0), (4.6, 0.25, 4.4))
    blk("Windschutz", (-0.1, 4.7, 0), (0.15, 2.0, 4.0), BRONZE_HI, transparency=0.4, deco=True)
    blk("Sitzbank", (-2.4, 3.9, 0), (2.0, 0.9, 3.8))
    lib.cylinder(car, "Reserverad", P(-5.6, 3.0, 0), 0.6, 2.2, "X", BRONZE, "Metal", reflectance=0.08)
    lib.cylinder(car, "Stossstange", P(5.9, 1.6, 0), 4.8, 0.35, "Z", BRONZE_HI, "Metal", deco=True)
    lib.cylinder(car, "Stossstange", P(-5.1, 1.6, 0), 4.6, 0.35, "Z", BRONZE_HI, "Metal", deco=True)
    return m


# ================================================================ Wegeleitsystem
def build_wayfinding(lib, dm):
    w = lib.model(dm, "Wegeleitsystem")
    fl = lib.model(w, "Farbleitsystem")

    def line(nm, color, pts, top, discs=()):
        m = lib.model(fl, nm, attrs={"Target": nm})
        _polyline(lib, m, "Linie", pts, top - 0.1 if top < 0 else 0.0, top, color)
        for (x, z, ground) in discs:
            lib.cylinder(m, "Zielscheibe", (x, (ground + ground + 0.15) / 2, z), 0.15, 3, "Y", color, "SmoothPlastic",
                         deco=True)
        return m

    def ring_start(x):
        return -201 + math.sqrt(8.5 ** 2 - x ** 2)

    # Innen (Hallenboden 0..0.05), vom Startring zu den Türen
    inner = [("Spielhalle", MAGENTA, -5), ("Meisterschule", LIME, -7), ("Werkstattmeile", AMBER, -3),
             ("Autohaus", LWHITE, 3), ("Auktionshaus", BRASS, 5), ("Credit-Center", PURPLE, 7)]
    m_in = lib.model(fl, "Halle")
    for nm, col, x in inner:
        _polyline(lib, m_in, "Linie " + nm, [(x, ring_start(x)), (x, HZ1)], 0.0, LINE_IN, col)
    _polyline(lib, m_in, "Linie Schrottplatz", [(-8.5, -201), (HX0, -201)], 0.0, LINE_IN, RUST_L)
    _polyline(lib, m_in, "Linie Tuning", [(8.5, -201), (HX1, -201)], 0.0, LINE_IN, TEAL)
    _polyline(lib, m_in, "Linie Parkplatz", [(0, -209.5), (0, HZ0)], 0.0, LINE_IN, BLUE)

    g = Y_PAVE
    line("Meisterschule", LIME, [(-7, HZ1), (-7, -177), (-54, -177), (-54, -148), (-66.5, -148)], LINE_OUT,
         [(-68, -148, g)])
    line("Spielhalle", MAGENTA, [(-5, HZ1), (-5, -175), (-52, -175), (-52, -72), (-66.5, -72)], LINE_OUT,
         [(-68, -72, g)])
    line("Auktionshaus", BRASS, [(5, HZ1), (5, -175), (52, -175), (52, -76), (66.5, -76)], LINE_OUT, [(68, -76, g)])
    line("Credit-Center", PURPLE, [(7, HZ1), (7, -177), (54, -177), (54, -152), (66.5, -152)], LINE_OUT,
         [(68, -152, g)])
    # Amber: Werkstattmeile (um den Meile-Pylon herum), dann entlang des Nordgehwegs zu beiden Toren
    am = line("Werkstattmeile", AMBER, [(-3, HZ1), (-3, -173), (-18.8, -173), (-18.8, -40), (-20.5, -40),
                                         (-20.5, -22.4)], LINE_OUT)
    zl = -21.8
    for x0, x1 in ((-182.5, -165), (-139, 1.4), (2.6, 139), (165, 182.5)):
        _box(lib, am, "Linie", x0, x1, LINE_OUT - 0.1, LINE_OUT, zl - 0.6, zl + 0.6, AMBER, "SmoothPlastic", deco=True)
    for x in (-182.5, 182.5):
        lib.cylinder(am, "Zielscheibe", (x, g + 0.075, -21.5), 0.15, 3, "Y", AMBER, "SmoothPlastic", deco=True)
    # Weiß: Autohaus über Z1 zur Rotunde
    wm = line("Autohaus", LWHITE, [(3, HZ1), (3, -173), (18.8, -173), (18.8, -30), (2, -30), (2, -13)], LINE_OUT)
    _polyline(lib, wm, "Linie", [(2, 13), (2, 34.5)], LINE_OUT - 0.1, LINE_OUT, LWHITE)
    lib.cylinder(wm, "Zielscheibe", (2, g + 0.075, 36), 0.15, 3, "Y", LWHITE, "SmoothPlastic", deco=True)
    # Blau: Parkplatz-Chaos (Nordtür)
    line("Parkplatz-Chaos", BLUE, [(0, HZ0), (0, -225), (-63.5, -225)], LINE_OUT, [(-65, -225, g)])
    # Rost: Schrottplatz (Westtür -> Z12 -> Tor -> Einfahrt, Waage ausgespart)
    rm = line("Schrottplatz", RUST_L, [(HX0, -201), (-139, -201)], LINE_OUT)
    _polyline(lib, rm, "Linie", [(-165, -201), (-178, -201)], -0.95, -0.90, RUST_L)
    _polyline(lib, rm, "Linie", [(-178, -201), (-244, -201)], -0.98, -0.92, RUST_L)
    _polyline(lib, rm, "Linie", [(-272, -201), (-302.5, -201)], -0.98, -0.92, RUST_L)
    lib.cylinder(rm, "Zielscheibe", (-304, -0.98 + 0.075, -201), 0.15, 3, "Y", RUST_L, "SmoothPlastic", deco=True)
    # Türkis: Tuning (Osttür -> Z13 -> Hallentür)
    tm = line("Tuning", TEAL, [(HX1, -201), (139, -201)], LINE_OUT)
    _polyline(lib, tm, "Linie", [(165, -201), (174, -201)], LINE_OUT - 0.1, LINE_OUT, TEAL)
    _polyline(lib, tm, "Linie", [(178, -201), (209.5, -201)], -1.0, -0.94, TEAL)
    lib.cylinder(tm, "Zielscheibe", (211, -1.0 + 0.075, -201), 0.15, 3, "Y", TEAL, "SmoothPlastic", deco=True)

    # Wegweiser
    wf = lib.model(w, "Wegweiser")
    _signpost(lib, wf, 0, -38, [(0, -1, "EMPFANG 140 m"), (-1, -1, "SPIELHALLE 80 m"), (1, -1, "AUKTIONSHAUS 80 m"),
                                (-1, 0, "WERKSTÄTTEN 1–4 190 m"), (1, 0, "WERKSTÄTTEN 5–8 190 m"),
                                (0, 1, "AUTOHAUS 80 m"), (-1, 1, "STADTPARK 300 m"), (1, 1, "TANKSTELLE 300 m")],
              name="Wegweiser Platz")
    _signpost(lib, wf, -128, -190, [(-1, 0, "SCHROTTPLATZ 60 m"), (1, 0, "EMPFANG 85 m"),
                                    (0, 1, "MEISTERSCHULE 45 m"), (0, -1, "PARKPLATZ-CHAOS 60 m")],
              name="Wegweiser Querachse West")
    _signpost(lib, wf, 128, -190, [(1, 0, "TUNING-ZENTRUM 90 m"), (-1, 0, "EMPFANG 85 m"),
                                   (0, 1, "CREDIT-CENTER 45 m"), (0, -1, "PARKPLATZ-CHAOS 60 m")],
              name="Wegweiser Querachse Ost")
    _signpost(lib, wf, -126, -18, [(1, 0, "STADTPLATZ 110 m"), (-1, 0, "WERKSTÄTTEN 1–4 60 m"),
                                   (0, -1, "SCHROTTPLATZ 190 m"), (0, 1, "STADTPARK 180 m")],
              name="Wegweiser Meile West")
    _signpost(lib, wf, 126, -18, [(-1, 0, "STADTPLATZ 110 m"), (1, 0, "WERKSTÄTTEN 5–8 60 m"),
                                  (0, -1, "TUNING-ZENTRUM 190 m"), (0, 1, "TANKSTELLE 180 m")],
              name="Wegweiser Meile Ost")

    # Meile-Verzeichnis-Pylon (-16, 9.5, -34), 6 x 20 x 1.5, Amber-Neonkanten, Text N und S
    pm = lib.model(w, "Meile-Verzeichnis", attrs={"Directory": "meile"})
    px, pz = -16.0, -34.0
    body = _box(lib, pm, "Pylon", px - 3, px + 3, Y_PAVE, 19.5, pz - 0.75, pz + 0.75, SLATE, "Metal")
    for s in (-1, 1):
        x0, x1 = sorted((px + s * 3, px + s * 3.3))
        _box(lib, pm, "Neonkante", x0, x1, Y_PAVE, 19.5, pz - 0.85, pz + 0.85, AMBER, "Neon", deco=True)
    _box(lib, pm, "Kappe", px - 3.5, px + 3.5, 19.5, 19.9, pz - 1.0, pz + 1.0, GRAPHITE, "Metal")
    _box(lib, pm, "Sockel", px - 3.5, px + 3.5, Y_PAVE, -0.1, pz - 1.2, pz + 1.2, BLACK, "Metal")
    for face, gname in (("Back", "Sued"), ("Front", "Nord")):
        g2 = _gui(lib, body, face, 40, name="Verzeichnis_" + gname)
        _frame(lib, g2, "Grund", 0.04, 0.02, 0.92, 0.96, (20, 28, 36), 0, 1)
        _label(lib, g2, "Title", "WERKSTATT-MEILE", 0.06, 0.04, 0.88, 0.07, AMBER, "GothamBlack", "center", 3)
        _label(lib, g2, "Untertitel", "Verzeichnis der Werkstätten", 0.08, 0.11, 0.84, 0.04, WHITE, "GothamBold",
               "center", 3)
        _frame(lib, g2, "Strich", 0.15, 0.165, 0.7, 0.006, AMBER, 0, 2)
        for i in range(8):
            y = 0.2 + i * 0.095
            _frame(lib, g2, "Nummernfeld", 0.08, y, 0.2, 0.075, AMBER, 0, 2)
            _label(lib, g2, "Nummer", str(i + 1), 0.08, y + 0.005, 0.2, 0.065, SLATE, "GothamBlack", "center", 3)
            _label(lib, g2, "Nr%d" % (i + 1), "FREI", 0.32, y + 0.01, 0.62, 0.055, WHITE, "GothamBold", "left", 3)
    return w


# ================================================================ Einstieg
def build(city, lib, tree):
    """Baut Stadtplatz + Ankunftshalle (CITY_SPEC §5, §6 D1/D2) als Model City.Districts.Stadtplatz."""
    dm = lib.model(lib.folder(city, "Districts"), NAME, attrs={"Districts": "D1 Stadtplatz, D2 Ankunftshalle"})
    anim = lib.folder(lib.folder(city, "Animated"), "Stadtplatz")
    with lib.section("D2 Ankunftshalle"):
        build_hall(lib, dm, anim)
    with lib.section("D1 Stadtplatz"):
        build_plaza(lib, dm, anim)
    with lib.section("Wegeleitsystem"):
        build_wayfinding(lib, dm)
    return dm
