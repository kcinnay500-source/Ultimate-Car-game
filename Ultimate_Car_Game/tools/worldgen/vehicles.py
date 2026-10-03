"""Fahrzeug-Anschlüsse der Stadt (PHASE2_CONTRACT §3, letzte Zeile):

* City.CarSpawns.<key>  unsichtbare, verankerte Parts (8 x 1 x 16, CanCollide/CanTouch/CanQuery false) auf freiem,
  befahrbarem Belag. Unterseite = Boden, LookVector = Fahrtrichtung zum Losfahren (Nase der Vorlagen-Autos = -Z).
  CarService: CFrame -> Position/LookVector, Boden per Raycast, Ausweichplätze seitlich (rechts = (-look.Z, 0,
  look.X)) in Schritten von CarCatalog.Physics.spawnSpacing (11). Attribute: Title (Anzeigename), AltSteps
  ("1,-1,..." = geprüfte freie Ausweichschritte in dieser Reihenfolge), Floor (Bodenhöhe).
* Werkstatt.CarSpawn    derselbe Part in der Plot-Vorlage auf dem Kundenparkplatz (plotlokal, Nase zur Meile).
* City.Track            Checkpoints.CP1..CPn (unsichtbar, CanCollide false, CanTouch true, CanQuery false, quer
  über die ganze Streckenbreite) und Ziel (Start/Ziel-Linie unter der Brücke). Reihenfolge im Uhrzeigersinn wie
  Schleife T; Start = CarSpawns.track kurz vor der Ziellinie, das erste Überfahren der Ziellinie zählt nicht.

Jede Ausfahrt (ROUTES) und jede Plot-Einfahrt wird in checks.py mit drive.py abgefahren.
"""
import math

from .lib import CF, TEAL, AMBER, set_attrs
from .plots import loc2world

SPAWN_SIZE = (8, 1, 16)

# key: (Titel, x, Boden, z, yaw (CF.at: 0 = Nase Nord, 90 West, 180 Süd, -90 Ost), AltSteps, Ausfahrt-Route)
# Die Route beginnt am Spawn und endet auf einer Fahrspur der Verkehrsschleifen A/B1/B2/T.
CAR_SPAWNS = {
    # Autohaus: Zufahrt vor der Übergabe-Halle, Nase zur Meile (Absenkung X 92..108), rechts abbiegen nach Osten
    "dealer": ("Autohaus", 100, -0.95, 46, 0, (1, -1),
               [(100, 46), (100, 16), (108, 6.5), (130, 6.5)]),
    # Probefahrt: Autohaus-Zufahrt R9 hinter dem Showroom, Nase nach Süden -> über den Südring in die Boxengasse
    "testdrive": ("Übergabe · Probefahrt", 100, -0.95, 158, 180, (1, -1, 2, -2),
                  [(100, 158), (100, 262), (80, 270), (-60, 270)]),
    # Teststrecke: Startplatz auf der Nordgeraden 30 vor der Start/Ziel-Linie, Fahrtrichtung Ost (Uhrzeigersinn)
    "track": ("Teststrecke", -30, -0.95, 274, -90, (1, -1),
              [(-30, 274), (60, 270), (85, 270)]),
    # Waschstraße: Gasse zwischen Tunnel und Saugerplatz, Nase nach Westen -> Tankstellen-Ausfahrt -> Marktstraße Ost
    "carwash": ("Waschstraße", 322, -1.0, 211, 90, (-1,),
                [(322, 211), (180, 211), (170, 211), (158.5, 199), (158.5, 150)]),
    # Stadtplatz / Ankunftshalle: Parkplatz-Chaos am Nordausgang der Halle -> Einfahrt Nordring
    "plaza": ("Stadtplatz · Parkplatz", -25, -1.0, -235.5, 90, (1, 2),
              [(-25, -235.5), (-54, -235.5), (-54, -307), (-100, -307), (-100, -335.5), (-60, -335.5)]),
    # Schrottplatz: Betonzufahrt hinter dem Tor, Nase nach Osten -> Marktstraße West (rechts nach Süden)
    "scrapyard": ("Schrottplatz", -192, -1.0, -201, -90, (1, -1),
                  [(-192, -201), (-170, -201), (-158.5, -190), (-158.5, -150)]),
    # Tuning-Zentrum: Fahrgasse vor dem Rolltor, Nase nach Westen -> Marktstraße Ost (rechts nach Norden)
    "tuning": ("Tuning-Zentrum", 196, -1.0, -249, 90, (1, -1),
               [(196, -249), (170, -249), (158.5, -260), (158.5, -300)]),
}

# Werkstatt-Kundenparkplatz (plotlokal): Bucht X 0..15 der 2.4.0-Parklinien, Nase zur Meile (+Z lokal)
PLOT_SPAWN = (7.5, -1.0, 64, 180, (1, -1, 2))
PLOT_ROUTE_LOCAL = [(7.5, 64), (7.5, 102.5)]      # bis auf die Meile-Fahrspur (Welt Z ∓6.5)

# Teststrecke "Grand-Prix-Kurs" (3.0): eine Mittellinie für Belag (districts/dealer_track.build_track), Checkpoints,
# Verkehrsschleife T (ground_roads.traffic_loops -> track_loop()) und Prüfungen (checks.py, test_vehicles.py).
# Start an der Westecke der Start/Ziel-Geraden (-90, 270), Blick nach Osten, im Uhrzeigersinn (Karte: Norden oben):
#   Start/Ziel-Gerade -> Kurve 1 (rechts) -> S-Kurve (links/rechts) -> schnelle Kurve (rechts, r 85)
#   -> lange Gegengerade (320) -> Haarnadel (180° rechts) -> Linksknick -> Westgerade -> weite Zielkurve (rechts)
# Stücke: ("S", Länge) Gerade | ("R"/"L", Radius, Grad) Bogen rechts/links. Breite 24 (Spuren ±9 frei befahrbar).
TRACK_START = (-90.0, 270.0)
TRACK_HEADING = (1.0, 0.0)
TRACK_PIECES = [
    ("S", 200.0, "Start/Ziel-Gerade"),
    ("R", 50.0, 90.0, "Kurve 1"),
    ("S", 10.0, "Ostgerade"),
    ("L", 60.0, 60.0, "S-Kurve links"),
    ("R", 60.0, 60.0, "S-Kurve rechts"),
    ("S", 6.0769515, "Ostgerade"),
    ("R", 85.0, 90.0, "Schnelle Kurve"),
    ("S", 320.0, "Lange Gerade"),
    ("R", 35.0, 180.0, "Haarnadel"),
    ("L", 35.0, 90.0, "Linksknick"),
    ("S", 90.0, "Westgerade"),
    ("R", 60.0, 90.0, "Zielkurve"),
]
TRACK_WIDTH = 24.0
TRACK_Y = -0.95                                    # Oberseite des Belags
CP_SIZE = (TRACK_WIDTH + 8, 14, 6)                 # quer, hoch, längs (6: schnelle Autos tunneln nicht hindurch)
# Checkpoints (Stück-Index, Anteil 0..1) in Fahrtrichtung ab der Ziellinie; das Ziel liegt bei X 0 der Geraden
CP_AT = [(0, 0.8), (1, 0.5), (3, 1.0), (4, 0.5), (6, 0.5), (7, 0.3), (7, 0.73), (8, 0.5), (9, 0.5), (10, 0.5),
         (11, 0.5), (0, 0.2)]
FINISH_AT = (0, 0.45)
TRACK_LAYOUT = 2                                   # = TrackRules.Layout.version (alte Bestzeiten vom Oval verfallen)


def _right(d):
    return (-d[1], d[0])


def track_geometry():
    """[(kind, a, b, data)] je Stück: Gerade ("S", Start, Ende, (dir, name)) oder Bogen ("A", Start, Ende,
    (center, radius, a0, a1, sign, name)) mit Winkeln in Grad (0 = +X, 90 = +Z), sign +1 = rechts (Uhrzeigersinn)."""
    out = []
    p, d = TRACK_START, TRACK_HEADING
    for piece in TRACK_PIECES:
        if piece[0] == "S":
            q = (p[0] + d[0] * piece[1], p[1] + d[1] * piece[1])
            out.append(("S", p, q, (d, piece[2])))
            p = q
            continue
        kind, r, deg, name = piece
        sign = 1 if kind == "R" else -1
        rv = _right(d)
        c = (p[0] + rv[0] * r * sign, p[1] + rv[1] * r * sign)
        a0 = math.degrees(math.atan2(p[1] - c[1], p[0] - c[0]))
        a1 = a0 + sign * deg
        q = (c[0] + r * math.cos(math.radians(a1)), c[1] + r * math.sin(math.radians(a1)))
        t = math.radians(a1)
        # Tangente in Fahrtrichtung: rechts herum (Winkel wächst) = (-sin, cos), links herum umgekehrt
        d = (-math.sin(t) * sign, math.cos(t) * sign)
        out.append(("A", p, q, (c, r, a0, a1, sign, name)))
        p = q
    return out


def piece_length(g):
    if g[0] == "S":
        return math.dist(g[1], g[2])
    return abs(g[3][3] - g[3][2]) * math.pi / 180 * g[3][1]


def track_length():
    return sum(piece_length(g) for g in track_geometry())


def track_point(idx, frac):
    """(x, z), (dx, dz) auf Stück idx beim Anteil frac"""
    g = track_geometry()[idx]
    if g[0] == "S":
        a, b = g[1], g[2]
        return (a[0] + (b[0] - a[0]) * frac, a[1] + (b[1] - a[1]) * frac), g[3][0]
    c, r, a0, a1, sign, name = g[3]
    t = math.radians(a0 + (a1 - a0) * frac)
    return (c[0] + r * math.cos(t), c[1] + r * math.sin(t)), (-math.sin(t) * sign, math.cos(t) * sign)


def track_loop(step=15.0):
    """Geschlossene Mittellinie (ohne doppelten Endpunkt) für Schleife T und die Prüfungen: Geraden-Endpunkte und
    Bogenpunkte alle `step` Grad."""
    pts = []
    for g in track_geometry():
        if g[0] == "S":
            pts.append(g[1])
            continue
        c, r, a0, a1, sign, name = g[3]
        n = max(1, int(round(abs(a1 - a0) / step)))
        for k in range(n):
            t = math.radians(a0 + (a1 - a0) * k / n)
            pts.append((c[0] + r * math.cos(t), c[1] + r * math.sin(t)))
    clean = []
    for q in pts:
        if not clean or math.dist(q, clean[-1]) > 1e-6:
            clean.append((round(q[0], 4), round(q[1], 4)))
    if math.dist(clean[0], clean[-1]) < 1e-6:
        clean.pop()
    return clean


def checkpoints():
    """[(Name, (x, z), (dx, dz) Fahrtrichtung)] im Uhrzeigersinn ab der Ziellinie, zuletzt das Ziel"""
    pts = []
    for i, (idx, frac) in enumerate(CP_AT):
        p, d = track_point(idx, frac)
        pts.append(("CP%d" % (i + 1), p, d))
    p, d = track_point(*FINISH_AT)
    pts.append(("Ziel", p, d))
    return pts


def spawn_world(key):
    title, x, fy, z, yaw, alts, route = CAR_SPAWNS[key]
    return x, fy, z, yaw


def plot_spawn_world(px, pz, rot):
    lx, fy, lz, yaw, alts = PLOT_SPAWN
    x, z = loc2world(px, pz, rot, lx, lz)
    return x, fy, z, (yaw + rot) % 360


def plot_route_world(px, pz, rot):
    return [loc2world(px, pz, rot, lx, lz) for lx, lz in PLOT_ROUTE_LOCAL]


def _yaw_cf(dx, dz):
    """CF-Gierwinkel mit LookVector (dx, 0, dz)"""
    return math.degrees(math.atan2(-dx, -dz))


def _spawn_part(lib, parent, name, x, fy, z, yaw, title, alts):
    p = lib.part(parent, name, SPAWN_SIZE, CF.at(x, fy + SPAWN_SIZE[1] / 2, z, yaw), TEAL, "SmoothPlastic",
                 transparency=1, collide=False, touch=False, query=False, cast_shadow=False)
    set_attrs(p, {"Title": title, "AltSteps": ",".join(str(a) for a in alts), "Floor": float(fy)})
    return p


def build_plot_spawn(werkstatt, lib):
    """Part CarSpawn in der (getrimmten) Plot-Vorlage; W.Create pivotiert ihn mit dem Plot."""
    from .lib import child
    old = child(werkstatt, "CarSpawn")
    if old is not None:
        werkstatt.remove(old)
    lx, fy, lz, yaw, alts = PLOT_SPAWN
    return _spawn_part(lib, werkstatt, "CarSpawn", lx, fy, lz, yaw, "Werkstatt", alts)


def build(city, lib, tree, workspace=None):
    with lib.section("Fahrzeuge (unsichtbar)"):
        sp = lib.folder(city, "CarSpawns")
        for key, (title, x, fy, z, yaw, alts, route) in CAR_SPAWNS.items():
            _spawn_part(lib, sp, key, x, fy, z, yaw, title, alts)
        tr = lib.folder(city, "Track")
        lib.attrs(tr, Laps=1, Direction="Uhrzeigersinn", Start="CarSpawns.track", Layout=TRACK_LAYOUT,
                  Length=round(track_length()), Title="Grand-Prix-Kurs")
        cps = lib.folder(tr, "Checkpoints")
        lst = checkpoints()
        for i, (name, (x, z), (dx, dz)) in enumerate(lst):
            parent = tr if name == "Ziel" else cps
            p = lib.part(parent, name, CP_SIZE, CF.at(x, TRACK_Y + CP_SIZE[1] / 2, z, _yaw_cf(dx, dz)),
                         AMBER if name == "Ziel" else TEAL, "SmoothPlastic", transparency=1, collide=False,
                         touch=True, query=False, cast_shadow=False)
            set_attrs(p, {"Index": i + 1, "Total": len(lst)})
        if workspace is not None:
            from .lib import child
            wk = child(workspace, "Werkstatt")
            if wk is not None:
                build_plot_spawn(wk, lib)
    return sp
