"""Autohaus (D8) und Teststrecke (D13) - docs/CITY_SPEC.md §6 D8 / D13, §8, §9.2.

Gebaut wird unter City.Districts.Autohaus (Model mit den Teil-Models Vorplatz, Rotunde, Showroom,
Gebrauchtwagen, Uebergabe, Hinterhof), City.Districts.Teststrecke und City.Animated.Autohaus /
City.Animated.Teststrecke:
  * Drehteller (Anim turntable, 24 s je Umdrehung) mit dem Helden-Auto (super, amber), PrimaryPart = Achse
    ohne Drehung, damit PivotTo um die Hochachse dreht
  * Schiebetüren Rotunde + Showroom hinten (Anim door, Glas/Stiel/Sockelleiste/Griff wie die Ankunftshalle)
  * 4 Fahnen am Vorplatz (Anim flag, ±6°), Startampel an der Start/Ziel-Brücke (Anim startlight, 5 Neon-Lampen)
Stationen dealer / testdrive / track und die Ankunftspunkte dealer / track baut contract.py; hier steht nur die
Kulisse um die Anker (Verkaufstresen, Übergabe-Pult, Tribünen-Kasse).

Höhen-Stapel (§1.2, nie zwei überlappende Oberseiten auf gleicher Höhe):
  Autohaus-Gelände -1.00 (ground_roads; Gebrauchtwagen-Belag bündig -1.00 in einer Aussparung) | Stellflächen,
  Kundenparkplatz, Zufahrt-Asphalt -0.95 | Vorplatz / Tribünenwege -0.50 | Böden Showroom, Rotunden-Sockel,
  Übergabe 0 | Teppiche +0.05
  Teststrecke (3.0 Grand-Prix-Kurs, Mittellinie aus vehicles.py): Belag -0.95 (Geraden + Trapez-Sektoren der Bögen)
  | Kies-Auslauf -1.00 | Ziellinie -0.90 | Kerbs abwechselnd -0.85 / -0.83
Markierungen (Linien, Raster, Stellflächen-Rahmen, Zielflagge) sind SurfaceGui-Frames auf der Oberseite: 0 Parts.
"""
import math

from ..lib import (CF, AMBER, BLACK, GLASS, GRAPHITE, LAMP, RED, SLATE, STEEL, TEAL, TRUSS, WHITE, _color3_el,
                   _sub_el, _udim2_el, fnum, props, set_attrs, yaw_towards)

NAME = "Autohaus"

# ---------------------------------------------------------------- Farben (CITY_SPEC §1.4 Autohaus / Teststrecke)
AH_WHITE = (235, 238, 240)
POLISH = (205, 208, 212)
FORECOURT = (170, 174, 176)
FORECOURT_LINE = (146, 150, 153)
LOT = (96, 100, 102)
PAD = (150, 154, 156)
NEON_WHITE = (232, 246, 249)
HALL_LIGHT = (224, 238, 255)
SCREEN = (27, 72, 82)
SCREEN_TEXT = (121, 225, 206)
DISC_DARK = (36, 40, 46)
TRACK_ASPHALT = (52, 56, 62)
TRACK_RED = (200, 50, 50)
KERB_WHITE = (236, 238, 240)
CONCRETE = (130, 139, 144)
GRASS = (73, 91, 64)
GRASS_IN = (78, 102, 66)
HEDGE = (61, 100, 65)
LEATHER = (38, 42, 48)
BOW_RED = (255, 40, 60)
WALK = (128, 134, 138)

GLASS_T = 0.35


def face_yaw(dx, dz):
    """yaw, bei dem die +Z-Seite (Schildtext, SurfaceGui Back) in Richtung (dx, dz) zeigt"""
    return math.degrees(math.atan2(dx, dz))


# ---------------------------------------------------------------- SurfaceGui-Markierungen (0 Parts)
def _frame(lib, gui, name, pos, size, color, transp=0.0, border=0, border_color=WHITE):
    fr = lib.item(gui, "Frame", name)
    p = props(fr)
    _udim2_el(p, "Size", size[0], 0, size[1], 0)
    _udim2_el(p, "Position", pos[0], 0, pos[1], 0)
    _color3_el(p, "BackgroundColor3", color)
    _sub_el(p, "float", "BackgroundTransparency", fnum(transp))
    _sub_el(p, "int", "BorderSizePixel", str(int(border)))
    if border:
        _color3_el(p, "BorderColor3", border_color)
        _sub_el(p, "token", "BorderMode", "2")
    return fr


def paint(lib, part, rects, px=10, name="Markierung"):
    """Farbflächen auf der Oberseite eines Parts. rects: (u0, v0, u1, v1, Farbe) in Anteilen
    (u entlang lokal X, v entlang lokal Z) oder (…, Farbe, 'rahmen', Pixel) für einen Rahmen."""
    gui = lib.surface_text(part, None, face="Top", name=name, px_per_stud=px)
    for i, r in enumerate(rects):
        u0, v0, u1, v1, col = r[:5]
        if len(r) > 5 and r[5] == "rahmen":
            _frame(lib, gui, "Rahmen%d" % i, (u0, v0), (u1 - u0, v1 - v0), col, 1.0, r[6], col)
        else:
            _frame(lib, gui, "Linie%d" % i, (u0, v0), (u1 - u0, v1 - v0), col)
    return gui


# ---------------------------------------------------------------- kleine Bausteine
def price_stand(lib, parent, x, fy, z, yaw, model, price, badge, badge_color=TEAL):
    """Preisaufsteller: Stahlstiel, Schiefertafel 2 x 3 (Modell, Preis in Cr, Level-Abzeichen). 2 Parts."""
    m = lib.model(parent, "Preisschild")
    lib.cylinder(m, "Stiel", (x, fy + 1.15, z), 2.3, 0.25, "Y", STEEL, "Metal", deco=True)
    plate = lib.part(m, "Tafel", (2, 3, 0.15), CF.at(x, fy + 3.8, z, yaw), SLATE, "SmoothPlastic", deco=True)
    gui = lib.surface_text(plate, None, px_per_stud=100)
    lib.text_label(gui, model, WHITE, "GothamBold", "Modell", None, (0.9, 0.26), (0.05, 0.05))
    lib.text_label(gui, price, AMBER, "GothamBlack", "Preis", None, (0.9, 0.24), (0.05, 0.36))
    lib.text_label(gui, badge, WHITE, "GothamBold", "Level", badge_color, (0.8, 0.16), (0.1, 0.72))
    return m


def door_leaf(lib, parent, nm, center, size, lift, stile_side, door):
    """Schiebeflügel (Anim door) entlang X wie in der Ankunftshalle: Glas, Stiel, Sockelleiste, Griff."""
    m = lib.model(parent, nm, attrs={"Anim": "door", "Axis": "X", "Lift": lift, "Period": 10, "Door": door,
                                     "OpenRange": 12, "OpenTime": 0.6, "Mode": "slide"})
    cx, cy, cz = center
    sx, sy, sz = size
    gl = lib.part(m, "Glas", (sx - 0.1, sy - 0.1, sz), CF(cx, cy, cz), GLASS, "Glass", transparency=GLASS_T,
                  collide=False, cast_shadow=False)
    lib.set_primary(m, gl)
    ex = cx + stile_side * (sx / 2 - 0.2)
    # Rahmenteile je Seite >= 0.05 vor der Glasfläche (kein Flimmern)
    lib.part(m, "Stiel", (0.4, sy, sz + 0.12), CF(ex, cy, cz), AH_WHITE, "Metal", collide=False)
    lib.part(m, "Sockelleiste", (sx - 0.4, 0.4, sz + 0.1), CF(cx - stile_side * 0.2, cy - sy / 2 + 0.2, cz),
             STEEL, "Metal", collide=False)
    lib.part(m, "Griff", (0.12, 2.6, sz + 0.24), CF(ex - stile_side * 0.5, cy, cz), BLACK, "Metal", deco=True)
    return m


def plant(lib, parent, x, fy, z, s=1.0):
    """Kübelpflanze, 2 Parts"""
    m = lib.model(parent, "Pflanze")
    lib.cylinder(m, "Kuebel", (x, fy + 0.9 * s, z), 1.8 * s, 2.0 * s, "Y", AH_WHITE, "SmoothPlastic")
    lib.ball(m, "Laub", (x, fy + 1.8 * s + 1.1 * s, z), 2.8 * s, (65, 104, 66), "Grass", deco=True)
    return m


# ================================================================ Autohaus (D8)
RC_X, RC_Z = 0.0, 60.0       # Rotundenmitte
R_VERT = 22.0                # Umkreis
R_APO = 21.25                # Inkreis (Glasflächen)
R_TOP = 32.0                 # Glasoberkante / Dachunterseite


def _vert(theta):
    t = math.radians(theta)
    return (RC_X + R_VERT * math.sin(t), RC_Z - R_VERT * math.cos(t))


def _shrink(a, b, d):
    """Strecke a-b an beiden Enden um d kürzen"""
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    return (a[0] + ux * d, a[1] + uz * d), (b[0] - ux * d, b[1] - uz * d)


def _pane(lib, parent, name, a, b, theta, y0, y1, thick=0.4):
    cx, cz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    w = math.hypot(b[0] - a[0], b[1] - a[1])
    return lib.part(parent, name, (w, y1 - y0, thick), CF.at(cx, (y0 + y1) / 2, cz, 180 - theta), GLASS, "Glass",
                    transparency=GLASS_T, cast_shadow=False)


def build_forecourt(dm, anim, lib):
    m = lib.model(dm, "Vorplatz")
    # Fußgänger-Vorplatz X -64..64, Z 23..38.75, Pflaster -0.5 (helles Beton) mit Fugenraster
    pv = lib.box(m, "Vorplatz-Pflaster", -64, 64, -1.0, -0.5, 23, 38.75, FORECOURT, "Concrete")
    rects = []
    for k in range(1, 16):
        u = k * 8 / 128.0
        rects.append((u - 0.0012, 0.0, u + 0.0012, 1.0, FORECOURT_LINE))
    for k in (1, 2, 3):
        v = k * 3.9375 / 15.75
        rects.append((0.0, v - 0.008, 1.0, v + 0.008, FORECOURT_LINE))
    paint(lib, pv, rects, px=12, name="Fugen")
    # Pflanzkübel beidseits der Achse
    for sx in (-1, 1):
        x = sx * 15
        lib.box(m, "Pflanzkasten", x - 3, x + 3, -0.5, 0.7, 29.5, 32.5, AH_WHITE, "SmoothPlastic")
        lib.box(m, "Hecke", x - 2.6, x + 2.6, 0.7, 2.3, 29.9, 32.1, HEDGE, "Grass", deco=True)
    # Fahnenmasten (Anim flag, ±6°) bei X ±40, ±52, Z 30
    flags = lib.folder(anim, "Fahnen")
    cols = [(TEAL, AH_WHITE), (AH_WHITE, TEAL), (AH_WHITE, TEAL), (TEAL, AH_WHITE)]
    for i, x in enumerate((-52, -40, 40, 52)):
        cloth, stripe = cols[i]
        f = lib.model(flags, "Fahne_%d" % (i + 1), attrs={"Anim": "flag", "Swing": 6, "Period": 3.2})
        lib.cylinder(f, "Mastfuss", (x, -0.2, 30), 0.6, 1.4, "Y", BLACK, "Metal")
        lib.cylinder(f, "Fahnenmast", (x, 9.8, 30), 19.4, 0.4, "Y", STEEL, "Metal")
        lib.ball(f, "Mastspitze", (x, 19.85, 30), 0.7, AMBER, "Metal", deco=True)
        tuch = lib.part(f, "Fahne", (6, 4, 0.1), CF(x + 3.2, 16.8, 30), cloth, "Fabric", deco=True)
        # PrimaryPart ohne Drehung: CityClient dreht die Fahne um die Hochachse des Pivots (am Mast)
        lib.set_primary(f, tuch)
        lib.part(f, "Fahnenstreifen", (5.9, 0.6, 0.2), CF(x + 3.2, 15.4, 30), stripe, "Fabric", deco=True)
        for face in ("Back", "Front"):
            lib.surface_text(tuch, "AUTOHAUS", face=face, text_color=stripe, font="GothamBlack",
                             name="Aufdruck" + face)
    # Monolith "AUTOHAUS" 6 x 18 x 1.5 bei (80, ·, 30)
    mo = lib.model(m, "Monolith")
    lib.box(mo, "Sockel", 76.4, 83.6, -1.0, -0.4, 28.8, 31.2, SLATE, "Metal")
    lib.box(mo, "Stele", 77, 83, -0.4, 17, 29.25, 30.75, AH_WHITE, "SmoothPlastic")
    lib.box(mo, "Leuchtkante", 77.2, 82.8, 17, 17.3, 29.45, 30.55, TEAL, "Neon", deco=True)
    lib.sign(mo, "A\nU\nT\nO\nH\nA\nU\nS", (3.6, 13.5), CF.at(80, 8.6, 29.15, 180), TEAL, SLATE,
             name="Steleschild", font="GothamBlack")
    s = lib.part(mo, "Stelenband", (4.6, 1.4, 0.2), CF.at(80, 1.4, 30.85, 0), SLATE, deco=True)
    lib.surface_text(s, "AUTOHAUS", text_color=TEAL)
    return m


def build_rotunda(dm, anim, lib):
    m = lib.model(dm, "Rotunde")
    # Sockel (poliert) unter der Nordhälfte; stößt an die Showroom-Bodenplatte bei Z 60
    lib.box(m, "Rotundensockel", -22, 22, -1, 0, 37.6, 60, POLISH, "SmoothPlastic", reflectance=0.12)
    # Pfosten an den 6 Ecken der Nordhälfte (volle Höhe) und den 6 Ecken der Südhälfte (Obergaden 27..32)
    for th in (-75, -45, -15, 15, 45, 75):
        vx, vz = _vert(th)
        lib.part(m, "Pfosten", (1, R_TOP, 1), CF.at(vx, R_TOP / 2, vz, 180 - th), AH_WHITE, "Metal")
    for th in (105, 135, 165, -105, -135, -165):
        vx, vz = _vert(th)
        lib.part(m, "Obergadenpfosten", (1, R_TOP - 27, 1), CF.at(vx, (27 + R_TOP) / 2, vz, 180 - th), AH_WHITE,
                 "Metal")
    # Glasflächen Nord (0 = Oberlicht über der Tür), ±30, ±60
    a, b = _shrink(_vert(-15), _vert(15), 0.5)
    _pane(lib, m, "Oberlicht", a, b, 0, 14, R_TOP)
    for th in (-60, -30, 30, 60):
        a, b = _shrink(_vert(th - 15), _vert(th + 15), 0.5)
        _pane(lib, m, "Glasflaeche", a, b, th, 0, R_TOP)
    # Füllscheiben an den ±90-Flächen bis zur Showroom-Glasfront (Z 60)
    for sx in (-1, 1):
        x = sx * R_APO
        _pane(lib, m, "Fuellscheibe", (x, _vert(75)[1] + 0.5), (x, RC_Z), sx * 90, 0, R_TOP)
        _pane(lib, m, "Obergaden", (x, RC_Z), (x, _vert(105)[1] - 0.5), sx * 90, 27, R_TOP)
    for th in (120, 150, 180, -120, -150):
        a, b = _shrink(_vert(th - 15), _vert(th + 15), 0.5)
        _pane(lib, m, "Obergaden", a, b, th, 27, R_TOP)
    # Türsturz (Laufschiene der Schiebetür) vor der Nordfläche
    lib.box(m, "Tuersturz", -10.6, 10.6, 14, 15.2, 37.6, 38.3, AH_WHITE, "Metal")
    lib.box(m, "Tuerleuchte", -10.4, 10.4, 14.3, 14.6, 37.45, 37.6, TEAL, "Neon", deco=True)
    # Dach: Zylinder Ø46 bei Y 32..33, Neon-Ring Ø46.4 (nur der äußere Rand sichtbar)
    lib.cylinder(m, "Rotundendach", (RC_X, 32.5, RC_Z), 1.0, 46, "Y", AH_WHITE, "SmoothPlastic")
    lib.cylinder(m, "Dachring", (RC_X, 32.5, RC_Z), 0.3, 46.4, "Y", TEAL, "Neon", deco=True)
    # Dachschild "AUTOHAUS" 36 x 5 bei Y 33.5..38.5, Text nach Norden (weiße Tafel, Petrol-Schrift)
    for sx in (-1, 1):
        lib.box(m, "Schildstuetze", sx * 12 - 0.3, sx * 12 + 0.3, 33, 37.5, 50.1, 50.9, STEEL, "Metal")
    sg = lib.sign(m, "AUTOHAUS", (36, 5), CF.at(0, 36, 50, 180), TEAL, AH_WHITE, name="Dachschild",
                  font="GothamBlack")
    lib.surface_text(sg, "AUTOHAUS", face="Front", text_color=TEAL, font="GothamBlack", name="Rueckseite")
    # Helden-Spot über dem Drehteller
    lib.box(m, "Spot-Abhaengung", -0.15, 0.15, 30.5, 32, 57.85, 58.15, STEEL, "Metal", deco=True)
    spot = lib.part(m, "Heldenspot", (2, 1, 2), CF(0, 30, 58), BLACK, "Metal", deco=True)
    lib.spot_light(spot, 30, 1.4, (255, 244, 230), 60, "Bottom", True, name="Heldenlicht")
    # Drehteller (Anim turntable, 24 s) mit Helden-Auto
    tt = lib.model(anim, "Drehteller", attrs={"Anim": "turntable", "Speed": 15, "Period": 24})
    piv = lib.part(tt, "Achse", (1, 0.4, 1), CF(0, 0.3, 58), DISC_DARK, "SmoothPlastic", transparency=1, deco=True)
    lib.set_primary(tt, piv)
    lib.cylinder(tt, "Drehscheibe", (0, 0.3, 58), 0.6, 22, "Y", DISC_DARK, "Metal", reflectance=0.08)
    lib.cylinder(tt, "Leuchtring", (0, 0.3, 58), 0.3, 22.4, "Y", AMBER, "Neon", deco=True)
    with lib.section("D8 Autohaus (Autos)"):
        lib.clone_car(tt, "super", CF.at(0, 0.6, 58, 20), AMBER, name="Heldenauto_Aureon",
                      attrs={"Showcar": True, "Price": 245000})
    price_stand(lib, m, 13, 0, 49, face_yaw(-13, -11), "Vektor Aureon V12", "245.000 Cr", "ab Level 30",
                AMBER)
    # Schiebetür Nordfläche 10 x 14 (zwei Flügel, außen auf dem Sockel)
    doors = lib.folder(anim, "Tueren")
    door_leaf(lib, doors, "Rotundentuer_W", (-2.6, 7, 38.0), (5.2, 14, 0.3), -5.0, 1, "Rotunde")
    door_leaf(lib, doors, "Rotundentuer_O", (2.6, 7, 38.0), (5.2, 14, 0.3), 5.0, -1, "Rotunde")
    return m


def build_showroom(dm, anim, lib):
    m = lib.model(dm, "Showroom")
    X0, X1, Z0, Z1 = -60, 60, 60, 111
    fl = lib.box(m, "Showroomboden", X0, X1, -1, 0, Z0, Z1, POLISH, "SmoothPlastic", reflectance=0.12)
    rects = []
    for k in range(1, 20):
        u = k * 6 / 120.0
        rects.append((u - 0.0008, 0, u + 0.0008, 1, (186, 190, 195)))
    for k in range(1, 9):
        v = k * 6 / 51.0
        rects.append((0, v - 0.002, 1, v + 0.002, (186, 190, 195)))
    paint(lib, fl, rects, px=8, name="Fliesenfugen")
    # --- Nordfront: Glas X -60..-21.25 / 21.25..60 (auf der Bodenplatte), Pfosten außen, Kämpfer Y 13
    for sx in (-1, 1):
        xa, xb = sorted((sx * 21.25, sx * 60))
        lib.box(m, "Glasfront_Nord", xa, xb, 0, 26, 60, 60.4, GLASS, "Glass", transparency=GLASS_T, cast_shadow=False)
        for x in (24, 36, 48):
            lib.box(m, "Sprosse", sx * x - 0.3, sx * x + 0.3, -1, 26, 59.4, 60, AH_WHITE, "Metal")
        ka, kb = sorted((sx * 21.6, sx * 59.9))
        lib.box(m, "Kaempfer", ka, kb, 12.8, 13.2, 59.5, 59.95, AH_WHITE, "Metal")
        fa, fb = sorted((sx * 21.45, sx * 61.2))
        lib.box(m, "Blende_Nord", fa, fb, 26, 31, 59.4, 60, AH_WHITE, "SmoothPlastic")
        la, lb = sorted((sx * 21.6, sx * 61.0))
        lib.box(m, "Blendenleuchte", la, lb, 25.7, 25.95, 59.3, 59.55, TEAL, "Neon", deco=True)
    # Innenblende zur Rotunde: die Deckenstufe 32 -> 26 bei Z 60 bekommt eine weiße Blende mit Leuchtband
    lib.box(m, "Blende_Rotunde", -21.05, 21.05, 25, 27, 59.4, 60, AH_WHITE, "SmoothPlastic")
    lib.box(m, "Blendenleuchte", -21.0, 21.0, 25.2, 25.45, 59.25, 59.4, TEAL, "Neon", deco=True)
    # --- Ost/West: Glasvorhang, Pfosten außen, Eckstützen
    for sx in (-1, 1):
        xa, xb = sorted((sx * 59.6, sx * 60))
        lib.box(m, "Glasfront_Seite", xa, xb, 0, 26, 60.4, 110.2, GLASS, "Glass", transparency=GLASS_T,
                cast_shadow=False)
        oa, ob = sorted((sx * 60, sx * 60.6))
        for z in (72, 84, 96):
            lib.box(m, "Sprosse", oa, ob, -1, 26, z - 0.3, z + 0.3, AH_WHITE, "Metal")
        ka, kb = sorted((sx * 60.05, sx * 60.5))
        lib.box(m, "Kaempfer", ka, kb, 12.8, 13.2, 60.5, 110.0, AH_WHITE, "Metal")
        ca, cb = sorted((sx * 60, sx * 61.2))
        lib.box(m, "Eckstuetze", ca, cb, -1, 26, 58.8, 60, AH_WHITE, "Metal")
        lib.box(m, "Eckstuetze", ca, cb, -1, 26, 110, 111.2, AH_WHITE, "Metal")
        pa, pb = sorted((sx * 59.2, sx * 60))
        lib.box(m, "Attika", pa, pb, 27, 31, 60, 111, AH_WHITE, "SmoothPlastic")
    # --- Süd: weiße Wand mit Hintertür X -6..6 (Höhe 14)
    lib.box(m, "Suedwand", -60, -6, 0, 26, 110.2, 111, AH_WHITE, "Metal")
    lib.box(m, "Suedwand", 6, 60, 0, 26, 110.2, 111, AH_WHITE, "Metal")
    lib.box(m, "Tuersturz_Sued", -6, 6, 14, 26, 110.2, 111, AH_WHITE, "Metal")
    lib.box(m, "Attika", -59.2, 59.2, 27, 31, 110.2, 111, AH_WHITE, "SmoothPlastic")
    lib.box(m, "Dach", X0, X1, 26, 27, Z0, Z1, GRAPHITE, "SmoothPlastic")
    lib.box(m, "Tuerstufe", -7, 7, -1, -0.25, 111, 113, POLISH, "Concrete")
    s = lib.sign(m, "AUTOHAUS", (12, 2.6), CF.at(0, 19, 111.1, 0), TEAL, SLATE, name="Hinterschild",
                 sub="Hintereingang · Teststrecke →")
    doors = lib.folder(anim, "Tueren")
    door_leaf(lib, doors, "Hintertuer_W", (-3.0, 7, 109.95), (6.0, 14, 0.3), -5.8, 1, "Showroom hinten")
    door_leaf(lib, doors, "Hintertuer_O", (3.0, 7, 109.95), (6.0, 14, 0.3), 5.8, -1, "Showroom hinten")
    # --- Decke: 3 Leuchten mit PointLight (Range 34) + 2 Lichtlinien
    for i, (x, z) in enumerate(((-35, 85), (35, 85), (0, 100))):
        lib.box(m, "Leuchtengehaeuse", x - 4.2, x + 4.2, 25.2, 26, z - 0.8, z + 0.8, AH_WHITE, "Metal", deco=True)
        bar = lib.box(m, "Leuchte", x - 4, x + 4, 25.0, 25.2, z - 0.6, z + 0.6, NEON_WHITE, "Neon", deco=True)
        lib.point_light(bar, 34, 0.9, HALL_LIGHT, name="Showroomlicht")
    for sx in (-1, 1):
        lib.box(m, "Lichtlinie", sx * 20 - 0.2, sx * 20 + 0.2, 25.85, 26, 64, 108, NEON_WHITE, "Neon", deco=True)
    # --- 4 Podeste mit Neon-Sockel und Ausstellungsautos (Nase zur Mitte / zum Eingang)
    cars = [("gt_coupe", (38, 78, 140), -44, 72, -30, "Vektor GTX", "145.000 Cr", "ab Level 24"),
            ("electric", AH_WHITE, 44, 72, 30, "Nord Elys E9", "310.000 Cr", "ab Level 38"),
            ("crossover", (60, 66, 74), -44, 93, -30, "Komet Urban", "32.000 Cr", "ab Level 7"),
            ("sedan", (110, 30, 40), 44, 93, 30, "Nord R4", "26.000 Cr", "ab Level 4")]
    for body, col, x, z, yaw, model, price, badge in cars:
        lib.part(m, "Podestlicht", (14.4, 0.1, 18.1), CF.at(x, 0.05, z, yaw), TEAL, "Neon", deco=True)
        lib.part(m, "Podest", (14, 0.3, 18), CF.at(x, 0.25, z, yaw), AH_WHITE, "SmoothPlastic", reflectance=0.1)
        with lib.section("D8 Autohaus (Autos)"):
            lib.clone_car(m, body, CF.at(x, 0.4, z, yaw), col, name="Ausstellung_" + body,
                          attrs={"Showcar": True, "Price": int(price.split(" ")[0].replace(".", ""))})
        sx = -1 if x > 0 else 1
        price_stand(lib, m, x + sx * 12.5, 0, z + 5, face_yaw(sx, -1), model, price, badge)
    # --- Verkaufstresen X -30..-10, Z 104..108 (Station dealer bei (-20,3,100), Spielerseite N)
    lib.box(m, "Beratungsteppich", -29, -11, 0, 0.05, 90, 103.6, (34, 92, 90), "Fabric")
    lib.box(m, "Verkaufstresen", -30, -10, 0, 3.2, 104, 108, AH_WHITE, "Metal")
    lib.box(m, "Tresenplatte", -30.3, -9.7, 3.2, 3.45, 103.7, 108.3, BLACK, "SmoothPlastic", reflectance=0.2)
    lib.box(m, "Tresenleuchte", -29.5, -10.5, 0.3, 0.5, 103.85, 104, TEAL, "Neon", deco=True)
    lib.box(m, "Monitorfuss", -24.1, -23.9, 3.45, 3.7, 106.3, 106.5, STEEL, "Metal", deco=True)
    mon = lib.part(m, "Monitor", (2.6, 1.5, 0.15), CF.at(-24, 4.45, 106.3, 180), SCREEN, "SmoothPlastic", deco=True)
    lib.surface_text(mon, "AUTOHAUS\nJetzt geöffnet", text_color=SCREEN_TEXT, name="Bildschirm")
    lib.sign(m, "VERKAUF · BERATUNG", (14, 3), CF.at(-20, 10.5, 110.1, 180), TEAL, SLATE, name="Tresenschild",
             sub="Neuwagen · Meine Autos · Probefahrt")
    # --- Lounge X 20..40, Z 104..110
    lib.box(m, "Loungeteppich", 20, 40, 0, 0.05, 100, 109.6, (70, 76, 84), "Fabric")
    lib.box(m, "Sofa", 22, 38, 0.05, 1.5, 106.4, 109.2, LEATHER, "Fabric")
    lib.box(m, "Sofalehne", 22, 38, 0.05, 3.2, 109.2, 110.1, LEATHER, "Fabric")
    lib.cylinder(m, "Tischfuss", (30, 0.6, 102.5), 1.1, 1.0, "Y", STEEL, "Metal")
    lib.part(m, "Couchtisch", (6, 0.2, 3), CF(30, 1.25, 102.5), GLASS, "Glass", transparency=0.2)
    lib.sign(m, "KUNDENLOUNGE", (10, 2), CF.at(30, 10, 110.1, 180), AH_WHITE, SLATE, name="Loungeschild",
             sub="Kaffee · Probefahrt-Termine", bolts=False)
    # --- Pflanzen
    for x, z in ((-57, 107.5), (57, 107.5)):
        plant(lib, m, x, 0, z)
    # --- Hinterer Fußweg zur Südring-Seite (Z 113..178, Pflaster -0.5)
    lib.box(m, "Hinterweg", -4, 4, -1.0, -0.5, 113, 178, WALK, "Concrete")
    return m


def build_used_lot(dm, lib):
    m = lib.model(dm, "Gebrauchtwagen")
    # Belag bündig in der Aussparung der Autohaus-Bodenplatte (ground_roads.GROUND_INSETS), Oberseite -1.00
    lib.box(m, "Gebrauchtwagen-Belag", -126, -68, -1.3, -1.0, 30, 150, LOT, "Concrete")
    lib.box(m, "Hecke", -70, -68, -1.0, 1.6, 36, 144, HEDGE, "Grass")
    cars = [("hot_hatch", (200, 50, 50), 46, "Komet S2", "11.900 Cr", "gebraucht · Level 3"),
            ("wagon", (170, 176, 180), 76, "Nord Atlas Tourer", "33.500 Cr", "gebraucht · Level 10"),
            ("compact", (47, 169, 163), 106, "Komet C1", "4.500 Cr", "gebraucht · Level 1"),
            ("sport", (240, 190, 40), 136, "Vektor RS", "68.000 Cr", "gebraucht · Level 18")]
    for body, col, z, model, price, badge in cars:
        pad = lib.part(m, "Stellflaeche", (12, 0.05, 21), CF.at(-97, -0.975, z, -45), PAD, "Concrete")
        paint(lib, pad, [(0, 0, 1, 1, WHITE, "rahmen", 4)], px=10, name="Rahmen")
        with lib.section("D8 Autohaus (Autos)"):
            lib.clone_car(m, body, CF.at(-97, -0.95, z, -45), col, name="Gebraucht_" + body,
                          attrs={"Showcar": True, "Used": True})
        price_stand(lib, m, -80.5, -1.0, z + 3, face_yaw(1, -1), model, price, badge, (200, 110, 40))
    # Wimpelkette an 3 Masten (Z 60 / 90 / 120); an den Masten Z 60 und Z 120 die Platzleuchten
    tops = []
    for z in (60, 90, 120):
        lib.cylinder(m, "Wimpelmast", (-97, -1.0 + 7.28, z), 14.56, 0.35, "Y", STEEL, "Metal")
        tops.append((-97, 13.3, z))
        if z in (60, 120):
            head = lib.part(m, "Platzleuchte", (1.6, 0.4, 1.6), CF(-97, 13.73, z), LAMP, "SmoothPlastic", deco=True)
            set_attrs(head, {"NightNeon": True})
            lib.point_light(head, 30, 0.9, LAMP, name="Platzlicht")
        else:
            lib.ball(m, "Mastkugel", (-97, 13.9, z), 0.8, AMBER, "Metal", deco=True)
    pcol = [TRACK_RED, AMBER, AH_WHITE, TEAL]
    k = 0
    for a, b in zip(tops, tops[1:]):
        mid = (a[0], a[1] - 2.0, (a[2] + b[2]) / 2)
        for p, q in ((a, mid), (mid, b)):
            lib.beam(m, "Wimpelschnur", p, q, 0.08, WHITE, "Fabric", deco=True)
            for t in (0.33, 0.72):
                x = p[0]
                y = p[1] + (q[1] - p[1]) * t
                z = p[2] + (q[2] - p[2]) * t
                lib.wedge(m, "Wimpel", (0.05, 1.1, 1.0), CF(x, y - 0.6, z) * CF.angles(math.pi, 0, 0), pcol[k % 4],
                          "Fabric", deco=True)
                k += 1
    # Schild "JUNGE GEBRAUCHTE" bei (-97, ·, 26), Text nach Norden
    for x in (-105, -89):
        lib.cylinder(m, "Schildpfosten", (x, -1.0 + 5.5, 26.35), 11, 0.5, "Y", STEEL, "Metal")
    lib.sign(m, "JUNGE GEBRAUCHTE", (18, 3.4), CF.at(-97, 8.3, 26, 180), AMBER, SLATE, name="Platzschild",
             sub="geprüft · mit Garantie · faire Preise")
    return m


def build_handover(dm, lib):
    m = lib.model(dm, "Uebergabe")
    X0, X1, Z0, Z1 = 80, 122, 56, 96
    T = 0.8
    fl = lib.box(m, "Hallenboden", X0, X1, -1, 0, Z0, Z1, POLISH, "SmoothPlastic", reflectance=0.12)
    # Übergabe-Bucht (Petrol-Rahmen) um das Auto bei (106, 76) + Laufweg zum Pult
    fx = lambda x: (x - X0) / (X1 - X0)
    fz = lambda z: (z - Z0) / (Z1 - Z0)
    paint(lib, fl, [(fx(97), fz(69), fx(117), fz(83), TEAL, "rahmen", 5),
                    (fx(82), fz(75.6), fx(96.5), fz(76.4), AMBER)], px=10, name="Bucht")
    lib.box(m, "Nordwand", X0, X1, 0, 28, Z0, Z0 + T, AH_WHITE, "Metal")
    lib.box(m, "Suedwand", X0, X1, 0, 28, Z1 - T, Z1, AH_WHITE, "Metal")
    lib.box(m, "Ostwand", X1 - T, X1, 0, 28, Z0 + T, Z1 - T, AH_WHITE, "Metal")
    lib.box(m, "Westwand", X0, X0 + T, 0, 28, Z0 + T, 64, AH_WHITE, "Metal")
    lib.box(m, "Westwand", X0, X0 + T, 0, 28, 88, Z1 - T, AH_WHITE, "Metal")
    lib.box(m, "Torsturz", X0, X0 + T, 20, 28, 64, 88, AH_WHITE, "Metal")
    lib.box(m, "Torleuchte", X0 - 0.2, X0 + 0.2, 19.6, 20, 64, 88, TEAL, "Neon", deco=True)
    lib.box(m, "Dach", X0 + T, X1 - T, 24, 25, Z0 + T, Z1 - T, GRAPHITE, "SmoothPlastic")
    lib.sign(m, "ÜBERGABE · TESTFAHRT", (20, 3.6), CF.at(X0 - 0.1, 23.9, 76, -90), TEAL, SLATE,
             name="Torschild", sub="Schlüsselübergabe · Probefahrt")
    # Licht (101, 23, 76) + 2 Deckenlinien
    lib.box(m, "Leuchtengehaeuse", 96.8, 105.2, 23.2, 24, 75.2, 76.8, AH_WHITE, "Metal", deco=True)
    bar = lib.box(m, "Leuchte", 97, 105, 22.9, 23.2, 75.4, 76.6, NEON_WHITE, "Neon", deco=True)
    lib.point_light(bar, 30, 0.9, HALL_LIGHT, name="Uebergabelicht")
    for z in (64, 88):
        lib.box(m, "Lichtlinie", 86, 118, 23.85, 24, z - 0.2, z + 0.2, NEON_WHITE, "Neon", deco=True)
    # Auto mit roter Neon-Schleife (compact amber, Nase West)
    with lib.section("D8 Autohaus (Autos)"):
        car_cf = CF.at(106, 0, 76, 90)
        lib.clone_car(m, "compact", car_cf, AMBER, name="Uebergabe_compact", attrs={"Showcar": True})
    bow = lib.model(m, "Schleife")
    lib.part(bow, "Band", (0.6, 0.06, 5.0), car_cf * CF(0, 5.32, 1.0), BOW_RED, "Neon", deco=True)
    lib.part(bow, "Band", (6.9, 0.06, 0.6), car_cf * CF(0, 5.33, 1.0), BOW_RED, "Neon", deco=True)
    for s in (-1, 1):
        lib.part(bow, "Schlaufe", (1.1, 0.8, 0.3), car_cf * CF(s * 0.65, 5.75, 1.0) * CF.angles(0, 0, s * 0.6),
                 BOW_RED, "Neon", deco=True)
    # Übergabe-Pult (Station testdrive bei (90,3,70), Spielerseite W)
    lib.box(m, "Uebergabepult", 91, 94, 0, 3.2, 66.5, 73.5, AH_WHITE, "Metal")
    lib.box(m, "Pultplatte", 90.8, 94.2, 3.2, 3.4, 66.3, 73.7, BLACK, "SmoothPlastic", reflectance=0.2)
    scr = lib.part(m, "Pultmonitor", (2.2, 1.4, 0.15), CF.at(93, 4.1, 70, -90), SCREEN, "SmoothPlastic", deco=True)
    lib.surface_text(scr, "PROBEFAHRT\n60 Sekunden", text_color=SCREEN_TEXT, name="Bildschirm")
    lib.sign(m, "SCHLÜSSELÜBERGABE", (14, 2.8), CF.at(101, 11, Z0 + T + 0.1, 0), TEAL, SLATE, name="Wandschild",
             sub="Neuwagen abholen · Probefahrt buchen", bolts=False)
    # Zufahrt: Meile-Absenkung (X 92..108) -> vor das offene Westtor -> Autohaus-Zufahrt (R9)
    for nm, x0, x1, z0, z1 in (("Zufahrt", 92, 108, 23, 40), ("Zufahrt", 64, 108, 40, 56),
                               ("Torvorfeld", 64, 80, 56, 96), ("Zufahrt", 64, 92, 96, 104)):
        lib.box(m, nm, x0, x1, -1.25, -0.95, z0, z1, (46, 52, 59), "Asphalt")
    lib.wedge(m, "Torrampe", (24, 0.95, 6), CF.at(77, -0.475, 76, 90), POLISH, "Concrete")
    return m


def flag_pole(lib, parent, name, x, fy, z, cloth, stripe, text="AUTOHAUS", h=19.4):
    """Fahnenmast mit Tuch (Anim flag, ±6°), 5 Parts; Tuch nach +X"""
    f = lib.model(parent, name, attrs={"Anim": "flag", "Swing": 6, "Period": 3.2})
    lib.cylinder(f, "Mastfuss", (x, fy + 0.3, z), 0.6, 1.4, "Y", BLACK, "Metal")
    lib.cylinder(f, "Fahnenmast", (x, fy + 0.6 + h / 2, z), h, 0.4, "Y", STEEL, "Metal")
    top = fy + 0.6 + h
    lib.ball(f, "Mastspitze", (x, top + 0.35, z), 0.7, AMBER, "Metal", deco=True)
    tuch = lib.part(f, "Fahne", (6, 4, 0.1), CF(x + 3.2, top - 3.0, z), cloth, "Fabric", deco=True)
    lib.set_primary(f, tuch)
    lib.part(f, "Fahnenstreifen", (5.9, 0.6, 0.2), CF(x + 3.2, top - 4.4, z), stripe, "Fabric", deco=True)
    for face in ("Back", "Front"):
        lib.surface_text(tuch, text, face=face, text_color=stripe, font="GothamBlack", name="Aufdruck" + face)
    return f


def build_backyard(dm, anim, lib):
    """Hinterhof X -60..90, Z 113..178 (bisher leere Betonfläche): Kundenparkplatz mit Lite-Autos, Baumhain mit
    Bänken beidseits des Hinterwegs, Aufbereitungs-Carport, 3 Fahnen zum Südring."""
    m = lib.model(dm, "Hinterhof")
    # Kundenparkplatz X 14..58, Z 124..172 (Belag -0.95), 2 x 4 Buchten, Linien als SurfaceGui (0 Parts)
    x0, x1, z0, z1 = 14, 58, 124, 172
    pad = lib.box(m, "Kundenparkplatz", x0, x1, -1.0, -0.95, z0, z1, LOT, "Concrete")
    rects = []
    for k in range(5):
        u = k * 11 / (x1 - x0)
        for v0, v1 in ((0.04, 0.44), (0.56, 0.96)):
            rects.append((max(0, u - 0.004), v0, min(1, u + 0.004), v1, WHITE))
    rects.append((0.3, 0.485, 0.7, 0.515, AMBER))
    paint(lib, pad, rects, px=8, name="Buchten")
    parked = [("sedan", (60, 66, 74), 19.5, 136, 0), ("hot_hatch", (200, 50, 50), 41.5, 136, 0),
              ("wagon", AH_WHITE, 30.5, 160, 180), ("crossover", (38, 78, 140), 52.5, 160, 180)]
    for body, col, x, z, yaw in parked:
        lib.lite_car(m, body, CF.at(x, -0.95, z, yaw), col, name="Kundenauto_" + body, attrs={"Parked": True})
    lib.sign(m, "KUNDENPARKPLATZ", (10, 1.8), CF.at(36, 3.4, z0 - 0.6, 180), AMBER, SLATE, name="Parkschild",
             sub="nur für Kunden des Autohauses")
    for x in (31.8, 40.2):
        lib.box(m, "Schildpfosten", x - 0.15, x + 0.15, -0.95, 2.5, z0 - 0.75, z0 - 0.45, STEEL, "Metal")
    # Baumhain West (X -52..-12) mit Pflanzinseln und Bänken zum Hinterweg
    for i, (x, z) in enumerate(((-50, 130), (-32, 128), (-14, 134), (-46, 156), (-26, 160), (-12, 168))):
        lib.box(m, "Pflanzinsel", x - 2, x + 2, -1.0, -0.6, z - 2, z + 2, AH_WHITE, "Concrete")
        lib.tree_lite(m, x, -0.6, z, scale=1.3, seed=i + 11, name="Hofbaum")
    for x, z, dx in ((-8, 125, 1), (-8, 150, 1), (8, 138, -1), (8, 163, -1)):
        bm = lib.model(m, "Bank")
        yaw = 90 if dx > 0 else -90
        lib.part(bm, "Sitz", (4.4, 0.3, 1.4), CF.at(x, 0.4, z, yaw), (181, 153, 112), "Wood")
        lib.part(bm, "Lehne", (4.4, 1.2, 0.25), CF.at(x, 1.15, z, yaw) * CF(0, 0, -0.6), (181, 153, 112), "Wood")
        for s in (-1, 1):
            lib.part(bm, "Bein", (0.3, 1.25, 1.2), CF.at(x, -0.375, z, yaw) * CF(s * 1.8, 0, 0), BLACK, "Metal")
    # Aufbereitung: Carport X 64..88, Z 126..146 (Y 12), Auto in Pflege, Hochdruckreiniger
    cx0, cx1, cz0, cz1 = 64, 88, 126, 146
    for x in (cx0 + 0.5, cx1 - 0.5):
        for z in (cz0 + 0.5, cz1 - 0.5):
            lib.box(m, "Carportstuetze", x - 0.4, x + 0.4, -1.0, 12, z - 0.4, z + 0.4, AH_WHITE, "Metal")
    lib.box(m, "Carportdach", cx0, cx1, 12, 12.6, cz0, cz1, AH_WHITE, "SmoothPlastic")
    lib.box(m, "Carportblende", cx0 - 0.1, cx1 + 0.1, 11.6, 12.0, cz1, cz1 + 0.15, TEAL, "Neon", deco=True)
    cs = lib.sign(m, "AUFBEREITUNG", (12, 1.6), CF.at((cx0 + cx1) / 2, 13.4, cz1 - 0.3, 0), TEAL, AH_WHITE,
                  name="Carportschild", bolts=False)
    lib.surface_text(cs, "AUFBEREITUNG", face="Front", text_color=TEAL, name="Rueckseite")
    lib.lite_car(m, "gt_coupe", CF.at(76, -1.0, 136, 180), (20, 22, 26), name="Pflegeauto_gt_coupe",
                 attrs={"Parked": True})
    lib.box(m, "Reinigergeraet", 84.5, 86.5, -1.0, 1.6, 139, 141, (200, 50, 50), "Metal")
    lib.beam(m, "Reinigerschlauch", (84.6, 0.4, 140), (81.5, -0.9, 138.5), 0.2, BLACK, "Plastic", deco=True)
    # 3 Fahnen zum Südring (Anim flag)
    for i, x in enumerate((66, 76, 86)):
        flag_pole(lib, anim, "Hof_Fahne_%d" % (i + 1), x, -1.0, 172,
                  TEAL if i % 2 == 0 else AH_WHITE, AH_WHITE if i % 2 == 0 else TEAL)
    return m


# ================================================================ Teststrecke (D13) - Grand-Prix-Kurs (3.0)
# Die Mittellinie (Geraden + Bögen), Breite, Checkpoints und Schleife T kommen aus vehicles.py (eine Quelle).
# Höhen: Belag -0.95 (Geraden: Quader, Bögen: Trapez-Sektoren ohne Überlappung) | Kies-Auslauf -1.00 (unter dem
# Belagrand beginnend) | Ziellinie -0.90 | Kerbs abwechselnd -0.85 / -0.83 | Reifenstapel auf dem Auslauf.
SAND = (196, 178, 140)
TYRE = (30, 32, 36)
TYRE_BAND = (200, 50, 50)
RAIL = (170, 178, 184)
# Breite des Kies-Auslaufs außen je Kurve (Zielkurve schmal: dahinter liegt der Stadtpark)
RUNOFF = {"Kurve 1": 16.0, "Schnelle Kurve": 16.0, "Haarnadel": 16.0, "Zielkurve": 8.0}
OUTER_KERBS = ("Kurve 1", "Haarnadel", "Zielkurve", "Schnelle Kurve")


def _sectors(deg, max_step):
    """Anzahl Sektoren m (je deg/m Grad), so dass 360 / (deg/m) ganzzahlig ist (lib.ring_slab braucht volle Kreise)"""
    m = max(1, int(math.ceil(deg / max_step)))
    while abs(360.0 * m / deg - round(360.0 * m / deg)) > 1e-6:
        m += 1
    return m


def arc_slab(lib, parent, name, c, r_in, r_out, a0, a1, m, y0, y1, color, material, **kw):
    """Bogen-Band als m Trapez-Sektoren (lib.ring_slab, Teil eines Vollkreises). r_in/r_out sind die Abstände der
    Sektor-ECKEN auf den Grenzstrahlen; so schließen Geraden genau an (Apothem = r * cos(halber Sektorwinkel))."""
    lo, hi = min(a0, a1), max(a0, a1)
    step = (hi - lo) / m
    n = int(round(360.0 / step))
    k = math.cos(math.radians(step / 2))
    return lib.ring_slab(parent, name, c[0], c[1], r_in * k, r_out * k, n, y0, y1, color, material,
                         phase=lo + step / 2, skip=tuple(range(m, n)), **kw)


def _flat_cf(a, b, y):
    """CFrame eines liegenden Quaders von a nach b (lokal -Z = Fahrtrichtung, lokal X = quer)"""
    mid = ((a[0] + b[0]) / 2, y, (a[1] + b[1]) / 2)
    return CF.look_at(mid, (mid[0] + b[0] - a[0], y, mid[2] + b[1] - a[1]))


def track_clear(x, z, margin=0.0):
    """True, wenn (x, z) mindestens TRACK_WIDTH/2 + margin von der Mittellinie entfernt liegt"""
    from ..vehicles import track_geometry, TRACK_WIDTH
    half = TRACK_WIDTH / 2 + margin
    for g in track_geometry():
        if g[0] == "S":
            (ax, az), (bx, bz) = g[1], g[2]
            dx, dz = bx - ax, bz - az
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
            if math.hypot(x - ax - dx * t, z - az - dz * t) < half:
                return False
        else:
            c, r, a0, a1, sign, nm = g[3]
            ang = math.degrees(math.atan2(z - c[1], x - c[0]))
            lo, hi = min(a0, a1), max(a0, a1)
            inside = any(lo - 1e-9 <= ang + k * 360 <= hi + 1e-9 for k in (-1, 0, 1))
            d = abs(math.hypot(x - c[0], z - c[1]) - r) if inside else min(math.dist((x, z), g[1]),
                                                                           math.dist((x, z), g[2]))
            if d < half:
                return False
    return True


def build_track(dm, anim, lib):
    from ..vehicles import track_geometry, TRACK_WIDTH, TRACK_Y
    m = lib.model(dm, "Teststrecke")
    hw = TRACK_WIDTH / 2
    geo = track_geometry()
    belag = lib.model(m, "Belag")
    kerbs = lib.model(m, "Kerbs")
    run = lib.model(m, "Auslauf")
    walls = lib.model(m, "Reifenstapel")
    e0, e1 = 0.7 / TRACK_WIDTH, 1.2 / TRACK_WIDTH
    kerb_i = 0
    wall_i = 0
    for g in geo:
        if g[0] == "S":
            a, b = g[1], g[2]
            ln = math.dist(a, b)
            nm = g[3][1]
            st = lib.part(belag, nm, (TRACK_WIDTH, 0.3, ln), _flat_cf(a, b, TRACK_Y - 0.15), TRACK_ASPHALT, "Asphalt")
            if ln > 20:
                paint(lib, st, [(e0, 0, e1, 1, WHITE), (1 - e1, 0, 1 - e0, 1, WHITE)], px=6, name="Randlinien")
            continue
        c, r, a0, a1, sign, nm = g[3]
        deg = abs(a1 - a0)
        m_road = _sectors(deg, 12.0)
        arc_slab(lib, belag, nm, c, r - hw, r + hw, a0, a1, m_road, TRACK_Y - 0.3, TRACK_Y, TRACK_ASPHALT, "Asphalt")
        # Kerbs rot/weiß: innen (Scheitel) an jedem Bogen, außen an den schnellen/engen Kurven; je Sektor ein
        # Stück auf der Sehne, abwechselnd Höhe (keine gemeinsamen Flächen an den Stoßstellen)
        lo, hi = min(a0, a1), max(a0, a1)
        step = (hi - lo) / m_road
        # Kerb-Außenseite 0.15 innerhalb der Belagkante (keine fast koplanaren Seitenflächen)
        edges = [("innen", r - hw + 0.9)]
        if nm in OUTER_KERBS:
            edges.append(("aussen", r + hw - 0.9))
        for edge, rc in edges:
            for k in range(m_road):
                t0, t1 = math.radians(lo + k * step), math.radians(lo + (k + 1) * step)
                pa = (c[0] + rc * math.cos(t0), c[1] + rc * math.sin(t0))
                pb = (c[0] + rc * math.cos(t1), c[1] + rc * math.sin(t1))
                red = kerb_i % 2 == 0
                kerb_i += 1
                y0, y1 = (-1.05, -0.85) if red else (-1.07, -0.83)
                ym = (y0 + y1) / 2
                lib.beam(kerbs, "Kerb_" + edge, (pa[0], ym, pa[1]), (pb[0], ym, pb[1]), 1.5,
                         TRACK_RED if red else KERB_WHITE, "SmoothPlastic", depth=y1 - y0)
        # Kies-Auslauf außen (beginnt 1 Stud unter dem Belagrand) und Reifenstapel an seinem Außenrand
        if nm in RUNOFF:
            m_run = _sectors(deg, 22.5)
            arc_slab(lib, run, "Kiesbett", c, r + hw - 1.0, r + hw + RUNOFF[nm], a0, a1, m_run, -1.15, -1.0, SAND,
                     "Pebble")
            rw = r + hw + RUNOFF[nm] + 1.4
            st2 = (hi - lo) / m_run
            for k in range(m_run):
                t0, t1 = math.radians(lo + k * st2), math.radians(lo + (k + 1) * st2)
                pa = (c[0] + rw * math.cos(t0), c[1] + rw * math.sin(t0))
                pb = (c[0] + rw * math.cos(t1), c[1] + rw * math.sin(t1))
                h = 3.0 if wall_i % 2 == 0 else 3.4
                wall_i += 1
                w = lib.beam(walls, "Reifenstapel", (pa[0], -1.0 + h / 2, pa[1]), (pb[0], -1.0 + h / 2, pb[1]), 2.6,
                             TYRE, "SmoothPlastic", depth=h)
                # rot-weiße Warnbänder als SurfaceGui (0 Parts) auf der Streckenseite
                gui = lib.surface_text(w, None, face="Left", name="Baender", px_per_stud=6)
                for j in range(6):
                    _frame(lib, gui, "Band%d" % j, (j / 6.0, 0.3), (1 / 12.0, 0.4), TYRE_BAND if j % 2 else KERB_WHITE)
    # Leitplanken: Außenseite der langen Gerade (Süd) und der Westgerade (zum Stadtpark)
    for nm, x0, x1, z0, z1 in (("Leitplanke", -185, 135, 538.5, 539.1), ("Leitplanke", -163.1, -162.5, 330, 420)):
        lib.box(walls, nm, x0, x1, 0.2, 1.4, z0, z1, RAIL, "Metal")
        n_post = max(2, int((max(x1 - x0, z1 - z0)) // 20) + 1)
        for k in range(n_post):
            f = k / (n_post - 1)
            if x1 - x0 > z1 - z0:
                px, pz = x0 + 0.6 + (x1 - x0 - 1.2) * f, (z0 + z1) / 2
            else:
                px, pz = (x0 + x1) / 2, z0 + 0.6 + (z1 - z0 - 1.2) * f
            lib.box(walls, "Pfosten", px - 0.25, px + 0.25, -1.1, 0.2, pz - 0.25, pz + 0.25, STEEL, "Metal")
    # --- Start/Ziel-Brücke: Pfeiler (0,·,256) und (0,·,284), Träger Y 16..18
    g = lib.model(m, "StartZiel")
    lib.box(g, "Pfeiler", -1, 1, -0.5, 16, 255, 257, TRACK_RED, "Metal")
    lib.box(g, "Pfeiler", -1, 1, -1.1, 16, 283, 285, TRACK_RED, "Metal")
    lib.box(g, "Traeger", -1.5, 1.5, 16, 18, 254.5, 285.5, SLATE, "Metal")
    for yaw, x in ((-90, -1.6), (90, 1.6)):
        lib.sign(g, "START · ZIEL", (22, 2.6), CF.at(x, 17, 270, yaw), AMBER, SLATE, name="StartZielSchild",
                 bolts=yaw < 0)
    lib.sign(g, "GRAND-PRIX-KURS", (4.6, 2.6), CF.at(0, 9.5, 254.9, 180), AMBER, SLATE, name="Rundentafel",
             sub="Start an der Kasse · Uhrzeigersinn", bolts=False)
    cl = lib.box(g, "Ziellinie", -1.2, 1.2, -0.95, -0.9, 258.5, 281.5, WHITE, "SmoothPlastic", deco=True)
    rects = []
    for i in range(2):
        for j in range(16):
            if (i + j) % 2 == 0:
                rects.append((i * 0.5, j / 16.0, (i + 1) * 0.5, (j + 1) / 16.0, BLACK))
    paint(lib, cl, rects, px=20, name="Zielflagge")
    # Startampel (Anim startlight) unter dem Träger, Lampen nach Westen (Anfahrt)
    sl = lib.model(anim, "Startampel", attrs={"Anim": "startlight", "Period": 5})
    hs = lib.box(sl, "Ampelgehaeuse", -0.5, 0.5, 14, 16, 264.5, 275.5, BLACK, "Metal")
    lib.set_primary(sl, hs)
    for i in range(5):
        lamp = lib.cylinder(sl, "Lampe%d" % (i + 1), (-0.65, 15, 266 + 2 * i), 0.3, 1.3, "X", (255, 40, 40), "Neon",
                            deco=True)
        lib.attrs(lamp, Index=i + 1)
    # --- Tribüne X -60..60, Z 228..252: 4 Stufen (je +1.5 nach Norden), Rückwand, Dach auf 4 Stützen bei Y 12
    tr = lib.model(m, "Tribuene")
    for i in range(4):
        z0, z1 = 252 - 6 * (i + 1), 252 - 6 * i
        top = 0.5 + 1.5 * i
        lib.box(tr, "Stufe", -60, 60, -1.1, top, z0, z1, CONCRETE, "Concrete")
        lib.box(tr, "Sitzreihe", -59, 59, top, top + 0.6, z0, z0 + 1.4, TRACK_RED if i % 2 == 0 else KERB_WHITE,
                "SmoothPlastic")
    lib.box(tr, "Rueckwand", -60, 60, -1.1, 12, 227.2, 228, SLATE, "Metal")
    for x in (-58, -20, 20, 58):
        lib.box(tr, "Stuetze", x - 0.4, x + 0.4, 0.5, 12, 250.8, 251.6, STEEL, "Metal")
    lib.box(tr, "Gelaender", -58, 58, 2.9, 3.1, 251.1, 251.3, STEEL, "Metal", deco=True)
    lib.box(tr, "Tribuenendach", -61, 61, 12, 12.8, 227.2, 253, GRAPHITE, "SmoothPlastic")
    ts = lib.sign(tr, "TRIBÜNE", (18, 2.6), CF.at(0, 14.1, 252.9, 0), TRACK_RED, KERB_WHITE, name="Dachschild",
                  font="GothamBlack", bolts=False)
    lib.surface_text(ts, "TRIBÜNE", face="Front", text_color=TRACK_RED, font="GothamBlack", name="Rueckseite")
    # Wege: Nordvorplatz (Kasse), Seitenwege, Frontweg an der Strecke (-0.5)
    for nm, x0, x1, z0, z1 in (("Kassenvorplatz", -66, 66, 222, 227.2), ("Seitenweg", -66, -60, 227.2, 252),
                               ("Seitenweg", 60, 66, 227.2, 252), ("Frontweg", -66, 66, 252, 257.5)):
        lib.box(tr, nm, x0, x1, -1.25, -0.5, z0, z1, WALK, "Concrete")
    # Kasse (Station track bei (0,3,224), Spielerseite N)
    lib.box(tr, "Kassentresen", -4, 4, -0.5, 2.6, 224.8, 227.2, TRACK_RED, "Metal")
    lib.box(tr, "Kassenplatte", -4.2, 4.2, 2.6, 2.8, 224.6, 227.2, KERB_WHITE, "SmoothPlastic")
    lib.sign(tr, "TESTSTRECKE", (16, 3.4), CF.at(0, 7.6, 227.1, 180), TRACK_RED, KERB_WHITE, name="Kassenschild",
             sub="Grand-Prix-Kurs · Zeitfahren · Bestzeiten", sub_color=SLATE)
    # --- 4 Flutlichtmasten im Innenfeld (je 1 SpotLight), Kopf zur Strecke
    for x, z, tx, tz in ((0, 330, 0, 270), (90, 470, 175, 495), (-185, 490, -215, 505), (-95, 425, -150, 375)):
        fm = lib.model(m, "Flutlichtmast")
        lib.cylinder(fm, "Mast", (x, 12.85, z), 27.9, 0.8, "Y", STEEL, "Metal")
        head_cf = CF.look_at((x, 26.8, z), (tx, -6.0, tz))
        head = lib.part(fm, "Scheinwerferrahmen", (7, 4, 0.8), head_cf, SLATE, "Metal")
        lib.part(fm, "Scheinwerfer", (6.4, 3.4, 0.1), head_cf * CF(0, 0, -0.45), NEON_WHITE, "Neon", deco=True)
        lib.spot_light(head, 60, 1.3, (244, 248, 255), 80, "Front", False, name="Flutlicht")
    # --- Kurvenschilder (Innenseite, Text zur Anfahrt)
    for text, x, z, face in (("KURVE 1", 70, 300, (-1, 0)), ("S-KURVE", 150, 372, (0, -1)),
                             ("SCHNELLE KURVE", 160, 452, (0, -1)), ("LANGE GERADE", 95, 500, (1, 0)),
                             ("HAARNADEL", -130, 500, (1, 0)), ("ZIELKURVE", -115, 345, (0, 1))):
        sm = lib.model(m, "Kurvenschild")
        yaw = face_yaw(*face)
        dx, dz = math.cos(math.radians(yaw)), -math.sin(math.radians(yaw))
        for s_ in (-1, 1):
            lib.cylinder(sm, "Pfosten", (x + dx * s_ * 3.2, -1.1 + 2.6, z + dz * s_ * 3.2), 5.2, 0.35, "Y", STEEL,
                         "Metal")
        lib.sign(sm, text, (8, 1.8), CF.at(x, 5.0, z, yaw), AMBER, SLATE, name="Schild", bolts=False)
    # --- Innenfeld: Bäume + Plakatwand "ULTIMATE CAR GAME" 16 x 6 bei (0,400), Text nach Norden
    trees = [(-60, 330), (60, 335), (-40, 470), (40, 470), (-110, 470), (30, 395), (-80, 380), (95, 460)]
    k = 0
    for x, z in trees:
        if track_clear(x, z, 6):
            lib.tree_lite(m, x, -1.1, z, scale=1.4, seed=k + 3, name="Innenfeldbaum")
            k += 1
    for x in (-6, 6):
        lib.box(m, "Plakatstuetze", x - 0.3, x + 0.3, -1.1, 5, 420.15, 420.75, STEEL, "Metal")
    bb = lib.sign(m, "ULTIMATE CAR GAME", (16, 6), CF.at(0, 8, 420, 180), AMBER, SLATE, name="Plakatwand",
                  thickness=0.3, font="GothamBlack", sub="GRAND-PRIX-KURS · SPIELERMEILE", sub_color=WHITE)
    lib.surface_text(bb, "ULTIMATE CAR GAME", face="Front", text_color=AMBER, font="GothamBlack", name="Rueckseite")
    return m


# ================================================================ Einstieg
def build(city, lib, tree):
    """Baut Autohaus (D8) und Teststrecke (D13) als eigene District-Models (siehe docs/CITY_SPEC.md §1.5, §6)."""
    districts = lib.folder(city, "Districts")
    dm = lib.model(districts, NAME)
    anim_ah = lib.folder(lib.folder(city, "Animated"), "Autohaus")
    anim_ts = lib.folder(lib.folder(city, "Animated"), "Teststrecke")
    with lib.section("D8 Autohaus"):
        build_forecourt(dm, anim_ah, lib)
        build_rotunda(dm, anim_ah, lib)
        build_showroom(dm, anim_ah, lib)
        build_used_lot(dm, lib)
        build_handover(dm, lib)
        build_backyard(dm, anim_ah, lib)
    with lib.section("D13 Teststrecke"):
        build_track(lib.model(districts, "Teststrecke"), anim_ts, lib)
    return dm
