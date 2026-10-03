"""Stufen-Vorlagen des Tycoons: ServerStorage.TycoonTemplates.<typ>.Stage_1..5 (PHASE4_CONTRACT §8).

Der TycoonService klont die Vorlage der aktuellen Stufe und setzt sie mit PivotTo auf den Anker des Grundstücks
(Tycoon.Plots.Slot_n.Anchor, CFrame (X, 0.5, Z) * Angles(0, rad(Rot), 0)). Jede Vorlage ist plotlokal gebaut:
  * PrimaryPart "Root" (1 x 1 x 1, unsichtbar) bei (0, 0.5, 0) - damit ist lokal Y = Welt Y (Oberseite Base = 0)
  * +Z = Vorderseite zur Straße (Pylon bei Z 39.5), -Z = hinten (Hecke); X -35..35, alle Teile innerhalb ±34
  * jede Stufe ist ein VOLLSTÄNDIGES, eigenständiges Bild des Grundstücks (Stufe 1 Kiesplatz + Stand, Stufe 2 Halle,
    Stufe 3 Halle + Anbau + Hofmaschinen, Stufe 4 zwei Hallen + Turm/Kran/Showroom, Stufe 5 großer Komplex mit
    Licht, Schildern, Fahnen) - der Service zeigt also nur die Vorlage der aktuellen Stufe (nicht gestapelt)
Fester Aufbau jeder Vorlage (Meilenstein-4-Vertrag, IDs siehe GameConfig.Tycoon):
  Root            Part, PrimaryPart
  Buttons         Folder mit 4 Kaufpads (Part 5 x 0.5 x 5, Attribut TycoonButton="<typ>_s<stufe>_u<k>", k = 1..4,
                  SurfaceGui "Label" (Top) mit TextLabels "Name" und "Price"; Price setzt der Service)
                  bei Z 30, X -9 / -3 / 3 / 9 (BUTTON_XS)
  StagePad        Part 7 x 0.5 x 7 (TycoonButton="<typ>_stage<stufe+1>", Label Name/Price) bei (29, 29); nur Stufe 1-4
  CashDisplay     Part (Tafel 7 x 3 x 0.5) bei (-20, 3, 20) über dem Sammelpad (Tycoon.COLLECT_PAD liegt genau
                  darunter), SurfaceGui "CashGui" mit TextLabel "Bargeld" (Text setzt der Service)
  Hidden          Folder mit Producer_1..4 (Model je Upgrade k der Stufe: 1 Produzent, 2 Tempo, 3 Lager, 4 Deko);
                  der Service hängt Producer_k nach dem Kauf ins Modell um (revealProducers)
  sichtbare Teile Gebäude, Hof, Deko der Stufe
Animationen (rein optisch, Client): Attribut Anim = press | turntable | door | neon | flag (CityClient, auch unter
Tycoon.Plots) und TycoonAnim = conveyor | stamp (TycoonClient). Der Kran nutzt "turntable" (CityClient "crane" braucht
Welt-Koordinaten, die nach PivotTo nicht stimmen). Bewegte Anim-Modelle sind nie ineinander verschachtelt.
Regeln (checks.template_checks): <= 350 Parts, <= 6 Lichter je Vorlage (TEMPLATE_BUDGET), alles verankert,
innerhalb X/Z ±34 und Y >= 0, keine AABB-Überschneidung zweier Teile (auch Hidden), keine Z-Fighting-Kandidaten,
alles am Boden verbunden (Stufenstapel: Hof 0.2, Hallenboden 0.3, Sockel darauf); Ausnahme Attribut Pierce=true
(Kolbenstangen der Pressen laufen absichtlich durch das Querhaupt).
Upgrade-Namen (Label "Name") sind eine Kopie der Namen aus GameConfig.Tycoon (flavour) - der Service darf sie
zur Laufzeit überschreiben.
"""
import math
from contextlib import contextmanager

from .lib import (CF, AMBER, APRON, ASPHALT, BLACK, FRAME, GLASS, GRAPHITE, HEDGE, LAMP, RED, SIDEWALK, SLATE, STEEL,
                  TEAL, TRUSS, WHITE, YARD, Color3, child, children, name_of, set_attrs, to_cf)

NAME = "TycoonTemplates"
TEMPLATE_BUDGET = (350, 6)          # Parts, Lichter je Stufenvorlage
TYPES = ("werkstatt", "autohaus", "produktion", "schrottplatz")
MAX_STAGE = 5
UPGRADES_PER_STAGE = 4
ROOT_Y = 0.5
INNER = 34.0                        # Teile bleiben innerhalb ±34 (Plot-Kanten bei 34.4..35)
BUTTON_XS = (-9.0, -3.0, 3.0, 9.0)
BUTTON_Z = 30.0
BUTTON_SIZE = 5.0
STAGE_PAD = (29.0, 29.0)
STAGE_PAD_SIZE = 7.0
CASH_DISPLAY = (-20.0, 3.0, 20.0)
KINDS = ("producer", "tempo", "lager", "deko")
ANIM_KINDS = {"press", "turntable", "door", "neon", "flag", "beacon", "pylon"}
TYCOON_ANIM_KINDS = {"conveyor", "stamp"}
MOVING = {"press", "turntable", "door", "flag", "conveyor", "stamp"}

# Kopie der Upgrade-Namen aus GameConfig.Tycoon (flavour) - nur Platzhalter für Label "Name": TycoonService.bindButtons
# schreibt den Namen zur Laufzeit aus GameConfig.Tycoon.UpgradeById/StageById; tests/test_tycoon_rules.lua prüft die Fixture
# (Ids, Namen, TycoonKind) gegen GameConfig.
NAMES = {
    "werkstatt": {
        "producer": ["Hebebühne", "Zweite Bühne", "Motorenprüfstand", "Lackierkabine", "Meisterhalle"],
        "tempo": ["Akkuschrauber", "Werkzeugwagen", "Schnellheber", "Diagnose-Computer", "Roboterarm"],
        "lager": ["Regal", "Teilelager", "Reifenlager", "Hochregal", "Logistikhalle"],
        "deko": ["Firmenschild", "Blumenkübel", "Neonschrift", "Kundencafé", "Pokalvitrine"],
    },
    "autohaus": {
        "producer": ["Verkaufsstand", "Showroom", "Glashalle", "Probefahrt-Strecke", "Luxus-Etage"],
        "tempo": ["Prospekte", "Verkaufstraining", "Online-Anzeigen", "Finanzierungsbüro", "Drehbühne"],
        "lager": ["Stellplätze", "Parkdeck", "Lackdepot", "Reifenhotel", "Auslieferungshalle"],
        "deko": ["Fahnenmast", "Ballonbogen", "Lichtband", "Kaffeebar", "Springbrunnen"],
    },
    "produktion": {
        "producer": ["Montageband", "Karosseriepresse", "Schweißroboter", "Lackierstraße", "Endmontage"],
        "tempo": ["Schichtplan", "Förderband", "Roboterzelle", "Just-in-time", "Vollautomatik"],
        "lager": ["Kistenlager", "Bauteilelager", "Lackdepot", "Hochregallager", "Verladehof"],
        "deko": ["Werkslogo", "Schornstein", "Testparcours", "Kantine", "Aussichtsturm"],
    },
    "schrottplatz": {
        "producer": ["Schrottpresse", "Greifkran", "Shredder", "Sortieranlage", "Schmelzofen"],
        "tempo": ["Brechstange", "Gabelstapler", "Magnetkran", "Förderschnecke", "Laserschneider"],
        "lager": ["Schrottberg", "Container", "Teilecontainer", "Lagerhalle", "Verladerampe"],
        "deko": ["Wachhund-Hütte", "Reifenstapel", "Autoturm", "Graffiti-Wand", "Leuchtreklame"],
    },
}
TITLES = {"werkstatt": "WERKSTATT", "autohaus": "AUTOHAUS", "produktion": "PRODUKTION", "schrottplatz": "SCHROTTPLATZ"}

# Farben
GRAVEL = (110, 104, 96)
WOOD = (130, 90, 60)
YELLOW = (230, 190, 40)
RUST = (122, 74, 44)
RUST2 = (98, 62, 40)
ORANGE = (225, 110, 40)
CONCRETE = (150, 150, 145)
BRICK = (140, 82, 62)
GREEN = (90, 180, 90)
PAINT = (52, 58, 66)
CAR_COLORS = [TEAL, AMBER, (200, 60, 60), (240, 240, 240), (70, 90, 200)]
PRICE_PLACEHOLDER = "– Bargeld"


def upgrade_id(typ, stage, k):
    return "%s_s%d_u%d" % (typ, stage, k)


def stage_id(typ, stage):
    return "%s_stage%d" % (typ, stage)


def _c3(rgb):
    return Color3(*rgb)


# ---------------------------------------------------------------- Bau-Kontext (plotlokal)
class Ctx:
    """Baut in ein Stufenmodell; alle Koordinaten plotlokal (Y = Welt-Y). Zählt Lichter je Vorlage."""

    def __init__(self, lib, model, hidden, typ, stage):
        self.lib = lib
        self.m = model
        self.hidden = hidden
        self.typ = typ
        self.stage = stage
        self.nlights = 0
        self.gy = 0.0            # Bodenhöhe (Stufe 1: Oberseite des Kiesplatzes), wird auf alle Y addiert

    # Grundbausteine
    def _cf(self, cf):
        return CF(0, self.gy, 0) * to_cf(cf)

    @contextmanager
    def raised(self, dy):
        """Alles im Block steht dy höher (z. B. auf einem Kabinenboden)."""
        self.gy += dy
        try:
            yield
        finally:
            self.gy -= dy

    def box(self, parent, name, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
        g = self.gy
        return self.lib.box(parent, name, min(x0, x1), max(x0, x1), min(y0, y1) + g, max(y0, y1) + g, min(z0, z1),
                            max(z0, z1), color, material, **kw)

    def part(self, parent, name, size, cf, color=SLATE, material="SmoothPlastic", **kw):
        return self.lib.part(parent, name, size, self._cf(cf), color, material, **kw)

    def cyl(self, parent, name, center, length, diameter, axis="Y", color=STEEL, material="Metal", **kw):
        cx, cy, cz = center
        return self.lib.cylinder(parent, name, (cx, cy + self.gy, cz), length, diameter, axis, color, material, **kw)

    def wedge(self, parent, name, size, cf, color=SLATE, material="SmoothPlastic", **kw):
        return self.lib.wedge(parent, name, size, self._cf(cf), color, material, **kw)

    def ball(self, parent, name, center, diameter, color=AMBER, material="Neon", **kw):
        cx, cy, cz = center
        return self.lib.ball(parent, name, (cx, cy + self.gy, cz), diameter, color, material, **kw)

    def model(self, parent, name, attrs=None):
        return self.lib.model(parent, name, attrs=attrs)

    def sign(self, parent, text, size, x, y, z, yaw=0, text_color=AMBER, bg=SLATE, name="Schild", **kw):
        return self.lib.sign(parent, text, size, CF.at(x, y + self.gy, z, yaw), text_color, bg, name=name,
                             bolts=False, **kw)

    def light(self, part, range_=22, brightness=0.8, color=LAMP):
        if self.nlights >= TEMPLATE_BUDGET[1]:
            return None
        self.nlights += 1
        return self.lib.point_light(part, range_, brightness, color)

    def spot(self, part, range_=26, brightness=1.2, angle=70):
        if self.nlights >= TEMPLATE_BUDGET[1]:
            return None
        self.nlights += 1
        return self.lib.spot_light(part, range_, brightness, (255, 244, 230), angle, "Bottom", False)

    def producer(self, k, attrs=None):
        return self.lib.model(self.hidden, "Producer_%d" % k, attrs=attrs)

    def car(self, parent, template, x, y, z, yaw, paint=TEAL, name="Auto", attrs=None):
        return self.lib.lite_car(parent, template, CF.at(x, y + self.gy, z, yaw), paint, name=name, attrs=attrs)

    # -------------------------------------------------------- Rezepte
    def plate(self, parent, name, x0, x1, z0, z1, y0=0.0, h=0.2, color=GRAVEL, material="Pebble"):
        return self.box(parent, name, x0, x1, y0, y0 + h, z0, z1, color, material)

    def gravel(self, parent):
        """Kiesplatz der Stufe 1 (X ±34, Z -34..14, 0..0.2); danach steht alles Weitere auf Y 0.2 (gy)."""
        p = self.plate(parent, "Kiesplatz", -34, 34, -34, 14)
        self.gy = 0.2
        return p

    def _wall(self, m, name, x0, x1, y0, y1, z0, z1, col, mat, win, glass, **kw):
        """Wandstück; win = (wy0, wy1) teilt es in Sockel / Glasband / Oberteil (Glas in der Wanddicke)."""
        if glass or win is None or win[1] - win[0] < 0.5:
            self.box(m, name, x0, x1, y0, y1, z0, z1, col, mat, **kw)
            return
        wy0, wy1 = win
        self.box(m, name, x0, x1, y0, wy0, z0, z1, col, mat)
        self.box(m, name + "_Glas", x0, x1, wy0, wy1, z0, z1, GLASS, "Glass", transparency=0.3, deco=True)
        self.box(m, name + "_Oben", x0, x1, wy1, y1, z0, z1, col, mat)

    def hall(self, parent, x0, x1, z0, z1, h, wall=SLATE, roof=GRAPHITE, material="Concrete", door=None,
             windows=True, name="Halle", floor=False, frame=False, glass=False, door_color=FRAME, y0=0.0,
             front="S"):
        """Halle mit 4 Wänden (0.6), Dach (0.6) und optional Boden (0.3, sonst ist die Base der Boden).
        door = (Mitte, Breite, Höhe) in der Vorderwand (+Z, front="S") oder Rückwand (front="N"); Rolltor mit
        Anim=door (öffnet bei Annäherung). windows: Glasband in der Wanddicke (45..72 % der Höhe).
        glass=True: Glaswände zwischen Stahlstützen (Showroom). Rückgabe: Model."""
        m = self.model(parent, name)
        t = 0.6
        mat = "Glass" if glass else material
        col = GLASS if glass else wall
        kw = {"transparency": 0.35} if glass else {}
        c = 0.8 if (frame or glass) else 0.0
        if floor:
            self.box(m, "Boden", x0 + max(t, c), x1 - max(t, c), y0, y0 + 0.3, z0 + max(t, c), z1 - max(t, c), APRON,
                     "Concrete")
        if c:
            for cx in (x0, x1 - c):
                for cz in (z0, z1 - c):
                    self.box(m, "Stuetze", cx, cx + c, y0, y0 + h, cz, cz + c, FRAME, "Metal")
        win = (y0 + h * 0.45, y0 + h * 0.72) if (windows and not glass and h >= 6) else None
        fz0, fz1 = (z1 - t, z1) if front == "S" else (z0, z0 + t)
        bz0, bz1 = (z0, z0 + t) if front == "S" else (z1 - t, z1)
        self._wall(m, "Rueckwand", x0 + c, x1 - c, y0, y0 + h, bz0, bz1, col, mat, win, glass, **kw)
        for nm, wx0, wx1 in (("Wand_W", x0, x0 + t), ("Wand_O", x1 - t, x1)):
            self._wall(m, nm, wx0, wx1, y0, y0 + h, z0 + max(t, c), z1 - max(t, c), col, mat, win, glass, **kw)
        if door:
            dcx, dw, dh = door
            dx0, dx1 = dcx - dw / 2, dcx + dw / 2
            self._wall(m, "Vorderwand_W", x0 + c, dx0, y0, y0 + h, fz0, fz1, col, mat, win, glass, **kw)
            self._wall(m, "Vorderwand_O", dx1, x1 - c, y0, y0 + h, fz0, fz1, col, mat, win, glass, **kw)
            self.box(m, "Torsturz", dx0, dx1, y0 + dh, y0 + h, fz0, fz1, wall, material)
            dm = self.model(m, "Rolltor", attrs={"Anim": "door", "Lift": dh - 0.8, "OpenRange": 14.0, "Period": 12.0,
                                                 "OpenTime": 0.8})
            gate = self.box(dm, "Torblatt", dx0 + 0.1, dx1 - 0.1, y0 + 0.3, y0 + dh - 0.05, fz0 + 0.1, fz1 - 0.1,
                            door_color, "Metal")
            self.lib.set_primary(dm, gate)
            lz0, lz1 = (fz1 - 0.1, fz1 + 0.02) if front == "S" else (fz0 - 0.02, fz0 + 0.1)
            for k in range(1, 4):
                yy = y0 + 0.3 + k * (dh - 0.35) / 4
                self.box(dm, "Torlamelle", dx0 + 0.3, dx1 - 0.3, yy - 0.08, yy + 0.08, lz0, lz1, BLACK, "Metal",
                         deco=True)
        else:
            self._wall(m, "Vorderwand", x0 + c, x1 - c, y0, y0 + h, fz0, fz1, col, mat, win, glass, **kw)
        self.box(m, "Dach", x0, x1, y0 + h, y0 + h + 0.6, z0, z1, roof, "Concrete")
        return m

    def annex(self, parent, x0, x1, z0, z1, h, wall=SLATE, roof=GRAPHITE, door=None, side="O", name="Anbau",
              material="Concrete"):
        """Anbau an eine Halle: Wand zur Halle entfällt (side = Seite, an der die Halle steht: 'W' oder 'O')."""
        m = self.model(parent, name)
        t = 0.6
        win = (h * 0.45, h * 0.72) if h >= 6 else None
        self._wall(m, "Rueckwand", x0, x1, 0.0, h, z0, z0 + t, wall, material, win, False)
        if side == "W":
            self._wall(m, "Wand_O", x1 - t, x1, 0.0, h, z0 + t, z1 - t, wall, material, win, False)
        else:
            self._wall(m, "Wand_W", x0, x0 + t, 0.0, h, z0 + t, z1 - t, wall, material, win, False)
        if door:
            dcx, dw, dh = door
            dx0, dx1 = dcx - dw / 2, dcx + dw / 2
            self._wall(m, "Vorderwand_W", x0, dx0, 0.0, h, z1 - t, z1, wall, material, win, False)
            self._wall(m, "Vorderwand_O", dx1, x1, 0.0, h, z1 - t, z1, wall, material, win, False)
            self.box(m, "Torsturz", dx0, dx1, dh, h, z1 - t, z1, wall, material)
            dm = self.model(m, "Rolltor", attrs={"Anim": "door", "Lift": dh - 0.8, "OpenRange": 14.0, "Period": 12.0,
                                                 "OpenTime": 0.8})
            gate = self.box(dm, "Torblatt", dx0 + 0.1, dx1 - 0.1, 0.3, dh - 0.05, z1 - t + 0.1, z1 - 0.1, FRAME,
                            "Metal")
            self.lib.set_primary(dm, gate)
        else:
            self._wall(m, "Vorderwand", x0, x1, 0.0, h, z1 - t, z1, wall, material, win, False)
        self.box(m, "Dach", x0, x1, h, h + 0.6, z0, z1, roof, "Concrete")
        return m

    def tower(self, parent, x0, x1, z0, z1, h, color=SLATE, name="Turm", beacon=True, bands=3, y0=0.0, sign=None):
        """Turm mit Fensterbändern auf der Vorderseite (+Z); sign = (Text, Breite, Höhe, Y) ersetzt dort das Band."""
        m = self.model(parent, name)
        self.box(m, "Turmkorpus", x0, x1, y0, y0 + h, z0, z1, color, "Concrete")
        sy0 = sy1 = None
        if sign:
            text, sw, sh, sy = sign
            self.sign(m, text, (sw, sh), (x0 + x1) / 2, sy, z1 + 0.1, 0, AMBER, SLATE, name="Turmschild")
            sy0, sy1 = sy - sh / 2 - 0.3, sy + sh / 2 + 0.3
        for k in range(bands):
            yy = y0 + h * (0.18 + 0.68 * k / max(1, bands - 1))
            if sy0 is not None and yy + 1.4 > sy0 and yy < sy1:
                continue
            self.box(m, "Turmfenster", x0 + 0.8, x1 - 0.8, yy, yy + 1.4, z1, z1 + 0.2, GLASS, "Glass",
                     transparency=0.3, deco=True)
        self.box(m, "Turmkrone", x0, x1, y0 + h, y0 + h + 0.8, z0, z1, GRAPHITE, "Concrete")
        if beacon:
            cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
            self.cyl(m, "Mast", (cx, y0 + h + 0.8 + 2.0, cz), 4.0, 0.4, "Y", STEEL, "Metal")
            b = self.ball(m, "Warnlicht", (cx, y0 + h + 0.8 + 4.0 + 0.5, cz), 1.0, RED, "Neon", deco=True)
            set_attrs(b, {"Anim": "beacon", "Period": 1.2})
        return m

    def lift(self, parent, x, z, car=None, paint=TEAL, raised=True, name="Hebebuehne"):
        """4-Säulen-Hebebühne mit Fahrschienen: Auto mit der Länge entlang X (yaw 90), Reifen stehen auf zwei Schienen
        (Z ±3.3..5.0), Säulen an den Ecken (X ±7.5, Z ±5.2). Platzbedarf X ±8, Z ±5.6."""
        m = self.model(parent, name)
        top = 6.4
        for sx in (-7.5, 7.5):
            for sz in (-5.2, 5.2):
                self.box(m, "Saeule", x + sx - 0.4, x + sx + 0.4, 0.0, top, z + sz - 0.4, z + sz + 0.4, TRUSS, "Metal")
                self.box(m, "Saeulenkopf", x + sx - 0.6, x + sx + 0.6, top, top + 0.5, z + sz - 0.6, z + sz + 0.6,
                         AMBER, "Metal", deco=True)
        ay = 2.7 if raised else 0.6
        for sz in (-1, 1):
            self.box(m, "Fahrschiene", x - 7.1, x + 7.1, ay, ay + 0.4, z + sz * 3.3, z + sz * 5.0, GRAPHITE, "Metal")
        if car:
            self.car(m, car, x, ay + 0.4, z, 90, paint, name="Kundenauto")
        return m

    @staticmethod
    def rack_tops(h=6.0, levels=3):
        """Oberseiten der Regalböden von rack(h, levels)"""
        return [0.3 + (k * (h - 0.6) / (levels - 1) if levels > 1 else 0.0) + 0.2 for k in range(levels)]

    def rack(self, parent, x0, x1, z0, z1, h=6.0, levels=3, crates=True, color=TRUSS, name="Regal"):
        """Regal: 4 Pfosten, Böden (Schwerlastregal), Kisten auf den Böden (Oberseiten: rack_tops)."""
        m = self.model(parent, name)
        for px in (x0, x1 - 0.3):
            for pz in (z0, z1 - 0.3):
                self.box(m, "Pfosten", px, px + 0.3, 0.0, h, pz, pz + 0.3, color, "Metal")
        n = 0
        for k in range(levels):
            yy = 0.3 + k * (h - 0.6) / (levels - 1) if levels > 1 else 0.3
            self.box(m, "Boden", x0 + 0.3, x1 - 0.3, yy, yy + 0.2, z0, z1, ORANGE if color == TRUSS else color,
                     "Metal")
            if crates and k < levels - 1:
                cx = x0 + 0.9
                while cx + 1.6 <= x1 - 0.9:
                    n += 1
                    if n % 3:
                        self.box(m, "Kiste", cx, cx + 1.4, yy + 0.2, yy + 1.3, z0 + 0.3, z1 - 0.3, WOOD, "Wood",
                                 deco=True)
                    cx += 1.8
        return m

    def tires(self, parent, x, z, n=4, name="Reifenstapel"):
        m = self.model(parent, name)
        for k in range(n):
            self.cyl(m, "Reifen", (x, 0.45 + k * 0.9, z), 0.9, 2.6, "Y", BLACK, "Plastic", deco=(k > 0))
        return m

    def barrels(self, parent, x, z, n=3, color=(60, 90, 140), name="Faesser"):
        m = self.model(parent, name)
        for k in range(n):
            self.cyl(m, "Fass", (x + k * 2.3, 1.5, z), 3.0, 2.0, "Y", color if k % 2 == 0 else RUST, "Metal")
        return m

    def workbench(self, parent, x0, x1, z0, z1, name="Werkbank"):
        m = self.model(parent, name)
        self.box(m, "Platte", x0, x1, 2.4, 2.7, z0, z1, WOOD, "Wood")
        for bx in (x0 + 0.2, x1 - 0.8):
            self.box(m, "Bein", bx, bx + 0.6, 0.0, 2.4, z0 + 0.2, z1 - 0.2, TRUSS, "Metal")
        self.box(m, "Schraubstock", x0 + 1.0, x0 + 2.0, 2.7, 3.4, z0 + 0.4, z1 - 0.4, STEEL, "Metal", deco=True)
        return m

    def tool_wall(self, parent, x0, x1, z, h=4.0, y0=0.0, face="S", name="Werkzeugwand", tools_y=None):
        """Lochwand (Platte 0.2) mit Werkzeugen auf der Sichtseite (face 'S' = +Z); tools_y = unterste Werkzeugreihe
        (über einer Werkbank davor z. B. 3.0)."""
        m = self.model(parent, name)
        zz0, zz1 = (z, z + 0.2) if face == "S" else (z - 0.2, z)
        self.box(m, "Lochwand", x0, x1, y0, y0 + h, zz0, zz1, (200, 170, 90), "Wood")
        tz0, tz1 = (zz1, zz1 + 0.25) if face == "S" else (zz0 - 0.25, zz0)
        base = y0 + 0.8 if tools_y is None else tools_y
        k = 0
        cx = x0 + 0.8
        while cx + 0.6 <= x1 - 0.6:
            col = (STEEL, RED, AMBER, BLACK)[k % 4]
            ty = base + (k % 2) * 1.2
            self.box(m, "Werkzeug", cx, cx + 0.5, ty, min(ty + 1.4, y0 + h), tz0, tz1, col, "Metal", deco=True)
            k += 1
            cx += 1.3
        return m

    def trolley(self, parent, x, z, color=RED, name="Werkzeugwagen"):
        m = self.model(parent, name)
        self.box(m, "Korpus", x - 1.5, x + 1.5, 0.5, 2.9, z - 0.9, z + 0.9, color, "Metal")
        for k in range(3):
            self.box(m, "Schublade", x - 1.3, x + 1.3, 0.8 + k * 0.7, 1.2 + k * 0.7, z + 0.9, z + 1.0, BLACK, "Metal",
                     deco=True)
        for sx in (-1, 1):
            for sz in (-0.6, 0.6):
                self.cyl(m, "Rolle", (x + sx * 1.1, 0.25, z + sz), 0.3, 0.5, "X", BLACK, "Plastic", deco=True)
        return m

    def planter(self, parent, x, z, name="Blumenkuebel"):
        m = self.model(parent, name)
        self.box(m, "Kuebel", x - 1.2, x + 1.2, 0.0, 1.3, z - 1.2, z + 1.2, CONCRETE, "Concrete")
        self.box(m, "Busch", x - 1.0, x + 1.0, 1.3, 2.6, z - 1.0, z + 1.0, HEDGE, "Grass", deco=True)
        return m

    def lamp(self, parent, x, z, dir_x, dir_z, name="Hoflaterne"):
        """Hoflaterne (4 Parts): Sockel, Mast, Ausleger (ab Mastoberfläche), Kopf mit PointLight."""
        if not self.light_ok():
            return None
        m = self.model(parent, name)
        self.box(m, "Sockel", x - 0.6, x + 0.6, 0.0, 0.8, z - 0.6, z + 0.6, BLACK, "Metal")
        self.cyl(m, "Mast", (x, 0.8 + 5.5, z), 11.0, 0.45, "Y", STEEL, "Metal")
        top = 0.8 + 11.0
        ax0, ax1 = x + dir_x * 0.225, x + dir_x * 2.4
        az0, az1 = z + dir_z * 0.225, z + dir_z * 2.4
        self.box(m, "Ausleger", min(ax0, ax1) - (0.15 if dir_x == 0 else 0), max(ax0, ax1) + (0.15 if dir_x == 0 else 0),
                 top - 0.45, top - 0.15, min(az0, az1) - (0.15 if dir_z == 0 else 0),
                 max(az0, az1) + (0.15 if dir_z == 0 else 0), STEEL, "Metal", deco=True)
        hx, hz = x + dir_x * 2.4, z + dir_z * 2.4
        head = self.box(m, "Kopf", hx - 0.8, hx + 0.8, top - 0.8, top - 0.45, hz - 0.8, hz + 0.8, LAMP, "SmoothPlastic",
                        deco=True)
        set_attrs(head, {"NightNeon": True})
        self.lib.point_light(head, 24, 0.9, LAMP)
        return m

    def flag(self, parent, name, x, z, cloth, stripe, text, h=13.0):
        """Fahnenmast (Anim=flag): Fuß, Mast, Spitze, Tuch nach +X mit Streifen auf der Tuchfläche (5 Parts)."""
        f = self.model(parent, name, attrs={"Anim": "flag", "Swing": 6, "Period": 3.2})
        self.cyl(f, "Mastfuss", (x, 0.3, z), 0.6, 1.4, "Y", BLACK, "Metal")
        self.cyl(f, "Fahnenmast", (x, 0.6 + h / 2, z), h, 0.4, "Y", STEEL, "Metal")
        top = 0.6 + h
        self.ball(f, "Mastspitze", (x, top + 0.35, z), 0.7, AMBER, "Metal", deco=True)
        tuch = self.part(f, "Fahne", (6, 4, 0.1), CF(x + 3.2, top - 3.0, z), cloth, "Fabric", deco=True)
        self.lib.set_primary(f, tuch)
        self.part(f, "Fahnenstreifen", (5.9, 0.6, 0.1), CF(x + 3.2, top - 4.4, z + 0.1), stripe, "Fabric", deco=True)
        for face in ("Back", "Front"):
            self.lib.surface_text(tuch, text, face=face, text_color=stripe, font="GothamBlack", name="Aufdruck" + face)
        return f

    def light_ok(self):
        if self.nlights >= TEMPLATE_BUDGET[1]:
            return False
        self.nlights += 1
        return True

    def sign_post(self, parent, text, x, z, w=8.0, h=2.4, top=8.0, color=AMBER, bg=SLATE, name="Firmenschild"):
        m = self.model(parent, name)
        self.box(m, "Pfosten", x - 0.3, x + 0.3, 0.0, top - h, z - 0.3, z + 0.3, STEEL, "Metal")
        self.sign(m, text, (w, h), x, top - h / 2, z + 0.4, 0, color, bg, name="Tafel")
        return m

    def neon_sign(self, parent, text, x, bottom, z, w, h=2.2, yaw=0, name="Neonschrift", color=AMBER):
        """Leuchtschrift (Anim=neon): Schild + 2 Neonröhren (oben/unten, anliegend), Text nach +Z (yaw 0).
        bottom = Unterkante der unteren Röhre (z. B. Dachoberkante)."""
        m = self.model(parent, name, attrs={"Anim": "neon", "Period": 3.0, "ColorB": _c3(TEAL)})
        y = bottom + 0.25 + h / 2
        cf = CF.at(x, y + self.gy, z, yaw)
        self.lib.sign(m, text, (w, h), cf, color, BLACK, name="Leuchtschild", bolts=False)
        for sy in (-1, 1):
            self.part(m, "Neonroehre", (w, 0.25, 0.2), cf * CF(0, sy * (h / 2 + 0.125), 0), color, "Neon", deco=True)
        return m

    def container(self, parent, x0, x1, z0, z1, h=8.0, color=(60, 90, 140), y0=0.0, name="Container"):
        m = self.model(parent, name)
        self.box(m, "Korpus", x0, x1, y0, y0 + h, z0, z1, color, "Metal")
        for k in range(3):
            fx = x0 + (x1 - x0) * (k + 1) / 4
            self.box(m, "Sicke", fx - 0.15, fx + 0.15, y0 + 0.3, y0 + h - 0.3, z1, z1 + 0.12, BLACK, "Metal",
                     deco=True)
        return m

    def heap(self, parent, x, z, r, h, colors=(RUST, RUST2, GRAPHITE), name="Schrotthaufen"):
        """Schrotthaufen: gestapelte Zylinder + Blechreste oben"""
        m = self.model(parent, name)
        n = 3
        for k in range(n):
            rr = r * (1 - 0.28 * k)
            hh = h / n
            self.cyl(m, "Schicht", (x, k * hh + hh / 2, z), hh, rr * 2, "Y", colors[k % len(colors)], "CorrodedMetal",
                     deco=(k > 0))
        top = h
        self.box(m, "Blech", x - 1.2, x + 0.6, top, top + 0.3, z - 0.5, z + 0.9, STEEL, "CorrodedMetal", deco=True)
        self.cyl(m, "Felge", (x + 1.6, top + 0.25, z - 1.3), 0.5, 1.4, "Y", BLACK, "Plastic", deco=True)
        return m

    def press(self, parent, x, z, w=18.0, d=10.0, h=20.0, car=None, name="Schrottpresse", scale=1.0):
        """Schrottpresse (Anim=press, CityClient): Bett, 4 Säulen, Querhaupt, Ram (Platen + Kolbenstangen mit Pierce),
        optional Wrack (Car) auf dem Bett, das gequetscht wird."""
        stroke = 6.0 * scale
        m = self.model(parent, name, attrs={"Anim": "press", "Stroke": stroke, "Period": 6.0, "Down": 1.2, "Hold": 0.4,
                                            "Up": 2.0, "Squash": 0.35, "BedY": 3.0})
        ram = self.model(m, "Ram")
        py = 3.0 + stroke + 3.0 + 0.5
        plate = self.box(ram, "Platen", x - w / 2 + 1, x + w / 2 - 1, py, py + 1.6, z - d / 2 + 1, z + d / 2 - 1,
                         (86, 92, 98), "Metal")
        self.lib.set_primary(ram, plate)
        self.box(ram, "Platen_Kante", x - w / 2 + 1.2, x + w / 2 - 1.2, py + 0.4, py + 0.9, z + d / 2 - 1,
                 z + d / 2 - 0.9, YELLOW, "Metal", deco=True)
        for sx in (-w / 4, w / 4):
            self.cyl(ram, "Kolbenstange", (x + sx, py + 1.6 + (h + 3.6 - py - 1.6) / 2, z), h + 3.6 - py - 1.6, 1.2,
                     "Y", (205, 212, 216), "Metal", attrs={"Pierce": True})
        self.box(m, "Pressbett", x - w / 2, x + w / 2, 0.0, 3.0, z - d / 2, z + d / 2, (70, 76, 82), "Metal")
        for sx in (-1, 1):
            for sz in (-1, 1):
                cx = x + sx * (w / 2 + 1.2)
                cz = z + sz * (d / 2 - 1)
                self.box(m, "Saeule", cx - 1.2, cx + 1.2, 0.0, h, cz - 1.0, cz + 1.0, (60, 66, 72), "Metal")
        self.box(m, "Querhaupt", x - w / 2 - 2.4, x + w / 2 + 2.4, h, h + 3, z - d / 2, z + d / 2, YELLOW, "Metal")
        self.sign(m, "PRESSE", (w * 0.7, 1.8), x, h + 1.5, z + d / 2 + 0.1, 0, BLACK, YELLOW, name="Pressenschild")
        if car:
            self.car(m, car, x, 3.0, z, 90, RUST, name="Car")
        self.part(m, "Spark", (1, 1, 1), CF(x, 4.2, z + d / 2 + 0.6), (255, 200, 90), "Neon", transparency=1,
                  deco=True)
        return m

    def stamp(self, parent, x, z, w=8.0, d=6.0, h=9.0, name="Karosseriepresse"):
        """Stanz-/Karosseriepresse (TycoonAnim=stamp): Amboss, 2 Ständer, Kopf, Stempel (Mover) darunter."""
        m = self.model(parent, name, attrs={"TycoonAnim": "stamp", "Period": 2.6, "Down": 0.5, "Hold": 0.25,
                                            "Up": 0.9})
        self.box(m, "Amboss", x - w / 2 + 1, x + w / 2 - 1, 0.0, 1.6, z - d / 2 + 0.5, z + d / 2 - 0.5, (70, 76, 82),
                 "Metal")
        for sx in (-1, 1):
            cx = x + sx * (w / 2 - 0.5)
            self.box(m, "Staender", cx - 0.5, cx + 0.5, 0.0, h, z - d / 2, z + d / 2, TRUSS, "Metal")
        self.box(m, "Kopf", x - w / 2, x + w / 2, h, h + 1.8, z - d / 2, z + d / 2, YELLOW, "Metal")
        gap = h - 1.6
        stroke = gap * 0.55
        st = self.box(m, "Stempel", x - w / 2 + 1.5, x + w / 2 - 1.5, h - stroke - 0.2 - 1.2, h - 0.0,
                      z - d / 2 + 1, z + d / 2 - 1, STEEL, "Metal", attrs={"Mover": True})
        set_attrs(m, {"Stroke": stroke})
        self.lib.set_primary(m, st)
        return m

    def conveyor(self, parent, x0, x1, z, w=3.0, top=2.0, axis="X", name="Montageband", cargo=3, anim=True):
        """Förderband (TycoonAnim=conveyor): Band (Mover), 4 Füße, Seitenschienen, Kisten (Cargo).
        anim=False: statisches Band ohne Kisten (z. B. unter einer Karosserie)."""
        attrs = {"TycoonAnim": "conveyor", "Axis": axis, "Speed": 2.5, "CargoColor": _c3(WOOD)} if anim else None
        if not anim:
            cargo = 0
        m = self.model(parent, name, attrs=attrs)
        band = self.box(m, "Band", x0, x1, top - 0.4, top, z - w / 2, z + w / 2, BLACK, "Plastic",
                        attrs={"Mover": True})
        self.lib.set_primary(m, band)
        for fx in (x0 + 0.6, x1 - 1.0):
            for sz in (-1, 1):
                self.box(m, "Fuss", fx, fx + 0.4, 0.0, top - 0.4, z + sz * (w / 2 - 0.4) - 0.2,
                         z + sz * (w / 2 - 0.4) + 0.2, TRUSS, "Metal")
        for sz in (-1, 1):
            self.box(m, "Schiene", x0, x1, top, top + 0.5, z + sz * (w / 2 + 0.1) - 0.1, z + sz * (w / 2 + 0.1) + 0.1,
                     STEEL, "Metal", deco=True)
        ln = x1 - x0
        for k in range(cargo):
            cx = x0 + ln * (k + 0.5) / cargo
            self.box(m, "Kiste_%d" % (k + 1), cx - 0.6, cx + 0.6, top, top + 0.8, z - 0.6, z + 0.6, WOOD, "Wood",
                     deco=True, attrs={"Cargo": True})
        return m

    def robot(self, parent, x, z, yaw=0, color=ORANGE, name="Roboter", spark=False):
        """Industrieroboter (statisch, achsparallel): Sockel, Säule, Oberarm, Unterarm, Greifer."""
        m = self.model(parent, name)
        self.cyl(m, "Sockel", (x, 0.3, z), 0.6, 3.0, "Y", GRAPHITE, "Metal")
        self.box(m, "Saeule", x - 0.7, x + 0.7, 0.6, 4.6, z - 0.7, z + 0.7, color, "Metal")
        dx, dz = (1, 0) if yaw == 0 else (0, 1) if yaw == 90 else (-1, 0) if yaw == 180 else (0, -1)
        ex, ez = x + dx * 3.4, z + dz * 3.4
        ax0, ax1 = min(x, ex) - 0.6, max(x, ex) + 0.6
        az0, az1 = min(z, ez) - 0.6, max(z, ez) + 0.6
        self.box(m, "Oberarm", ax0, ax1, 4.6, 5.6, az0, az1, color, "Metal")
        self.box(m, "Unterarm", ex - 0.4, ex + 0.4, 2.2, 4.6, ez - 0.4, ez + 0.4, color, "Metal")
        self.cyl(m, "Greifer", (ex, 1.9, ez), 0.6, 1.2, "Y", STEEL, "Metal", deco=True)
        if spark:
            b = self.ball(m, "Schweissfunke", (ex, 1.2, ez), 0.8, (255, 220, 120), "Neon", deco=True)
            set_attrs(b, {"Anim": "beacon", "Period": 0.6})
        return m

    def crane(self, parent, x, z, mast_h=16.0, jib=7.0, cab=True, name="Magnetkran", speed=5.0, magnet_y=3.5):
        """Magnetkran: Mast (PrimaryPart), Kabine, Ausleger nach +X, Seil, Magnet - dreht als Ganzes (Anim=turntable).
        Schwenkkreis Radius jib + 1.5 bis Höhe magnet_y (Unterkante Magnet) freihalten."""
        self.box(parent, name + "_Fuss", x - 2.0, x + 2.0, 0.0, 0.8, z - 2.0, z + 2.0, GRAPHITE, "Metal")
        m = self.model(parent, name, attrs={"Anim": "turntable", "Speed": speed})
        mast = self.cyl(m, "Mast", (x, 0.8 + mast_h / 2, z), mast_h, 1.6, "Y", YELLOW, "Metal")
        self.lib.set_primary(m, mast)
        top = 0.8 + mast_h
        if cab:
            self.box(m, "Kabine", x - 1.3, x + 1.3, top, top + 2.6, z - 1.3, z + 1.3, YELLOW, "Metal")
            self.box(m, "Kabinenfenster", x - 1.0, x + 1.0, top + 0.8, top + 2.2, z + 1.3, z + 1.5, GLASS, "Glass",
                     transparency=0.3, deco=True)
        jy = top + (2.6 if cab else 0.0)
        self.box(m, "Ausleger", x - 2.0, x + jib, jy, jy + 0.8, z - 0.4, z + 0.4, YELLOW, "Metal")
        self.box(m, "Gegengewicht", x - 2.6, x - 2.0, jy - 0.6, jy + 1.2, z - 0.6, z + 0.6, GRAPHITE, "Metal",
                 deco=True)
        my = magnet_y + 1.2
        self.box(m, "Seil", x + jib - 0.6, x + jib - 0.4, my, jy, z - 0.1, z + 0.1, BLACK, "Metal", deco=True)
        self.cyl(m, "Magnet", (x + jib - 0.5, my - 0.4, z), 0.8, 3.0, "Y", RUST2, "Metal", deco=True)
        self.cyl(m, "Magnetkern", (x + jib - 0.5, my - 1.0, z), 0.4, 2.2, "Y", ORANGE, "Metal", deco=True)
        return m

    def turntable(self, parent, x, z, car, paint=TEAL, yaw=0, diameter=14.0, speed=12.0, name="Drehteller"):
        """Drehteller (Anim=turntable) mit Auto: Achse (PrimaryPart, unsichtbar), Leuchtring, Scheibe, Auto."""
        m = self.model(parent, name, attrs={"Anim": "turntable", "Speed": speed})
        piv = self.part(m, "Achse", (1, 0.3, 1), CF(x, 0.15, z), BLACK, "SmoothPlastic", transparency=1, deco=True)
        self.lib.set_primary(m, piv)
        self.cyl(m, "Leuchtring", (x, 0.15, z), 0.3, diameter + 0.6, "Y", AMBER, "Neon", deco=True)
        self.cyl(m, "Drehscheibe", (x, 0.6, z), 0.6, diameter, "Y", PAINT, "Metal", reflectance=0.08)
        self.car(m, car, x, 0.9, z, yaw, paint, name="Showcar")
        return m

    def forklift(self, parent, x, z, name="Gabelstapler"):
        m = self.model(parent, name)
        self.box(m, "Chassis", x - 1.6, x + 1.6, 0.9, 2.2, z - 2.2, z + 1.0, ORANGE, "Metal")
        self.box(m, "Dach", x - 1.4, x + 1.4, 4.6, 4.9, z - 2.0, z + 0.8, BLACK, "Metal", deco=True)
        for sx in (-1.2, 1.2):
            self.box(m, "Dachstuetze", x + sx - 0.15, x + sx + 0.15, 2.2, 4.6, z - 1.8, z - 1.5, BLACK, "Metal",
                     deco=True)
        self.box(m, "Hubmast", x - 1.2, x + 1.2, 0.3, 4.4, z + 1.0, z + 1.4, TRUSS, "Metal")
        for sx in (-0.7, 0.7):
            self.box(m, "Gabel", x + sx - 0.15, x + sx + 0.15, 0.3, 0.5, z + 1.4, z + 3.6, STEEL, "Metal", deco=True)
        for sx in (-1.4, 1.4):
            for wz in (-1.5, 0.3):
                self.cyl(m, "Rad", (x + sx, 0.45, z + wz), 0.5, 0.9, "X", BLACK, "Plastic", deco=True)
        return m

    def pallets(self, parent, x, z, cols=2, rows=2, high=2, name="Kistenlager"):
        m = self.model(parent, name)
        for i in range(cols):
            for j in range(rows):
                px, pz = x + i * 3.4, z + j * 3.4
                self.box(m, "Palette", px, px + 3.0, 0.0, 0.3, pz, pz + 3.0, WOOD, "WoodPlanks")
                for k in range((i + j) % high + 1):
                    self.box(m, "Kiste", px + 0.2, px + 2.8, 0.3 + k * 1.6, 1.9 + k * 1.6, pz + 0.2, pz + 2.8,
                             (WOOD, (110, 80, 50))[k % 2], "Wood", deco=(k > 0))
        return m

    def fence(self, parent, x0, x1, z, h=4.0, along="X", name="Zaun"):
        """Wellblechzaun mit Pfosten"""
        m = self.model(parent, name)
        if along == "X":
            self.box(m, "Wellblech", x0, x1, 0.0, h, z - 0.15, z + 0.15, RUST, "CorrodedMetal")
            px = x0 + 0.25
            while px <= x1 - 0.25:
                self.box(m, "Zaunpfosten", px - 0.25, px + 0.25, 0.0, h + 0.4, z - 0.35, z - 0.15, GRAPHITE, "Metal")
                px += 8
        else:
            self.box(m, "Wellblech", z - 0.15, z + 0.15, 0.0, h, x0, x1, RUST, "CorrodedMetal")
            pz = x0
            while pz <= x1:
                self.box(m, "Zaunpfosten", z + 0.15, z + 0.35, 0.0, h + 0.4, pz - 0.25, pz + 0.25, GRAPHITE, "Metal")
                pz += 8
        return m

    def cones(self, parent, pts, name="Pylonen"):
        m = self.model(parent, name)
        for x, z in pts:
            self.lib.cone(m, x, self.gy, z)
        return m

    def cafe(self, parent, x, z, tables=2, name="Kundencafe"):
        """Kiosk + Tische mit Sonnenschirmen; Tische entlang +X"""
        m = self.model(parent, name)
        self.box(m, "Kiosk", x - 3.0, x + 3.0, 0.0, 3.6, z - 2.0, z + 2.0, TEAL, "Metal")
        self.box(m, "Theke", x - 3.0, x + 3.0, 3.6, 3.9, z + 2.0, z + 3.0, WOOD, "Wood", deco=True)
        self.box(m, "Markise", x - 3.4, x + 3.4, 4.2, 4.5, z - 2.4, z + 3.6, AMBER, "Fabric", deco=True)
        for sx in (-3.0, 3.0):
            self.box(m, "Markisenstuetze", x + sx - 0.12, x + sx + 0.12, 0.0, 4.2, z + 3.2, z + 3.44, STEEL, "Metal",
                     deco=True)
        self.sign(m, "CAFÉ", (5, 1.2), x, 3.0, z + 2.1, 0, WHITE, TEAL, name="Cafeschild")
        for k in range(tables):
            tx, tz = x + 6.5 + k * 5.5, z + 1.0
            self.cyl(m, "Tischfuss", (tx, 1.2, tz), 2.4, 0.3, "Y", STEEL, "Metal")
            self.cyl(m, "Tischplatte", (tx, 2.55, tz), 0.3, 3.0, "Y", WOOD, "Wood", deco=True)
            self.cyl(m, "Schirmstange", (tx, 2.7 + 1.6, tz), 3.2, 0.2, "Y", STEEL, "Metal", deco=True)
            self.cyl(m, "Schirm", (tx, 6.05, tz), 0.3, 4.6, "Y", AMBER, "Fabric", deco=True)
        return m


# ---------------------------------------------------------------- feste Teile jeder Vorlage
def build_fixed(c, typ, stage):
    lib = c.lib
    m = c.m
    root = lib.part(m, "Root", (1, 1, 1), CF(0, ROOT_Y, 0), TEAL, "SmoothPlastic", transparency=1, collide=False,
                    touch=False, query=False, cast_shadow=False)
    lib.set_primary(m, root)
    buttons = lib.folder(m, "Buttons")
    for k in range(1, UPGRADES_PER_STAGE + 1):
        x = BUTTON_XS[k - 1]
        nm = NAMES[typ][KINDS[k - 1]][stage - 1]
        pad = lib.part(buttons, "Button_%d" % k, (BUTTON_SIZE, 0.5, BUTTON_SIZE), CF(x, 0.25, BUTTON_Z), STEEL,
                       "SmoothPlastic", attrs={"TycoonButton": upgrade_id(typ, stage, k), "TycoonKind": KINDS[k - 1]})
        gui = lib.surface_text(pad, None, face="Top", name="Label")
        lib.text_label(gui, nm, SLATE, "GothamBlack", "Name", None, (0.92, 0.5), (0.04, 0.05))
        lib.text_label(gui, PRICE_PLACEHOLDER, BLACK, "GothamBold", "Price", None, (0.92, 0.34), (0.04, 0.6))
        # kleiner Pfosten mit Nummer hinter dem Pad (Sicht von der Straße)
        lib.part(m, "Padpfosten", (0.3, 2.2, 0.3), CF(x, 1.1, BUTTON_Z - BUTTON_SIZE / 2 - 0.5), STEEL, "Metal",
                 deco=True)
        lib.sign(m, "%d" % k, (1.2, 1.0), CF.at(x, 2.7, BUTTON_Z - BUTTON_SIZE / 2 - 0.4, 0), AMBER, SLATE,
                 name="Padnummer", bolts=False)
    if stage < MAX_STAGE:
        sx, sz = STAGE_PAD
        pad = lib.part(m, "StagePad", (STAGE_PAD_SIZE, 0.5, STAGE_PAD_SIZE), CF(sx, 0.25, sz), AMBER, "SmoothPlastic",
                       attrs={"TycoonButton": stage_id(typ, stage + 1)})
        gui = lib.surface_text(pad, None, face="Top", name="Label")
        lib.text_label(gui, "Stufe %d" % (stage + 1), SLATE, "GothamBlack", "Name", None, (0.92, 0.5), (0.04, 0.05))
        lib.text_label(gui, PRICE_PLACEHOLDER, BLACK, "GothamBold", "Price", None, (0.92, 0.34), (0.04, 0.6))
        lib.part(m, "Stufenpfosten", (0.4, 5.1, 0.4), CF(sx, 2.55, sz - STAGE_PAD_SIZE / 2 - 0.6), STEEL, "Metal")
        lib.sign(m, "STUFE %d" % (stage + 1), (5.0, 1.4), CF.at(sx, 5.8, sz - STAGE_PAD_SIZE / 2 - 0.5, 0), SLATE,
                 AMBER, name="Stufenschild", bolts=False)
    # Bargeld-Tafel über dem Sammelpad (Pfosten stehen auf dem Pad, Oberseite 0.5)
    cx, cy, cz = CASH_DISPLAY
    disp = lib.part(m, "CashDisplay", (7.0, 3.0, 0.5), CF(cx, cy, cz), BLACK, "SmoothPlastic")
    gui = lib.surface_text(disp, None, face="Back", name="CashGui")
    lib.text_label(gui, "Bargeld 0", AMBER, "GothamBlack", "Bargeld", None, (0.94, 0.8), (0.03, 0.1))
    gui2 = lib.surface_text(disp, "SAMMELN", face="Front", text_color=TEAL, font="GothamBlack", name="BackGui")
    del gui2
    for sx in (-3.0, 3.0):
        lib.part(m, "Tafelpfosten", (0.5, 1.0, 0.5), CF(cx + sx, 1.0, cz), STEEL, "Metal")
    lib.part(m, "Tafelleiste", (7.0, 0.3, 0.5), CF(cx, cy + 1.65, cz), AMBER, "Neon", deco=True)


# ---------------------------------------------------------------- Werkstatt
def werkstatt(c, s):
    m = c.m
    if s == 1:
        c.gravel(m)
        c.hall(m, -32, -12, -33, -17, 6, WOOD, SLATE, "WoodPlanks", door=(-22, 5, 4.5), name="Schuppen",
               windows=False)
        c.tool_wall(m, -8, 4, -32.5, 4.0, 0.0)
        c.workbench(m, -8, 4, -31.5, -29.5)
        c.barrels(m, 20, -31, 3)
        c.tires(m, 30, -31, 3)
        c.tires(m, 30, -27, 2)
        p = c.producer(1)
        c.lift(p, 14, -14, car="compact", paint=CAR_COLORS[0])
        p = c.producer(2)
        c.trolley(p, -8, -21)
        c.tool_wall(p, -12, -4, -24.0, 2.5, 0.0, name="Akkuschrauber_Wand")
        p = c.producer(3)
        c.rack(p, 6, 16, -33.5, -31, 6.0, 3)
        p = c.producer(4)
        c.sign_post(p, "WERKSTATT", -30, 8, 8, 2.4, 8.5)
    elif s == 2:
        c.hall(m, -32, 18, -33, -3, 9, SLATE, GRAPHITE, door=(-7, 10, 7))
        c.lift(m, -20, -18)
        c.workbench(m, -8, 6, -32.2, -30.2)
        c.tool_wall(m, -8, 6, -32.4, 6.0, 0.0, tools_y=3.0)
        c.sign(m, "WERKSTATT", (14, 2.2), -7, 8.2, -2.9, 0, AMBER, SLATE)
        c.plate(m, "Parkbucht", 21, 33, -20, -4, 0.0, 0.15, ASPHALT, "Asphalt")
        c.tires(m, 30, -30, 4)
        c.tires(m, 26, -30, 3)
        c.barrels(m, 21, -26, 2)
        c.lamp(m, 31, 6, -1, 0)
        p = c.producer(1)
        c.lift(p, 4, -18, car="sedan", paint=CAR_COLORS[1], name="Zweite_Buehne")
        p = c.producer(2)
        c.trolley(p, -27, -6)
        c.trolley(p, -27, -9.5, color=(60, 90, 140))
        p = c.producer(3)
        c.rack(p, 14.4, 17.2, -30, -10, 6.0, 3, name="Teilelager")
        p = c.producer(4)
        for x in (-29, -20, 2, 12):
            c.planter(p, x, 0)
    elif s == 3:
        c.hall(m, -34, 10, -33, -5, 10, SLATE, GRAPHITE, door=(-12, 10, 7.5))
        c.annex(m, 10, 34, -33, -13, 7, SLATE, GRAPHITE, door=(22, 8, 5.5), side="W")
        c.lift(m, -24.5, -20)
        c.lift(m, -7.5, -20, car="hot_hatch", paint=CAR_COLORS[2])
        c.workbench(m, -30, -18, -32.2, -30.2)
        c.tool_wall(m, -30, -18, -32.4, 6.0, 0.0, tools_y=3.0)
        c.sign(m, "WERKSTATT", (14, 2.2), -12, 9.2, -4.9, 0, AMBER, SLATE)
        # Hofmaschinen: Kompressor, Reifen, Fässer, Laterne, Kundenauto
        comp = c.model(m, "Kompressor")
        c.box(comp, "Kompressorgehaeuse", 29, 33, 0.0, 2.0, -6, -2, TRUSS, "Metal")
        c.cyl(comp, "Drucktank", (31, 2.9, -4), 4.0, 1.8, "X", (60, 90, 140), "Metal")
        c.tires(m, 31, 2, 4)
        c.tires(m, 27, 2, 2)
        c.barrels(m, 12, 4, 2)
        c.lamp(m, 12, 12, 0, -1)
        c.car(m, "compact", 24, 0.0, 12, 0, CAR_COLORS[3], name="Kundenauto_Hof")
        p = c.producer(1)
        dyno = c.model(p, "Motorenpruefstand")
        c.box(dyno, "Plattform", 16, 28, 0.0, 0.6, -31, -15, GRAPHITE, "DiamondPlate")
        for zz in (-27, -20):
            c.cyl(dyno, "Rolle", (22, 1.2, zz), 8.0, 1.2, "X", STEEL, "Metal")
        c.box(dyno, "Schaltschrank", 12, 15, 0.0, 4.5, -31, -28, TRUSS, "Metal")
        c.box(dyno, "Bildschirm", 12.3, 14.7, 2.6, 4.2, -28, -27.8, TEAL, "Neon", deco=True)
        c.car(dyno, "sport", 22, 1.8, -23.5, 0, CAR_COLORS[4], name="Pruefling")
        p = c.producer(2)
        sc = c.model(p, "Schnellheber")
        c.box(sc, "Grundrahmen", -26, -18, 0.0, 0.3, -10.5, -7.5, TRUSS, "Metal")
        c.box(sc, "Hubtisch", -26, -18, 2.8, 3.2, -10.5, -7.5, AMBER, "Metal")
        for x in (-25, -19):
            c.box(sc, "Schere", x - 0.2, x + 0.2, 0.3, 2.8, -9.2, -8.8, STEEL, "Metal")
        p = c.producer(3)
        c.rack(p, 29, 33, -31, -17, 7.0, 3, crates=False, name="Reifenlager")
        for zz in (-29, -25, -21):
            for yy in c.rack_tops(7.0, 3)[:2]:
                c.cyl(p, "Lagerreifen", (31, yy + 1.3, zz), 1.0, 2.6, "X", BLACK, "Plastic", deco=True)
        p = c.producer(4)
        c.neon_sign(p, "MEISTERBETRIEB", -12, 10.6, -4.9, 12, 1.6)
    elif s == 4:
        c.hall(m, -34, -3, -33, -5, 11, SLATE, GRAPHITE, door=(-18, 10, 8))
        c.hall(m, 3, 34, -33, -9, 9, SLATE, GRAPHITE, door=(18, 9, 7), name="Halle_2")
        c.tower(m, -3, 3, -33, -21, 22, sign=("WERKSTATT", 5.4, 4.5, 15))
        c.lift(m, -24, -22, car="sedan", paint=CAR_COLORS[0])
        c.car(m, "compact", -9, 0.0, -24, 0, CAR_COLORS[3], name="Wartendes_Auto")
        c.workbench(m, -32, -22, -32.2, -30.2)
        c.tool_wall(m, -32, -22, -32.4, 6.0, 0.0, tools_y=3.0)
        dyno = c.model(m, "Pruefstand")
        c.box(dyno, "Plattform", 13, 25, 0.0, 0.6, -31, -14, GRAPHITE, "DiamondPlate")
        for zz in (-27, -19):
            c.cyl(dyno, "Rolle", (19, 1.2, zz), 8.0, 1.2, "X", STEEL, "Metal")
        c.car(dyno, "sport", 19, 1.8, -22.5, 0, CAR_COLORS[2], name="Pruefling")
        c.tires(m, 31, 0, 4)
        c.tires(m, 27, 0, 3)
        c.barrels(m, 6, -4, 3)
        c.lamp(m, 10, 12, 0, -1)
        c.lamp(m, -30, 6, 1, 0)
        sp = c.part(m, "Hallenspot", (2, 0.4, 2), CF(-18, 10.8, -19), BLACK, "Metal", deco=True)
        c.spot(sp)
        p = c.producer(1)
        booth = c.model(p, "Lackierkabine")
        c.box(booth, "Kabinenboden", -32, -16, 0.0, 0.3, -15.8, -5.6, (60, 66, 72), "Metal")
        c.box(booth, "Rueckwand", -32, -16, 0.3, 6.6, -15.8, -15.4, WHITE, "Metal")
        for x0 in (-32, -16.4):
            c.box(booth, "Seitenwand", x0, x0 + 0.4, 0.3, 6.6, -15.4, -5.6, WHITE, "Metal")
        c.box(booth, "Kabinendach", -32, -16, 6.6, 7.0, -15.8, -5.6, GRAPHITE, "Metal")
        c.box(booth, "Glasfront", -31.6, -16.4, 0.3, 6.6, -5.8, -5.6, GLASS, "Glass", transparency=0.4, deco=True)
        lp = c.box(booth, "Kabinenlicht", -30, -18, 6.2, 6.6, -11.0, -10.4, WHITE, "Neon", deco=True)
        c.light(lp, 14, 0.8, WHITE)
        c.car(booth, "compact", -24, 0.3, -10.7, 90, (240, 240, 240), name="Lackierauto")
        p = c.producer(2)
        dg = c.model(p, "Diagnose_Computer")
        c.box(dg, "Konsole", 5, 11, 0.0, 3.0, -31, -28.5, TRUSS, "Metal")
        c.box(dg, "Monitorwand", 5, 11, 3.0, 6.4, -31, -30.6, BLACK, "Metal")
        c.box(dg, "Monitor", 5.4, 10.6, 3.4, 6.0, -30.6, -30.4, TEAL, "Neon", deco=True)
        p = c.producer(3)
        c.rack(p, 27, 33.2, -31, -11, 8.0, 4, name="Hochregal")
        p = c.producer(4)
        c.cafe(p, 18, 4, tables=2)
    else:
        c.hall(m, -34, 18, -34, -8, 13, SLATE, GRAPHITE, door=(-6, 14, 9))
        c.tower(m, 20, 34, -34, -22, 26, GRAPHITE, bands=4, sign=("WERKSTATT", 12, 3.0, 22))
        c.neon_sign(m, "MEISTERWERKSTATT", -6, 13.6, -7.9, 24, 2.6, name="Dachschrift")
        c.lift(m, -25, -25)
        c.lift(m, -8, -25, car="sedan", paint=CAR_COLORS[0])
        c.lift(m, 9, -25, car="hot_hatch", paint=CAR_COLORS[2])
        c.workbench(m, -32, -20, -33.2, -31.2)
        c.tool_wall(m, -32, -20, -33.4, 6.0, 0.0, tools_y=3.0)
        for x in (-20, 0):
            sp = c.part(m, "Hallenspot", (2, 0.4, 2), CF(x, 12.8, -20), BLACK, "Metal", deco=True)
            c.spot(sp)
        c.lamp(m, -31, 12, 1, 0)
        c.lamp(m, 8, 16, 0, -1)
        for k, x in enumerate((-33, -27)):
            c.flag(m, "Fahne_%d" % (k + 1), x, 18 - k * 4, (AMBER, TEAL)[k % 2], (SLATE, WHITE)[k % 2], "PROFI")
        c.car(m, "compact", 27, 0.0, 6, 0, CAR_COLORS[3], name="Kundenauto_Hof")
        c.tires(m, -14, 10, 4)
        c.tires(m, -10, 10, 3)
        p = c.producer(1)
        mh = c.model(p, "Meisterhalle")
        c.box(mh, "Podest", -33, -15, 0.0, 0.5, -18.6, -9.2, TEAL, "DiamondPlate")
        c.car(mh, "super", -24, 0.5, -13.9, 90, CAR_COLORS[1], name="Meisterstueck")
        c.sign(mh, "MEISTERHALLE", (10, 1.6), -24, 9.0, -33.3, 0, AMBER, SLATE, name="Meisterschild")
        p = c.producer(2)
        c.robot(p, 12, -14, 180, ORANGE, name="Roboterarm")
        p = c.producer(3)
        lg = c.hall(p, 20, 34, -20, -2, 8, SLATE, GRAPHITE, door=(27, 8, 6), name="Logistikhalle", windows=False)
        c.container(lg, 22, 29, -18, -8, 4, (60, 90, 140), 0.0, name="Container_innen")
        p = c.producer(4)
        vit = c.model(p, "Pokalvitrine")
        c.box(vit, "Sockel", -14, -8, 0.0, 1.0, 2, 4, SLATE, "Metal")
        for x0, x1, z0, z1 in ((-13.9, -13.8, 2.1, 3.9), (-8.2, -8.1, 2.1, 3.9), (-13.8, -8.2, 2.1, 2.2),
                               (-13.8, -8.2, 3.8, 3.9)):
            c.box(vit, "Glas", x0, x1, 1.0, 4.6, z0, z1, GLASS, "Glass", transparency=0.5, deco=True)
        c.box(vit, "Glasdeckel", -13.9, -8.1, 4.6, 4.7, 2.1, 3.9, GLASS, "Glass", transparency=0.5, deco=True)
        for k, x in enumerate((-13, -11, -9)):
            c.cyl(vit, "Pokal", (x, 1.0 + 0.9 + k * 0.2, 3), 1.8 + k * 0.4, 0.8, "Y", AMBER, "Metal", deco=True)
        c.sign(vit, "POKALE", (5, 1.0), -11, 5.2, 3.0, 0, AMBER, SLATE, name="Vitrinenschild")


# ---------------------------------------------------------------- Autohaus
def autohaus(c, s):
    m = c.m
    if s == 1:
        c.gravel(m)
        kiosk = c.model(m, "Verkaufskiosk")
        c.box(kiosk, "Kiosk", -33, -25, 0.0, 4.0, -33, -27, TEAL, "Metal")
        c.box(kiosk, "Fenster", -32.5, -25.5, 1.5, 3.4, -27, -26.8, GLASS, "Glass", transparency=0.3, deco=True)
        c.box(kiosk, "Kioskdach", -33.5, -24.5, 4.0, 4.4, -33.5, -25.5, AMBER, "Fabric", deco=True)
        c.sign(kiosk, "AUTOS", (6, 1.4), -29, 5.1, -29.5, 0, SLATE, AMBER, name="Kioskschild")
        c.car(m, "compact", -16, 0.0, -22, 0, CAR_COLORS[2], name="Gebrauchtwagen_1")
        c.car(m, "hot_hatch", 24, 0.0, -22, 0, CAR_COLORS[4], name="Gebrauchtwagen_2")
        for x in (-16, 24):
            c.sign_post(m, "ANGEBOT", x, -9, 4, 1.4, 4.0, WHITE, RED, name="Preisschild")
        p = c.producer(1)
        c.turntable(p, 4, -22, "sedan", CAR_COLORS[0], name="Verkaufsstand")
        p = c.producer(2)
        st = c.model(p, "Prospektstaender")
        c.box(st, "Staender", -9, -6, 0.0, 3.6, -31, -30.4, TEAL, "Metal")
        c.sign(st, "PROSPEKTE", (3, 1.0), -7.5, 4.1, -30.7, 0, WHITE, TEAL, name="Prospektschild")
        p = c.producer(3)
        sp = c.model(p, "Stellplaetze")
        for x in (16, 22, 28, 34):
            c.box(sp, "Markierung", x - 0.2, x + 0.2 if x < 34 else 34, 0.0, 0.1, -8, 8, WHITE, "SmoothPlastic",
                  deco=True)
        c.sign_post(sp, "STELLPLÄTZE", 25, 11, 8, 1.6, 5.0, SLATE, WHITE)
        p = c.producer(4)
        c.flag(p, "Fahnenmast", -31, 6, AMBER, SLATE, "AUTO")
    elif s == 2:
        c.hall(m, -32, 16, -33, -5, 9, glass=True, door=(-8, 8, 7), name="Showroom")
        c.turntable(m, -20, -19, "sedan", CAR_COLORS[0])
        c.sign(m, "AUTOHAUS", (14, 2.4), -8, 10.9, -4.5, 0, SLATE, AMBER, name="Dachschild")
        c.box(m, "Dachschildfuss", -15, -1, 9.6, 9.7, -5.0, -4.3, SLATE, "Metal", deco=True)
        c.car(m, "compact", 25, 0.0, 8, 0, CAR_COLORS[2], name="Gebrauchtwagen")
        c.sign_post(m, "ANGEBOT", 25, 17, 4, 1.4, 4.0, WHITE, RED, name="Preisschild")
        c.lamp(m, -30, 6, 1, 0)
        p = c.producer(1)
        c.turntable(p, 4, -19, "sport", CAR_COLORS[1], name="Showroom_Teller")
        p = c.producer(2)
        desk = c.model(p, "Verkaufstresen")
        c.box(desk, "Tresen", -30, -24, 0.0, 2.6, -9.5, -7.5, WHITE, "Marble")
        c.box(desk, "Bildschirm", -28.5, -25.5, 2.6, 4.2, -8.7, -8.5, TEAL, "Neon", deco=True)
        p = c.producer(3)
        deck = c.model(p, "Parkdeck")
        for x in (20.5, 32.5):
            for z in (-32, -15.5):
                c.box(deck, "Deckstuetze", x, x + 1, 0.0, 4.0, z, z + 1, CONCRETE, "Concrete")
        c.box(deck, "Deckplatte", 20, 34, 4.0, 4.6, -33, -14, CONCRETE, "Concrete")
        c.box(deck, "Bruestung", 20, 34, 4.6, 5.6, -33, -32.6, STEEL, "Metal", deco=True)
        c.car(deck, "hot_hatch", 27, 4.6, -24, 0, CAR_COLORS[4], name="Deckauto")
        c.wedge(deck, "Rampe", (8, 4.6, 12), CF.at(27, 2.3, -8, 180), CONCRETE, "Concrete")
        p = c.producer(4)
        arch = c.model(p, "Ballonbogen")
        for x in (-14, -2):
            c.box(arch, "Bogenpfosten", x - 0.2, x + 0.2, 0.0, 6.5, -1.2, -0.8, STEEL, "Metal")
        c.box(arch, "Bogenbalken", -14.2, -1.8, 6.5, 6.9, -1.2, -0.8, STEEL, "Metal")
        for k in range(7):
            c.ball(arch, "Ballon", (-13 + k * 1.8, 7.6, -1.0), 1.4, (AMBER, TEAL, RED, WHITE)[k % 4], "SmoothPlastic",
                   deco=True)
    elif s == 3:
        c.hall(m, -34, 10, -33, -5, 10, glass=True, door=(-12, 8, 7.5), name="Showroom")
        c.annex(m, 10, 34, -33, -15, 7, SLATE, GRAPHITE, door=(22, 8, 5.5), side="W", name="Service")
        c.turntable(m, -24, -19, "compact", CAR_COLORS[0])
        c.turntable(m, -6, -19, "sport", CAR_COLORS[3], name="Drehteller_2")
        c.lift(m, 22, -24)
        c.sign(m, "AUTOHAUS", (14, 2.4), -12, 11.9, -6.1, 0, SLATE, AMBER, name="Dachschild")
        c.box(m, "Dachschildfuss", -19, -5, 10.6, 10.7, -6.5, -5.8, SLATE, "Metal", deco=True)
        c.sign(m, "SERVICE", (8, 1.6), 22, 6.0, -14.9, 0, WHITE, TEAL, name="Serviceschild")
        c.lamp(m, -31, 8, 1, 0)
        c.lamp(m, 6, 12, 0, -1)
        c.car(m, "compact", 28, 0.0, 9, 0, CAR_COLORS[2], name="Gebrauchtwagen")
        p = c.producer(1)
        gh = c.hall(p, 12, 32, -13, 1, 6, glass=True, name="Glashalle", door=None)
        c.car(gh, "sport", 22, 0.0, -6, 90, CAR_COLORS[1], name="Glashallenauto")
        p = c.producer(2)
        bb = c.model(p, "Werbetafel")
        for x in (-33, -27):
            c.box(bb, "Tafelpfosten", x - 0.3, x + 0.3, 0.0, 5.0, 6.7, 7.3, STEEL, "Metal")
        c.box(bb, "Tafel", -34, -26, 5.0, 9.5, 6.6, 7.0, BLACK, "SmoothPlastic")
        c.sign(bb, "ONLINE-ANZEIGEN", (7.6, 4.0), -30, 7.25, 7.1, 0, AMBER, BLACK, name="Anzeige")
        p = c.producer(3)
        c.rack(p, 12, 20, -32.4, -30.0, 5.0, 3, crates=False, name="Lackdepot")
        for k in range(4):
            c.cyl(p, "Lackfass", (13.5 + k * 1.8, 0.5 + 0.9, -31.2), 1.8, 1.4, "Y", CAR_COLORS[k], "Metal", deco=True)
        p = c.producer(4)
        lb = c.model(p, "Lichtband", attrs={"Anim": "neon", "Period": 2.4, "ColorB": _c3(TEAL)})
        c.box(lb, "Lichtleiste", -34, 10, 10.6, 10.9, -5.3, -5.0, AMBER, "Neon", deco=True)
        c.box(lb, "Lichtleiste_W", -34, -33.7, 10.6, 10.9, -33, -5.3, AMBER, "Neon", deco=True)
    elif s == 4:
        c.hall(m, -34, -2, -33, -5, 11, glass=True, door=(-18, 8, 8), name="Showroom")
        c.hall(m, 4, 34, -33, -11, 9, SLATE, GRAPHITE, door=(19, 9, 7), name="Servicehalle")
        c.tower(m, -2, 4, -33, -23, 24, GRAPHITE, bands=4, sign=("AUTOHAUS", 5.6, 5.0, 16))
        c.turntable(m, -24.5, -20, "sport", CAR_COLORS[0])
        pod = c.model(m, "Praesentationspodest")
        c.box(pod, "Podest", -14, -4, 0.0, 0.5, -28, -12, WHITE, "Marble")
        c.car(pod, "compact", -9, 0.5, -20, 0, CAR_COLORS[3], name="Showcar_2")
        c.lift(m, 13, -22, car="compact", paint=CAR_COLORS[2])
        c.workbench(m, 23, 32, -32.2, -30.2)
        c.tool_wall(m, 23, 32, -32.4, 6.0, 0.0, tools_y=3.0)
        c.tires(m, 30, -18, 4)
        c.tires(m, 26, -18, 2)
        c.sign(m, "SERVICE", (8, 1.6), 19, 8.0, -10.9, 0, WHITE, TEAL, name="Serviceschild")
        c.lamp(m, -31, 10, 1, 0)
        c.lamp(m, 32, 14, -1, 0)
        sp = c.part(m, "Showspot", (2, 0.4, 2), CF(-17, 10.8, -20), BLACK, "Metal", deco=True)
        c.spot(sp)
        p = c.producer(1)
        tr = c.model(p, "Probefahrtstrecke")
        c.plate(tr, "Asphalt", 6, 26, -8, 12, 0.0, 0.15, ASPHALT, "Asphalt")
        c.gy += 0.15
        c.cones(tr, [(12, -5), (20, -5), (16, 9)])
        c.gy -= 0.15
        c.car(tr, "hot_hatch", 16, 0.15, 2, 90, CAR_COLORS[4], name="Testauto")
        p = c.producer(2)
        of = c.model(p, "Finanzierungsbuero")
        c.box(of, "Bueroboden", -33, -25, 0.0, 0.3, -10.5, -6.2, WHITE, "Marble")
        c.box(of, "Buerowand", -33, -25, 0.3, 4.5, -10.5, -10.2, WHITE, "SmoothPlastic")
        c.box(of, "Buerowand_O", -25.3, -25, 0.3, 4.5, -10.2, -6.2, WHITE, "SmoothPlastic")
        c.box(of, "Schreibtisch", -32, -27, 0.3, 2.5, -9, -7.5, WOOD, "Wood")
        c.sign(of, "FINANZIERUNG", (7, 1.2), -29, 5.1, -10.35, 0, TEAL, WHITE, name="Bueroschild")
        p = c.producer(3)
        c.rack(p, 28, 33.2, -8, 4, 7.0, 3, crates=False, name="Reifenhotel")
        for zz in (-6, -2, 2):
            for yy in c.rack_tops(7.0, 3)[:2]:
                c.cyl(p, "Hotelreifen", (30.6, yy + 1.3, zz), 1.0, 2.6, "X", BLACK, "Plastic", deco=True)
        p = c.producer(4)
        c.cafe(p, -26, 2, tables=2, name="Kaffeebar")
    else:
        c.hall(m, -34, 20, -34, -6, 14, glass=True, door=(-4, 10, 9), name="Glaspalast")
        c.tower(m, 20, 34, -34, -20, 28, GRAPHITE, bands=5, sign=("AUTOHAUS", 12, 3.4, 24))
        c.neon_sign(m, "PREMIUM AUTOHAUS", -4, 14.6, -5.9, 24, 2.6, name="Dachschrift")
        c.turntable(m, -22, -17, "sedan", CAR_COLORS[0])
        c.turntable(m, -3, -17, "compact", CAR_COLORS[3], name="Drehteller_2")
        pod = c.model(m, "Praesentationspodest")
        c.box(pod, "Podest", 7, 19, 0.0, 0.5, -25, -9, WHITE, "Marble")
        c.car(pod, "sport", 13, 0.5, -17, 0, CAR_COLORS[1], name="Showcar_3")
        for x in (-22, -3, 13):
            sp = c.part(m, "Showspot", (2, 0.4, 2), CF(x, 13.8, -15), BLACK, "Metal", deco=True)
            c.spot(sp)
        c.lamp(m, -31, 14, 1, 0)
        c.lamp(m, 8, 16, 0, -1)
        for k, x in enumerate((-33, -27)):
            c.flag(m, "Fahne_%d" % (k + 1), x, 20 - k * 4, (AMBER, TEAL)[k % 2], (SLATE, WHITE)[k % 2], "AUTO")
        p = c.producer(1)
        lx = c.model(p, "Luxus_Etage")
        for x in (-32.5, -8):
            for z in (-33, -26):
                c.box(lx, "Etagenstuetze", x, x + 0.8, 0.0, 7.0, z, z + 0.8, FRAME, "Metal")
        c.box(lx, "Etage", -33, -5, 7.0, 7.6, -33.4, -24, WHITE, "Marble")
        c.box(lx, "Gelaender", -33, -5, 7.6, 8.6, -24.2, -24, STEEL, "Metal", deco=True)
        c.car(lx, "super", -19, 7.6, -28.7, 90, CAR_COLORS[4], name="Luxusauto")
        c.sign(lx, "LUXUS-ETAGE", (10, 1.6), -19, 9.4, -23.9, 0, AMBER, BLACK, name="Etagenschild")
        p = c.producer(2)
        c.turntable(p, 27, 8, "sport", CAR_COLORS[2], name="Drehbuehne", diameter=12.0)
        p = c.producer(3)
        ah = c.hall(p, 20, 34, -19, -1, 8, SLATE, GRAPHITE, door=(27, 8, 6), name="Auslieferungshalle", windows=False)
        c.car(ah, "compact", 27, 0.0, -10, 0, CAR_COLORS[3], name="Auslieferung")
        p = c.producer(4)
        fo = c.model(p, "Springbrunnen")
        c.cyl(fo, "Becken", (-27, 0.5, 6), 1.0, 8.0, "Y", CONCRETE, "Concrete")
        c.cyl(fo, "Wasser", (-27, 1.15, 6), 0.3, 7.0, "Y", (80, 160, 220), "Glass", transparency=0.3, deco=True)
        c.cyl(fo, "Brunnensaeule", (-27, 2.3, 6), 2.0, 1.2, "Y", CONCRETE, "Concrete")
        c.cyl(fo, "Fontaene", (-27, 4.3, 6), 2.0, 0.6, "Y", (170, 220, 250), "Neon", deco=True)


# ---------------------------------------------------------------- Produktion
def produktion(c, s):
    m = c.m
    if s == 1:
        c.gravel(m)
        c.hall(m, -33, -15, -33, -19, 6, GRAPHITE, SLATE, "Metal", door=(-24, 5, 4.5), name="Werkzelt",
               windows=False)
        c.pallets(m, 22, -33, 2, 2, 2, name="Paletten")
        c.forklift(m, 20, -10)
        c.barrels(m, -10, -31, 3)
        p = c.producer(1)
        c.conveyor(p, -6, 12, -24)
        p = c.producer(2)
        c.sign_post(p, "SCHICHTPLAN", -8, -10, 6, 2.0, 5.0, WHITE, TEAL, name="Schichtplan")
        p = c.producer(3)
        c.pallets(p, 26, -20, 2, 2, 3, name="Kistenlager")
        p = c.producer(4)
        c.sign_post(p, "PRODUKTION", -30, 8, 8, 2.4, 8.5, AMBER, SLATE, name="Werkslogo")
    elif s == 2:
        c.hall(m, -33, 25, -33, -5, 10, SLATE, GRAPHITE, door=(-4, 12, 8))
        c.conveyor(m, -20, 6, -22, cargo=4)
        c.robot(m, -8, -27, 0, ORANGE)
        c.pallets(m, 14, -32.3, 1, 2, 2, name="Paletten")
        c.forklift(m, 30, 2)
        c.sign(m, "PRODUKTION", (16, 2.4), -4, 9.2, -4.9, 0, AMBER, SLATE)
        c.lamp(m, 31, 12, -1, 0)
        p = c.producer(1)
        c.stamp(p, -24, -14, h=7.5)
        p = c.producer(2)
        c.conveyor(p, -20, 4, -12, name="Foerderband")
        p = c.producer(3)
        c.rack(p, 20.4, 24.2, -31, -8, 7.0, 3, name="Bauteilelager")
        p = c.producer(4)
        ch = c.model(p, "Schornstein")
        c.box(ch, "Schornsteinfuss", 27, 33, 0.0, 2.0, -33, -27, BRICK, "Brick")
        c.cyl(ch, "Schornstein", (30, 2.0 + 10, -30), 20.0, 4.0, "Y", BRICK, "Brick")
        c.cyl(ch, "Schornsteinkrone", (30, 22.4, -30), 0.8, 4.6, "Y", GRAPHITE, "Metal", deco=True)
    elif s == 3:
        c.hall(m, -34, 14, -33, -5, 11, SLATE, GRAPHITE, door=(-10, 12, 8))
        c.annex(m, 14, 34, -33, -13, 8, SLATE, GRAPHITE, door=(24, 8, 6), side="W")
        c.conveyor(m, -30, -4, -24, cargo=4)
        c.stamp(m, 4, -26)
        c.robot(m, -18, -29, 0, ORANGE)
        c.robot(m, -8, -18, 180, ORANGE, name="Roboter_2")
        c.sign(m, "PRODUKTION", (16, 2.4), -10, 10.2, -4.9, 0, AMBER, SLATE)
        silo = c.model(m, "Silo")
        c.cyl(silo, "Silo", (-30, 0.5 + 6, 6), 12.0, 5.0, "Y", STEEL, "Metal")
        c.box(silo, "Silofuss", -32.5, -27.5, 0.0, 0.5, 3.5, 8.5, GRAPHITE, "Metal")
        c.cyl(silo, "Silodeckel", (-30, 12.9, 6), 0.8, 5.4, "Y", GRAPHITE, "Metal", deco=True)
        c.forklift(m, 24, 2)
        c.lamp(m, 10, 12, 0, -1)
        p = c.producer(1)
        c.robot(p, 24, -27, 90, ORANGE, name="Schweissroboter", spark=True)
        c.robot(p, 30, -27, 90, ORANGE, name="Schweissroboter_2", spark=True)
        c.conveyor(p, 16, 32, -20, name="Schweissband", cargo=3)
        p = c.producer(2)
        cell = c.model(p, "Roboterzelle")
        c.box(cell, "Zellenboden", 2, 12, 0.0, 0.3, -14, -6.2, YELLOW, "DiamondPlate")
        for x in (2, 11.7):
            c.box(cell, "Gitter", x, x + 0.3, 0.3, 3.5, -14, -6.2, TRUSS, "Metal", deco=True)
        c.box(cell, "Gitter_N", 2.3, 11.7, 0.3, 3.5, -14, -13.7, TRUSS, "Metal", deco=True)
        with c.raised(0.3):
            c.robot(cell, 7, -10, 90, TEAL, name="Zellenroboter")
        p = c.producer(3)
        c.rack(p, 15.4, 21.6, -32.4, -29.4, 6.0, 3, crates=False, name="Lackdepot")
        for k in range(4):
            c.cyl(p, "Lackfass", (16.6 + k * 1.3, c.rack_tops(6.0, 3)[0] + 0.9, -30.9), 1.8, 1.0, "Y", CAR_COLORS[k],
                  "Metal", deco=True)
        p = c.producer(4)
        tp = c.model(p, "Testparcours")
        c.plate(tp, "Asphaltband", 16, 34, -9, -5, 0.0, 0.15, ASPHALT, "Asphalt")
        c.plate(tp, "Asphaltband_2", 16, 34, 8, 12, 0.0, 0.15, ASPHALT, "Asphalt")
        c.plate(tp, "Asphaltband_O", 30, 34, -5, 8, 0.0, 0.15, ASPHALT, "Asphalt")
        c.cones(tp, [(19, -2), (19, 5), (27, 1.5)])
        c.sign_post(tp, "TESTPARCOURS", 20, 14, 6, 1.4, 5.0, WHITE, TEAL, name="Parcoursschild")
    elif s == 4:
        c.hall(m, -34, -2, -33, -5, 12, SLATE, GRAPHITE, door=(-18, 12, 8.5))
        c.hall(m, 2, 34, -33, -11, 10, SLATE, GRAPHITE, door=(18, 10, 7.5), name="Halle_2")
        tw = c.model(m, "Stahlturm")
        for x in (-1.8, 1.4):
            for z in (-32.8, -27.4):
                c.box(tw, "Turmstiel", x, x + 0.4, 0.0, 24.0, z, z + 0.4, TRUSS, "Metal")
        for yy in (6, 12, 18):
            c.box(tw, "Turmpodest", -1.4, 1.4, yy, yy + 0.4, -32.4, -27.4, TRUSS, "Metal", deco=True)
        c.box(tw, "Turmplattform", -2.4, 2.4, 24.0, 24.6, -33.4, -26.4, GRAPHITE, "Metal")
        b = c.ball(tw, "Warnlicht", (0, 25.2, -30), 1.2, RED, "Neon", deco=True)
        set_attrs(b, {"Anim": "beacon", "Period": 1.2})
        c.conveyor(m, -31, -7, -24, cargo=4)
        c.stamp(m, -26, -12)
        c.robot(m, -20, -30, 0, ORANGE)
        c.robot(m, -10, -30, 0, ORANGE, name="Roboter_2")
        c.robot(m, -10, -18, 180, ORANGE, name="Roboter_3")
        c.sign(m, "PRODUKTION", (16, 2.4), -18, 11.2, -4.9, 0, AMBER, SLATE)
        c.pallets(m, 27, -4, 2, 1, 2, name="Paletten")
        c.forklift(m, 8, -4)
        c.lamp(m, -31, 13, 1, 0)
        c.lamp(m, 32, 14, -1, 0)
        sp = c.part(m, "Hallenspot", (2, 0.4, 2), CF(-18, 11.8, -20), BLACK, "Metal", deco=True)
        c.spot(sp)
        p = c.producer(1)
        ls = c.model(p, "Lackierstrasse")
        c.box(ls, "Kabinenboden", 4, 24, 0.0, 0.3, -31, -23, (60, 66, 72), "Metal")
        c.box(ls, "Kabinenrueckwand", 4, 24, 0.3, 6.5, -31, -30.6, WHITE, "Metal")
        c.box(ls, "Kabinendach", 4, 24, 6.5, 6.9, -31, -23, GRAPHITE, "Metal")
        for x in (4, 23.6):
            c.box(ls, "Kabinenseite", x, x + 0.4, 0.3, 6.5, -30.6, -23, WHITE, "Metal")
        with c.raised(0.3):
            c.conveyor(ls, 5, 23, -27, top=1.4, name="Lackband", cargo=3)
        lp = c.box(ls, "Kabinenlicht", 8, 20, 6.1, 6.5, -27.3, -26.7, WHITE, "Neon", deco=True)
        c.light(lp, 14, 0.8, WHITE)
        p = c.producer(2)
        tr = c.model(p, "Lieferwagen")
        c.box(tr, "Fahrerhaus", 18.5, 25.5, 2.0, 5.5, 6, 10, TEAL, "Metal")
        c.box(tr, "Frontscheibe", 19, 25, 3.2, 5.0, 10, 10.2, GLASS, "Glass", transparency=0.3, deco=True)
        c.box(tr, "Koffer", 18.5, 25.5, 2.0, 7.0, -6, 5.8, WHITE, "Metal")
        c.sign(tr, "JUST-IN-TIME", (10, 2.0), 25.6, 4.0, 0, -90, TEAL, WHITE, name="Kofferschild")
        for x in (19.2, 24.8):
            for z in (-3.5, 4.5, 8.5):
                c.cyl(tr, "Rad", (x, 1.0, z), 0.8, 2.0, "X", BLACK, "Plastic", deco=True)
        p = c.producer(3)
        c.rack(p, 26, 33.2, -31, -13, 8.5, 4, name="Hochregallager")
        p = c.producer(4)
        kt = c.hall(p, -34, -22, 0, 8, 5, WHITE, GRAPHITE, "SmoothPlastic", door=None, name="Kantine", frame=True,
                    windows=False)
        c.box(kt, "Kantinenfenster", -33, -23, 1.5, 4.0, 8, 8.2, GLASS, "Glass", transparency=0.3, deco=True)
        c.sign(kt, "KANTINE", (6, 1.2), -28, 6.2, 8.1, 0, WHITE, TEAL, name="Kantinenschild")
    else:
        c.hall(m, -34, 20, -34, -8, 14, SLATE, GRAPHITE, door=(-8, 14, 9))
        # Sheddach: 6 Keile auf dem Dach (Schräge entlang X)
        for k in range(6):
            x0 = -34 + k * 9
            c.wedge(m, "Sheddach", (26, 3.0, 9), CF.at(x0 + 4.5, 14.6 + 1.5, -21, 90), GRAPHITE, "Metal", deco=True)
        for x in (-28, -18):
            c.cyl(m, "Schornstein", (x, 17.6 + 6, -30), 12.0, 2.6, "Y", BRICK, "Brick", deco=True)
        c.conveyor(m, -31, -9, -26, cargo=4)
        c.conveyor(m, -31, -9, -16, cargo=4, name="Montageband_2")
        c.stamp(m, 4, -28)
        c.robot(m, -26, -31.5, 0, ORANGE)
        c.robot(m, -14, -31.5, 0, ORANGE, name="Roboter_2")
        c.robot(m, -20, -21, 0, ORANGE, name="Roboter_3")
        c.neon_sign(m, "AUTOWERK", -8, 14.6, -7.9, 20, 2.6, name="Dachschrift")
        for x in (-20, 4):
            sp = c.part(m, "Hallenspot", (2, 0.4, 2), CF(x, 13.8, -22), BLACK, "Metal", deco=True)
            c.spot(sp)
        c.lamp(m, -31, 14, 1, 0)
        c.lamp(m, 10, 18, 0, -1)
        for k, x in enumerate((-33, -27)):
            c.flag(m, "Fahne_%d" % (k + 1), x, 20 - k * 4, (AMBER, TEAL)[k % 2], (SLATE, WHITE)[k % 2], "WERK")
        c.forklift(m, 14, 6)
        p = c.producer(1)
        em = c.model(p, "Endmontage")
        c.conveyor(em, -4, 16, -16, w=9.6, top=1.6, name="Endmontageband", anim=False)
        c.car(em, "compact", 6, 1.6, -16, 90, (240, 240, 240), name="Rohkarosse")
        c.robot(em, 0, -23.5, 180, TEAL, name="Montageroboter")
        c.robot(em, 14, -23.5, 180, TEAL, name="Montageroboter_2")
        p = c.producer(2)
        ga = c.model(p, "Portalroboter")
        for x in (-31, -9.4):
            c.box(ga, "Portalstiel", x, x + 0.4, 0.0, 9.0, -11.4, -11, TRUSS, "Metal")
        c.box(ga, "Portalbruecke", -31, -9, 9.0, 9.8, -11.6, -10.8, YELLOW, "Metal")
        c.box(ga, "Portalarm", -21, -19.6, 3.0, 9.0, -11.6, -10.8, YELLOW, "Metal")
        c.cyl(ga, "Portalgreifer", (-20.3, 2.7, -11.2), 0.6, 1.4, "Y", STEEL, "Metal", deco=True)
        p = c.producer(3)
        vh = c.model(p, "Verladehof")
        c.plate(vh, "Hofplatte", 22, 34, -34, -2, 0.0, 0.15, ASPHALT, "Asphalt")
        c.container(vh, 23, 33, -33, -25, 6, (60, 90, 140), 0.15)
        c.container(vh, 23, 33, -24, -16, 6, RED, 0.15, name="Container_2")
        c.container(vh, 23, 33, -33, -25, 6, AMBER, 6.15, name="Container_3")
        with c.raised(0.15):
            c.pallets(vh, 24, -12, 2, 2, 2, name="Verladepaletten")
        p = c.producer(4)
        at = c.model(p, "Aussichtsturm")
        for x in (25.5, 30.1):
            for z in (3.5, 8.1):
                c.box(at, "Turmstiel", x, x + 0.4, 0.0, 22.0, z, z + 0.4, TRUSS, "Metal")
        for yy in (6, 12, 18):
            c.box(at, "Turmpodest", 25.9, 30.1, yy, yy + 0.4, 3.9, 8.1, TRUSS, "Metal", deco=True)
        c.box(at, "Kanzel", 24.5, 31.5, 22.0, 25.0, 2.5, 9.5, TEAL, "Metal")
        c.box(at, "Kanzelfenster", 25, 31, 22.8, 24.4, 9.5, 9.7, GLASS, "Glass", transparency=0.3, deco=True)
        c.box(at, "Kanzeldach", 24.2, 31.8, 25.0, 25.5, 2.2, 9.8, GRAPHITE, "Metal", deco=True)


# ---------------------------------------------------------------- Schrottplatz
def schrottplatz(c, s):
    m = c.m
    if s == 1:
        c.gravel(m)
        c.fence(m, -34, 34, -33.6, 4.0)
        c.hall(m, -33, -25, -33, -27, 5, WOOD, SLATE, "WoodPlanks", door=(-29, 3, 4), name="Wachhaeuschen",
               windows=False)
        c.heap(m, -12, -24, 5.0, 4.2)
        c.heap(m, 20, -26, 6.0, 5.0)
        c.car(m, "sedan", 4, 0.0, -8, 0, RUST, name="Wrack")
        c.tires(m, 32, -20, 3)
        p = c.producer(1)
        c.press(p, -16, -8, car="compact")
        p = c.producer(2)
        c.workbench(p, -33, -27, -24.5, -22.5)
        c.tool_wall(p, -33, -27, -25.0, 3.0, 0.0, name="Brechstangen")
        p = c.producer(3)
        c.heap(p, 24, -8, 7.0, 6.5, name="Schrottberg")
        p = c.producer(4)
        dh = c.model(p, "Wachhund_Huette")
        c.box(dh, "Huette", 26, 30, 0.0, 2.4, 6, 10, WOOD, "WoodPlanks")
        c.wedge(dh, "Huettendach", (4.4, 1.6, 2.2), CF.at(28, 2.4 + 0.8, 8 - 1.1, 0), RED, "Slate", deco=True)
        c.wedge(dh, "Huettendach_2", (4.4, 1.6, 2.2), CF.at(28, 2.4 + 0.8, 8 + 1.1, 180), RED, "Slate", deco=True)
        c.cyl(dh, "Napf", (24.5, 0.2, 8), 0.4, 1.2, "Y", STEEL, "Metal", deco=True)
    elif s == 2:
        c.hall(m, -33, 15, -33, -9, 9, GRAPHITE, SLATE, "Metal", door=(-9, 14, 7.5), name="Zerlegehalle")
        c.press(m, -20, 0, w=16, d=9, h=17, car="compact")
        c.workbench(m, 2, 12, -32.2, -30.2)
        c.tool_wall(m, 2, 12, -32.4, 6.0, 0.0, tools_y=3.0)
        c.heap(m, -20, -22, 5.0, 4.0, name="Hallenhaufen")
        c.barrels(m, -30, -30, 2)
        c.sign(m, "SCHROTTPLATZ", (16, 2.2), -9, 8.2, -8.9, 0, YELLOW, GRAPHITE)
        c.heap(m, 26, 2, 5.0, 4.5)
        c.fence(m, 15, 34, -33.6, 4.0)
        c.lamp(m, 20, 14, -1, 0)
        p = c.producer(1)
        c.crane(p, 25, -18, name="Greifkran")
        p = c.producer(2)
        c.forklift(p, -6, 8)
        p = c.producer(3)
        c.container(p, 18, 26, -33, -27, 8, (60, 90, 140))
        c.container(p, 26.5, 34, -33, -27, 8, RED, name="Container_2")
        p = c.producer(4)
        c.tires(p, -30, 8, 4)
        c.tires(p, -26, 8, 3)
        c.tires(p, -30, 12, 2)
    elif s == 3:
        c.hall(m, -34, 8, -33, -7, 10, GRAPHITE, SLATE, "Metal", door=(-12, 14, 8), name="Zerlegehalle")
        c.annex(m, 8, 34, -33, -15, 7, GRAPHITE, SLATE, door=(20, 8, 5.5), side="W", material="Metal")
        c.press(m, -16, -0.5, w=16, d=9, h=17, car="compact")
        c.workbench(m, -2, 6, -32.2, -30.2)
        c.tool_wall(m, -2, 6, -32.4, 6.0, 0.0, tools_y=3.0)
        c.heap(m, -20, -22, 6.0, 5.0, name="Hallenhaufen")
        c.heap(m, -6, -20, 4.0, 3.5, name="Hallenhaufen_2")
        c.sign(m, "SCHROTTPLATZ", (16, 2.2), -12, 9.2, -6.9, 0, YELLOW, GRAPHITE)
        c.crane(m, 24, -2, jib=6.0)
        c.heap(m, 20, 10, 5.0, 4.5)
        c.lamp(m, 32, 20, -1, 0)
        p = c.producer(1)
        sh = c.model(p, "Shredder")
        c.box(sh, "Shreddergehaeuse", 10, 20, 0.0, 4.0, -31, -23, TRUSS, "Metal")
        c.wedge(sh, "Trichter", (10, 2.4, 8), CF.at(15, 5.2, -27, 0), STEEL, "Metal", deco=True)
        c.conveyor(sh, 21, 31, -27, top=2.4, name="Shredderband", cargo=3)
        p = c.producer(2)
        c.crane(p, -28, 10, jib=4.5, mast_h=12.0, name="Magnetkran_2", speed=-4.0)
        p = c.producer(3)
        c.container(p, 27, 34, 7, 12, 6, (60, 90, 140), name="Teilecontainer")
        c.container(p, 27, 34, 7, 12, 6, ORANGE, 6.0, name="Teilecontainer_2")
        p = c.producer(4)
        at = c.model(p, "Autoturm")
        c.car(at, "sedan", 4, 0.0, 6, 0, RUST, name="Wrack_1")
        c.car(at, "compact", 4, 4.9, 6, 0, RUST2, name="Wrack_2")
    elif s == 4:
        c.hall(m, -34, -2, -33, -7, 11, GRAPHITE, SLATE, "Metal", door=(-18, 14, 8), name="Zerlegehalle")
        c.hall(m, 2, 34, -33, -15, 9, GRAPHITE, SLATE, "Metal", door=(18, 10, 7), name="Sortierhalle")
        c.press(m, -20, 0, w=16, d=9, h=17, car="compact")
        sh = c.model(m, "Shredder")
        c.box(sh, "Shreddergehaeuse", -33, -27, 0.0, 5.0, -14, -8, TRUSS, "Metal")
        c.wedge(sh, "Trichter", (6, 3.0, 6), CF.at(-30, 6.5, -11, 0), STEEL, "Metal", deco=True)
        c.heap(m, -20, -22, 6.0, 5.0, name="Hallenhaufen")
        c.crane(m, 0, -30, mast_h=26.0, jib=10.0, name="Turmkran", speed=3.0, magnet_y=13.0)
        c.heap(m, 0, 8, 6.0, 5.5)
        c.heap(m, 8, -9, 5.0, 4.0, name="Schrotthaufen_2")
        c.sign(m, "SCHROTTPLATZ", (16, 2.2), -18, 10.2, -6.9, 0, YELLOW, GRAPHITE)
        c.lamp(m, -31, 14, 1, 0)
        c.lamp(m, 32, 12, -1, 0)
        sp = c.part(m, "Hallenspot", (2, 0.4, 2), CF(-18, 10.8, -20), BLACK, "Metal", deco=True)
        c.spot(sp)
        p = c.producer(1)
        so = c.model(p, "Sortieranlage")
        c.conveyor(so, 4, 30, -28, name="Sortierband", cargo=4)
        c.conveyor(so, 4, 30, -20, name="Sortierband_2", cargo=4)
        for k, x in enumerate((6, 14, 22)):
            c.box(so, "Sortierbox", x, x + 5, 0.0, 3.0, -18.3, -16.0, (RUST, (60, 90, 140), AMBER)[k], "Metal")
        p = c.producer(2)
        fs = c.model(p, "Foerderschnecke")
        c.box(fs, "Schneckentrichter", 6, 12, 0.0, 2.0, -2, 2, TRUSS, "Metal")
        c.cyl(fs, "Schneckenrohr", (15.5, 3.0, 0), 7.0, 1.6, "X", STEEL, "Metal")
        c.box(fs, "Schneckenfuss", 18, 19, 0.0, 2.2, -0.5, 0.5, TRUSS, "Metal")
        c.box(fs, "Schneckenfuss_2", 11, 12, 2.0, 2.2, -0.5, 0.5, TRUSS, "Metal")
        p = c.producer(3)
        c.hall(p, 20, 34, -12, 2, 6, GRAPHITE, SLATE, "Metal", door=(27, 8, 5), name="Lagerhalle", windows=False)
        p = c.producer(4)
        gw = c.model(p, "Graffiti_Wand")
        c.box(gw, "Mauer", 6, 22, 0.0, 5.0, 10, 11, CONCRETE, "Concrete")
        for k in range(6):
            c.box(gw, "Graffiti", 7 + k * 2.5, 8.6 + k * 2.5, 1.0 + (k % 2) * 1.2, 3.4 + (k % 2) * 0.8, 11, 11.1,
                  (AMBER, TEAL, RED, GREEN, WHITE, ORANGE)[k], "Neon", deco=True)
        c.sign(gw, "SCHROTT-ART", (8, 1.2), 14, 4.2, 11.2, 0, WHITE, BLACK, name="Graffitischild")
    else:
        c.hall(m, -34, 18, -34, -8, 12, GRAPHITE, SLATE, "Metal", door=(-8, 14, 9), name="Recyclinghalle")
        c.press(m, 4, -1, w=16, d=9, h=17, car="compact")
        sh = c.model(m, "Shredder")
        c.box(sh, "Shreddergehaeuse", 4, 14, 0.0, 5.0, -33, -25, TRUSS, "Metal")
        c.wedge(sh, "Trichter", (10, 3.0, 8), CF.at(9, 6.5, -29, 0), STEEL, "Metal", deco=True)
        c.conveyor(m, 4, 16, -18, name="Sortierband", cargo=3)
        c.heap(m, -22, -24, 6.0, 5.0, name="Hallenhaufen")
        c.heap(m, -8, -26, 4.0, 3.5, name="Hallenhaufen_2")
        c.crane(m, 24, -24, mast_h=20.0, jib=8.0, name="Turmkran", speed=3.0, magnet_y=14.0)
        c.heap(m, 8, 10, 5.0, 4.5)
        c.heap(m, 22, 6, 4.0, 3.5, name="Schrotthaufen_2")
        c.neon_sign(m, "RECYCLING", -8, 12.6, -7.9, 18, 2.6, name="Dachschrift", color=YELLOW)
        for x in (-20, 6):
            sp = c.part(m, "Hallenspot", (2, 0.4, 2), CF(x, 11.8, -22), BLACK, "Metal", deco=True)
            c.spot(sp)
        c.lamp(m, -31, 14, 1, 0)
        c.lamp(m, 12, 16, 0, -1)
        for k, x in enumerate((-33, -27)):
            c.flag(m, "Fahne_%d" % (k + 1), x, 20 - k * 4, (YELLOW, GRAPHITE)[k % 2], (BLACK, YELLOW)[k % 2],
                   "SCHROTT")
        p = c.producer(1)
        of = c.model(p, "Schmelzofen")
        c.box(of, "Ofenkorpus", 22, 34, 0.0, 7.0, -12, -2, BRICK, "Brick")
        c.box(of, "Ofenmaul", 26, 30, 1.0, 4.0, -2, -1.8, (255, 140, 40), "Neon", deco=True)
        c.cyl(of, "Ofenschlot", (28, 7.0 + 6, -8), 12.0, 3.0, "Y", GRAPHITE, "Metal")
        lp = c.box(of, "Glut", 26.5, 29.5, 4.0, 4.3, -1.8, -1.2, (255, 140, 40), "Neon", deco=True)
        c.light(lp, 16, 1.0, (255, 150, 60))
        p = c.producer(2)
        lc = c.model(p, "Laserschneider")
        c.box(lc, "Lasertisch", -4, 4, 0.0, 2.0, -24, -18, TRUSS, "Metal")
        for x in (-4, 3.6):
            c.box(lc, "Laserportal", x, x + 0.4, 2.0, 5.0, -21.4, -20.6, YELLOW, "Metal")
        c.box(lc, "Laserbruecke", -4, 4, 5.0, 5.6, -21.6, -20.4, YELLOW, "Metal")
        c.box(lc, "Laserkopf", -0.5, 0.5, 3.0, 5.0, -21.4, -20.6, STEEL, "Metal", deco=True)
        b = c.ball(lc, "Laserstrahl", (0, 2.4, -21), 0.8, RED, "Neon", deco=True)
        set_attrs(b, {"Anim": "beacon", "Period": 0.5})
        p = c.producer(3)
        vr = c.model(p, "Verladerampe")
        c.box(vr, "Rampe", -34, -22, 0.0, 1.6, -8, 0, CONCRETE, "Concrete")
        c.wedge(vr, "Auffahrt", (12, 1.6, 6), CF.at(-28, 0.8, 3, 180), CONCRETE, "Concrete")
        c.container(vr, -33, -23, -7, -1, 4, (60, 90, 140), 1.6, name="Rampencontainer")
        c.container(vr, -33, -23, -7, -1, 4, RED, 5.6, name="Rampencontainer_2")
        tr = c.model(vr, "Lastwagen")
        c.box(tr, "Fahrerhaus", -20, -13, 2.0, 5.5, 6, 10, ORANGE, "Metal")
        c.box(tr, "Frontscheibe", -19.5, -13.5, 3.2, 5.0, 10, 10.2, GLASS, "Glass", transparency=0.3, deco=True)
        c.box(tr, "Mulde", -20, -13, 2.0, 5.0, -6, 5.8, GRAPHITE, "Metal")
        for x in (-19.3, -13.7):
            for z in (-3, 5, 8):
                c.cyl(tr, "Rad", (x, 1.0, z), 0.8, 2.0, "X", BLACK, "Plastic", deco=True)
        p = c.producer(4)
        c.neon_sign(p, "SCHROTT & MEHR", 4, 12.6, -24, 14, 2.4, name="Leuchtreklame", color=YELLOW)


BUILDERS = {"werkstatt": werkstatt, "autohaus": autohaus, "produktion": produktion, "schrottplatz": schrottplatz}


# ---------------------------------------------------------------- Aufbau
def build_stage(lib, parent, typ, stage):
    m = lib.model(parent, "Stage_%d" % stage, attrs={"TycoonType": typ, "TycoonStage": stage})
    hidden = lib.folder(m, "Hidden")
    c = Ctx(lib, m, hidden, typ, stage)
    build_fixed(c, typ, stage)
    BUILDERS[typ](c, stage)
    return m


def build(tree, lib):
    """ServerStorage.TycoonTemplates.<typ>.Stage_1..5 (ersetzt einen vorhandenen Ordner)."""
    root = tree.getroot()
    ss = next(i for i in root.findall("Item") if i.get("class") == "ServerStorage")
    old = child(ss, NAME)
    if old is not None:
        ss.remove(old)
    folder = lib.item(ss, "Folder", NAME)
    set_attrs(folder, {"Version": "3.0"})
    for typ in TYPES:
        tf = lib.folder(folder, typ)
        for s in range(1, MAX_STAGE + 1):
            with lib.section("Tycoon-Vorlage %s %d" % (typ, s)):
                build_stage(lib, tf, typ, s)
    return folder


def templates_of(tree):
    """{(typ, stage): Model} der gebauten Vorlagen (leer, wenn keine da sind)."""
    root = tree.getroot()
    ss = next((i for i in root.findall("Item") if i.get("class") == "ServerStorage"), None)
    folder = child(ss, NAME) if ss is not None else None
    out = {}
    if folder is None:
        return out
    for tf in children(folder):
        for st in children(tf):
            nm = name_of(st)
            if nm.startswith("Stage_"):
                out[(name_of(tf), int(nm[6:]))] = st
    return out
