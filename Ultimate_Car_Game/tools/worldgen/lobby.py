"""Lobby-Halle (PHASE4_CONTRACT §1, §5): Workspace.Lobby bei Z -700, Boden Y 0, im Stil der Ankunftshalle (CITY_SPEC D2).

Halle 120 x 80 (X -60..60, Z -740..-660), 24 lichte Höhe (Dachplatte 24..25, Attika bis 28), Glasfront nach Süden
(zur Stadt hin) mit Schiebetüren (Anim door), Vordach, Attika-Schild und Amber-Neonband (Anim neon).
Innen: Drehteller mit Showcar (Anim turntable) in der Mitte, Empfangstresen mit NPC an der Nordwand, davor links das
Portal "TYCOON" (türkis) und rechts das Portal "OPEN WORLD" (amber) - je zwei Pfeiler, Sturz mit Schild,
leuchtende Portalfläche (Anim neon) und Startring am Boden. Einstellungs-Terminal an der Westwand, Party-Tafel an der
Ostwand, Tutorial-Kiosk links neben dem Eingang.

Hierarchie (alles unter Workspace.Lobby, Model mit Attribut Zone="lobby"):
  Ground, Shell, Interior, Lights, Stations.<key>, Arrivals.<key>, Animated, LobbySpawn
  Stations (Vertrag wie City.Stations, contract.build_station): mode_tycoon, mode_openworld, settings, party, tutorial
    - Attribute MiniTab="lobby", MiniTitle, LobbyAction=<key>, PlayerSide; ProximityPrompt "Öffnen"; Attachment Arrival
  Arrivals: hub (0,0,-668) Blick N, portal_tycoon (-38,0,-728) Blick N, portal_openworld (38,0,-728) Blick N
  LobbySpawn: SpawnLocation 10 x 0.2 x 10 bei (0,0.1,-676), Enabled=false (der Server versetzt nach Modus)
  Animated: Tueren (door), Neonband + Portalflächen (neon), Drehteller (turntable) - der Client animiert wie in der
  Stadt (CityClient hört heute nur auf Workspace.City.Animated; LobbyClient/Integrator hängt Lobby.Animated an).

Höhen (§1.2, keine koplanaren Oberseiten): Gras -1.0 | Vorplatz/Sockelplatte -0.5 | Bänder -0.45 | Hallenboden 0
  | Startringe 0.05 | Startring-Inlay 0.10 | Drehscheibe 0.6 (Leuchtring 0.45) | Dachplatte 25 | Attika 28.
Budget: <= 1500 Parts, <= 12 Lichter (LOBBY_BUDGET).
"""
from .contract import build_arrival, build_station
from .lib import (CF, AMBER, BLACK, FRAME, GLASS, GRAPHITE, LAMP, PLAZA, PLAZA_BAND, SLATE, STEEL, TEAL, WHITE,
                  Color3, set_attrs)

NAME = "Lobby"
LOBBY_BUDGET = (1500, 12)          # Parts, Lichter

# Halle
X0, X1 = -60.0, 60.0
Z0, Z1 = -740.0, -660.0            # Z0 = Nordwand, Z1 = Glasfront (Süden, zur Stadt)
CEIL = 24.0                        # lichte Höhe; Dachplatte 24..25, Attika 25..28
WT = 0.8
FLOOR = (200, 204, 208)
WOOD = (130, 90, 60)
SKIN = (222, 184, 150)
GLASS_T = 0.3
PORTALS = {                        # key: (x, Farbe, Titel, Unterzeile)
    "mode_tycoon": (-38.0, TEAL, "TYCOON", "Tycoon-Runde mit Bargeld · Stufe 1–5"),
    "mode_openworld": (38.0, AMBER, "OPEN WORLD", "Spielermeile · Stadt · Minispiele"),
}
PORTAL_Z = -738.0                  # Portalfläche (Anker der Stationen mode_*)

# key: (Titel, Anker (x,y,z), Spielerseite, Bodenhöhe)
STATIONS = {
    "mode_tycoon": ("Tycoon · Portal", (-38.0, 3.0, PORTAL_Z), "S", 0.0),
    "mode_openworld": ("Open World · Portal", (38.0, 3.0, PORTAL_Z), "S", 0.0),
    "settings": ("Einstellungen · Terminal", (-58.0, 3.0, -700.0), "E", 0.0),
    "party": ("Party-Tafel", (58.0, 3.0, -700.0), "W", 0.0),
    "tutorial": ("Tutorial-Kiosk", (-56.5, 3.0, -676.0), "E", 0.0),
}
# key: (x, Bodenhöhe, z, Blick)
ARRIVALS = {
    "hub": (0.0, 0.0, -668.0, "N"),
    "portal_tycoon": (-38.0, 0.0, -728.0, "N"),
    "portal_openworld": (38.0, 0.0, -728.0, "N"),
}
SPAWN = (0.0, 0.1, -676.0)


def _box(lib, parent, name, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
    return lib.box(parent, name, min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1),
                   color, material, **kw)


def _cyl_y(lib, parent, name, x, y0, y1, z, dia, color, material="SmoothPlastic", **kw):
    return lib.cylinder(parent, name, (x, (y0 + y1) / 2, z), abs(y1 - y0), dia, "Y", color, material, **kw)


def door_leaf(lib, parent, nm, center, size, lift, stile_side, door):
    """Schiebeflügel (Anim door, Axis X) wie in der Ankunftshalle: Glas (PrimaryPart), Stiel, Sockelleiste, Griff."""
    m = lib.model(parent, nm, attrs={"Anim": "door", "Axis": "X", "Lift": lift, "Period": 10, "Door": door,
                                     "OpenRange": 12, "OpenTime": 0.6, "Mode": "slide"})
    cx, cy, cz = center
    sx, sy, sz = size
    gl = lib.part(m, "Glas", (sx - 0.1, sy - 0.1, sz), CF(cx, cy, cz), GLASS, "Glass", transparency=GLASS_T + 0.05,
                  collide=False, cast_shadow=False)
    lib.set_primary(m, gl)
    ex = cx + stile_side * (sx / 2 - 0.2)
    lib.part(m, "Stiel", (0.4, sy, sz + 0.12), CF(ex, cy, cz), STEEL, "Metal", collide=False)
    lib.part(m, "Sockelleiste", (sx - 0.4, 0.4, sz + 0.1), CF(cx - stile_side * 0.2, cy - sy / 2 + 0.2, cz),
             STEEL, "Metal", collide=False)
    lib.part(m, "Griff", (0.12, 2.6, sz + 0.24), CF(ex - stile_side * 0.5, cy, cz), BLACK, "Metal", deco=True)
    return m


# ---------------------------------------------------------------- Boden und Hülle
def build_ground(lib, root):
    g = lib.folder(root, "Ground")
    with lib.section("Lobby: Boden"):
        # Grasplatte der Zone (Oberseite -1.0; Sockelplatte und Vorplatz liegen darauf)
        _box(lib, g, "Grasplatte", -100, 100, -5.0, -1.0, -780, -600, (73, 91, 64), "Grass")
        # Baumreihen links und rechts der Halle und am Vorplatz
        k = 0
        for x in (-84, 84):
            for z in (-736, -712, -688, -664, -640, -616):
                lib.tree_lite(g, x, -1.0, z, scale=1.1, seed=k, name="Baum")
                k += 1
        for x in (-50, 50):
            lib.tree_lite(g, x, -1.0, -770, scale=1.2, seed=k, name="Baum")
            k += 1
        # Sockelplatte unter der Halle + Vorplatz bis Z -610 (Platzstein -0.5)
        _box(lib, g, "Vorplatz", -70, 70, -1.25, -0.5, -746, -610, PLAZA, "Concrete")
        # Bänder auf dem Vorplatz (-0.45) als Leitlinie zur Tür
        for x in (-16, 16):
            _box(lib, g, "Band", x - 1, x + 1, -0.5, -0.45, -654, -614, PLAZA_BAND, "Concrete", deco=True)
        _box(lib, g, "Band", -15, 15, -0.5, -0.45, -616, -614, PLAZA_BAND, "Concrete", deco=True)
        # Hallenboden (Platte -1..0 auf der Sockelplatte)
        lib.box(g, "Hallenboden", X0, X1, -1.0, 0.0, Z0, Z1, FLOOR, "SmoothPlastic", reflectance=0.08)
        # Eingangsstufe 1:2-Keil vor der Tür (Boden 0 -> Vorplatz -0.5)
        lib.wedge(g, "Eingangsrampe", (24, 0.5, 2), CF.at(0, -0.25, Z1 + 1.0, 180), PLAZA, "Concrete")
    return g


def build_shell(lib, root, anim):
    sh = lib.model(root, "Shell")
    with lib.section("Lobby: Hülle"):
        # Wände bis zur Dachplatte (24); Nordwand voll, Ost/West mit Glasband Y 9..20
        _box(lib, sh, "Nordwand", X0 - WT, X1 + WT, 0, CEIL, Z0 - WT, Z0, SLATE, "Metal")
        for nm, xa, xb in (("Westwand", X0 - WT, X0), ("Ostwand", X1, X1 + WT)):
            _box(lib, sh, nm + "_unten", xa, xb, 0, 9, Z0, Z1, SLATE, "Metal")
            _box(lib, sh, nm + "_oben", xa, xb, 20, CEIL, Z0, Z1, SLATE, "Metal")
            z = Z0
            while z < Z1 - 0.01:
                _box(lib, sh, nm + "_Glas", xa + 0.2, xb - 0.2, 9, 20, z + 0.4, z + 9.6, GLASS, "Glass",
                     transparency=GLASS_T, collide=True, cast_shadow=False)
                _box(lib, sh, nm + "_Pfosten", xa, xb, 9, 20, z + 9.6, z + 10.4, FRAME, "Metal")
                z += 10
            _box(lib, sh, nm + "_Pfosten", xa, xb, 9, 20, Z0, Z0 + 0.4, FRAME, "Metal")
        # Südfront: Glasvorhang mit Pfosten alle 10, Kämpfer bei 12, Tür X -10..10
        for k in range(13):
            x = X0 + 10 * k
            if x == 0:
                continue        # kein Pfosten in der Türachse (Kamera hinter dem Ankunftspunkt hub)
            _box(lib, sh, "Pfosten", x - 0.4, x + 0.4, 0, CEIL, Z1, Z1 + WT, SLATE, "Metal")
        for k in range(12):
            xa, xb = X0 + 10 * k + 0.4, X0 + 10 * (k + 1) - 0.4
            door_bay = abs((xa + xb) / 2) < 10
            if not door_bay:
                _box(lib, sh, "Glas_unten", xa, xb, 0, 11.8, Z1 + 0.2, Z1 + WT - 0.2, GLASS, "Glass",
                     transparency=GLASS_T, collide=True, cast_shadow=False)
            _box(lib, sh, "Glas_oben", xa, xb, 12.2, CEIL, Z1 + 0.2, Z1 + WT - 0.2, GLASS, "Glass",
                 transparency=GLASS_T, collide=True, cast_shadow=False)
        _box(lib, sh, "Kaempfer", X0, X1, 11.8, 12.2, Z1 + 0.1, Z1 + WT - 0.1, SLATE, "Metal")
        # Türsturz über der Türöffnung (die Türflügel fahren darunter)
        _box(lib, sh, "Tuersturz", -10, 10, 11.8, 12.2, Z1 - 0.3, Z1, STEEL, "Metal")
        # Dachplatte und Attika-Ring (25..28; N/S zwischen den Seiten, W/O über die volle Tiefe)
        _box(lib, sh, "Dachplatte", X0 - WT, X1 + WT, CEIL, CEIL + 1, Z0 - WT, Z1 + WT, GRAPHITE, "Concrete")
        _box(lib, sh, "Attika_N", X0, X1, CEIL + 1, 28, Z0 - WT, Z0, SLATE, "Metal")
        _box(lib, sh, "Attika_S", X0, X1, CEIL + 1, 28, Z1, Z1 + WT, SLATE, "Metal")
        _box(lib, sh, "Attika_W", X0 - WT, X0, CEIL + 1, 28, Z0 - WT, Z1 + WT, SLATE, "Metal")
        _box(lib, sh, "Attika_O", X1, X1 + WT, CEIL + 1, 28, Z0 - WT, Z1 + WT, SLATE, "Metal")
        # Attika-Schild "LOBBY" (Text nach Süden, yaw 0) und Vordach
        lib.sign(sh, "LOBBY", (40, 3.6), CF.at(0, 26.5, Z1 + WT + 0.15, 0), AMBER, SLATE, name="Attikaschild",
                 sub="TYCOON · OPEN WORLD · PARTY", sub_color=WHITE)
        _box(lib, sh, "Vordach", -13, 13, 15.5, 16.5, Z1 + WT, Z1 + WT + 8, GRAPHITE, "Concrete")
        for x in (-11, 11):
            lib.beam(sh, "Vordachstrebe", (x, 22, Z1 + WT), (x, 16.5, Z1 + WT + 7.5), 0.3, STEEL, "Metal", deco=True)
        # Amber-Neonband außen unter der Dachplatte (Anim neon, pulsiert)
        band = lib.model(anim, "Neonband", attrs={"Anim": "neon", "Period": 2.0, "ColorB": Color3(*TEAL)})
        _box(lib, band, "Neonleiste", -58, 58, 23.0, 23.4, Z1 + WT, Z1 + WT + 0.3, AMBER, "Neon", deco=True)
        # Schiebetüren (zwei Flügel, 10 x 12) innen vor dem Kämpfer
        doors = lib.folder(anim, "Tueren")
        door_leaf(lib, doors, "Eingangstuer_W", (-5, 6, Z1 - 0.35), (10, 12, 0.3), -10.0, 1, "Lobby")
        door_leaf(lib, doors, "Eingangstuer_O", (5, 6, Z1 - 0.35), (10, 12, 0.3), 10.0, -1, "Lobby")
    return sh


# ---------------------------------------------------------------- Innenausbau
def build_portal(lib, parent, anim, key, x, color, title, sub):
    m = lib.model(parent, "Portal_" + key)
    zf, zb = PORTAL_Z + 0.8, PORTAL_Z - 1.2          # Pfeiler Z -737.2 .. -739.2 (an der Nordwand)
    for sx in (-1, 1):
        _box(lib, m, "Pfeiler", x + sx * 8, x + sx * 6, 0, 16, zb, zf, SLATE, "Metal")
        _box(lib, m, "Pfeilerkante", x + sx * 8.1, x + sx * 7.9, 0.5, 15.5, zf, zf + 0.15, color, "Neon", deco=True)
    _box(lib, m, "Sturz", x - 8, x + 8, 16, 19, zb, zf, SLATE, "Metal")
    lib.sign(m, title, (14, 2.4), CF.at(x, 17.5, zf + 0.12, 0), color, SLATE, name="Portalschild", bolts=False,
             sub=sub, sub_color=WHITE)
    # große Wandschrift über dem Portal
    lib.sign(m, title, (16, 3), CF.at(x, 21.5, Z0 + 0.12, 0), color, SLATE, name="Wandschrift", bolts=False)
    # leuchtende Portalfläche (Anim neon) zwischen den Pfeilern
    pl = lib.model(anim, "Portalflaeche_" + key, attrs={"Anim": "neon", "Period": 2.4, "ColorB": Color3(*WHITE)})
    face = _box(lib, pl, "Flaeche", x - 6, x + 6, 0.5, 15.5, PORTAL_Z - 0.15, PORTAL_Z + 0.15, color, "Neon",
                transparency=0.35, deco=True)
    lib.point_light(face, 22, 1.2, color, name="Portallicht")
    # Startring am Boden (0.05) mit Inlay (0.10)
    lib.cylinder(m, "Startring", (x, 0.025, PORTAL_Z + 7), 0.05, 12, "Y", color, "Neon", deco=True)
    lib.cylinder(m, "Startinlay", (x, 0.05, PORTAL_Z + 7), 0.1, 9, "Y", FLOOR, "SmoothPlastic", deco=True)
    return m


def build_reception(lib, parent):
    m = lib.model(parent, "Empfang")
    dz0, dz1 = -732, -729
    _box(lib, m, "Tresenkorpus", -12, 12, 0, 3.2, dz0, dz1, SLATE, "Metal")
    _box(lib, m, "Tresenplatte", -12.4, 12.4, 3.2, 3.5, dz0 - 0.4, dz1 + 0.4, WOOD, "Wood")
    _box(lib, m, "Neonleiste", -11.5, 11.5, 0.3, 0.5, dz1, dz1 + 0.1, AMBER, "Neon", deco=True)
    lib.sign(m, "EMPFANG · INFO", (8, 1.2), CF.at(0, 2.1, dz1 + 0.06, 0), AMBER, SLATE, name="Tresenschild",
             bolts=False, thickness=0.1)
    # NPC (7 Teile, Amber-Weste) hinter dem Tresen
    fig = lib.model(m, "Empfang_NPC")
    px, pz = 0, -734.5
    _box(lib, fig, "Beine", px - 0.8, px + 0.8, 0, 2.8, pz - 0.4, pz + 0.4, (40, 45, 55), "SmoothPlastic")
    _box(lib, fig, "Hemd", px - 0.9, px + 0.9, 2.8, 4.8, pz - 0.45, pz + 0.45, WHITE, "SmoothPlastic")
    _box(lib, fig, "Weste", px - 0.95, px + 0.95, 3.0, 4.6, pz - 0.5, pz + 0.5, AMBER, "SmoothPlastic", deco=True)
    for s in (-1, 1):
        _box(lib, fig, "Arm", px + s * 0.9, px + s * 1.4, 2.9, 4.8, pz - 0.3, pz + 0.3, WHITE, "SmoothPlastic",
             deco=True)
    _box(lib, fig, "Kopf", px - 0.55, px + 0.55, 4.85, 5.95, pz - 0.55, pz + 0.55, SKIN, "SmoothPlastic", deco=True)
    _box(lib, fig, "Haare", px - 0.575, px + 0.575, 5.75, 6.15, pz - 0.575, pz + 0.575, (70, 50, 35),
         "SmoothPlastic", deco=True)
    # Wandschrift über dem Empfang
    lib.sign(m, "WILLKOMMEN IN DER LOBBY", (26, 3), CF.at(0, 14.5, Z0 + 0.12, 0), AMBER, SLATE, name="Wandschrift",
             bolts=False, sub="Wähle links den Tycoon oder rechts die Open World", sub_color=WHITE)
    return m


def build_turntable(lib, anim, lights):
    tt = lib.model(anim, "Drehteller", attrs={"Anim": "turntable", "Speed": 15, "Period": 24})
    cz = -700
    piv = lib.part(tt, "Achse", (1, 0.4, 1), CF(0, 0.3, cz), BLACK, "SmoothPlastic", transparency=1, deco=True)
    lib.set_primary(tt, piv)
    lib.cylinder(tt, "Drehscheibe", (0, 0.3, cz), 0.6, 22, "Y", (52, 58, 66), "Metal", reflectance=0.08)
    lib.cylinder(tt, "Leuchtring", (0, 0.3, cz), 0.3, 22.4, "Y", AMBER, "Neon", deco=True)
    with lib.section("Lobby: Showcar"):
        lib.clone_car(tt, "super", CF.at(0, 0.6, cz, 20), TEAL, name="Showcar_Lobby", attrs={"Showcar": True})
    # Spot über dem Drehteller
    _box(lib, lights, "Spot-Abhaengung", -0.15, 0.15, CEIL - 1.5, CEIL, cz - 0.15, cz + 0.15, STEEL, "Metal",
         deco=True)
    spot = lib.part(lights, "Showspot", (2, 1, 2), CF(0, CEIL - 2, cz), BLACK, "Metal", deco=True)
    lib.spot_light(spot, 30, 1.4, (255, 244, 230), 60, "Bottom", True, name="Showlicht")
    return tt


def build_terminals(lib, parent):
    m = lib.model(parent, "Terminals")
    # Einstellungs-Terminal an der Westwand (Bildschirm nach Osten, yaw 90)
    _box(lib, m, "Terminalfuss", X0, X0 + 1.4, 0, 2.4, -702, -698, SLATE, "Metal")
    scr = _box(lib, m, "Terminal", X0, X0 + 1.2, 2.4, 8.4, -703, -697, BLACK, "SmoothPlastic")
    lib.sign(m, "EINSTELLUNGEN", (6, 1.4), CF.at(X0 + 1.3, 9.0, -700, 90), TEAL, SLATE, name="Terminalschild",
             bolts=False, thickness=0.2)
    g = lib.surface_text(scr, None, face="Right", name="Screen")
    lib.text_label(g, "EINSTELLUNGEN", TEAL, "GothamBlack", "Title", None, (0.94, 0.3), (0.03, 0.05))
    lib.text_label(g, "Singleplayer · Passiv-Modus · Beginner-Hinweise", WHITE, "GothamBold", "Lines", None,
                   (0.9, 0.5), (0.05, 0.4))
    # Party-Tafel an der Ostwand (Text nach Westen, yaw -90)
    _box(lib, m, "Tafelrahmen", X1 - 0.8, X1, 2.5, 11.5, -708, -692, FRAME, "Metal")
    board = _box(lib, m, "Partytafel", X1 - 1.0, X1 - 0.8, 3, 11, -707.5, -692.5, BLACK, "SmoothPlastic")
    g = lib.surface_text(board, None, face="Left", name="Screen")
    lib.text_label(g, "PARTY", AMBER, "GothamBlack", "Title", None, (0.94, 0.3), (0.03, 0.05))
    lib.text_label(g, "Code eingeben · bis zu 4 Freunde · gemeinsam reisen", WHITE, "GothamBold", "Lines", None,
                   (0.9, 0.5), (0.05, 0.4))
    _box(lib, m, "Neonleiste", X1 - 1.05, X1 - 0.85, 11.5, 11.8, -708, -692, AMBER, "Neon", deco=True)
    # Tutorial-Kiosk links neben dem Eingang (Bildschirm nach Osten)
    kx, kz = X0 + 1.5, -676
    _cyl_y(lib, m, "Kiosksaeule", kx, 0, 3.6, kz, 1.2, STEEL, "Metal")
    scr = _box(lib, m, "Kioskschirm", kx - 0.3, kx + 0.3, 3.6, 7.6, kz - 3, kz + 3, BLACK, "SmoothPlastic")
    g = lib.surface_text(scr, None, face="Right", name="Screen")
    lib.text_label(g, "TUTORIAL", AMBER, "GothamBlack", "Title", None, (0.94, 0.34), (0.03, 0.05))
    lib.text_label(g, "10 Schritte · 500 Credits + 60 XP", WHITE, "GothamBold", "Lines", None, (0.9, 0.45),
                   (0.05, 0.45))
    _box(lib, m, "Kioskdach", kx - 0.4, kx + 0.4, 7.6, 7.9, kz - 3.2, kz + 3.2, AMBER, "Neon", deco=True)
    return m


def build_showcase(lib, parent, lights):
    """Zwei Ausstellungspodeste mit Vorlagen-Autos links und rechts des Drehtellers"""
    m = lib.model(parent, "Ausstellung")
    for x, tpl, paint, yaw, nm in ((-26, "sport", AMBER, 150, "Showcar_Sport"), (26, "gt_coupe", (200, 50, 50), 210,
                                                                                "Showcar_Coupe")):
        lib.cylinder(m, "Podest", (x, 0.2, -690), 0.4, 18, "Y", (52, 58, 66), "Metal", reflectance=0.08)
        lib.cylinder(m, "Podestring", (x, 0.2, -690), 0.25, 18.4, "Y", TEAL, "Neon", deco=True)
        with lib.section("Lobby: Showcar"):
            lib.clone_car(m, tpl, CF.at(x, 0.4, -690, yaw), paint, name=nm, attrs={"Showcar": True})
    # Stützen entlang der Längswände (zwischen den Glasfeldern)
    for x in (X0 + 2.2, X1 - 2.2):
        for z in (-730, -710, -690, -670):
            _cyl_y(lib, m, "Stuetze", x, 0, CEIL, z, 2.0, FRAME, "Metal")
    return m


def build_furniture(lib, parent):
    m = lib.model(parent, "Moebel")
    # Bänke entlang der Seitenwände, Pflanzkübel an den Ecken
    for x in (-50, 50):
        for z in (-720, -690):
            _box(lib, m, "Bankfuss", x - 2.5, x + 2.5, 0, 0.4, z - 0.6, z + 0.6, SLATE, "Metal")
            _box(lib, m, "Banksitz", x - 3, x + 3, 0.4, 0.8, z - 1.2, z + 1.2, WOOD, "Wood")
    for x, z in ((-54, -736), (54, -736), (-54, -664), (54, -664), (-16, -736), (16, -736)):
        _cyl_y(lib, m, "Kuebel", x, 0, 1.8, z, 2.4, FRAME, "SmoothPlastic")
        lib.ball(m, "Laub", (x, 3.0, z), 3.0, (65, 104, 66), "Grass", deco=True)
    # Leitlinien vom Eingang zu den Portalen (0.05 über dem Boden): quer bei Z -723, dann nach Norden bis vor den
    # Startring (der endet bei Z -725)
    for key, (x, color, title, sub) in PORTALS.items():
        xa, xb = (x, -0.6) if x < 0 else (0.6, x)
        _box(lib, m, "Leitlinie", xa - 0.5, xb + 0.5, 0.0, 0.05, -723.5, -722.5, color, "Neon", deco=True)
        _box(lib, m, "Leitlinie", x - 0.5, x + 0.5, 0.0, 0.05, -724.6, -723.5, color, "Neon", deco=True)
    return m


def build_lights(lib, root):
    lights = lib.folder(root, "Lights")
    with lib.section("Lobby: Licht"):
        for x in (-30, 30):
            for z in (-722, -680):
                bar = lib.part(lights, "Deckenleuchte", (20, 0.4, 1), CF(x, CEIL - 0.2, z), LAMP, "Neon", deco=True)
                set_attrs(bar, {"NightNeon": True})
                lib.point_light(bar, 34, 0.9, LAMP)
        # Vorplatz-Laternen
        for x in (-30, 30):
            lib.street_lamp(lights, x, -636, -0.5, 0, -1)
    return lights


# ---------------------------------------------------------------- Aufbau
def build(workspace, lib, tree):
    root = lib.model(workspace, NAME, attrs={"Zone": "lobby", "Version": "3.0"})
    for nm in ("Ground", "Lights", "Stations", "Arrivals", "Animated"):
        lib.folder(root, nm)
    anim = lib.folder(root, "Animated")
    build_ground(lib, root)
    build_shell(lib, root, anim)
    inner = lib.model(root, "Interior")
    lights = build_lights(lib, root)
    with lib.section("Lobby: Innenausbau"):
        for key, (x, color, title, sub) in PORTALS.items():
            build_portal(lib, inner, anim, key, x, color, title, sub)
        build_reception(lib, inner)
        build_turntable(lib, anim, lights)
        build_terminals(lib, inner)
        build_showcase(lib, inner, lights)
        build_furniture(lib, inner)
    st = lib.folder(root, "Stations")
    ar = lib.folder(root, "Arrivals")
    with lib.section("Lobby: Stationen & Ankunft (unsichtbar)"):
        for key, (title, pos, side, floor) in STATIONS.items():
            build_station(lib, st, key, "lobby", title, pos, side, floor, {"LobbyAction": key})
        for key, (x, fy, z, look) in ARRIVALS.items():
            build_arrival(lib, ar, key, x, fy, z, look)
        lib.spawn(root, "LobbySpawn", (10, 0.2, 10), CF.at(SPAWN[0], SPAWN[1], SPAWN[2], 180), enabled=False)
    return root
