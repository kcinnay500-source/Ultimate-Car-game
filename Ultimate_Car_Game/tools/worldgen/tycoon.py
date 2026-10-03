"""Tycoon-Gelände "Tycoon" (PHASE4_CONTRACT §1, §8): Workspace.Tycoon ab Z +700.

Gelände X -220..220, Z 700..1000: zwei Reihen à 4 Grundstücke 70 x 70 (Reihe A bei Z 760 mit Blick nach Süden,
Reihe B bei Z 940 mit Blick nach Norden), dazwischen eine Straßenschleife (Asphalt) um den Marktplatz in der Mitte
(Handelstafel, Infostand, Neonbogen, Fahnen, Laternen).

Hierarchie (alles unter Workspace.Tycoon, Model mit Attribut Zone="tycoon"):
  Ground, Roads, Lights, Plots.Slot_1..8, Markt, Stations.<key>, Arrivals.<key>, Animated, TycoonSpawn
  Plots.Slot_n (Model, Attribute Slot, X, Z, Rot = Pivot wie C.PlotSlots; Rot 0 = Front nach Süden (+Z),
    180 = Front nach Norden; GameConfig.Tycoon.Slots übernimmt diese Werte - siehe SLOTS unten):
    Base        Part 70 x 1 x 70, Oberseite Y 0
    Sign        Model (Anim=pylon, Slot, Owner=""): Body mit SurfaceGui StreetGui (Number/Owner/Street) und PlotGui
                (Welcome) wie die Hausnummer-Pylonen der Stadt (CityService/World setzen Owner/Welcome)
    StartPad    Part (Attribut TycoonSlot=n, ProximityPrompt "Durchlauf starten"), plotlokal (18, 0.5, 28) nahe
                der Straße neben dem Stufen-Pad der Vorlagen (29, 29)
    CollectPad  Part (Attribut TycoonPad="collect", ProximityPrompt "Sammeln"), plotlokal (-20, 0.5, 20) - genau
                unter der CashDisplay der Stufenvorlagen (tycoon_templates.CASH_DISPLAY = (-20, 3, 20))
    Anchor      unsichtbares Part (Pivot der Stufenmodelle ServerStorage.TycoonTemplates.<typ>.Stage_n, Meilenstein 4):
                CFrame = CFrame.new(X, 0.5, Z) * CFrame.Angles(0, rad(Rot), 0), Unterseite auf Y 0
                (die Vorlagen werden von tycoon_templates.build in ServerStorage gebaut, siehe dort)
    ButtonsRoot Folder (Kaufpads TycoonButton=<upgradeId> legt der TycoonService hier ab)
  Stations (contract.build_station): tycoon_market (MiniTab="tycoon", "Marktplatz · Handel", Anker (0,3,830),
    Spielerseite S) und tycoon (MiniTab="tycoon", "Infostand · Tycoon", Anker (-32,3,862), Spielerseite E)
  Arrivals: hub (0,-0.45,856) Blick N.  TycoonSpawn: SpawnLocation bei (0,-0.35,850), Enabled=false.
  Animated: Neonbogen (neon), Fahne_1..4 (flag) - ein TycoonClient/LobbyClient hängt Tycoon.Animated wie
  City.Animated an (CityClient hört heute nur auf Workspace.City).

Höhen (§1.2): Gras -1.0 | Asphalt -0.95 | Markierungen -0.90 | Gehwege/Platz -0.5 | Markt-Inlay -0.45
  | Grundstück (Base) 0 | Plot-Kanten 0.15 | Pads 0.5.
Budget: <= 2500 Parts, <= 20 Lichter (TYCOON_BUDGET).
"""
from . import tycoon_templates
from .contract import build_arrival, build_station
from .lib import (CF, AMBER, ASPHALT, BLACK, FRAME, GRASS, HEDGE, PLAZA, PLAZA_BAND, SIDEWALK, SLATE, STEEL, TEAL,
                  WHITE, YARD, Color3, set_attrs)
from .plots import loc2world

NAME = "Tycoon"
TYCOON_BUDGET = (2500, 20)         # Parts, Lichter

# Slot, Pivot x, z, rot (Reihe A Z 760 Front Süd, Reihe B Z 940 Front Nord) - Vergabe = Listenreihenfolge
SLOTS = [
    (1, -45, 760, 0),
    (2, 45, 760, 0),
    (3, -45, 940, 180),
    (4, 45, 940, 180),
    (5, -135, 760, 0),
    (6, 135, 760, 0),
    (7, -135, 940, 180),
    (8, 135, 940, 180),
]
HALF = 35.0
START_PAD = (18.0, 28.0)           # plotlokal (x, z), Straßenseite (+Z)
COLLECT_PAD = (-20.0, 20.0)        # unter tycoon_templates.CASH_DISPLAY
SIGN_LZ = 39.5                     # Pylon auf dem Gehweg vor dem Grundstück

# Straßenschleife und Marktplatz
ZX0, ZX1, ZZ0, ZZ1 = -220.0, 220.0, 700.0, 1000.0      # Gras
RX0, RX1 = -190.0, 190.0
ROAD_N = (807.0, 821.0)
ROAD_S = (879.0, 893.0)
WALK_N = (795.0, 807.0)
WALK_S = (893.0, 905.0)
LEG_W = 14.0
INNER = (RX0 + LEG_W, RX1 - LEG_W, ROAD_N[1], ROAD_S[0])        # Innenfläche X -176..176, Z 821..879 (Gras)
WALK_IN = 6.0                                                 # Gehweg innen entlang der Schleife
PLAZA_RECT = (-80.0, 80.0, INNER[2] + WALK_IN, INNER[3] - WALK_IN)   # Marktplatz-Pflaster X -80..80, Z 827..873
MARKET = (-50.0, 50.0, 835.0, 865.0)                          # Inlay -0.45
GREEN = (90, 180, 90)
PAD_TXT = SLATE

STATIONS = {
    "tycoon_market": ("Marktplatz · Handel", (0.0, 3.0, 830.0), "S", -0.45),
    "tycoon": ("Infostand · Tycoon", (-32.0, 3.0, 862.0), "E", -0.45),
}
ARRIVALS = {"hub": (0.0, -0.45, 856.0, "N")}
SPAWN = (0.0, -0.35, 850.0)


def _box(lib, parent, name, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
    return lib.box(parent, name, min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1),
                   color, material, **kw)


def _c3(rgb):
    return Color3(*rgb)


def slot_cf(px, pz, rot):
    return CF.at(px, 0, pz, rot)


# ---------------------------------------------------------------- Boden, Straße, Platz
def build_ground(lib, root):
    g = lib.folder(root, "Ground")
    with lib.section("Tycoon: Boden"):
        _box(lib, g, "Grasplatte", ZX0, ZX1, -5.0, -1.0, ZZ0, ZZ1, GRASS, "Grass")
        _box(lib, g, "Gehweg_N", RX0, RX1, -1.25, -0.5, WALK_N[0], WALK_N[1], SIDEWALK, "Concrete")
        _box(lib, g, "Gehweg_S", RX0, RX1, -1.25, -0.5, WALK_S[0], WALK_S[1], SIDEWALK, "Concrete")
        _box(lib, g, "Gehweg_W", RX0 - 10, RX0, -1.25, -0.5, WALK_N[0], WALK_S[1], SIDEWALK, "Concrete")
        _box(lib, g, "Gehweg_O", RX1, RX1 + 10, -1.25, -0.5, WALK_N[0], WALK_S[1], SIDEWALK, "Concrete")
        ix0, ix1, iz0, iz1 = INNER
        _box(lib, g, "Gehweg_innen_N", ix0, ix1, -1.25, -0.5, iz0, iz0 + WALK_IN, SIDEWALK, "Concrete")
        _box(lib, g, "Gehweg_innen_S", ix0, ix1, -1.25, -0.5, iz1 - WALK_IN, iz1, SIDEWALK, "Concrete")
        _box(lib, g, "Gehweg_innen_W", ix0, ix0 + WALK_IN, -1.25, -0.5, iz0 + WALK_IN, iz1 - WALK_IN, SIDEWALK,
             "Concrete")
        _box(lib, g, "Gehweg_innen_O", ix1 - WALK_IN, ix1, -1.25, -0.5, iz0 + WALK_IN, iz1 - WALK_IN, SIDEWALK,
             "Concrete")
        x0, x1, z0, z1 = PLAZA_RECT
        _box(lib, g, "Platz", x0, x1, -1.25, -0.5, z0, z1, PLAZA, "Concrete")
        # Rasen innen: Bäume und Wege zum Platz
        for x in (-110, -140, 110, 140):
            for z in (838, 862):
                lib.tree_lite(g, x, -1.0, z, scale=1.0, seed=int(abs(x) + z) % 7, name="Baum")
        for sx in (-1, 1):
            _box(lib, g, "Weg", sx * 80, sx * 170, -1.25, -0.5, 847, 853, SIDEWALK, "Concrete")
        mx0, mx1, mz0, mz1 = MARKET
        _box(lib, g, "Markt_Inlay", mx0, mx1, -0.5, -0.45, mz0, mz1, PLAZA_BAND, "Concrete")
        # Bäume in den Grasecken
        k = 0
        for x in (-205, 205):
            for z in (720, 760, 940, 980):
                lib.tree_lite(g, x, -1.0, z, scale=1.1, seed=k, name="Baum")
                k += 1
    return g


def build_roads(lib, root):
    r = lib.folder(root, "Roads")
    with lib.section("Tycoon: Straße"):
        _box(lib, r, "Fahrbahn_N", RX0, RX1, -1.25, -0.95, ROAD_N[0], ROAD_N[1], ASPHALT, "Asphalt")
        _box(lib, r, "Fahrbahn_S", RX0, RX1, -1.25, -0.95, ROAD_S[0], ROAD_S[1], ASPHALT, "Asphalt")
        _box(lib, r, "Fahrbahn_W", RX0, RX0 + LEG_W, -1.25, -0.95, ROAD_N[1], ROAD_S[0], ASPHALT, "Asphalt")
        _box(lib, r, "Fahrbahn_O", RX1 - LEG_W, RX1, -1.25, -0.95, ROAD_N[1], ROAD_S[0], ASPHALT, "Asphalt")
        marks = lib.folder(r, "Markierungen")
        for zc in ((ROAD_N[0] + ROAD_N[1]) / 2, (ROAD_S[0] + ROAD_S[1]) / 2):
            x = RX0 + LEG_W + 4
            while x + 4 <= RX1 - LEG_W - 4:
                _box(lib, marks, "Mittelstrich", x, x + 4, -0.95, -0.90, zc - 0.25, zc + 0.25, AMBER,
                     "SmoothPlastic", deco=True)
                x += 8
        for xc in (RX0 + LEG_W / 2, RX1 - LEG_W / 2):
            z = ROAD_N[1] + 4
            while z + 4 <= ROAD_S[0] - 4:
                _box(lib, marks, "Mittelstrich", xc - 0.25, xc + 0.25, -0.95, -0.90, z, z + 4, AMBER,
                     "SmoothPlastic", deco=True)
                z += 8
    return r


def build_lights(lib, root):
    lights = lib.folder(root, "Lights")
    with lib.section("Tycoon: Licht"):
        for x in (-150, -60, 60, 150):
            lib.street_lamp(lights, x, WALK_N[0] + 6, -0.5, 0, 1)
            lib.street_lamp(lights, x, WALK_S[1] - 6, -0.5, 0, -1)
        for x in (-44, 44):
            for z, dz in ((828, 1), (872, -1)):
                lib.street_lamp(lights, x, z, -0.5, 0, dz, name="Platzlaterne")
    return lights


# ---------------------------------------------------------------- Grundstücke
def build_pylon(lib, parent, slot, x, z, yaw):
    pyl = lib.model(parent, "Sign", attrs={"Anim": "pylon", "Slot": slot, "Owner": ""})
    body = lib.part(pyl, "Body", (4.5, 12, 1.2), CF.at(x, 5.5, z, yaw), SLATE, "Metal")
    lib.set_primary(pyl, body)
    gui = lib.surface_text(body, None, face="Back", name="StreetGui", canvas=(180, 480))
    lib.text_label(gui, str(slot), AMBER, "GothamBlack", "Number", None, (0.9, 0.5), (0.05, 0.04))
    lib.text_label(gui, "FREI", WHITE, "GothamBold", "Owner", None, (0.9, 0.16), (0.05, 0.58))
    lib.text_label(gui, "TYCOON", TEAL, "GothamBold", "Street", None, (0.9, 0.08), (0.05, 0.82))
    gui2 = lib.surface_text(body, None, face="Front", name="PlotGui", canvas=(180, 480))
    lib.text_label(gui2, "FREI – Grundstück %d" % slot, AMBER, "GothamBold", "Welcome", None, (0.9, 0.4),
                   (0.05, 0.3))
    cap = lib.part(pyl, "Cap", (4.7, 0.5, 1.4), CF.at(x, 11.75, z, yaw), AMBER, "Neon", deco=True)
    set_attrs(cap, {"FreeColor": _c3(AMBER), "OwnedColor": _c3(TEAL)})
    lib.part(pyl, "Plinth", (5.3, 0.6, 2.0), CF.at(x, -0.2, z, yaw), STEEL, "Metal")
    return pyl


def build_pad(lib, parent, name, wx, wz, yaw, color, label, attrs, action, obj):
    pad = lib.part(parent, name, (8, 0.5, 8), CF.at(wx, 0.25, wz, yaw), color, "SmoothPlastic", attrs=attrs)
    gui = lib.surface_text(pad, label, face="Top", text_color=PAD_TXT, font="GothamBlack", name="PadGui")
    lib.prompt(pad, action, obj)
    return pad, gui


def build_slot(lib, root, slot, px, pz, rot):
    m = lib.model(root, "Slot_%d" % slot, attrs={"Slot": slot, "X": px, "Z": pz, "Rot": rot})
    base = lib.box(m, "Base", px - HALF, px + HALF, -1.0, 0.0, pz - HALF, pz + HALF, YARD, "Concrete")
    lib.set_primary(m, base)
    # Kanten (0.15) rundum und Hecke an der Rückseite
    for nm, x0, x1, z0, z1 in (("Kante_W", px - HALF, px - HALF + 0.6, pz - HALF, pz + HALF),
                               ("Kante_O", px + HALF - 0.6, px + HALF, pz - HALF, pz + HALF),
                               ("Kante_N", px - HALF + 0.6, px + HALF - 0.6, pz - HALF, pz - HALF + 0.6),
                               ("Kante_S", px - HALF + 0.6, px + HALF - 0.6, pz + HALF - 0.6, pz + HALF)):
        _box(lib, m, nm, x0, x1, 0.0, 0.15, z0, z1, FRAME, "Metal", deco=True)
    hx0, hz = loc2world(px, pz, rot, -HALF, -HALF - 1.5)
    _box(lib, m, "Hecke", hx0, hx0 + (HALF * 2 if rot == 0 else -HALF * 2), -1.0, 1.6, hz - 0.75, hz + 0.75,
         HEDGE, "Grass", deco=True)
    # Pads (Start amber, Sammeln grün) mit Prompt
    sx, sz = loc2world(px, pz, rot, START_PAD[0], START_PAD[1])
    build_pad(lib, m, "StartPad", sx, sz, rot, AMBER, "START", {"TycoonSlot": slot}, "Durchlauf starten",
              "Grundstück %d" % slot)
    cx, cz = loc2world(px, pz, rot, COLLECT_PAD[0], COLLECT_PAD[1])
    build_pad(lib, m, "CollectPad", cx, cz, rot, GREEN, "SAMMELN", {"TycoonPad": "collect"}, "Sammeln", "Bargeld")
    # Anker (Pivot der Stufenmodelle), unsichtbar, Unterseite auf Y 0
    lib.part(m, "Anchor", (1, 1, 1), CF.at(px, 0.5, pz, rot), TEAL, "SmoothPlastic", transparency=1,
             collide=False, touch=False, query=False, cast_shadow=False, attrs={"Slot": slot, "Rot": rot})
    lib.folder(m, "ButtonsRoot")
    # Pylon auf dem Gehweg
    gx, gz = loc2world(px, pz, rot, 0, SIGN_LZ)
    build_pylon(lib, m, slot, gx, gz, rot)
    return m


def build_plots(lib, root):
    plots = lib.folder(root, "Plots")
    with lib.section("Tycoon: Grundstücke"):
        for slot, px, pz, rot in SLOTS:
            build_slot(lib, plots, slot, px, pz, rot)
    return plots


# ---------------------------------------------------------------- Marktplatz
def flag_pole(lib, parent, name, x, fy, z, cloth, stripe, text, h=17.0):
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


def build_market(lib, root, anim):
    m = lib.model(root, "Markt")
    with lib.section("Tycoon: Marktplatz"):
        # Handelstafel (Text nach Süden) auf 2 Pfosten
        for x in (-7, 7):
            _box(lib, m, "Tafelpfosten", x - 0.3, x + 0.3, -0.5, 7.6, 829.7, 830.3, STEEL, "Metal")
        board = _box(lib, m, "Tafel", -8.5, 8.5, 2.0, 8.0, 829.6, 830.0, BLACK, "SmoothPlastic")
        g = lib.surface_text(board, None, face="Back", name="MarketScreen")
        lib.text_label(g, "MARKTPLATZ · HANDEL", AMBER, "GothamBlack", "Title", None, (0.94, 0.26), (0.03, 0.04))
        lib.text_label(g, "Angebote der Spieler (Bargeld): noch keine", WHITE, "GothamBold", "Offers", None,
                       (0.9, 0.5), (0.05, 0.36))
        lib.text_label(g, "Tauschen · Kaufen · Verkaufen – nur im Tycoon", TEAL, "GothamBold", "Hint",
                       None, (0.9, 0.12), (0.05, 0.86))
        _box(lib, m, "Tafeldach", -9, 9, 8.0, 8.4, 829.2, 830.8, AMBER, "Neon", deco=True)
        # Infostand (Säule + Bildschirm nach Osten)
        kx, kz = -34.0, 862.0
        lib.cylinder(m, "Infosaeule", (kx, 1.3, kz), 3.6, 1.2, "Y", STEEL, "Metal")
        scr = _box(lib, m, "Infoschirm", kx - 0.3, kx + 0.3, 3.1, 7.1, kz - 3, kz + 3, BLACK, "SmoothPlastic")
        g = lib.surface_text(scr, None, face="Right", name="Screen")
        lib.text_label(g, "TYCOON", AMBER, "GothamBlack", "Title", None, (0.94, 0.34), (0.03, 0.05))
        lib.text_label(g, "Grundstück wählen · Gebäude bauen · Stufe 5 · Rebirth", WHITE, "GothamBold", "Lines",
                       None, (0.9, 0.45), (0.05, 0.45))
        _box(lib, m, "Infodach", kx - 0.4, kx + 0.4, 7.1, 7.4, kz - 3.2, kz + 3.2, AMBER, "Neon", deco=True)
        # Bänke am Inlay-Rand
        for x in (-40, 40):
            for z in (837.5, 862.5):
                _box(lib, m, "Bankfuss", x - 2.5, x + 2.5, -0.45, -0.05, z - 0.6, z + 0.6, SLATE, "Metal")
                _box(lib, m, "Banksitz", x - 3, x + 3, -0.05, 0.35, z - 1.2, z + 1.2, (130, 90, 60), "Wood")
        # Neonbogen "TYCOON" am Südrand des Platzes (Text beidseitig), Anim neon
        am = lib.model(anim, "Neonbogen", attrs={"Anim": "neon", "Period": 3.2, "ColorB": _c3(TEAL)})
        ax, az = 0, 874
        for sx in (-1, 1):
            x = ax + sx * 15.5
            _box(lib, am, "Bogenpfosten", x - 0.75, x + 0.75, -0.5, 19, az - 0.75, az + 0.75, SLATE, "Metal")
            _box(lib, am, "Neonroehre", x - 0.15, x + 0.15, 0.0, 17.5, az + 0.75, az + 1.05, AMBER, "Neon", deco=True)
        _box(lib, am, "Bogentraeger", ax - 16.25, ax + 16.25, 19, 22, az - 0.75, az + 0.75, SLATE, "Metal")
        _box(lib, am, "Neonroehre", ax - 14.5, ax + 14.5, 18.7, 19.0, az + 0.75, az + 1.05, AMBER, "Neon", deco=True)
        lib.sign(am, "TYCOON", (28, 2.6), CF.at(ax, 20.5, az + 0.85, 0), AMBER, SLATE, name="Bogenschild",
                 bolts=False)
        lib.sign(am, "TYCOON", (28, 2.6), CF.at(ax, 20.5, az - 0.85, 180), AMBER, SLATE, name="Bogenschild",
                 bolts=False)
        # Fahnen an den Platzecken (Anim flag)
        k = 0
        for x in (-58, 58):
            for z in (826, 874):
                k += 1
                col, stripe = (AMBER, SLATE) if k % 2 else (TEAL, WHITE)
                flag_pole(lib, anim, "Fahne_%d" % k, x, -0.5, z, col, stripe, "TYCOON")
    return m


# ---------------------------------------------------------------- Aufbau
def build(workspace, lib, tree):
    root = lib.model(workspace, NAME, attrs={"Zone": "tycoon", "Version": "3.0"})
    for nm in ("Ground", "Roads", "Lights", "Plots", "Stations", "Arrivals", "Animated"):
        lib.folder(root, nm)
    anim = lib.folder(root, "Animated")
    build_ground(lib, root)
    build_roads(lib, root)
    build_lights(lib, root)
    build_plots(lib, root)
    build_market(lib, root, anim)
    st = lib.folder(root, "Stations")
    ar = lib.folder(root, "Arrivals")
    with lib.section("Tycoon: Stationen & Ankunft (unsichtbar)"):
        for key, (title, pos, side, floor) in STATIONS.items():
            build_station(lib, st, key, "tycoon", title, pos, side, floor)
        for key, (x, fy, z, look) in ARRIVALS.items():
            build_arrival(lib, ar, key, x, fy, z, look)
        lib.spawn(root, "TycoonSpawn", (10, 0.2, 10), CF.at(SPAWN[0], SPAWN[1], SPAWN[2], 0), enabled=False)
    # Stufen-Vorlagen ServerStorage.TycoonTemplates (nicht Teil des Zonen-Budgets)
    tycoon_templates.build(tree, lib)
    return root
