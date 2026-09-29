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

# Teststrecke (Mittellinie wie Schleife T): Oval, Geraden Z 270 / 410, Halbkreise um (±85, 340) r 70, Breite 24
T_CX, T_CZ, T_R = 85.0, 340.0, 70.0
TRACK_WIDTH = 24.0
CP_SIZE = (TRACK_WIDTH + 8, 14, 3)                 # quer, hoch, längs


def _arc(sx, deg):
    a = math.radians(deg)
    return (sx * T_CX + T_R * math.cos(a), T_CZ + T_R * math.sin(a))


def checkpoints():
    """[(Name, (x, z), (dx, dz) Fahrtrichtung)] im Uhrzeigersinn, zuletzt das Ziel"""
    pts = []

    def add(p, d):
        pts.append(("CP%d" % (len(pts) + 1), p, d))
    add((60, 270), (1, 0))
    for deg in (-45, 0, 45):                      # Ostkurve: Winkel -90 (Nord) .. 90 (Süd)
        a = math.radians(deg)
        add(_arc(1, deg), (-math.sin(a), math.cos(a)))
    add((0, 410), (-1, 0))
    for deg in (135, 180, 225):                   # Westkurve: 90 (Süd) .. 270 (Nord)
        a = math.radians(deg)
        add(_arc(-1, deg), (-math.sin(a), math.cos(a)))
    add((-60, 270), (1, 0))
    pts.append(("Ziel", (0, 270), (1, 0)))
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
        lib.attrs(tr, Laps=1, Direction="Uhrzeigersinn", Start="CarSpawns.track")
        cps = lib.folder(tr, "Checkpoints")
        lst = checkpoints()
        for i, (name, (x, z), (dx, dz)) in enumerate(lst):
            parent = tr if name == "Ziel" else cps
            p = lib.part(parent, name, CP_SIZE, CF.at(x, -0.95 + CP_SIZE[1] / 2, z, _yaw_cf(dx, dz)),
                         AMBER if name == "Ziel" else TEAL, "SmoothPlastic", transparency=1, collide=False,
                         touch=True, query=False, cast_shadow=False)
            set_attrs(p, {"Index": i + 1, "Total": len(lst)})
        if workspace is not None:
            from .lib import child
            wk = child(workspace, "Werkstatt")
            if wk is not None:
                build_plot_spawn(wk, lib)
    return sp
