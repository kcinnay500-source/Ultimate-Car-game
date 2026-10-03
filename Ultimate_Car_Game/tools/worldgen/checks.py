#!/usr/bin/env python3
"""Prüft die gebaute Stadt (Workspace.City) im Place.

  python3 tools/worldgen/checks.py [/tmp/claude-0/foundation.rbxlx] [--verbose]

Prüfungen:
  * alle BaseParts verankert; keine Parts unter Y -3 (außer Liste INTENDED_LOW)
  * Z-Fighting-Kandidaten: exakt koplanare, gleich orientierte Flächen, die sich überlappen
    (Oberseiten und senkrechte Seiten; Vorlagen-Autos ausgenommen), und fast koplanare (0 < Abstand < 0.05)
  * schwebende Geometrie: Berührungsgraph der AABBs (Toleranz 0.06) - jede Gruppe muss die Grasplatte erreichen
  * Bordsteinabsenkungen frei von Laternen, Bäumen, Baken, Pylonen (§9.1)
  * Spielerseite jeder Station 10 x 10 frei (§1.3), Kamera-Strahlen (Zoom 10/16/24, ±35°) hinter Stationen und
    Ankunftspunkten
  * Parts und Lichter je Bereich gegen das Budget (CITY_SPEC §10)
  * Stationen / Ankunftspunkte / CitySpawn gemäß Vertrag (Prompt-Werte, Attachment Arrival, freier Boden)
  * Stadt-Parts in Plot-Grundflächen (außer PlotSlots.*.Vacant und Bodenplatte)
  * Anim-Attribute nur unter City.Animated; Plot-Vorlage: Start deaktiviert, Anker vorhanden
  * Befahrbarkeit (drive.py): Verkehrsschleifen A/B1/B2/T in mehreren Spuren ohne Stufe > 0.6 und ohne
    (unsichtbare) Hindernisse; CarSpawns (Stellfläche inkl. Ausweichplätze, Ausfahrt bis zur Schleife); Plot-CarSpawn
    und Einfahrt an allen 8 Slots (Vorlage mit Vollausbau); Checkpoints der Teststrecke; Auktions- und
    Automaten-Bildschirme; kein Soon an den Stationen der Ausbaustufe 2/3
  * Zonen der Ausbaustufe 4 (PHASE4_CONTRACT §1; Workspace.Lobby, Workspace.Tycoon, falls vorhanden): verankert,
    Z-Fighting / fast koplanar / schwebend wie die Stadt, ganz außerhalb der Stadtgrenzen X ±450 / Z ±320 und ohne
    AABB-Überschneidung mit Stadt-Parts, Budget (Lobby 1500/12, Tycoon 2500/20), Stationen/Ankünfte/Spawn nach
    Vertrag (Spawn Enabled=false), Lobby.Stations mit MiniTab=lobby + LobbyAction, Tycoon.Plots.Slot_1..8 mit
    Base/Sign/StartPad(TycoonSlot)/Anchor/CollectPad(TycoonPad)/ButtonsRoot, Anim nur unter <Zone>.Animated (+ Plots)
  * Stufen-Vorlagen ServerStorage.TycoonTemplates.<typ>.Stage_1..5 (PHASE4_CONTRACT §8, tycoon_templates.py): Aufbau
    (Root als PrimaryPart bei (0, 0.5, 0), Buttons mit 4 Kaufpads + Label Name/Price, StagePad (Stufe 1-4), Hidden mit
    Producer_1..4, CashDisplay bei (-20, 3, 20) mit Label "Bargeld"), verankert, innerhalb X/Z ±34 und Y >= 0,
    Budget 350 Parts / 6 Lichter, keine AABB-Überschneidung (auch Hidden; Ausnahme Attribut Pierce), Z-Fighting,
    schwebende Teile, bekannte Anim-Arten ohne verschachtelte bewegte Animationen, und - am Anker von Slot_1 (Rot 0)
    und Slot_3 (Rot 180) eingesetzt - keine Überschneidung mit StartPad/CollectPad/Sign/Kanten/Hecke des Grundstücks,
    CollectPad genau unter der CashDisplay
  * Open World (PHASE4_CONTRACT §7, ow_buildings.py / plots.py / districts/kiesplatz.py): Plot-Vorlage mit
    OWAnchors.autohaus|produktion|schrottplatz (unsichtbar, auf plots.OW_ANCHORS); Vorlagen ServerStorage.OWBuildings
    (baustelle, <typ>_1..4): Root als PrimaryPart bei (0, 0.5, 0), Attribute OWType/OWStage, verankert, innerhalb der
    Grundfläche (Width x Depth) und Y 0..18, Budget 250 Parts / 4 Lichter, keine Überschneidungen / Z-Fighting /
    schwebenden Teile, bekannte Anim-Arten, Drehteile ohne Konflikt, Baustelle mit TextLabel "Countdown" - und an
    allen 8 Slots eingesetzt (jede Vorlage an ihrem Anker, die Baustelle an allen drei) innerhalb der Plot-Fläche
    ohne Überschneidung mit Stadt-Parts und der Vorlage mit Vollausbau; City.Missions.Delivery_1..3 (Start/Ziel
    unsichtbar, CanCollide false, CanTouch true, auf Asphalt -0.95, 300..600 Studs auseinander); Kiesplatz mit
    Spots.Spot_1..3 (+ Auto), Kunden (Anim npc_idle, Spot) unter City.Animated.Kiesplatz, Preistafel "PriceBoard"
    mit Line1..3, Station kiesplatz (MiniTab story) und Ankunft kiesplatz
  Ohne Workspace.City (Place lobby/tycoon) laufen nur die Zonen-Prüfungen (+ Vorlagen).
Exit-Code 1 bei Fehlern (Warnungen nicht).
"""
import math
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from worldgen import scan  # noqa: E402
from worldgen.lib import child, children, get_attrs, get_prop, name_of  # noqa: E402
from worldgen.plots import KEEP_TOP, RECT, SLOTS, loc2world  # noqa: E402
from worldgen.contract import STATIONS, ARRIVALS  # noqa: E402

# 3.0: Hügel des Naturrands (liegende Zylinder / Kugeln, Mitte unter dem Gras) reichen tief in den Boden
INTENDED_LOW = {"Grasplatte", "Teichbecken", "Teichboden", "Huegel", "Kuppe"}
# Budget je District-Model (Name unter City.Districts) - Parts ohne Autos, Lichter (CITY_SPEC §10, Stand des Baus)
DISTRICT_BUDGET = {
    "Stadtplatz": (700, 9),          # D1 + D2 (mit Ausbau der Ankunftshalle) + Wegeleitsystem
    "Platzgebaeude": (580, 11),      # D3-D6
    "Schrottplatz": (540, 5),        # D10
    "Tuning": (280, 7),              # D9 inkl. Vorplatz-Deko
    "Autohaus": (340, 7),            # D8 inkl. Hinterhof
    "Teststrecke": (560, 4),         # D13 (3.0: Grand-Prix-Kurs mit Bögen, Kerbs, Kiesbett, Reifenstapeln)
    "Parkplatz": (150, 4),           # D7 + Parkhaus
    "Tankstelle": (260, 3),          # D11 + Waschstraße + Kundenparkplatz + Baumreihe
    "Stadtpark": (410, 3),           # D12
    "Meile": (120, 0),               # Haltestellen, Gassen-Portale, Bänke, Eimer
    "Stadtrand": (640, 0),           # Wäldchen in den leeren Ecken
    "Kiesplatz": (900, 8),           # D14 Kiesplatz (Story Kapitel 1)
    "Grosswerkstatt": (900, 4),      # D15 Große Werkstatt (3.x: 4 Hallen, Teile-Ankauf, Vorplatz, Zufahrt)
}
# 3.0: Ground mit Naturrand (Hügel/Felsen/Bäume, horizon.build_edge) 800, Horizon (Fernboden + Skyline) 700,
# Track 13 Checkpoints + Ziel
FOLDER_BUDGET = {"Ground": (800, 0), "Roads": (610, 0), "Lights": (220, 52), "PlotSlots": (300, 0),
                 "Animated": (2300, 0), "CarSpawns": (12, 0), "Track": (16, 0), "Missions": (6, 0),
                 "Horizon": (700, 0)}
# Gesamtobergrenze aller Stadt-Parts inkl. Autos und Verkehr (Merge-Vorgabe 12000; 3.0: +1000 für Naturrand,
# Skyline und Grand-Prix-Kurs, gebaut ~12650 - Reserve für die übrigen 3.0-Teams), Lichter unverändert 120
TOTAL_BUDGET = 13000
LIGHT_BUDGET = 120


# ---------------------------------------------------------------- Flächen / Polygone
def _faces(p):
    """Liste (normal, offset, [Punkte]) der ebenen Außenflächen eines Parts."""
    out = []
    if p.cls == "Part" and p.shape == 0:
        return out
    corners = p.corners()
    if p.cls == "Part" and p.shape == 2:
        # Zylinder: nur die Kreisflächen (Achse = lokales X), als 16-Eck
        ax = p.cf.vector((1, 0, 0))
        r = p.size[1] / 2
        u = p.cf.vector((0, 1, 0))
        v = p.cf.vector((0, 0, 1))
        for s in (-1, 1):
            c = p.cf.point((s * p.size[0] / 2, 0, 0))
            pts = [tuple(c[i] + r * (math.cos(a) * u[i] + math.sin(a) * v[i]) for i in range(3))
                   for a in (k * math.pi / 8 for k in range(16))]
            n = tuple(s * x for x in ax)
            out.append((n, sum(n[i] * c[i] for i in range(3)), pts))
        return out
    hx, hy, hz = p.size[0] / 2, p.size[1] / 2, p.size[2] / 2
    if p.cls == "WedgePart":
        loc_faces = {
            (-1, 0, 0): [(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz)],
            (1, 0, 0): [(hx, -hy, -hz), (hx, -hy, hz), (hx, hy, hz)],
            (0, -1, 0): [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)],
            (0, 0, 1): [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)],
        }
    else:
        loc_faces = {}
        for ax in range(3):
            for s in (-1, 1):
                n = [0, 0, 0]
                n[ax] = s
                pts = []
                for a in (-1, 1):
                    for b in ((-1, 1) if a < 0 else (1, -1)):
                        v = [0.0, 0.0, 0.0]
                        v[ax] = s * (hx, hy, hz)[ax]
                        o = [i for i in range(3) if i != ax]
                        v[o[0]] = a * (hx, hy, hz)[o[0]]
                        v[o[1]] = b * (hx, hy, hz)[o[1]]
                        pts.append(tuple(v))
                loc_faces[tuple(n)] = pts
    for n, pts in loc_faces.items():
        wn = p.cf.vector(n)
        wp = [p.cf.point(q) for q in pts]
        out.append((wn, sum(wn[i] * wp[0][i] for i in range(3)), wp))
    return out


def _basis(n):
    a = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 0.0, 1.0)
    u = (n[1] * a[2] - n[2] * a[1], n[2] * a[0] - n[0] * a[2], n[0] * a[1] - n[1] * a[0])
    ln = math.sqrt(sum(x * x for x in u))
    u = tuple(x / ln for x in u)
    v = (n[1] * u[2] - n[2] * u[1], n[2] * u[0] - n[0] * u[2], n[0] * u[1] - n[1] * u[0])
    return u, v


def _hull(pts):
    pts = sorted(set((round(a, 5), round(b, 5)) for a, b in pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for q in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], q) <= 0:
            lo.pop()
        lo.append(q)
    for q in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], q) <= 0:
            hi.pop()
        hi.append(q)
    return lo[:-1] + hi[:-1]


def _clip(subject, clipper):
    """Sutherland-Hodgman (beide konvex, gegen den Uhrzeigersinn) -> Schnittpolygon"""
    def inside(p, a, b):
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= -1e-9

    def inter(p, q, a, b):
        x1, y1, x2, y2 = p[0], p[1], q[0], q[1]
        x3, y3, x4, y4 = a[0], a[1], b[0], b[1]
        d = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(d) < 1e-12:
            return q
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / d
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))
    out = subject
    for i in range(len(clipper)):
        a, b = clipper[i], clipper[(i + 1) % len(clipper)]
        inp, out = out, []
        if not inp:
            break
        for j in range(len(inp)):
            p, q = inp[j], inp[(j + 1) % len(inp)]
            if inside(q, a, b):
                if not inside(p, a, b):
                    out.append(inter(p, q, a, b))
                out.append(q)
            elif inside(p, a, b):
                out.append(inter(p, q, a, b))
    return out


def _area(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))) / 2 if len(poly) >= 3 else 0.0


def zfight(parts, min_area=0.02):
    groups = defaultdict(list)
    for p in parts:
        if p.car or p.transp >= 0.95:
            continue
        for n, off, pts in _faces(p):
            if n[1] < -0.5:
                continue   # Unterseiten sind nie sichtbar
            key = (round(n[0], 3) + 0.0, round(n[1], 3) + 0.0, round(n[2], 3) + 0.0, round(off, 3) + 0.0)
            groups[key].append((p, pts))
    hits = []
    for key, lst in groups.items():
        if len(lst) < 2:
            continue
        n = key[:3]
        u, v = _basis(n)
        polys = []
        for p, pts in lst:
            poly = _hull([(sum(q[i] * u[i] for i in range(3)), sum(q[i] * v[i] for i in range(3))) for q in pts])
            xs = [a for a, b in poly]
            ys = [b for a, b in poly]
            polys.append((p, poly, (min(xs), max(xs), min(ys), max(ys))))
        polys.sort(key=lambda t: t[2][0])
        for i in range(len(polys)):
            pi, qi, bi = polys[i]
            for j in range(i + 1, len(polys)):
                pj, qj, bj = polys[j]
                if bj[0] >= bi[1]:
                    break
                if bj[2] >= bi[3] or bi[2] >= bj[3]:
                    continue
                if pi.item is pj.item:
                    continue
                if abs(n[1]) < 0.5 and pi.top <= -0.9 and pj.top <= -0.9:
                    continue   # Seitenflächen zweier Bodenplatten liegen im Boden
                a = _area(_clip(qi, qj))
                if a > min_area:
                    hits.append((pi, pj, a, key))
    return hits


def near_coplanar(parts, max_d=0.049, min_area=0.5):
    """Parallele, gleich orientierte Flächen mit 0 < Abstand < max_d, die sich überlappen (Z-Fighting auf Distanz).
    Nur Oberseiten und Seiten; Vorlagen-Autos und (fast) unsichtbare Parts ausgenommen."""
    groups = defaultdict(list)
    for p in parts:
        if p.car or p.transp >= 0.95 or p.path.startswith("City.Animated.Verkehr"):
            continue
        for n, off, pts in _faces(p):
            if n[1] < -0.5:
                continue
            key = (round(n[0], 3) + 0.0, round(n[1], 3) + 0.0, round(n[2], 3) + 0.0)
            groups[key].append((off, p, pts))
    hits = []
    for n, lst in groups.items():
        if len(lst) < 2:
            continue
        u, v = _basis(n)
        lst.sort(key=lambda t: t[0])
        polys = []
        for off, p, pts in lst:
            poly = _hull([(sum(q[i] * u[i] for i in range(3)), sum(q[i] * v[i] for i in range(3))) for q in pts])
            xs = [a for a, b in poly]
            ys = [b for a, b in poly]
            polys.append((off, p, poly, (min(xs), max(xs), min(ys), max(ys))))
        for i in range(len(polys)):
            oi, pi, qi, bi = polys[i]
            for j in range(i + 1, len(polys)):
                oj, pj, qj, bj = polys[j]
                d = oj - oi
                if d >= max_d:
                    break
                if d < 0.0005 or pi.item is pj.item:
                    continue
                if _same_wreck(pi, pj):
                    continue       # Lite-Wracks übernehmen die Blechteile der Vorlagen (wie die Vorlagen-Autos)
                if bj[0] >= bi[1] or bi[0] >= bj[1] or bj[2] >= bi[3] or bi[2] >= bj[3]:
                    continue
                if abs(n[1]) < 0.5 and pi.top <= -0.9 and pj.top <= -0.9:
                    continue
                a = _area(_clip(qi, qj))
                if a > min_area:
                    hits.append((pi, pj, a, d, n))
    return hits


def _same_wreck(a, b):
    for p in (a, b):
        if ".Wrack." not in p.path and ".Wreck." not in p.path:
            return False
    return a.path.rsplit(".", 1)[0] == b.path.rsplit(".", 1)[0]


def _ov(a, b, e):
    return (a[0] - e <= b[1] and b[0] - e <= a[1] and a[2] - e <= b[3] and b[2] - e <= a[3] and
            a[4] - e <= b[5] and b[4] - e <= a[5])


def islands(parts, eps=0.06, cell=16):
    """Zusammenhang über sich berührende AABBs (Toleranz eps). Liefert die Komponenten (Listen von Parts), die
    nicht mit der Grasplatte (dem Boden der Stadt) verbunden sind - schwebende Geometrie."""
    # Vorlagen-Autos zählen als Verbindung (Schleifen, Dachlasten liegen auf ihnen), werden aber selbst nicht
    # gemeldet (Motorraum-Teile der Vorlagen hängen frei im Auto)
    sel = [p for p in parts if p.transp < 0.95 and not p.path.startswith("City.Animated.Verkehr")]
    bb = [p.aabb() for p in sel]
    grid = defaultdict(list)
    big = []
    for i, a in enumerate(bb):
        if (a[1] - a[0]) * (a[5] - a[4]) > 40000:
            big.append(i)          # Grasplatte o. Ä.: gegen alle prüfen statt in tausend Zellen
            continue
        for gx in range(int(a[0] // cell), int(a[1] // cell) + 1):
            for gz in range(int(a[4] // cell), int(a[5] // cell) + 1):
                grid[(gx, gz)].append(i)
    par = list(range(len(sel)))

    def find(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i

    def union(i, j):
        ri, rj = find(i), find(j)
        if ri != rj:
            par[ri] = rj
    for lst in grid.values():
        for ii in range(len(lst)):
            i = lst[ii]
            for jj in range(ii + 1, len(lst)):
                j = lst[jj]
                if _ov(bb[i], bb[j], eps):
                    union(i, j)
    for i in big:
        for j in range(len(sel)):
            if j != i and _ov(bb[i], bb[j], eps):
                union(i, j)
    # Autos und Wracks sind je ein starres Objekt (die Dellen der Wracks lassen Karosserieteile minimal abstehen)
    group = {}
    for i, p in enumerate(sel):
        segs = p.path.split(".")
        for k in range(len(segs) - 1, 0, -1):
            if segs[k] in ("Wreck", "Car", "Wrack") or segs[k].startswith(("Wrack_", "Wreck_")):
                key = ".".join(segs[:k + 1])
                if key in group:
                    union(i, group[key])
                else:
                    group[key] = i
                break
    roots = {find(i) for i, p in enumerate(sel) if p.name == "Grasplatte"}
    comps = defaultdict(list)
    for i in range(len(sel)):
        r = find(i)
        if r not in roots:
            comps[r].append(sel[i])
    return sorted((c for c in comps.values() if not all(p.car for p in c)), key=lambda c: c[0].path)


def curb_cut_blockers(parts):
    """Stehende Stadt-Parts (Laternen, Bäume, Pylonen, Baken ...) auf einer Bordsteinabsenkung (§9.1: 0 Laternen
    in Einfahrten). Erlaubt: Fahrbahn/Absenkung selbst und Markierungen (Unterseite <= -0.95)."""
    from worldgen.ground_roads import CURB_CUTS, plot_cuts
    rects = [(c[0], c[1], c[2], c[3], c[4]) for c in CURB_CUTS + plot_cuts()]
    out = []
    for p in parts:
        if p.car or p.transp >= 0.95 or p.path.startswith("City.Animated.Verkehr"):
            continue
        b = p.aabb()
        if b[2] <= -0.95 + 1e-3 or b[2] > 4:
            continue
        for nm, x0, x1, z0, z1 in rects:
            if b[1] > x0 + 0.01 and b[0] < x1 - 0.01 and b[5] > z0 + 0.01 and b[4] < z1 - 0.01:
                out.append((nm, p.path, [round(v, 2) for v in b]))
    return out


class _Occluders:
    """Kamera-Verdecker wie Poppercam: CanCollide und Transparency < 0.25"""

    def __init__(self, parts):
        self.data = []
        self.grid = defaultdict(list)
        for p in parts:
            if not p.collide or p.transp >= 0.25 or p.path.startswith(("City.Stations", "City.Arrivals")):
                continue
            if p.path.startswith("City.Animated.Verkehr"):
                continue
            k = len(self.data)
            self.data.append((p, p.cf.inverse(), p.aabb()))
            b = self.data[-1][2]
            if (b[1] - b[0]) * (b[5] - b[4]) > 40000:
                self.grid["big"].append(k)
                continue
            for gx in range(int(b[0] // 16), int(b[1] // 16) + 1):
                for gz in range(int(b[4] // 16), int(b[5] // 16) + 1):
                    self.grid[(gx, gz)].append(k)

    def hit(self, a, b, step=0.25):
        lo = [min(a[i], b[i]) for i in range(3)]
        hi = [max(a[i], b[i]) for i in range(3)]
        ks = set(self.grid["big"])
        for gx in range(int(lo[0] // 16), int(hi[0] // 16) + 1):
            for gz in range(int(lo[2] // 16), int(hi[2] // 16) + 1):
                ks.update(self.grid.get((gx, gz), ()))
        cands = []
        for k in ks:
            p, inv, bb = self.data[k]
            if bb[0] <= hi[0] and bb[1] >= lo[0] and bb[2] <= hi[1] and bb[3] >= lo[1] and bb[4] <= hi[2] and \
                    bb[5] >= lo[2]:
                cands.append((p, inv))
        dist = math.dist(a, b)
        n = int(dist / step) + 1
        for k in range(n + 1):
            t = k / n
            q = tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
            for p, inv in cands:
                l = inv.point(q)
                if p.cls == "Part" and p.shape == 0:
                    inside = l[0] * l[0] + l[1] * l[1] + l[2] * l[2] < (p.size[0] / 2) ** 2
                elif p.cls == "Part" and p.shape == 2:
                    inside = abs(l[0]) < p.size[0] / 2 and l[1] * l[1] + l[2] * l[2] < (p.size[1] / 2) ** 2
                else:
                    inside = abs(l[0]) < p.size[0] / 2 and abs(l[1]) < p.size[1] / 2 and abs(l[2]) < p.size[2] / 2
                if inside:
                    return p, t * dist
        return None


CAM_ZOOMS = ((10, 5), (16, 8), (24, 12))     # Abstand hinter dem Kopf, Höhe über dem Kopf (Neigung ~27°)
CAM_ANGLES = (0, 35, -35)


def camera_snags(occ, px, fy, pz, bx, bz):
    """Strahlen vom Kopf (Boden + 4.5) zur Kamera hinter dem Spieler (Richtung (bx,bz) = hinter dem Spieler).
    Liefert [(Zoom, Winkel, Part, Abstand)] für verdeckte Strahlen."""
    head = (px, fy + 4.5, pz)
    res = []
    for d, h in CAM_ZOOMS:
        for ang in CAM_ANGLES:
            r = math.radians(ang)
            dx = bx * math.cos(r) - bz * math.sin(r)
            dz = bx * math.sin(r) + bz * math.cos(r)
            hh = occ.hit(head, (px + dx * d, fy + 4.5 + h, pz + dz * d))
            if hh:
                res.append((d, ang, hh[0], hh[1]))
    return res


def player_side_blockers(parts, cx, fy, cz, half=5.0, y_lo=0.7, y_hi=6.0):
    """Kollidierende Parts in einem (2*half)² Quadrat um (cx,cz) zwischen Boden + y_lo und Boden + y_hi (§1.3)"""
    out = []
    for p in parts:
        if not p.collide or p.transp >= 1 or p.path.startswith(("City.Stations", "City.Arrivals",
                                                                "City.Animated.Verkehr")):
            continue
        a = p.aabb()
        if a[3] <= fy + y_lo or a[2] >= fy + y_hi:
            continue
        if a[1] <= cx - half or a[0] >= cx + half or a[5] <= cz - half or a[4] >= cz + half:
            continue
        out.append(p.path)
    return out


def _cam_report(errors, warns, who, snags):
    """Kamera klemmt: Treffer näher als 8 Studs am Kopf, oder der mittlere Strahl bei Zoom 10 ist verdeckt."""
    bad = [(d, a, p, dist) for d, a, p, dist in snags if dist < 8 or (d == 10 and a == 0)]
    soft = [s for s in snags if s not in bad]
    if bad:
        errors.append("%s: Kamera klemmt (%s)" % (who, ", ".join("Zoom %d/%+d° %s nach %.1f" % (d, a, p.path, dist)
                                                                 for d, a, p, dist in bad[:3])))
    if soft:
        warns.append("%s: Kamera rückt näher (%s)" % (who, ", ".join("Zoom %d/%+d° %s nach %.1f" % (d, a, p.name, dist)
                                                                     for d, a, p, dist in soft[:2])))


# ---------------------------------------------------------------- Prüfungen
def main(argv):
    place = next((a for a in argv if not a.startswith("--")), scan.DEFAULT_PLACE)
    verbose = "--verbose" in argv
    tree = scan.load(place)
    city, parts = scan.city_parts(tree)
    errors, warns, info = [], [], []
    if city is None:
        info.append("Workspace.City fehlt (Place lobby/tycoon?) - nur Zonen-Prüfungen")
        zone_checks(tree, [], errors, warns, info, verbose)
        template_checks(tree, errors, warns, info, verbose)
        ow_checks(tree, [], errors, warns, info, verbose)
        return _report(errors, warns, info)
    # 1) verankert / zu tief
    unanch = [p.path for p in parts if not p.anchored]
    if unanch:
        errors.append("%d Parts nicht verankert: %s" % (len(unanch), unanch[:5]))
    low = [(p.path, round(p.aabb()[2], 2)) for p in parts if p.aabb()[2] < -3 and p.name not in INTENDED_LOW]
    if low:
        errors.append("%d Parts unter Y -3: %s" % (len(low), low[:5]))
    # 2) Z-Fighting
    hits = zfight(parts)
    if hits:
        errors.append("%d Z-Fighting-Kandidaten (koplanar, überlappend)" % len(hits))
        for a, b, ar, key in hits[: (200 if verbose else 12)]:
            errors.append("   %s <-> %s  Fläche %.2f  Ebene n=(%g,%g,%g) d=%g" % (a.path, b.path, ar, *key))
    # 2b) fast koplanare Flächen (0 < Abstand < 0.05, Spec §1.2: Stufen >= 0.05)
    nc = near_coplanar(parts)
    if nc:
        errors.append("%d fast koplanare Flächenpaare (Abstand < 0.05, Z-Fighting auf Distanz)" % len(nc))
        for a, b, ar, d, n in sorted(nc, key=lambda h: -h[2])[: (200 if verbose else 12)]:
            errors.append("   %s <-> %s  Fläche %.1f  Abstand %.3f  n=(%g,%g,%g)" % (a.path, b.path, ar, d, *n))
    # 2c) schwebende Geometrie: Teile ohne Berührung (0.06) zur Grasplatte
    isl = islands(parts)
    if isl:
        errors.append("%d schwebende Gruppen (keine Verbindung zum Boden)" % len(isl))
        for comp in isl[: (200 if verbose else 12)]:
            y0 = min(p.aabb()[2] for p in comp)
            errors.append("   %s (+%d) Unterkante %.2f bei (%.1f, %.1f)" % (comp[0].path, len(comp) - 1, y0,
                                                                         comp[0].cf.p[0], comp[0].cf.p[2]))
    # 2d) nichts Stehendes auf Bordsteinabsenkungen (Laternen, Bäume, Baken, Pylonen)
    cc = curb_cut_blockers(parts)
    if cc:
        errors.append("%d Parts stehen auf Bordsteinabsenkungen: %s" % (len(cc), cc[:6]))
    # 3) Budget
    total = len(parts)
    cars_parts = sum(1 for p in parts if p.car)
    traffic = sum(1 for p in parts if p.path.startswith("City.Animated.Verkehr"))
    def count_lights(item):
        return sum(1 for x in item.iter("Item") if x.get("class") in ("PointLight", "SpotLight", "SurfaceLight"))
    lights_total = count_lights(city)
    info.append("Parts gesamt %d / Budget %d (davon Auto-Parts %d, darin Verkehr Lite-Autos + Bus %d)"
                % (total, TOTAL_BUDGET, cars_parts, traffic))
    if total > TOTAL_BUDGET:
        errors.append("Part-Budget überschritten: %d > %d" % (total, TOTAL_BUDGET))
    info.append("Lichter gesamt %d / Budget %d" % (lights_total, LIGHT_BUDGET))
    if lights_total > LIGHT_BUDGET:
        errors.append("Licht-Budget überschritten")
    for f in children(city):
        nm = name_of(f)
        n = sum(1 for p in parts if p.path.startswith("City." + nm + ".") or p.path == "City." + nm)
        nl = count_lights(f)
        b = FOLDER_BUDGET.get(nm)
        tag = ""
        if b:
            tag = "  (Budget %d / %d)" % b
            if n > b[0] * 1.15:
                warns.append("%s: %d Parts > Budget %d (+15%%)" % (nm, n, b[0]))
            if nl > b[1]:
                warns.append("%s: %d Lichter > Budget %d" % (nm, nl, b[1]))
        info.append("  %-10s %5d Parts %3d Lichter%s" % (nm, n, nl, tag))
    districts = child(city, "Districts")
    for d in children(districts) if districts is not None else []:
        nm = name_of(d)
        pre = "City.Districts." + nm
        n = sum(1 for p in parts if (p.path == pre or p.path.startswith(pre + ".")) and not p.car)
        ncars = sum(1 for x in d.iter("Item") if x.get("class") == "Model" and "Body" in get_attrs(x))
        nl = count_lights(d)
        b = DISTRICT_BUDGET.get(nm)
        info.append("  District %-14s %5d Parts + %d Autos, %d Lichter%s" %
                    (nm, n, ncars, nl, "  (Budget %d / %d)" % b if b else ""))
        if b and n > b[0] * 1.15:
            warns.append("District %s: %d Parts > Budget %d" % (nm, n, b[0]))
        if b and nl > b[1]:
            warns.append("District %s: %d Lichter > Budget %d" % (nm, nl, b[1]))
    # 4) Stationen / Ankunft / Spawn
    st = child(city, "Stations")
    ar = child(city, "Arrivals")
    solid = [p for p in parts if p.collide and p.transp < 1 and not p.path.startswith("City.Animated.Verkehr")]
    grid = defaultdict(list)
    for p in solid:
        b = p.aabb()
        for gx in range(int(b[0] // 20), int(b[1] // 20) + 1):
            for gz in range(int(b[4] // 20), int(b[5] // 20) + 1):
                grid[(gx, gz)].append((p, b))

    def near(x, z):
        return grid.get((int(x // 20), int(z // 20)), [])

    def free_floor(x, fy, z, r=3.0, h=6.0):
        """(Boden vorhanden, blockierende Parts)"""
        floor_ok = False
        block = []
        for p, b in near(x, z):
            if b[0] <= x <= b[1] and b[4] <= z <= b[5] and abs(b[3] - fy) <= 0.12:
                floor_ok = True
            if b[1] > x - r and b[0] < x + r and b[5] > z - r and b[4] < z + r and b[3] > fy + 0.6 and \
                    b[2] < fy + h:
                block.append(p.path)
        return floor_ok, block
    keys_st = {name_of(c) for c in children(st)} if st is not None else set()
    missing = sorted(set(STATIONS) - keys_st)
    if missing:
        errors.append("Stationen fehlen: %s" % missing)
    for s in children(st) if st is not None else []:
        k = name_of(s)
        a = get_attrs(s)
        if not isinstance(a.get("MiniTab"), str):
            errors.append("Station %s ohne MiniTab" % k)
        pr = [c for c in children(s) if c.get("class") == "ProximityPrompt"]
        if len(pr) != 1:
            errors.append("Station %s: %d ProximityPrompts" % (k, len(pr)))
        else:
            def v(n):
                e = get_prop(pr[0], n)
                return e.text if e is not None else None
            want = {"ActionText": "Öffnen", "KeyboardKeyCode": "101", "HoldDuration": "0.25",
                    "MaxActivationDistance": "10.0", "RequiresLineOfSight": "false"}
            for n, w in want.items():
                if v(n) != w:
                    errors.append("Station %s: Prompt %s=%s (soll %s)" % (k, n, v(n), w))
        att = [c for c in children(s) if c.get("class") == "Attachment" and name_of(c) == "Arrival"]
        if len(att) != 1:
            errors.append("Station %s ohne Attachment Arrival" % k)
        rec = scan.record(s, "City.Stations." + k)
        if rec.collide or rec.transp < 1 or not rec.anchored:
            errors.append("Station %s: muss unsichtbar, verankert, CanCollide false sein" % k)
        if att:
            from worldgen.lib import read_cf
            w = rec.cf * read_cf(att[0])
            fy = w.p[1] - 3.5
            ok, block = free_floor(w.p[0], fy, w.p[2], 2.0, 5.5)
            if not ok:
                warns.append("Station %s: kein Boden auf Höhe %.2f unter Arrival (%.1f,%.1f)" %
                             (k, fy, w.p[0], w.p[2]))
            if block:
                warns.append("Station %s: Arrival blockiert durch %s" % (k, block[:3]))
    # 4b) Spielerseite 10 x 10 frei (§1.3) und Kamera hinter dem Spieler (Poppercam: CanCollide, T < 0.25)
    occ = _Occluders(parts)
    from worldgen.contract import SIDE
    for key, (tab, title, (x, y, z), side, floor, extra) in STATIONS.items():
        sx, sz = SIDE[side]
        blk = player_side_blockers(parts, x + sx * 6.5, floor, z + sz * 6.5)
        if blk:
            errors.append("Station %s: 10x10 auf der Spielerseite %s blockiert durch %s" % (key, side,
                                                                                       sorted(set(blk))[:4]))
        _cam_report(errors, warns, "Station " + key, camera_snags(occ, x + sx * 6, floor, z + sz * 6, sx, sz))
    for key, (x, fy, z, look) in ARRIVALS.items():
        sx, sz = SIDE[look]
        _cam_report(errors, warns, "Arrival " + key, camera_snags(occ, x, fy, z, -sx, -sz))
    keys_ar = {name_of(c) for c in children(ar)} if ar is not None else set()
    if set(ARRIVALS) - keys_ar:
        errors.append("Arrivals fehlen: %s" % sorted(set(ARRIVALS) - keys_ar))
    for a in children(ar) if ar is not None else []:
        rec = scan.record(a, "City.Arrivals." + name_of(a))
        if rec.collide or rec.transp < 1:
            errors.append("Arrival %s sichtbar oder kollidierend" % rec.name)
        ok, block = free_floor(rec.cf.p[0], rec.cf.p[1], rec.cf.p[2], 3.0, 6.0)
        if not ok:
            warns.append("Arrival %s: kein Boden auf Höhe %.2f bei (%.1f,%.1f)" %
                         (rec.name, rec.cf.p[1], rec.cf.p[0], rec.cf.p[2]))
        if block:
            warns.append("Arrival %s: 6-Stud-Fläche blockiert durch %s" % (rec.name, block[:3]))
    sp = child(city, "CitySpawn")
    if sp is None or sp.get("class") != "SpawnLocation":
        errors.append("CitySpawn fehlt")
    else:
        e = get_prop(sp, "Enabled")
        if e is None or e.text != "true":
            errors.append("CitySpawn nicht aktiv")
        ok, block = free_floor(0, 0, -201, 4, 6)
        if not ok:
            warns.append("CitySpawn: noch kein Boden (Y 0) - Ankunftshalle fehlt")
    ws = scan.workspace(tree)
    spawns = [x for x in ws.iter("Item") if x.get("class") == "SpawnLocation"]
    enabled = [name_of(x) for x in spawns if (get_prop(x, "Enabled") is not None and get_prop(x, "Enabled").text == "true")]
    if enabled != ["CitySpawn"]:
        errors.append("Aktive SpawnLocations: %s (soll nur CitySpawn)" % enabled)
    # 5) Plot-Vorlage
    wk = child(ws, "Werkstatt")
    if wk is None:
        errors.append("Workspace.Werkstatt fehlt")
    else:
        miss = [k for k in KEEP_TOP if child(wk, k) is None]
        if miss:
            errors.append("Plot-Vorlage: Anker fehlen %s" % miss)
        arch = child(wk, "Architecture")
        if child(arch, "Boundary") is not None:
            errors.append("Plot-Vorlage: Boundary noch vorhanden")
    # 6) Stadt-Parts in Plot-Grundflächen
    fps = []
    for slot, house, px, pz, rot in SLOTS:
        a = loc2world(px, pz, rot, RECT[0], RECT[2])
        b = loc2world(px, pz, rot, RECT[1], RECT[3])
        fps.append((slot, min(a[0], b[0]), max(a[0], b[0]), min(a[1], b[1]), max(a[1], b[1])))
    intr = []
    for p in parts:
        if ".Vacant" in p.path or p.name in ("Grasplatte",) or p.transp >= 1:
            continue
        b = p.aabb()
        if b[3] <= -1.0 + 1e-6:
            continue
        for slot, x0, x1, z0, z1 in fps:
            if b[1] > x0 + 0.01 and b[0] < x1 - 0.01 and b[5] > z0 + 0.01 and b[4] < z1 - 0.01:
                intr.append((slot, p.path))
    if intr:
        errors.append("%d Stadt-Parts in Plot-Grundflächen: %s" % (len(intr), intr[:6]))
    # 7) Anim nur unter Animated
    anim_root = child(city, "Animated")
    inside = set(id(x) for x in anim_root.iter("Item")) if anim_root is not None else set()
    ps = child(city, "PlotSlots")
    ps_ids = set(id(x) for x in ps.iter("Item")) if ps is not None else set()
    bad_anim = [n for n, it in ((name_of(it), it) for it in city.iter("Item"))
                if "Anim" in get_attrs(it) and id(it) not in inside and id(it) not in ps_ids]
    if bad_anim:
        warns.append("Anim-Attribut außerhalb City.Animated: %s" % bad_anim[:8])
    # 8) Fahrzeuge, Strecke, Bildschirme
    vehicle_checks(tree, city, parts, errors, warns, info, verbose)
    # 9) Zonen der Ausbaustufe 4
    zone_checks(tree, parts, errors, warns, info, verbose)
    # 10) Stufen-Vorlagen des Tycoons (ServerStorage.TycoonTemplates)
    template_checks(tree, errors, warns, info, verbose)
    # 11) Open World: Plot-Anker, Gebäude-Vorlagen an allen Slots, Lieferrouten, Kiesplatz
    ow_checks(tree, parts, errors, warns, info, verbose)
    mission_checks(city, parts, errors, warns, info)
    kiesplatz_checks(city, errors, warns, info)
    # 12) 3.0: natürlicher Weltrand, Fernboden, Skyline (horizon.py)
    edge_checks(tree, city, parts, errors, warns, info)
    return _report(errors, warns, info)


def edge_checks(tree, city, parts, errors, warns, info, n_dir=32, step=2.0, r_max=2400.0):
    """Vom Stadtzentrum in n_dir Richtungen: Boden reicht bis hinter die äußerste unsichtbare Grenze (>= 50 Studs),
    die Grenze sperrt Y 0..100, und davor (<= 150 Studs) steht ein sichtbarer, kollidierender Teil des Naturrands
    (Hügel/Fels/Stamm). Skyline: nur Deko (CanCollide/CanTouch/CanQuery/CastShadow false), Budget."""
    from worldgen import drive, horizon
    hz = child(city, "Horizon")
    sky = child(hz, "Skyline") if hz is not None else None
    if sky is None:
        errors.append("City.Horizon.Skyline fehlt (horizon.build)")
    else:
        sp = [p for p in parts if p.path.startswith("City.Horizon.Skyline.")]
        bad = [p.path for p in sp if p.collide or _bool_prop(p.item, "CanTouch", True) or
               _bool_prop(p.item, "CanQuery", True) or _bool_prop(p.item, "CastShadow", True)]
        if bad:
            errors.append("Skyline: %d Parts nicht reine Deko (CanCollide/CanTouch/CanQuery/CastShadow): %s" %
                          (len(bad), bad[:4]))
        if len(sp) > horizon.SKY_BUDGET:
            errors.append("Skyline: %d Parts > Budget %d" % (len(sp), horizon.SKY_BUDGET))
        info.append("Skyline: %d Türme, %d Parts (Budget %d)" % (len(children(sky)), len(sp), horizon.SKY_BUDGET))
    floor = [p for p in parts if p.name in ("Grasplatte", "Fernboden")]
    for zn in ("Lobby", "Tycoon"):
        zm, zparts = scan.zone_parts(tree, zn)
        floor += [p for p in zparts if p.name == "Grasplatte"]
    walls = [p for p in parts if p.name == "Grenze" and p.collide]
    natural = [p for p in parts if ".Naturrand." in p.path and p.collide and p.transp < 0.95]

    def hit(lst, x, z, y0, y1):
        for p in lst:
            b = p.aabb()
            if not (b[0] - 1e-6 <= x <= b[1] + 1e-6 and b[4] - 1e-6 <= z <= b[5] + 1e-6):
                continue
            iv = drive.vertical_interval(p, x, z)
            if iv is not None and iv[0] <= y0 + 1e-6 and iv[1] >= y1 - 1e-6:
                return p
        return None

    def touch(lst, x, z, y0, y1):
        for p in lst:
            b = p.aabb()
            if not (b[0] <= x <= b[1] and b[4] <= z <= b[5]):
                continue
            iv = drive.vertical_interval(p, x, z)
            if iv is not None and iv[0] < y1 and iv[1] > y0:
                return p
        return None
    ok = 0
    for k in range(n_dir):
        a = 2 * math.pi * k / n_dir
        ux, uz = math.cos(a), math.sin(a)
        r = 0.0
        last_wall = None
        ground_end = None
        while r < r_max:
            x, z = ux * r, uz * r
            if hit(floor, x, z, -1.2, -1.2) is None:
                ground_end = r
                break
            if hit(walls, x, z, 0.0, 100.0) is not None:
                last_wall = r
            r += step
        who = "Rand Richtung %d° " % round(math.degrees(a))
        if last_wall is None:
            errors.append(who + "ohne Grenze bis zum Bodenende %s" % ground_end)
            continue
        if ground_end is not None and ground_end - last_wall < 50:
            errors.append(who + "Boden endet %.0f Studs hinter der Grenze (soll >= 50)" % (ground_end - last_wall))
            continue
        nat = None
        r = last_wall
        while r > last_wall - 150 and nat is None:
            nat = touch(natural, ux * r, uz * r, 0.5, 6.0)
            r -= step
        if nat is None:
            errors.append(who + "kein natürliches Hindernis vor der Grenze (r %.0f)" % last_wall)
            continue
        ok += 1
    info.append("Weltrand: %d / %d Richtungen mit Naturrand + Grenze, Boden bis dahinter" % (ok, n_dir))


def _report(errors, warns, info):
    for line in info:
        print(line)
    for w in warns:
        print("WARNUNG:", w)
    for e in errors:
        print("FEHLER:" if not e.startswith("   ") else "      ", e.strip() if e.startswith("   ") else e)
    print("OK" if not errors else "%d Fehler" % sum(1 for e in errors if not e.startswith("   ")))
    return 0 if not errors else 1


# ---------------------------------------------------------------- Zonen (PHASE4_CONTRACT §1, §5, §8)
CITY_BOUNDS = (-450, 450, -320, 320)     # X, Z: dort liegt die Stadt; Zonen müssen ganz außerhalb liegen
PROMPT_WANT = {"ActionText": "Öffnen", "KeyboardKeyCode": "101", "HoldDuration": "0.25",
               "MaxActivationDistance": "10.0", "RequiresLineOfSight": "false"}


def _prompt_props(item):
    pr = [c for c in children(item) if c.get("class") == "ProximityPrompt"]
    if len(pr) != 1:
        return None

    def v(n):
        e = get_prop(pr[0], n)
        return e.text if e is not None else None
    return {n: v(n) for n in ("ActionText", "ObjectText", "KeyboardKeyCode", "HoldDuration", "MaxActivationDistance",
                              "RequiresLineOfSight")}


def _station_checks(zone_name, root, parts, stations, tab, errors, warns, extra_attr=None):
    """Stationen einer Zone: Vertrag wie City.Stations (Prompt, Attachment Arrival, unsichtbar), Spielerseite frei,
    Kamera frei, MiniTab = tab (+ extra_attr gesetzt)."""
    from worldgen.contract import SIDE
    from worldgen.lib import read_cf
    st = child(root, "Stations")
    keys = {name_of(c) for c in children(st)} if st is not None else set()
    missing = sorted(set(stations) - keys)
    if missing:
        errors.append("%s: Stationen fehlen: %s" % (zone_name, missing))
    occ = _Occluders(parts)
    for s in children(st) if st is not None else []:
        k = name_of(s)
        a = get_attrs(s)
        if a.get("MiniTab") != tab:
            errors.append("%s.Stations.%s: MiniTab=%r (soll %r)" % (zone_name, k, a.get("MiniTab"), tab))
        if not isinstance(a.get("MiniTitle"), str):
            errors.append("%s.Stations.%s ohne MiniTitle" % (zone_name, k))
        if extra_attr and a.get(extra_attr) != k:
            errors.append("%s.Stations.%s: %s=%r (soll %r)" % (zone_name, k, extra_attr, a.get(extra_attr), k))
        pp = _prompt_props(s)
        if pp is None:
            errors.append("%s.Stations.%s: genau ein ProximityPrompt erwartet" % (zone_name, k))
        else:
            for n, w in PROMPT_WANT.items():
                if pp[n] != w:
                    errors.append("%s.Stations.%s: Prompt %s=%s (soll %s)" % (zone_name, k, n, pp[n], w))
        att = [c for c in children(s) if c.get("class") == "Attachment" and name_of(c) == "Arrival"]
        rec = scan.record(s, "%s.Stations.%s" % (zone_name, k))
        if rec.collide or rec.transp < 1 or not rec.anchored:
            errors.append("%s.Stations.%s: muss unsichtbar, verankert, CanCollide false sein" % (zone_name, k))
        if len(att) != 1:
            errors.append("%s.Stations.%s ohne Attachment Arrival" % (zone_name, k))
            continue
        w = rec.cf * read_cf(att[0])
        fy = w.p[1] - 3.5
        side = a.get("PlayerSide")
        if side not in SIDE:
            errors.append("%s.Stations.%s: PlayerSide fehlt" % (zone_name, k))
            continue
        sx, sz = SIDE[side]
        blk = player_side_blockers(parts, w.p[0] + sx * 0.5, fy, w.p[2] + sz * 0.5)
        if blk:
            errors.append("%s.Stations.%s: 10x10 auf der Spielerseite blockiert durch %s" %
                          (zone_name, k, sorted(set(blk))[:4]))
        floor = _floor_at(parts, w.p[0], w.p[2], fy)
        if floor is None:
            warns.append("%s.Stations.%s: kein Boden auf Höhe %.2f unter Arrival (%.1f,%.1f)" %
                         (zone_name, k, fy, w.p[0], w.p[2]))
        _cam_report(errors, warns, "%s.Stations.%s" % (zone_name, k), camera_snags(occ, w.p[0], fy, w.p[2], sx, sz))


def _floor_at(parts, x, z, fy, tol=0.12):
    for p in parts:
        if not p.collide or p.transp >= 1:
            continue
        b = p.aabb()
        if b[0] <= x <= b[1] and b[4] <= z <= b[5] and abs(b[3] - fy) <= tol:
            return p
    return None


def _arrival_checks(zone_name, root, parts, arrivals, errors, warns):
    from worldgen.contract import SIDE
    ar = child(root, "Arrivals")
    keys = {name_of(c) for c in children(ar)} if ar is not None else set()
    if set(arrivals) - keys:
        errors.append("%s: Arrivals fehlen: %s" % (zone_name, sorted(set(arrivals) - keys)))
    occ = _Occluders(parts)
    for a in children(ar) if ar is not None else []:
        rec = scan.record(a, "%s.Arrivals.%s" % (zone_name, name_of(a)))
        if rec.collide or rec.transp < 1 or not rec.anchored:
            errors.append("%s.Arrivals.%s sichtbar oder kollidierend" % (zone_name, rec.name))
        x, fy, z = rec.cf.p
        if _floor_at(parts, x, z, fy) is None:
            warns.append("%s.Arrivals.%s: kein Boden auf Höhe %.2f bei (%.1f,%.1f)" % (zone_name, rec.name, fy, x, z))
        blk = player_side_blockers(parts, x, fy, z, half=3.0)
        if blk:
            errors.append("%s.Arrivals.%s: 6-Stud-Fläche blockiert durch %s" % (zone_name, rec.name, blk[:3]))
        look = rec.attrs.get("Look")
        if look in SIDE:
            sx, sz = SIDE[look]
            _cam_report(errors, warns, "%s.Arrivals.%s" % (zone_name, rec.name), camera_snags(occ, x, fy, z, -sx, -sz))
        else:
            errors.append("%s.Arrivals.%s: Attribut Look fehlt" % (zone_name, rec.name))


def _spawn_checks(zone_name, root, parts, spawn, errors):
    sp = child(root, spawn)
    if sp is None or sp.get("class") != "SpawnLocation":
        errors.append("%s.%s fehlt (SpawnLocation)" % (zone_name, spawn))
        return
    if _bool_prop(sp, "Enabled", True):
        errors.append("%s.%s muss Enabled=false sein (der Server entscheidet)" % (zone_name, spawn))
    rec = scan.record(sp, "%s.%s" % (zone_name, spawn))
    if rec.collide or rec.transp < 1:
        errors.append("%s.%s sichtbar oder kollidierend" % (zone_name, spawn))
    x, y, z = rec.cf.p
    if _floor_at(parts, x, z, rec.aabb()[2], 0.15) is None:
        errors.append("%s.%s: kein Boden unter dem Spawn (%.1f, %.2f, %.1f)" % (zone_name, spawn, x, rec.aabb()[2], z))


def _geometry_checks(zone_name, parts, city_parts, budget, errors, warns, info, verbose):
    unanch = [p.path for p in parts if not p.anchored]
    if unanch:
        errors.append("%s: %d Parts nicht verankert: %s" % (zone_name, len(unanch), unanch[:5]))
    low = [(p.path, round(p.aabb()[2], 2)) for p in parts if p.aabb()[2] < -6]
    if low:
        errors.append("%s: %d Parts unter Y -6: %s" % (zone_name, len(low), low[:5]))
    hits = zfight(parts)
    if hits:
        errors.append("%s: %d Z-Fighting-Kandidaten (koplanar, überlappend)" % (zone_name, len(hits)))
        for a, b, ar, key in hits[: (200 if verbose else 12)]:
            errors.append("   %s <-> %s  Fläche %.2f  Ebene n=(%g,%g,%g) d=%g" % (a.path, b.path, ar, *key))
    nc = near_coplanar(parts)
    if nc:
        errors.append("%s: %d fast koplanare Flächenpaare (Abstand < 0.05)" % (zone_name, len(nc)))
        for a, b, ar, d, n in sorted(nc, key=lambda h: -h[2])[: (200 if verbose else 12)]:
            errors.append("   %s <-> %s  Fläche %.1f  Abstand %.3f  n=(%g,%g,%g)" % (a.path, b.path, ar, d, *n))
    isl = islands(parts)
    if isl:
        errors.append("%s: %d schwebende Gruppen (keine Verbindung zur Grasplatte der Zone)" % (zone_name, len(isl)))
        for comp in isl[: (200 if verbose else 12)]:
            y0 = min(p.aabb()[2] for p in comp)
            errors.append("   %s (+%d) Unterkante %.2f bei (%.1f, %.1f)" % (comp[0].path, len(comp) - 1, y0,
                                                                         comp[0].cf.p[0], comp[0].cf.p[2]))
    # ganz außerhalb der Stadtgrenzen und ohne Überschneidung mit Stadt-Parts
    x0, x1, z0, z1 = CITY_BOUNDS
    inside = [p.path for p in parts if not (p.aabb()[1] < x0 or p.aabb()[0] > x1 or p.aabb()[5] < z0 or
                                            p.aabb()[4] > z1)]
    if inside:
        errors.append("%s: %d Parts innerhalb der Stadtgrenzen X ±450 / Z ±320: %s" % (zone_name, len(inside),
                                                                                      inside[:5]))
    if city_parts:
        grid = defaultdict(list)
        for p in city_parts:
            b = p.aabb()
            for gx in range(int(b[0] // 32), int(b[1] // 32) + 1):
                for gz in range(int(b[4] // 32), int(b[5] // 32) + 1):
                    grid[(gx, gz)].append((p, b))
        ov = []
        for p in parts:
            a = p.aabb()
            seen = set()
            for gx in range(int(a[0] // 32), int(a[1] // 32) + 1):
                for gz in range(int(a[4] // 32), int(a[5] // 32) + 1):
                    for q, b in grid.get((gx, gz), ()):
                        if id(q) in seen:
                            continue
                        seen.add(id(q))
                        if _ov(a, b, -0.01):
                            ov.append((p.path, q.path))
        if ov:
            errors.append("%s: %d Überschneidungen mit Stadt-Parts: %s" % (zone_name, len(ov), ov[:4]))
    # Budget
    n = len(parts)
    nl = sum(1 for p in parts for x in p.item.iter("Item") if x.get("class") in ("PointLight", "SpotLight",
                                                                                "SurfaceLight"))
    info.append("%s: %d Parts / Budget %d, %d Lichter / Budget %d" % (zone_name, n, budget[0], nl, budget[1]))
    if n > budget[0]:
        errors.append("%s: Part-Budget überschritten: %d > %d" % (zone_name, n, budget[0]))
    if nl > budget[1]:
        errors.append("%s: Licht-Budget überschritten: %d > %d" % (zone_name, nl, budget[1]))
    # Stufen-Regel: keine begehbaren Oberseiten (kollidierend, Höhe < 4 über der nächsten) mit Stufe 0 < d < 0.05
    # deckt near_coplanar ab; hier zusätzlich: Oberseiten aller kollidierenden Bodenplatten paarweise verschieden
    tops = defaultdict(list)
    for p in parts:
        if p.collide and p.transp < 1 and p.size[0] * p.size[2] > 400 and p.top <= 1:
            tops[round(p.top, 3)].append(p)
    for top, lst in tops.items():
        for i in range(len(lst)):
            for j in range(i + 1, len(lst)):
                a, b = lst[i].aabb(), lst[j].aabb()
                if a[0] < b[1] - 0.05 and b[0] < a[1] - 0.05 and a[4] < b[5] - 0.05 and b[4] < a[5] - 0.05:
                    errors.append("%s: zwei Bodenplatten mit derselben Oberseite %.2f überlappen: %s / %s" %
                                  (zone_name, top, lst[i].path, lst[j].path))


def _anim_checks(zone_name, root, warns, extra_roots=()):
    anim_root = child(root, "Animated")
    inside = set(id(x) for x in anim_root.iter("Item")) if anim_root is not None else set()
    for nm in extra_roots:
        f = child(root, nm)
        if f is not None:
            inside |= set(id(x) for x in f.iter("Item"))
    bad = [name_of(it) for it in root.iter("Item") if "Anim" in get_attrs(it) and id(it) not in inside]
    if bad:
        warns.append("%s: Anim-Attribut außerhalb %s.Animated: %s" % (zone_name, zone_name, bad[:8]))


def _tycoon_plot_checks(root, parts, errors):
    from worldgen.tycoon import SLOTS as TSLOTS
    plots = child(root, "Plots")
    if plots is None:
        errors.append("Tycoon.Plots fehlt")
        return
    for slot, px, pz, rot in TSLOTS:
        m = child(plots, "Slot_%d" % slot)
        if m is None or m.get("class") != "Model":
            errors.append("Tycoon.Plots.Slot_%d fehlt" % slot)
            continue
        a = get_attrs(m)
        for key, want in (("Slot", slot), ("X", px), ("Z", pz), ("Rot", rot)):
            if a.get(key) != want:
                errors.append("Tycoon.Plots.Slot_%d: Attribut %s=%r (soll %r)" % (slot, key, a.get(key), want))
        for nm, cls in (("Base", "Part"), ("Sign", "Model"), ("StartPad", "Part"), ("Anchor", "Part"),
                        ("CollectPad", "Part"), ("ButtonsRoot", "Folder")):
            c = child(m, nm)
            if c is None or c.get("class") != cls:
                errors.append("Tycoon.Plots.Slot_%d.%s fehlt oder ist kein %s" % (slot, nm, cls))
        base = child(m, "Base")
        if base is not None:
            rec = scan.record(base, "Tycoon.Plots.Slot_%d.Base" % slot)
            if abs(rec.top) > 1e-6 or tuple(round(v, 3) for v in rec.size) != (70.0, 1.0, 70.0):
                errors.append("Tycoon.Plots.Slot_%d.Base: 70 x 1 x 70 mit Oberseite Y 0 erwartet" % slot)
            if abs(rec.cf.p[0] - px) > 1e-6 or abs(rec.cf.p[2] - pz) > 1e-6:
                errors.append("Tycoon.Plots.Slot_%d.Base liegt nicht auf dem Pivot" % slot)
        sp = child(m, "StartPad")
        if sp is not None:
            if get_attrs(sp).get("TycoonSlot") != slot:
                errors.append("Tycoon.Plots.Slot_%d.StartPad: TycoonSlot=%r" % (slot, get_attrs(sp).get("TycoonSlot")))
            pp = _prompt_props(sp)
            if pp is None or pp["ActionText"] != "Durchlauf starten":
                errors.append("Tycoon.Plots.Slot_%d.StartPad: ProximityPrompt 'Durchlauf starten' fehlt" % slot)
        cp = child(m, "CollectPad")
        if cp is not None and get_attrs(cp).get("TycoonPad") != "collect":
            errors.append("Tycoon.Plots.Slot_%d.CollectPad: TycoonPad='collect' fehlt" % slot)
        an = child(m, "Anchor")
        if an is not None:
            rec = scan.record(an, "Tycoon.Plots.Slot_%d.Anchor" % slot)
            if rec.collide or rec.transp < 1 or abs(rec.cf.p[0] - px) > 1e-6 or abs(rec.cf.p[2] - pz) > 1e-6:
                errors.append("Tycoon.Plots.Slot_%d.Anchor: unsichtbar, CanCollide false, auf dem Pivot erwartet" % slot)
            want = -math.sin(math.radians(rot)), -math.cos(math.radians(rot))
            look = rec.cf.look
            if abs(look[0] - want[0]) > 1e-6 or abs(look[2] - want[1]) > 1e-6:
                errors.append("Tycoon.Plots.Slot_%d.Anchor: LookVector passt nicht zu Rot %d" % (slot, rot))
        sign = child(m, "Sign")
        if sign is not None:
            labels = {name_of(x) for x in sign.iter("Item") if x.get("class") == "TextLabel"}
            if {"Number", "Owner", "Street", "Welcome"} - labels:
                errors.append("Tycoon.Plots.Slot_%d.Sign: Labels fehlen %s" %
                              (slot, sorted({"Number", "Owner", "Street", "Welcome"} - labels)))


def zone_checks(tree, city_parts, errors, warns, info, verbose=False):
    from worldgen import lobby as lobby_mod, tycoon as tycoon_mod
    for nm in scan.ZONES:
        root, parts = scan.zone_parts(tree, nm)
        if root is None:
            info.append("Zone %s nicht im Place" % nm)
            continue
        if root.get("class") != "Model":
            errors.append("Workspace.%s muss ein Model sein" % nm)
        if nm == "Lobby":
            _geometry_checks(nm, parts, city_parts, lobby_mod.LOBBY_BUDGET, errors, warns, info, verbose)
            _station_checks(nm, root, parts, lobby_mod.STATIONS, "lobby", errors, warns, extra_attr="LobbyAction")
            _arrival_checks(nm, root, parts, lobby_mod.ARRIVALS, errors, warns)
            _spawn_checks(nm, root, parts, "LobbySpawn", errors)
            _anim_checks(nm, root, warns)
            kinds = {get_attrs(it).get("Anim") for it in child(root, "Animated").iter("Item")} - {None}
            if {"neon", "door", "turntable"} - kinds:
                errors.append("Lobby.Animated: Anim-Arten fehlen %s" % sorted({"neon", "door", "turntable"} - kinds))
        else:
            _geometry_checks(nm, parts, city_parts, tycoon_mod.TYCOON_BUDGET, errors, warns, info, verbose)
            _station_checks(nm, root, parts, tycoon_mod.STATIONS, "tycoon", errors, warns)
            _arrival_checks(nm, root, parts, tycoon_mod.ARRIVALS, errors, warns)
            _spawn_checks(nm, root, parts, "TycoonSpawn", errors)
            _anim_checks(nm, root, warns, extra_roots=("Plots",))
            _tycoon_plot_checks(root, parts, errors)
        walls = [p.path for p in parts if p.collide and p.transp >= 0.95]
        if walls:
            errors.append("%s: unsichtbare kollidierende Parts: %s" % (nm, walls[:5]))


# ---------------------------------------------------------------- Stufen-Vorlagen (PHASE4_CONTRACT §8)
def _pen(a, b, eps):
    """AABBs durchdringen sich auf allen drei Achsen um mehr als eps"""
    return (min(a[1], b[1]) - max(a[0], b[0]) > eps and min(a[3], b[3]) - max(a[2], b[2]) > eps and
            min(a[5], b[5]) - max(a[4], b[4]) > eps)


def _pair_overlaps(parts, eps=0.02, cell=8):
    """Paare sich durchdringender Parts (AABB) - Vorlagen-Autos und Pierce-Teile ausgenommen"""
    sel = [p for p in parts if p.transp < 0.95 and not p.car and not p.attrs.get("Pierce")]
    bb = [p.aabb() for p in sel]
    grid = defaultdict(list)
    for i, a in enumerate(bb):
        for gx in range(int(math.floor(a[0] / cell)), int(math.floor(a[1] / cell)) + 1):
            for gz in range(int(math.floor(a[4] / cell)), int(math.floor(a[5] / cell)) + 1):
                grid[(gx, gz)].append(i)
    seen = set()
    hits = []
    for lst in grid.values():
        for ii in range(len(lst)):
            for jj in range(ii + 1, len(lst)):
                i, j = lst[ii], lst[jj]
                key = (min(i, j), max(i, j))
                if key in seen:
                    continue
                seen.add(key)
                if _pen(bb[i], bb[j], eps):
                    hits.append((sel[i], sel[j]))
    return sorted(hits, key=lambda h: (h[0].path, h[1].path))


def _car_overlaps(parts, eps=0.05):
    """Teile der Vorlagen-Autos gegen alle anderen Parts (AABB)"""
    cars = [p for p in parts if p.car and p.transp < 0.95]
    others = [(p, p.aabb()) for p in parts if not p.car and p.transp < 0.95 and not p.attrs.get("Pierce")]
    hits = []
    for c in cars:
        a = c.aabb()
        for p, b in others:
            if _pen(a, b, eps):
                hits.append((c, p))
    return hits


def _floating(parts, grounded, eps=0.06):
    """Zusammenhang über sich berührende AABBs; Komponenten ohne "grounded"-Teil (schwebend)"""
    sel = [p for p in parts if p.transp < 0.95]
    bb = [p.aabb() for p in sel]
    par = list(range(len(sel)))

    def find(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i

    for i in range(len(sel)):
        for j in range(i + 1, len(sel)):
            if _ov(bb[i], bb[j], eps):
                ri, rj = find(i), find(j)
                if ri != rj:
                    par[ri] = rj
    # Autos sind je ein starres Objekt
    group = {}
    for i, p in enumerate(sel):
        if p.car:
            key = p.path.rsplit(".", 1)[0]
            if key in group:
                ri, rj = find(i), find(group[key])
                if ri != rj:
                    par[ri] = rj
            else:
                group[key] = i
    roots = {find(i) for i, p in enumerate(sel) if grounded(p, bb[i])}
    comps = defaultdict(list)
    for i in range(len(sel)):
        r = find(i)
        if r not in roots:
            comps[r].append(sel[i])
    return sorted(comps.values(), key=lambda c: c[0].path)


def _sweep_conflicts(model, parts, who):
    """Drehende Modelle (Anim=turntable): jedes Teil überstreicht einen Kreisring um den Pivot (PrimaryPart) in seiner
    Höhe; andere Teile in diesem Ring würden beim Drehen durchdrungen. Liefert (Teil, anderes Teil)."""
    by_ref = {p.item.get("referent"): p for p in parts if p.item is not None}
    hits = []
    for it in model.iter("Item"):
        if it.get("class") != "Model" or get_attrs(it).get("Anim") != "turntable":
            continue
        pp = get_prop(it, "PrimaryPart")
        piv = by_ref.get(pp.text) if pp is not None else None
        if piv is None:
            continue
        cx, cz = piv.cf.p[0], piv.cf.p[2]
        inside = {id(x) for x in it.iter("Item")}
        mine = [p for p in parts if id(p.item) in inside and p.transp < 0.95]
        others = [p for p in parts if id(p.item) not in inside and p.transp < 0.95 and p.name != "Root"]
        for p in mine:
            b = p.aabb()
            round_ = p.cls == "Part" and (p.shape == 0 or (p.shape == 2 and abs(p.cf.vector((1, 0, 0))[1]) > 0.95))
            if round_:
                # stehender Zylinder / Kugel: echter Radius statt AABB-Ecken
                rad = p.size[1] / 2 if p.shape == 2 else p.size[0] / 2
                dc = math.hypot(p.cf.p[0] - cx, p.cf.p[2] - cz)
                rmax, rmin = dc + rad, max(0.0, dc - rad)
            else:
                cs = [(b[0], b[4]), (b[1], b[4]), (b[0], b[5]), (b[1], b[5])]
                rmax = max(math.hypot(x - cx, z - cz) for x, z in cs)
                dx = max(b[0] - cx, 0.0, cx - b[1])
                dz = max(b[4] - cz, 0.0, cz - b[5])
                rmin = math.hypot(dx, dz)
            for q in others:
                a = q.aabb()
                if min(a[3], b[3]) - max(a[2], b[2]) <= 0.02:
                    continue
                qdx = max(a[0] - cx, 0.0, cx - a[1])
                qdz = max(a[4] - cz, 0.0, cz - a[5])
                qmin = math.hypot(qdx, qdz)
                qcs = [(a[0], a[4]), (a[1], a[4]), (a[0], a[5]), (a[1], a[5])]
                qmax = max(math.hypot(x - cx, z - cz) for x, z in qcs)
                if qmin < rmax - 0.05 and qmax > rmin + 0.05:
                    hits.append((p, q))
    return hits


def _template_structure(model, typ, s, who, errors):
    from worldgen import tycoon_templates as TT
    root = child(model, "Root")
    pp = get_prop(model, "PrimaryPart")
    if root is None or root.get("class") != "Part":
        errors.append("%s: Part Root fehlt" % who)
    else:
        if pp is None or pp.text != root.get("referent"):
            errors.append("%s: PrimaryPart ist nicht Root" % who)
        rec = scan.record(root, who + ".Root")
        if any(abs(a - b) > 1e-6 for a, b in zip(rec.cf.p, (0.0, TT.ROOT_Y, 0.0))) or \
                any(abs(v) > 1e-6 for v in (rec.cf.look[0], rec.cf.look[1], rec.cf.look[2] + 1)):
            errors.append("%s: Root muss unverdreht bei (0, %g, 0) liegen" % (who, TT.ROOT_Y))
        if rec.collide or rec.transp < 1:
            errors.append("%s: Root muss unsichtbar und CanCollide=false sein" % who)
    buttons = child(model, "Buttons")
    if buttons is None or buttons.get("class") != "Folder":
        errors.append("%s: Ordner Buttons fehlt" % who)
    pads = {}
    for it in model.iter("Item"):
        bid = get_attrs(it).get("TycoonButton")
        if bid is not None:
            if it.get("class") != "Part":
                errors.append("%s: TycoonButton=%r an %s (kein Part)" % (who, bid, name_of(it)))
                continue
            pads[bid] = it
    want = {TT.upgrade_id(typ, s, k) for k in range(1, TT.UPGRADES_PER_STAGE + 1)}
    if s < TT.MAX_STAGE:
        want.add(TT.stage_id(typ, s + 1))
    if set(pads) != want:
        errors.append("%s: TycoonButton-Ids %s erwartet, gefunden %s" % (who, sorted(want), sorted(pads)))
    for bid, it in pads.items():
        if bid.startswith(typ + "_stage"):
            if name_of(it) != "StagePad":
                errors.append("%s: Stufen-Pad %s muss 'StagePad' heißen" % (who, bid))
        elif buttons is None or it not in list(buttons):
            errors.append("%s: Kaufpad %s liegt nicht in Buttons" % (who, bid))
        label = next((g for g in it.findall("Item") if g.get("class") == "SurfaceGui" and name_of(g) == "Label"), None)
        names = {name_of(x) for x in label.iter("Item") if x.get("class") == "TextLabel"} if label is not None else set()
        if {"Name", "Price"} - names:
            errors.append("%s: Pad %s ohne SurfaceGui Label mit TextLabels Name/Price" % (who, bid))
        rec = scan.record(it, who + "." + name_of(it))
        if not rec.collide or get_prop(it, "CanTouch") is not None and get_prop(it, "CanTouch").text != "true":
            errors.append("%s: Pad %s muss CanCollide/CanTouch true haben" % (who, bid))
    if s == TT.MAX_STAGE and child(model, "StagePad") is not None:
        errors.append("%s: Stufe 5 darf kein StagePad haben" % who)
    hidden = child(model, "Hidden")
    if hidden is None or hidden.get("class") != "Folder":
        errors.append("%s: Ordner Hidden fehlt" % who)
    else:
        prods = {name_of(x) for x in children(hidden) if x.get("class") == "Model"}
        missing = {"Producer_%d" % k for k in range(1, TT.UPGRADES_PER_STAGE + 1)} - prods
        if missing:
            errors.append("%s: Hidden ohne %s" % (who, sorted(missing)))
        for x in children(hidden):
            if not any(scan.walk(x)):
                errors.append("%s: Hidden.%s ist leer" % (who, name_of(x)))
    cash = child(model, "CashDisplay")
    if cash is None or cash.get("class") != "Part":
        errors.append("%s: Part CashDisplay fehlt" % who)
    else:
        rec = scan.record(cash, who + ".CashDisplay")
        if any(abs(a - b) > 1e-6 for a, b in zip(rec.cf.p, TT.CASH_DISPLAY)):
            errors.append("%s: CashDisplay bei %s erwartet (ist %s)" % (who, TT.CASH_DISPLAY, tuple(rec.cf.p)))
        gui = next((g for g in cash.findall("Item") if g.get("class") == "SurfaceGui"), None)
        labels = {name_of(x) for x in gui.iter("Item") if x.get("class") == "TextLabel"} if gui is not None else set()
        if "Bargeld" not in labels:
            errors.append("%s: CashDisplay ohne SurfaceGui mit TextLabel 'Bargeld'" % who)


def _template_anims(model, who, errors):
    from worldgen import tycoon_templates as TT
    anim_items = []
    for it in model.iter("Item"):
        a = get_attrs(it)
        if "Anim" in a:
            if a["Anim"] not in TT.ANIM_KINDS:
                errors.append("%s: unbekannte Anim=%r an %s" % (who, a["Anim"], name_of(it)))
            anim_items.append((it, a["Anim"]))
        if "TycoonAnim" in a:
            if a["TycoonAnim"] not in TT.TYCOON_ANIM_KINDS:
                errors.append("%s: unbekannte TycoonAnim=%r an %s" % (who, a["TycoonAnim"], name_of(it)))
            anim_items.append((it, a["TycoonAnim"]))
    moving = {id(it) for it, kind in anim_items if kind in TT.MOVING}
    parent_of = {id(c): p for p in model.iter("Item") for c in p.findall("Item")}
    for it, kind in anim_items:
        if kind not in TT.MOVING:
            continue
        p = parent_of.get(id(it))
        while p is not None and p is not model:
            if id(p) in moving:
                errors.append("%s: bewegte Animation %s (%s) innerhalb von %s" % (who, name_of(it), kind, name_of(p)))
                break
            p = parent_of.get(id(p))


def template_checks(tree, errors, warns, info, verbose=False):
    from worldgen import tycoon_templates as TT
    from worldgen.tycoon import SLOTS as TSLOTS, COLLECT_PAD, HALF
    from worldgen.plots import loc2world
    from worldgen.lib import CF
    tpls = TT.templates_of(tree)
    if not tpls:
        info.append("ServerStorage.TycoonTemplates nicht im Place")
        return
    for typ in TT.TYPES:
        for s in range(1, TT.MAX_STAGE + 1):
            if (typ, s) not in tpls:
                errors.append("TycoonTemplates.%s.Stage_%d fehlt" % (typ, s))
    zone, zparts = scan.zone_parts(tree, "Tycoon")
    slot_parts = {}
    for slot, px, pz, rot in TSLOTS:
        if slot in (1, 3):
            pre = "Tycoon.Plots.Slot_%d." % slot
            slot_parts[slot] = ([p for p in zparts if p.path.startswith(pre) and p.name != "Base" and p.transp < 0.95],
                                px, pz, rot)
    total_p = total_l = 0
    rows = []
    for (typ, s), model in sorted(tpls.items()):
        who = "TycoonTemplates.%s.Stage_%d" % (typ, s)
        if model.get("class") != "Model":
            errors.append("%s muss ein Model sein" % who)
            continue
        _template_structure(model, typ, s, who, errors)
        _template_anims(model, who, errors)
        parts = scan.walk(model, who)
        n = len(parts)
        nl = sum(1 for x in model.iter("Item") if x.get("class") in ("PointLight", "SpotLight", "SurfaceLight"))
        total_p += n
        total_l += nl
        rows.append("%s.%d %d/%d" % (typ, s, n, nl))
        if n > TT.TEMPLATE_BUDGET[0]:
            errors.append("%s: Part-Budget überschritten: %d > %d" % (who, n, TT.TEMPLATE_BUDGET[0]))
        if nl > TT.TEMPLATE_BUDGET[1]:
            errors.append("%s: Licht-Budget überschritten: %d > %d" % (who, nl, TT.TEMPLATE_BUDGET[1]))
        unanch = [p.path for p in parts if not p.anchored]
        if unanch:
            errors.append("%s: %d Parts nicht verankert: %s" % (who, len(unanch), unanch[:5]))
        out = []
        for p in parts:
            if p.name == "Root":
                continue
            b = p.aabb()
            if b[0] < -TT.INNER - 0.01 or b[1] > TT.INNER + 0.01 or b[4] < -TT.INNER - 0.01 or b[5] > TT.INNER + 0.01 \
                    or b[2] < -0.001 or b[3] > 60:
                out.append((p.path, tuple(round(v, 2) for v in b)))
        if out:
            errors.append("%s: %d Parts außerhalb X/Z ±%g bzw. Y 0..60: %s" % (who, len(out), TT.INNER, out[:4]))
        walls = [p.path for p in parts if p.collide and p.transp >= 0.95 and p.name != "Root"]
        if walls:
            errors.append("%s: unsichtbare kollidierende Parts: %s" % (who, walls[:5]))
        ov = _pair_overlaps(parts)
        if ov:
            errors.append("%s: %d Überschneidungen (AABB): " % (who, len(ov)))
            for a, b in ov[: (200 if verbose else 10)]:
                errors.append("   %s <-> %s" % (a.path[len(who) + 1:], b.path[len(who) + 1:]))
        cv = _car_overlaps(parts)
        if cv:
            errors.append("%s: %d Auto-Überschneidungen: %s" % (who, len(cv),
                                                               [(a.path[len(who) + 1:], b.path[len(who) + 1:])
                                                                for a, b in cv[:4]]))
        sw = _sweep_conflicts(model, parts, who)
        if sw:
            errors.append("%s: %d Teile im Schwenkbereich drehender Modelle: %s" %
                          (who, len(sw), [(a.path[len(who) + 1:], b.path[len(who) + 1:]) for a, b in sw[:6]]))
        hits = zfight(parts)
        if hits:
            errors.append("%s: %d Z-Fighting-Kandidaten" % (who, len(hits)))
            for a, b, ar, key in hits[: (200 if verbose else 8)]:
                errors.append("   %s <-> %s  Fläche %.2f" % (a.path[len(who) + 1:], b.path[len(who) + 1:], ar))
        nc = near_coplanar(parts)
        if nc:
            errors.append("%s: %d fast koplanare Flächenpaare" % (who, len(nc)))
            for a, b, ar, d, nrm in sorted(nc, key=lambda h: -h[2])[: (200 if verbose else 8)]:
                errors.append("   %s <-> %s  Fläche %.1f  Abstand %.3f" % (a.path[len(who) + 1:],
                                                                          b.path[len(who) + 1:], ar, d))
        cx, cz = COLLECT_PAD
        fl = _floating(parts, lambda p, b: b[2] <= 0.02 or (b[2] <= 0.52 and cx - 4 <= p.cf.p[0] <= cx + 4 and
                                                             cz - 4 <= p.cf.p[2] <= cz + 4))
        if fl:
            errors.append("%s: %d schwebende Gruppen" % (who, len(fl)))
            for comp in fl[: (200 if verbose else 8)]:
                y0 = min(p.aabb()[2] for p in comp)
                errors.append("   %s (+%d) Unterkante %.2f bei (%.1f, %.1f)" % (comp[0].path[len(who) + 1:],
                                                                             len(comp) - 1, y0, comp[0].cf.p[0],
                                                                             comp[0].cf.p[2]))
        # am Anker eingesetzt (Slot_1 Rot 0, Slot_3 Rot 180): Grundstücks-Teile frei, CollectPad unter der Tafel
        for slot, (sparts, px, pz, rot) in slot_parts.items():
            xf = CF.at(px, 0.5, pz, rot) * CF(0, TT.ROOT_Y, 0).inverse()
            tparts = [p for p in scan.walk(model, who, False, xf) if p.transp < 0.95 and not p.attrs.get("Pierce")]
            bad = []
            for p in tparts:
                a = p.aabb()
                if a[0] < px - HALF - 0.01 or a[1] > px + HALF + 0.01 or a[4] < pz - HALF - 0.01 or a[5] > pz + HALF + 0.01:
                    bad.append(p.path)
                for q in sparts:
                    if _pen(a, q.aabb(), 0.02):
                        bad.append("%s <-> %s" % (p.path[len(who) + 1:], q.path))
            if bad:
                errors.append("%s an Slot_%d: %d Konflikte mit dem Grundstück: %s" % (who, slot, len(bad), bad[:4]))
            cash = next((p for p in tparts if p.name == "CashDisplay"), None)
            pad = next((p for p in sparts if p.name == "CollectPad"), None)
            if cash is not None and pad is not None:
                if abs(cash.cf.p[0] - pad.cf.p[0]) > 1e-6 or abs(cash.cf.p[2] - pad.cf.p[2]) > 1e-6:
                    errors.append("%s an Slot_%d: CollectPad (%.1f, %.1f) liegt nicht unter der CashDisplay (%.1f, %.1f)"
                                  % (who, slot, pad.cf.p[0], pad.cf.p[2], cash.cf.p[0], cash.cf.p[2]))
    info.append("TycoonTemplates: %d Vorlagen, %d Parts, %d Lichter (Budget je Vorlage %d / %d)"
                % (len(tpls), total_p, total_l, *TT.TEMPLATE_BUDGET))
    if verbose:
        info.append("  Vorlagen Parts/Lichter: " + ", ".join(rows))
    else:
        info.append("  größte: " + ", ".join(sorted(rows, key=lambda r: -int(r.split()[1].split("/")[0]))[:4]))


# ---------------------------------------------------------------- Open World (PHASE4_CONTRACT §7)
def _ow_anchor_checks(tree, errors):
    """Plot.OWAnchors.<typ> in der Vorlage: unsichtbar, verankert, CanCollide false, auf plots.OW_ANCHORS."""
    from worldgen.plots import OW_TYPES, ow_anchor_cf
    ws = scan.workspace(tree)
    wk = child(ws, "Werkstatt")
    anchors = child(wk, "OWAnchors") if wk is not None else None
    if anchors is None:
        errors.append("Plot-Vorlage: Ordner OWAnchors fehlt")
        return
    for typ in OW_TYPES:
        a = child(anchors, typ)
        if a is None or a.get("class") != "Part":
            errors.append("Plot-Vorlage: OWAnchors.%s fehlt (Part)" % typ)
            continue
        rec = scan.record(a, "Werkstatt.OWAnchors." + typ)
        if rec.collide or rec.transp < 1 or not rec.anchored or _bool_prop(a, "CanTouch", True):
            errors.append("OWAnchors.%s: muss unsichtbar, verankert, CanCollide/CanTouch false sein" % typ)
        want = ow_anchor_cf(typ)
        if any(abs(x - y) > 1e-3 for x, y in zip(rec.cf.p, want.p)) or \
                any(abs(x - y) > 1e-3 for x, y in zip(rec.cf.look, want.look)):
            errors.append("OWAnchors.%s: liegt nicht auf plots.OW_ANCHORS (%s statt %s)" %
                          (typ, tuple(round(v, 2) for v in rec.cf.p), tuple(round(v, 2) for v in want.p)))
        if get_attrs(a).get("OWType") != typ:
            errors.append("OWAnchors.%s: Attribut OWType fehlt" % typ)


def _ow_template_structure(model, name, who, errors):
    from worldgen import ow_buildings as OB
    root = child(model, "Root")
    pp = get_prop(model, "PrimaryPart")
    if root is None or root.get("class") != "Part":
        errors.append("%s: Part Root fehlt" % who)
    else:
        if pp is None or pp.text != root.get("referent"):
            errors.append("%s: PrimaryPart ist nicht Root" % who)
        rec = scan.record(root, who + ".Root")
        if any(abs(a - b) > 1e-6 for a, b in zip(rec.cf.p, (0.0, OB.ROOT_Y, 0.0))) or \
                any(abs(v) > 1e-6 for v in (rec.cf.look[0], rec.cf.look[1], rec.cf.look[2] + 1)):
            errors.append("%s: Root muss unverdreht bei (0, %g, 0) liegen" % (who, OB.ROOT_Y))
        if rec.collide or rec.transp < 1:
            errors.append("%s: Root muss unsichtbar und CanCollide=false sein" % who)
    a = get_attrs(model)
    typ, stage = ("baustelle", 0) if name == "baustelle" else (name.rsplit("_", 1)[0], int(name.rsplit("_", 1)[1]))
    if a.get("OWType") != typ or a.get("OWStage") != stage:
        errors.append("%s: Attribute OWType=%r / OWStage=%r erwartet" % (who, typ, stage))
    if name == "baustelle":
        labels = {name_of(x) for x in model.iter("Item") if x.get("class") == "TextLabel"}
        if "Countdown" not in labels:
            errors.append("%s: TextLabel 'Countdown' fehlt (OWService schreibt die Restzeit hinein)" % who)
    anim_items = []
    for it in model.iter("Item"):
        at = get_attrs(it)
        if "Anim" in at:
            if at["Anim"] not in OB.ANIM_KINDS:
                errors.append("%s: unbekannte Anim=%r an %s" % (who, at["Anim"], name_of(it)))
            anim_items.append((it, at["Anim"]))
        if "TycoonAnim" in at:
            if at["TycoonAnim"] not in OB.TYCOON_ANIM_KINDS:
                errors.append("%s: unbekannte TycoonAnim=%r an %s" % (who, at["TycoonAnim"], name_of(it)))
            anim_items.append((it, at["TycoonAnim"]))
    moving = {id(it) for it, kind in anim_items if kind in OB.MOVING}
    parent_of = {id(c): p for p in model.iter("Item") for c in p.findall("Item")}
    for it, kind in anim_items:
        if kind not in OB.MOVING:
            continue
        p = parent_of.get(id(it))
        while p is not None and p is not model:
            if id(p) in moving:
                errors.append("%s: bewegte Animation %s (%s) innerhalb von %s" % (who, name_of(it), kind, name_of(p)))
                break
            p = parent_of.get(id(p))


def ow_checks(tree, city_parts, errors, warns, info, verbose=False):
    """Plot-Anker + Vorlagen ServerStorage.OWBuildings (ow_buildings.py) - einzeln und an allen 8 Slots eingesetzt."""
    from worldgen import ow_buildings as OB
    from worldgen.plots import OW_TYPES, RECT, SLOTS, loc2world, ow_anchor_cf, slot_cf
    from worldgen.lib import CF
    _ow_anchor_checks(tree, errors)
    tpls = OB.templates_of(tree)
    if not tpls:
        errors.append("ServerStorage.OWBuildings fehlt im Place")
        return
    for name in OB.template_names():
        if name not in tpls:
            errors.append("OWBuildings.%s fehlt" % name)
    # Grundstücks-Teile (Vorlage mit Vollausbau) und Stadt-Teile für die Einsetz-Prüfung
    plot_parts = [p for p in scan.plot_parts(tree) + _stage_parts(tree) if p.transp < 0.95]
    city_sel = [p for p in city_parts if ".Vacant." not in p.path and p.name != "Grasplatte" and p.transp < 0.95]
    grid = defaultdict(list)
    for p in city_sel + plot_parts:
        b = p.aabb()
        for gx in range(int(b[0] // 32), int(b[1] // 32) + 1):
            for gz in range(int(b[4] // 32), int(b[5] // 32) + 1):
                grid[(gx, gz)].append((p, b))
    total_p = total_l = 0
    rows = []
    for name, model in sorted(tpls.items()):
        who = "OWBuildings." + name
        if model.get("class") != "Model":
            errors.append("%s muss ein Model sein" % who)
            continue
        _ow_template_structure(model, name, who, errors)
        w, d = OB.footprint(name)
        parts = scan.walk(model, who)
        n = len(parts)
        nl = sum(1 for x in model.iter("Item") if x.get("class") in ("PointLight", "SpotLight", "SurfaceLight"))
        total_p += n
        total_l += nl
        rows.append("%s %d/%d" % (name, n, nl))
        if n > OB.BUDGET[0]:
            errors.append("%s: Part-Budget überschritten: %d > %d" % (who, n, OB.BUDGET[0]))
        if nl > OB.BUDGET[1]:
            errors.append("%s: Licht-Budget überschritten: %d > %d" % (who, nl, OB.BUDGET[1]))
        unanch = [p.path for p in parts if not p.anchored]
        if unanch:
            errors.append("%s: %d Parts nicht verankert: %s" % (who, len(unanch), unanch[:5]))
        out = []
        for p in parts:
            if p.name == "Root":
                continue
            b = p.aabb()
            if b[0] < -w / 2 - 0.01 or b[1] > w / 2 + 0.01 or b[4] < -d / 2 - 0.01 or b[5] > d / 2 + 0.01 \
                    or b[2] < -0.001 or b[3] > OB.MAX_H:
                out.append((p.path[len(who) + 1:], tuple(round(v, 2) for v in b)))
        if out:
            errors.append("%s: %d Parts außerhalb der Grundfläche %g x %g bzw. Y 0..%g: %s" %
                          (who, len(out), w, d, OB.MAX_H, out[:4]))
        walls = [p.path for p in parts if p.collide and p.transp >= 0.95 and p.name != "Root"]
        if walls:
            errors.append("%s: unsichtbare kollidierende Parts: %s" % (who, walls[:5]))
        ov = _pair_overlaps(parts)
        if ov:
            errors.append("%s: %d Überschneidungen (AABB): " % (who, len(ov)))
            for a, b in ov[: (200 if verbose else 10)]:
                errors.append("   %s <-> %s" % (a.path[len(who) + 1:], b.path[len(who) + 1:]))
        cv = _car_overlaps(parts)
        if cv:
            errors.append("%s: %d Auto-Überschneidungen: %s" % (who, len(cv),
                                                               [(a.path[len(who) + 1:], b.path[len(who) + 1:])
                                                                for a, b in cv[:4]]))
        sw = _sweep_conflicts(model, parts, who)
        if sw:
            errors.append("%s: %d Teile im Schwenkbereich drehender Modelle: %s" %
                          (who, len(sw), [(a.path[len(who) + 1:], b.path[len(who) + 1:]) for a, b in sw[:6]]))
        hits = zfight(parts)
        if hits:
            errors.append("%s: %d Z-Fighting-Kandidaten" % (who, len(hits)))
            for a, b, ar, key in hits[: (200 if verbose else 8)]:
                errors.append("   %s <-> %s  Fläche %.2f" % (a.path[len(who) + 1:], b.path[len(who) + 1:], ar))
        nc = near_coplanar(parts)
        if nc:
            errors.append("%s: %d fast koplanare Flächenpaare" % (who, len(nc)))
            for a, b, ar, dd, nrm in sorted(nc, key=lambda h: -h[2])[: (200 if verbose else 8)]:
                errors.append("   %s <-> %s  Fläche %.1f  Abstand %.3f" % (a.path[len(who) + 1:],
                                                                          b.path[len(who) + 1:], ar, dd))
        fl = _floating(parts, lambda p, b: b[2] <= 0.02)
        if fl:
            errors.append("%s: %d schwebende Gruppen" % (who, len(fl)))
            for comp in fl[: (200 if verbose else 8)]:
                y0 = min(p.aabb()[2] for p in comp)
                errors.append("   %s (+%d) Unterkante %.2f bei (%.1f, %.1f)" % (comp[0].path[len(who) + 1:],
                                                                             len(comp) - 1, y0, comp[0].cf.p[0],
                                                                             comp[0].cf.p[2]))
        # an allen 8 Slots eingesetzt: innerhalb der Plot-Fläche, keine Durchdringung mit Stadt/Grundstück
        if not city_parts:
            continue
        typs = OW_TYPES if name == "baustelle" else (name.rsplit("_", 1)[0],)
        for typ in typs:
            for slot, house, px, pz, rot in SLOTS:
                anchor = slot_cf(px, pz, rot) * ow_anchor_cf(typ)
                xf = anchor * CF(0, OB.ROOT_Y, 0).inverse()
                tparts = [p for p in scan.walk(model, who, False, xf) if p.transp < 0.95 and not p.attrs.get("Pierce")]
                fa = loc2world(px, pz, rot, RECT[0], RECT[2])
                fb = loc2world(px, pz, rot, RECT[1], RECT[3])
                fx0, fx1 = min(fa[0], fb[0]), max(fa[0], fb[0])
                fz0, fz1 = min(fa[1], fb[1]), max(fa[1], fb[1])
                bad = []
                for p in tparts:
                    a = p.aabb()
                    if a[0] < fx0 - 0.01 or a[1] > fx1 + 0.01 or a[4] < fz0 - 0.01 or a[5] > fz1 + 0.01:
                        bad.append("%s außerhalb der Plot-Fläche" % p.path[len(who) + 1:])
                    seen = set()
                    for gx in range(int(a[0] // 32), int(a[1] // 32) + 1):
                        for gz in range(int(a[4] // 32), int(a[5] // 32) + 1):
                            for q, b in grid.get((gx, gz), ()):
                                if id(q) in seen:
                                    continue
                                seen.add(id(q))
                                if _pen(a, b, 0.02):
                                    bad.append("%s <-> %s" % (p.path[len(who) + 1:], q.path))
                if bad:
                    errors.append("%s an Slot_%d (Anker %s): %d Konflikte: %s" % (who, slot, typ, len(bad), bad[:4]))
    info.append("OWBuildings: %d Vorlagen, %d Parts, %d Lichter (Budget je Vorlage %d / %d)"
                % (len(tpls), total_p, total_l, *OB.BUDGET))
    if verbose:
        info.append("  Vorlagen Parts/Lichter: " + ", ".join(rows))
    else:
        info.append("  größte: " + ", ".join(sorted(rows, key=lambda r: -int(r.split()[1].split("/")[0]))[:4]))


def mission_checks(city, parts, errors, warns, info):
    """City.Missions.Delivery_<n>: Model mit Parts Start/Ziel (Role start/end), unsichtbar, CanCollide false,
    CanTouch true, Attribut Route, Unterkante auf Asphalt (-0.95), Start-Ziel 300..600 Studs."""
    from worldgen.ground_roads import Y_ROAD
    folder = child(city, "Missions")
    if folder is None:
        errors.append("City.Missions fehlt")
        return
    roads = [(p, p.aabb()) for p in parts if p.collide and p.transp < 1 and abs(p.top - Y_ROAD) < 1e-3]
    n = 0
    for m in children(folder):
        nm = name_of(m)
        if not nm.startswith("Delivery_"):
            continue
        n += 1
        who = "City.Missions." + nm
        if m.get("class") != "Model" or get_attrs(m).get("Route") is None:
            errors.append("%s: Model mit Attribut Route erwartet" % who)
        pts = {}
        for pn, role in (("Start", "start"), ("Ziel", "end")):
            it = child(m, pn)
            if it is None or it.get("class") != "Part":
                errors.append("%s: Part %s fehlt" % (who, pn))
                continue
            rec = scan.record(it, who + "." + pn)
            a = get_attrs(it)
            if rec.collide or rec.transp < 1 or not rec.anchored or not _bool_prop(it, "CanTouch", True):
                errors.append("%s.%s: unsichtbar, verankert, CanCollide false, CanTouch true erwartet" % (who, pn))
            if a.get("Role") != role or a.get("Route") is None:
                errors.append("%s.%s: Attribute Role=%r / Route erwartet" % (who, pn, role))
            b = rec.aabb()
            if abs(b[2] - Y_ROAD) > 0.05:
                errors.append("%s.%s: Unterkante %.2f statt auf der Fahrbahn %.2f" % (who, pn, b[2], Y_ROAD))
            x, z = rec.cf.p[0], rec.cf.p[2]
            if not any(bb[0] <= x <= bb[1] and bb[4] <= z <= bb[5] for p, bb in roads):
                errors.append("%s.%s: (%.0f, %.0f) liegt nicht auf Asphalt" % (who, pn, x, z))
            pts[pn] = (x, z)
        if len(pts) == 2:
            dist = math.dist(pts["Start"], pts["Ziel"])
            if not 300 <= dist <= 600:
                errors.append("%s: Start-Ziel %.0f Studs (soll 300..600)" % (who, dist))
    if n < 3:
        errors.append("City.Missions: %d Lieferrouten (Delivery_1..3 erwartet)" % n)
    info.append("Lieferrouten: %d" % n)


def kiesplatz_checks(city, errors, warns, info):
    """Kiesplatz (districts/kiesplatz.py): Spots mit Auto, NPC-Kunden unter Animated, Preistafel (Line1..3 mit der
    Legende günstig/fair/teuer; StoryUI schreibt die Kundenpreise hinein), Station/Ankunft."""
    districts = child(city, "Districts")
    dm = child(districts, "Kiesplatz") if districts is not None else None
    if dm is None:
        errors.append("City.Districts.Kiesplatz fehlt")
        return
    spots = child(dm, "Spots")
    for n in (1, 2, 3):
        sp = child(spots, "Spot_%d" % n) if spots is not None else None
        if sp is None or sp.get("class") != "Part" or get_attrs(sp).get("Spot") != n:
            errors.append("Kiesplatz.Spots.Spot_%d fehlt oder ohne Attribut Spot=%d" % (n, n))
        cars = [x for x in children(spots) if x.get("class") == "Model" and get_attrs(x).get("Spot") == n and
                "Body" in get_attrs(x)] if spots is not None else []
        if len(cars) != 1:
            errors.append("Kiesplatz.Spots: %d Autos für Spot %d (1 erwartet)" % (len(cars), n))
    anim = child(child(city, "Animated"), "Kiesplatz")
    if anim is None:
        errors.append("City.Animated.Kiesplatz fehlt")
    else:
        for n in (1, 2, 3):
            k = child(anim, "Kunde_%d" % n)
            a = get_attrs(k) if k is not None else {}
            if k is None or a.get("Anim") != "npc_idle" or a.get("Spot") != n:
                errors.append("Animated.Kiesplatz.Kunde_%d: Model mit Anim=npc_idle und Spot=%d erwartet" % (n, n))
            elif get_prop(k, "PrimaryPart") is None or child(k, "Head") is None or child(k, "Torso") is None:
                errors.append("Animated.Kiesplatz.Kunde_%d: PrimaryPart, Head und Torso erwartet" % n)
    board = next((g for g in dm.iter("Item") if g.get("class") == "SurfaceGui" and name_of(g) == "PriceBoard"), None)
    labels = {name_of(x) for x in board.iter("Item") if x.get("class") == "TextLabel"} if board is not None else set()
    if {"Line1", "Line2", "Line3"} - labels:
        errors.append("Kiesplatz: SurfaceGui PriceBoard mit TextLabels Line1..3 fehlt")
    elif board is not None:
        # get_prop liefert das XML-Element: den Text daraus lesen (sonst wäre jede Legende ein „Platzhalter“)
        texts = {name_of(x): getattr(get_prop(x, "Text"), "text", None) for x in board.iter("Item")
                 if x.get("class") == "TextLabel"}
        for n, word in ((1, "günstig"), (2, "fair"), (3, "teuer")):
            if word not in str(texts.get("Line%d" % n) or ""):
                errors.append("Kiesplatz: PriceBoard.Line%d sollte die Legende „%s“ zeigen (kein Platzhalter)" % (n, word))
    st = child(child(city, "Stations"), "kiesplatz")
    if st is None or get_attrs(st).get("MiniTab") != "story":
        errors.append("Station kiesplatz mit MiniTab=story fehlt")
    if child(child(city, "Arrivals"), "kiesplatz") is None:
        errors.append("Arrival kiesplatz fehlt")
    info.append("Kiesplatz: %d Parts" % sum(1 for x in dm.iter("Item") if x.get("class") in
                                           ("Part", "WedgePart", "CornerWedgePart", "TrussPart")))


# ---------------------------------------------------------------- Fahrzeuge (PHASE2_CONTRACT §3)
OPENED_STATIONS = ("dealer", "testdrive", "track", "carwash", "auction", "auction_consign", "arcade")
REQUIRED_SPAWNS = ("dealer", "testdrive", "track", "carwash")


def _bool_prop(item, name, default):
    e = get_prop(item, name)
    return default if e is None or e.text is None else e.text == "true"


def _stage_parts(tree):
    from worldgen.plots import slot_cf
    ss = next(i for i in tree.getroot().findall("Item") if i.get("class") == "ServerStorage")
    ext = child(ss, "WorkshopExtensions")
    out = []
    for slot, house, px, pz, rot in SLOTS:
        for st in children(ext) if ext is not None else []:
            scan.walk(st, "Plot%d.%s" % (slot, name_of(st)), False, slot_cf(px, pz, rot), out)
    return out


def _report_drive(errors, who, probs, verbose):
    if probs:
        errors.append("%s: %d Befahrbarkeits-Probleme" % (who, len(probs)))
        for kind, x, z, off, detail in probs[: (60 if verbose else 5)]:
            errors.append("   %s bei (%.1f, %.1f) Spur %+.1f: %s" % (kind, x, z, off, detail))


def vehicle_checks(tree, city, parts, errors, warns, info, verbose=False):
    from worldgen import drive, vehicles
    from worldgen.ground_roads import traffic_loops
    world = drive.World(parts)
    # a) Verkehrsschleifen: alle Spuren ohne Stufe > 0.6 / Hindernis
    track_line = vehicles.track_loop()
    # 3.0: keine Verkehrsschleife (Autos mit fester Kollisionsbox) darf die Teststrecke berühren, sonst fährt ein
    # Zeitfahr-Auto von hinten auf ein Verkehrsauto auf
    track_pts = drive.polyline_samples(track_line, True, 2.0)
    for key, nm, pts, speed in traffic_loops():
        near = min(min(math.hypot(x - sx, z - sz) for sx, sz, dx, dz in track_pts)
                   for x, z, a, b in drive.polyline_samples(list(pts), True, 4.0))
        if near < vehicles.TRACK_WIDTH / 2 + 8:
            errors.append("Schleife %s (Verkehr) kommt der Teststrecke bis %.0f Studs nahe (Mittellinie): Verkehr "
                          "mit Kollisionsbox gehört nicht auf die Rennlinie" % (key, near))
        _report_drive(errors, "Schleife %s (%s)" % (key, nm), drive.drive(world, pts, -0.95, True, (-5.0, 0.0, 5.0)),
                      verbose)
    _report_drive(errors, "Teststrecke (Mittellinie, Spuren ±9)",
                  drive.drive(world, track_line, -0.95, True, (-9.0, -4.5, 0.0, 4.5, 9.0)), verbose)
    # b) CarSpawns
    folder = child(city, "CarSpawns")
    have = {name_of(c): c for c in children(folder)} if folder is not None else {}
    miss = [k for k in REQUIRED_SPAWNS if k not in have]
    if miss:
        errors.append("CarSpawns fehlen: %s" % miss)
    ok_spawns = 0

    def check_spot(who, w, x, fy, z, yaw, alts):
        nf, blk = drive.footprint_blockers(w, x, fy, z, yaw)
        if nf or blk:
            errors.append("%s: Stellfläche nicht frei (%s%s)" % (who, ("ohne Boden %s " % nf[:3]) if nf else "",
                                                                  blk[:4]))
            return False
        (lx, lz), (rx, rz) = drive.look_right(yaw)
        for st in alts:
            ax, az = x + rx * st * 11, z + rz * st * 11
            g = w.ground(ax, az, fy, 0.3)
            nf, blk = drive.footprint_blockers(w, ax, fy if g is None else g, az, yaw)
            if nf or blk:
                errors.append("%s: Ausweichplatz %+d (%.1f, %.1f) nicht frei (%s%s)" % (
                    who, st, ax, az, ("ohne Boden %s " % nf[:2]) if nf else "", blk[:3]))
        return True
    for key, it in have.items():
        rec = scan.record(it, "City.CarSpawns." + key)
        if rec.collide or rec.transp < 1 or not rec.anchored or _bool_prop(it, "CanTouch", True) or \
                _bool_prop(it, "CanQuery", True):
            errors.append("CarSpawn %s: muss unsichtbar, verankert, CanCollide/CanTouch/CanQuery false sein" % key)
        spec = vehicles.CAR_SPAWNS.get(key)
        if spec is None:
            warns.append("CarSpawn %s nicht in vehicles.CAR_SPAWNS" % key)
            continue
        title, x, fy, z, yaw, alts, route = spec
        look = rec.cf.look
        want = drive.look_right(yaw)[0]
        if abs(look[0] - want[0]) > 1e-3 or abs(look[2] - want[1]) > 1e-3 or abs(look[1]) > 1e-3:
            errors.append("CarSpawn %s: Blickrichtung %s statt %s" % (key, look, want))
        g = world.ground(x, z, fy, 0.3)
        if g is None or abs(g - fy) > 0.12:
            errors.append("CarSpawn %s: Boden %s statt %.2f" % (key, g, fy))
        if abs(rec.aabb()[2] - fy) > 0.01:
            errors.append("CarSpawn %s: Unterseite %.2f nicht auf dem Boden %.2f" % (key, rec.aabb()[2], fy))
        if check_spot("CarSpawn " + key, world, x, fy, z, yaw, alts):
            ok_spawns += 1
        _report_drive(errors, "Ausfahrt CarSpawn " + key, drive.drive(world, route, fy, False), verbose)
    info.append("CarSpawns: %d / %d frei und befahrbar (%s)" % (ok_spawns, len(have), ", ".join(sorted(have))))
    # c) Plot-Vorlage: CarSpawn + Einfahrt an allen Slots (Vollausbau, ohne Vacant-Kit)
    ws = scan.workspace(tree)
    wk = child(ws, "Werkstatt")
    cs = child(wk, "CarSpawn") if wk is not None else None
    if cs is None:
        errors.append("Plot-Vorlage: Part CarSpawn fehlt")
    else:
        rec = scan.record(cs, "Werkstatt.CarSpawn")
        if rec.collide or rec.transp < 1 or not rec.anchored or _bool_prop(cs, "CanTouch", True):
            errors.append("Plot-Vorlage CarSpawn: muss unsichtbar, verankert, CanCollide/CanTouch false sein")
        plot_world = drive.World([p for p in parts if ".Vacant." not in p.path] + scan.plot_parts(tree) +
                                 _stage_parts(tree))
        lx, fy, lz, yaw0, alts = vehicles.PLOT_SPAWN
        n_ok = 0
        for slot, house, px, pz, rot in SLOTS:
            x, fy, z, yaw = vehicles.plot_spawn_world(px, pz, rot)
            w = rec.cf.p
            wx, wz = loc2world(px, pz, rot, w[0], w[2])
            if abs(wx - x) > 1e-3 or abs(wz - z) > 1e-3:
                errors.append("Plot-CarSpawn: Vorlage (%.1f, %.1f) != vehicles.PLOT_SPAWN" % (w[0], w[2]))
                break
            ok = check_spot("Plot %d CarSpawn" % slot, plot_world, x, fy, z, yaw, alts)
            probs = drive.drive(plot_world, vehicles.plot_route_world(px, pz, rot), fy, False)
            _report_drive(errors, "Plot %d Ausfahrt" % slot, probs, verbose)
            n_ok += ok and not probs
        info.append("Plot-CarSpawn: %d / %d Slots frei und bis zur Meile befahrbar" % (n_ok, len(SLOTS)))
    # d) Teststrecke
    tr = child(city, "Track")
    cps = child(tr, "Checkpoints") if tr is not None else None
    if cps is None:
        errors.append("City.Track.Checkpoints fehlt")
    else:
        names = [name_of(c) for c in children(cps)]
        n = 0
        while "CP%d" % (n + 1) in names:
            n += 1
        if n < 3 or n != len(names):
            errors.append("Checkpoints: CP1..CPn lückenlos erwartet, gefunden %s" % names)
        seq = [child(cps, "CP%d" % (i + 1)) for i in range(n)] + [child(tr, "Ziel")]
        if seq[-1] is None:
            errors.append("City.Track.Ziel fehlt")
            seq = seq[:-1]
        samples = drive.polyline_samples(track_line, True, 1.0)
        for it in seq:
            rec = scan.record(it, "City.Track." + name_of(it))
            if rec.collide or rec.transp < 1 or not rec.anchored or not _bool_prop(it, "CanTouch", True):
                errors.append("Checkpoint %s: unsichtbar, verankert, CanCollide false, CanTouch true erwartet" %
                              rec.name)
            c = rec.cf.p
            d, dirv = min((math.hypot(sx - c[0], sz - c[2]), (dx, dz)) for sx, sz, dx, dz in samples)
            if d > 3:
                errors.append("Checkpoint %s liegt %.1f neben der Ideallinie" % (rec.name, d))
            across = rec.cf.vector((1, 0, 0))
            if rec.size[0] < vehicles.TRACK_WIDTH + 2 or abs(across[0] * dirv[0] + across[2] * dirv[1]) > 0.2:
                errors.append("Checkpoint %s deckt die Streckenbreite nicht quer ab" % rec.name)
            if rec.aabb()[2] > -0.95 + 0.01 or rec.aabb()[3] < 6:
                errors.append("Checkpoint %s: Höhe %.2f..%.2f (Fahrzeug muss hindurch)" % (rec.name, rec.aabb()[2],
                                                                                            rec.aabb()[3]))
        info.append("Teststrecke: %d Checkpoints + Ziel" % n)
    # e) Bildschirme
    guis = [x for x in city.iter("Item") if x.get("class") == "SurfaceGui"]
    auction = [g for g in guis if name_of(g) == "AuctionScreen"]
    if len(auction) != 1:
        errors.append("AuctionScreen: %d SurfaceGuis (soll 1)" % len(auction))
    else:
        labs = {name_of(x) for x in auction[0].iter("Item") if x.get("class") == "TextLabel"}
        if {"Title", "Lot", "Bid", "Time"} - labs:
            errors.append("AuctionScreen: Labels fehlen %s" % sorted({"Title", "Lot", "Bid", "Time"} - labs))
    screens = [g for g in guis if name_of(g) == "Screen"]
    titled = [g for g in screens if any(x.get("class") == "TextLabel" and name_of(x) == "Title" for x in g.iter("Item"))]
    from worldgen.contract import ARCADE_GAMES
    if len(titled) != len(ARCADE_GAMES) or len(screens) != len(ARCADE_GAMES):
        errors.append("Spielhalle: %d Screens / %d mit Title (soll je %d)" % (len(screens), len(titled),
                                                                            len(ARCADE_GAMES)))
    walls = [p.path for p in parts if p.collide and p.transp >= 0.95 and p.name != "Grenze"]
    if walls:
        errors.append("Unsichtbare kollidierende Parts (nur die Stadtgrenze darf das): %s" % walls[:5])
    st = child(city, "Stations")
    soon = [name_of(s) for s in children(st) if (name_of(s) in OPENED_STATIONS or name_of(s).startswith("arcade_"))
            and "Soon" in get_attrs(s)] if st is not None else []
    if soon:
        errors.append("Stationen noch mit Soon: %s" % soon)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
