#!/usr/bin/env python3
"""Selbsttest für vehicles.py / drive.py (ohne gebauten Place, außer mit Pfad-Argument).

  python3 tools/worldgen/test_vehicles.py                 reine Geometrie- und Tabellen-Tests
  python3 tools/worldgen/test_vehicles.py <place.rbxlx>   zusätzlich: gebaute Stadt (CarSpawns, Track, Screens)
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from worldgen import drive, vehicles  # noqa: E402
from worldgen.lib import CF  # noqa: E402
from worldgen.plots import RECT, SLOTS  # noqa: E402

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


class FakePart:
    def __init__(self, cls, size, cf, shape=1, collide=True, path="Test"):
        self.cls, self.size, self.cf, self.shape, self.collide, self.path = cls, size, cf, shape, collide, path
        self.item = object()
        self.car = False
        self.name = path

    def corners(self):
        hx, hy, hz = self.size[0] / 2, self.size[1] / 2, self.size[2] / 2
        return [self.cf.point((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]

    def aabb(self):
        c = self.corners()
        return (min(p[0] for p in c), max(p[0] for p in c), min(p[1] for p in c), max(p[1] for p in c),
                min(p[2] for p in c), max(p[2] for p in c))


def near(a, b, eps=1e-6):
    return a is not None and b is not None and abs(a[0] - b[0]) < eps and abs(a[1] - b[1]) < eps


def test_intervals():
    box = FakePart("Part", (4, 2, 6), CF(0, 1, 0))
    check(near(drive.vertical_interval(box, 1, 2), (0, 2)), "Quader-Intervall")
    check(drive.vertical_interval(box, 3, 0) is None, "Quader außerhalb")
    rot = FakePart("Part", (4, 2, 6), CF.at(10, 1, 0, 90))          # 90° gedreht: X-Ausdehnung 6
    check(drive.vertical_interval(rot, 12.5, 0) is not None and drive.vertical_interval(rot, 10, 2.5) is None,
          "gedrehter Quader")
    # Keil wie Torrampe: volle Höhe bei lokal +Z; yaw 90 -> lokal +Z zeigt nach Osten (+X)
    w = FakePart("WedgePart", (24, 0.95, 6), CF.at(77, -0.475, 76, 90))
    lo, hi = drive.vertical_interval(w, 79.9, 76)
    check(abs(hi - (-0.95 + 0.95 * 5.9 / 6)) < 1e-3 and abs(lo + 0.95) < 1e-6, "Keil hoch am Ostende (%s)" % hi)
    lo, hi = drive.vertical_interval(w, 74.3, 76)
    check(hi < -0.85, "Keil flach am Westende (%s)" % hi)
    cyl = FakePart("Part", (0.3, 10, 10), CF(0, -1.15, 0) * CF.angles(0, 0, math.pi / 2), shape=2)  # stehend
    iv = drive.vertical_interval(cyl, 3, 3)
    check(iv is not None and abs(iv[1] + 1.0) < 1e-6, "stehender Zylinder Oberseite (%s)" % (iv,))
    check(drive.vertical_interval(cyl, 4, 4) is None, "stehender Zylinder außerhalb")
    ball = FakePart("Part", (2, 2, 2), CF(0, 5, 0), shape=0)
    check(near(drive.vertical_interval(ball, 0, 0), (4, 6)), "Kugel")


def test_drive():
    floor = FakePart("Part", (100, 0.3, 20), CF(0, -1.1, 0), path="Boden")
    curb_ok = FakePart("Part", (10, 0.75, 20), CF(10, -0.875, 0), path="Bordstein045")     # Oberseite -0.5
    w = drive.World([floor, curb_ok])
    check(drive.drive(w, [(-40, 0), (40, 0)], -0.95, offsets=(0,)) == [], "0.45-Stufe befahrbar")
    curb_bad = FakePart("Part", (10, 1.0, 20), CF(30, -0.75, 0), path="Bordstein07")     # Oberseite -0.25
    w = drive.World([floor, curb_bad])
    pr = drive.drive(w, [(-40, 0), (40, 0)], -0.95, offsets=(0,))
    check(len(pr) == 1 and pr[0][0] == "Hindernis" and "Bordstein07" in pr[0][4], "0.7-Stufe erkannt (%s)" % pr)
    wall = FakePart("Part", (1, 60, 20), CF(0, 29, 0), path="UnsichtbareWand")
    w = drive.World([floor, wall])
    check(any("UnsichtbareWand" in p[4] for p in drive.drive(w, [(-40, 0), (40, 0)], -0.95)), "Wand erkannt")
    deco = FakePart("Part", (1, 60, 20), CF(0, 29, 0), collide=False, path="Deko")
    w = drive.World([floor, deco])
    check(drive.drive(w, [(-40, 0), (40, 0)], -0.95) == [], "Deko ohne CanCollide ignoriert")
    beam = FakePart("Part", (2, 2, 30), CF(0, 16, 0), path="Traeger")
    w = drive.World([floor, beam])
    check(drive.drive(w, [(-40, 0), (40, 0)], -0.95) == [], "Träger über der Fahrbahn ignoriert")
    gap = drive.World([FakePart("Part", (20, 0.3, 20), CF(-30, -1.1, 0))])
    check(any(p[0] == "kein Boden" for p in drive.drive(gap, [(-35, 0), (0, 0)], -0.95, offsets=(0,))),
          "fehlender Boden erkannt")
    nf, blk = drive.footprint_blockers(drive.World([floor, curb_bad]), 30, -0.95, 0, 90)
    check(blk == ["Bordstein07"], "Stellfläche blockiert (%s)" % blk)


def test_tables():
    for key in ("dealer", "testdrive", "track", "carwash"):
        check(key in vehicles.CAR_SPAWNS, "Spawn %s fehlt" % key)
    for key, (title, x, fy, z, yaw, alts, route) in vehicles.CAR_SPAWNS.items():
        check(isinstance(title, str) and title, "Titel %s" % key)
        check(math.dist(route[0], (x, z)) < 1e-6, "Route %s beginnt am Spawn" % key)
        (lx, lz), _ = drive.look_right(yaw)
        d = (route[1][0] - x, route[1][1] - z)
        ln = math.hypot(*d)
        check(ln > 0 and (d[0] * lx + d[1] * lz) / ln > 0.9, "Spawn %s schaut in Richtung Ausfahrt" % key)
        check(-1.01 <= fy <= -0.94, "Bodenhöhe %s" % key)
        check(all(isinstance(a, int) and a != 0 for a in alts), "AltSteps %s" % key)
    lx, fy, lz, yaw, alts = vehicles.PLOT_SPAWN
    check(RECT[0] + 6 < lx < RECT[1] - 6 and RECT[2] + 10 < lz < RECT[3] - 10, "Plot-Spawn in der Fläche")
    check(-30 + 5.2 <= lx <= 30 - 5.2, "Plot-Spawn vor der Einfahrt (lokal X -30..30)")
    for slot, house, px, pz, rot in SLOTS:
        x, y, z, yw = vehicles.plot_spawn_world(px, pz, rot)
        (ax, az), _ = drive.look_right(yw)
        check(az * (-1 if pz > 0 else 1) > 0.99, "Plot %d: Nase zur Meile" % slot)
        r = vehicles.plot_route_world(px, pz, rot)
        check(abs(abs(r[-1][1]) - 6.5) < 1e-6, "Plot %d: Route endet auf der Meile-Spur" % slot)


def test_checkpoints():
    cps = vehicles.checkpoints()
    check(cps[-1][0] == "Ziel" and [c[0] for c in cps[:-1]] == ["CP%d" % (i + 1) for i in range(len(cps) - 1)],
          "Checkpoint-Namen")
    loop = vehicles.track_loop()
    samples = drive.polyline_samples(loop, True, 0.5)
    last = i0 = None
    for name, (x, z), (dx, dz) in cps:
        d, i = min((math.hypot(sx - x, sz - z), i) for i, (sx, sz, a, b) in enumerate(samples))
        sd = samples[i]
        i0 = i if i0 is None else i0
        i = (i - i0) % len(samples)          # Mittellinie beginnt bei (-90, 270): relativ zu CP1 zählen
        check(d < 2.0, "%s auf der Ideallinie (%.2f)" % (name, d))
        check(dx * sd[2] + dz * sd[3] > 0.95, "%s Fahrtrichtung" % name)
        if last is not None and name != "Ziel":
            check(i > last, "%s nach dem vorigen Checkpoint" % name)
        last = i
    x, fy, z, yaw = vehicles.spawn_world("track")
    zx = cps[-1][1][0]
    check(x < zx - vehicles.CP_SIZE[2] / 2 - drive.CAR_HALF_L, "Startplatz vor der Ziellinie, ohne sie zu berühren")


def test_track_geometry():
    """3.0 Grand-Prix-Kurs: Mittellinie geschlossen, tangential stetig, länger als das alte Oval, Kurvenmix"""
    geo = vehicles.track_geometry()
    check(math.dist(geo[-1][2], vehicles.TRACK_START) < 1e-6, "Strecke geschlossen (%s)" % (geo[-1][2],))
    for i, g in enumerate(geo):
        nxt = geo[(i + 1) % len(geo)]
        check(math.dist(g[2], nxt[1]) < 1e-6, "Stück %d schließt an" % i)
        (p, d1), (q, d2) = vehicles.track_point(i, 1.0), vehicles.track_point((i + 1) % len(geo), 0.0)
        check(d1[0] * d2[0] + d1[1] * d2[1] > 0.9999, "Stück %d tangential stetig" % i)
    ln = vehicles.track_length()
    check(1100 < ln < 1400, "Rundenlänge %.0f (altes Oval ~780)" % ln)
    arcs = [g[3] for g in geo if g[0] == "A"]
    check(any(abs(a[3] - a[2]) >= 179 and a[1] <= 40 for a in arcs), "Haarnadel (180°, enger Radius)")
    check(any(a[1] >= 80 for a in arcs), "schnelle Kurve (großer Radius)")
    check(any(g[0] == "A" and g[3][4] < 0 for g in geo) and any(g[0] == "A" and g[3][4] > 0 for g in geo),
          "Links- und Rechtskurven (S-Kurve)")
    check(max(math.dist(g[1], g[2]) for g in geo if g[0] == "S") >= 300, "lange Gerade >= 300")
    for x, z in vehicles.track_loop(5.0):
        check(-300 <= x <= 300 and 230 <= z <= 560 - vehicles.TRACK_WIDTH / 2, "Mittellinie im Gelände (%g,%g)" % (x, z))
    check(len(vehicles.checkpoints()) <= 20, "höchstens 20 Checkpoints (Zeitfahren-Tests: 9 s je Abschnitt < 240 s)")


def test_place(path):
    from worldgen import scan
    from worldgen.lib import child, children, get_attrs, name_of
    tree = scan.load(path)
    city, parts = scan.city_parts(tree)
    sp = child(city, "CarSpawns")
    check(sp is not None and {"dealer", "testdrive", "track", "carwash"} <= {name_of(c) for c in children(sp)},
          "City.CarSpawns")
    for c in children(sp):
        r = scan.record(c, name_of(c))
        (lx, lz), _ = drive.look_right(vehicles.CAR_SPAWNS[name_of(c)][4])
        check(abs(r.cf.look[0] - lx) < 1e-6 and abs(r.cf.look[2] - lz) < 1e-6, "LookVector %s" % name_of(c))
        check("Title" in get_attrs(c) and "AltSteps" in get_attrs(c), "Attribute %s" % name_of(c))
    wk = child(scan.workspace(tree), "Werkstatt")
    check(child(wk, "CarSpawn") is not None, "Werkstatt.CarSpawn")
    tr = child(city, "Track")
    check(child(tr, "Ziel") is not None and child(child(tr, "Checkpoints"), "CP1") is not None, "Track")
    guis = {name_of(x) for x in city.iter("Item") if x.get("class") == "SurfaceGui"}
    check("AuctionScreen" in guis and "Screen" in guis, "Bildschirme")
    st = child(city, "Stations")
    check(not any("Soon" in get_attrs(s) for s in children(st)), "keine Soon-Stationen mehr")


if __name__ == "__main__":
    test_intervals()
    test_drive()
    test_tables()
    test_checkpoints()
    test_track_geometry()
    if len(sys.argv) > 1:
        test_place(sys.argv[1])
    for f in FAILS:
        print("FEHLER:", f)
    print("OK" if not FAILS else "%d Fehler" % len(FAILS))
    sys.exit(1 if FAILS else 0)
