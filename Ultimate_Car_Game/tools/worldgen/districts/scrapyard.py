"""Schrottplatz/Recyclinghof (D10): Zaun, Tor, Kontor, Presse-Halle mit Sheddach und Schornstein, Aufgabebunker,
Magnetkran, Zerlegeplatz (docs/CITY_SPEC.md §6 D10).

Gebaut wird unter City.Districts.Schrottplatz (statische Kulisse, 5 Lichter) und City.Animated.Schrottplatz
(Presse Anim=press mit Ram/Plate/Car, Magnetkran Anim=crane mit Boom/Trolley/Magnet, Rundumleuchten Anim=beacon).
Stationen press / scrap_trader / scrapyard und die Ankunftspunkte baut contract.py; hier steht nur die Kulisse
um die Anker (Steuerpult, Ankaufschalter, Zerlegeplatz).

Höhen-Stapel im Hof (nie zwei überlappende Oberseiten auf gleicher Höhe):
  Erde -1.00 | Haufen-Schotter -0.92 | Einfahrt -0.98 | Randlinien -0.96 | Waagenrahmen -0.94 | Waage -0.86
  | Fußweg -0.50 | Bunkerboden -0.50 (getrennt) | Hallenboden / Zerlegeplatz 0 | Bodenlinien +0.02

Wracks: "Lite"-Wracks werden aus ServerStorage.CarTemplates abgeleitet (nur die tragenden Teile: Chassis,
Karosserie-Paint, Hood, einzelne Reifen/Säulen; 9-16 Parts statt 135), rostig umgefärbt, gekippt und gestapelt.
Sie zählen ehrlich zum District-Budget. Der einzige volle Vorlagen-Klon ist der Kombi auf dem Zerlegeplatz.
"""
import math
import random

from ..lib import (CF, AMBER, APRON, BLACK, GRAPHITE, LAMP, SLATE, STEEL, TRUSS, WHITE, Vec3, _color3_el, _sub_el,
                   aabb, child, get_prop, is_basepart, name_of, props, read_cf, read_size, set_attrs, write_cf,
                   yaw_towards)

NAME = "Schrottplatz"

# ---------------------------------------------------------------- Farben (CITY_SPEC §1.4 Schrottplatz)
RUST = (140, 70, 40)
RUST_DARK = (104, 52, 34)
YELLOW = (240, 190, 40)
CORR = (104, 110, 114)
DIRT = (92, 84, 72)
GRAVEL = (74, 68, 60)
CONCRETE = APRON
CONCRETE_DARK = (96, 100, 102)
RUBBER = (30, 31, 34)
KONTOR_RED = (150, 66, 42)
HALL_LIGHT = (224, 238, 255)
NEON_WHITE = (232, 246, 249)
RED_NEON = (255, 45, 45)
WRECK_COLORS = [((140, 70, 40), "CorrodedMetal"), ((116, 58, 36), "CorrodedMetal"), ((96, 104, 112), "CorrodedMetal"),
                ((150, 118, 80), "CorrodedMetal"), ((78, 96, 84), "CorrodedMetal"), ((132, 52, 44), "CorrodedMetal"),
                ((70, 84, 110), "Metal"), ((160, 150, 130), "Metal")]
CUBE_COLORS = [(120, 60, 40), (90, 96, 104), (150, 120, 60), (70, 90, 110), (130, 50, 45), (104, 110, 114),
               (96, 82, 64)]

Y_DIRT = -1.0
Y_PAD = -0.92
Y_ROAD = -0.98

# ---------------------------------------------------------------- Lage (§6 D10)
YARD = (-468, -178, -364, -159)
HALL = (-380, -310, -250, -180)     # X0, X1, Z0, Z1
HALL_H = 34
MAST = (-420, -262)
BUNKER = (-392, -211)
PILES_CRANE = [(-445, -315), (-390, -305), (-452, -215)]
PILES_STATIC = [(-260, -320), (-320, -335)]
PRESS = (-352, -211)


class Support:
    """Einfache Höhenkarte aus AABBs, damit Wracks, Presslinge und Reifen aufeinander liegen statt zu schweben
    oder sich zu durchdringen."""

    def __init__(self, base):
        self.base = base
        self.boxes = []

    def add(self, item):
        b = aabb(item)
        self.boxes.append((b[0], b[1], b[4], b[5], b[3]))

    def height(self, x, z):
        h = self.base
        for x0, x1, z0, z1, top in self.boxes:
            if x0 <= x <= x1 and z0 <= z <= z1 and top > h:
                h = top
        return h


# ---------------------------------------------------------------- Lite-Wracks aus den Vorlagen
def _shape(it):
    e = get_prop(it, "shape")
    if e is None:
        return "Block"
    return {0: "Ball", 1: "Block", 2: "Cylinder"}.get(int(float(e.text)), "Block")


def wreck_spec(lib, body, flat=False, tires=(), hood=0.0, bumper=False):
    """Teileliste (Name, Klasse, Form, Größe, lokaler CF, Farbrolle) eines Lite-Wracks aus der Vorlage <body>.
    flat: Dach eingedrückt (liegt auf den Türen), keine Säulen. tires: Reifen-Kürzel ('FL','FR','RL','RR').
    hood: Haube um das 2.4.0-Scharnier (0,3.9,-3.55) geöffnet (Grad)."""
    tpl = lib.templates()[body]
    parts = []
    for it in tpl.iter("Item"):
        if not is_basepart(it):
            continue
        nm = name_of(it)
        size = read_size(it)
        cf = read_cf(it)
        role = None
        if nm == "Chassis":
            role = "chassis"
        elif nm == "Paint":
            vol = size[0] * size[1] * size[2]
            # platt: nur Wanne, Kotflügel, Türen, Dach; intakt zusätzlich Front- und Heckblech
            if vol < 0.5 or (flat and size[2] < 0.35):
                continue
            role = "paint"
        elif nm == "Hood":
            role = "paint"
            if hood:
                cf = CF(0, 3.9, -3.55) * CF.angles(math.radians(hood), 0, 0) * CF(0, 0, -size[2] / 2)
        elif nm == "Pillar" and not flat:
            role = "trim"
        elif nm.startswith("Wheel") and nm.endswith("Tire") and nm[5:7] in tires:
            role = "tire"
        elif nm == "Bumper" and bumper and not flat and cf.p[2] > 0:
            role = "trim"
        if role:
            parts.append([nm, it.get("class"), _shape(it), size, cf, role])
    if flat:
        # Dach = höchstes Paint-Teil; es sinkt auf die Oberkante der übrigen Karosserie
        paints = [p for p in parts if p[0] == "Paint"]
        roof = max(paints, key=lambda p: p[4].p[1])
        rest_top = max(p[4].p[1] + p[3][1] / 2 for p in paints if p is not roof)
        y = rest_top + roof[3][1] / 2 + 0.01
        roof[4] = CF(roof[4].p[0], y, roof[4].p[2]) * CF.angles(0, 0, math.radians(3))
    # Die Vorlagen haben bündige Flächen (im vollen Auto-Klon vom Z-Fighting-Check ausgenommen). Jedes Teil wird
    # um einen eigenen, winzigen Betrag verkleinert, damit keine zwei Flächen in derselben Ebene liegen.
    for k, p in enumerate(parts):
        d = 0.012 + 0.007 * k
        p[3] = tuple(max(0.05, v - d) for v in p[3])
    return parts


def _sample_points(cf, size):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    pts = []
    for a in (-1, -0.5, 0, 0.5, 1):
        for b in (-1, -0.5, 0, 0.5, 1):
            pts.append(cf.point((a * hx, -hy, b * hz)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                pts.append(cf.point((sx * hx, sy * hy, sz * hz)))
    return pts


def place_wreck(lib, parent, spec, pose, paint, name="Wrack", support=None, top=None, collide=True, gap=0.03):
    """Setzt ein Lite-Wrack. pose = CF ohne Höhe (x, 0, z + Drehung). Mit support: fällt auf die Höhenkarte;
    mit top: hängt mit der Oberkante auf Y top (Kranmagnet)."""
    color, material = paint
    world = [(p, pose * p[4]) for p in spec]
    if support is not None:
        lift = max(support.height(q[0], q[2]) - q[1] for p, cf in world for q in _sample_points(cf, p[3])) + gap
    else:
        hi = max(q[1] for p, cf in world for q in _sample_points(cf, p[3]))
        lift = top - hi
    m = lib.model(parent, name, attrs={"LiteWreck": True})
    made = []
    for (nm, cls, shape, size, _lcf, role), cf in world:
        cf = cf.moved(0, lift, 0)
        if role == "paint":
            col, mat = color, material
        elif role == "chassis":
            col, mat = (58, 50, 44), "CorrodedMetal"
        elif role == "tire":
            col, mat = RUBBER, "SmoothPlastic"
        else:
            col, mat = (40, 42, 46), "Metal"
        small = min(size) < 0.3 and role != "paint"
        it = lib.part(m, nm, size, cf, col, mat, shape=shape, cls=cls, collide=collide and not small,
                      deco=small or not collide)
        made.append(it)
    if support is not None:
        for it in made:
            support.add(it)
    return m


def place_block(lib, parent, name, size, pose, color, material, support, gap=0.02, **kw):
    """Quader (Pressling/Ballen) auf die Höhenkarte fallen lassen"""
    lift = max(support.height(q[0], q[2]) - q[1] for q in _sample_points(pose, size)) + gap
    it = lib.part(parent, name, size, pose.moved(0, lift, 0), color, material, **kw)
    support.add(it)
    return it


# ---------------------------------------------------------------- Bauabschnitte
def build(city, lib, tree):
    """Baut Schrottplatz (siehe docs/CITY_SPEC.md §6 D10)."""
    rng = random.Random(1010)
    dm = lib.model(lib.folder(city, "Districts"), NAME)
    anim = lib.folder(lib.folder(city, "Animated"), NAME)
    with lib.section("D10 Schrottplatz"):
        build_fence(dm, lib)
        build_gate(dm, anim, lib)
        build_entry(dm, lib)
        build_kontor(dm, lib)
        build_hall(dm, lib)
        build_press(anim, lib)
        build_conveyor_bunker(dm, lib, rng)
        build_chimney(dm, anim, lib)
        build_crane(dm, anim, lib)
        build_piles(dm, lib, rng)
        build_yard_props(dm, lib, rng)
        build_zerlegeplatz(dm, lib)
    return dm


# ---------------------------------------------------------------- Zaun
def build_fence(dm, lib):
    m = lib.model(dm, "Zaun")
    x0, x1, z0, z1 = YARD
    t = 0.4
    top = 7.0
    band = (4.6, 5.6)
    # (Name, x0, x1, z0, z1, Außenrichtung (dx, dz), Pfosten-Achse)
    segs = [
        ("Nord", x0, x1, z0, z0 + t, (0, -1)),
        ("West", x0, x0 + t, z0 + t, z1 - t, (-1, 0)),
        ("Sued-West", x0, -329, z1 - t, z1, (0, 1)),
        ("Sued-Ost", -317, x1, z1 - t, z1, (0, 1)),
        ("Ost-Nord", x1 - t, x1, z0 + t, -214, (1, 0)),
        ("Ost-Sued", x1 - t, x1, -188, z1 - t, (1, 0)),
    ]
    for nm, a0, a1, b0, b1, (dx, dz) in segs:
        lib.box(m, "Wellblech_" + nm, a0, a1, Y_DIRT, top, b0, b1, CORR, "Metal")
        # Roststreifen auf der Außenseite
        if dx:
            xo = a1 if dx > 0 else a0
            lib.box(m, "Rostband", min(xo, xo + dx * 0.08), max(xo, xo + dx * 0.08), band[0], band[1], b0, b1,
                    RUST, "CorrodedMetal", deco=True)
        else:
            zo = b1 if dz > 0 else b0
            lib.box(m, "Rostband", a0, a1, band[0], band[1], min(zo, zo + dz * 0.08), max(zo, zo + dz * 0.08),
                    RUST, "CorrodedMetal", deco=True)
        # Pfosten innen (Hofseite), rostig, alle ~44 Studs
        length = (a1 - a0) if not dx else (b1 - b0)
        n = max(2, int(round(length / 60)) + 1)
        for k in range(n):
            f = k / (n - 1)
            if dx:
                zc = b0 + 3 + f * (b1 - b0 - 6)
                if nm == "Ost-Nord" and zc > -238:
                    continue      # dort parkt der Schiebetor-Flügel
                xi = a0 if dx > 0 else a1          # Innenseite
                xa, xb = (xi - 0.7, xi) if dx > 0 else (xi, xi + 0.7)
                lib.box(m, "Zaunpfosten", xa, xb, Y_DIRT, top + 0.4, zc - 0.35, zc + 0.35, RUST_DARK, "CorrodedMetal")
            else:
                xc = a0 + 1 + f * (a1 - a0 - 2)
                zi = b0 if dz > 0 else b1
                za, zb = (zi - 0.7, zi) if dz > 0 else (zi, zi + 0.7)
                lib.box(m, "Zaunpfosten", xc - 0.35, xc + 0.35, Y_DIRT, top + 0.4, za, zb, RUST_DARK, "CorrodedMetal")
    # Banner zur Marktstraße und Hintertor-Portal
    lib.sign(m, "SCHROTTPLATZ · RECYCLINGHOF", (26, 3.2), CF.at(-177.9, 2.4, -290, 90), (255, 232, 200), RUST,
             name="Zaunbanner", sub="Ankauf von Altfahrzeugen · Einfahrt ›", sub_color=YELLOW)
    for xa in (-329, -318):
        lib.box(m, "Hintertor_Pfosten", xa, xa + 1, Y_DIRT, 11, -159.6, -158.6, YELLOW, "Metal")
    lib.box(m, "Hintertor_Balken", -329, -317, 11, 12, -159.6, -158.6, BLACK, "Metal")
    lib.sign(m, "SCHROTTPLATZ", (10, 2.2), CF.at(-323, 13.1, -158.9, 0), (255, 232, 200), RUST, name="Hintertor_Schild",
             sub="Hintereingang · Schrottgasse", sub_color=YELLOW)


# ---------------------------------------------------------------- Einfahrtstor
def build_gate(dm, anim, lib):
    m = lib.model(dm, "Tor")
    for zc in (-212.5, -189.5):
        lib.box(m, "Torpfeiler", -181, -178.02, -2, 16, zc - 1.5, zc + 1.5, YELLOW, "Metal")
        for y in (1.5, 6.5, 11.5):
            lib.box(m, "Warnring", -181.05, -177.95, y, y + 2, zc - 1.55, zc + 1.55, BLACK, "Metal")
    lib.box(m, "Torbalken", -181, -178, 16, 19, -214, -188, BLACK, "Metal")
    lib.box(m, "Torbalken_Neon", -180.8, -178.2, 15.8, 16, -211, -191, AMBER, "Neon", deco=True)
    lib.sign(m, "SCHROTTPLATZ", (24, 5), CF.at(-179.3, 21.5, -201, 90), (255, 232, 200), RUST, name="Torschild",
             sub="RECYCLINGHOF · ANKAUF · PRESSE", sub_color=YELLOW, bolts=True)
    lib.sign(m, "GUTE FAHRT!", (24, 5), CF.at(-179.5, 21.5, -201, -90), YELLOW, RUST, name="Torschild_Innen",
             sub="Ausfahrt Marktstraße", sub_color=(255, 232, 200), bolts=False)
    lib.box(m, "Leuchtensockel", -179.8, -178.8, 24, 24.3, -201.5, -200.5, STEEL, "Metal")
    b = lib.ball(anim, "Torleuchte", (-179.3, 24.95, -201), 1.4, AMBER, "Neon", deco=True)
    set_attrs(b, {"Anim": "beacon", "Period": 1.2})
    # geparkter Schiebetor-Flügel innen am Zaun
    lib.box(m, "Schiebetor", -180.2, -179.8, -0.6, 6.4, -236, -215, CORR, "DiamondPlate", transparency=0.25)
    lib.box(m, "Schiebetor_Rahmen", -180.3, -179.7, 6.4, 6.9, -236, -215, YELLOW, "Metal")
    lib.box(m, "Schiebetor_Laufschiene", -180.4, -179.6, Y_DIRT, -0.6, -238, -213.5, STEEL, "Metal")


# ---------------------------------------------------------------- Einfahrt, Waage, Wege
def build_entry(dm, lib):
    m = lib.model(dm, "Einfahrt")
    lib.box(m, "Betonzufahrt", -310, -178, -1.3, Y_ROAD, -209, -193, CONCRETE_DARK, "Concrete")
    for z0 in (-208.6, -193.8):
        lib.box(m, "Randlinie", -306, -180, Y_ROAD, -0.96, z0, z0 + 0.4, YELLOW, "SmoothPlastic", deco=True)
    lib.box(m, "Waagenrahmen", -271, -245, -1.05, -0.94, -209, -193, STEEL, "Metal")
    lib.box(m, "Fahrzeugwaage", -270, -246, -1.06, -0.86, -208, -194, (122, 128, 132), "DiamondPlate")
    lib.box(m, "Waagenpylon_Fuss", -259.5, -256.5, Y_DIRT, 0.2, -213, -211, CONCRETE, "Concrete")
    lib.box(m, "Waagenpylon", -258.6, -257.4, 0.2, 8, -212.4, -211.6, SLATE, "Metal")
    lib.sign(m, "WAAGE  0,00 t", (6, 2.2), CF.at(-258, 9, -211.3, 0), (255, 80, 60), BLACK, name="Waagenanzeige",
             font="RobotoMono", sub="bitte langsam auffahren", sub_color=AMBER, bolts=False)
    lib.box(m, "Waagenanzeige_Gehaeuse", -261.2, -254.8, 7.7, 10.3, -212.6, -211.4, SLATE, "Metal")
    # Fußweg vom Hintertor zur Einfahrt (Oberseite -0.50 wie die Schrottgasse)
    lib.box(m, "Fussweg", -326, -320, Y_DIRT, -0.5, -172, -159, (128, 134, 138), "Concrete")
    lib.box(m, "Fussweg", -326, -304, Y_DIRT, -0.5, -178, -172, (128, 134, 138), "Concrete")
    lib.box(m, "Fussweg", -310, -304, Y_DIRT, -0.5, -193, -178, (128, 134, 138), "Concrete")
    # Rampe zur Hallenöffnung (von der Zufahrt -0.98 auf den Hallenboden 0)
    lib.wedge(m, "Hallenrampe", (30, 0.98, 4), CF.at(-308, Y_ROAD + 0.49, -211, -90), (122, 128, 132), "DiamondPlate")


# ---------------------------------------------------------------- Schrotthändler-Kontor
def build_kontor(dm, lib):
    m = lib.model(dm, "Kontor")
    # Untergeschoss (Container-Optik) mit Schalter-Nische auf der Südseite
    lib.box(m, "Container_Unten", -236, -204, Y_DIRT, 9, -246, -219, KONTOR_RED, "Metal")
    lib.box(m, "Front_Links", -236, -228, Y_DIRT, 9, -219, -216, KONTOR_RED, "Metal")
    lib.box(m, "Front_Rechts", -212, -204, Y_DIRT, 9, -219, -216, KONTOR_RED, "Metal")
    lib.box(m, "Front_Bruestung", -228, -212, Y_DIRT, 3, -219, -216, KONTOR_RED, "Metal")
    lib.box(m, "Front_Sturz", -228, -212, 8, 9, -219, -216, KONTOR_RED, "Metal")
    lib.box(m, "Tresen", -228, -212, 3, 3.3, -219, -214.6, (130, 90, 60), "Wood")
    lib.box(m, "Schalterfenster", -228, -220.2, 3.3, 8, -216.4, -216.2, (116, 159, 178), "Glass", transparency=0.4)
    lib.box(m, "Kasse", -217, -214.8, 3.3, 4.3, -218.6, -217.2, SLATE, "SmoothPlastic", deco=True)
    lib.box(m, "Laptop", -224, -222, 3.3, 3.45, -218.4, -217, (60, 64, 70), "SmoothPlastic", deco=True)
    lib.sign(m, "ANKAUF", (7, 1.6), CF.at(-220, 6.4, -218.9, 0), AMBER, SLATE, name="Schalter_Innen", bolts=False)
    lamp = lib.box(m, "Schalterlampe", -221.5, -218.5, 7.75, 8, -218.4, -217.2, LAMP, "Neon", deco=True)
    set_attrs(lamp, {"NightNeon": True})
    lib.point_light(lamp, 20, 0.9, LAMP, name="KontorLicht")
    lib.box(m, "Vordach", -229, -211, 8.4, 8.7, -216, -212.6, YELLOW, "Metal")
    lib.box(m, "Vordach_Kante", -229, -211, 8.1, 8.4, -212.9, -212.6, BLACK, "Metal", deco=True)
    # Container-Rippen (Außenhaut)
    for x in (-209, -206):
        lib.box(m, "Rippe", x - 0.25, x + 0.25, -0.8, 8.8, -216, -215.85, (126, 56, 36), "Metal", deco=True)
    for z in (-242, -236, -230, -224):
        lib.box(m, "Rippe", -204, -203.85, -0.8, 8.8, z - 0.25, z + 0.25, (126, 56, 36), "Metal", deco=True)
    lib.box(m, "Tuer", -203.85, -203.7, -1, 6, -222, -219.5, SLATE, "Metal")
    # Obergeschoss (gelber Büro-Container) mit Firmenschild
    lib.box(m, "Container_Oben", -234, -206, 9, 15, -244, -218, YELLOW, "Metal")
    lib.box(m, "Dach", -234.5, -205.5, 15, 15.5, -244.5, -217.5, GRAPHITE, "Metal")
    lib.box(m, "Fensterband", -232, -226, 10.5, 13.5, -217.98, -217.9, (116, 159, 178), "Glass", transparency=0.3,
            deco=True)
    lib.sign(m, "SCHROTTHÄNDLER · ANKAUF", (17, 3), CF.at(-214.5, 12, -217.9, 0), AMBER, SLATE, name="Kontorschild",
             sub="Altauto · Metall · Ersatzteile", sub_color=WHITE)
    lib.box(m, "Klimageraet", -232, -228, 15.5, 17.5, -242, -239, (170, 176, 180), "Metal")
    lib.sign(m, "ANKAUFSPREISE", (6.4, 4), CF.at(-232, 4.6, -215.9, 0), AMBER, SLATE, name="Preistafel",
             sub="Stahl · Alu · Kupfer · Katalysator", sub_color=WHITE)


# ---------------------------------------------------------------- Presse-Halle
def build_hall(dm, lib):
    m = lib.model(dm, "PresseHalle")
    X0, X1, Z0, Z1 = HALL
    H = HALL_H
    wall = (48, 54, 61)
    lib.box(m, "Hallenboden", X0, X1, Y_DIRT, 0, Z0, Z1, CONCRETE, "Concrete")
    # Nord- und Südwand (volle Breite), Südwand mit Glasband
    lib.box(m, "Nordwand", X0, X1, 0, H, Z0, Z0 + 1, wall, "Metal")
    lib.box(m, "Suedwand", X0, X1, 0, 14, Z1 - 1, Z1, wall, "Metal")
    lib.box(m, "Suedwand_Glasband", X0, X1, 14, 20, Z1 - 0.7, Z1 - 0.3, (150, 140, 110), "Glass", transparency=0.45)
    lib.box(m, "Suedwand_Oben", X0, X1, 20, H, Z1 - 1, Z1, wall, "Metal")
    for x in (-366, -352, -338, -324):
        lib.box(m, "Pfosten_Glas", x - 0.3, x + 0.3, 13.95, 20.05, Z1 - 1.1, Z1 + 0.1, (66, 80, 94), "Metal")
    # Westwand mit Förderband-Öffnung Z -218..-204, Y 0..6 (Stahlgitter)
    lib.box(m, "Westwand", X0, X0 + 1, 0, H, Z0 + 1, -218, wall, "Metal")
    lib.box(m, "Westwand", X0, X0 + 1, 0, H, -204, Z1 - 1, wall, "Metal")
    lib.box(m, "Westwand_Sturz", X0, X0 + 1, 6, H, -218, -204, wall, "Metal")
    lib.box(m, "Stahlgitter", X0 + 0.3, X0 + 0.7, 2.2, 6, -218, -204, STEEL, "DiamondPlate", transparency=0.6)
    # Ostseite: Einfahrt Z -228..-194, Y 0..26, Sturz mit Schild
    lib.box(m, "Ostwand", X1 - 1, X1, 0, H, Z0 + 1, -228, wall, "Metal")
    lib.box(m, "Ostwand", X1 - 1, X1, 0, H, -194, Z1 - 1, wall, "Metal")
    lib.box(m, "Ostwand_Sturz", X1 - 1, X1, 26, H, -228, -194, wall, "Metal")
    lib.sign(m, "SCHROTTPRESSE", (30, 5.4), CF.at(X1 + 0.12, 30, -211, 90), YELLOW, BLACK, name="Hallenschild")
    # Warnstreifen an den Torleibungen (gelb/schwarz im Wechsel)
    for zs, (za, zb) in ((-1, (-229.2, -228)), (1, (-194, -192.8))):
        for k in range(2):
            col = YELLOW if k % 2 == 0 else BLACK
            lib.box(m, "Torleibung", X1, X1 + 0.1, k * 13, (k + 1) * 13, za, zb, col, "Metal", deco=True)
    lib.box(m, "Torsturz_Warnstreifen", X1, X1 + 0.1, 26, 27, -228, -194, YELLOW, "Metal", deco=True)
    # Rostbänder außen (Sockel und Traufe)
    rb = (0, 2)
    tb = (29.5, 31.5)
    lib.box(m, "Rostband", X0 - 0.1, X1 + 0.1, rb[0], rb[1], Z0 - 0.1, Z0, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X0 - 0.1, X1 + 0.1, tb[0], tb[1], Z0 - 0.1, Z0, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X0 - 0.1, X1 + 0.1, rb[0], rb[1], Z1, Z1 + 0.1, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X0 - 0.1, X1 + 0.1, tb[0], tb[1], Z1, Z1 + 0.1, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X0 - 0.1, X0, tb[0], tb[1], Z0, Z1, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X0 - 0.1, X0, rb[0], rb[1], Z0, -218, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X0 - 0.1, X0, rb[0], rb[1], -204, Z1, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X1, X1 + 0.1, rb[0], rb[1], Z0, -229.2, RUST, "CorrodedMetal", deco=True)
    lib.box(m, "Rostband", X1, X1 + 0.1, rb[0], rb[1], -192.8, Z1, RUST, "CorrodedMetal", deco=True)
    # Decke: Binder Y 30..31,5 (30 frei), Deckenplatte 33..34
    lib.box(m, "Deckenplatte", X0 + 1, X1 - 1, 33, H, Z0 + 1, Z1 - 1, (58, 64, 72), "Metal")
    for zc in (-238.33, -226.67, -215.0, -203.33, -191.67):
        lib.box(m, "Binder", X0 + 1, X1 - 1, 30, 31.5, zc - 0.5, zc + 0.5, TRUSS, "Metal")
    # Sheddach: 3 Zähne entlang Z, je 23,33 tief, Glas-Nordseiten (nachts Neon)
    depth = 70 / 3
    for k in range(3):
        zs = Z0 + k * depth
        glass = lib.box(m, "Shedverglasung", X0, X1, H, H + 7, zs, zs + 0.4, (150, 140, 110), "Glass",
                        transparency=0.5)
        set_attrs(glass, {"NightNeon": True})
        d = depth - 0.4
        lib.wedge(m, "Shedzahn", (70, 7, d), CF.at((X0 + X1) / 2, H + 3.5, zs + 0.4 + d / 2, 180), (58, 64, 72),
                  "Metal")
        lib.box(m, "Firstblech", X0 - 0.2, X1 + 0.2, H + 7, H + 7.3, zs - 0.1, zs + 0.6, RUST, "CorrodedMetal")
    # Pendelleuchten (2 Lichter, Range 36)
    for zc in (-200, -235):
        lib.box(m, "Pendel", -350.15, -349.85, 28.9, 33, zc - 0.15, zc + 0.15, STEEL, "Metal", deco=True)
        lib.box(m, "Leuchtengehaeuse", -351.6, -348.4, 28.4, 28.9, zc - 1.6, zc + 1.6, SLATE, "Metal", deco=True)
        lamp = lib.box(m, "Leuchte", -351.3, -348.7, 28.2, 28.4, zc - 1.3, zc + 1.3, NEON_WHITE, "Neon", deco=True)
        lib.point_light(lamp, 36, 1.0, HALL_LIGHT, name="HallenLicht")
    # Boden: Sicherheitslinien um die Presse, Gehweg zum Steuerpult
    for (a0, a1, b0, b1) in ((-370, -334, -224.5, -224), (-370, -334, -198, -197.5),
                             (-370.5, -370, -224.5, -197.5), (-334, -333.5, -224.5, -197.5)):
        lib.box(m, "Sicherheitslinie", a0, a1, 0, 0.02, b0, b1, YELLOW, "SmoothPlastic", deco=True)
    lib.box(m, "Gehweglinie", -330, -311, 0, 0.02, -223.2, -222.8, WHITE, "SmoothPlastic", deco=True)
    # Steuerpult (-324,0,-220): Sockel, geneigtes Pult, roter Not-Aus-Pilz
    lib.box(m, "Steuerpult", -325.2, -323, 0, 3.2, -221.6, -218.4, SLATE, "Metal")
    panel = lib.part(m, "Pultplatte", (2.6, 0.3, 3.4), CF(-323.9, 3.6, -220) * CF.angles(0, 0, math.radians(-25)),
                     AMBER, "Metal")
    lib.surface_text(panel, "PRESSE", face="Top", text_color=BLACK)
    lib.cylinder(m, "NotAus", (-323.8, 3.9, -221), 0.4, 0.9, "Y", RED_NEON, "Neon", deco=True)
    lib.box(m, "Pultanzeige_Mast", -325.1, -324.7, 3.2, 6.2, -218.9, -218.5, STEEL, "Metal", deco=True)
    lib.sign(m, "320 bar", (2.6, 1.3), CF.at(-324.6, 6.6, -218.7, 90), (80, 255, 140), BLACK, name="Druckanzeige",
             font="RobotoMono", bolts=False)
    # Ballenstapel (8 Presslinge 4x4x4) bei (-372,-236)
    sup = Support(0.0)
    k = 0
    for layer, cells in ((0, [(-2.2, -2.2), (2.2, -2.2), (-2.2, 2.2), (2.2, 2.2)]),
                         (1, [(-1.2, -2.2), (2.4, -1.4), (0.6, 2.2)]), (2, [(0.4, -0.2)])):
        for dx, dz in cells:
            pose = CF.at(-372 + dx, 2, -236 + dz, (k * 13) % 7 - 3)
            place_block(lib, m, "Pressling", (4, 4, 4), pose, CUBE_COLORS[k % len(CUBE_COLORS)], "CorrodedMetal", sup)
            k += 1
    # Ölfässer, Feuerlöscher, Warnschilder
    for i, (x, z, col) in enumerate(((-376.2, -245.4, (40, 70, 130)), (-373.4, -245.6, (160, 50, 40)),
                                     (-375.0, -242.6, RUST))):
        lib.cylinder(m, "Oelfass", (x, 1.7, z), 3.4, 2.4, "Y", col, "Metal")
    lib.cylinder(m, "Feuerloescher", (-312.2, 1.2, -231), 2.4, 0.8, "Y", (200, 30, 30), "SmoothPlastic", deco=True)
    lib.sign(m, "ACHTUNG · PRESSE IN BETRIEB", (18, 3), CF.at(-352, 12, -248.88, 0), BLACK, YELLOW, name="Warnschild",
             sub="Abstand halten · Gehörschutz tragen", sub_color=BLACK)
    lib.sign(m, "RECYCLINGHOF", (14, 2.6), CF.at(-352, 24, -180.88 - 0.24, 180), AMBER, SLATE, name="Innenschild",
             sub="Presse · Ballenlager · Förderband", sub_color=WHITE)


# ---------------------------------------------------------------- Presse (Animated, Anim=press)
def build_press(anim, lib):
    px, pz = PRESS
    m = lib.model(anim, "Presse", attrs={"Anim": "press", "Stroke": 12.5, "Period": 6.0, "Down": 1.2, "Hold": 0.4,
                                        "Up": 2.0, "Squash": 0.35, "RestY": 16.0, "BedY": 3.0})
    # Ram zuerst (CityClient bewegt das erste Kind mit "ram" im Namen)
    ram = lib.model(m, "Ram")
    plate = lib.box(ram, "Plate", px - 10, px + 10, 16, 18, pz - 6, pz + 6, (86, 92, 98), "Metal")
    for x in (px - 5, px + 5):
        lib.cylinder(ram, "Kolbenstange", (x, 18 + 6.45, pz), 12.9, 1.4, "Y", (205, 212, 216), "Metal")
    lib.box(ram, "Plate_Kante", px - 9.9, px + 9.9, 16.6, 17.2, pz - 6.05, pz + 6.05, YELLOW, "Metal", deco=True)
    lib.set_primary(ram, plate)
    lib.box(m, "Pressbett", px - 12, px + 12, 0, 3, pz - 7, pz + 7, (70, 76, 82), "Metal")
    for x0 in (px - 14, px + 10):
        for zc in (pz - 7, pz + 7):
            lib.box(m, "Saeule", x0, x0 + 4, 0, 24, zc - 1.25, zc + 1.25, (60, 66, 72), "Metal")
    lib.box(m, "Querhaupt", px - 14, px + 14, 24, 28, pz - 8, pz + 8, YELLOW, "Metal")
    lib.sign(m, "SCHROTTPRESSE 800 t", (16, 2.2), CF.at(px, 26, pz + 8.12, 0), BLACK, YELLOW, name="Querhaupt_Schild",
             bolts=False)
    for x in (px - 5, px + 5):
        lib.cylinder(m, "Zylinder", (x, 21, pz), 6, 3, "Y", (70, 76, 82), "Metal")
        lib.cylinder(m, "Zylinderkopf", (x, 29.5, pz), 3, 3.4, "Y", (70, 76, 82), "Metal")
    # Wrack auf dem Bett (Car), Funken-Blitz (Spark), 2 Rundumleuchten auf dem Querhaupt
    spec = wreck_spec(lib, "sedan", flat=True, tires=(), hood=0)
    car = place_wreck(lib, m, spec, CF.at(px, 0, pz, 90), WRECK_COLORS[2], name="Car", support=Support(3.0),
                      collide=False, gap=0.0)
    set_attrs(car, {"Squash": 0.35})
    lib.part(m, "Spark", (1, 1, 1), CF(px, 4.2, pz + 6.5), (255, 200, 90), "Neon", transparency=1, deco=True)
    for x in (px - 12, px + 12):
        lib.box(m, "Leuchtensockel", x - 0.4, x + 0.4, 28, 28.3, pz - 0.4, pz + 0.4, STEEL, "Metal", deco=True)
        bk = lib.ball(m, "Rundumleuchte", (x, 28.95, pz), 1.3, AMBER, "Neon", deco=True)
        set_attrs(bk, {"Anim": "beacon", "Period": 0.8})


# ---------------------------------------------------------------- Aufgabebunker und Förderband
def build_conveyor_bunker(dm, lib, rng):
    m = lib.model(dm, "Aufgabebunker")
    bx0, bx1, bz0, bz1 = -402, -382, -222, -200
    lib.box(m, "Bunkerboden", bx0, bx1, Y_DIRT, -0.5, bz0, bz1, CONCRETE, "Concrete")
    lib.box(m, "Bunkerwand", bx0, bx1, -0.5, 1.5, bz0, bz0 + 1, CONCRETE_DARK, "Concrete")
    lib.box(m, "Bunkerwand", bx0, bx1, -0.5, 1.5, bz1 - 1, bz1, CONCRETE_DARK, "Concrete")
    lib.box(m, "Bunkerwand", bx0, bx0 + 1, -0.5, 1.5, bz0 + 1, bz1 - 1, CONCRETE_DARK, "Concrete")
    for k in range(5):
        col = YELLOW if k % 2 == 0 else BLACK
        lib.box(m, "Warnstreifen", bx1 - 1.2, bx1, -0.5, -0.48, bz0 + 1 + k * 4, bz0 + 1 + (k + 1) * 4, col,
                "SmoothPlastic", deco=True)
    lib.cylinder(m, "Abwurfmarke", (BUNKER[0], -0.49, BUNKER[1]), 0.02, 5, "Y", YELLOW, "SmoothPlastic", deco=True)
    sup = Support(-0.5)
    place_block(lib, m, "Pressling", (3.4, 3, 3.6), CF.at(-397, 0, -205, 17), CUBE_COLORS[0], "CorrodedMetal", sup)
    place_block(lib, m, "Pressling", (3.2, 3.2, 3.2), CF.at(-397.5, 0, -216.5, -9), CUBE_COLORS[3], "CorrodedMetal",
                sup)
    # Förderband: vom Bunker (-386) durch das Gitter auf das Pressbett (-364), 22 x 1 x 8, steigend 0,8 -> 3,4
    f = lib.model(dm, "Foerderband")
    a, b = (-386, 0.3, -211), (-364, 2.9, -211)
    lib.beam(f, "Band", a, b, 8, (34, 36, 40), "SmoothPlastic", depth=1.0)
    for dz in (-4.3, 4.3):
        lib.beam(f, "Bandwange", (a[0], a[1] + 0.3, a[2] + dz), (b[0], b[1] + 0.3, b[2] + dz), 0.6, YELLOW, "Metal",
                 depth=1.4)
    for x in (-375, -368):
        t = (x - a[0]) / (b[0] - a[0])
        yb = a[1] + t * (b[1] - a[1]) - 0.5
        for dz in (-3.4, 3.4):
            lib.box(f, "Bandstuetze", x - 0.3, x + 0.3, 0, yb, -211 + dz - 0.3, -211 + dz + 0.3, STEEL, "Metal")


# ---------------------------------------------------------------- Schornstein
def build_chimney(dm, anim, lib):
    m = lib.model(dm, "Schornstein")
    cx, cz = -304, -246
    lib.box(m, "Sockel", cx - 3.5, cx + 3.5, Y_DIRT, 0, cz - 3.5, cz + 3.5, CONCRETE_DARK, "Concrete")
    lib.cylinder(m, "Schaft", (cx, 28, cz), 56, 5, "Y", RUST, "CorrodedMetal")
    for y in (44, 49.5):
        lib.cylinder(m, "Weissband", (cx, y, cz), 2, 5.3, "Y", WHITE, "SmoothPlastic")
    cap = lib.cylinder(m, "Kopfring", (cx, 55.65, cz), 1.3, 5.7, "Y", (60, 52, 46), "Metal")
    smoke = lib.item(cap, "Smoke", "Rauch")
    p = props(smoke)
    _color3_el(p, "Color", (150, 146, 140))
    _sub_el(p, "bool", "Enabled", "true")
    _sub_el(p, "float", "opacity_xml", "0.18")
    _sub_el(p, "float", "riseVelocity_xml", "4")
    _sub_el(p, "float", "size_xml", "3")
    lib.cylinder(m, "Rauchrohr", (-307.5, 20, cz), 5, 1.6, "X", (70, 76, 82), "Metal")
    for y in (8, 20, 32):
        lib.box(m, "Steigeisen", cx + 2.45, cx + 2.75, y, y + 12, cz - 0.4, cz + 0.4, STEEL, "Metal", deco=True)
    b = lib.ball(anim, "Kaminlicht", (cx, 56.9, cz), 1.2, RED_NEON, "Neon", deco=True)
    set_attrs(b, {"Anim": "beacon", "Period": 1.0, "Aviation": True})


# ---------------------------------------------------------------- Magnetkran
def build_crane(dm, anim, lib):
    mx, mz = MAST
    st = lib.model(dm, "Kranmast")
    lib.box(st, "Fundament", mx - 5, mx + 5, -1, 1, mz - 5, mz + 5, CONCRETE_DARK, "Concrete")
    posts = [(-2.6, -2.6), (2.6, -2.6), (2.6, 2.6), (-2.6, 2.6)]
    for dx, dz in posts:
        lib.box(st, "Maststiel", mx + dx - 0.4, mx + dx + 0.4, 1, 51.5, mz + dz - 0.4, mz + dz + 0.4, YELLOW, "Metal")
    lib.box(st, "Mastkopf", mx - 3.1, mx + 3.1, 51.5, 52, mz - 3.1, mz + 3.1, YELLOW, "Metal")
    # 6 Diagonalen: Nord/Süd unten, Ost/West Mitte, Nord/Süd oben
    for (y0, y1), faces in (((1.5, 18), ("N", "S")), ((18, 35), ("E", "W")), ((35, 51.5), ("N", "S"))):
        for f in faces:
            if f in "NS":
                z = mz + (-2.6 if f == "N" else 2.6)
                a, b = (mx - 2.6, y0, z), (mx + 2.6, y1, z)
            else:
                x = mx + (2.6 if f == "E" else -2.6)
                a, b = (x, y0, mz - 2.6), (x, y1, mz + 2.6)
            lib.beam(st, "Mastdiagonale", a, b, 0.35, YELLOW, "Metal")
    lib.sign(st, "MAGNETKRAN · 66 m", (4.4, 1.4), CF.at(mx, 4, mz + 3.05, 0), BLACK, YELLOW, name="Kranschild",
             bolts=False)
    # Drehteil: Jib zeigt in der Ruhelage mittig zwischen Bunker und Haufen 3 (Schwenk ±31,5° erreicht beide)
    ang_b = math.degrees(math.atan2(BUNKER[0] - mx, BUNKER[1] - mz))
    ang_3 = math.degrees(math.atan2(PILES_CRANE[2][0] - mx, PILES_CRANE[2][1] - mz))
    mid = math.radians((ang_b + ang_3) / 2)
    yaw = yaw_towards(math.sin(mid), math.cos(mid))
    swing = abs(ang_b - ang_3) / 2
    F = CF.at(mx, 0, mz, yaw)

    def L(x, y, z):
        return F.point((x, y, z))

    def box(parent, nm, x0, x1, y0, y1, z0, z1, col, mat="Metal", **kw):
        return lib.part(parent, nm, (x1 - x0, y1 - y0, z1 - z0),
                        F * CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), col, mat, **kw)

    trolley_r = 57.5
    attrs = {"Anim": "crane", "Swing": round(swing, 1), "Period": 40.0, "MaxSlew": 15.0, "CarryY": 45.0, "DropY": 3.0,
             "TrolleyR": trolley_r, "Bunker": Vec3(BUNKER[0], -0.5, BUNKER[1])}
    for i, (x, z) in enumerate(PILES_CRANE):
        attrs["Pile%d" % (i + 1)] = Vec3(x, -1.0, z)
    cr = lib.model(anim, "Magnetkran", attrs=attrs)
    deck = box(cr, "Drehbuehne", -4, 4, 53, 53.6, -4, 4, (70, 76, 82))
    lib.set_primary(cr, deck)
    lib.cylinder(cr, "Drehkranz", (mx, 52.5, mz), 1, 6.4, "Y", (60, 66, 72), "Metal")
    cab = box(cr, "Kabine", 2.9, 7.3, 53.6, 58.2, -3.4, 1.2, YELLOW)
    box(cr, "Kabinenfenster", 3.3, 6.9, 55.4, 57.8, -3.6, -3.4, (116, 159, 178), "Glass", transparency=0.3, deco=True)
    del cab
    boom = lib.model(cr, "Boom")
    for sx in (-1.5, 1.5):
        box(boom, "Untergurt", sx - 0.3, sx + 0.3, 53.6, 54.2, -64.2, -3.5, YELLOW)
    box(boom, "Obergurt", -0.3, 0.3, 56.4, 57.0, -64.2, -3.5, YELLOW)
    box(boom, "Auslegerfuss", -1.9, 1.9, 53.6, 56.9, -4, -3, YELLOW)
    box(boom, "Auslegerspitze", -1.9, 1.9, 53.6, 56.9, -64.4, -64, YELLOW)
    for i, z in enumerate((-8, -22, -36, -50)):
        for sx in (-1.5, 1.5):
            if (i + (sx > 0)) % 2:
                continue
            lib.beam(boom, "Diagonale", L(sx * 0.9, 54.1, z), L(0, 56.5, z - 7), 0.3, YELLOW, "Metal", deco=True)
    # Gegenausleger mit 2 Gewichten
    for sx in (-1.2, 1.2):
        box(cr, "Gegenausleger", sx - 0.4, sx + 0.4, 53.6, 54.4, 2, 17.8, YELLOW)
    box(cr, "Gegenausleger_Ende", -1.7, 1.7, 53.6, 54.5, 17.6, 18.2, YELLOW)
    for i, (z0, z1) in enumerate(((11, 14.2), (14.4, 17.6))):
        w = box(cr, "Gegengewicht", -1.9, 1.9, 50.2, 53.6, z0, z1, CONCRETE, "Concrete")
        if i == 0:
            lib.surface_text(w, "SCHROTT", face="Right", text_color=YELLOW)
    # A-Bock, Abspannung, Flugwarnlicht
    apex = L(0, 66, 0.5)
    for sx in (-2.4, 2.4):
        lib.beam(cr, "ABock", L(sx, 53.6, 1), apex, 0.5, YELLOW, "Metal")
    lib.beam(cr, "Zugstange", apex, L(0, 57, -44), 0.25, STEEL, "Metal", deco=True)
    lib.beam(cr, "Zugstange", apex, L(0, 54.4, 17.6), 0.25, STEEL, "Metal", deco=True)
    fl = lib.ball(cr, "Flugwarnlicht", (apex[0], 66.55, apex[2]), 1.2, RED_NEON, "Neon", deco=True)
    set_attrs(fl, {"Anim": "beacon", "Period": 1.0, "Aviation": True})
    # Laufkatze, Seil, Magnet mit orangem Rand und hängendem Wrack
    box(cr, "Trolley", -2, 2, 52.6, 53.6, -trolley_r - 1.5, -trolley_r + 1.5, (60, 66, 72))
    box(cr, "Cable", -0.15, 0.15, 47.5, 52.6, -trolley_r - 0.15, -trolley_r + 0.15, (30, 30, 32), deco=True)
    mc = L(0, 46.75, -trolley_r)
    lib.cylinder(cr, "Magnet", mc, 1.5, 6, "Y", (40, 40, 44), "Metal")
    lib.cylinder(cr, "MagnetRim", mc, 0.5, 6.4, "Y", (230, 110, 30), "Metal", deco=True)
    spec = wreck_spec(lib, "compact", flat=True, tires=("RL",), bumper=False)
    pose = F * CF(0, 0, -trolley_r) * CF.yaw(90)
    place_wreck(lib, cr, spec, pose, WRECK_COLORS[0], name="Wreck", top=45.98, collide=False)


# ---------------------------------------------------------------- Schrotthaufen
def build_piles(dm, lib, rng):
    m = lib.model(dm, "Schrotthaufen")
    bodies = ["wagon", "sedan", "compact", "hot_hatch", "crossover", "sedan", "compact"]
    ci = 0
    for n, (px, pz) in enumerate(PILES_CRANE + PILES_STATIC):
        crane = n < 3
        hm = lib.model(m, "Haufen_%d" % (n + 1), attrs={"Crane": crane})
        pad = lib.box(hm, "Schotter", px - 12, px + 12, -1.2, Y_PAD, pz - 12, pz + 12, GRAVEL, "Pebble")
        sup = Support(Y_DIRT)
        sup.add(pad)
        sup_c = Support(Y_DIRT)
        sup_c.add(pad)
        a = rng.uniform(-20, 20)
        # zwei Wracks unten nebeneinander (eins intakt, eins platt), eins quer obenauf gekippt
        lay = [(-5.4, "intact"), (5.4, "flat")] if n % 2 == 0 else [(-5.4, "flat"), (5.4, "intact")]
        if not crane:
            lay = [(0.0, "intact")]
        for dxl, kind in lay:
            body = bodies[ci % len(bodies)]
            ci += 1
            spec = wreck_spec(lib, body, flat=(kind == "flat"),
                              tires=(("FL", "RR") if kind == "intact" else ()),
                              hood=(0 if kind == "flat" else rng.choice((0, 30))))
            ox = dxl * math.cos(math.radians(a))
            oz = -dxl * math.sin(math.radians(a))
            pose = CF(px + ox, 0, pz + oz) * CF.angles(0, math.radians(a + rng.uniform(-3, 3)),
                                                      math.radians(rng.uniform(-2, 2)))
            place_wreck(lib, hm, spec, pose, WRECK_COLORS[ci % len(WRECK_COLORS)], support=sup)
        if crane:
            body = bodies[ci % len(bodies)]
            ci += 1
            spec = wreck_spec(lib, body, flat=True, tires=("FR",), bumper=False)
            tilt = rng.uniform(7, 11) * (1 if n % 2 else -1)
            pose = CF(px, 0, pz) * CF.angles(0, math.radians(a + 90 + rng.uniform(-8, 8)), 0) * \
                CF.angles(math.radians(tilt), 0, math.radians(rng.uniform(-4, 4)))
            place_wreck(lib, hm, spec, pose, WRECK_COLORS[ci % len(WRECK_COLORS)], support=sup)
        # Presslinge am Rand
        cubes = [(-12.6, 4), (12.6, -5)] if crane else [(-12.6, -4), (12.6, 3), (12.6, 3)]
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        for i, (lx, lz) in enumerate(cubes):
            dx, dz = lx * ca + lz * sa, -lx * sa + lz * ca
            s = rng.uniform(3.2, 4.0)
            size = (s, rng.uniform(2.6, 3.4), s * rng.uniform(0.85, 1.15))
            pose = CF(px + dx, 0, pz + dz) * CF.angles(math.radians(rng.uniform(-4, 4)), math.radians(rng.uniform(0, 90)),
                                                      math.radians(rng.uniform(-4, 4)))
            place_block(lib, hm, "Pressling", size, pose, CUBE_COLORS[(n * 3 + i) % len(CUBE_COLORS)],
                        "CorrodedMetal", sup_c)


# ---------------------------------------------------------------- Reifenberg, Container, Flutlicht
def build_yard_props(dm, lib, rng):
    # Reifenberg: 24 Reifen bei (-440,-180) - 3 Stapel und lose, schräg gelehnte Reifen
    rm = lib.model(dm, "Reifenberg")
    n = 0
    for (sx, sz, count) in ((-444, -182.5, 6), (-440.4, -178.2, 7), (-436.2, -182.8, 5)):
        for k in range(count):
            y = Y_DIRT + 0.55 + k * 1.1
            lib.cylinder(rm, "Reifen", (sx + rng.uniform(-0.2, 0.2), y, sz + rng.uniform(-0.2, 0.2)), 1.1, 3.2, "Y",
                         RUBBER, "SmoothPlastic")
            n += 1
    for (x, z, yaw, lean) in ((-446.5, -176.5, 30, 18), (-433.4, -178, -60, 22), (-439.6, -186.2, 80, 20),
                              (-447.8, -186, 10, 16), (-434.6, -174.4, -20, 24), (-443.4, -173.8, 55, 19)):
        # stehender, angelehnter Reifen (Achse horizontal)
        cf = CF(x, Y_DIRT + 1.62, z) * CF.angles(0, math.radians(yaw), math.radians(lean))
        lib.part(rm, "Reifen", (1.1, 3.2, 3.2), cf, RUBBER, "SmoothPlastic", shape="Cylinder")
        n += 1
    assert n == 24
    # Container am Nordzaun (Z -355), X -360..-180
    cm = lib.model(dm, "Container")
    cols = [(140, 70, 40), (47, 110, 140), (60, 110, 70), (150, 40, 40), (104, 110, 114)]
    for i, xc in enumerate((-350, -316, -282, -248, -200)):
        x0, x1 = xc - 10, xc + 10
        body = lib.box(cm, "Container", x0, x1, Y_DIRT, 7.5, -359, -351, cols[i], "Metal")
        lib.box(cm, "Containertuer", x1, x1 + 0.12, -0.8, 7.3, -358.8, -351.2, tuple(max(0, c - 22) for c in cols[i]),
                "Metal", deco=True)
        if i == 1:
            lib.surface_text(body, "RECYCLING-WERK", face="Back", text_color=WHITE)
        if i == 2:
            top = lib.box(cm, "Container", x0 + 1, x1 + 1, 7.5, 16, -358.6, -350.6, cols[4], "Metal")
            lib.surface_text(top, "ALTMETALL", face="Back", text_color=YELLOW)
    # 2 Flutlichtmasten, 30 hoch
    fm = lib.model(dm, "Flutlicht")
    for (x, z, dx, dz) in ((-300, -270, 0, 1), (-200, -300, -1, 1)):
        lib.box(fm, "Mastfuss", x - 1, x + 1, Y_DIRT, 0, z - 1, z + 1, CONCRETE_DARK, "Concrete")
        lib.cylinder(fm, "Mast", (x, 15, z), 30, 0.8, "Y", STEEL, "Metal")
        yaw = yaw_towards(dx, dz)
        lib.part(fm, "Traverse", (5, 0.4, 0.6), CF.at(x, 30.2, z, yaw), STEEL, "Metal")
        for s in (-1.4, 1.4):
            hd = CF.at(x, 30.2, z, yaw) * CF(s, -0.6, -0.6) * CF.angles(math.radians(-35), 0, 0)
            head = lib.part(fm, "Scheinwerfer", (2.0, 0.9, 1.4), hd, (224, 231, 230), "SmoothPlastic", deco=True)
            set_attrs(head, {"NightNeon": True})
            if s < 0:
                lib.point_light(head, 50, 1.2, (255, 236, 205), name="FlutLicht")


# ---------------------------------------------------------------- Zerlegeplatz
def build_zerlegeplatz(dm, lib):
    m = lib.model(dm, "Zerlegeplatz")
    x0, x1, z0, z1 = -286, -238, -188, -164
    lib.box(m, "Boden", x0, x1, Y_DIRT, 0, z0, z1, CONCRETE, "Concrete")
    for x in (-285.5, -262, -238.5):
        for zc in (-187.5, -164.5):
            lib.box(m, "Stuetze", x - 0.5, x + 0.5, 0, 24, zc - 0.5, zc + 0.5, YELLOW, "Metal")
    lib.box(m, "Dach", x0 - 1, x1 + 1, 24, 25, z0 - 1, z1 + 1, CORR, "Metal")
    lib.box(m, "Blende", x0 - 1, x1 + 1, 21.5, 24, z0 - 1, z0, RUST, "CorrodedMetal")
    lib.sign(m, "ZERLEGEPLATZ", (22, 2.2), CF.at(-262, 22.75, z0 - 1.12, 180), AMBER, SLATE, name="Schild",
             sub="Teile ausbauen · Ersatzteile · Recycling", sub_color=WHITE)
    for a, b in ((-285, -262.5), (-261.5, -239)):
        lib.box(m, "Rueckwand", a, b, 0, 12, -164.9, -164.1, (48, 54, 61), "Metal")
    # Werkzeugwand und Werkbank
    lib.box(m, "Lochwand", -284, -266, 4.5, 10.5, -165.05, -164.9, (181, 153, 112), "Wood", deco=True)
    for i, (x, h) in enumerate(((-281.5, 3.4), (-278.5, 2.2), (-275, 3.0), (-271.5, 1.8))):
        lib.box(m, "Werkzeug", x - 0.15, x + 0.15, 9.8 - h, 9.8, -165.12, -165.05, STEEL if i % 2 else (200, 60, 50),
                "Metal", deco=True)
    lib.box(m, "Werkbank", -284, -268, 0, 3, -167, -165, SLATE, "Metal")
    lib.box(m, "Werkbankplatte", -284.3, -267.7, 3, 3.3, -167.6, -164.95, (130, 90, 60), "Wood")
    # Bodenmarkierung Arbeitsplatz
    for z in (-182, -170):
        lib.box(m, "Platzlinie", -275, -249, 0, 0.02, z - 0.2, z + 0.2, YELLOW, "SmoothPlastic", deco=True)
    # Vorlagen-Kombi, verblasst, auf 4 Unterstellböcken, Haube offen, Rad vorn links fehlt
    root = (-262, 1.5, -176)
    car = lib.clone_car(m, "wagon", CF.at(root[0], root[1], root[2], 90), (120, 110, 95), name="Zerlegewagen",
                        hide=("WheelFL",), attrs={"Display": "Zerlegeplatz"})
    rcf = CF.at(root[0], root[1], root[2], 90)
    hood = child(car, "Hood")
    if hood is not None:
        write_cf(hood, rcf * CF(0, 3.9, -3.55) * CF.angles(math.radians(65), 0, 0) * CF(0, 0, -1.95))
    chassis_bottom = root[1] + 1.65 - 0.225
    for lx in (-2.6, 2.6):
        for lz in (-3.0, 5.0):
            w = rcf.point((lx, 0, lz))
            lib.box(m, "Unterstellbock", w[0] - 0.35, w[0] + 0.35, 0, chassis_bottom, w[2] - 0.3, w[2] + 0.3, (200, 60, 50),
                    "Metal")
    # abgebautes Rad liegt flach neben dem Auto
    lib.cylinder(m, "Rad_ab", (-270, 0.5, -168.5), 1.0, 2.6, "Y", RUBBER, "SmoothPlastic")
    lib.cylinder(m, "Felge_ab", (-270, 0.51, -168.5), 1.0, 1.9, "Y", (97, 112, 124), "Metal")
    # Motorkran mit hängendem Motorblock
    hx, hz = -279.5, -176
    lib.box(m, "Motorkran_Fuss", hx - 0.3, hx + 7, 0, 0.5, hz - 2.6, hz - 2.1, (200, 60, 50), "Metal")
    lib.box(m, "Motorkran_Fuss", hx - 0.3, hx + 7, 0, 0.5, hz + 2.1, hz + 2.6, (200, 60, 50), "Metal")
    lib.box(m, "Motorkran_Saeule", hx - 1, hx - 0.3, 0, 9, hz - 0.35, hz + 0.35, (200, 60, 50), "Metal")
    lib.beam(m, "Motorkran_Arm", (hx - 0.65, 8.6, hz), (hx + 5.5, 7.4, hz), 0.5, (200, 60, 50), "Metal")
    lib.box(m, "Motorkran_Kette", hx + 5.35, hx + 5.55, 4.6, 7.2, hz - 0.1, hz + 0.1, STEEL, "Metal", deco=True)
    lib.box(m, "Motorblock", hx + 4.1, hx + 6.8, 2.6, 4.6, hz - 1.1, hz + 1.1, (86, 91, 96), "Metal")
    # Sortierbehälter (Beschriftung nach Norden zum Weg)
    for i, (x, txt, col) in enumerate(((-256, "STAHL", CORR), (-251.6, "ALU", (150, 160, 170)),
                                       (-247.2, "KABEL", YELLOW))):
        b = lib.box(m, "Behaelter", x - 2, x + 2, 0, 3, -168.5, -165.5, col, "Metal")
        lib.surface_text(b, txt, face="Front", text_color=BLACK if i == 2 else WHITE)
