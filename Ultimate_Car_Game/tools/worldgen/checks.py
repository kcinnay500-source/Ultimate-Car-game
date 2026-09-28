#!/usr/bin/env python3
"""Prüft die gebaute Stadt (Workspace.City) im Place.

  python3 tools/worldgen/checks.py [/tmp/claude-0/foundation.rbxlx] [--verbose]

Prüfungen:
  * alle BaseParts verankert; keine Parts unter Y -3 (außer Liste INTENDED_LOW)
  * Z-Fighting-Kandidaten: exakt koplanare, gleich orientierte Flächen, die sich überlappen
    (Oberseiten und senkrechte Seiten; Vorlagen-Autos ausgenommen)
  * Parts und Lichter je Bereich gegen das Budget (CITY_SPEC §10)
  * Stationen / Ankunftspunkte / CitySpawn gemäß Vertrag (Prompt-Werte, Attachment Arrival, freier Boden)
  * Stadt-Parts in Plot-Grundflächen (außer PlotSlots.*.Vacant und Bodenplatte)
  * Anim-Attribute nur unter City.Animated; Plot-Vorlage: Start deaktiviert, Anker vorhanden
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

INTENDED_LOW = {"Grasplatte", "Teichbecken", "Teichboden"}
# Budget je District-Model (Name unter City.Districts) - Parts ohne Vorlagen-Autos, Lichter (§10)
DISTRICT_BUDGET = {
    "Stadtplatz": (360 + 140 + 82, 9), "Platzgebaeude": (250 + 90 + 161 + 77, 11),
    "Parkplatz": (135 + 371 + 99 + 56 + 150, 10), "Autohaus": (203 + 131, 11), "Tuning": (263, 7),
    "Schrottplatz": (532, 5),
}
FOLDER_BUDGET = {"Ground": (11 + 220, 0), "Roads": (275 + 128 + 24 + 60, 0), "Lights": (220, 52),
                 "PlotSlots": (282 + 88, 0)}
TOTAL_BUDGET = 7740
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


# ---------------------------------------------------------------- Prüfungen
def main(argv):
    place = next((a for a in argv if not a.startswith("--")), scan.DEFAULT_PLACE)
    verbose = "--verbose" in argv
    tree = scan.load(place)
    city, parts = scan.city_parts(tree)
    errors, warns, info = [], [], []
    if city is None:
        print("FEHLER: Workspace.City fehlt")
        return 1
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
    # 3) Budget
    total = len(parts)
    cars_parts = sum(1 for p in parts if p.car)
    traffic = sum(1 for p in parts if p.path.startswith("City.Animated.Verkehr"))
    def count_lights(item):
        return sum(1 for x in item.iter("Item") if x.get("class") in ("PointLight", "SpotLight", "SurfaceLight"))
    lights_total = count_lights(city)
    info.append("Parts gesamt %d (davon Vorlagen-Autos %d, Verkehrsautos %d); ohne Verkehr %d / Budget %d"
                % (total, cars_parts, traffic, total - traffic, TOTAL_BUDGET))
    if total - traffic > TOTAL_BUDGET:
        errors.append("Part-Budget überschritten: %d > %d" % (total - traffic, TOTAL_BUDGET))
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
    # Ausgabe
    for line in info:
        print(line)
    for w in warns:
        print("WARNUNG:", w)
    for e in errors:
        print("FEHLER:" if not e.startswith("   ") else "      ", e.strip() if e.startswith("   ") else e)
    print("OK" if not errors else "%d Fehler" % sum(1 for e in errors if not e.startswith("   ")))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
