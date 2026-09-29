"""Tuning-Zentrum (D9): Halle, Lounge, Teile-Wand, Prüfstand (dyno), Projektbuchten, Vorplatz-Rampe, TUNING-Pylon,
Tuning-Treff, Dragstrip-Deko (docs/CITY_SPEC.md §6 D9).

Gebaut wird unter City.Districts.Tuning (statische Kulisse, 7 Lichter: Halle 5, Vorplatz 1, Treff 1) und
City.Animated.Tuning:
  * Eingangstuer_Nord / _Sued  Anim=door (Schiebeflügel, Axis Z) - Glas + Stiel, PrimaryPart = Glas
  * Rolltor                    Anim=door (Axis Y, Lift 13.8; bleibt unter den Bindern Y 30)
  * Pruefstand                 Anim=dyno: Rolle1..4 (Zylinder, Achse lokal X), Walzenluefter_Blatt (Lüfterrad, dreht
                               wie eine Rolle), Car (Sportwagen orange), Screen (LEISTUNG-Kurve), Auspuffflamme (T 1)
  * Hebebuehne_1..4            Anim=lift (Lift 4): Kind-Model "Plattform" (Fahrschienen, Schlitten, Auto) bewegt sich,
                               Säulen / Querträger / Statusbildschirm bleiben stehen
  * Treff-Bogen                Anim=neon (ColorB Magenta)
  * Startampel                 Anim=startlight (Lampe1..4 Neon, nach Namen sortiert)
Stationen tuning / dyno und die Ankunft tuning baut contract.py; hier steht die Kulisse drumherum
(Tresen vor (234,3,-201), Prüfstand hinter (310,3,-206), je 10 x 10 freier Boden auf der Spielerseite).

Höhen-Stapel (nie zwei überlappende Oberseiten auf gleicher Höhe):
  Gelände -1.00 (Treff-Belag bündig -1.00 in einer Aussparung, ground_roads.GROUND_INSETS) | Dragstrip-Asphalt,
  Vorplatz-Leitstreifen, Treff-Markierungen -0.95 | Vorplatz-Zufahrtslinien -0.94 | Dragstrip-Markierungen -0.90
  | Fußweg / Eingangsstufe -0.50 | Hallenboden 0 | Teppich / Linien / Prüfstand-Rahmen +0.05 | Drehscheibe
  0.12 / 0.42 | Fahrschienen 0.5

Abweichungen von der Spec (begründet):
  * Showcar-Rampe bei (196,-276) statt (196,-250): (196,-250) liegt in der Rolltor-Zufahrt Z -258..-240 (§3.4),
    die frei bleiben muss. Keilhöhe 2.53 statt 2, damit Rampe und Auto dieselben 8° haben (Räder liegen auf).
  * Binder Y 30..32 statt 30..31.5 (liegen an der Deckenplatte an statt zu schweben; lichte Höhe bleibt 30).
  * Pendelleuchten hängen bei Y 29 unter der Decke zwischen den Bindern (Spec-Positionen).
"""
import math

from ..lib import (CF, AMBER, BLACK, FRAME, GLASS, GRAPHITE, SLATE, STEEL, TEAL, TRUSS, WHITE, Color3, is_basepart,
                   name_of, set_scalar)

NAME = "Tuning"

# ---------------------------------------------------------------- Farben (CITY_SPEC §1.4 Tuning)
FLOOR = (22, 26, 31)            # schwarzer Hallenboden, Refl 0.12
MAGENTA = (255, 64, 180)
SCREEN_BG = (27, 72, 82)
SCREEN_TXT = (121, 225, 206)
PETROL = (43, 102, 121)
HALL_LIGHT = (224, 238, 255)
NEON_WHITE = (232, 246, 249)
TREFF_PAD = (30, 34, 40)
CARBON = (28, 30, 34)
LEATHER = (34, 36, 40)
RUG = (30, 54, 58)
TITAN = (112, 92, 168)          # angelaufene Titan-Endrohre

# ---------------------------------------------------------------- Lage (§6 D9)
HX0, HX1, HZ0, HZ1 = 214, 334, -290, -170
WT = 0.8
IX0, IX1, IZ0, IZ1 = HX0 + WT, HX1 - WT, HZ0 + WT, HZ1 - WT     # Innenflächen
ROOF_Y = 32.0
PARAPET = 38.0
DOOR = (-208, -194)             # Eingangstüren Z (14 x 12)
ROLL = (-258, -240)             # Rolltor Z (18 x 16)
BAYS = [237, 263, 289, 315]
BAY_Z = -274
DYNO = (310, -220)
Y_G = -1.0


def build(city, lib, tree):
    """Baut Tuning (siehe docs/CITY_SPEC.md §6 D9)."""
    dm = lib.model(lib.folder(city, "Districts"), NAME)
    anim = lib.folder(lib.folder(city, "Animated"), NAME)
    with lib.section("D9 Tuning"):
        build_shell(dm, lib)
        build_facade(dm, anim, lib)
        build_lounge(dm, lib)
        build_parts_wall(dm, lib)
        build_dyno(dm, anim, lib)
        build_showroom(dm, lib)
        build_bays(dm, anim, lib)
        build_forecourt(dm, anim, lib)
        build_treff(dm, anim, lib)
        build_dragstrip(dm, anim, lib)
    return dm


def matte(lib, car):
    """Lack matt: Paint/Hood/Mirror SmoothPlastic statt Metal"""
    for it in car.iter("Item"):
        if is_basepart(it) and name_of(it) in ("Paint", "Hood", "Mirror"):
            set_scalar(it, "token", "Material", "272")


# ---------------------------------------------------------------- Hallenhülle
def build_shell(dm, lib):
    m = lib.model(dm, "Halle")
    lib.box(m, "Hallenboden", HX0, HX1, -1, 0, HZ0, HZ1, FLOOR, "SmoothPlastic", reflectance=0.12)
    # Nord-, Süd-, Ostwand: Schiefer, Glasband Y 16..26 (eingerückt), weiße Doppelstreifen außen bei Y 6
    for nm, x0, x1, z0, z1, axis in (("Nordwand", HX0, HX1, HZ0, IZ0, "z"), ("Suedwand", HX0, HX1, IZ1, HZ1, "z"),
                                     ("Ostwand", IX1, HX1, IZ0, IZ1, "x")):
        lib.box(m, nm, x0, x1, 0, 16, z0, z1, SLATE, "Metal")
        lib.box(m, nm + "_Oben", x0, x1, 26, PARAPET, z0, z1, SLATE, "Metal")
        if axis == "z":
            c = (z0 + z1) / 2
            lib.box(m, nm + "_Glasband", x0, x1, 16, 26, c - 0.15, c + 0.15, GLASS, "Glass", transparency=0.3)
        else:
            c = (x0 + x1) / 2
            lib.box(m, nm + "_Glasband", c - 0.15, c + 0.15, 16, 26, z0, z1, GLASS, "Glass", transparency=0.3)
    for y0 in (5.1, 6.3):
        y1 = y0 + 0.6
        lib.box(m, "Rennstreifen", HX0, HX1, y0, y1, HZ0 - 0.08, HZ0, WHITE, "SmoothPlastic", deco=True)
        lib.box(m, "Rennstreifen", HX0, HX1, y0, y1, HZ1, HZ1 + 0.08, WHITE, "SmoothPlastic", deco=True)
        lib.box(m, "Rennstreifen", HX1, HX1 + 0.08, y0, y1, HZ0 - 0.08, HZ1 + 0.08, WHITE, "SmoothPlastic",
                deco=True)
    # Innen: türkises Neonband unter dem Glasband (Ost geteilt um den LEISTUNG-Bildschirm)
    ny = (15.8, 16.0)
    lib.box(m, "Neonband", IX0, IX1, ny[0], ny[1], IZ0, IZ0 + 0.15, TEAL, "Neon", deco=True)
    lib.box(m, "Neonband", IX0, IX1, ny[0], ny[1], IZ1 - 0.15, IZ1, TEAL, "Neon", deco=True)
    lib.box(m, "Neonband", IX1 - 0.15, IX1, ny[0], ny[1], IZ0 + 0.15, -234.6, TEAL, "Neon", deco=True)
    lib.box(m, "Neonband", IX1 - 0.15, IX1, ny[0], ny[1], -205.4, IZ1 - 0.15, TEAL, "Neon", deco=True)
    # Decke 32..33 (32 frei), 6 Binder Y 30..32 quer (Ost-West), Dachaufbauten
    lib.box(m, "Deckenplatte", IX0, IX1, ROOF_Y, ROOF_Y + 1, IZ0, IZ1, GRAPHITE, "Metal")
    for k in range(6):
        zc = HZ1 - (k + 1) * (HZ1 - HZ0) / 7.0
        lib.box(m, "Binder", IX0, IX1, 30, ROOF_Y, zc - 0.5, zc + 0.5, TRUSS, "Metal")
    lib.box(m, "Lueftungsgeraet", 290, 306, 33, 36, -270, -262, (70, 78, 86), "Metal")
    lib.box(m, "Lueftungsgeraet", 250, 262, 33, 35.5, -200, -190, (70, 78, 86), "Metal")
    # Hallenlicht: 5 Pendelleuchten bei Y 29 (Range 40)
    for x, z in ((244, -190), (274, -190), (304, -190), (259, -260), (304, -260)):
        lib.box(m, "Pendel", x - 0.08, x + 0.08, 29.6, ROOF_Y, z - 0.08, z + 0.08, STEEL, "Metal", deco=True)
        lib.box(m, "Leuchtengehaeuse", x - 1.6, x + 1.6, 29.1, 29.6, z - 1.6, z + 1.6, SLATE, "Metal", deco=True)
        lamp = lib.box(m, "Leuchte", x - 1.3, x + 1.3, 28.98, 29.1, z - 1.3, z + 1.3, NEON_WHITE, "Neon", deco=True)
        lib.point_light(lamp, 40, 1.1, HALL_LIGHT, name="HallenLicht")
    # Außenschilder Süd (zur Meile) und Ost (zum Treff)
    lib.sign(m, "TUNING-ZENTRUM", (40, 6), CF.at(274, 32, HZ1 + 0.1, 0), TEAL, SLATE, name="Schild_Sued", bolts=False)
    lib.sign(m, "PRÜFSTAND · PROJEKTE · TEILE", (40, 4.4), CF.at(HX1 + 0.1, 32, -230, 90), TEAL, SLATE,
             name="Schild_Ost", bolts=False)


# ---------------------------------------------------------------- Westfassade, Türen, Rolltor
def build_facade(dm, anim, lib):
    m = lib.model(dm, "Westfassade")
    gx0, gx1 = HX0 + 0.25, HX0 + 0.55
    # Glasflächen
    lib.box(m, "Glasfront", gx0, gx1, 0, 27.98, IZ0, ROLL[0] - 0.6, GLASS, "Glass", transparency=0.3)
    lib.box(m, "Glasfront", gx0, gx1, 0, 27.98, ROLL[1] + 0.6, DOOR[0] - 0.6, GLASS, "Glass", transparency=0.3)
    lib.box(m, "Glasfront", gx0, gx1, 0, 27.98, DOOR[1] + 0.6, IZ1, GLASS, "Glass", transparency=0.3)
    lib.box(m, "Oberlicht_Rolltor", gx0, gx1, 16.8, 28, ROLL[0], ROLL[1], GLASS, "Glass", transparency=0.3)
    lib.box(m, "Oberlicht_Eingang", gx0, gx1, 12.6, 28, DOOR[0], DOOR[1], GLASS, "Glass", transparency=0.3)
    # Pfosten (Schiefer, alle 12) und Leibungen
    for z in (-278, -266, -230, -218, -182):
        lib.box(m, "Pfosten", HX0, IX0, 0, 28, z - 0.3, z + 0.3, SLATE, "Metal")
    for z0, z1 in ((ROLL[0] - 0.6, ROLL[0]), (ROLL[1], ROLL[1] + 0.6), (DOOR[0] - 0.6, DOOR[0]),
                   (DOOR[1], DOOR[1] + 0.6)):
        lib.box(m, "Leibung", HX0, IX0, 0, 28, z0, z1, SLATE, "Metal")
    lib.box(m, "Sturz_Rolltor", HX0, IX0, 16, 16.8, ROLL[0], ROLL[1], SLATE, "Metal")
    lib.box(m, "Sturz_Eingang", HX0, IX0, 12, 12.6, DOOR[0], DOOR[1], SLATE, "Metal")
    # Attika 28..38 mit Neonlinie bei 28.5 und Schild 70 x 7
    lib.box(m, "Attika", HX0, IX0, 28, PARAPET, IZ0, IZ1, SLATE, "Metal")
    neon = lib.box(m, "Neonlinie", HX0 - 0.15, HX0, 28.3, 28.7, HZ0, HZ1, TEAL, "Neon", deco=True, transparency=0.4)
    lib.attrs(neon, NeonStrip=True)
    lib.sign(m, "TUNING-ZENTRUM", (70, 7), CF.at(HX0 - 0.1, 34, -230, -90), TEAL, SLATE, name="Fassadenschild")
    # Vordach über dem Eingang mit Beschriftung und Neonkante
    can = lib.box(m, "Vordach", 208, HX0, 12.8, 14.0, DOOR[0] - 1, DOOR[1] + 1, SLATE, "Metal")
    lib.surface_text(can, "EMPFANG · AUFTRÄGE", face="Left", text_color=TEAL)
    lib.box(m, "Vordach_Neon", 208.2, 208.6, 12.7, 12.8, DOOR[0] - 0.8, DOOR[1] + 0.8, TEAL, "Neon", deco=True)
    lib.box(m, "Eingangsstufe", 212.6, HX0, Y_G, -0.5, DOOR[0], DOOR[1], (114, 121, 124), "Concrete")
    # Rolltor: Führungsschienen, Rampe 1:6, Schild über der Einfahrt
    for z0, z1 in ((ROLL[0], ROLL[0] + 0.4), (ROLL[1] - 0.4, ROLL[1])):
        lib.box(m, "Fuehrungsschiene", IX0, IX0 + 0.8, 0, 16, z0, z1, STEEL, "Metal")
    lib.wedge(m, "Einfahrtsrampe", (18, 1, 6), CF.at(211, -0.5, -249, 90), (114, 121, 124), "Concrete")
    lib.sign(m, "EINFAHRT · PROJEKTE", (12, 1.6), CF.at(HX0 + 0.15, 17.8, -249, -90), AMBER, BLACK,
             name="Einfahrtsschild", bolts=False)

    # --- Animated: Schiebetüren und Rolltor
    def leaf(nm, z0, z1, lift, stile_z):
        md = lib.model(anim, nm, attrs={"Anim": "door", "Axis": "Z", "Lift": lift, "Period": 10, "Door": "Tuning",
                                        "OpenRange": 12, "OpenTime": 0.6, "Mode": "slide"})
        gl = lib.box(md, "Glas", 214.9, 215.1, 0, 11.9, z0, z1, GLASS, "Glass", transparency=0.3, collide=False,
                     cast_shadow=False)
        lib.set_primary(md, gl)
        lib.box(md, "Stiel", 214.85, 215.15, 0, 11.8, stile_z - 0.2, stile_z + 0.2, STEEL, "Metal", collide=False)
        return md
    leaf("Eingangstuer_Nord", DOOR[0], -201, -6.8, -201.25)
    leaf("Eingangstuer_Sued", -201, DOOR[1], 6.8, -200.75)
    rt = lib.model(anim, "Rolltor", attrs={"Anim": "door", "Axis": "Y", "Lift": 13.8, "Period": 14, "Door": "Tuning",
                                          "OpenRange": 12, "OpenTime": 0.6, "Mode": "roll"})
    pn = lib.box(rt, "Panel", 215.0, 215.4, 0, 16, ROLL[0] + 0.4, ROLL[1] - 0.4, FRAME, "Metal", collide=False)
    lib.set_primary(rt, pn)
    lib.box(rt, "Panel_Streifen", 214.92, 215.0, 7.4, 8.6, ROLL[0] + 0.6, ROLL[1] - 0.6, TEAL, "SmoothPlastic",
            deco=True)


# ---------------------------------------------------------------- Z1 Lounge und Empfangstresen
def build_lounge(dm, lib):
    m = lib.model(dm, "Lounge")
    # Tresen 3 x 14, Front bei X 236.5, Mitte Z -201 (Station tuning davor bei X 234)
    lib.box(m, "Tresen", 236.5, 239.5, 0, 3.4, -208, -194, SLATE, "Metal")
    lib.box(m, "Tresenplatte", 236.2, 239.8, 3.4, 3.7, -208.3, -193.7, WHITE, "Marble")
    lib.box(m, "Tresen_Neon", 236.4, 236.5, 2.8, 3.1, -207.6, -194.4, TEAL, "Neon", deco=True)
    lib.sign(m, "EMPFANG · AUFTRAGSANNAHME", (9, 1.5), CF.at(236.45, 1.75, -201, -90), TEAL, SLATE, name="Tresenschild",
             thickness=0.1, bolts=False)
    lib.box(m, "Monitorfuss", 238.4, 238.8, 3.7, 4.2, -202.2, -201.8, BLACK, "Metal", deco=True)
    lib.sign(m, "TUNING-KATALOG", (2.6, 1.6), CF.at(238.6, 5.0, -202, -90), SCREEN_TXT, SCREEN_BG, name="Monitor",
             bolts=False)
    # Farbleitlinie innen: Tür -> Tresen
    lib.box(m, "Leitlinie", 215.4, 232.5, 0, 0.05, -201.25, -200.75, TEAL, "SmoothPlastic", deco=True)
    # Trennwand hinter dem Tresen (10 hoch) mit Logo
    lib.box(m, "Trennwand", 243.6, 244, 0, 10, -211, -191, SLATE, "Metal")
    lib.box(m, "Trennwand_Neon", 243.6, 244, 10, 10.2, -211, -191, TEAL, "Neon", deco=True)
    lib.sign(m, "TUNING-ZENTRUM", (14, 4), CF.at(243.5, 6.4, -201, -90), TEAL, SLATE, name="Logo",
             sub="Leistung · Optik · Fahrwerk", sub_color=WHITE)
    # Sitzecke: Teppich, 2 Sofas, Couchtisch
    lib.box(m, "Teppich", 221, 235, 0, 0.05, -190, -176, RUG, "Fabric", deco=True, collide=False)
    lib.box(m, "Sofa", 218, 232, 0, 1.5, -175, -172, LEATHER, "Fabric")
    lib.box(m, "Sofalehne", 218, 232, 0, 3.4, -172, IZ1, LEATHER, "Fabric")
    lib.box(m, "Sofakissen", 218.2, 231.8, 1.5, 1.8, -174.8, -172, TEAL, "Fabric", deco=True)
    lib.box(m, "Sofa", 216.4, 219.4, 0, 1.5, -190, -177, LEATHER, "Fabric")
    lib.box(m, "Sofalehne", 215.2, 216.4, 0, 3.4, -190, -177, LEATHER, "Fabric")
    lib.box(m, "Sofakissen", 216.4, 219.2, 1.5, 1.8, -189.8, -177.2, TEAL, "Fabric", deco=True)
    lib.box(m, "Tischfuss", 225.5, 228.5, 0.05, 1.4, -184, -181, SLATE, "Metal")
    lib.box(m, "Tischplatte", 224, 230, 1.4, 1.6, -185.5, -179.5, (40, 50, 58), "Glass", reflectance=0.2)
    # Felgen-Vitrine: Sockel, stehende Felge, Neon-Nabe
    lib.box(m, "Vitrinensockel", 236.5, 239.5, 0, 2.4, -181.5, -178.5, SLATE, "Metal")
    lib.cylinder(m, "Schaufelge", (238, 4.1, -180), 0.8, 3.4, "X", (205, 210, 215), "Metal")
    lib.cylinder(m, "Schaufelge_Nabe", (238, 4.1, -180), 1.0, 1.1, "X", TEAL, "Neon", deco=True)
    # Pflanze am Eingang
    lib.cylinder(m, "Pflanzkuebel", (217, 0.7, -211.5), 1.4, 1.8, "Y", SLATE, "Metal")
    lib.ball(m, "Pflanze", (217, 2.6, -211.5), 2.6, (61, 100, 65), "Grass", deco=True)


# ---------------------------------------------------------------- Z2 Teile-Wand (Südwand innen)
def build_parts_wall(dm, lib):
    m = lib.model(dm, "TeileWand")
    zf = IZ1 - 0.3                                   # Vorderseite der Lochwand
    lib.box(m, "Lochwand", 250, 330, 1, 13, zf, IZ1, (38, 48, 58), "Metal")
    lib.box(m, "Lochwand_Neon", 250, 330, 13, 13.2, zf, IZ1, TEAL, "Neon", deco=True)
    lib.sign(m, "TEILE & ZUBEHÖR", (14, 1.6), CF.at(258, 11.6, zf - 0.1, 180), TEAL, SLATE, name="Titel", bolts=False)
    rims = [(205, 210, 215), (201, 162, 90), (30, 32, 36), TEAL, (140, 100, 60), WHITE, (70, 76, 82), (200, 50, 50)]
    k = 0
    for y in (8.0, 4.2):
        for x in (254, 259, 264, 269):
            col = rims[k]
            lib.cylinder(m, "Felge", (x, y, zf - 0.25), 0.5, 3.2, "Z", col, "Metal")
            lib.cylinder(m, "Felgendeckel", (x, y, zf - 0.4), 0.6, 1.1, "Z", AMBER if k % 2 == 0 else BLACK, "Metal",
                         deco=True)
            k += 1
    # 2 Heckflügel auf Konsolen
    for y, col in ((9.0, CARBON), (5.0, TEAL)):
        lib.box(m, "Konsole", 283.7, 284.3, y - 0.8, y, zf - 1.1, zf, STEEL, "Metal")
        lib.box(m, "Heckfluegel", 278, 290, y, y + 0.35, zf - 1.9, zf - 0.3, col, "Metal")
    # 3 Sportauspuffanlagen mit Titan-Endrohr
    for y in (10.2, 7.0, 3.8):
        lib.cylinder(m, "Auspuff", (308.5, y, zf - 0.45), 9, 0.9, "X", STEEL, "Metal")
        lib.cylinder(m, "Endrohr", (313.75, y, zf - 0.6), 1.5, 1.2, "X", TITAN, "Metal")
    lib.sign(m, "LEISTUNGS-PAKETE", (10, 7), CF.at(323, 6.5, zf - 0.1, 180), AMBER, SLATE, name="Preistafel",
             sub="Stufe 1 · Stufe 2 · Stufe 3", bolts=False)


# ---------------------------------------------------------------- Z3 Prüfstand (Anim=dyno)
def _curve_screen(lib, part):
    """LEISTUNG-Bildschirm: Titel, Werte und eine Leistungs-/Drehmomentkurve aus GUI-Balken (keine Parts)."""
    gui = lib.surface_text(part, None)
    lib.text_label(gui, "LEISTUNG", SCREEN_TXT, "GothamBold", "Titel", None, (0.4, 0.14), (0.04, 0.04))
    lib.text_label(gui, "412 PS · 530 Nm", AMBER, "GothamBold", "Werte", None, (0.42, 0.11), (0.54, 0.055))
    x0, x1, base, top = 0.06, 0.94, 0.9, 0.24
    lib.text_label(gui, "", SCREEN_TXT, "GothamBold", "AchseX", (72, 140, 150), (x1 - x0, 0.008), (x0, base))
    lib.text_label(gui, "", SCREEN_TXT, "GothamBold", "AchseY", (72, 140, 150), (0.004, base - top), (x0, top))
    n = 28
    w = (x1 - x0) / n
    for i in range(n):
        u = (i + 0.5) / n
        p = max(0.04, math.sin(u * math.pi * 0.62) ** 1.4 * (1.05 - 0.25 * max(0, u - 0.8) / 0.2))
        t = max(0.05, 0.92 - 1.4 * (u - 0.45) ** 2)
        h = p * (base - top)
        lib.text_label(gui, "", SCREEN_TXT, "GothamBold", "PS%02d" % i, TEAL, (w * 0.7, h), (x0 + i * w + w * 0.15,
                                                                                          base - h))
        ht = t * (base - top)
        lib.text_label(gui, "", SCREEN_TXT, "GothamBold", "Nm%02d" % i, AMBER, (w * 0.7, 0.012),
                       (x0 + i * w + w * 0.15, base - ht))
    lib.text_label(gui, "U/min", SCREEN_TXT, "Gotham", "Einheit", None, (0.12, 0.06), (0.84, 0.92))
    return gui


def build_dyno(dm, anim, lib):
    dx, dz = DYNO
    s = lib.model(dm, "Pruefstand_Umfeld")
    # Amber-Rahmen um die Rollengrube 12 x 20 (4 Leisten, +0.05); die Rollen ragen 0.37 aus dem Hallenboden
    for a0, a1, b0, b1 in ((dx - 6.3, dx + 6.3, dz - 10.3, dz - 10), (dx - 6.3, dx + 6.3, dz + 10, dz + 10.3),
                           (dx - 6.3, dx - 6, dz - 10, dz + 10), (dx + 6, dx + 6.3, dz - 10, dz + 10)):
        lib.box(s, "Grubenrahmen", a0, a1, 0, 0.05, b0, b1, AMBER, "Metal")
    # Sicherheitsbereich (gelbe Linien)
    for x0, x1, z0, z1 in ((298, 322, -237.8, -237.4), (298, 322, -207.6, -207.2), (298, 298.4, -237.4, -207.6),
                           (321.6, 322, -237.4, -207.6)):
        lib.box(s, "Sicherheitslinie", x0, x1, 0, 0.05, z0, z1, (240, 190, 40), "SmoothPlastic", deco=True)
    # Spanngurte vorn und hinten
    for sx in (-1, 1):
        lib.beam(s, "Spanngurt", (dx + sx * 2.6, 1.4, dz + 7.2), (dx + sx * 3.4, 0.1, dz + 10.6), 0.12, AMBER,
                 "Fabric", depth=0.6, deco=True)
        lib.beam(s, "Spanngurt", (dx + sx * 2.6, 1.4, dz - 7.2), (dx + sx * 3.4, 0.1, dz - 10.6), 0.12, AMBER,
                 "Fabric", depth=0.6, deco=True)
    # Steuerpult
    lib.box(s, "Steuerpult", 324, 327, 0, 3.2, -212, -208, SLATE, "Metal")
    panel = lib.part(s, "Pultplatte", (3.4, 0.3, 4.4), CF(325.5, 3.55, -210) * CF.angles(0, 0, math.radians(20)),
                     SCREEN_BG, "SmoothPlastic")
    lib.surface_text(panel, "PRÜFSTAND · START", face="Top", text_color=SCREEN_TXT)
    lib.sign(s, "LEISTUNGSPRÜFSTAND", (14, 1.8), CF.at(IX1 - 0.1, 27.9, -220, -90), TEAL, SLATE, name="Pruefstandschild",
             bolts=False)

    # --- Animated: Rollen, Lüfter, Auto, Bildschirm, Auspuffflamme
    m = lib.model(anim, "Pruefstand", attrs={"Anim": "dyno", "Speed": 2880, "Period": 45, "Station": "dyno"})
    s_ax = 1.3
    ry = -0.835                                       # Rolle Ø2.4 berührt den Reifen (r 1.3) tangential
    k = 1
    for axle in (dz - 4.5, dz + 4.2):                  # Sportwagen: Vorderachse -4.5, Hinterachse +4.2
        for off in (-s_ax, s_ax):
            lib.cylinder(m, "Rolle%d" % k, (dx, ry, axle + off), 11, 2.4, "X", STEEL, "Metal")
            k += 1
    fz = -234
    lib.box(m, "Luefterfuss", dx - 2.5, dx + 2.5, 0, 0.5, fz - 1.5, fz + 1.5, SLATE, "Metal")
    lib.cylinder(m, "Luefter", (dx, 3.7, fz), 1.2, 6.4, "Z", SLATE, "Metal")
    # Lüfterrad liegt an der Gehäusefront (Z fz + 0.6) an, die Nabe am Rad
    blade_cf = CF.at(dx, 3.7, fz + 0.7, -90)
    lib.part(m, "Walzenluefter_Blatt", (0.2, 5.4, 0.9), blade_cf, (70, 76, 82), "Metal", deco=True)
    lib.part(m, "Walzenluefter_Blatt", (0.1, 5.4, 0.9), blade_cf * CF.angles(math.pi / 2, 0, 0),
             (70, 76, 82), "Metal", deco=True)
    lib.cylinder(m, "Luefternabe", (dx, 3.7, fz + 0.95), 0.3, 1.2, "Z", TEAL, "Neon", deco=True)
    car = lib.clone_car(m, "sport", CF.at(dx, 0, dz, 0), (255, 125, 30), name="Car",
                        attrs={"Display": "Pruefstand"})
    lib.part(m, "Auspuffflamme", (0.8, 0.8, 0.8), CF(dx + 1.8, 1.2, dz + 7.9), (255, 140, 40), "Neon",
             transparency=1, shape="Ball", deco=True)
    # LEISTUNG-Bildschirm an der Ostwand (Z -234..-206, Y 10..22)
    lib.box(m, "Bildschirmrahmen", IX1 - 0.4, IX1, 10, 22, -234, -206, BLACK, "Metal")
    scr = lib.part(m, "Screen", (27.2, 11.2, 0.1), CF.at(IX1 - 0.45, 16, -220, -90), SCREEN_BG, "SmoothPlastic",
                   deco=True)
    _curve_screen(lib, scr)
    return car


# ---------------------------------------------------------------- Z4 "DEIN AUTO · BALD" (Showroom-Ecke)
def build_showroom(dm, lib):
    m = lib.model(dm, "Showroom")
    x0, x1, z0, z1 = 250, 285, -239.5, -205
    for a0, a1, b0, b1 in ((x0, x1, z0, z0 + 0.5), (x0, x1, z1 - 0.5, z1), (x0, x0 + 0.5, z0 + 0.5, z1 - 0.5),
                           (x1 - 0.5, x1, z0 + 0.5, z1 - 0.5)):
        lib.box(m, "Rahmenlinie", a0, a1, 0, 0.05, b0, b1, AMBER, "SmoothPlastic", deco=True)
    cx, cz = 266.5, -222.25
    lib.cylinder(m, "Drehteller_Neon", (cx, 0.06, cz), 0.12, 17, "Y", TEAL, "Neon")
    lib.cylinder(m, "Drehteller", (cx, 0.27, cz), 0.3, 16, "Y", SLATE, "Metal")
    for z in (cz - 4, cz + 4):
        lib.box(m, "Schildpfosten", 282.7, 283.3, 0, 8.5, z - 0.3, z + 0.3, STEEL, "Metal")
    lib.sign(m, "DEIN AUTO · BALD", (10, 3), CF.at(282.6, 7, cz, -90), AMBER, SLATE, name="Schild",
             sub="Bring dein Projekt ins Tuning-Zentrum", sub_color=WHITE)


# ---------------------------------------------------------------- Z5 Fahrgasse + Z6 Projektbuchten (Anim=lift)
BAY_CARS = {
    1: ("compact", (150, 220, 40), False, "PROJEKT 1 · COMPACT", "Fahrwerk · Felgen · 72 %"),
    2: ("gt_coupe", (36, 38, 42), True, "PROJEKT 2 · GT COUPÉ", "Mattfolie · Auspuff · 45 %"),
    3: ("hot_hatch", TEAL, False, "PROJEKT 3 · HOT HATCH", "Turbo-Kit · Abstimmung · 88 %"),
}


def build_bays(dm, anim, lib):
    m = lib.model(dm, "Projektbuchten")
    # Fahrgasse Z -258..-240: türkise Fahrbahnlinien, weiße Rennstreifen
    lib.box(m, "Fahrgasse_Linie", IX0 + 0.6, IX1, 0, 0.05, ROLL[0] - 0.2, ROLL[0] + 0.2, TEAL, "SmoothPlastic",
            deco=True)
    lib.box(m, "Fahrgasse_Linie", IX0 + 0.6, IX1, 0, 0.05, ROLL[1] - 0.2, ROLL[1] + 0.2, TEAL, "SmoothPlastic",
            deco=True)
    for z0 in (-251.4, -247.8):
        lib.box(m, "Rennstreifen", 222, 326, 0, 0.05, z0, z0 + 1.2, WHITE, "SmoothPlastic", deco=True)
    # Buchtlinien (amber), Werkzeugwagen, Reifenstapel
    for x in (224, 250, 276, 302, 328):
        lib.box(m, "Buchtlinie", x - 0.2, x + 0.2, 0, 0.05, -286.5, -259, AMBER, "SmoothPlastic", deco=True)
    for x in (250, 276):
        lib.box(m, "Werkzeugwagen", x - 2, x + 2, 0, 3.6, IZ0, IZ0 + 2, PETROL, "Metal")
        lib.box(m, "Werkzeugwagen_Platte", x - 2.1, x + 2.1, 3.6, 3.8, IZ0, IZ0 + 2.1, STEEL, "Metal")
    for k, (ox, oz) in enumerate(((0, 0), (0.12, -0.08), (-0.1, 0.1))):
        lib.cylinder(m, "Reifen", (325 + ox, 0.5 + k, -285 + oz), 1.0, 2.6, "Y", BLACK, "SmoothPlastic")
    # 4 Hebebühnen
    for i, c in enumerate(BAYS, start=1):
        lm = lib.model(anim, "Hebebuehne_%d" % i, attrs={"Anim": "lift", "Lift": 4, "Period": 60, "Bay": i})
        for sx in (-1, 1):
            lib.box(lm, "Saeule", c + sx * 5.8, c + sx * 7.0, 0, 12.8, BAY_Z - 0.8, BAY_Z + 0.8, TEAL, "Metal")
        lib.box(lm, "Quertraeger", c - 7.0, c + 7.0, 12.8, 13.6, BAY_Z - 0.8, BAY_Z + 0.8, STEEL, "Metal")
        pm = lib.model(lm, "Plattform")
        rl = None
        for sx in (-1, 1):
            r = lib.box(pm, "Fahrschiene", c + sx * 3.0, c + sx * 5.0, 0, 0.5, BAY_Z - 8, BAY_Z + 8, STEEL,
                        "DiamondPlate")
            rl = rl or r
            lib.box(pm, "Schlitten", c + sx * 5.0, c + sx * 5.8, 0, 1.2, BAY_Z - 0.6, BAY_Z + 0.6, AMBER, "Metal")
        lib.box(pm, "Traverse", c - 3.0, c + 3.0, 0, 0.4, BAY_Z - 8, BAY_Z - 7, STEEL, "Metal")
        lib.set_primary(pm, rl)
        if i in BAY_CARS:
            body, paint, is_matte, title, sub = BAY_CARS[i]
            car = lib.clone_car(pm, body, CF.at(c, 0.5, BAY_Z, 0), paint, name="Projektauto_%d" % i,
                                attrs={"Display": "Projektbucht"})
            if is_matte:
                matte(lib, car)
            col = SCREEN_TXT
        else:
            title, sub, col = "PROJEKT FREI", "Hebebühne verfügbar", AMBER
        lib.sign(lm, title, (9, 3.5), CF.at(c, 14, IZ0 + 0.1, 0), col, SCREEN_BG, name="Statusbildschirm",
                 sub=sub, sub_color=WHITE, bolts=False)


# ---------------------------------------------------------------- Vorplatz: Showcar-Rampe, Pylon, Leuchte
def build_forecourt(dm, anim, lib):
    m = lib.model(dm, "Vorplatz")
    # Rolltor-Zufahrt: Randlinien bis zur Rampe
    for z in ROLL:
        lib.box(m, "Zufahrtslinie", 178, 208, Y_G, -0.94, z - 0.2, z + 0.2, WHITE, "SmoothPlastic", deco=True)
    # Showcar-Rampe 10 x 2.53 x 18 (8°), hohes Ende im Westen, lila Supersportwagen mit der Nase nach oben
    ang = 8.0
    h = 18 * math.tan(math.radians(ang))
    rx, rz = 196, -276
    lib.wedge(m, "Showcar_Rampe", (10, h, 18), CF.at(rx, Y_G + h / 2, rz, -90), SLATE, "Metal")
    lib.box(m, "Rampe_Neon", rx + 9, rx + 9.2, Y_G, Y_G + 0.12, rz - 5, rz + 5, TEAL, "Neon", deco=True)
    y_root = Y_G + h / 2
    lib.clone_car(m, "super", CF.at(rx, y_root, rz, 90) * CF.angles(math.radians(ang), 0, 0), (120, 60, 200),
                  name="Showcar", attrs={"Display": "Vorplatz"})
    lib.sign(m, "SHOWCAR DER WOCHE", (8, 1.4), CF.at(rx - 9.1, Y_G + h / 2, rz, -90), TEAL, SLATE,
             name="Rampenschild", bolts=False)
    # Vorplatzleuchte (1 Licht) zwischen Rolltor und Rampe
    lib.street_lamp(m, 208, -268, Y_G, -1, 0, name="Vorplatzleuchte", range_=30, brightness=1.0)
    # TUNING-Pylon 4 x 44 x 4 bei (190,-166), senkrechte Schrift nach Westen und Süden
    px, pz = 190, -166
    lib.box(m, "Pylon", px - 2, px + 2, 0.5, 43, pz - 2, pz + 2, SLATE, "Metal")
    word = "\n".join("TUNING")
    lib.sign(m, word, (3.4, 32), CF.at(px - 2.05, 22, pz, -90), TEAL, SLATE, name="Pylonschrift_W", thickness=0.1,
             bolts=False)
    lib.sign(m, word, (3.4, 32), CF.at(px, 22, pz + 2.05, 0), TEAL, SLATE, name="Pylonschrift_S", thickness=0.1,
             bolts=False)
    lib.box(m, "Pylon_Neonkappe", px - 2.1, px + 2.1, 43, 43.6, pz - 2.1, pz + 2.1, TEAL, "Neon", deco=True)
    lib.box(m, "Pylon_Neonkante", px - 2.15, px - 1.85, 3, 40, pz + 1.85, pz + 2.15, TEAL, "Neon", deco=True)
    lib.box(m, "Pylon_Sockel", px - 2.6, px + 2.6, Y_G, 0.5, pz - 2.6, pz + 2.6, (70, 78, 86), "Concrete")
    # Farbe auf dem dunklen Vorplatz: türkise Leitstreifen zur Eingangstür, Leuchtpoller, 2 Bäume, 2 Fahnen
    for z0, z1 in ((DOOR[0] - 2.2, DOOR[0] - 1.6), (DOOR[1] + 1.6, DOOR[1] + 2.2)):
        lib.box(m, "Leitstreifen", 178, 212.6, Y_G, Y_G + 0.05, z0, z1, TEAL, "Neon", deco=True)
    for x in (183, 191, 199, 207):
        for z in (DOOR[0] - 3.4, DOOR[1] + 3.4):
            lib.cylinder(m, "Leuchtpoller", (x, Y_G + 0.6, z), 1.2, 0.6, "Y", SLATE, "Metal")
            lib.cylinder(m, "Pollerlicht", (x, Y_G + 1.35, z), 0.3, 0.64, "Y", TEAL, "Neon", deco=True)
    for z in (DOOR[0] - 7, DOOR[1] + 7):
        lib.box(m, "Pflanzkasten", 205, 209, Y_G, -0.4, z - 2, z + 2, SLATE, "Metal")
        lib.tree_lite(m, 207, -0.4, z, scale=1.2, seed=5 if z < -200 else 9, name="Vorplatzbaum")
    from .dealer_track import flag_pole
    for i, z in enumerate((-226, -182)):
        flag_pole(lib, anim, "Tuningfahne_%d" % (i + 1), 181, Y_G, z, TEAL if i == 0 else (22, 26, 31),
                  (22, 26, 31) if i == 0 else TEAL, text="TUNING")


# ---------------------------------------------------------------- Tuning-Treff
def build_treff(dm, anim, lib):
    m = lib.model(dm, "TuningTreff")
    # Belag bündig in der Aussparung des Tuning-Geländes (ground_roads.GROUND_INSETS)
    y_pad = Y_G
    lib.box(m, "Treffbelag", 350, 450, Y_G - 0.3, y_pad, -300, -190, TREFF_PAD, "Asphalt")
    # Fußweg von der Tuninggasse (X 320..326, Z -159) zum Treff-Bogen, Oberseite -0.5
    walk = (128, 134, 138)
    lib.box(m, "Treffweg", 320, 326, Y_G, -0.5, -168, -159, walk, "Concrete")
    lib.box(m, "Treffweg", 326, 403, Y_G, -0.5, -168, -162, walk, "Concrete")
    lib.box(m, "Treffweg", 397, 403, Y_G, -0.5, -190, -168, walk, "Concrete")
    # 6 Buchten mit Neonkanten (türkis/magenta), Rückwandlinie
    yl = (y_pad, y_pad + 0.05)
    for k, x in enumerate(range(358, 443, 14)):
        col = TEAL if k % 2 == 0 else MAGENTA
        lib.box(m, "Buchtkante", x - 0.2, x + 0.2, yl[0], yl[1], -297.6, -276, col, "Neon", deco=True)
    lib.box(m, "Buchtkante", 357.8, 442.2, yl[0], yl[1], -298, -297.6, TEAL, "Neon", deco=True)
    # Kombi schwarz auf Unterboden-Leuchtplatte (Treff-Licht)
    cx, cz = 379, -287
    glow = lib.box(m, "Unterbodenlicht", cx - 3, cx + 3, y_pad, y_pad + 0.05, cz - 6, cz + 6, TEAL, "Neon", deco=True)
    lib.point_light(glow, 18, 1.6, (90, 230, 220), name="TreffLicht")
    lib.clone_car(m, "wagon", CF.at(cx, y_pad, cz, 0), (20, 22, 26), name="Treffauto", attrs={"Display": "Treff"})
    # 3 Bänke mit Blick auf die Buchten
    for x in (372, 400, 428):
        lib.box(m, "Bankfuss", x - 2.5, x + 2.5, y_pad, 0.4, -241, -239.8, SLATE, "Metal")
        lib.box(m, "Banksitz", x - 3, x + 3, 0.4, 0.8, -241.8, -239.2, (130, 90, 60), "Wood")
    # Infotafel
    for z in (-254, -246):
        lib.box(m, "Tafelpfosten", 445.7, 446.3, y_pad, 7.5, z - 0.3, z + 0.3, STEEL, "Metal")
    lib.sign(m, "TUNING-TREFF · JEDEN ABEND", (9, 3.2), CF.at(445.6, 5.6, -250, -90), TEAL, SLATE, name="Infotafel",
             sub="Zeig dein Projekt – Parken nur mit Stil", sub_color=WHITE, bolts=False)
    # Neon-Bogen "TUNING-TREFF" bei (400,-192), Anim=neon (Farbwechsel türkis -> magenta)
    am = lib.model(anim, "Treff-Bogen", attrs={"Anim": "neon", "Period": 3.2, "ColorB": Color3(*MAGENTA)})
    ax, az = 400, -192
    for sx in (-1, 1):
        x = ax + sx * 13.5
        lib.box(am, "Bogenpfosten", x - 0.75, x + 0.75, y_pad, 15, az - 0.75, az + 0.75, SLATE, "Metal")
        lib.box(am, "Neonroehre", x - 0.15, x + 0.15, 0.5, 13.5, az + 0.75, az + 1.05, TEAL, "Neon", deco=True)
    lib.box(am, "Bogentraeger", ax - 14.25, ax + 14.25, 15, 18, az - 0.75, az + 0.75, SLATE, "Metal")
    lib.box(am, "Neonroehre", ax - 12.5, ax + 12.5, 14.7, 15.0, az + 0.75, az + 1.05, MAGENTA, "Neon", deco=True)
    lib.sign(am, "TUNING-TREFF", (24, 2.6), CF.at(ax, 16.5, az + 0.85, 0), TEAL, SLATE, name="Bogenschild",
             bolts=False)


# ---------------------------------------------------------------- Dragstrip (R10, Deko)
def build_dragstrip(dm, anim, lib):
    m = lib.model(dm, "Dragstrip")
    ym = (-0.95, -0.90)
    lib.box(m, "Startlinie", 199.7, 200.3, ym[0], ym[1], -349.5, -326.5, WHITE, "SmoothPlastic", deco=True)
    lib.box(m, "Spurtrenner", 200.3, 439.9, ym[0], ym[1], -338.15, -337.85, WHITE, "SmoothPlastic", deco=True)
    # Ziel: 6 weiße Felder im 4er-Schachbrett (2 Spalten x 6 Reihen, der Asphalt bildet die schwarzen)
    for r in range(6):
        x0 = 440 if r % 2 == 0 else 444
        z0 = -350 + r * 4
        lib.box(m, "Zielfeld", x0, x0 + 4, ym[0], ym[1], z0, z0 + 4, WHITE, "SmoothPlastic", deco=True)
    # Schild "VIERTELMEILE · BALD"
    for x in (221, 239):
        lib.box(m, "Schildpfosten", x - 0.3, x + 0.3, Y_G, 7.5, -357.5, -356.9, STEEL, "Metal")
    lib.sign(m, "VIERTELMEILE · BALD", (20, 3.4), CF.at(230, 5.6, -356.8, 0), AMBER, SLATE, name="Dragstripschild",
             sub="Beschleunigungsrennen – eröffnet bald", sub_color=WHITE)
    # Startampel ("Christbaum") bei (196,-352), Anim=startlight
    sm = lib.model(anim, "Startampel", attrs={"Anim": "startlight", "Period": 5})
    tx, tz = 196, -352
    lib.cylinder(sm, "Mast", (tx, Y_G + 4.5, tz), 9, 0.5, "Y", STEEL, "Metal")
    lib.box(sm, "Gehaeuse", tx - 0.7, tx + 0.7, 5, 10.4, tz - 0.6, tz + 0.6, BLACK, "Metal")
    for k, (y, col) in enumerate(((9.5, AMBER), (8.3, AMBER), (7.1, AMBER), (5.9, (60, 230, 90))), start=1):
        lib.ball(sm, "Lampe%d" % k, (tx, y, tz + 0.75), 0.9, col, "Neon", deco=True, transparency=0.8)
