"""Kiesplatz (Story Kapitel 1, PHASE4_CONTRACT §7): Gebrauchtwagen-Stand am südöstlichen Stadtrand hinter der
Tankstelle (X 282..398, Z 282..346), Zufahrt über das Tankstellen-Gelände (Ausfahrt-Absenkung X 165..178, Z 206..216,
dann über die Fläche nach Süden) und eine Kiesauffahrt X 318..336, Z 260..282 zwischen den Bäumen der Baumreihe.

Aufbau (alle Oberseiten auf dem Höhen-Stapel CITY_SPEC §1.2: Kies -1.0, Stellflächen -0.9, Hüttenboden 0):
  City.Districts.Kiesplatz
    Kies, Zufahrt            Bodenplatten (Pebble, -1.3..-1.0)
    Zaun                     Holzzaun mit Pfosten + 2 Riegeln, Lücke an der Einfahrt (X 316..338)
    Huette                   Verkaufshütte 14 x 12 (Boden 0), Fenster nach Osten (Station kiesplatz am Fenster),
                             Dachschild "KIESPLATZ · GEBRAUCHTWAGEN" (nach Norden, zur Einfahrt), Lampe
    Spots.Spot_1..3          Part (Stellfläche 10 x 0.1 x 18, Oberseite -0.9, Attribut Spot=n) + Lite-Auto darauf
    Preistafel               Tafel mit SurfaceGui "PriceBoard" und TextLabels Line1..3 (Server/Client schreiben)
    Leitlinie                Farbleitlinie (Sand-Ocker, Neon) von der Tankstellen-Ausfahrt zur Hütte
    Deko                     Pylonen, Reifenstapel, Bank, Hoflaternen (2 Lichter)
  City.Animated.Kiesplatz
    Kunde_1..3               NPC-Kunde (Kopf/Torso/Arme/Beine aus Parts, PrimaryPart Torso), Anim="npc_idle", Spot=n
    Fahne_1..3               Fahnenmasten (Anim=flag)
  City.Missions.Delivery_1..3  Lieferrouten (Nebenmissionen): Model mit Parts Start und Ziel (unsichtbar,
                             CanCollide false, CanTouch true) auf der Fahrbahn; Attribute Route=n, Role=start|end
Station "kiesplatz" (MiniTab story) und Ankunft "kiesplatz" baut contract.py.
"""
import math

from ..lib import (CF, AMBER, APRON, BLACK, GLASS, GRAPHITE, LAMP, SLATE, STEEL, TEAL, WHITE, set_attrs)
from ..tycoon import flag_pole

NAME = "Kiesplatz"
BUDGET = (900, 8)                 # Parts, Lichter (Vorgabe des Weltteams)

# Lage
LOT = (282.0, 398.0, 282.0, 346.0)          # x0, x1, z0, z1 (Kiesfläche)
DRIVE = (318.0, 336.0, 260.0, 282.0)        # Kiesauffahrt vom Tankstellen-Gelände (Z 260) zum Platz
Y_GRAVEL = -1.0
Y_PAD = -0.9
HUT = (286.0, 300.0, 300.0, 312.0)          # Verkaufshütte
HUT_H = 6.5
SPOT_SIZE = (10.0, 0.1, 18.0)
SPOTS = [(318.0, 322.0), (342.0, 322.0), (366.0, 322.0)]       # Mitte der Stellflächen (Auto schaut nach Norden)
SPOT_CARS = [("compact", (214, 160, 72)), ("sedan", (60, 110, 170)), ("wagon", (180, 60, 50))]
NPC_COLORS = [((230, 190, 150), (200, 60, 60), (50, 60, 110)), ((200, 160, 120), (60, 150, 90), (40, 40, 48)),
              ((240, 205, 170), (240, 190, 60), (90, 70, 50))]       # Haut, Oberteil, Hose
PRICE_BOARD = (300.5, 324.0)                 # Tafel östlich der Hütte, Text nach Osten
FLAGS = [(300.0, 284.5), (356.0, 284.5), (396.0, 310.0)]
LINE_COLOR = (214, 160, 72)                  # Sand-Ocker (Farbleitsystem: Kiesplatz)
LINE_Z = 223.0                               # Leitlinie quer über das Tankstellen-Gelände (südlich der Ladebucht)
GRAVEL = (110, 104, 96)
WOOD = (130, 90, 60)
WOOD_D = (100, 68, 44)
CREAM = (224, 214, 190)

# Lieferrouten (auf der Fahrbahn, Oberseite -0.95): n -> (Start (x, z, Breite x, Tiefe z), Ziel (...))
# Abstände Luftlinie: 1: 520 (Meile Ost -> Meile West), 2: ~535 (Marktstraße West Nord -> Südring Ost),
# 3: ~487 (Nordring -> Marktstraße Ost Süd)
ROUTES = {
    1: ((260.0, -6.5, 12.0, 20.0), (-260.0, 6.5, 12.0, 20.0)),
    2: ((-152.0, -280.0, 20.0, 12.0), (80.0, 200.0, 12.0, 20.0)),
    3: ((0.0, -342.0, 12.0, 20.0), (152.0, 120.0, 20.0, 12.0)),
}
ROUTE_H = 4.0
Y_ROAD = -0.95


def build(city, lib, tree):
    districts = lib.folder(city, "Districts")
    anim_root = lib.folder(city, "Animated")
    missions = lib.folder(city, "Missions")
    with lib.section("D14 Kiesplatz"):
        dm = lib.model(districts, NAME, attrs={"District": "D14"})
        an = lib.model(anim_root, NAME)
        build_ground(dm, lib)
        build_fence(dm, lib)
        build_hut(dm, lib)
        build_spots(dm, an, lib)
        build_price_board(dm, lib)
        build_guide_line(dm, lib)
        build_flags(an, lib)
        build_deco(dm, lib)
    with lib.section("Lieferrouten (unsichtbar)"):
        build_routes(missions, lib)
    return dm


# ---------------------------------------------------------------- Boden
def build_ground(dm, lib):
    x0, x1, z0, z1 = LOT
    lib.box(dm, "Kies", x0, x1, Y_GRAVEL - 0.3, Y_GRAVEL, z0, z1, GRAVEL, "Pebble")
    dx0, dx1, dz0, dz1 = DRIVE
    lib.box(dm, "Zufahrt", dx0, dx1, Y_GRAVEL - 0.3, Y_GRAVEL, dz0, z0, GRAVEL, "Pebble")
    # Randsteine der Zufahrt (auf dem Gras, 0.1 über der Grasplatte -1.10)
    for xx in (dx0 - 0.6, dx1):
        lib.box(dm, "Randstein", xx, xx + 0.6, -1.1, -0.8, dz0, z0, APRON, "Concrete")


# ---------------------------------------------------------------- Zaun
def build_fence(dm, lib):
    m = lib.model(dm, "Zaun")
    x0, x1, z0, z1 = LOT
    gap = (DRIVE[0] - 2.0, DRIVE[1] + 2.0)
    top = Y_GRAVEL + 3.6
    # (Name, (xa, za), (xb, zb)) - Segmente entlang der Kante
    segs = [("Nord_W", (x0, z0 + 0.4), (gap[0], z0 + 0.4)), ("Nord_O", (gap[1], z0 + 0.4), (x1, z0 + 0.4)),
            ("Sued", (x0, z1 - 0.4), (x1, z1 - 0.4)), ("West", (x0 + 0.4, z0 + 0.4), (x0 + 0.4, z1 - 0.4)),
            ("Ost", (x1 - 0.4, z0 + 0.4), (x1 - 0.4, z1 - 0.4))]
    for nm, (xa, za), (xb, zb) in segs:
        along_x = abs(xb - xa) > abs(zb - za)
        length = abs(xb - xa) if along_x else abs(zb - za)
        n = max(2, int(round(length / 8.0)) + 1)
        for k in range(n):
            if not along_x and k in (0, n - 1):
                continue            # Eckpfosten setzen die Nord-/Südseiten
            f = k / (n - 1)
            px = xa + (xb - xa) * f
            pz = za + (zb - za) * f
            lib.box(m, "Pfosten_" + nm, px - 0.3, px + 0.3, Y_GRAVEL, top + 0.3, pz - 0.3, pz + 0.3, WOOD_D, "Wood")
        for ry in (1.2, 2.6):
            if along_x:
                lib.box(m, "Riegel_" + nm, min(xa, xb), max(xa, xb), Y_GRAVEL + ry, Y_GRAVEL + ry + 0.5,
                        za - 0.12, za + 0.12, WOOD, "WoodPlanks", deco=True)
            else:
                # Längsriegel enden vor den Querriegeln der Ecken (keine Überschneidung)
                lib.box(m, "Riegel_" + nm, xa - 0.12, xa + 0.12, Y_GRAVEL + ry, Y_GRAVEL + ry + 0.5,
                        min(za, zb) + 0.15, max(za, zb) - 0.15, WOOD, "WoodPlanks", deco=True)
    # Torbogen über der Einfahrt mit Willkommensschild
    for gx in gap:
        lib.box(m, "Torpfosten", gx - 0.5, gx + 0.5, Y_GRAVEL, Y_GRAVEL + 9.0, z0 - 0.6, z0 + 0.4, WOOD_D, "Wood")
    lib.box(m, "Torbalken", gap[0] - 0.5, gap[1] + 0.5, Y_GRAVEL + 9.0, Y_GRAVEL + 9.8, z0 - 0.6, z0 + 0.4, WOOD_D,
            "Wood")
    lib.sign(m, "WILLKOMMEN", (gap[1] - gap[0] - 2, 2.2), CF.at((gap[0] + gap[1]) / 2, Y_GRAVEL + 9.0 - 1.1, z0 - 0.7, 180),
             CREAM, WOOD_D, name="Torschild", sub="Gebrauchtwagen · faire Preise", sub_color=AMBER)
    return m


# ---------------------------------------------------------------- Hütte
def build_hut(dm, lib):
    m = lib.model(dm, "Huette")
    x0, x1, z0, z1 = HUT
    t = 0.5
    h = HUT_H
    lib.box(m, "Boden", x0, x1, Y_GRAVEL, 0.0, z0, z1, APRON, "Concrete")
    lib.box(m, "Wand_W", x0, x0 + t, 0.0, h, z0, z1, WOOD, "WoodPlanks")
    lib.box(m, "Wand_N", x0 + t, x1 - t, 0.0, h, z0, z0 + t, WOOD, "WoodPlanks")
    lib.box(m, "Wand_S", x0 + t, x1 - t, 0.0, h, z1 - t, z1, WOOD, "WoodPlanks")
    # Ostwand mit Verkaufsfenster (Theke) - die Station steht am Fenster, Spieler östlich davor
    wz0, wz1 = 302.5, 309.5
    lib.box(m, "Wand_O_N", x1 - t, x1, 0.0, h, z0, wz0, WOOD, "WoodPlanks")
    lib.box(m, "Wand_O_S", x1 - t, x1, 0.0, h, wz1, z1, WOOD, "WoodPlanks")
    lib.box(m, "Wand_O_Sockel", x1 - t, x1, 0.0, 2.6, wz0, wz1, WOOD, "WoodPlanks")
    lib.box(m, "Wand_O_Sturz", x1 - t, x1, 5.0, h, wz0, wz1, WOOD, "WoodPlanks")
    lib.box(m, "Theke", x1 - 0.3, x1 + 1.0, 2.6, 2.9, wz0 - 0.4, wz1 + 0.4, WOOD_D, "Wood")
    lib.box(m, "Fenster", x1 - 0.1, x1 + 0.1, 2.9, 5.0, wz0, wz1, GLASS, "Glass", transparency=0.55, deco=True)
    # Tür in der Südwand (nur Optik)
    lib.box(m, "Tuer", x0 + 4.0, x0 + 7.0, 0.0, 4.6, z1, z1 + 0.15, WOOD_D, "Wood", deco=True)
    # Dach mit Überstand und Firstschild
    lib.box(m, "Dach", x0 - 1.0, x1 + 1.5, h, h + 0.6, z0 - 1.0, z1 + 1.0, GRAPHITE, "Concrete")
    lib.box(m, "Schildtraeger", x0 + 1.0, x1 - 1.0, h + 0.6, h + 1.4, z0 + 0.2, z0 + 1.2, WOOD_D, "Wood")
    lib.sign(m, "KIESPLATZ · GEBRAUCHTWAGEN", (x1 - x0, 2.6), CF.at((x0 + x1) / 2, h + 2.7, z0 + 0.6, 180), AMBER,
             SLATE, name="Dachschild", sub="Hier beginnt deine Händler-Karriere", sub_color=WHITE)
    # Lampe über dem Fenster
    head = lib.box(m, "Lampe", x1 + 0.2, x1 + 1.4, h - 0.3, h, 304.5, 307.5, LAMP, "SmoothPlastic", deco=True)
    set_attrs(head, {"NightNeon": True})
    lib.point_light(head, 20, 0.8, LAMP)
    # Innen: Schreibtisch mit Kasse
    lib.box(m, "Schreibtisch", x1 - 4.5, x1 - 0.5, 2.2, 2.5, 303.0, 309.0, WOOD_D, "Wood")
    lib.box(m, "Kasse", x1 - 2.4, x1 - 1.2, 2.5, 3.3, 305.3, 306.7, GRAPHITE, "Metal", deco=True)
    return m


# ---------------------------------------------------------------- Stellflächen, Autos, Kunden
def build_spots(dm, an, lib):
    spots = lib.model(dm, "Spots")
    for n, ((sx, sz), (body, paint)) in enumerate(zip(SPOTS, SPOT_CARS), start=1):
        w, hh, d = SPOT_SIZE
        pad = lib.box(spots, "Spot_%d" % n, sx - w / 2, sx + w / 2, Y_PAD - hh, Y_PAD, sz - d / 2, sz + d / 2,
                      (126, 122, 114), "Concrete", attrs={"Spot": n})
        gui = lib.surface_text(pad, str(n), face="Top", text_color=WHITE, font="GothamBlack", name="Nummer",
                               size=(0.3, 0.14), pos=(0.35, 0.02), px_per_stud=12)
        del gui
        lib.lite_car(spots, body, CF.at(sx, Y_PAD, sz, 0), paint, name="Angebot_%d" % n,
                     attrs={"Spot": n, "Display": "Kiesplatz"})
        # Kunde steht vor dem Auto (Süden) und schaut nach Norden
        npc(lib, an, "Kunde_%d" % n, sx + 3.0, Y_GRAVEL, sz + 12.5, 0, NPC_COLORS[n - 1], n)
    return spots


def npc(lib, parent, name, x, fy, z, yaw, colors, spot):
    """Blockiger NPC (6 Parts): Beine 2x4x2, Torso 4x4x2, Arme 2x4x2, Kopf (Kugel 2.4). Füße auf fy, Blick yaw.
    PrimaryPart Torso; der Client animiert Anim='npc_idle' (leichtes Wippen/Drehen)."""
    skin, shirt, pants = colors
    m = lib.model(parent, name, attrs={"Anim": "npc_idle", "Spot": spot, "Period": 2.4 + spot * 0.3})
    base = CF.at(x, fy, z, yaw)
    for k, sx in enumerate((-1.0, 1.0)):
        lib.part(m, "Bein_%s" % ("L" if k == 0 else "R"), (2, 4, 2), base * CF(sx, 2.0, 0), pants, "SmoothPlastic",
                 collide=False)
    torso = lib.part(m, "Torso", (4, 4, 2), base * CF(0, 6.0, 0), shirt, "SmoothPlastic", collide=False)
    lib.set_primary(m, torso)
    for k, sx in enumerate((-3.0, 3.0)):
        lib.part(m, "Arm_%s" % ("L" if k == 0 else "R"), (2, 4, 2), base * CF(sx, 6.0, 0), skin, "SmoothPlastic",
                 deco=True)
    head = lib.part(m, "Head", (2.4, 2.4, 2.4), base * CF(0, 9.2, 0), skin, "SmoothPlastic", shape="Ball",
                    deco=True)
    # Gesicht: Augen auf der Blickseite (-Z lokal, wie die Autos)
    for sx in (-0.5, 0.5):
        lib.part(m, "Auge", (0.4, 0.4, 0.2), base * CF(sx, 9.5, -1.15), BLACK, "SmoothPlastic", deco=True)
    del head
    return m


# ---------------------------------------------------------------- Preistafel, Leitlinie, Fahnen, Deko
def build_price_board(dm, lib):
    m = lib.model(dm, "Preistafel")
    x, z = PRICE_BOARD
    for dz in (-3.0, 3.0):
        lib.box(m, "Tafelpfosten", x - 0.3, x + 0.3, Y_GRAVEL, Y_GRAVEL + 6.6, z + dz - 0.3, z + dz + 0.3, STEEL,
                "Metal")
    plate = lib.part(m, "Tafel", (8.0, 4.0, 0.3), CF.at(x + 0.3, Y_GRAVEL + 4.4, z, 90), SLATE, "SmoothPlastic",
                     collide=False)
    gui = lib.surface_text(plate, None, face="Back", name="PriceBoard", canvas=(320, 160))
    lib.text_label(gui, "ANGEBOTE", AMBER, "GothamBlack", "Title", None, (0.9, 0.2), (0.05, 0.03))
    for k in range(3):
        lib.text_label(gui, "%d · – Credits" % (k + 1), WHITE, "GothamBold", "Line%d" % (k + 1), None, (0.9, 0.22),
                       (0.05, 0.26 + k * 0.24))
    return m


def build_guide_line(dm, lib):
    """Farbleitlinie (CITY_SPEC §5): von der Tankstellen-Ausfahrt (X 178, Z 211) auf dem Tankstellen-Gelände
    (-1.0) nach Süden auf Z 223, dann nach Osten bis X 327, dann nach Süden über die Zufahrt und den Kies bis vor die
    Hütte; Endscheibe vor dem Verkaufsfenster. Oberseiten -0.95 (Linie 0.05 dick auf dem Boden)."""
    m = lib.model(dm, "Leitlinie")
    y0, y1 = Y_GRAVEL, Y_GRAVEL + 0.05
    lx = 327.0
    lib.box(m, "Leitlinie", 178.0, 179.0, y0, y1, 211.0, LINE_Z + 0.5, LINE_COLOR, "Neon", deco=True)
    lib.box(m, "Leitlinie", 179.0, lx + 0.5, y0, y1, LINE_Z - 0.5, LINE_Z + 0.5, LINE_COLOR, "Neon", deco=True)
    lib.box(m, "Leitlinie", lx - 0.5, lx + 0.5, y0, y1, LINE_Z + 0.5, 296.0, LINE_COLOR, "Neon", deco=True)
    lib.box(m, "Leitlinie", 308.0, lx + 0.5, y0, y1, 296.0, 297.0, LINE_COLOR, "Neon", deco=True)
    lib.box(m, "Leitlinie", 308.0, 309.0, y0, y1, 297.0, 304.0, LINE_COLOR, "Neon", deco=True)
    lib.cylinder(m, "Zielscheibe", (308.5, y0 + 0.05, 305.5), 0.1, 3.0, "Y", LINE_COLOR, "Neon", deco=True)
    return m


def build_flags(an, lib):
    texts = ("KIES", "PLATZ", "DEALS")
    for n, (x, z) in enumerate(FLAGS, start=1):
        flag_pole(lib, an, "Fahne_%d" % n, x, Y_GRAVEL, z, (AMBER, TEAL, (200, 60, 60))[n - 1], WHITE, texts[n - 1],
                  h=13.0)


def build_deco(dm, lib):
    m = lib.model(dm, "Deko")
    for x, z in ((308.0, 288.0), (346.0, 288.0), (384.0, 340.0)):
        lib.cone(m, x, Y_GRAVEL, z)
    # Reifenstapel an der Südwest-Ecke
    for k in range(4):
        lib.cylinder(m, "Reifen", (288.0, Y_GRAVEL + 0.45 + k * 0.9, 340.0), 0.9, 2.6, "Y", BLACK, "Plastic",
                     deco=(k > 0))
    for k in range(3):
        lib.cylinder(m, "Reifen", (291.0, Y_GRAVEL + 0.45 + k * 0.9, 340.5), 0.9, 2.6, "Y", BLACK, "Plastic",
                     deco=(k > 0))
    # Bank vor der Hütte (Südseite)
    lib.box(m, "Banksitz", 288.0, 294.0, Y_GRAVEL + 1.3, Y_GRAVEL + 1.6, 315.0, 316.6, WOOD, "WoodPlanks")
    for bx in (288.4, 293.0):
        lib.box(m, "Bankbein", bx, bx + 0.6, Y_GRAVEL, Y_GRAVEL + 1.3, 315.2, 316.4, GRAPHITE, "Metal")
    # Hoflaternen (2 Lichter), Ausleger zum Platz
    lib.street_lamp(m, 310.0, 344.0, Y_GRAVEL, 0, -1, name="Hoflaterne", range_=30, brightness=0.9)
    lib.street_lamp(m, 380.0, 286.0, Y_GRAVEL, 0, 1, name="Hoflaterne", range_=30, brightness=0.9)
    # Werbetafel am Ostzaun
    lib.sign(m, "GEBRAUCHT · GEPRÜFT · GÜNSTIG", (14, 2.0), CF.at(396.0, Y_GRAVEL + 4.5, 326.0, -90), SLATE, AMBER,
             name="Werbetafel")
    for dz in (-6.5, 6.5):
        lib.box(m, "Tafelpfosten", 395.6, 396.2, Y_GRAVEL, Y_GRAVEL + 5.6, 326.0 + dz - 0.3, 326.0 + dz + 0.3,
                STEEL, "Metal")
    return m


# ---------------------------------------------------------------- Lieferrouten
def build_routes(missions, lib):
    for n, ((sx, sz, sw, sd), (ex, ez, ew, ed)) in sorted(ROUTES.items()):
        m = lib.model(missions, "Delivery_%d" % n, attrs={"Route": n, "Kind": "delivery",
                                                          "Distance": round(math.hypot(ex - sx, ez - sz))})
        for nm, role, (x, z, w, d) in (("Start", "start", (sx, sz, sw, sd)), ("Ziel", "end", (ex, ez, ew, ed))):
            lib.part(m, nm, (w, ROUTE_H, d), CF(x, Y_ROAD + ROUTE_H / 2, z), TEAL, "SmoothPlastic", transparency=1,
                     collide=False, touch=True, query=False, cast_shadow=False,
                     attrs={"Route": n, "Role": role})
    return missions
