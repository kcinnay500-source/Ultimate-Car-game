"""Platz-Gebäude am Stadtplatz: Spielhalle (D3), Meisterschule (D4), Auktionshaus mit Portikus (D5),
Credit-Center (D6) - docs/CITY_SPEC.md §6 D3-D6, §8, §9.2, §10.

Statische Kulisse unter City.Districts.Platzgebaeude (je Gebäude ein Model), Bewegtes unter
City.Animated.Platzgebaeude:
  * Spielhalle_Lauflicht_1..4   Anim=neon (20 Glühbirnen um das SPIELHALLE-Schild, 4 versetzte Gruppen,
                                Period 0.48 = 4 x 0.12 s, Farbwechsel warmweiß -> magenta)
  * Spielhalle_Neonband_*       Anim=neon (umlaufendes Wandband innen, magenta/türkis -> violett)
  * Automat_Marquee_<n>         Anim=neon (leuchtende Titelschilder der 6 Automaten)
  * Auktion_Drehbuehne          Anim=turntable (Speed 12 = 30 s je Umdrehung), Vorlagen-gt_coupe in Burgund
  * Auktionshammer              Anim=gavel, Kind-Model "Hammer" (PrimaryPart = Griffknauf = Drehpunkt)
  * Tresorrad                   Anim=vault (Axis X = Welt-Z, Period 8), PrimaryPart = Nabe
Stationen (arcade, arcade_1..8, quiz, auction, auction_consign, shop) und die Ankünfte arcade / quiz / auction /
shop baut contract.py; hier steht die Kulisse drumherum (je 10 x 10 freier Boden auf der Spielerseite).

Höhen (§1.2, keine koplanaren überlappenden Oberseiten):
  Pflaster -0.50 (ground_roads) | Gebäudeboden 0 (Platte -0.5..0 auf dem Pflaster, 0.5-Stufe an den Türen)
  | Einlagen/Teppiche 0.03..0.07 | Bühne 3.0, Drehbühne 3.3 | Dach Spielhalle 26, Schule/Credit 24, Auktion 30.
Lichte Höhen: Spielhalle 26, Meisterschule 24, Auktionshaus 30, Credit-Center 24 (Binder bis 24.8 bzw. Pendel).
Lichter (11): Spielhalle 3, Meisterschule 2, Auktionshaus 3 Kronleuchter + 1 Bühnen-Spot (Schatten), Credit 2.

Abweichungen vom Spec (begründet):
  * Automaten arcade_5/6 stehen an der Nordwand (Z -110) - ihr Bildschirm zeigt nach SÜDEN zur Spielerseite S
    (Spec: "screen faces N" widerspricht Wandlage und Spielerseite).
  * Auktionshaus: keine eigene Stufe X 69..70 - dort liegt die Messing-Zielscheibe des Farbleitsystems; die
    Portikus-Bodenkante (0 über Pflaster -0.5) ist die eine 0.5-Stufe.
  * Gebälk und Giebel Z -98.4..-53.6 statt -99..-53: enden in den Rücksprung-Wänden statt ins Innere zu ragen.
  * Kuppel: Tambour Y 31..40 (steht auf dem Dach statt zu schweben), Messingkugel Ø14 mit Mitte 40 (sichtbare
    Halbkugel 40..47), Laterne 46.9..48.9.
  * Auktionshaus: Tribünen mit 3 statt 4 Stufen (X 91..106), Bieterkasse/Einlieferung X 79.5..89.5 mit den
    Stationen bei X 84.5 (Spec 81): so hat die Spielerseite 10 x 10 freien Boden neben der Portalwand (X 78.8).
    Bühne bis X 129 (Wandsockel), kein Spalt vor der Ostwand.
  * Spielhalle: Rennsimulatoren 2.5 nach Norden (Sitz Z -48.5, Stationen arcade_7/8 bei Z -43.5), Binder alle 16.
  * Drehbühne: Scheibe 3.0..3.3 auf der Bühne (3.0), Auto-Root auf 3.3.
  * Credit-Center: die 2 Lichter (Spec ohne Position) hängen bei (92,21,-152) und (110,21,-152).
"""
import math
import xml.etree.ElementTree as ET

from ..lib import (CF, AMBER, BLACK, FRAME, GLASS, GRAPHITE, SLATE, STEEL, TEAL, TRUSS, WHITE, Color3, _color3_el,
                   _sub_el, _udim2_el, fnum, props, set_attrs, yaw_towards)

NAME = "Platzgebaeude"
WT = 0.8
Y_PAVE = -0.5

# ---------------------------------------------------------------- Farben (§1.4 District-Identitäten)
NIGHT = (35, 22, 50)
SP_FLOOR = (30, 22, 45)
MAGENTA = (255, 64, 180)
VIOLET = (150, 80, 255)
CYAN = (60, 220, 255)
BULB = (255, 214, 120)
LWOOD = (181, 153, 112)
CHALK = (44, 74, 62)
SCHOOL_FLOOR = (152, 145, 127)
WOOD = (130, 90, 60)
DARKWOOD = (80, 52, 36)
BRASS = (201, 162, 90)
BURGUNDY = (110, 30, 40)
CREAM = (224, 214, 190)
MARBLE = (200, 194, 180)
PURPLE = (135, 75, 196)
PURPLE_D = (70, 45, 103)
PURPLE_FLOOR = (45, 28, 72)
PURPLE_TXT = (233, 212, 255)
PURPLE_NEON = (180, 110, 255)
SCREEN = (27, 72, 82)
SCREEN_TXT = (121, 225, 206)
HALL_LIGHT = (224, 238, 255)
NEON_WHITE = (232, 246, 249)
WARM = (255, 210, 150)
RED = (200, 50, 50)
SKIN = (234, 192, 160)


# ================================================================ Hilfen
def _box(lib, parent, name, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
    return lib.box(parent, name, min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1),
                   color, material, **kw)


def _cyl_y(lib, parent, name, x, y0, y1, z, dia, color, material="SmoothPlastic", **kw):
    return lib.cylinder(parent, name, (x, (y0 + y1) / 2, z), abs(y1 - y0), dia, "Y", color, material, **kw)


def _rects(u0, u1, y0, y1, holes):
    """Zerlegt eine Wandfläche (u0..u1 x y0..y1) ohne die Öffnungen in möglichst wenige Rechtecke."""
    def cl(v, a, b):
        return max(a, min(b, v))
    us = sorted({u0, u1} | {cl(h[0], u0, u1) for h in holes} | {cl(h[1], u0, u1) for h in holes})
    ys = sorted({y0, y1} | {cl(h[2], y0, y1) for h in holes} | {cl(h[3], y0, y1) for h in holes})

    def solid(ua, ub, ya, yb):
        mu, my = (ua + ub) / 2, (ya + yb) / 2
        return not any(h[0] < mu < h[1] and h[2] < my < h[3] for h in holes)

    def runs(cells):
        out, start = [], None
        for (a, b, ok) in cells:
            if ok and start is None:
                start = a
            if not ok and start is not None:
                out.append((start, a))
                start = None
            last = b
        if start is not None:
            out.append((start, last))
        return tuple(out)

    def merge(outer, inner, col_major):
        groups = []
        for i in range(len(outer) - 1):
            a, b = outer[i], outer[i + 1]
            if b - a < 1e-6:
                continue
            cells = [(inner[j], inner[j + 1],
                      solid(a, b, inner[j], inner[j + 1]) if col_major else solid(inner[j], inner[j + 1], a, b))
                     for j in range(len(inner) - 1) if inner[j + 1] - inner[j] > 1e-6]
            iv = runs(cells)
            if groups and groups[-1][2] == iv and abs(groups[-1][1] - a) < 1e-6:
                groups[-1][1] = b
            else:
                groups.append([a, b, iv])
        rects = []
        for a, b, iv in groups:
            for c, d in iv:
                rects.append((a, b, c, d) if col_major else (c, d, a, b))
        return rects
    r1 = merge(us, ys, True)
    r2 = merge(ys, us, False)
    return r1 if len(r1) <= len(r2) else r2


def _wall(lib, parent, name, axis, t0, t1, u0, u1, y0, y1, holes=(), color=SLATE, material="Metal", **kw):
    """Wand mit rechteckigen Öffnungen. axis 'x': Wand läuft entlang X (Dicke Z t0..t1); 'z': entlang Z
    (Dicke X t0..t1). holes: [(u_a, u_b, y_a, y_b)]."""
    out = []
    for ua, ub, ya, yb in _rects(u0, u1, y0, y1, list(holes)):
        if axis == "x":
            out.append(_box(lib, parent, name, ua, ub, ya, yb, t0, t1, color, material, **kw))
        else:
            out.append(_box(lib, parent, name, t0, t1, ya, yb, ua, ub, color, material, **kw))
    return out


def _pane(lib, parent, axis, tmid, ua, ub, ya, yb, name="Glas", t=0.3):
    """Glasscheibe mittig in der Wand, 0.2 in Laibung/Sturz eingelassen (keine koplanaren Flächen)."""
    if axis == "x":
        return _box(lib, parent, name, ua - 0.2, ub + 0.2, ya - 0.2, yb + 0.2, tmid - t / 2, tmid + t / 2, GLASS,
                    "Glass", transparency=0.3, reflectance=0.1)
    return _box(lib, parent, name, tmid - t / 2, tmid + t / 2, ya - 0.2, yb + 0.2, ua - 0.2, ub + 0.2, GLASS, "Glass",
                transparency=0.3, reflectance=0.1)


# ---------------------------------------------------------------- GUI
def _gui(lib, part, face="Back", px=40, name="SurfaceGui"):
    return lib.surface_text(part, None, face=face, px_per_stud=px, name=name)


def _frame(lib, g, name, x, y, w, h, color, transp=0.0, z=1, rot=None, round_=None):
    f = lib.item(g, "Frame", name)
    p = props(f)
    _udim2_el(p, "Size", w, 0, h, 0)
    _udim2_el(p, "Position", x, 0, y, 0)
    _color3_el(p, "BackgroundColor3", color)
    _sub_el(p, "float", "BackgroundTransparency", fnum(transp))
    _sub_el(p, "int", "BorderSizePixel", "0")
    _sub_el(p, "int", "ZIndex", str(z))
    if rot:
        _sub_el(p, "float", "Rotation", fnum(rot))
    if round_ is not None:
        c = lib.item(f, "UICorner", "UICorner")
        e = ET.SubElement(props(c), "UDim", {"name": "CornerRadius"})
        ET.SubElement(e, "S").text = fnum(round_)
        ET.SubElement(e, "O").text = "0"
    return f


def _label(lib, g, name, text, x, y, w, h, color=AMBER, font="GothamBold", align=None, z=3, bg=None):
    lab = lib.text_label(g, text, color, font, name, bg, (w, h), (x, y))
    p = props(lab)
    _sub_el(p, "int", "ZIndex", str(z))
    if align:
        _sub_el(p, "token", "TextXAlignment", {"left": "0", "right": "1", "center": "2"}[align])
    return lab


def _sign_plain(lib, parent, text, size, cf, text_color, bg, font="GothamBold", sub=None, sub_color=WHITE,
                thickness=0.12, name="Schild"):
    """Schild ohne Bolzen (innen), 1 Part."""
    return lib.sign(parent, text, size, cf, text_color, bg, font, name=name, thickness=thickness, bolts=False, sub=sub,
                    sub_color=sub_color)


def _local(lib, parent, base):
    """Teile in einem lokalen Rahmen (base = CF) bauen."""
    def P(name, size, pos, color, material="SmoothPlastic", rot=None, **kw):
        cf = base * CF(*pos)
        if rot is not None:
            cf = cf * rot
        return lib.part(parent, name, size, cf, color, material, **kw)
    return P


# ================================================================ D3 Spielhalle
SX0, SX1, SZ0, SZ1 = -130.0, -70.0, -111.0, -31.0
S_ROOF, S_TOP = 26.0, 30.0

GAMES = [  # (Nr, Titel, Akzent, Art, Lage)
    (1, "BLITZ-REAKTION", MAGENTA, "reaction", ("W", -60)),
    (2, "BREMSWEG-PROFI", CYAN, "brake", ("W", -72)),
    (3, "BOXENSTOPP", VIOLET, "pit", ("W", -84)),
    (4, "DREHMOMENT", AMBER, "torque", ("W", -96)),
    (5, "MOTOR-OHR", CYAN, "ear", ("N", -112)),
    (6, "EINPARK-PROFI", MAGENTA, "park", ("N", -98)),
]


def _screen_art(lib, g, kind, title, accent):
    _frame(lib, g, "Grund", 0, 0, 1, 1, (12, 10, 28), 0, 1)
    _frame(lib, g, "Kopf", 0, 0, 1, 0.2, (26, 18, 44), 0, 2)
    _label(lib, g, "Title", title, 0.03, 0.03, 0.94, 0.15, accent, "GothamBlack", "center", 4)
    dim = tuple(int(c * 0.35) for c in accent)
    if kind == "reaction":
        for i, col in enumerate(((90, 20, 20), (110, 80, 20), (60, 230, 110))):
            _frame(lib, g, "Lampe", 0.2 + i * 0.22, 0.28, 0.16, 0.2, col, 0, 3, round_=0.5)
        _label(lib, g, "Wert", "0,187 s", 0.1, 0.52, 0.8, 0.22, WHITE, "GothamBlack", "center", 4)
    elif kind == "brake":
        _frame(lib, g, "Strasse", 0, 0.5, 1, 0.2, (46, 52, 59), 0, 2)
        _frame(lib, g, "Auto", 0.12, 0.52, 0.18, 0.12, accent, 0, 3, round_=0.2)
        _frame(lib, g, "Haltelinie", 0.78, 0.5, 0.025, 0.2, WHITE, 0, 3)
        _label(lib, g, "Wert", "BREMSWEG 12,4 m", 0.05, 0.25, 0.9, 0.2, WHITE, "GothamBold", "center", 4)
    elif kind == "pit":
        _frame(lib, g, "Auto", 0.36, 0.3, 0.28, 0.4, accent, 0, 3, round_=0.2)
        for tx, ty in ((0.3, 0.32), (0.64, 0.32), (0.3, 0.58), (0.64, 0.58)):
            _frame(lib, g, "Reifen", tx, ty, 0.06, 0.1, (10, 10, 12), 0, 4)
        _label(lib, g, "Wert", "2,8 s", 0.7, 0.4, 0.28, 0.2, WHITE, "GothamBlack", "center", 4)
    elif kind == "torque":
        _frame(lib, g, "Skala", 0.3, 0.24, 0.4, 0.52, dim, 0, 2, round_=0.5)
        _frame(lib, g, "Zeiger", 0.49, 0.3, 0.02, 0.24, accent, 0, 3, rot=40)
        _label(lib, g, "Wert", "320 Nm", 0.25, 0.58, 0.5, 0.16, WHITE, "GothamBlack", "center", 4)
    elif kind == "ear":
        for i, h in enumerate((0.1, 0.25, 0.4, 0.18, 0.5, 0.3, 0.12, 0.45, 0.22, 0.35, 0.15, 0.28)):
            _frame(lib, g, "Welle", 0.06 + i * 0.075, 0.52 - h / 2, 0.05, h, accent, 0, 3)
    elif kind == "park":
        for i in range(4):
            _frame(lib, g, "Linie", 0.15 + i * 0.24, 0.28, 0.02, 0.44, WHITE, 0, 2)
        _frame(lib, g, "Auto", 0.42, 0.34, 0.14, 0.3, accent, 0, 3, round_=0.2)
        _frame(lib, g, "Nachbar", 0.19, 0.36, 0.14, 0.3, dim, 0, 3, round_=0.2)
    _label(lib, g, "Status", "TASTE E · SPIELEN", 0.04, 0.82, 0.92, 0.13, SCREEN_TXT, "GothamBold", "center", 4)


def _cabinet(lib, parent, anim, nr, title, accent, kind, ox, oz, fx, fz):
    """Arcade-Automat (13 Parts): Unterbau, Pult, Gehäuse, Bildschirm, Marquee (+ leuchtende Blende unter
    Animated), Seitenwangen, Knöpfe, Joystick, Themen-Requisite. (ox,oz) = Wandfläche, (fx,fz) = zur Spielerseite."""
    m = lib.model(parent, "Automat_%d" % nr, attrs={"Game": title, "GameKey": "arcade_%d" % nr})
    base = CF.at(ox, 0, oz, yaw_towards(fx, fz))
    P = _local(lib, m, base)
    body = (24, 18, 36)
    P("Unterbau", (4.6, 3.4, 3.2), (0, 1.7, -1.6), body, "Metal")
    P("Pult", (4.6, 0.4, 1.4), (0, 3.6, -2.9), BLACK, "SmoothPlastic")
    P("Gehaeuse", (4.6, 4.4, 2.2), (0, 5.6, -1.1), body, "Metal")
    scr = P("Bildschirm", (3.6, 2.8, 0.12), (0, 5.7, -2.26), (18, 30, 70), "Neon", deco=True)
    _screen_art(lib, _gui(lib, scr, "Front", 40, "Screen"), kind, title, accent)
    P("Marquee", (4.8, 1.2, 2.6), (0, 8.4, -1.3), BLACK, "Metal")
    for s in (-1, 1):
        P("Seitenwange", (0.1, 7.8, 3.2), (s * 2.35, 3.9, -1.6), accent, "SmoothPlastic")
    P("Knopf", (0.5, 0.5, 0.5), (1.0, 3.95, -3.0), CYAN if accent != CYAN else MAGENTA, "Neon", shape="Ball", deco=True)
    P("Knopf", (0.5, 0.5, 0.5), (1.7, 3.95, -2.7), AMBER, "Neon", shape="Ball", deco=True)
    P("Joystick", (0.7, 0.15, 0.15), (-1.4, 4.15, -2.9), STEEL, "Metal", rot=CF.angles(0, 0, math.pi / 2), deco=True)
    P("Joystickkugel", (0.45, 0.45, 0.45), (-1.4, 4.55, -2.9), RED, "SmoothPlastic", shape="Ball", deco=True)
    if kind == "reaction":
        P("Buzzer", (0.35, 1.1, 1.1), (0, 3.975, -2.9), (230, 40, 40), "Neon", shape="Cylinder",
          rot=CF.angles(0, 0, math.pi / 2), deco=True)
    elif kind == "brake":
        P("Bremspedal", (1.2, 0.2, 1.6), (0, 0.5, -4.0), STEEL, "DiamondPlate", rot=CF.angles(math.radians(18), 0, 0))
    elif kind == "pit":
        P("Reifen", (1.0, 2.6, 2.6), (0, 10.3, -1.3), BLACK, "SmoothPlastic", shape="Cylinder", deco=True)
    elif kind == "torque":
        P("Drehmomentschluessel", (3.8, 0.25, 0.5), (0, 9.125, -1.3), STEEL, "Metal",
          rot=CF.angles(0, math.radians(18), 0), deco=True)
    elif kind == "ear":
        P("Motorblock", (2.2, 1.2, 1.6), (0, 9.6, -1.3), (104, 110, 114), "Metal", deco=True)
    elif kind == "park":
        p = base * CF(0, 9.0, -1.3)
        lib.cone(m, p.p[0], p.p[1], p.p[2], name="Leitkegel")
    # Leuchtende Marquee-Blende (Anim neon)
    mq = lib.part(anim, "Automat_Marquee_%d" % nr, (4.4, 0.9, 0.1), base * CF(0, 8.4, -2.65), accent, "Neon",
                  deco=True, attrs={"Anim": "neon", "Period": 1.2 + 0.2 * nr,
                                    "ColorB": Color3(*tuple(min(255, c + 70) for c in accent))})
    g = _gui(lib, mq, "Front", 40)
    _label(lib, g, "Titel", title, 0.03, 0.08, 0.94, 0.84, (20, 10, 30), "GothamBlack", "center", 3)
    return m


SIM_Z = -48.5          # Sitz der Rennsimulatoren (Spec -46; 2.5 nach Norden für 10 x 10 freie Spielerseite)


def _sim(lib, parent, nr, x, accent):
    """Rennsimulator (19 Parts), Sitz bei (x,0,SIM_Z), Blick nach Norden, Bildschirme 6 weiter nördlich."""
    m = lib.model(parent, "Rennsimulator_%d" % nr, attrs={"Game": "RENNSIMULATOR %d" % nr,
                                                          "GameKey": "arcade_%d" % (6 + nr)})
    base = CF.at(x, 0, SIM_Z, 0)
    P = _local(lib, m, base)
    P("Plattform", (6, 0.3, 8), (0, 0.15, 0), BLACK, "DiamondPlate")
    for s in (-1, 1):
        P("Unterleuchte", (0.12, 0.15, 8), (s * 3.06, 0.1, 0), accent, "Neon", deco=True)
    P("Sitzsockel", (1.2, 1.0, 1.2), (0, 0.8, 0.3), STEEL, "Metal")
    P("Sitzflaeche", (2.2, 0.5, 2.2), (0, 1.55, 0.3), BLACK, "Fabric")
    P("Lehne", (2.1, 3.4, 0.5), (0, 3.4, 1.6), BLACK, "Fabric", rot=CF.angles(math.radians(12), 0, 0))
    for s in (-1, 1):
        P("Seitenwange", (0.3, 1.0, 2.2), (s * 1.2, 2.1, 0.3), accent, "SmoothPlastic")
    P("Lenksaeule", (0.6, 3.0, 0.6), (0, 1.8, -2.6), (40, 44, 50), "Metal")
    P("Lenknabe", (0.4, 0.5, 0.5), (0, 3.3, -2.3), AMBER, "Metal", shape="Cylinder",
      rot=CF.angles(0, math.pi / 2, 0), deco=True)
    P("Lenkrad", (0.18, 1.8, 1.8), (0, 3.3, -2.1), BLACK, "SmoothPlastic", shape="Cylinder",
      rot=CF.angles(0, math.pi / 2, 0))
    P("Pedal", (0.4, 0.5, 0.2), (-0.4, 0.55, -3.4), STEEL, "Metal", deco=True)
    P("Pedal", (0.4, 0.5, 0.2), (0.4, 0.55, -3.4), RED, "Metal", deco=True)
    P("Staenderfuss", (2.0, 0.2, 1.2), (0, 0.1, -6.2), BLACK, "Metal")
    P("Staender", (0.4, 3.4, 0.4), (0, 1.9, -6.2), (40, 44, 50), "Metal")
    scr = P("Bildschirm", (4.2, 2.6, 0.15), (0, 4.9, -6.0), (10, 12, 20), "SmoothPlastic")
    _race_art(lib, _gui(lib, scr, "Back", 40, "Screen"), nr, accent, True)
    for s in (-1, 1):
        a = math.radians(35)
        cx, cz = s * (2.1 + math.cos(a) * 1.8), -6.0 + math.sin(a) * 1.8
        sc = P("Bildschirm", (3.6, 2.6, 0.15), (cx, 4.9, cz), (10, 12, 20), "SmoothPlastic",
               rot=CF.yaw(-s * 35))
        _race_art(lib, _gui(lib, sc, "Back", 40), nr, accent, False)
    sg = P("Schild", (4.2, 0.9, 0.15), (0, 6.65, -6.0), NIGHT, "SmoothPlastic", deco=True)
    g = _gui(lib, sg, "Back", 40)
    _label(lib, g, "Titel", "RENNSIMULATOR %d" % nr, 0.03, 0.1, 0.94, 0.8, accent, "GothamBlack", "center", 3)
    return m


def _race_art(lib, g, nr, accent, center):
    _frame(lib, g, "Himmel", 0, 0, 1, 0.5, (70, 110, 180), 0, 1)
    _frame(lib, g, "Horizont", 0, 0.42, 1, 0.08, (140, 160, 200), 0, 2)
    _frame(lib, g, "Wiese", 0, 0.5, 1, 0.5, (60, 120, 60), 0, 1)
    if center:
        for i, w in enumerate((0.08, 0.2, 0.34, 0.5, 0.68)):
            _frame(lib, g, "Strasse", 0.5 - w / 2, 0.5 + i * 0.1, w, 0.1, (60, 64, 70), 0, 2)
        for i in range(3):
            _frame(lib, g, "Mittellinie", 0.495 - i * 0.004, 0.55 + i * 0.14, 0.01 + i * 0.008, 0.06, WHITE, 0, 3)
        _frame(lib, g, "Motorhaube", 0.25, 0.86, 0.5, 0.14, accent, 0, 4, round_=0.3)
        _label(lib, g, "Runde", "RUNDE 2/3", 0.03, 0.03, 0.3, 0.1, WHITE, "GothamBlack", "left", 5)
        _label(lib, g, "Zeit", "1:12,408", 0.67, 0.03, 0.3, 0.1, AMBER, "GothamBlack", "right", 5)
        _label(lib, g, "Title", "RENNSIMULATOR %d" % nr, 0.3, 0.14, 0.4, 0.1, WHITE, "GothamBlack", "center", 5)
        _label(lib, g, "Status", "TASTE E · SPIELEN", 0.3, 0.25, 0.4, 0.07, AMBER, "GothamBold", "center", 5)
    else:
        _frame(lib, g, "Leitplanke", 0, 0.56, 1, 0.04, STEEL, 0, 2)
        for i in range(4):
            _frame(lib, g, "Baum", 0.1 + i * 0.24, 0.3, 0.08, 0.22, (40, 90, 50), 0, 3, round_=0.5)


def build_spielhalle(lib, dm, anim):
    h = lib.model(dm, "Spielhalle", attrs={"District": "D3", "Title": "SPIELHALLE"})
    shell = lib.model(h, "Huelle")
    x0, x1, z0, z1 = SX0, SX1, SZ0, SZ1
    _box(lib, shell, "Boden", x0, x1, Y_PAVE, 0, z0, z1, SP_FLOOR, "SmoothPlastic", reflectance=0.08)
    wall = dict(color=NIGHT, material="Metal")
    _wall(lib, shell, "Nordwand", "x", z0, z0 + WT, x0, x1, 0, S_TOP, **wall)
    _wall(lib, shell, "Westwand", "z", x0, x0 + WT, z0 + WT, z1 - WT, 0, S_TOP, **wall)
    # Süd (Meile): Schaufenster X -126..-74, Y 2..14
    _wall(lib, shell, "Suedwand", "x", z1 - WT, z1, x0, x1, 0, S_TOP, [(-126, -74, 2, 14)], **wall)
    _pane(lib, shell, "x", z1 - WT / 2, -126, -74, 2, 14, "Schaufenster")
    for x in (-113, -100, -87):
        _box(lib, shell, "Sprosse", x - 0.25, x + 0.25, 2, 14, z1 - 0.7, z1 - 0.1, VIOLET, "Metal")
    # Ost (Platz): Tür Z -78..-66 (12 x 12), Fenster Z -104..-88 und -58..-40, Y 3..10
    e_holes = [(-78, -66, 0, 12), (-104, -88, 3, 10), (-58, -40, 3, 10)]
    _wall(lib, shell, "Ostwand", "z", x1 - WT, x1, z0 + WT, z1 - WT, 0, S_TOP, e_holes, **wall)
    for a, b in ((-104, -88), (-58, -40)):
        _pane(lib, shell, "z", x1 - WT / 2, a, b, 3, 10, "Fenster")
    _box(lib, shell, "Dach", x0 + WT, x1 - WT, S_ROOF, S_ROOF + 1, z0 + WT, z1 - WT, GRAPHITE, "Metal")
    # Neon-Traufband außen (Ost, Süd)
    nb = _box(lib, shell, "Neonband", x1, x1 + 0.2, 28.6, 29.0, z0 + 0.4, z1, CYAN, "Neon", transparency=0.4,
              deco=True)
    set_attrs(nb, {"NeonStrip": True})
    nb = _box(lib, shell, "Neonband", x0 + 0.4, x1 + 0.2, 28.6, 29.0, z1, z1 + 0.2, CYAN, "Neon", transparency=0.4,
              deco=True)
    set_attrs(nb, {"NeonStrip": True})
    for z in (-110.6, -31.4):
        _box(lib, shell, "Eckleiste", x1, x1 + 0.3, Y_PAVE, 28.4, z - 0.4, z + 0.4, MAGENTA, "Neon", deco=True)

    # --- Fassade Ost: Marquee-Vordach, Schild mit Lauflicht, Türrahmen
    fac = lib.model(h, "Fassade")
    _box(lib, fac, "Vordach", x1, x1 + 6, 12, 13.5, -82, -62, NIGHT, "Metal")
    _box(lib, fac, "Vordach Kante", x1 + 6, x1 + 6.2, 12.3, 13.2, -82, -62, MAGENTA, "Neon", deco=True)
    _box(lib, fac, "Vordach Unterlicht", x1 + 5.0, x1 + 5.6, 11.8, 12.0, -81.5, -62.5, CYAN, "Neon", deco=True)
    for z in (-81, -63):
        lib.beam(fac, "Zugstange", (x1 + 0.1, 20.5, z), (x1 + 5.8, 13.5, z), 0.2, STEEL, "Metal", deco=True)
    for a, b in ((-78.6, -78), (-66, -65.4)):
        _box(lib, fac, "Tuerrahmen", x1, x1 + 0.3, Y_PAVE, 12, a, b, MAGENTA, "Neon", deco=True)
    _box(lib, fac, "Schildrahmen", x1, x1 + 0.4, 13.5, 18.8, -82.8, -61.2, VIOLET, "Metal")
    lib.sign(fac, "SPIELHALLE", (20, 4), CF.at(x1 + 0.5, 16, -72, 90), MAGENTA, NIGHT, "GothamBlack",
             name="Hauptschild")
    _sign_plain(lib, fac, "GESCHICK STATT GLÜCK", (18, 1.8), CF.at(x1 + 0.06, 20.5, -72, 90), CYAN, NIGHT,
                "GothamBlack", name="Leitspruch")
    # 20 Lauflicht-Birnen in 4 Gruppen (Anim neon)
    pts = []
    for i in range(8):
        z = -82.4 + i * (20.8 / 7)
        pts.append((18.45, z))
    for yy in (16.8, 15.2):
        pts.append((yy, -61.6))
    for i in range(8):
        z = -61.6 - i * (20.8 / 7)
        pts.append((13.85, z))
    for yy in (15.2, 16.8):
        pts.append((yy, -82.4))
    groups = [lib.model(anim, "Spielhalle_Lauflicht_%d" % (k + 1),
                        attrs={"Anim": "neon", "Period": 0.48, "Step": 0.12, "Chase": k + 1,
                               "ColorB": Color3(*MAGENTA)}) for k in range(4)]
    for i, (yy, z) in enumerate(pts):
        lib.ball(groups[i % 4], "Birne", (x1 + 0.55, yy, z), 0.6, BULB, "Neon", deco=True)
    # Süd: Schriftzug über dem Schaufenster
    lib.sign(fac, "SPIELHALLE", (30, 3.6), CF.at(-100, 18.2, z1 + 0.1, 0), MAGENTA, NIGHT, "GothamBlack",
             name="Meileschild", sub="RENNSIMULATOREN · REAKTION · BOXENSTOPP", sub_color=CYAN)
    # Ecke SO: Fahnenschild ARCADE
    _box(lib, fac, "Fahnenschild Neon", -69.2, -68.75, 7.6, 32.4, -36.4, -29.6, VIOLET, "Neon", deco=True)
    bl = lib.part(fac, "Fahnenschild", (6, 24, 1.5), CF.at(-68.0, 20, -33, 90), NIGHT, "Metal")
    lib.surface_text(bl, "A\nR\nC\nA\nD\nE", face="Back", text_color=CYAN, font="GothamBlack")
    for y in (10, 30):
        _box(lib, fac, "Halter", x1, -69.2, y - 0.2, y + 0.2, -33.3, -32.7, STEEL, "Metal")

    # --- Innen
    inn = lib.model(h, "Innenraum")
    for z, col in ((-75.5, CYAN), (-68.5, MAGENTA)):
        _box(lib, inn, "Leuchtbahn", -118, x1 - WT, 0, 0.05, z - 0.3, z + 0.3, col, "Neon", deco=True)
    lib.cylinder(inn, "Bodenring", (-98, 0.025, -86), 0.05, 10, "Y", CYAN, "Neon", deco=True)
    lib.cylinder(inn, "Bodenscheibe", (-98, 0.05, -86), 0.1, 8.4, "Y", (40, 26, 62), "SmoothPlastic", deco=True)
    # Binder im gleichmäßigen 16er-Raster, je >= 3 von den Pendelleuchten (Z -50, -80, -100)
    for z in (-39, -55, -71, -87, -103):
        _box(lib, inn, "Binder", x0 + WT, x1 - WT, S_ROOF - 1.2, S_ROOF, z - 0.4, z + 0.4, TRUSS, "Metal")
    for (lx, lz), col in (((-110, -50), MAGENTA), ((-100, -80), CYAN), ((-90, -100), VIOLET)):
        _cyl_y(lib, inn, "Pendelstange", lx, 22.3, S_ROOF, lz, 0.2, STEEL, "Metal", deco=True)
        lamp = lib.cylinder(inn, "Pendelleuchte", (lx, 22, lz), 0.6, 3.2, "Y", col, "Neon", deco=True)
        lib.point_light(lamp, 30, 1.0, col)
    # umlaufendes Neonband innen (Anim neon)
    for nm, (a, b, c, d), col in (("N", (x0 + WT, x1 - WT, z0 + WT, z0 + WT + 0.2), MAGENTA),
                                   ("S", (x0 + WT, x1 - WT, z1 - WT - 0.2, z1 - WT), MAGENTA),
                                   ("W", (x0 + WT, x0 + WT + 0.2, z0 + WT + 0.2, z1 - WT - 0.2), CYAN),
                                   ("O", (x1 - WT - 0.2, x1 - WT, z0 + WT + 0.2, z1 - WT - 0.2), CYAN)):
        _box(lib, anim, "Spielhalle_Neonband_" + nm, a, b, 15.6, 16.0, c, d, col, "Neon", deco=True,
             attrs={"Anim": "neon", "Period": 2.4, "ColorB": Color3(*VIOLET)})
    # 6 Automaten
    for nr, title, accent, kind, (side, pos) in GAMES:
        if side == "W":
            _cabinet(lib, inn, anim, nr, title, accent, kind, x0 + WT, pos, 1, 0)
        else:
            _cabinet(lib, inn, anim, nr, title, accent, kind, pos, z0 + WT, 0, 1)
    _sim(lib, inn, 1, -110, MAGENTA)
    _sim(lib, inn, 2, -90, CYAN)
    # Punkte-Schalter (Station arcade davor) + Preisregal + Highscore-Tafel
    ps = lib.model(inn, "Punkte-Schalter")
    _box(lib, ps, "Tresen", -86, -74, 0, 3.2, -106, -100, NIGHT, "Metal")
    _box(lib, ps, "Tresenplatte", -86.2, -73.8, 3.2, 3.5, -106.2, -99.8, BLACK, "SmoothPlastic", reflectance=0.15)
    _box(lib, ps, "Neonleiste", -85.5, -74.5, 0.9, 1.3, -100, -99.9, MAGENTA, "Neon", deco=True)
    _sign_plain(lib, ps, "PUNKTE-SCHALTER", (8, 1.2), CF.at(-80, 2.3, -99.94, 0), CYAN, NIGHT, "GothamBlack",
                thickness=0.08)
    t = _box(lib, ps, "Terminal", -83.2, -80.8, 3.5, 5.2, -104.4, -104.2, BLACK, "SmoothPlastic", deco=True)
    g = _gui(lib, t, "Back", 40)
    _frame(lib, g, "Grund", 0, 0, 1, 1, SCREEN, 0, 1)
    _label(lib, g, "Text", "PUNKTE\nEINLÖSEN", 0.05, 0.1, 0.9, 0.8, SCREEN_TXT, "GothamBlack", "center", 3)
    _box(lib, ps, "Preisregal", -88, -72, 0, 6, z0 + WT, z0 + WT + 2, NIGHT, "Metal")
    for i, col in enumerate((MAGENTA, CYAN, AMBER, VIOLET, (90, 220, 120))):
        lib.ball(ps, "Preis", (-86 + i * 3.5, 6.55, z0 + WT + 1), 1.3, col, "SmoothPlastic", deco=True)
    hs = _box(lib, ps, "Highscore-Tafel", -90, -72, 7.4, 15.2, z0 + WT, z0 + WT + 0.2, BLACK, "SmoothPlastic")
    g = _gui(lib, hs, "Back", 30)
    _frame(lib, g, "Grund", 0, 0, 1, 1, (16, 10, 30), 0, 1)
    _label(lib, g, "Titel", "HIGHSCORES", 0.03, 0.04, 0.94, 0.18, MAGENTA, "GothamBlack", "center", 3)
    for i, (nr, title, accent, kind, _) in enumerate(GAMES + [(7, "RENNSIMULATOR", CYAN, "", None)]):
        y = 0.26 + i * 0.1
        _label(lib, g, "Spiel", title, 0.06, y, 0.55, 0.085, accent, "GothamBold", "left", 3)
        _label(lib, g, "Wert", "---", 0.64, y, 0.3, 0.085, WHITE, "GothamBold", "right", 3)
    # Wandbilder Westwand
    _sign_plain(lib, inn, "GESCHICK STATT GLÜCK", (30, 3), CF.at(x0 + WT + 0.06, 19.5, -78, 90), MAGENTA, NIGHT,
                "GothamBlack", sub="Nur Können zählt – keine Glücksspiele", sub_color=CYAN)
    for z, txt, col in ((-54, "RENNFIEBER", CYAN), (-102, "BOXENCREW", VIOLET)):
        _sign_plain(lib, inn, txt, (7, 3.2), CF.at(x0 + WT + 0.06, 12.4, z, 90), col, (22, 14, 34), "GothamBlack",
                    sub="Spielhalle · Werkstattmeile", sub_color=WHITE, name="Poster")
    return h


# ================================================================ D4 Meisterschule
MX0, MX1, MZ0, MZ1 = -130.0, -70.0, -175.0, -121.0
M_ROOF, M_TOP = 24.0, 28.0


def _gear(lib, parent, cx, cy, cz, dia, color=AMBER, x_front=None):
    """Zahnrad (Achse X, Vorderseite nach Osten): Scheibe, 4 Zahnleisten, Nabe."""
    lib.cylinder(parent, "Zahnrad", (cx, cy, cz), 0.3, dia, "X", color, "Metal", deco=True)
    for k in range(4):
        t = (0.2, 0.4, 0.5, 0.6)[k]             # gestaffelt um >= 0.05 je Seite: keine (fast) koplanaren Flächen
        cf = CF(cx, cy, cz) * CF.angles(math.radians(k * 45), 0, 0)
        lib.part(parent, "Zahn", (t, dia + 1.0, 0.8), cf, color, "Metal", deco=True)
    lib.cylinder(parent, "Nabe", (cx + 0.4, cy, cz), 0.2, dia * 0.33, "X", SLATE, "Metal", deco=True)


def _desk(lib, parent, c, z):
    m = lib.model(parent, "Schulbank")
    _box(lib, m, "Tischplatte", c - 1.2, c + 1.2, 2.5, 2.7, z - 2.6, z + 2.6, LWOOD, "Wood")
    _box(lib, m, "Stirnwand", c - 1.2, c - 0.9, 0, 2.5, z - 2.4, z + 2.4, SLATE, "Metal")
    _box(lib, m, "Hocker", c + 1.6, c + 3.0, 0, 1.7, z - 0.7, z + 0.7, (43, 102, 121), "SmoothPlastic")
    _box(lib, m, "Lehne", c + 2.8, c + 3.0, 1.7, 3.6, z - 0.7, z + 0.7, (43, 102, 121), "SmoothPlastic")
    return m


def _chart(lib, parent, title, lines, cf, accent):
    p = lib.part(parent, "Lehrtafel", (8, 7, 0.15), cf, (236, 232, 220), "SmoothPlastic")
    g = _gui(lib, p, "Back", 40)
    _frame(lib, g, "Kopf", 0, 0, 1, 0.18, accent, 0, 1)
    _label(lib, g, "Titel", title, 0.04, 0.02, 0.92, 0.14, WHITE, "GothamBlack", "center", 3)
    for i, ln in enumerate(lines):
        _frame(lib, g, "Punkt", 0.06, 0.27 + i * 0.14, 0.03, 0.04, accent, 0, 2, round_=0.5)
        _label(lib, g, "Zeile", ln, 0.12, 0.24 + i * 0.14, 0.84, 0.1, (40, 44, 50), "GothamBold", "left", 3)
    return p


def build_meisterschule(lib, dm, anim):
    h = lib.model(dm, "Meisterschule", attrs={"District": "D4", "Title": "MEISTERSCHULE"})
    shell = lib.model(h, "Huelle")
    x0, x1, z0, z1 = MX0, MX1, MZ0, MZ1
    _box(lib, shell, "Boden", x0, x1, Y_PAVE, 0, z0, z1, SCHOOL_FLOOR, "WoodPlanks")
    _wall(lib, shell, "Nordwand", "x", z0, z0 + WT, x0, x1, 0, M_TOP)
    _wall(lib, shell, "Westwand", "z", x0, x0 + WT, z0 + WT, z1 - WT, 0, M_TOP)
    _wall(lib, shell, "Suedwand", "x", z1 - WT, z1, x0, x1, 0, M_TOP, [(-128, -72, 9, 20)])
    _pane(lib, shell, "x", z1 - WT / 2, -128, -72, 9, 20, "Glasband")
    e_holes = [(-153, -143, 0, 12), (-173, -157, 9, 20), (-139, -123, 9, 20)]
    _wall(lib, shell, "Ostwand", "z", x1 - WT, x1, z0 + WT, z1 - WT, 0, M_TOP, e_holes)
    for a, b in ((-173, -157), (-139, -123)):
        _pane(lib, shell, "z", x1 - WT / 2, a, b, 9, 20, "Glasband")
    for x in (-114, -100, -86):
        _box(lib, shell, "Sprosse", x - 0.25, x + 0.25, 9, 20, z1 - 0.7, z1 - 0.1, FRAME, "Metal")
    _box(lib, shell, "Dach", x0 + WT, x1 - WT, M_ROOF, M_ROOF + 1, z0 + WT, z1 - WT, GRAPHITE, "Metal")
    nb = _box(lib, shell, "Neonband", x1, x1 + 0.2, 22.8, 23.2, z0 + 0.4, z1 - 0.4, AMBER, "Neon", transparency=0.4,
              deco=True)
    set_attrs(nb, {"NeonStrip": True})
    # Holzportal + Schild mit Zahnrad
    fac = lib.model(h, "Fassade")
    for a, b in ((-154.2, -153), (-143, -141.8)):
        _box(lib, fac, "Portal", x1, x1 + 0.5, Y_PAVE, 12, a, b, LWOOD, "Wood")
    _box(lib, fac, "Portalsturz", x1, x1 + 0.5, 12, 13.4, -154.2, -141.8, LWOOD, "Wood")
    _box(lib, fac, "Schildgrund", x1, x1 + 0.2, 15.6, 21.4, -157.4, -138.6, LWOOD, "Wood")
    sg = lib.part(fac, "Schild", (18, 5, 0.2), CF.at(x1 + 0.3, 18.5, -148, 90), SLATE, "SmoothPlastic", deco=True)
    g = _gui(lib, sg, "Back", 40)
    _label(lib, g, "Titel", "MEISTERSCHULE", 0.26, 0.08, 0.72, 0.52, AMBER, "GothamBlack", "center", 3)
    _label(lib, g, "Sub", "Mechaniker-Quiz", 0.3, 0.62, 0.64, 0.3, WHITE, "GothamBold", "center", 3)
    for sy in (-1, 1):
        for sz in (-1, 1):
            lib.part(fac, "SignBolt", (0.08, 0.17, 0.17), CF(x1 + 0.44, 18.5 + sy * 2.25, -148 + sz * 8.0), STEEL,
                     "Metal", deco=True)
    _gear(lib, fac, x1 + 0.55, 18.5, -141.6, 3.4)
    # --- Innen
    inn = lib.model(h, "Innenraum")
    # Kreidetafel / Quiz-Bildschirm (W-Wand, Z -162..-134, Y 6..18)
    wi = x0 + WT
    _box(lib, inn, "Tafelrahmen", wi, wi + 0.3, 5.6, 18.4, -162.4, -133.6, LWOOD, "Wood")
    bd = _box(lib, inn, "Kreidetafel", wi + 0.3, wi + 0.4, 6, 18, -162, -134, CHALK, "Slate")
    g = _gui(lib, bd, "Right", 30)
    chalk = (236, 240, 232)
    _label(lib, g, "Titel", "MECHANIKER-QUIZ", 0.05, 0.04, 0.9, 0.14, chalk, "GothamBlack", "center", 3)
    _frame(lib, g, "Strich", 0.25, 0.19, 0.5, 0.008, chalk, 0.2, 2)
    _label(lib, g, "Frage", "Frage 3 / 10: Welches Bauteil wandelt die Auf- und Abbewegung der Kolben in eine "
           "Drehbewegung um?", 0.06, 0.24, 0.88, 0.2, chalk, "GothamBold", "left", 3)
    for i, ans in enumerate(("A  Nockenwelle", "B  Kurbelwelle", "C  Getriebe", "D  Lichtmaschine")):
        _label(lib, g, "Antwort", ans, 0.08 + (i % 2) * 0.44, 0.5 + (i // 2) * 0.13, 0.4, 0.1,
               AMBER if i == 1 else chalk, "GothamBold", "left", 3)
    _label(lib, g, "Hinweis", "Drücke [E] am Lehrerpult und werde Meister!", 0.06, 0.82, 0.88, 0.1,
           (180, 220, 190), "GothamBold", "center", 3)
    _box(lib, inn, "Kreideablage", wi + 0.3, wi + 0.8, 5.6, 5.85, -161, -135, LWOOD, "Wood")
    # Lehrerpult mit Quiz-Terminal (Station quiz bei (-116,3,-148), Spieler östlich)
    pult = lib.model(inn, "Lehrerpult")
    _box(lib, pult, "Pultplatte", -121.7, -118.3, 2.8, 3.1, -151.7, -144.3, LWOOD, "Wood")
    _box(lib, pult, "Stirnwand", -118.8, -118.5, 0, 2.8, -151.3, -144.7, SLATE, "Metal")
    _box(lib, pult, "Schubladen", -121.3, -119.0, 0, 2.8, -151.3, -149.0, SLATE, "Metal")
    _box(lib, pult, "Monitorfuss", -120.8, -120.2, 3.1, 3.6, -148.3, -147.7, BLACK, "Metal", deco=True)
    mon = _box(lib, pult, "Quiz-Terminal", -120.4, -120.2, 3.6, 5.6, -149.6, -146.4, BLACK, "SmoothPlastic",
               deco=True)
    g = _gui(lib, mon, "Right", 40)
    _frame(lib, g, "Grund", 0.03, 0.04, 0.94, 0.92, SCREEN, 0, 1)
    _label(lib, g, "Text", "QUIZ-TERMINAL", 0.06, 0.12, 0.88, 0.3, AMBER, "GothamBlack", "center", 3)
    _label(lib, g, "Sub", "[E] Prüfung starten", 0.06, 0.5, 0.88, 0.3, SCREEN_TXT, "GothamBold", "center", 3)
    _cyl_y(lib, pult, "Buzzer", -119.2, 3.1, 3.4, -150.6, 0.8, AMBER, "Neon", deco=True)
    # 12 Schulbänke, Gang Z -152..-144 frei
    for c in (-104, -94, -84):
        for z in (-166, -157, -139, -130):
            _desk(lib, inn, c, z)
    # Motor auf Montageständer (-78,0,-130)
    mo = lib.model(inn, "Motor-Schnittmodell")
    _box(lib, mo, "Fuss", -79.5, -76.5, 0, 0.3, -131.5, -128.5, BLACK, "Metal")
    _box(lib, mo, "Staender", -78.2, -77.8, 0.3, 2.3, -130.2, -129.8, (43, 102, 121), "Metal")
    _box(lib, mo, "Oelwanne", -78.8, -77.2, 2.3, 2.6, -131.0, -129.0, BLACK, "Metal")
    _box(lib, mo, "Motorblock", -79.0, -77.0, 2.6, 4.4, -131.2, -128.8, (104, 110, 114), "Metal")
    _box(lib, mo, "Ventildeckel", -78.8, -77.2, 4.4, 4.9, -131.0, -129.0, AMBER, "Metal")
    lib.cylinder(mo, "Riemenscheibe", (-78, 3.2, -131.45), 0.5, 1.3, "Z", STEEL, "Metal", deco=True)
    lib.beam(mo, "Kruemmer", (-79.1, 3.9, -130.6), (-79.1, 3.0, -128.9), 0.35, (154, 102, 80), "Metal", deco=True)
    # Bremsen-Schnittmodell (-78,0,-168)
    br = lib.model(inn, "Bremsen-Schnittmodell")
    _box(lib, br, "Sockel", -79, -77, 0, 2.4, -169, -167, SLATE, "Metal")
    lib.cylinder(br, "Bremsscheibe", (-78, 4.0, -168), 0.3, 3.0, "X", (120, 124, 128), "Metal")
    lib.cylinder(br, "Radnabe", (-78.25, 4.0, -168), 0.3, 1.0, "X", AMBER, "Metal", deco=True)
    _box(lib, br, "Bremssattel", -78.5, -77.5, 4.9, 5.8, -168.7, -167.3, RED, "Metal")
    _box(lib, br, "Halter", -78.3, -77.7, 2.4, 2.6, -168.4, -167.6, STEEL, "Metal")
    # Lehrtafeln: 2 an der Nordwand, 2 an der Westwand neben der Tafel
    _chart(lib, inn, "MOTOR", ["Kolben & Pleuel", "Kurbelwelle", "Ventiltrieb", "Ölkreislauf"],
           CF.at(-112, 11.5, z0 + WT + 0.08, 0), AMBER)
    _chart(lib, inn, "BREMSANLAGE", ["Bremsscheibe", "Bremssattel", "Beläge prüfen", "Bremsflüssigkeit"],
           CF.at(-96, 11.5, z0 + WT + 0.08, 0), RED)
    _chart(lib, inn, "FAHRWERK", ["Stoßdämpfer", "Spur & Sturz", "Reifendruck", "Radlager"],
           CF.at(wi + 0.08, 11.5, -168, 90), TEAL)
    _chart(lib, inn, "ELEKTRIK", ["Batterie 12 V", "Lichtmaschine", "Zündung", "OBD-Diagnose"],
           CF.at(wi + 0.08, 11.5, -128, 90), (60, 110, 200))
    # Leuchten (2 mit Licht)
    for lx, lz, lit in ((-110, -148, True), (-85, -148, True), (-110, -162, False), (-85, -134, False)):
        _cyl_y(lib, inn, "Pendelstange", lx, 21.1, M_ROOF, lz, 0.2, STEEL, "Metal", deco=True)
        bar = _box(lib, inn, "Leuchtbalken", lx - 6, lx + 6, 20.8, 21.1, lz - 0.6, lz + 0.6, NEON_WHITE, "Neon",
                   deco=True)
        if lit:
            lib.point_light(bar, 28, 0.9, HALL_LIGHT)
    return h


# ================================================================ D5 Auktionshaus
AX0, AX1, AZ0, AZ1 = 70.0, 130.0, -121.0, -31.0
A_ROOF, A_TOP = 30.0, 34.0
PORT_Z0, PORT_Z1, PORT_X = -98.0, -54.0, 78.0
DESK_X = 84.5          # Bieterkasse / Einlieferung (Stationen auction / auction_consign)


def _chandelier(lib, parent, x, z):
    m = lib.model(parent, "Kronleuchter")
    _cyl_y(lib, m, "Kette", x, 26.6, A_ROOF, z, 0.2, BRASS, "Metal", deco=True)
    disc = lib.cylinder(m, "Kranz", (x, 26.4, z), 0.4, 8, "Y", BRASS, "Metal", deco=True)
    lib.ball(m, "Zapfen", (x, 25.95, z), 1.0, BRASS, "Metal", deco=True)
    for k in range(6):
        a = math.radians(k * 60)
        _cyl_y(lib, m, "Kerze", x + 3.3 * math.cos(a), 26.6, 27.6, z + 3.3 * math.sin(a), 0.35, WARM, "Neon",
               deco=True)
    lib.point_light(disc, 32, 1.0, WARM)
    return m


def build_auktionshaus(lib, dm, anim):
    h = lib.model(dm, "Auktionshaus", attrs={"District": "D5", "Title": "AUKTIONSHAUS"})
    shell = lib.model(h, "Huelle")
    x0, x1, z0, z1 = AX0, AX1, AZ0, AZ1
    # Böden: Holz innen, Marmor im Portikus
    _box(lib, shell, "Boden", x0, x1, Y_PAVE, 0, z0, PORT_Z0, WOOD, "WoodPlanks", reflectance=0.05)
    _box(lib, shell, "Boden", PORT_X, x1, Y_PAVE, 0, PORT_Z0, PORT_Z1, WOOD, "WoodPlanks", reflectance=0.05)
    _box(lib, shell, "Boden", x0, x1, Y_PAVE, 0, PORT_Z1, z1, WOOD, "WoodPlanks", reflectance=0.05)
    _box(lib, shell, "Portikusboden", x0, PORT_X, Y_PAVE, 0, PORT_Z0, PORT_Z1, MARBLE, "Marble")
    wall = dict(color=CREAM, material="SmoothPlastic")
    wins = [(79, 85, 6, 22), (91, 97, 6, 22), (103, 109, 6, 22), (115, 121, 6, 22)]
    _wall(lib, shell, "Suedwand", "x", z1 - WT, z1, x0, x1, 0, A_TOP, wins, **wall)
    _wall(lib, shell, "Nordwand", "x", z0, z0 + WT, x0, x1, 0, A_TOP, wins, **wall)
    _pane(lib, shell, "x", z1 - WT / 2, 79, 121, 6, 22, "Fensterband")
    _pane(lib, shell, "x", z0 + WT / 2, 79, 121, 6, 22, "Fensterband")
    _wall(lib, shell, "Ostwand", "z", x1 - WT, x1, z0 + WT, z1 - WT, 0, A_TOP, **wall)
    _wall(lib, shell, "Westwand", "z", x0, x0 + WT, z0 + WT, PORT_Z0, 0, A_TOP, **wall)
    _wall(lib, shell, "Westwand", "z", x0, x0 + WT, PORT_Z1, z1 - WT, 0, A_TOP, **wall)
    _wall(lib, shell, "Ruecksprung", "x", PORT_Z0 - WT, PORT_Z0, x0 + WT, PORT_X, 0, A_TOP, **wall)
    _wall(lib, shell, "Ruecksprung", "x", PORT_Z1, PORT_Z1 + WT, x0 + WT, PORT_X, 0, A_TOP, **wall)
    _wall(lib, shell, "Portalwand", "z", PORT_X, PORT_X + WT, PORT_Z0 - WT, PORT_Z1 + WT, 0, A_TOP,
          [(-82, -70, 0, 14)], **wall)
    _box(lib, shell, "Dach", PORT_X + WT, x1 - WT, A_ROOF, A_ROOF + 1, z0 + WT, z1 - WT, GRAPHITE, "Metal")
    _box(lib, shell, "Dach", x0 + WT, PORT_X + WT, A_ROOF, A_ROOF + 1, z0 + WT, PORT_Z0 - WT, GRAPHITE, "Metal")
    _box(lib, shell, "Dach", x0 + WT, PORT_X + WT, A_ROOF, A_ROOF + 1, PORT_Z1 + WT, z1 - WT, GRAPHITE, "Metal")
    # Messing-Pilaster alle 12 und Messing-Gesims bei Y 30
    fac = lib.model(h, "Fassade")
    for x in (76, 88, 100, 112, 124):
        _box(lib, fac, "Pilaster", x - 0.6, x + 0.6, Y_PAVE, 29.4, z1, z1 + 0.3, BRASS, "Metal")
        _box(lib, fac, "Pilaster", x - 0.6, x + 0.6, Y_PAVE, 29.4, z0 - 0.3, z0, BRASS, "Metal")
    for z in (-115, -103, -91, -79, -67, -55, -43):
        _box(lib, fac, "Pilaster", x1, x1 + 0.3, Y_PAVE, 29.4, z - 0.6, z + 0.6, BRASS, "Metal")
    for z in (-115, -103, -43):
        _box(lib, fac, "Pilaster", x0 - 0.3, x0, Y_PAVE, 29.4, z - 0.6, z + 0.6, BRASS, "Metal")
    _box(lib, fac, "Gesims", x0 - 0.5, x1 + 0.5, 29.4, 30.4, z1, z1 + 0.5, BRASS, "Metal")
    _box(lib, fac, "Gesims", x0 - 0.5, x1 + 0.5, 29.4, 30.4, z0 - 0.5, z0, BRASS, "Metal")
    _box(lib, fac, "Gesims", x1, x1 + 0.5, 29.4, 30.4, z0, z1, BRASS, "Metal")
    _box(lib, fac, "Gesims", x0 - 0.5, x0, 29.4, 30.4, z0, PORT_Z0, BRASS, "Metal")
    _box(lib, fac, "Gesims", x0 - 0.5, x0, 29.4, 30.4, PORT_Z1, z1, BRASS, "Metal")
    # Fahnen-Banner an den Westwand-Stücken
    for z, txt in ((-109, "VERSTEIGERUNG"), (-37, "AUKTION")):
        bn = _box(lib, fac, "Banner", x0 - 0.15, x0, 12, 26, z - 1.8, z + 1.8, BURGUNDY, "Fabric", deco=True)
        lib.surface_text(bn, "\n".join(txt), face="Left", text_color=BRASS, font="GothamBlack", px_per_stud=30)
    # --- Portikus: 6 Säulen, Gebälk, Giebel
    port = lib.model(h, "Portikus")
    for z in (-97, -90, -83, -69, -62, -55):
        _cyl_y(lib, port, "Saeulenfuss", 72, 0, 0.8, z, 3.2, BRASS, "Metal")
        _cyl_y(lib, port, "Saeule", 72, 0.8, 19.2, z, 2.4, CREAM, "SmoothPlastic")
        _cyl_y(lib, port, "Kapitell", 72, 19.2, 20, z, 3.2, BRASS, "Metal")
    gz0, gz1 = -98.4, -53.6
    _box(lib, port, "Gebaelk", 69.6, PORT_X + 0.4, 20, 23, gz0, gz1, CREAM, "SmoothPlastic")
    _box(lib, port, "Gebaelkband", 69.3, 69.6, 22.4, 23.0, gz0, gz1, BRASS, "Metal")
    lib.sign(port, "AUKTIONSHAUS", (28, 1.9), CF.at(69.5, 21.25, -76, -90), BRASS, DARKWOOD, "GothamBlack",
             name="Gebaelkschild", thickness=0.2)
    half = (gz1 - gz0) / 2
    zm = (gz0 + gz1) / 2
    for s in (-1, 1):   # -1: Nordhälfte (hohe Seite nach Süden = zur Mitte)
        lib.wedge(port, "Giebel", (PORT_X + 0.4 - 69.7, 8, half), CF.at((69.7 + PORT_X + 0.4) / 2, 27, zm + s * half / 2,
                                                                     0 if s < 0 else 180), CREAM, "SmoothPlastic")
        gx = 69.5 if s < 0 else 69.52
        lib.beam(port, "Giebelgesims", (gx, 23.0, zm + s * half), (gx, 31.0, zm), 0.5, BRASS, "Metal", deco=True)
    lib.cylinder(port, "Hammerscheibe", (69.575, 26.2, zm), 0.25, 4, "X", BRASS, "Metal", deco=True)
    hcf = CF(69.4, 26.2, zm) * CF.angles(math.radians(35), 0, 0)
    lib.part(port, "Hammerstiel", (0.1, 2.6, 0.35), hcf * CF(0, -0.4, 0), DARKWOOD, "Wood", deco=True)
    lib.part(port, "Hammerkopf", (0.14, 0.8, 1.6), hcf * CF(0.01, 1.0, 0), DARKWOOD, "Wood", deco=True)
    # Holz-Doppeltür (offen an die Portalwand geklappt) + Messing-Faschen
    for a, b in ((-82.6, -82), (-70, -69.4)):
        _box(lib, port, "Tuerfasche", PORT_X - 0.3, PORT_X, 0, 14, a, b, BRASS, "Metal")
    _box(lib, port, "Tuersturz", PORT_X - 0.3, PORT_X, 14, 14.8, -82.6, -69.4, BRASS, "Metal")
    for a, b, hz in ((-88.8, -82.8, -86.0), (-69.2, -63.2, -66.0)):
        _box(lib, port, "Tuerfluegel", PORT_X - 0.6, PORT_X - 0.3, 0, 14, a, b, DARKWOOD, "Wood")
        _box(lib, port, "Tuergriff", PORT_X - 0.8, PORT_X - 0.6, 5.5, 8.5, hz - 0.15, hz + 0.15, BRASS, "Metal",
             deco=True)
    # Kuppel auf dem Dach
    cup = lib.model(h, "Kuppel")
    # Tambour Ø16 bis 40, Kuppel Ø14 mit Mitte 40 (untere Hälfte im Tambour, sichtbar eine volle Halbkugel
    # 40..47), Laterne auf dem Scheitel
    _cyl_y(lib, cup, "Tambour", 100, A_ROOF + 1, 40, -76, 16, CREAM, "SmoothPlastic")
    _cyl_y(lib, cup, "Kranzgesims", 100, 39.2, 39.8, -76, 16.8, BRASS, "Metal")
    lib.ball(cup, "Kuppel", (100, 40.0, -76), 14, BRASS, "Metal")
    _cyl_y(lib, cup, "Laterne", 100, 46.9, 48.9, -76, 2.4, AMBER, "Neon", deco=True)
    lib.ball(cup, "Knauf", (100, 49.1, -76), 0.8, BRASS, "Metal", deco=True)

    # --- Innen
    inn = lib.model(h, "Innenraum")
    wx = x0 + WT
    for a, b, c, d in ((x0 + WT, x1 - WT, z1 - WT - 0.2, z1 - WT),               # Süd
                       (x0 + WT, x1 - WT, z0 + WT, z0 + WT + 0.2),               # Nord
                       (x1 - WT - 0.2, x1 - WT, z0 + WT + 0.2, z1 - WT - 0.2),   # Ost
                       (wx, wx + 0.2, z0 + WT + 0.2, PORT_Z0 - WT),              # West N
                       (wx, wx + 0.2, PORT_Z1 + WT, z1 - WT - 0.2),              # West S
                       (PORT_X + WT, PORT_X + WT + 0.2, PORT_Z0 - WT, -82),       # Portalwand
                       (PORT_X + WT, PORT_X + WT + 0.2, -70, PORT_Z1 + WT)):
        _box(lib, inn, "Wandsockel", a, b, 0, 4, c, d, WOOD, "Wood")
    _box(lib, inn, "Laeufer", PORT_X + WT + 0.2, 104, 0, 0.05, -86, -66, BURGUNDY, "Fabric", deco=True)
    # Bühne X 108..128, Z -98..-54, Oberkante 3; Treppe X 104..108, Z -80..-72
    # bis an den Wandsockel der Ostwand (X 129) - kein Spalt hinter dem Vorhang
    _box(lib, inn, "Buehne", 108, 129, 0, 2.8, -98, -54, BURGUNDY, "Fabric")
    _box(lib, inn, "Buehnenboden", 108, 129, 2.8, 3.0, -98, -54, WOOD, "WoodPlanks", reflectance=0.08)
    for a, b in ((-98, -80), (-72, -54)):
        _box(lib, inn, "Buehnenkante", 107.8, 108, 2.6, 3.0, a, b, BRASS, "Metal", deco=True)
    for k in range(4):
        _box(lib, inn, "Stufe", 104 + k, 108, 0.75 * k, 0.75 * (k + 1), -80, -72, BURGUNDY, "Fabric")
    for a, b in ((-97.6, -97.0), (-55.0, -54.4)):
        _box(lib, inn, "Vorhang", 120, 128.2, 3.0, A_ROOF, a, b, BURGUNDY, "Fabric")
    _box(lib, inn, "Schabracke", 126.8, 128.8, 28.4, A_ROOF, -97.0, -55.0, BURGUNDY, "Fabric")
    # LED-Wand
    _box(lib, inn, "LED-Rahmen", 128.95, x1 - WT, 11.5, 28.3, -100.5, -51.5, BRASS, "Metal")
    led = _box(lib, inn, "LED-Wand", 128.8, 128.95, 12, 28, -100, -52, (8, 8, 12), "SmoothPlastic")
    # SurfaceGui "AuctionScreen" mit den Labels Title / Lot / Bid / Time (AuctionService schreibt die Texte)
    g = _gui(lib, led, "Left", 30, "AuctionScreen")
    _frame(lib, g, "Grund", 0, 0, 1, 1, (14, 10, 12), 0, 1)
    _frame(lib, g, "Kopfband", 0.02, 0.04, 0.96, 0.16, (40, 16, 22), 0, 2)
    _label(lib, g, "Title", "AUKTIONSHAUS", 0.04, 0.06, 0.92, 0.12, BRASS, "GothamBlack", "center", 3)
    _frame(lib, g, "Feld", 0.02, 0.23, 0.96, 0.55, (40, 16, 22), 0, 2)
    _label(lib, g, "Lot", "Gerade keine Versteigerung", 0.04, 0.25, 0.92, 0.2, WHITE, "GothamBlack", "center", 3)
    _label(lib, g, "Bid", "Einliefern am Schalter rechts", 0.04, 0.47, 0.92, 0.15, AMBER, "GothamBlack", "center", 3)
    _label(lib, g, "Time", "", 0.04, 0.63, 0.92, 0.12, (255, 120, 110), "GothamBold", "center", 3)
    _label(lib, g, "Laufband", "SONDERMODELLE UND SPIELER-AUKTIONEN · EINLIEFERUNG AM SCHALTER RECHTS · BIETEN AN DER "
           "KASSE", 0.02, 0.8, 0.96, 0.14, CREAM, "GothamBold", "center", 3)
    # Pult des Auktionators mit Klangholz
    lp = lib.model(inn, "Rednerpult")
    _box(lib, lp, "Pult", 110.3, 111.7, 3.0, 6.6, -96, -94, DARKWOOD, "Wood")
    _box(lib, lp, "Pultplatte", 110.1, 111.9, 6.6, 6.8, -96.2, -93.8, WOOD, "Wood")
    _box(lib, lp, "Messingschild", 110.2, 110.3, 4.9, 6.1, -95.7, -94.3, BRASS, "Metal", deco=True)
    lib.cylinder(lp, "Klangholz", (110.8, 6.875, -94.6), 0.15, 1.1, "Y", BRASS, "Metal", deco=True)
    gav = lib.model(anim, "Auktionshammer", attrs={"Anim": "gavel", "Period": 6, "Angle": 35})
    ham = lib.model(gav, "Hammer")
    knob = lib.ball(ham, "Knauf", (110.8, 6.95, -96.0), 0.3, DARKWOOD, "Wood", deco=True)
    lib.set_primary(ham, knob)
    lib.beam(ham, "Stiel", (110.8, 6.95, -96.0), (110.8, 7.2, -94.6), 0.16, DARKWOOD, "Wood", deco=True)
    lib.cylinder(ham, "Kopf", (110.8, 7.2, -94.6), 1.0, 0.5, "X", DARKWOOD, "Wood", deco=True)
    # Drehbühne mit gt_coupe in Burgund (Anim turntable, 30 s je Umdrehung)
    tt = lib.model(anim, "Auktion_Drehbuehne", attrs={"Anim": "turntable", "Speed": 12})
    disc = lib.cylinder(tt, "Drehteller", (118, 3.15, -76), 0.3, 19.4, "Y", DARKWOOD, "Wood")
    lib.cylinder(tt, "Messingring", (118, 3.1, -76), 0.2, 20, "Y", BRASS, "Metal", deco=True)
    lib.set_primary(tt, disc)
    with lib.section("D5 Auktionshaus (Auto)"):
        lib.clone_car(tt, "gt_coupe", CF.at(118, 3.3, -76, 60), (128, 22, 38), name="Los017_GT_Coupe",
                      attrs={"Role": "AuctionLot"})
    # Sitzstufen (3 Podeste je Block, X 91..106) mit Burgund-Bänken, Blick nach Osten
    for za, zb in ((-108, -88), (-64, -44)):
        blk = lib.model(inn, "Tribuene")
        for n in range(1, 4):
            xa = 91 + 5 * (n - 1)
            top = 0.6 * n
            _box(lib, blk, "Podest", xa, xa + 5, 0, top, za, zb, WOOD, "WoodPlanks")
            _box(lib, blk, "Sitzbank", xa + 1.2, xa + 2.8, top, top + 1.5, za + 0.6, zb - 0.6, BURGUNDY, "Fabric")
            _box(lib, blk, "Lehne", xa + 0.9, xa + 1.2, top, top + 3.3, za + 0.6, zb - 0.6, BURGUNDY, "Fabric")
    # Bieterkasse (Station auction, Spieler südlich) und Einlieferung (auction_consign, Spieler nördlich)
    for nm, za, zb, face_z, yaw, txt, sub in (("Bieterkasse", -106, -102, -102, 0, "BIETERKASSE", "Bieterkarte holen"),
                                             ("Einlieferung", -50, -46, -50, 180, "EINLIEFERUNG", "Auto einliefern")):
        d = lib.model(inn, nm)
        dx = DESK_X - 81           # Tresen X 79.5..89.5 (Station bei DESK_X, contract.py)
        _box(lib, d, "Tresen", 76.2 + dx, 85.8 + dx, 0, 3.2, za + 0.2, zb - 0.2, DARKWOOD, "Wood")
        _box(lib, d, "Tresenplatte", 76 + dx, 86 + dx, 3.2, 3.5, za, zb, MARBLE, "Marble")
        s = 1 if yaw == 0 else -1
        lib.sign(d, txt, (6, 1.6), CF.at(DESK_X, 1.9, face_z - s * 0.2 + s * 0.06, yaw), BRASS, BURGUNDY,
                 "GothamBlack", thickness=0.12, bolts=False, name="Tresenschild", sub=sub, sub_color=CREAM)
        mz = (za + zb) / 2
        sc = lib.part(d, "Bildschirm", (2.4, 1.5, 0.15), CF.at(83.5 + dx, 4.4, mz + s * 0.2, yaw) *
                      CF.angles(math.radians(-15), 0, 0), BLACK, "SmoothPlastic", deco=True)
        g = _gui(lib, sc, "Back", 40)
        _frame(lib, g, "Grund", 0.03, 0.05, 0.94, 0.9, (40, 16, 22), 0, 1)
        _label(lib, g, "Text", "BIETEN" if yaw == 0 else "EINLIEFERN", 0.05, 0.15, 0.9, 0.7, BRASS, "GothamBlack",
               "center", 3)
        _box(lib, d, "Bildschirmfuss", 83.3 + dx, 83.7 + dx, 3.5, 3.9, mz - 0.2 + s * 0.2, mz + 0.2 + s * 0.2, BLACK,
             "Metal", deco=True)
        _cyl_y(lib, d, "Bieterkelle", 78.6 + dx, 3.5, 3.6, mz, 1.3, BURGUNDY, "SmoothPlastic", deco=True)
    # Kronleuchter + Bühnen-Spot
    for z in (-98, -76, -54):
        _chandelier(lib, inn, 94, z)
    _box(lib, inn, "Spotschiene", 117.8, 118.2, 29.0, A_ROOF, -76.2, -75.8, STEEL, "Metal", deco=True)
    spot = _box(lib, inn, "Buehnenspot", 117.4, 118.6, 27.8, 29.0, -76.6, -75.4, BLACK, "Metal", deco=True)
    lib.spot_light(spot, 32, 2.0, (255, 236, 210), 55, "Bottom", True, "Buehnenlicht")
    return h


# ================================================================ D6 Credit-Center
CX0, CX1, CZ0, CZ1 = 70.0, 130.0, -175.0, -129.0
C_ROOF, C_TOP = 24.0, 28.0

PACKS = [("Kleine Werkzeugkasse", "3.000", ""), ("Service-Kasse", "16.500", "+10 % Bonus"),
         ("Werkstatt-Kasse", "34.500", "+15 % Bonus"), ("Meister-Kasse", "72.000", "+20 % Bonus"),
         ("Flotten-Kasse", "187.500", "+25 % Bonus")]


def build_credit(lib, dm, anim):
    h = lib.model(dm, "Credit-Center", attrs={"District": "D6", "Title": "CREDIT-CENTER"})
    shell = lib.model(h, "Huelle")
    x0, x1, z0, z1 = CX0, CX1, CZ0, CZ1
    _box(lib, shell, "Boden", x0, x1, Y_PAVE, 0, z0, z1, PURPLE_FLOOR, "Marble", reflectance=0.1)
    wall = dict(color=PURPLE_D, material="Metal")
    _wall(lib, shell, "Nordwand", "x", z0, z0 + WT, x0, x1, 0, C_TOP, **wall)
    _wall(lib, shell, "Suedwand", "x", z1 - WT, z1, x0, x1, 0, C_TOP, **wall)
    _wall(lib, shell, "Ostwand", "z", x1 - WT, x1, z0 + WT, z1 - WT, 0, C_TOP, **wall)
    w_holes = [(-157, -147, 0, 12), (-171, -161, 3, 11), (-143, -133, 3, 11)]
    _wall(lib, shell, "Westwand", "z", x0, x0 + WT, z0 + WT, z1 - WT, 0, C_TOP, w_holes, **wall)
    for a, b in ((-171, -161), (-143, -133)):
        _pane(lib, shell, "z", x0 + WT / 2, a, b, 3, 11, "Schaufenster")
    _box(lib, shell, "Dach", x0 + WT, x1 - WT, C_ROOF, C_ROOF + 1, z0 + WT, z1 - WT, GRAPHITE, "Metal")
    nb = _box(lib, shell, "Neonband", x0 - 0.2, x0, 25.6, 26.0, z0 + 0.4, z1 - 0.4, PURPLE_NEON, "Neon",
              transparency=0.4, deco=True)
    set_attrs(nb, {"NeonStrip": True})
    fac = lib.model(h, "Fassade")
    for a, b in ((-157.6, -157), (-147, -146.4)):
        _box(lib, fac, "Tuerrahmen", x0 - 0.3, x0, Y_PAVE, 12, a, b, PURPLE_NEON, "Neon", deco=True)
    _box(lib, fac, "Tuerrahmen", x0 - 0.3, x0, 12, 12.6, -157.6, -146.4, PURPLE_NEON, "Neon", deco=True)
    lib.sign(fac, "CREDIT-CENTER", (20, 3.6), CF.at(x0 - 0.1, 15.4, -152, -90), PURPLE_TXT, PURPLE_FLOOR,
             "GothamBlack", name="Hauptschild", sub="Credits für deine Werkstatt", sub_color=AMBER)
    lib.cylinder(fac, "Muenze", (x0 - 0.2, 21, -152), 0.4, 6, "X", AMBER, "Metal")
    coin = lib.cylinder(fac, "Muenzpraegung", (x0 - 0.45, 21, -152), 0.1, 4.6, "X", (255, 196, 90), "Metal",
                        deco=True)
    lib.surface_text(coin, "C", face="Left", text_color=(150, 90, 20), font="GothamBlack")
    # --- Innen
    inn = lib.model(h, "Innenraum")
    for a, b, c, d in ((78, 114, -168.2, -167.8), (78, 114, -136.2, -135.8), (77.8, 78.2, -167.8, -136.2),
                       (113.8, 114.2, -167.8, -136.2)):
        _box(lib, inn, "Goldeinlage", a, b, 0, 0.05, c, d, AMBER, "Metal", deco=True)
    lib.cylinder(inn, "Bodenmedaillon", (96, 0.03, -152), 0.06, 8, "Y", AMBER, "Metal", deco=True)
    # Kassentresen X 118..124, Z -166..-138, 3 Terminals
    ks = lib.model(inn, "Kassentresen")
    _box(lib, ks, "Tresen", 118.2, 124, 0, 3.2, -165.8, -138.2, PURPLE_D, "Metal")
    _box(lib, ks, "Tresenplatte", 118, 124, 3.2, 3.5, -166, -138, (225, 215, 235), "Marble", reflectance=0.1)
    _box(lib, ks, "Neonleiste", 118.05, 118.2, 1.0, 1.4, -165.5, -138.5, PURPLE_NEON, "Neon", deco=True)
    for z in (-159, -152, -145):
        _box(lib, ks, "Terminalfuss", 119.3, 119.9, 3.5, 4.1, z - 0.3, z + 0.3, BLACK, "Metal", deco=True)
        t = lib.part(ks, "Terminal", (0.15, 1.6, 2.4), CF(119.55, 4.8, z) * CF.angles(0, 0, math.radians(-12)), BLACK,
                     "SmoothPlastic", deco=True)
        g = _gui(lib, t, "Left", 40)
        _frame(lib, g, "Grund", 0.04, 0.05, 0.92, 0.9, PURPLE_FLOOR, 0, 1)
        _label(lib, g, "Text", "CREDITS\nKAUFEN", 0.06, 0.12, 0.88, 0.76, PURPLE_TXT, "GothamBlack", "center", 3)
    # Kassiererin (5 Parts)
    fig = lib.model(inn, "Kasse_NPC")
    px, pz = 126.2, -152
    _box(lib, fig, "Beine", px - 0.4, px + 0.4, 0, 2.8, pz - 0.8, pz + 0.8, (40, 45, 55), "SmoothPlastic")
    _box(lib, fig, "Oberkoerper", px - 0.45, px + 0.45, 2.8, 4.8, pz - 0.9, pz + 0.9, PURPLE, "SmoothPlastic")
    for s in (-1, 1):
        _box(lib, fig, "Arm", px - 0.3, px + 0.3, 2.9, 4.8, pz + s * 0.9, pz + s * 1.4, PURPLE, "SmoothPlastic",
             deco=True)
    _box(lib, fig, "Kopf", px - 0.55, px + 0.55, 4.8, 5.9, pz - 0.55, pz + 0.55, SKIN, "SmoothPlastic", deco=True)
    _sign_plain(lib, inn, "CREDIT-KASSE", (16, 2.6), CF.at(x1 - WT - 0.06, 12, -152, -90), PURPLE_TXT, PURPLE_FLOOR,
                "GothamBlack", sub="Sicher bezahlen · sofort gutgeschrieben", sub_color=AMBER)
    # Preiswand (S-Wand, X 80..116, Y 6..16) mit 5 Paketen
    wi = z1 - WT
    _sign_plain(lib, inn, "CREDIT-PAKETE", (20, 1.8), CF.at(98, 17.4, wi - 0.06, 180), AMBER, PURPLE_FLOOR,
                "GothamBlack")
    for i, (nm, credits, bonus) in enumerate(PACKS):
        xa = 80 + i * 7.4
        pnl = _box(lib, inn, "Paket", xa, xa + 6.4, 6, 16, wi - 0.2, wi, PURPLE_FLOOR, "SmoothPlastic")
        g = _gui(lib, pnl, "Front", 30)
        _frame(lib, g, "Rahmen", 0.03, 0.02, 0.94, 0.96, (60, 38, 92), 0, 1)
        _frame(lib, g, "Muenze", 0.32, 0.08, 0.36, 0.22, AMBER, 0, 2, round_=0.5)
        _label(lib, g, "C", "C", 0.32, 0.1, 0.36, 0.18, (150, 90, 20), "GothamBlack", "center", 3)
        _label(lib, g, "Name", nm, 0.06, 0.34, 0.88, 0.14, PURPLE_TXT, "GothamBold", "center", 3)
        _label(lib, g, "Credits", credits, 0.06, 0.5, 0.88, 0.2, AMBER, "GothamBlack", "center", 3)
        _label(lib, g, "Einheit", "CREDITS", 0.06, 0.7, 0.88, 0.08, PURPLE_TXT, "GothamBold", "center", 3)
        if bonus:
            _label(lib, g, "Bonus", bonus, 0.1, 0.82, 0.8, 0.1, (120, 230, 150), "GothamBlack", "center", 3)
    # Tresortür Ø16 an der N-Wand mit drehendem Rad (Anim vault)
    vt = lib.model(inn, "Tresor")
    lib.cylinder(vt, "Tresorrahmen", (100, 9, -173.95), 0.5, 18, "Z", (96, 100, 108), "Metal")
    lib.cylinder(vt, "Tresortuer", (100, 9, -174.0), 1.5, 16, "Z", (150, 156, 164), "Metal", reflectance=0.1)
    for k in range(6):
        a = math.radians(k * 60 + 30)
        lib.cylinder(vt, "Riegelbolzen", (100 + 6.6 * math.cos(a), 9 + 6.6 * math.sin(a), -173.1), 0.3, 0.9, "Z",
                     STEEL, "Metal", deco=True)
    for y in (4.5, 13.5):
        _box(lib, vt, "Scharnier", 107.4, 109.4, y - 0.7, y + 0.7, -173.9, -172.9, (60, 64, 70), "Metal")
    _sign_plain(lib, vt, "TRESOR", (6, 1.3), CF.at(100, 18.6, z0 + WT + 0.06, 0), AMBER, PURPLE_FLOOR,
                "GothamBlack")
    wheel = lib.model(anim, "Tresorrad", attrs={"Anim": "vault", "Axis": "X", "Period": 8})
    hub = lib.cylinder(wheel, "Nabe", (100, 9, -172.95), 0.9, 2, "Z", AMBER, "Metal", deco=True)
    lib.set_primary(wheel, hub)
    for k in range(3):
        cf = CF(100, 9, -173.1) * CF.angles(0, 0, math.radians(k * 60))
        lib.part(wheel, "Speiche", (0.4, 7, 0.3 - 0.1 * k), cf, STEEL, "Metal", deco=True)
    # 2 Glasvitrinen mit Münzstapeln
    for cz in (-140, -164):
        v = lib.model(inn, "Muenzvitrine")
        _box(lib, v, "Sockel", 88.5, 91.5, 0, 3, cz - 1.5, cz + 1.5, PURPLE_D, "Metal")
        _box(lib, v, "Vitrine", 88.7, 91.3, 3, 5.8, cz - 1.3, cz + 1.3, GLASS, "Glass", transparency=0.55,
             reflectance=0.15)
        _cyl_y(lib, v, "Muenzstapel", 89.5, 3, 4.0, cz - 0.3, 1.2, AMBER, "Metal", deco=True)
        _cyl_y(lib, v, "Muenzstapel", 90.5, 3, 4.6, cz + 0.4, 1.2, AMBER, "Metal", deco=True)
    # 2 Lichter
    for lx in (92, 110):
        _cyl_y(lib, inn, "Pendelstange", lx, 21.3, C_ROOF, -152, 0.2, STEEL, "Metal", deco=True)
        lamp = lib.cylinder(inn, "Pendelleuchte", (lx, 21, -152), 0.6, 4, "Y", PURPLE_TXT, "Neon", deco=True)
        lib.point_light(lamp, 30, 0.9, (235, 220, 255))
    return h


# ================================================================ Einstieg
def build(city, lib, tree):
    """Baut Platzgebaeude (siehe docs/CITY_SPEC.md §6 D3-D6)."""
    dm = lib.model(lib.folder(city, "Districts"), NAME,
                   attrs={"Districts": "D3 Spielhalle, D4 Meisterschule, D5 Auktionshaus, D6 Credit-Center"})
    anim = lib.folder(lib.folder(city, "Animated"), NAME)
    with lib.section("D3 Spielhalle"):
        build_spielhalle(lib, dm, anim)
    with lib.section("D4 Meisterschule"):
        build_meisterschule(lib, dm, anim)
    with lib.section("D5 Auktionshaus"):
        build_auktionshaus(lib, dm, anim)
    with lib.section("D6 Credit-Center"):
        build_credit(lib, dm, anim)
    return dm
