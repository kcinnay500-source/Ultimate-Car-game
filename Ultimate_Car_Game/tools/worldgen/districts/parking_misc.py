"""Parkplatz-Chaos mit Parkhaus (D7), Tankstelle + Waschstraße (D11), Stadtpark (D12), 8 Skyline-Türme (§2),
Meile-Deko (Bushaltestellen „Markt“, Lampenbanner, Gassen-Portale, Bänke, Abfalleimer) - docs/CITY_SPEC.md.

Statische Kulisse je Bezirk ein Model (§1.5): City.Districts.Parkplatz (Parkplatz-Chaos, Parkhaus),
City.Districts.Tankstelle (Tankstelle, Waschstrasse), City.Districts.Stadtpark, City.Districts.Meile (Gassen,
Haltestellen); animierte Objekte unter City.Animated:
  * Parkplatz.Schranke        Anim=barrier: Kind-Model "Schlagbaum" (PrimaryPart Drehlager, Drehachse Welt-Z)
  * Parkplatz.Parkraster      Anim=parkgrid: Rasterlinien + Attribute Corner/Exit (Vector3), CellX/CellZ/Cols/Rows
  * Tankstelle.Waschanlage    Anim=wash: 3 Portale mit je 2 senkrechten + 1 waagrechten Bürste ("Buerste_*",
                              drehen um ihre Zylinderachse = lokal X)
  * Stadtpark.Teichfontaene   Anim=fountain (Strahl + Gischt)
  * Skyline.Turm_N            Anim=nightwindows: Fensterbänder "Fenster" (Glass bei Tag; Attribute NightNeon,
                              NightColor (255,214,150), NightTransparency 0.55 für den Nachtschalter §9.3);
                              Flugwarnleuchte "Warnlicht" mit eigenem Anim=beacon
  * Meile.Banner_N            Anim=flag (Swing 6): senkrechte "Stange" = Drehachse, "Tuch" schwingt
Stationen parking / carwash und die Ankünfte parking / carwash / park baut contract.py; hier nur die Kulisse
(Schalterfenster des Parkwärterhäuschens vor (-65,2.5,-236.5), Bezahlsäule (304,·,212) hinter carwash).

Höhen-Stapel (§1.2; nie zwei überlappende Oberseiten auf gleicher Höhe):
  Gras -1.10 | Teichboden -1.04 | Parkplatz/Tankstelle/Parkwege/Teichring-Weg/Reifenplatz -1.00 | Ladebucht-Fläche
  -0.95 | Markierungen -0.90 | Fotopunkt -0.95 (auf dem Weg) | Wasser -0.80, Seerosen -0.75 | Zapfinseln -0.60
  | Teichrand -0.55 (Trapez-Sektoren) | Musikpavillon-Stufe -0.30, Bühne 0.40
  | Steg -0.20 | Shop-/Waschstraßen-Boden 0 | Plattform 8 | Parkdeck 25 (Linien 25.05)

Abweichungen vom Spec (begründet):
  * Teich: "Becken -3 / Wasser -1.3" liegt im massiven Gras-Slab (-5.1..-1.1) und wäre unsichtbar. Gebaut als
    flacher Spiegelteich auf dem Gras: dunkler Boden -1.04, Wasser (Glass T 0.3) bis -0.80, Steinring -0.55.
  * Waschbürsten: senkrechte Bürsten bei Z 181/195 statt 182/194 und waagrechte Bürste bei Y 7.2 statt 6, je Satz
    1.6 vor/hinter der Portalmitte - sonst stecken sie im stehenden hot_hatch (340,0,188) (Breite Z 182.9..192.9,
    Dachhöhe 5.5).
  * Parkhaus: Stütze (72,-238) entfällt (liegt im Treppenturm X 70..78, Z -244..-236); das Deck ist um den Turm
    ausgespart. P-Schild-Mast steht auf dem Deck bei (120.9,-241.9) (Schild-Mitte (120.5,34,-241.5)), damit das
    diagonal gedrehte Schild nicht in die Brüstung ragt.
  * Parkplatz-Leuchten: Köpfe exakt an den Spec-Punkten, Masten mit Ausleger daneben ((±64,-274); der
    mittlere Kopf hängt am Anzeigetafel-Portal bei Z -314), damit die AUSFAHRT-Markierung frei bleibt.
"""
import math

from ..lib import (CF, AMBER, BLACK, FRAME, GLASS, GRAPHITE, LAMP, SLATE, STEEL, TEAL, TRUNK, Color3, Vec3,
                   set_attrs, yaw_towards)
from ..ground_roads import street_lamps

NAME = "Parkplatz"

# ---------------------------------------------------------------- Farben
BLUE = (40, 110, 200)
BLUE_D = (24, 62, 120)
CONC = (150, 155, 158)
CONC_L = (170, 174, 176)
LWHITE = (235, 238, 240)
MARK = (224, 231, 230)
MAGENTA = (255, 64, 180)
CYAN = (60, 220, 255)
NIGHT_BLUE = (20, 30, 60)
RED = (200, 50, 50)
GRAVEL = (158, 146, 122)
WOOD = (130, 95, 65)
WOOD_L = (181, 153, 112)
STONE = (122, 124, 118)
WATER = (70, 130, 150)
POND_BED = (36, 52, 58)
SAND = (196, 178, 140)
HEDGE_C = (58, 96, 60)
SKY_BODY = (52, 64, 78)
WIN_NIGHT = (255, 214, 150)
TILE = (205, 208, 212)
GREEN_EV = (70, 160, 90)
SCREEN = (27, 72, 82)
SCREEN_TXT = (121, 225, 206)

Y_GRASS = -1.10
Y_G = -1.0          # Bezirks-Gelände / Parkwege
Y_MARK = -0.90


def build(city, lib, tree):
    """Baut Parkplatz, Tankstelle, Stadtpark und Meile-Deko (docs/CITY_SPEC.md §2, §6 D7/D11/D12,
    Spielermeile-Deko) - je Bezirk ein eigenes Model unter City.Districts (§1.5, bereit für ModelStreaming)."""
    districts = lib.folder(city, "Districts")
    anim_root = lib.folder(city, "Animated")
    dm = lib.model(districts, NAME)
    with lib.section("D7 Parkplatz + Parkhaus"):
        build_parkplatz(dm, lib.folder(anim_root, "Parkplatz"), lib)
        build_parkhaus(dm, lib)
    with lib.section("D11 Tankstelle / Wash"):
        ts = lib.model(districts, "Tankstelle")
        build_tankstelle(ts, lib)
        build_waschstrasse(ts, lib.folder(anim_root, "Tankstelle"), lib)
    with lib.section("D12 Stadtpark"):
        build_park(lib.model(districts, "Stadtpark"), lib.folder(anim_root, "Stadtpark"), lib)
    with lib.section("Skyline-Türme"):
        build_skyline(lib.folder(anim_root, "Skyline"), lib)
    with lib.section("Meile-Deko"):
        build_meile(lib.model(districts, "Meile"), lib.folder(anim_root, "Meile"), lib)
    with lib.section("Stadtrand (Wäldchen)"):
        build_outskirts(lib.model(districts, "Stadtrand"), lib)
    return dm


# ================================================================ Bausteine
def box(lib, parent, name, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
    return lib.box(parent, name, min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1),
                   color, material, **kw)


def lbox(lib, parent, name, base, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
    """Quader in lokalen Koordinaten eines Basis-CFrames (base * Mitte)"""
    size = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
    return lib.part(parent, name, size, base * CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material,
                    **kw)


def cyl_y(lib, parent, name, x, y0, y1, z, d, color=STEEL, material="Metal", **kw):
    return lib.cylinder(parent, name, (x, (y0 + y1) / 2, z), y1 - y0, d, "Y", color, material, **kw)


def flat_text(lib, parent, name, text, x, y_top, z, length, depth, read_yaw, color=MARK, font="GothamBold",
              thick=0.05):
    """Bodenschrift (0.05 dicke Platte, transparent) - Text liegt auf der Oberseite, Buchstaben-Oberkante zeigt in
    Leserichtung read_yaw (yaw wie CF.at: 0 = Leser schaut nach Norden). length = Textzeile, depth = Zeichenhöhe."""
    p = lib.part(parent, name, (length, thick, depth), CF.at(x, y_top - thick / 2, z, read_yaw), color,
                 "SmoothPlastic", transparency=1, deco=True)
    lib.surface_text(p, text, face="Top", text_color=color, font=font)
    return p


def bench(lib, parent, x, z, floor, look_dx, look_dz, length=5.0, color=WOOD_L):
    """Bank (4 Parts); Sitzfläche schaut in Richtung (look_dx, look_dz)."""
    m = lib.model(parent, "Bank")
    yaw = yaw_towards(look_dx, look_dz)
    base = CF.at(x, floor, z, yaw)
    quarter = round(yaw / 90.0)
    aligned = abs(yaw - quarter * 90.0) < 1e-6

    def put(name, size, off, col, mat):
        cf = base * CF(*off)
        if aligned:
            # Vielfache von 90°: achsparallel mit getauschten Maßen (gleiche Geometrie, Size = Weltausdehnung)
            if quarter % 2:
                size = (size[2], size[1], size[0])
            cf = CF(*cf.p)
        lib.part(m, name, size, cf, col, mat)
    put("Sitz", (length, 0.3, 1.6), (0, 1.5, 0), color, "Wood")
    put("Lehne", (length, 1.35, 0.25), (0, 2.325, 0.675), color, "Wood")
    for sx in (-1, 1):
        put("Bein", (0.3, 1.35, 1.4), (sx * (length / 2 - 0.5), 0.675, 0.0), BLACK, "Metal")
    return m


def trash_bin(lib, parent, x, z, floor):
    """Abfalleimer (2 Parts)"""
    m = lib.model(parent, "Abfalleimer")
    cyl_y(lib, m, "Eimer", x, floor, floor + 2.4, z, 1.2, SLATE, "Metal")
    cyl_y(lib, m, "Deckel", x, floor + 2.4, floor + 2.65, z, 1.35, AMBER, "Metal", deco=True)
    return m


def arm_lamp(lib, parent, name, mast_x, mast_z, floor, head_x, head_z, head_y, range_=34, brightness=1.0):
    """Mastleuchte (4 Parts): Fuß, Mast, Ausleger, Kopf (LAMP, NightNeon) mit PointLight am Kopf-Punkt."""
    m = lib.model(parent, name)
    box(lib, m, "Fuss", mast_x - 0.7, mast_x + 0.7, floor, floor + 0.8, mast_z - 0.7, mast_z + 0.7, BLACK, "Metal")
    top = head_y + 0.9
    cyl_y(lib, m, "Mast", mast_x, floor + 0.8, top + 0.25, mast_z, 0.55, STEEL, "Metal")
    lib.beam(m, "Ausleger", (mast_x, top, mast_z), (head_x, top, head_z), 0.3, STEEL, "Metal", deco=True)
    head = lib.part(m, "Kopf", (2.4, 0.4, 1.4), CF.at(head_x, head_y + 0.55, head_z,
                                                     yaw_towards(head_x - mast_x, head_z - mast_z)),
                    LAMP, "SmoothPlastic", deco=True)
    set_attrs(head, {"NightNeon": True})
    lib.point_light(head, range_, brightness, LAMP)
    return m


def panel(lib, parent, name, w, h, cf, bg, lines, thick=0.12, material="SmoothPlastic", face="Back"):
    """Tafel ohne Bolzen mit mehreren Textzeilen: lines = [(Text, Farbe, relative Höhe)]"""
    p = lib.part(parent, name, (w, h, thick), cf, bg, material, deco=True)
    add_lines(lib, p, lines, face)
    return p


def add_lines(lib, part, lines, face="Back", font="GothamBold"):
    gui = lib.surface_text(part, None, face=face)
    total = sum(r for _, _, r in lines)
    y = 0.04
    for i, (text, col, rel) in enumerate(lines):
        hh = 0.92 * rel / total
        lib.text_label(gui, text, col, font, "Zeile%d" % (i + 1), None, (0.92, hh * 0.9), (0.04, y + hh * 0.05))
        y += hh
    return gui


# ================================================================ D7 Parkplatz-Chaos
GRID_X0, GRID_X1, GRID_Z0, GRID_Z1 = -48, 48, -306, -242
CELL_X, CELL_Z = 24, 16
EXIT_Z = (-282, -266)


def build_parkplatz(dm, anim, lib):
    m = lib.model(dm, "Parkplatz-Chaos")
    build_grid(anim, lib)
    # Einfahrt-Markierung (Nordring X -110..-90): Pfeil nach Süden + Schrift
    mk = lib.model(m, "Markierungen")
    box(lib, mk, "Pfeil", -100.6, -99.4, Y_MARK - 0.05, Y_MARK, -312, -305, MARK, deco=True)
    lib.flat_tri(mk, "Pfeilspitze", (-100, -305), (-103, -305), (-100, -301), Y_MARK - 0.05, Y_MARK, MARK,
                 "SmoothPlastic", deco=True)
    lib.flat_tri(mk, "Pfeilspitze", (-100, -305), (-97, -305), (-100, -301), Y_MARK - 0.05, Y_MARK, MARK,
                 "SmoothPlastic", deco=True)
    flat_text(lib, mk, "Schrift_Einfahrt", "EINFAHRT", -100, Y_MARK, -296, 12, 3, 180)
    build_booth(m, lib)
    build_platform(m, lib)
    build_board(m, lib)
    arm_lamp(lib, m, "Mastleuchte_West", -64, -274, Y_G, -56, -274, 14)
    arm_lamp(lib, m, "Mastleuchte_Ost", 64, -274, Y_G, 56, -274, 14)
    build_barrier(anim, lib)


def build_grid(anim, lib):
    g = lib.model(anim, "Parkraster", attrs={
        "Anim": "parkgrid", "Corner": Vec3(GRID_X0, Y_G, GRID_Z0), "Exit": Vec3(GRID_X1, Y_G, sum(EXIT_Z) / 2),
        "CellX": CELL_X, "CellZ": CELL_Z, "Cols": 4, "Rows": 4})
    y0, y1 = Y_MARK - 0.05, Y_MARK
    fw = 0.5    # halbe Rahmenbreite (1.0)
    # Amber-Rahmen (Ost mit Ausfahrt-Lücke)
    box(lib, g, "Rahmen_Nord", GRID_X0 - fw, GRID_X1 + fw, y0, y1, GRID_Z0 - fw, GRID_Z0 + fw, AMBER, deco=True)
    box(lib, g, "Rahmen_Sued", GRID_X0 - fw, GRID_X1 + fw, y0, y1, GRID_Z1 - fw, GRID_Z1 + fw, AMBER, deco=True)
    box(lib, g, "Rahmen_West", GRID_X0 - fw, GRID_X0 + fw, y0, y1, GRID_Z0 + fw, GRID_Z1 - fw, AMBER, deco=True)
    box(lib, g, "Rahmen_Ost", GRID_X1 - fw, GRID_X1 + fw, y0, y1, GRID_Z0 + fw, EXIT_Z[0], AMBER, deco=True)
    box(lib, g, "Rahmen_Ost", GRID_X1 - fw, GRID_X1 + fw, y0, y1, EXIT_Z[1], GRID_Z1 - fw, AMBER, deco=True)
    # weiße Zellenlinien 0.4: Längslinien durchgehend, Querlinien zwischen den Längslinien geteilt
    xs = [GRID_X0 + CELL_X * i for i in range(1, 4)]
    for x in xs:
        box(lib, g, "Linie", x - 0.2, x + 0.2, y0, y1, GRID_Z0 + fw, GRID_Z1 - fw, MARK, deco=True)
    edges = [GRID_X0 + fw] + [v for x in xs for v in (x - 0.2, x + 0.2)] + [GRID_X1 - fw]
    for k in range(1, 4):
        z = GRID_Z0 + CELL_Z * k
        for i in range(0, len(edges), 2):
            box(lib, g, "Linie", edges[i], edges[i + 1], y0, y1, z - 0.2, z + 0.2, MARK, deco=True)
    # AUSFAHRT-Pfeil (amber) nach Osten aus der Rahmenlücke, Schrift dahinter
    zc = sum(EXIT_Z) / 2
    box(lib, g, "Ausfahrt_Pfeil", GRID_X1 + fw, 53.5, y0, y1, zc - 1.2, zc + 1.2, AMBER, deco=True)
    lib.flat_tri(g, "Ausfahrt_Spitze", (53.5, zc), (53.5, zc - 4.5), (58, zc), y0, y1, AMBER, "SmoothPlastic",
                 deco=True)
    lib.flat_tri(g, "Ausfahrt_Spitze", (53.5, zc), (53.5, zc + 4.5), (58, zc), y0, y1, AMBER, "SmoothPlastic",
                 deco=True)
    flat_text(lib, g, "Schrift_Ausfahrt", "AUSFAHRT", 60.6, Y_MARK, zc, 13, 2.6, -90, AMBER)
    return g


def build_booth(parent, lib):
    """Parkwärterhäuschen X -70..-60, Z -248..-238, 10 hoch (nicht begehbar), Schalterfenster nach Süden."""
    m = lib.model(parent, "Parkwaerterhaeuschen")
    x0, x1, z0, z1 = -70, -60, -248, -238
    box(lib, m, "Korpus", x0, x1, Y_G, 8, z0, z1 - 2, SLATE, "Metal")
    # Front mit Fensternische (X -68..-62, Y 2.5..6.5, 2 tief)
    box(lib, m, "Bruestung", x0, x1, Y_G, 2.5, z1 - 2, z1, SLATE, "Metal")
    box(lib, m, "Sturz", x0, x1, 6.5, 8, z1 - 2, z1, SLATE, "Metal")
    box(lib, m, "Laibung", x0, -68, 2.5, 6.5, z1 - 2, z1, SLATE, "Metal")
    box(lib, m, "Laibung", -62, x1, 2.5, 6.5, z1 - 2, z1, SLATE, "Metal")
    box(lib, m, "Fenster", -68, -62, 3.4, 6.5, z1 - 0.35, z1 - 0.15, GLASS, "Glass", transparency=0.3)
    box(lib, m, "Schalterbrett", -68.5, -61.5, 2.5, 2.8, z1 - 1.2, z1 + 1.2, WOOD_L, "Wood")
    # Innenleben hinter der Scheibe: Monitor, Tischleuchte
    box(lib, m, "Monitor", -66.8, -64.4, 3.2, 4.9, z1 - 1.95, z1 - 1.85, SCREEN, "Neon", deco=True)
    box(lib, m, "Monitorfuss", -65.8, -65.4, 2.8, 3.2, z1 - 1.9, z1 - 1.6, BLACK, "Metal", deco=True)
    # Dach: blaues Dachband mit grafitfarbener Kappe
    box(lib, m, "Dachband", x0 - 0.6, x1 + 0.6, 8, 9, z0 - 0.6, z1 + 0.6, BLUE, "SmoothPlastic")
    box(lib, m, "Dachkappe", x0 - 0.3, x1 + 0.3, 9, 9.25, z0 - 0.3, z1 + 0.3, GRAPHITE, "Metal")
    # Tür (West), Schild über dem Fenster
    box(lib, m, "Tuer", x0 - 0.12, x0, Y_G, 6.2, -246, -242.5, FRAME, "Metal", deco=True)
    box(lib, m, "Tuergriff", x0 - 0.3, x0 - 0.12, 2.4, 2.7, -242.9, -242.6, STEEL, "Metal", deco=True)
    lib.sign(m, "P · PARKPLATZ-CHAOS", (9.4, 1.3), CF.at(-65, 7.25, z1 + 0.1, 0), (255, 255, 255), BLUE,
             name="Schild")
    # Dach-"P" (nach Süden und Norden)
    p = lib.part(m, "Dach_P", (2.6, 2.6, 0.4), CF.at(-65, 10.95, -243, 0), BLUE, "SmoothPlastic")
    lib.surface_text(p, "P", face="Back", text_color=(255, 255, 255), font="GothamBlack")
    lib.surface_text(p, "P", face="Front", text_color=(255, 255, 255), font="GothamBlack", name="Rueckseite")
    box(lib, m, "Dach_P_Stuetze", -65.3, -64.7, 9.25, 9.65, -243.15, -242.85, STEEL, "Metal", deco=True)
    return m


def build_platform(parent, lib):
    """Aussichtsplattform X -126..-86, Z -300..-262, Oberseite 8; Rampe X -126..-118, Z -262..-242."""
    m = lib.model(parent, "Aussichtsplattform")
    x0, x1, z0, z1 = -126, -86, -300, -262
    box(lib, m, "Deck", x0, x1, 7, 8, z0, z1, STEEL, "DiamondPlate")
    for x in (-125, -106, -87):
        for z in (-299, -263):
            box(lib, m, "Stuetze", x - 0.6, x + 0.6, Y_G, 7, z - 0.6, z + 0.6, SLATE, "Metal")
    # Geländer 3 hoch: Glasfelder + Handlauf (Südseite offen für die Rampe X -126..-118)
    gy0, gy1 = 8, 10.7
    t = 0.2
    rails = [("Nord", x0, x1, z0, z0 + t), ("West", x0, x0 + t, z0 + t, z1), ("Ost", x1 - t, x1, z0 + t, z1),
             ("Sued", -118, x1 - t, z1 - t, z1)]
    for nm, a0, a1, b0, b1 in rails:
        box(lib, m, "Glas_" + nm, a0, a1, gy0, gy1, b0, b1, GLASS, "Glass", transparency=0.5)
        box(lib, m, "Handlauf_" + nm, a0, a1, gy1, gy1 + 0.3, b0, b1, STEEL, "Metal")
    # Rampe (1:2.2) mit Handläufen
    lib.wedge(m, "Rampe", (8, 9, 20), CF.at(-122, 3.5, -252, 180), STEEL, "DiamondPlate")
    for x in (-125.85, -118.15):
        lib.beam(m, "Rampengelaender", (x, 2.0, -242.2), (x, 11.0, -262.0), 0.25, STEEL, "Metal")
        cyl_y(lib, m, "Gelaenderpfosten", x, Y_G, 2.0, -242.4, 0.3, STEEL, "Metal")
    # Münzfernrohr + Schild
    cyl_y(lib, m, "Fernrohr_Saeule", -106, 8, 11, -297.5, 0.45, SLATE, "Metal")
    lib.part(m, "Fernrohr", (1.0, 0.9, 2.0), CF(-106, 11.4, -297.5) * CF.angles(math.radians(12), 0, 0), BLUE,
             "Metal")
    lib.sign(m, "AUSSICHT", (8, 1.6), CF.at(-106, 9.4, z0 + 0.32, 0), AMBER, SLATE, name="Schild",
             sub=None)
    lib.sign(m, "AUSSICHTSPLATTFORM", (7.4, 1.2), CF.at(-122, 1.6, -241.6, 0), AMBER, SLATE, name="Schild_Rampe")
    for x in (-124.6, -119.4):         # 2 Pfosten vom Platz bis unter das Schild (Rampenfuß ist dort flach)
        box(lib, m, "Schildpfosten", x - 0.12, x + 0.12, Y_G, 1.0, -241.72, -241.48, STEEL, "Metal")
    return m


def build_board(parent, lib):
    """Anzeigetafel-Portal am Nordrand (Z -314): Tafel nach Süden, trägt die Leuchte (0,14,-314)."""
    m = lib.model(parent, "Tafelportal")
    for sx in (-1, 1):
        box(lib, m, "Pfosten", sx * 12.9 - 0.4, sx * 12.9 + 0.4, Y_G, 15.2, -314.4, -313.6, SLATE, "Metal")
    box(lib, m, "Traeger", -13.3, 13.3, 15.2, 15.8, -314.4, -313.6, SLATE, "Metal")
    lib.sign(m, "PARKPLATZ-CHAOS", (24.4, 6.5), CF.at(0, 8.25, -313.5, 0), (255, 255, 255), BLUE, name="Tafel",
             sub="Rätsel-Raster 4 × 4 · Schalter am Parkwärterhäuschen", sub_color=AMBER, thickness=0.3)
    box(lib, m, "Tafelrahmen", -12.5, 12.5, 4.8, 5.0, -313.9, -313.1, AMBER, "Metal", deco=True)
    # Halter unter dem Träger (Z -314.4..-313.6), Leuchte darunter
    box(lib, m, "Leuchtenhalter", -0.1, 0.1, 14.5, 15.2, -314.1, -313.9, STEEL, "Metal", deco=True)
    head = lib.part(m, "Leuchte", (3.2, 0.4, 1.2), CF(0, 14.3, -314), LAMP, "SmoothPlastic", deco=True)
    set_attrs(head, {"NightNeon": True})
    lib.point_light(head, 34, 1.0, LAMP)
    return m


def build_barrier(anim, lib):
    """Schranke an der Einfahrt (Z -318, X -110..-90), Anim=barrier. Drehlager bei X -111.75, Baum nach Osten."""
    m = lib.model(anim, "Schranke", attrs={"Anim": "barrier", "Angle": 80, "Period": 12, "Axis": "Z"})
    z = -318
    box(lib, m, "Saeule", -112.5, -111.0, Y_G, 2.2, z - 0.75, z + 0.75, (230, 232, 234), "SmoothPlastic")
    box(lib, m, "Saeulenband", -112.55, -110.95, 1.2, 1.7, z - 0.8, z + 0.8, RED, "SmoothPlastic", deco=True)
    sb = lib.model(m, "Schlagbaum")
    hinge = lib.part(sb, "Drehlager", (0.8, 0.8, 0.8), CF(-111.75, 2.6, z), STEEL, "Metal")
    lib.set_primary(sb, hinge)
    box(lib, sb, "Baum", -111.35, -89.6, 2.4, 2.8, z - 0.2, z + 0.2, (240, 240, 240), "SmoothPlastic", deco=True)
    for k in range(4):
        xa = -108.5 + k * 5
        box(lib, sb, "Streifen", xa, xa + 2.2, 2.35, 2.85, z - 0.25, z + 0.25, RED, "SmoothPlastic", deco=True)
    box(lib, m, "Auflage", -89.3, -88.7, Y_G, 2.38, z - 0.3, z + 0.3, (230, 232, 234), "SmoothPlastic")
    # Ticketsäule (Fahrerseite Ost)
    box(lib, m, "Ticketsaeule", -88.2, -86.8, Y_G, 3.6, -315.7, -314.3, BLUE, "Metal")
    box(lib, m, "Ticketschirm", -88.3, -88.2, 2.0, 3.0, -315.4, -314.6, SCREEN, "Neon", deco=True)
    return m


# ================================================================ D7 Parkhaus
PH_X0, PH_X1, PH_Z0, PH_Z1 = 70, 126, -316, -236
TOWER = (70, 78, -244, -236)


def build_parkhaus(dm, lib):
    m = lib.model(dm, "Parkhaus")
    # Deck Y 24..25, um den Treppenturm ausgespart
    box(lib, m, "Deck", 78, PH_X1, 24, 25, PH_Z0, PH_Z1, CONC, "Concrete")
    box(lib, m, "Deck", PH_X0, 78, 24, 25, PH_Z0, TOWER[2], CONC, "Concrete")
    for x in (72, 90, 108, 124):
        for z in (-314, -276, -238):
            if (x, z) == (72, -238):
                continue    # liegt im Treppenturm
            box(lib, m, "Stuetze", x - 1, x + 1, Y_G, 24, z - 1, z + 1, CONC_L, "Concrete")
            box(lib, m, "Stuetzenband", x - 1.1, x + 1.1, 0.4, 1.6, z - 1.1, z + 1.1, BLUE, "SmoothPlastic",
                deco=True)
    # Brüstung 1.2 x 3 (Y 25..28), blaues Neonband außen (N, O, S); West trägt das PARKHAUS-Schild
    t = 1.2
    box(lib, m, "Bruestung_Nord", PH_X0, PH_X1, 25, 28, PH_Z0, PH_Z0 + t, CONC_L, "Concrete")
    box(lib, m, "Bruestung_Sued", 78, PH_X1, 25, 28, PH_Z1 - t, PH_Z1, CONC_L, "Concrete")
    box(lib, m, "Bruestung_Ost", PH_X1 - t, PH_X1, 25, 28, PH_Z0 + t, PH_Z1 - t, CONC_L, "Concrete")
    box(lib, m, "Bruestung_West", PH_X0, PH_X0 + t, 25, 28, PH_Z0 + t, TOWER[2], CONC_L, "Concrete")
    ny = (26.2, 26.8)
    box(lib, m, "Neonband", PH_X0, PH_X1 + 0.15, ny[0], ny[1], PH_Z0 - 0.15, PH_Z0, BLUE, "Neon", deco=True)
    box(lib, m, "Neonband", 78, PH_X1 + 0.15, ny[0], ny[1], PH_Z1, PH_Z1 + 0.15, BLUE, "Neon", deco=True)
    box(lib, m, "Neonband", PH_X1, PH_X1 + 0.15, ny[0], ny[1], PH_Z0, PH_Z1, BLUE, "Neon", deco=True)
    lib.sign(m, "PARKHAUS", (26, 2.6), CF.at(PH_X0 - 0.1, 26.5, -281, -90), (255, 255, 255), BLUE, name="Schild_West",
             sub=None)
    # Stellplatzlinien auf dem Deck (Y 25.05) und unten (Y -0.90)
    for x in (84, 96):
        box(lib, m, "Decklinie", x - 0.2, x + 0.2, 25, 25.05, -270, -250, MARK, deco=True)
    for x in (102, 114):
        box(lib, m, "Decklinie", x - 0.2, x + 0.2, 25, 25.05, -300, -280, MARK, deco=True)
    for z in (-306.5, -293.5, -280.5, -267.5, -254.5, -241.5):
        box(lib, m, "Stellplatzlinie", 93, 112, Y_MARK - 0.05, Y_MARK, z - 0.2, z + 0.2, MARK, deco=True)
    flat_text(lib, m, "Schrift_P", "P", 84, Y_MARK, -276, 6, 6, 90, BLUE, "GothamBlack")
    # Deckenbeleuchtung: 2 Leuchtröhren + Pendelleuchte (98,21,-276)
    for x in (81, 117):
        box(lib, m, "Leuchtroehre", x - 0.2, x + 0.2, 23.7, 24, -310, -242, (232, 246, 249), "Neon", deco=True)
    box(lib, m, "Pendel", 97.9, 98.1, 21.3, 24, -276.1, -275.9, STEEL, "Metal", deco=True)
    lamp = lib.part(m, "Deckenleuchte", (2.6, 0.5, 2.6), CF(98, 21.05, -276), (232, 246, 249), "Neon", deco=True)
    lib.point_light(lamp, 36, 1.0, (224, 238, 255))
    # Treppenturm (geschlossen), Tür "NUR PERSONAL"
    tx0, tx1, tz0, tz1 = TOWER
    box(lib, m, "Treppenturm", tx0, tx1, Y_G, 29, tz0, tz1, SLATE, "Metal")
    box(lib, m, "Turmkappe", tx0 - 0.3, tx1 + 0.3, 29, 29.6, tz0 - 0.3, tz1 + 0.3, GRAPHITE, "Metal")
    box(lib, m, "Lichtschlitz", tx0 - 0.15, tx0, 3, 27, -241.2, -239.2, GLASS, "Glass", transparency=0.3)
    box(lib, m, "Blauband", tx0 - 0.1, tx1 + 0.1, 27.4, 28.2, tz0 - 0.1, tz1 + 0.1, BLUE, "SmoothPlastic",
        deco=True)
    box(lib, m, "Tuer", 74.2, 77.2, Y_G, 6.4, tz1, tz1 + 0.12, FRAME, "Metal")
    lib.sign(m, "NUR PERSONAL", (3.4, 0.9), CF.at(75.7, 7.2, tz1 + 0.1, 0), (255, 255, 255), RED, name="Tuerschild",
             bolts=False)
    # P-Schild 10 x 10 (Y 29..39) diagonal: Textseite (+Z, yaw -45) zeigt nach Südwest zum Platz / zur
    # Ankunftshalle. Der Mast steht dahinter (Nordost) und berührt die Rückseite (Abstand Achse - Schildmitte
    # 0.15 + 0.3); die Rückseite bleibt ohne Schrift, weil der Mast davor steht.
    off = (0.15 + 0.3) / math.sqrt(2)
    cyl_y(lib, m, "Schildmast", 120.5 + off, 25, 38.5, -241.5 - off, 0.6, STEEL, "Metal")
    lib.sign(m, "P", (10, 10), CF.at(120.5, 34, -241.5, -45), (255, 255, 255), BLUE, name="P_Schild",
             sub="PARKHAUS", font="GothamBlack", thickness=0.3)
    # Autos: 2 auf dem Deck, 1 darunter
    cars = lib.model(m, "Autos")
    lib.clone_car(cars, "sedan", CF.at(90, 25, -260, 0), BLUE, name="Deckauto_sedan", attrs={"Display": "Parkhaus"})
    lib.clone_car(cars, "wagon", CF.at(108, 25, -290, 180), (180, 186, 190), name="Deckauto_wagon",
                  attrs={"Display": "Parkhaus"})
    lib.clone_car(cars, "crossover", CF.at(100, -1, -300, 90), LWHITE, name="Parkauto_crossover",
                  attrs={"Display": "Parkhaus"})
    return m


# ================================================================ D11 Tankstelle
def build_tankstelle(dm, lib):
    m = lib.model(dm, "Tankstelle")
    build_price_pylon(m, lib)
    build_canopy(m, lib)
    build_shop(m, lib)
    build_ev(m, lib)
    build_vacuum(m, lib)
    build_forecourt_south(m, lib)
    mk = lib.model(m, "Markierungen")
    flat_text(lib, mk, "Schrift_Einfahrt", "EINFAHRT", 184, Y_MARK, 170, 10, 2.4, -90)
    flat_text(lib, mk, "Schrift_Ausfahrt", "AUSFAHRT", 186, Y_MARK, 211, 8, 2.4, 90)
    # Bezahlsäule der Waschstraße (Station carwash davor bei (304,3,218); Spielerseite Nord hat 10 x 10 frei,
    # Spec (304,3,209) läge zwischen Shop und Waschstraße, dort ist die Gasse nur 10 breit)
    t = lib.model(m, "Bezahlsaeule")
    box(lib, t, "Saeule", 303.0, 305.0, Y_G, 4.6, 220.4, 221.8, SLATE, "Metal")
    box(lib, t, "Haube", 302.7, 305.3, 4.6, 5.0, 220.0, 222.0, CYAN, "SmoothPlastic")
    panel(lib, t, "Bildschirm", 1.7, 1.5, CF.at(304, 3.1, 220.35, 180), NIGHT_BLUE,
          [("WASCHEN", CYAN, 1.2), ("Programm wählen", (255, 255, 255), 0.8), ("Glanz für dein Auto", MAGENTA, 0.8)],
          thick=0.1)
    return m


def build_price_pylon(parent, lib):
    m = lib.model(parent, "Preispylon")
    x, z = 186, 162
    box(lib, m, "Pylon", x - 2.5, x + 2.5, Y_G, 25, z - 1, z + 1, SLATE, "Metal")
    box(lib, m, "Kappe", x - 2.7, x + 2.7, 25, 25.6, z - 1.2, z + 1.2, AMBER, "Neon", deco=True)
    for face_z, yaw in ((z + 1.06, 0), (z - 1.06, 180)):
        panel(lib, m, "Logo", 4.6, 4.6, CF.at(x, 22.1, face_z, yaw), TEAL,
              [("TANKSTELLE", (255, 255, 255), 1.0), ("Spielermeile", SLATE, 0.6)])
        panel(lib, m, "Preise", 4.6, 8.4, CF.at(x, 14.9, face_z, yaw), BLACK,
              [("SUPER", (255, 255, 255), 0.7), ("1,79", AMBER, 1.3), ("DIESEL", (255, 255, 255), 0.7),
               ("1,69", AMBER, 1.3), ("E-LADEN", GREEN_EV, 0.7), ("0,39", AMBER, 1.3)])
    return m


def build_canopy(parent, lib):
    """Dach X 196..256, Z 170..206 (Y 12..14) auf 4 Stützen, Zapfinseln Z 181/195, Säulen X 216/236."""
    m = lib.model(parent, "Tankdach")
    x0, x1, z0, z1 = 196, 256, 170, 206
    f = 0.3
    box(lib, m, "Dachplatte", x0 + f, x1 - f, 12, 14, z0 + f, z1 - f, (225, 228, 230), "SmoothPlastic")
    fas = [box(lib, m, "Blende_Nord", x0, x1, 11.6, 14.4, z0, z0 + f, TEAL, "SmoothPlastic"),
           box(lib, m, "Blende_Sued", x0, x1, 11.6, 14.4, z1 - f, z1, TEAL, "SmoothPlastic"),
           box(lib, m, "Blende_West", x0, x0 + f, 11.6, 14.4, z0 + f, z1 - f, TEAL, "SmoothPlastic"),
           box(lib, m, "Blende_Ost", x1 - f, x1, 11.6, 14.4, z0 + f, z1 - f, TEAL, "SmoothPlastic")]
    lib.surface_text(fas[0], "TANKSTELLE · SPIELERMEILE", face="Front", text_color=(255, 255, 255))
    lib.surface_text(fas[1], "TANKSTELLE · SPIELERMEILE", face="Back", text_color=(255, 255, 255))
    lib.surface_text(fas[2], "TANKEN · SHOP · WASCHEN", face="Left", text_color=(255, 255, 255))
    lib.surface_text(fas[3], "TANKEN · SHOP · WASCHEN", face="Right", text_color=(255, 255, 255))
    s = 0.12
    ny0, ny1 = 11.75, 12.1
    box(lib, m, "Neon", x0 - s, x1 + s, ny0, ny1, z0 - s, z0, AMBER, "Neon", deco=True)
    box(lib, m, "Neon", x0 - s, x1 + s, ny0, ny1, z1, z1 + s, AMBER, "Neon", deco=True)
    box(lib, m, "Neon", x0 - s, x0, ny0, ny1, z0, z1, AMBER, "Neon", deco=True)
    box(lib, m, "Neon", x1, x1 + s, ny0, ny1, z0, z1, AMBER, "Neon", deco=True)
    # Deckenfelder (6), 2 davon mit Licht
    for x in (216, 226, 236):
        for z in (181, 195):
            lp = box(lib, m, "Deckenfeld", x - 3, x + 3, 11.9, 12, z - 1.2, z + 1.2, (240, 246, 250), "Neon", deco=True)
            if x == 226:
                lib.point_light(lp, 32, 1.1, (236, 244, 255))
    # Zapfinseln, Stützen, Säulen, Poller
    for zi in (181, 195):
        box(lib, m, "Zapfinsel", 206, 246, Y_G, -0.6, zi - 1.2, zi + 1.2, CONC_L, "Concrete")
        for x in (209, 243):
            box(lib, m, "Stuetze", x - 0.6, x + 0.6, -0.6, 12, zi - 0.6, zi + 0.6, LWHITE, "Metal")
        for x in (205.2, 246.8):
            cyl_y(lib, m, "Poller", x, Y_G, 1.8, zi, 0.6, (240, 190, 40), "Metal")
        face = 1 if zi == 181 else -1      # Bildschirm zur Fahrgasse (Z 188)
        for i, x in enumerate((216, 236)):
            nr = (1 if zi == 181 else 3) + i
            build_pump(m, lib, x, zi, face, nr)
    lib.clone_car(m, "compact", CF.at(216, Y_G, 188, -90), RED, name="Tankauto_compact",
                  attrs={"Display": "Tankstelle"})
    return m


def build_pump(parent, lib, x, z, face, nr):
    m = lib.model(parent, "Zapfsaeule_%d" % nr)
    box(lib, m, "Gehaeuse", x - 1.1, x + 1.1, -0.6, 4.8, z - 0.7, z + 0.7, LWHITE, "SmoothPlastic")
    head = box(lib, m, "Kopf", x - 1.25, x + 1.25, 4.8, 5.7, z - 0.8, z + 0.8, TEAL, "SmoothPlastic")
    lib.surface_text(head, str(nr), face="Back", text_color=(255, 255, 255))
    lib.surface_text(head, str(nr), face="Front", text_color=(255, 255, 255), name="Rueckseite")
    panel(lib, m, "Anzeige", 1.6, 1.3, CF.at(x, 3.6, z + face * 0.76, 0 if face > 0 else 180), BLACK,
          [("SUPER", (255, 255, 255), 0.8), ("1,79", AMBER, 1.2)], thick=0.1)
    hx = x + 1.1
    box(lib, m, "Zapfpistole", hx, hx + 0.35, 2.0, 2.9, z - 0.25, z + 0.25, BLACK, "Metal", deco=True)
    lib.beam(m, "Schlauch", (hx + 0.1, 4.3, z), (hx + 0.2, 2.9, z), 0.22, BLACK, "Plastic", deco=True)
    return m


def build_shop(parent, lib):
    """Shop X 266..300, Z 172..204, 12 hoch, Glasfront West, Verkaufstresen außen (nicht begehbar)."""
    m = lib.model(parent, "Shop")
    x0, x1, z0, z1 = 266, 300, 172, 204
    w = 0.8
    box(lib, m, "Boden", x0, x1, Y_G, 0, z0, z1, TILE, "SmoothPlastic", reflectance=0.08)
    box(lib, m, "Wand_Nord", x0, x1, 0, 12, z0, z0 + w, SLATE, "Metal")
    box(lib, m, "Wand_Sued", x0, x1, 0, 12, z1 - w, z1, SLATE, "Metal")
    box(lib, m, "Wand_Ost", x1 - w, x1, 0, 12, z0 + w, z1 - w, SLATE, "Metal")
    lint = box(lib, m, "Sturz", x0, x0 + 0.7, 9.5, 12, z0 + w, z1 - w, TEAL, "SmoothPlastic")
    lib.surface_text(lint, "SHOP · KAFFEE · SNACKS", face="Left", text_color=(255, 255, 255))
    box(lib, m, "Dach", x0 + 0.7, x1 - w, 11, 12, z0 + w, z1 - w, GRAPHITE, "Metal")
    box(lib, m, "Klimageraet", 285, 293, 12, 13.5, 185, 191, (70, 78, 86), "Metal")
    e = 0.12
    box(lib, m, "Dachkante", x0 - e, x1 + e, 11.4, 11.8, z0 - e, z0, AMBER, "Neon", deco=True)
    box(lib, m, "Dachkante", x0 - e, x1 + e, 11.4, 11.8, z1, z1 + e, AMBER, "Neon", deco=True)
    box(lib, m, "Dachkante", x1, x1 + e, 11.4, 11.8, z0, z1, AMBER, "Neon", deco=True)
    # Glasfront in 4 Feldern mit 3 Pfosten
    mull = [180, 188, 196]
    edges = [z0 + w] + [v for zz in mull for v in (zz - 0.25, zz + 0.25)] + [z1 - w]
    for i in range(0, len(edges), 2):
        box(lib, m, "Glasfront", x0 + 0.2, x0 + 0.5, 0, 9.5, edges[i], edges[i + 1], GLASS, "Glass",
            transparency=0.3)
    for zz in mull:
        box(lib, m, "Pfosten", x0, x0 + 0.7, 0, 9.5, zz - 0.25, zz + 0.25, FRAME, "Metal")
    # Verkaufstresen außen + Kassenschild
    box(lib, m, "Tresen", x0 - 1.4, x0 + 0.2, 3.3, 3.6, 181, 187, WOOD_L, "Wood")
    # Kassenschild flach auf der Glasfront (Rückseite X 266.2)
    lib.sign(m, "KASSE · Kaffee to go", (5, 1.1), CF.at(x0 + 0.1, 7.6, 184, -90), AMBER, SLATE, name="Kassenschild")
    # Innenleben hinter dem Glas
    box(lib, m, "Theke", 272, 282, 0, 3.2, 196, 198.8, WOOD_L, "Wood")
    box(lib, m, "Thekenplatte", 271.8, 282.2, 3.2, 3.45, 195.8, 199, SLATE, "Metal")
    box(lib, m, "Kasse", 273, 274.6, 3.45, 4.6, 196.8, 197.8, BLACK, "Metal", deco=True)
    box(lib, m, "Kaffeemaschine", 279, 281, 3.45, 5.8, 197.2, 198.6, RED, "Metal", deco=True)
    panel(lib, m, "Preistafel", 10, 3, CF.at(277, 8, z1 - w - 0.07, 180), (44, 74, 62),
          [("KAFFEE 1,50 · BREZEL 1,20", (255, 255, 255), 1.0), ("ÖL · WISCHWASSER · SNACKS", AMBER, 0.8)])
    for zr in (180.5, 188.5):
        box(lib, m, "Regal", 275, 290, 0, 5, zr - 0.9, zr + 0.9, (230, 232, 234), "Metal")
        box(lib, m, "Ware", 275.4, 289.6, 2.2, 4.4, zr - 1.05, zr + 1.05, (200, 90, 60), "Fabric", deco=True)
    box(lib, m, "Kuehlregal", 296.6, x1 - w, 0, 8, 176, 198, (40, 46, 52), "Metal")
    box(lib, m, "Kuehlglas", 296.45, 296.6, 0.6, 7.4, 176.5, 197.5, GLASS, "Glass", transparency=0.35)
    box(lib, m, "Kuehlneon", 296.4, 296.6, 7.5, 7.8, 176, 198, CYAN, "Neon", deco=True)
    for zz in (180, 194):
        box(lib, m, "Deckenroehre", 272, 294, 10.7, 11, zz - 0.2, zz + 0.2, (240, 246, 250), "Neon", deco=True)
    return m


def build_ev(parent, lib):
    """E-Ladebuchten X 204..226, Z 225..241 (grüne Fläche -0.95, Linien -0.90), 2 Ladesäulen am Nordende."""
    m = lib.model(parent, "E_Laden")
    box(lib, m, "Ladebucht", 204, 226, Y_G, Y_G + 0.05, 225, 241, GREEN_EV, "SmoothPlastic", deco=True)
    for x in (204.2, 215, 225.8):
        box(lib, m, "Linie", x - 0.2, x + 0.2, Y_MARK - 0.05, Y_MARK, 225, 241, MARK, deco=True)
    for x in (209.6, 220.4):
        box(lib, m, "Ladesaeule", x - 0.6, x + 0.6, Y_G, 4.4, 222.8, 223.6, LWHITE, "SmoothPlastic")
        box(lib, m, "Ladeband", x - 0.62, x + 0.62, 3.6, 4.0, 222.78, 223.62, GREEN_EV, "Neon", deco=True)
        panel(lib, m, "Ladeschild", 1.1, 0.8, CF.at(x, 2.6, 223.66, 0), BLACK, [("E-LADEN", GREEN_EV, 1.0)],
              thick=0.08)
        lib.beam(m, "Ladekabel", (x + 0.6, 2.4, 223.2), (x + 1.0, 0.2, 224.0), 0.2, BLACK, "Plastic", deco=True)
    return m


def build_vacuum(parent, lib):
    """Saugerplatz hinter der Waschstraße (X 330..366, Z 216..232): 4 Buchten, 2 Saugsäulen."""
    m = lib.model(parent, "Saugerplatz")
    for x in (330, 342, 354, 366):
        box(lib, m, "Linie", x - 0.2, x + 0.2, Y_MARK - 0.05, Y_MARK, 216, 232, MARK, deco=True)
    for x in (336, 360):
        box(lib, m, "Saugsaeule", x - 0.7, x + 0.7, Y_G, 5.2, 213.3, 214.7, CYAN, "SmoothPlastic")
        box(lib, m, "Saugkopf", x - 0.9, x + 0.9, 5.2, 5.8, 213.1, 214.9, NIGHT_BLUE, "Metal")
        lib.beam(m, "Saugschlauch", (x + 0.7, 4.4, 214), (x + 5.5, 0.2, 219), 0.3, BLACK, "Plastic", deco=True)
    lib.sign(m, "SAUGER · 1 € / 3 MIN", (7, 1.2), CF.at(348, 4.6, 214.1, 0), CYAN, NIGHT_BLUE, name="Schild")
    box(lib, m, "Schildpfosten", 344.6, 345.0, Y_G, 3.95, 213.8, 214.0, STEEL, "Metal")
    box(lib, m, "Schildpfosten", 351.0, 351.4, Y_G, 3.95, 213.8, 214.0, STEEL, "Metal")
    return m


def build_forecourt_south(parent, lib):
    """Südteil des Tankstellen-Geländes (bisher leer): Kundenparkplatz mit 3 Lite-Autos, Luft-/Wasserstation,
    Baumreihe auf dem Grünstreifen dahinter (Z 266)."""
    m = lib.model(parent, "Kundenparkplatz")
    x0, x1, z0, z1 = 250, 300, 236, 256
    pad = box(lib, m, "Parkflaeche", x0, x1, Y_G, Y_G + 0.05, z0, z1, (96, 100, 102), "Concrete")
    gui = lib.surface_text(pad, None, face="Top", name="Buchten", px_per_stud=8)
    from .dealer_track import _frame
    for k in range(5):
        u = k * 12.5 / (x1 - x0)
        _frame(lib, gui, "Linie%d" % k, (max(0.0, u - 0.004), 0.05), (0.008, 0.9), MARK)
    for i, (body, col, x) in enumerate((("compact", (60, 110, 170), 256.25), ("wagon", (180, 60, 50), 268.75),
                                        ("sedan", (230, 230, 225), 293.75))):
        lib.lite_car(m, body, CF.at(x, Y_G + 0.05, 246, 0 if i % 2 == 0 else 180), col, name="Parkauto_" + body,
                     attrs={"Parked": True})
    # Luft- und Wasserstation
    lw = lib.model(parent, "Luftstation")
    lx, lz = 318, 238
    box(lib, lw, "Sockel", lx - 1.2, lx + 1.2, Y_G, -0.6, lz - 1.2, lz + 1.2, CONC_L, "Concrete")
    box(lib, lw, "Saeule", lx - 0.8, lx + 0.8, -0.6, 4.6, lz - 0.6, lz + 0.6, (40, 110, 200), "SmoothPlastic")
    box(lib, lw, "Kopf", lx - 1.0, lx + 1.0, 4.6, 5.4, lz - 0.8, lz + 0.8, LWHITE, "SmoothPlastic")
    panel(lib, lw, "Anzeige", 1.4, 1.2, CF.at(lx, 3.4, lz + 0.66, 0), BLACK,
          [("LUFT", (255, 255, 255), 1.0), ("2,5 bar", AMBER, 0.9)], thick=0.1)
    lib.beam(lw, "Luftschlauch", (lx + 0.8, 2.6, lz), (lx + 2.6, -0.8, lz + 1.6), 0.18, BLACK, "Plastic", deco=True)
    lib.sign(lw, "LUFT · WASSER", (4, 0.9), CF.at(lx, 5.85, lz + 0.35, 0), (255, 255, 255), (40, 110, 200),
             name="Schild", bolts=False)
    # Baumreihe auf dem Grünstreifen südlich des Geländes
    for i, x in enumerate(range(200, 400, 28)):
        lib.tree_lite(parent, x, Y_GRASS, 266, scale=1.5, seed=i + 21, name="Baumreihe")
    return m


def build_outskirts(parent, lib):
    """Wäldchen in den leeren Ecken innerhalb der Hecke (SO: X 170..590, Z 270..470; SW: X -590..-170,
    Z 340..470): Lite-Bäume in Gruppen, dazwischen Findlinge."""
    import random
    rng = random.Random(4711)
    clusters = [(240, 330, 6), (340, 410, 7), (460, 320, 6), (530, 430, 5), (430, 445, 4),
                (-250, 400, 6), (-390, 415, 7), (-520, 380, 6), (-545, 250, 5), (-300, 450, 4)]
    n = 0
    for cx, cz, k in clusters:
        g = lib.model(parent, "Waeldchen")
        for j in range(k):
            a = rng.uniform(0, 2 * math.pi)
            r = rng.uniform(3, 14) if j else 0
            x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
            lib.tree_lite(g, x, Y_GRASS, z, scale=rng.uniform(1.3, 1.9), seed=n, name="Waldbaum")
            n += 1
        for j in range(2):
            a = rng.uniform(0, 2 * math.pi)
            d = rng.uniform(1.6, 2.6)
            lib.ball(g, "Findling", (cx + math.cos(a) * 17, Y_GRASS + d * 0.3, cz + math.sin(a) * 17), d, STONE,
                     "Slate")
    return parent


# ================================================================ D11 Waschstraße
WX0, WX1, WZ0, WZ1 = 310, 370, 176, 200
OPEN = (179, 197)


def build_waschstrasse(dm, anim, lib):
    m = lib.model(dm, "Waschstrasse")
    t = 0.8
    box(lib, m, "Boden", WX0, WX1, Y_G, 0, WZ0, WZ1, (96, 104, 112), "Concrete")
    lib.wedge(m, "Auffahrt_West", (OPEN[1] - OPEN[0], 1, 6), CF.at(WX0 - 3, -0.5, 188, 90), (96, 104, 112),
              "Concrete")
    lib.wedge(m, "Auffahrt_Ost", (OPEN[1] - OPEN[0], 1, 6), CF.at(WX1 + 3, -0.5, 188, -90), (96, 104, 112),
              "Concrete")
    # Stirnrahmen (offen Z 179..197 x Y 0..20), Wände bis 28
    for nm, a0, a1 in (("West", WX0, WX0 + t), ("Ost", WX1 - t, WX1)):
        box(lib, m, "Pfeiler_" + nm, a0, a1, 0, 28, WZ0, OPEN[0], SLATE, "Metal")
        box(lib, m, "Pfeiler_" + nm, a0, a1, 0, 28, OPEN[1], WZ1, SLATE, "Metal")
        box(lib, m, "Sturz_" + nm, a0, a1, 20, 28, OPEN[0], OPEN[1], SLATE, "Metal")
    # Seitenwände: Sockel, Glas (T 0.4), oberes Band; innen je ein Neonband
    for nm, b0, b1 in (("Nord", WZ0, WZ0 + t), ("Sued", WZ1 - t, WZ1)):
        box(lib, m, "Sockel_" + nm, WX0 + t, WX1 - t, 0, 2, b0, b1, SLATE, "Metal")
        box(lib, m, "Glaswand_" + nm, WX0 + t, WX1 - t, 2, 22, b0 + 0.25, b1 - 0.25, GLASS, "Glass", transparency=0.4)
        box(lib, m, "Band_" + nm, WX0 + t, WX1 - t, 22, 28, b0, b1, SLATE, "Metal")
    box(lib, m, "Neon_Nord", WX0 + t, WX1 - t, 22.3, 22.6, WZ0 + t, WZ0 + t + 0.15, MAGENTA, "Neon", deco=True)
    box(lib, m, "Neon_Sued", WX0 + t, WX1 - t, 22.3, 22.6, WZ1 - t - 0.15, WZ1 - t, CYAN, "Neon", deco=True)
    box(lib, m, "Dach", WX0 + t, WX1 - t, 24, 25, WZ0 + t, WZ1 - t, GRAPHITE, "Metal")
    box(lib, m, "Fuehrungsschiene", WX0 + 1, WX1 - 1, 0, 0.35, 182.8, 183.4, STEEL, "Metal")
    # Tunnellicht (340,22,188)
    box(lib, m, "Pendel", 339.9, 340.1, 22.3, 24, 187.9, 188.1, STEEL, "Metal", deco=True)
    lp = lib.part(m, "Tunnelleuchte", (6, 0.4, 1.4), CF(340, 22.1, 188), (232, 246, 249), "Neon", deco=True)
    lib.point_light(lp, 34, 1.1, (224, 238, 255))
    # Schilder
    lib.sign(m, "WASCHSTRASSE", (16, 4), CF.at(WX0 - 0.1, 24, 188, -90), CYAN, NIGHT_BLUE, name="Schild_West",
             sub="Schaum · Bürsten · Glanz", sub_color=MAGENTA)
    lib.sign(m, "AUSFAHRT · GUTE FAHRT!", (14, 2.4), CF.at(WX1 + 0.1, 24, 188, 90), CYAN, NIGHT_BLUE,
             name="Schild_Ost")
    # Einfahrtsampel am Nordpfeiler (West)
    box(lib, m, "Ampelgehaeuse", WX0 - 0.6, WX0, 9.4, 13.4, 177.0, 178.4, BLACK, "Metal")
    lib.ball(m, "Ampel_Rot", (WX0 - 0.65, 12.4, 177.7), 0.9, (90, 20, 20), "SmoothPlastic", deco=True)
    lib.ball(m, "Ampel_Gruen", (WX0 - 0.65, 10.4, 177.7), 0.9, (60, 230, 90), "Neon", deco=True)
    lib.clone_car(m, "hot_hatch", CF.at(340, 0, 188, -90), TEAL, name="Waschauto_hot_hatch",
                  attrs={"Display": "Waschstrasse"})
    build_brushes(anim, lib)
    return m


def build_brushes(anim, lib):
    """3 Bürstenportale bei X 325/340/355: senkrechte Bürsten (Ø3 x 14) bei Z 181/195 (X s-1.6),
    waagrechte Bürste (Ø3 x 16, Achse Z) bei Y 7.2 (X s+1.6); Anim=wash dreht jede Bürste um ihre Achse."""
    wa = lib.model(anim, "Waschanlage", attrs={"Anim": "wash", "Speed": 240, "Axis": "X"})
    for i, s in enumerate((325, 340, 355)):
        p = lib.model(wa, "Portal_%d" % (i + 1))
        for zc in (177.8, 198.2):
            box(lib, p, "Stuetze", s - 0.5, s + 0.5, 0, 16, zc - 0.5, zc + 0.5, STEEL, "Metal")
        box(lib, p, "Traeger", s - 3.2, s + 3.2, 16, 17, 177.3, 198.7, STEEL, "Metal")
        for k, zc in enumerate((181, 195)):
            col = BLUE if (i + k) % 2 == 0 else MAGENTA
            cyl_y(lib, p, "Buerste_Senkrecht", s - 1.6, 1.0, 15.0, zc, 3, col, "Fabric", deco=True)
            cyl_y(lib, p, "Achse", s - 1.6, 15.0, 16.0, zc, 0.5, STEEL, "Metal", deco=True)
            cyl_y(lib, p, "Haenger", s + 1.6, 8.7, 16.0, zc, 0.3, STEEL, "Metal", deco=True)
        lib.cylinder(p, "Buerste_Waagrecht", (s + 1.6, 7.2, 188), 16, 3, "Z", MAGENTA if i % 2 == 0 else BLUE,
                     "Fabric", deco=True)
    return wa


# ================================================================ D12 Stadtpark
POND = (-320, 265)
POND_R = 28
PAV = (-250, 305)


def build_park(dm, anim, lib):
    m = lib.model(dm, "Stadtpark")
    build_park_paths(m, lib)
    build_pond(m, anim, lib)
    build_pavilion(m, lib)
    build_photo_spot(m, lib)
    build_tyre_course(m, lib)
    build_park_green(m, lib)
    # Parkleuchten (2 frei, 1 im Pavillon)
    lm = lib.model(m, "Parkleuchten")
    park_lamp(lib, lm, -315.5, 225, -320, 225)
    park_lamp(lib, lm, -195.5, 200, -199.5, 200)
    return m


def park_lamp(lib, parent, mx, mz, hx, hz):
    """Parkleuchte (4 Parts), Kopf bei Y 8 über (hx, hz)"""
    m = lib.model(parent, "Parkleuchte")
    box(lib, m, "Fuss", mx - 0.5, mx + 0.5, Y_GRASS, -0.4, mz - 0.5, mz + 0.5, BLACK, "Metal")
    cyl_y(lib, m, "Mast", mx, -0.4, 9.2, mz, 0.4, (40, 60, 52), "Metal")
    lib.beam(m, "Ausleger", (mx, 9.0, mz), (hx, 9.0, hz), 0.22, (40, 60, 52), "Metal", deco=True)
    head = lib.part(m, "Laterne", (1.3, 1.5, 1.3), CF(hx, 8.14, hz), LAMP, "SmoothPlastic", deco=True)
    set_attrs(head, {"NightNeon": True})
    lib.point_light(head, 28, 0.9, LAMP)
    return m


def build_park_paths(parent, lib):
    m = lib.model(parent, "Wege")
    y0, y1 = Y_G - 0.3, Y_G
    rects = [
        ("Hauptweg", -420, -174, 162, 168),          # Eingang Z14 (-178,165) bis Reifen-Parcours
        ("Hintereingang", -326, -320, 159, 162),     # Gasse X -323 (Z 153..159)
        ("Teichweg", -323, -317, 168, 228),          # endet an der Außenkante des Ringwegs (r 37)
        ("Pavillonweg", -283, -247, 262, 268),
        ("Pavillonweg", -253, -247, 268, 296.5),
        ("Ostweg", -203, -197, 168, 308),
        ("Suedweg", -241, -203, 302, 308),
        ("Parcoursweg", -403, -397, 168, 196),
    ]
    for nm, x0, x1, z0, z1 in rects:
        box(lib, m, nm, x0, x1, y0, y1, z0, z1, GRAVEL, "Pebble")
    box(lib, m, "Parcoursplatz", -424, -376, y0, y1, 196, 228, SAND, "Sand")
    # Ringweg um den Teich r 31..37: 16 Trapez-Sektoren ohne Überlappung, Oberseite -1.00 (wie die Wege)
    cx, cz = POND
    lib.ring_slab(m, "Ringweg", cx, cz, 31, 37, 16, y0, y1, GRAVEL, "Pebble")
    return m


def build_pond(parent, anim, lib):
    m = lib.model(parent, "Teich")
    cx, cz = POND
    cyl_y(lib, m, "Teichboden", cx, Y_GRASS, -1.04, cz, 2 * POND_R + 1, POND_BED, "Slate")
    cyl_y(lib, m, "Wasser", cx, -1.04, -0.80, cz, 2 * POND_R, WATER, "Glass", transparency=0.3, collide=False,
          query=False, cast_shadow=False, reflectance=0.15)
    # Steinring r 28..29.6 (16 Trapez-Sektoren ohne Überlappung, Oberseite -0.55), 8 Findlinge
    lib.ring_slab(m, "Teichrand", cx, cz, 28, 29.6, 16, Y_GRASS, -0.55, (128, 124, 116), "Cobblestone",
                  phase=360 / 32)
    for k in range(8):
        a = 2 * math.pi * (k * 45 + 20) / 360
        d = 2.2 + 0.4 * (k % 3)
        lib.ball(m, "Findling", (cx + math.cos(a) * 29.0, -0.55 + d * 0.3, cz + math.sin(a) * 29.0), d, STONE,
                 "Slate", deco=False)
    # Seerosen
    for k, (dx, dz) in enumerate(((-9, -8), (-13, 2), (6, -14), (11, 9), (-4, 15))):
        cyl_y(lib, m, "Seerose", cx + dx, -0.80, -0.75, cz + dz, 2.4 + 0.3 * (k % 2), (72, 130, 70), "Grass",
              deco=True)
    # Steg von Süden (r 31 -> r 9), Deck Oberseite -0.2
    st = lib.model(m, "Steg")
    box(lib, st, "Stegdeck", cx - 2, cx + 2, -0.5, -0.2, cz + 9, cz + 31, WOOD, "WoodPlanks")
    for dz in (9.4, 18.0):
        for dx in (-1.7, 1.7):
            cyl_y(lib, st, "Stegpfahl", cx + dx, -1.04, -0.5, cz + dz, 0.5, TRUNK, "Wood")
    for dx in (-1.85, 1.85):
        box(lib, st, "Stegkante", cx + dx - 0.15, cx + dx + 0.15, -0.2, 0.1, cz + 9, cz + 30, WOOD, "Wood", deco=True)
    bench(lib, st, cx, cz + 10.4, -0.2, 0, -1, 3.2, WOOD)
    # Fontäne in der Teichmitte (Anim=fountain)
    fo = lib.model(anim, "Teichfontaene", attrs={"Anim": "fountain", "Amplitude": 0.35, "Period": 2.4})
    cyl_y(lib, fo, "Duese", cx, -0.80, -0.55, cz, 1.6, STEEL, "Metal", deco=True)
    cyl_y(lib, fo, "Strahl", cx, -0.55, 6.0, cz, 0.7, (215, 238, 250), "Glass", transparency=0.35, deco=True)
    lib.ball(fo, "Gischt", (cx, 6.1, cz), 2.2, (225, 242, 252), "Glass", transparency=0.5, deco=True)
    return m


def build_pavilion(parent, lib):
    m = lib.model(parent, "Musikpavillon")
    cx, cz = PAV
    cyl_y(lib, m, "Stufe", cx, Y_GRASS, -0.3, cz, 19, CONC_L, "Concrete")
    cyl_y(lib, m, "Buehne", cx, -0.3, 0.4, cz, 16, (150, 110, 75), "WoodPlanks")
    r = 7.2
    tops = []
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
        cyl_y(lib, m, "Saeule", px, 0.4, 9.0, pz, 0.7, LWHITE, "SmoothPlastic")
        tops.append((px, pz))
    cyl_y(lib, m, "Traufe", cx, 9.0, 9.6, cz, 18.5, SLATE, "Metal")
    cyl_y(lib, m, "Traufband", cx, 9.1, 9.5, cz, 18.8, AMBER, "Metal", deco=True)
    # Dach: 8 Keile als Achteck-Pyramide, Spitze mit Amber-Kugel
    d, h = 9.0, 4.2
    wd = 2 * d * math.tan(math.pi / 8) + 0.1
    for k in range(8):
        a = 2 * math.pi * k / 8
        ox, oz = math.cos(a), math.sin(a)
        cf = CF.at(cx + ox * d / 2, 9.6 + h / 2, cz + oz * d / 2, yaw_towards(ox, oz))
        lib.wedge(m, "Dach", (wd, h, d), cf, GRAPHITE, "Slate")
    lib.ball(m, "Spitze", (cx, 9.6 + h + 0.3, cz), 1.2, AMBER, "Neon", deco=True)
    # Lichterketten zwischen den Säulen + Glühbirnen
    for k in range(8):
        a, b = tops[k], tops[(k + 1) % 8]
        lib.beam(m, "Lichterkette", (a[0], 8.6, a[1]), (b[0], 8.6, b[1]), 0.12, AMBER, "Neon", deco=True)
        lib.ball(m, "Gluehbirne", ((a[0] + b[0]) / 2, 8.31, (a[1] + b[1]) / 2), 0.5, AMBER, "Neon", deco=True)
    # Laterne in der Mitte (Licht (-250,8,305))
    box(lib, m, "Laternenstab", cx - 0.1, cx + 0.1, 8.7, 9.0, cz - 0.1, cz + 0.1, STEEL, "Metal", deco=True)
    lat = lib.part(m, "Laterne", (1.2, 1.4, 1.2), CF(cx, 8.0, cz), LAMP, "SmoothPlastic", deco=True)
    set_attrs(lat, {"NightNeon": True})
    lib.point_light(lat, 28, 0.9, LAMP)
    # Notenständer + Schild am Weg
    cyl_y(lib, m, "Notenstaender", cx + 2, 0.4, 3.6, cz + 2.5, 0.15, BLACK, "Metal", deco=True)
    lib.part(m, "Notenpult", (1.4, 1.0, 0.1), CF(cx + 2, 3.9, cz + 2.5) * CF.angles(math.radians(-25), 0, 0),
             BLACK, "Metal", deco=True)
    box(lib, m, "Schildpfosten", -245.2, -244.8, Y_GRASS, 3.2, 290.8, 291.2, SLATE, "Metal")
    lib.sign(m, "MUSIKPAVILLON", (4.6, 1.2), CF.at(-245, 3.5, 290.7, 180), AMBER, SLATE, name="Schild")
    return m


def build_photo_spot(parent, lib):
    """Amber "UCG"-Buchstaben (10 hoch) auf Schiefersockel bei (-222,·,185), Blick nach Osten; Fotopunkt am Ostweg."""
    m = lib.model(parent, "Fotopunkt")
    box(lib, m, "Sockel", -225, -219, Y_GRASS, 0.5, 172.5, 197.5, SLATE, "Slate")
    sk = lib.part(m, "Sockelschild", (0.1, 1.2, 20), CF(-218.95, -0.15, 185), SLATE, "SmoothPlastic", deco=True)
    lib.surface_text(sk, "ULTIMATE CAR GAME · SPIELERMEILE", face="Right", text_color=AMBER)
    x0, x1 = -222.75, -221.25
    y0, y1 = 0.5, 10.5
    s = 1.5

    def seg(z0, z1, ya, yb):
        p = box(lib, m, "Buchstabe", x0, x1, ya, yb, z0, z1, AMBER, "SmoothPlastic")
        set_attrs(p, {"NightNeon": True})
    # Leser schaut nach Westen: links = +Z. Buchstabe belegt [a, a+6], linke Kante a+6
    a = 190     # U
    seg(a + 6 - s, a + 6, y0 + s, y1)
    seg(a, a + s, y0 + s, y1)
    seg(a, a + 6, y0, y0 + s)
    a = 182     # C
    seg(a + 6 - s, a + 6, y0, y1)
    seg(a, a + 6 - s, y1 - s, y1)
    seg(a, a + 6 - s, y0, y0 + s)
    a = 174     # G
    seg(a + 6 - s, a + 6, y0, y1)
    seg(a, a + 6 - s, y1 - s, y1)
    seg(a, a + 6 - s, y0, y0 + s)
    seg(a, a + s, y0 + s, 5.5)
    seg(a + s, a + 3.2, 4.0, 5.5)
    # Bodenmarke FOTOPUNKT auf dem Ostweg (liest sich mit Blick nach Westen)
    fp = lib.part(m, "Fotopunkt_Marke", (4.6, 0.05, 4.6), CF.at(-200, -0.975, 185, 90), AMBER, "SmoothPlastic",
                  deco=True)
    lib.surface_text(fp, "FOTOPUNKT", face="Top", text_color=SLATE)
    return m


def build_tyre_course(parent, lib):
    m = lib.model(parent, "Reifenparcours")
    cx, cz = -400, 210
    pts = [(-16, -6), (-8, -6), (0, -6), (8, -6), (16, -6), (-12, 2), (-4, 2), (4, 2), (12, 2), (0, 9)]
    for i, (dx, dz) in enumerate(pts):
        cyl_y(lib, m, "Reifen", cx + dx, Y_G, Y_G + 1.3, cz + dz, 4.2, (28, 30, 34), "Plastic")
    for dx in (-12, 12):
        box(lib, m, "Sprungblock", cx + dx - 2, cx + dx + 2, Y_G, 1.5, cz + 11, cz + 15, AMBER, "Wood")
        lib.wedge(m, "Sprungrampe", (4, 2.5, 4), CF.at(cx + dx, Y_G + 1.25, cz + 9, 0), (200, 150, 60), "Wood")
    box(lib, m, "Schildpfosten", -379.2, -378.8, Y_G, 3.4, 196.8, 197.2, SLATE, "Metal")
    lib.sign(m, "REIFEN-PARCOURS", (5.2, 1.3), CF.at(-379, 3.7, 197.3, 0), AMBER, SLATE, name="Schild")
    return m


def build_park_green(parent, lib):
    m = lib.model(parent, "Gruen")
    # 10 Heldenbäume
    trees = [(-190, 232), (-214, 262), (-286, 196), (-356, 192), (-444, 252), (-384, 302), (-282, 326),
             (-214, 326), (-452, 180), (-352, 332)]
    for i, (x, z) in enumerate(trees):
        lib.tree_lite(m, x, Y_GRASS, z, scale=1.9, seed=i + 3, name="Parkbaum")
    # 6 Bänke (zum Weg), 2 Abfalleimer
    bench(lib, m, -240, 170.4, Y_GRASS, 0, -1)
    bench(lib, m, -280, 170.4, Y_GRASS, 0, -1)
    bench(lib, m, -206, 250, Y_GRASS, 1, 0)
    bench(lib, m, -206, 282, Y_GRASS, 1, 0)
    for ang in (45, 135):
        a = math.radians(ang)
        bench(lib, m, POND[0] + math.cos(a) * 39.5, POND[1] + math.sin(a) * 39.5, Y_GRASS, -math.cos(a),
              -math.sin(a))
    trash_bin(lib, m, -260, 170.6, Y_GRASS)
    trash_bin(lib, m, -206, 266, Y_GRASS)
    # Blumenbeete (rund)
    for i, (x, z) in enumerate(((-190, 180), (-236, 290), (-300, 180), (-420, 240))):
        cyl_y(lib, m, "Beeteinfassung", x, Y_GRASS, -0.6, z, 6, (140, 90, 70), "Brick")
        cyl_y(lib, m, "Beet", x, -0.6, -0.45, z, 5.2, (70, 110, 60), "Grass", deco=True)
        for k in range(4):
            a = math.radians(k * 90 + i * 20)
            col = [(220, 70, 120), (250, 200, 60), (170, 90, 220), (240, 240, 240)][(k + i) % 4]
            lib.ball(m, "Blume", (x + math.cos(a) * 1.4, -0.2, z + math.sin(a) * 1.4), 1.0, col, "SmoothPlastic",
                     deco=True)
    # Hecken am Rand (2.5 hoch), Lücken für Eingang und Hintereingang
    hy = Y_GRASS + 2.5
    box(lib, m, "Hecke", -468, -329, Y_GRASS, hy, 158.5, 160, HEDGE_C, "Grass")
    box(lib, m, "Hecke", -317, -180, Y_GRASS, hy, 158.5, 160, HEDGE_C, "Grass")
    box(lib, m, "Hecke", -180, -178.5, Y_GRASS, hy, 172, 340, HEDGE_C, "Grass")
    box(lib, m, "Hecke", -468, -180, Y_GRASS, hy, 338.5, 340, HEDGE_C, "Grass")
    box(lib, m, "Hecke", -468, -466.5, Y_GRASS, hy, 160, 338.5, HEDGE_C, "Grass")
    # Eingangstor (Z14): Durchgang 11.6 hoch (Kamera-Ausleger passt darunter), Schild STADTPARK steht auf dem
    # Torbalken und zeigt nach Osten; Hintereingang-Schild
    g = lib.model(m, "Eingangstor")
    for z in (159.9, 170.1):
        box(lib, g, "Torpfeiler", -177.4, -175.8, Y_GRASS, 11.2, z - 0.8, z + 0.8, (140, 90, 70), "Brick")
        box(lib, g, "Pfeilerkappe", -177.6, -175.6, 11.2, 11.6, z - 1.0, z + 1.0, SLATE, "Metal")
    box(lib, g, "Torbalken", -177.0, -176.2, 11.6, 12.6, 159.1, 170.9, SLATE, "Metal")
    lib.sign(g, "STADTPARK", (9.6, 2.0), CF.at(-176.6, 13.6, 165, 90), AMBER, SLATE, name="Schild",
             sub="Teich · Musikpavillon · Fotopunkt")
    box(lib, m, "Schildpfosten", -330.2, -329.8, Y_GRASS, 3.8, 160.4, 160.8, SLATE, "Metal")
    lib.sign(m, "STADTPARK", (4.4, 1.2), CF.at(-330, 4.1, 160.35, 180), AMBER, SLATE, name="Schild_Hintereingang")
    return m


# ================================================================ Skyline
TOWERS = [(-420, -430, 90), (-200, -430, 120), (60, -430, 75), (300, -430, 140), (480, -430, 100),
          (630, -200, 85), (630, 250, 110), (-630, 0, 95)]


def build_skyline(anim, lib):
    for i, (x, z, h) in enumerate(TOWERS):
        crown = AMBER if i % 2 == 0 else TEAL
        m = lib.model(anim, "Turm_%d" % (i + 1), attrs={"Anim": "nightwindows", "NightColor": Color3(*WIN_NIGHT),
                                                       "NightTransparency": 0.55})
        box(lib, m, "Koerper", x - 20, x + 20, Y_GRASS, h, z - 20, z + 20, SKY_BODY, "Concrete")
        # Stadtseite: 3 Fensterbänder, Nachbarseiten je 1, Rückseite keine (9 Parts je Turm)
        if abs(x) > 600:
            city = (-1 if x > 0 else 1, 0)
        else:
            city = (0, 1)
        faces = [(city, (-12, 0, 12))]
        side = (city[1], city[0])
        faces += [(side, (0,)), ((-side[0], -side[1]), (0,))]
        for (nx, nz), offs in faces:
            for o in offs:
                if nx:
                    fx = x + nx * 20.15
                    win = box(lib, m, "Fenster", fx - 0.15, fx + 0.15, 4, h - 6, z + o - 1.5, z + o + 1.5, GLASS,
                              "Glass", transparency=0.1, deco=True)
                else:
                    fz = z + nz * 20.15
                    win = box(lib, m, "Fenster", x + o - 1.5, x + o + 1.5, 4, h - 6, fz - 0.15, fz + 0.15, GLASS,
                              "Glass", transparency=0.1, deco=True)
                set_attrs(win, {"NightNeon": True, "NightColor": Color3(*WIN_NIGHT), "NightTransparency": 0.55})
        box(lib, m, "Krone", x - 20.3, x + 20.3, h - 4, h - 2.6, z - 20.3, z + 20.3, crown, "Neon", deco=True)
        cyl_y(lib, m, "Antenne", x + 4, h, h + 17, z, 0.6, STEEL, "Metal", deco=True)
        lib.ball(m, "Warnlicht", (x + 4, h + 17.5, z), 1.4, (230, 30, 30), "Neon", deco=True,
                 attrs={"Anim": "beacon", "Period": 1.5})
    return anim


# ================================================================ Spielermeile-Deko
def build_meile(dm, anim, lib):
    m = lib.model(dm, "Meile")
    bus_stop(lib, m, 80, -20, 0, "Haltestelle_Nord")
    bus_stop(lib, m, -80, 20, 180, "Haltestelle_Sued")
    # BUS-Schrift auf der Fahrbahn vor den Haltestellen
    flat_text(lib, m, "Schrift_Bus", "BUS", 80, Y_MARK, -9.2, 6, 3, 90, (240, 190, 40))
    flat_text(lib, m, "Schrift_Bus", "BUS", -80, Y_MARK, 9.2, 6, 3, -90, (240, 190, 40))
    alleys(lib, m)
    banners(lib, anim)
    return m


def bus_stop(lib, parent, cx, cz, yaw, name):
    """Wartehäuschen "Markt": Rückwand (lokal z -1..-0.8), Kragdach über dem Gehweg, Blick nach lokal +Z."""
    m = lib.model(parent, name)
    base = CF.at(cx, -0.5, cz, yaw)
    lbox(lib, m, "Rueckwand", base, -5.5, 5.5, 0.4, 7.5, -1.0, -0.8, GLASS, "Glass", transparency=0.4)
    for x in (-5.8, 5.8):
        lbox(lib, m, "Pfosten", base, x - 0.3, x + 0.3, 0, 8.5, -1.2, -0.6, SLATE, "Metal")
    lbox(lib, m, "Sockel", base, -5.5, 5.5, 0, 0.4, -1.0, -0.8, SLATE, "Metal")
    lbox(lib, m, "Dach", base, -6.5, 6.5, 8.5, 9.0, -3.0, 3.2, GRAPHITE, "Metal")
    lbox(lib, m, "Dachneon", base, -6.5, 6.5, 8.3, 8.5, 3.0, 3.2, AMBER, "Neon", deco=True)
    lbox(lib, m, "Seitenglas", base, -5.7, -5.5, 0.4, 7.5, -0.6, 1.8, GLASS, "Glass", transparency=0.4)
    lbox(lib, m, "Sitz", base, -3.5, 3.5, 1.3, 1.6, -0.8, 0.6, WOOD_L, "Wood")
    for x in (-3, 3):
        lbox(lib, m, "Sitzbein", base, x - 0.15, x + 0.15, 0, 1.3, -0.6, 0.4, BLACK, "Metal")
    ad = lib.part(m, "Werbetafel", (0.2, 6, 2.4), base * CF(5.6, 3.6, 0.6), TEAL, "SmoothPlastic", deco=True)
    add_lines(lib, ad, [("UCG", (255, 255, 255), 1.2), ("Deine Werkstatt wartet!", SLATE, 1.0)], face="Left")
    lib.sign(m, "HALTESTELLE MARKT", (8, 1.0), base * CF(0, 9.55, 3.2), AMBER, SLATE, name="Schild")
    # H-Mast an der Bordsteinkante
    hx, hz = 7.5, 5.5
    lbox(lib, m, "H_Mast", base, hx - 0.15, hx + 0.15, 0, 8.4, hz - 0.15, hz + 0.15, STEEL, "Metal")
    h = lib.part(m, "H_Schild", (2.2, 2.2, 0.12), base * CF(hx, 7.6, hz + 0.21), (240, 200, 40), "SmoothPlastic",
                 deco=True)
    lib.surface_text(h, "H", text_color=(20, 120, 60), font="GothamBlack")
    lib.surface_text(h, "H", face="Front", text_color=(20, 120, 60), font="GothamBlack", name="Rueckseite")
    fp = lib.part(m, "Fahrplan", (1.2, 1.6, 0.08), base * CF(hx, 4.4, hz + 0.19), LWHITE, "SmoothPlastic", deco=True)
    add_lines(lib, fp, [("Linie A", SLATE, 1.0), ("Meile-Schleife", SLATE, 0.7), ("alle 6 min", RED, 0.7)])
    return m


def alleys(lib, parent):
    """Gassenportale (X ±318..±328, an den Meile-Mündungen Z ±24), Bänke und Abfalleimer in den Gassen."""
    m = lib.model(parent, "Gassen")
    names = {(-1, -1): ("SCHROTTGASSE", "Schrottplatz · Hintertor"), (1, -1): ("TUNINGGASSE", "Tuning-Zentrum · Treff"),
             (-1, 1): ("PARKGASSE", "Stadtpark · Teich"), (1, 1): ("WASCHGASSE", "Tankstelle · Waschstraße")}
    for (sx, sz), (title, sub) in names.items():
        g = lib.model(m, "Gasse_" + title.title())
        xc = sx * 323
        zc = sz * 24
        for px in (xc - 4.3, xc + 4.3):
            box(lib, g, "Portalpfosten", px - 0.25, px + 0.25, Y_GRASS, 10.4, zc - 0.25, zc + 0.25, SLATE, "Metal")
        box(lib, g, "Portalbalken", xc - 4.55, xc + 4.55, 10.4, 10.8, zc - 0.3, zc + 0.3, AMBER, "Metal")
        # Schild hängt am Portalbalken (Oberkante 10.4 = Balkenunterseite)
        lib.sign(g, title, (7.6, 2.0), CF.at(xc, 9.4, zc - sz * 0.35, 0 if sz < 0 else 180), AMBER, SLATE,
                 name="Schild", sub=sub)
        # Eimer beidseits des Wegs an der Mündung, Bank(en) auf dem Grünstreifen
        for ex in (xc - 3.7, xc + 3.7):     # im Grünstreifen, auch die ungedrehte Size bleibt in der Gasse
            trash_bin(lib, g, ex, sz * 27.5, Y_GRASS)
        bench_sides = [-1] if (sx, sz) in ((1, -1), (-1, 1)) else [-1, 1]
        for bs in bench_sides:
            bx = xc + bs * 4.0
            bench(lib, g, bx, sz * 34, Y_GRASS, -bs, 0, 4.4)
    return m


def banners(lib, anim):
    """12 Lampenbanner (amber/türkis) an den Meile-Laternen X ±100 (Süd-Ost: 110), ±306/310, ±456/460 - Anim=flag."""
    picks = {100, 110, 306, 310, 456, 460}       # 110: Laterne neben der Absenkung Übergabe-Halle
    i = 0
    for grp, x, z, dx, dz in street_lamps():
        if grp != "Meile" or abs(x) not in picks:
            continue
        i += 1
        away = 1 if z > 0 else -1          # vom Fahrbahnrand weg
        col = AMBER if i % 2 else TEAL
        txt = SLATE if col == AMBER else (255, 255, 255)
        m = lib.model(anim, "Banner_%d" % i, attrs={"Anim": "flag", "Swing": 6, "Period": 3.2})
        zr = z + away * 0.31              # Stange liegt am Laternenmast an (r 0.225 + 0.09)
        cyl_y(lib, m, "Stange", x, 7.0, 12.0, zr, 0.18, STEEL, "Metal", deco=True)
        z0 = z + away * 0.40              # Tuch schließt an die Stange an
        z1 = z + away * 2.85
        tuch = box(lib, m, "Tuch", x - 0.05, x + 0.05, 7.3, 11.8, z0, z1, col, "Fabric", deco=True)
        for face in ("Right", "Left"):
            add_lines(lib, tuch, [("UCG", txt, 1.3), ("WERKSTATT", txt, 0.55), ("MEILE", txt, 0.55)], face=face)
    return anim
