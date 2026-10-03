"""Vorlagen der Open-World-Gebäude (PHASE4_CONTRACT §7): ServerStorage.OWBuildings.<name>

  baustelle            Bauzaun, Kran (Anim=turntable), Sandhaufen, Paletten, Bautafel mit SurfaceGui "Countdown"
                       (TextLabel "Countdown" - OWService schreibt die Restzeit hinein); Grundfläche 18 x 14
  autohaus_1..4        Verkaufsstand -> Glaspavillon mit Auto -> Showroom mit Dachausstellung -> + Pylon mit
                       Drehlogo, Neon, Licht; Grundfläche 20 x 14
  produktion_1..4      Montageschuppen mit Band -> Halle mit Roboter -> + Stanze, Schornstein -> + Anbau,
                       Karosserie auf dem Band, Neon, Licht; Grundfläche 24 x 16
  schrottplatz_1..4    Kieshof mit Zaun, Haufen, Container -> + Magnetkran (Anim=turntable) -> + Schrottpresse
                       (Anim=press) -> + Büro, Neon, Licht; Grundfläche 18 x 14

Konventionen (checks.py ow_checks, OWService.place):
* Jede Vorlage ist ein Model mit PrimaryPart "Root" (unsichtbar, CanCollide false, 1 x 1 x 1) bei (0, ROOT_Y, 0),
  Attribute OWType, OWStage, Width, Depth. Der Boden der Vorlage liegt auf Y 0, die Front zeigt nach +Z.
  OWService setzt das Model mit PivotTo auf Plot.OWAnchors.<typ> (Anker 0.5 über der Hof-Oberseite, plots.py).
* Alle Teile verankert, innerhalb X ±Width/2, Z ±Depth/2 und Y 0..MAX_H; Budget BUDGET (Parts, Lichter);
  keine AABB-Überschneidungen (Pierce-Teile ausgenommen), kein Z-Fighting, nichts schwebend; bewegte Animationen
  nicht verschachtelt; drehende Modelle (turntable) überstreichen keine anderen Teile.
* Anim-Attribute wie in der Stadt (CityClient): press, turntable, door, neon, flag, beacon; Förderband/Stanze tragen
  TycoonAnim (conveyor, stamp) wie die Tycoon-Vorlagen. Die Klone liegen in workspace.PlayerWorkshops.Plot_<UserId>.
  OWBuildings - der Client muss diesen Ordner wie City.Animated beobachten, damit sie sich bewegen.
Gebaut wird in jedem Place (Grundstück gibt es überall); Zählung in lib.section("OW-Vorlage <name>").
"""
from .lib import (CF, AMBER, APRON, BLACK, FRAME, GLASS, GRAPHITE, LAMP, RED, SLATE, STEEL, TEAL, TRUSS, WHITE,
                  child, children, name_of, set_attrs)
from .plots import OW_ANCHORS, OW_TYPES
from .tycoon_templates import CONCRETE, Ctx, GRAVEL, GREEN, ORANGE, RUST, WOOD, YELLOW, _c3

NAME = "OWBuildings"
ROOT_Y = 0.5
BUDGET = (250, 4)             # Parts, Lichter je Vorlage
MAX_H = 18.0
STAGES = 4
SITE_FOOTPRINT = (18.0, 14.0)
SAND = (196, 170, 120)
CREAM = (224, 214, 190)
BLUE = (60, 90, 140)
ANIM_KINDS = {"press", "turntable", "door", "neon", "flag", "beacon"}
TYCOON_ANIM_KINDS = {"conveyor", "stamp"}
MOVING = {"press", "turntable", "door", "flag", "conveyor", "stamp"}


def template_names():
    out = ["baustelle"]
    for typ in OW_TYPES:
        out += ["%s_%d" % (typ, s) for s in range(1, STAGES + 1)]
    return out


def footprint(name):
    """(Breite X, Tiefe Z) der Vorlage"""
    if name == "baustelle":
        return SITE_FOOTPRINT
    typ = name.rsplit("_", 1)[0]
    return OW_ANCHORS[typ][3], OW_ANCHORS[typ][4]


class OwCtx(Ctx):
    """Bau-Kontext wie bei den Tycoon-Vorlagen, Lichtdeckel BUDGET[1], Grundfläche w x d (Mitte 0/0)."""

    def __init__(self, lib, model, w, d):
        Ctx.__init__(self, lib, model, None, "ow", 0)
        self.w, self.d = w, d

    def light_ok(self):
        if self.nlights >= BUDGET[1]:
            return False
        self.nlights += 1
        return True

    def light(self, part, range_=22, brightness=0.8, color=LAMP):
        if not self.light_ok():
            return None
        return self.lib.point_light(part, range_, brightness, color)

    def spot(self, part, range_=26, brightness=1.2, angle=70):
        if not self.light_ok():
            return None
        return self.lib.spot_light(part, range_, brightness, (255, 244, 230), angle, "Bottom", False)

    def neon_sign(self, parent, text, x, bottom, z, w, h=2.2, yaw=0, name="Neonschrift", color=AMBER):
        """Leuchtschrift (Anim=neon) wie Ctx.neon_sign, aber gy nur einmal (Röhren liegen an der Tafel an;
        untere Röhre steht auf bottom)."""
        m = self.model(parent, name, attrs={"Anim": "neon", "Period": 3.0, "ColorB": _c3(TEAL)})
        y = bottom + 0.25 + h / 2
        cf = CF.at(x, y + self.gy, z, yaw)
        self.lib.sign(m, text, (w, h), cf, color, BLACK, name="Leuchtschild", bolts=False)
        for sy in (-1, 1):
            self.lib.part(m, "Neonroehre", (w, 0.25, 0.2), cf * CF(0, sy * (h / 2 + 0.125), 0), color, "Neon",
                          deco=True)
        return m

    def base(self, parent, color=CONCRETE, material="Concrete", name="Bodenplatte"):
        hw, hd = self.w / 2, self.d / 2
        p = self.plate(parent, name, -hw, hw, -hd, hd, 0.0, 0.2, color, material)
        self.gy = 0.2
        return p

    def post_fence(self, parent, x0, x1, z0, z1, h=3.0, color=WOOD, gap=None, name="Zaun", step=6.0):
        """Pfosten (0.5) + 2 Riegel zwischen den Pfosten um das Rechteck; Eckpfosten gehören zu den X-Seiten.
        gap = (xa, xb) Lücke in der Vorderseite (+Z): dort entfallen Pfosten und Riegel."""
        m = self.model(parent, name)
        half = 0.25
        for z in (z0, z1):
            n = max(2, int(round((x1 - x0) / step)) + 1)
            xs = [x0 + (x1 - x0) * k / (n - 1) for k in range(n)]
            front = z == z1 and gap is not None
            for px in xs:
                if front and gap[0] < px < gap[1]:
                    continue
                self.box(m, "Pfosten", px - half, px + half, 0.0, h + 0.3, z - half, z + half, GRAPHITE, "Metal")
            for a, b in zip(xs, xs[1:]):
                if front and gap[0] < (a + b) / 2 < gap[1]:
                    continue
                for ry in (0.9, h - 0.6):
                    self.box(m, "Riegel", a + half, b - half, ry, ry + 0.4, z - 0.1, z + 0.1, color, "WoodPlanks",
                             deco=True)
        for x in (x0, x1):
            n = max(2, int(round((z1 - z0) / step)) + 1)
            zs = [z0 + (z1 - z0) * k / (n - 1) for k in range(n)]
            for pz in zs[1:-1]:
                self.box(m, "Pfosten", x - half, x + half, 0.0, h + 0.3, pz - half, pz + half, GRAPHITE, "Metal")
            for a, b in zip(zs, zs[1:]):
                for ry in (0.9, h - 0.6):
                    self.box(m, "Riegel", x - 0.1, x + 0.1, ry, ry + 0.4, a + half, b - half, color, "WoodPlanks",
                             deco=True)
        return m

    def board(self, parent, title, lines, x, z, w=7.0, h=3.0, top=5.5, yaw=0, name="Bautafel", bg=SLATE,
              gui_name="Countdown"):
        """Tafel auf 2 Pfosten mit SurfaceGui gui_name: TextLabel "Title" + TextLabels lines (Name, Text)."""
        m = self.model(parent, name)
        cf = CF.at(x, 0, z, yaw)
        for sx in (-w / 2 + 0.4, w / 2 - 0.4):
            p = cf.point((sx, 0, -0.4))
            self.box(m, "Tafelpfosten", p[0] - 0.25, p[0] + 0.25, 0.0, top, p[2] - 0.25, p[2] + 0.25, STEEL, "Metal")
        plate = self.part(m, "Tafel", (w, h, 0.3), cf * CF(0, top - h / 2, 0), bg, "SmoothPlastic", collide=False)
        gui = self.lib.surface_text(plate, None, face="Back", name=gui_name, canvas=(int(w * 50), int(h * 50)))
        n = len(lines) + 1
        self.lib.text_label(gui, title, AMBER, "GothamBlack", "Title", None, (0.92, 0.9 / n), (0.04, 0.04))
        for k, (nm, txt) in enumerate(lines):
            self.lib.text_label(gui, txt, WHITE, "GothamBold", nm, None, (0.92, 0.9 / n),
                                (0.04, 0.04 + (k + 1) * 0.92 / n))
        return m

    def roof_rail(self, parent, x0, x1, z0, z1, y, h=1.2, name="Dachgelaender"):
        m = self.model(parent, name)
        t = 0.15
        self.box(m, "Gelaender", x0, x1, y, y + h, z0, z0 + t, STEEL, "Metal", deco=True)
        self.box(m, "Gelaender", x0, x1, y, y + h, z1 - t, z1, STEEL, "Metal", deco=True)
        self.box(m, "Gelaender", x0, x0 + t, y, y + h, z0 + t, z1 - t, STEEL, "Metal", deco=True)
        self.box(m, "Gelaender", x1 - t, x1, y, y + h, z0 + t, z1 - t, STEEL, "Metal", deco=True)
        return m


# ---------------------------------------------------------------- Baustelle
def baustelle(c):
    m = c.m
    hw, hd = c.w / 2, c.d / 2
    c.base(m, GRAVEL, "Pebble", "Kies")
    c.post_fence(m, -hw + 0.4, hw - 0.4, -hd + 0.4, hd - 0.4, h=3.2, color=YELLOW, gap=(-2.5, 2.5), name="Bauzaun")
    # Kran in der Mitte (Anim=turntable): Schwenkring Radius ~5.5 ab Magnet-Unterkante 5.0 freihalten
    c.crane(m, 0.0, 0.0, mast_h=11.0, jib=4.5, cab=True, name="Baukran", speed=4.0, magnet_y=5.0)
    # Sandhaufen, Paletten, Betonmischer, Pylonen (alle niedriger als der Magnet)
    c.heap(m, 5.5, -3.5, 2.2, 2.4, colors=(SAND, SAND, SAND), name="Sandhaufen")
    c.pallets(m, -8.0, -6.0, cols=2, rows=1, high=1, name="Baumaterial")
    mixer = c.model(m, "Mischer")
    c.box(mixer, "Gestell", -7.5, -4.5, 0.0, 1.0, 2.0, 4.6, GRAPHITE, "Metal")
    c.cyl(mixer, "Trommel", (-6.0, 2.1, 3.3), 2.4, 2.2, "X", ORANGE, "Metal", yaw=20)
    c.cones(m, ((-3.5, 4.5), (3.5, 4.5)))
    # Bautafel vorn rechts mit Countdown (Text setzt der Server)
    c.board(m, "BAUSTELLE", [("Countdown", "Bauzeit läuft …")], 5.5, 5.9, w=6.0, h=2.6, top=5.0, name="Bautafel")
    return m


# ---------------------------------------------------------------- Autohaus (20 x 14)
def autohaus(c, s):
    m = c.m
    hw, hd = c.w / 2, c.d / 2
    c.base(m, APRON, "Concrete")
    if s == 1:
        # Verkaufsstand: Kiosk, Stellplatz-Markierung, Fahne, Firmenschild
        k = c.model(m, "Verkaufsstand")
        c.box(k, "Kiosk", -9.0, -3.0, 0.0, 4.4, -6.5, -2.0, TEAL, "Metal")
        c.box(k, "Kioskdach", -9.4, -2.6, 4.4, 4.8, -6.9, -1.2, GRAPHITE, "Concrete")
        c.box(k, "Fenster", -8.4, -3.6, 1.4, 3.3, -2.0, -1.9, GLASS, "Glass", transparency=0.4, deco=True)
        c.sign(k, "AUTOHAUS", (5.5, 1.0), -6.0, 3.85, -1.9, 0, WHITE, SLATE, name="Kioskschild")
        c.box(m, "Stellplatz", -1.0, 9.0, 0.0, 0.05, -4.2, 4.2, (126, 122, 114), "Concrete", deco=True)
        c.flag(m, "Fahne", -9.0, 5.5, AMBER, WHITE, "AUTO", h=9.0)
        c.sign_post(m, "VERKAUF · bald", 5.0, 6.0, w=7.0, h=1.6, top=6.0, color=AMBER, bg=SLATE)
        c.planter(m, 8.6, -5.6)
        return m
    # Stufe 2..4: Glaspavillon über einem Auto (Auto längs X, Nase West), Rolltor vorn, Streifen Z 5.5..7 davor
    h = 7.0 if s == 2 else 8.0
    z1 = 5.5
    c.hall(m, -hw + 0.1, hw - 0.1, -hd + 0.1, z1, h, door=(-4.0, 6.0, 5.4), glass=True, name="Showroom",
           door_color=FRAME)
    car = c.car(m, ("compact", "sedan", "sport")[s - 2], 0.8, 0.0, -0.6, 90, (TEAL, (200, 60, 60), AMBER)[s - 2],
                name="Showcar")
    set_attrs(car, {"Display": "Autohaus"})
    c.sign(m, "AUTOHAUS", (10.0, 1.6), 3.0, h - 0.9, z1 + 0.11, 0, AMBER, SLATE, name="Hallenschild")
    c.box(m, "Blumenkasten", 4.0, 7.0, 0.0, 0.9, 6.0, 7.0, CONCRETE, "Concrete")
    c.box(m, "Blumen", 4.2, 6.8, 0.9, 1.6, 6.2, 6.8, GREEN, "Grass", deco=True)
    if s >= 3:
        # Dachausstellung: Auto auf dem Dach mit Geländer, Neonschrift, Hoflaterne
        ry = h + 0.6
        c.roof_rail(m, -hw + 0.1, hw - 0.1, -hd + 0.1, z1, ry)
        rc = c.car(m, "hot_hatch", -0.8, ry, -0.6, -90, (240, 240, 240), name="Dachauto")
        set_attrs(rc, {"Display": "Autohaus"})
        c.neon_sign(m, "AUTOHAUS", 0.0, ry, 5.1, 9.0, h=1.6, name="Neonschrift")
        c.lamp(m, -8.8, 6.2, 1, 0, name="Hoflaterne")
    if s >= 4:
        # Pylon mit Drehlogo (Anim=turntable) vorn rechts, Dachstrahler, Fahne
        py = c.model(m, "Pylon")
        c.box(py, "Pylonfuss", 7.0, 9.0, 0.0, 0.6, 6.0, 6.9, GRAPHITE, "Concrete")
        c.box(py, "Pylonmast", 7.7, 8.3, 0.6, 13.0, 6.2, 6.7, STEEL, "Metal")
        c.box(py, "Nabenlager", 7.6, 8.4, 13.0, 13.4, 6.1, 6.8, BLACK, "Metal", deco=True)
        tt = c.model(py, "Drehlogo", attrs={"Anim": "turntable", "Speed": 20.0})
        ring = c.box(tt, "Logoring", 7.1, 8.9, 13.4, 13.8, 6.15, 6.75, TEAL, "Neon", deco=True)
        c.lib.set_primary(tt, ring)
        c.box(tt, "Logo", 6.8, 9.2, 13.8, 15.4, 6.25, 6.65, AMBER, "Neon", deco=True)
        ry = h + 0.6
        head = c.box(m, "Dachstrahler", -9.0, -7.0, ry, ry + 0.4, 4.9, 5.3, LAMP, "SmoothPlastic", deco=True)
        set_attrs(head, {"NightNeon": True})
        c.light(head, 18, 0.7)
        c.flag(m, "Fahne", -5.5, 6.25, TEAL, WHITE, "AUTO", h=8.5)
    return m


# ---------------------------------------------------------------- Produktion (24 x 16)
def produktion(c, s):
    m = c.m
    hw, hd = c.w / 2, c.d / 2
    c.base(m, APRON, "Concrete")
    if s == 1:
        # Montageschuppen: 4 Stützen + Dach, Band darunter, Werkbank, Paletten und Fässer daneben
        sh = c.model(m, "Schuppen")
        for sx in (-11.0, 2.4):
            for sz in (-7.4, 4.4):
                c.box(sh, "Stuetze", sx, sx + 0.6, 0.0, 6.5, sz, sz + 0.6, TRUSS, "Metal")
        c.box(sh, "Schuppendach", -11.4, 3.4, 6.5, 7.0, -7.8, 5.4, GRAPHITE, "Concrete")
        c.conveyor(m, -10.0, 2.0, -1.0, w=3.0, top=2.0, name="Montageband", cargo=3)
        c.workbench(m, -10.0, -5.0, 2.0, 4.0)
        c.pallets(m, 5.0, -7.0, cols=2, rows=1, high=2, name="Teilelager")
        c.barrels(m, 5.0, 3.0, n=3)
        c.sign_post(m, "PRODUKTION", 8.5, 6.5, w=7.0, h=1.6, top=6.5, color=WHITE, bg=SLATE)
        return m
    # Stufe 2..4: Halle (wächst nach rechts), Band + Roboter innen, Hof rechts
    x1 = 4.5 if s == 2 else 7.5
    h = 8.0 if s == 2 else 9.5
    z1 = 5.5
    c.hall(m, -hw + 0.1, x1, -hd + 0.1, z1, h, wall=SLATE, roof=GRAPHITE, door=(-3.5, 6.0, 5.5), name="Halle",
           door_color=FRAME)
    c.conveyor(m, -10.5, x1 - 2.0, -4.0, w=3.0, top=2.0, name="Montageband", cargo=4 if s == 2 else 5)
    c.robot(m, -6.0, 0.5, yaw=180, spark=True, name="Roboter")
    c.sign(m, "PRODUKTION", (9.0, 1.5), -3.5, h - 0.9, z1 + 0.11, 0, WHITE, SLATE, name="Hallenschild")
    if s == 2:
        c.pallets(m, 6.0, -7.0, cols=1, rows=1, high=2, name="Teilelager")
        c.forklift(m, 9.0, 0.0)
        c.barrels(m, 6.0, 6.0, n=2)
    if s >= 3:
        c.stamp(m, 2.5, 1.5, w=6.0, d=5.0, h=6.5, name="Karosseriepresse")
        c.robot(m, -9.0, 2.5, yaw=0, spark=False, name="Roboter_2")
        chim = c.model(m, "Schornstein")
        c.cyl(chim, "Schlot", (-9.5, h + 0.6 + 3.0, -5.5), 6.0, 2.0, "Y", (104, 110, 114), "Metal")
        c.cyl(chim, "Schlotkrone", (-9.5, h + 0.6 + 6.2, -5.5), 0.4, 2.4, "Y", RED, "Metal", deco=True)
        c.lamp(m, 11.3, 7.2, -1, 0, name="Hoflaterne")
    if s == 3:
        c.pallets(m, 8.6, -7.0, cols=1, rows=2, high=2, name="Teilelager")
        c.forklift(m, 9.5, 1.8)
    if s >= 4:
        # Anbau rechts (Versand) mit Rolltor, Versandband, Dachtanks, Neon, Warnlicht, Torstrahler
        c.annex(m, x1, hw - 0.1, -hd + 0.1, z1, 6.5, side="W", door=(9.7, 3.6, 5.0), name="Versand")
        c.conveyor(m, x1 + 0.9, hw - 1.0, -4.0, w=3.0, top=2.0, name="Versandband", cargo=2)
        c.neon_sign(m, "PRODUKTION", -3.5, h + 0.6, 5.1, 10.0, h=1.6, name="Neonschrift")
        tank = c.model(m, "Dachtanks")
        for tx in (2.0, 5.5):
            c.cyl(tank, "Tank", (tx, h + 0.6 + 1.8, -3.0), 3.6, 2.6, "Y", STEEL, "Metal")
        beacon = c.ball(m, "Warnlicht", (-9.5, h + 0.6 + 6.8, -5.5), 0.8, RED, "Neon", deco=True)
        set_attrs(beacon, {"Anim": "beacon", "Period": 1.5})
        head = c.box(m, "Torstrahler", -6.5, -0.5, h - 2.2, h - 1.9, z1, z1 + 0.3, LAMP, "SmoothPlastic", deco=True)
        set_attrs(head, {"NightNeon": True})
        c.light(head, 18, 0.7)
    return m


# ---------------------------------------------------------------- Schrottplatz (18 x 14)
def schrottplatz(c, s):
    m = c.m
    hw, hd = c.w / 2, c.d / 2
    c.base(m, GRAVEL, "Pebble", "Kies")
    # Wellblechzaun hinten und an den Seiten (Front offen)
    c.fence(m, -hw + 0.4, hw - 0.4, -hd + 0.4, h=4.0, along="X", name="Zaun_N")
    c.fence(m, -hd + 1.0, hd - 0.4, -hw + 0.4, h=4.0, along="Z", name="Zaun_W")
    c.fence(m, (-hd + 1.0) if s < 3 else 1.0, hd - 0.4, hw - 0.4, h=4.0, along="Z", name="Zaun_O")
    c.heap(m, -5.5, -3.5, 2.2, 3.0, name="Schrotthaufen")
    if s < 3:
        c.container(m, 4.0, 8.2, -6.0, -2.2, h=4.4, color=BLUE, name="Container")
    if s < 4:
        c.tires(m, 6.9, 4.0, n=3)
        c.sign_post(m, "SCHROTTPLATZ", 5.0, 6.2, w=8.0, h=1.6, top=6.0, color=YELLOW, bg=SLATE)
    if s == 1:
        c.barrels(m, -7.0, 5.0, n=2, color=RUST)
        c.cones(m, ((-2.0, 5.8),))
        return m
    # Stufe 2..4: Magnetkran links (Anim=turntable; Schwenkring Radius ~4.5 ab Magnet-Unterkante 4.9), 2. Haufen
    c.crane(m, -5.5, 2.0, mast_h=11.0, jib=3.0, cab=True, name="Magnetkran", speed=5.0, magnet_y=4.5)
    c.heap(m, -1.2, 3.2, 2.2, 2.4, name="Schrotthaufen_2")
    if s == 2:
        c.barrels(m, 0.5, -5.3, n=2, color=RUST)
        return m
    # Stufe 3..4: Schrottpresse rechts (Anim=press; Säulen X -1.6..8.8, Z -4.5..0.5, Querhaupt 13..16; der Ostzaun
    # endet davor bei Z 1), Hoflaterne
    c.press(m, 3.6, -2.0, w=5.6, d=5.0, h=13.0, name="Schrottpresse", scale=0.6)
    c.lamp(m, -7.5, 6.2, 1, 0, name="Hoflaterne")
    if s == 3:
        return m
    # Stufe 4: Büro vorn rechts, Neon, Pressenstrahler
    of = c.model(m, "Buero")
    wall = (104, 110, 114)
    c.box(of, "Bueroboden", 3.6, 8.0, 0.0, 0.3, 2.6, 6.6, APRON, "Concrete")
    c.box(of, "Buerowand_S", 3.6, 8.0, 0.3, 4.4, 6.0, 6.6, wall, "Metal")
    c.box(of, "Buerowand_N", 3.6, 8.0, 0.3, 4.4, 2.6, 3.2, wall, "Metal")
    c.box(of, "Buerowand_W", 3.6, 4.2, 0.3, 4.4, 3.2, 6.0, wall, "Metal")
    c.box(of, "Buerowand_O", 7.4, 8.0, 0.3, 4.4, 3.2, 6.0, wall, "Metal")
    c.box(of, "Buerofenster", 4.2, 7.4, 1.8, 3.4, 6.6, 6.7, GLASS, "Glass", transparency=0.35, deco=True)
    c.box(of, "Buerodach", 3.4, 8.2, 4.4, 4.8, 2.4, 6.8, GRAPHITE, "Concrete")
    c.neon_sign(m, "SCHROTT", 5.8, 4.8, 6.4, 4.6, h=1.4, name="Neonschrift", color=YELLOW)
    head = c.box(m, "Pressenstrahler", 1.4, 3.4, 12.7, 13.0, -1.0, 0.0, LAMP, "SmoothPlastic", deco=True)
    set_attrs(head, {"NightNeon": True})
    c.light(head, 18, 0.7)
    return m


BUILDERS = {"autohaus": autohaus, "produktion": produktion, "schrottplatz": schrottplatz}


# ---------------------------------------------------------------- Aufbau
def build_template(lib, parent, name):
    w, d = footprint(name)
    typ, stage = ("baustelle", 0) if name == "baustelle" else (name.rsplit("_", 1)[0], int(name.rsplit("_", 1)[1]))
    m = lib.model(parent, name, attrs={"OWType": typ, "OWStage": stage, "Width": w, "Depth": d})
    root = lib.part(m, "Root", (1, 1, 1), CF(0, ROOT_Y, 0), TEAL, "SmoothPlastic", transparency=1, collide=False,
                    touch=False, query=False, cast_shadow=False)
    lib.set_primary(m, root)
    c = OwCtx(lib, m, w, d)
    if name == "baustelle":
        baustelle(c)
    else:
        BUILDERS[typ](c, stage)
    return m


def build(tree, lib):
    """ServerStorage.OWBuildings.<name> (ersetzt einen vorhandenen Ordner)."""
    root = tree.getroot()
    ss = next(i for i in root.findall("Item") if i.get("class") == "ServerStorage")
    old = child(ss, NAME)
    if old is not None:
        ss.remove(old)
    folder = lib.item(ss, "Folder", NAME)
    set_attrs(folder, {"Version": "3.0"})
    for name in template_names():
        with lib.section("OW-Vorlage " + name):
            build_template(lib, folder, name)
    return folder


def templates_of(tree):
    """{name: Model} der gebauten Vorlagen (leer, wenn keine da sind)."""
    root = tree.getroot()
    ss = next((i for i in root.findall("Item") if i.get("class") == "ServerStorage"), None)
    folder = child(ss, NAME) if ss is not None else None
    if folder is None:
        return {}
    return {name_of(m): m for m in children(folder) if m.get("class") == "Model"}
