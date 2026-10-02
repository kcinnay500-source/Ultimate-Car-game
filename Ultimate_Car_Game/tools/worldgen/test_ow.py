#!/usr/bin/env python3
"""Selbsttest für die Open-World-Welt (plots.OW_ANCHORS, ow_buildings, districts/kiesplatz, contract) ohne Roblox.

  python3 tools/worldgen/test_ow.py                 reine Tabellen-/Geometrie-Tests
  python3 tools/worldgen/test_ow.py <place.rbxlx>   zusätzlich: gebauter Place (checks.ow_checks, mission_checks,
                                                    kiesplatz_checks müssen fehlerfrei sein)
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from worldgen import contract, ow_buildings as OB  # noqa: E402
from worldgen.districts import ORDER, kiesplatz  # noqa: E402
from worldgen.plots import (OW_ANCHORS, OW_TYPES, RECT, SLOTS, ow_footprint_local, ow_footprint_world,  # noqa: E402
                            loc2world)

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)


def _disjoint(a, b):
    return a[1] <= b[0] or b[1] <= a[0] or a[3] <= b[2] or b[3] <= a[2]


def test_anchors():
    # Hallen mit allen 4 Anbauten (plotlokal), Vorfeld, Parkplatz, CarSpawn (aus der getrimmten Vorlage)
    blocked = {"Halle+Anbauten": (-74.5, 34.4, -33.4, 33.4), "Vorfeld": (-74.5, 56, 33, 45),
               "Parkplatz": (-54, 54, 52, 78), "Einfahrt": (-30, 30, 45, 84), "Rolltor-Zufahrt": (-53, -33, 45, 84)}
    fps = {}
    for typ in OW_TYPES:
        x, z, yaw, w, d = OW_ANCHORS[typ]
        fp = ow_footprint_local(typ)
        fps[typ] = fp
        check(fp[0] >= RECT[0] and fp[1] <= RECT[1] and fp[2] >= RECT[2] and fp[3] <= RECT[3],
              "%s: Grundfläche %s außerhalb der Plot-Fläche" % (typ, fp))
        check(abs((fp[1] - fp[0]) * (fp[3] - fp[2]) - w * d) < 1e-6, "%s: Grundfläche %gx%g erwartet" % (typ, w, d))
        for nm, b in blocked.items():
            check(_disjoint(fp, b), "%s: Grundfläche %s überschneidet %s" % (typ, fp, nm))
    for a in OW_TYPES:
        for b in OW_TYPES:
            if a < b:
                check(_disjoint(fps[a], fps[b]), "Grundflächen %s / %s überschneiden sich" % (a, b))
    # Welt: Rot 0 und Rot 180 spiegeln, bleiben in der Plot-Fläche aller 8 Slots
    for slot, house, px, pz, rot in SLOTS:
        a = loc2world(px, pz, rot, RECT[0], RECT[2])
        b = loc2world(px, pz, rot, RECT[1], RECT[3])
        plot = (min(a[0], b[0]), max(a[0], b[0]), min(a[1], b[1]), max(a[1], b[1]))
        for typ in OW_TYPES:
            f = ow_footprint_world(px, pz, rot, typ)
            check(f[0] >= plot[0] - 1e-6 and f[1] <= plot[1] + 1e-6 and f[2] >= plot[2] - 1e-6 and
                  f[3] <= plot[3] + 1e-6, "Slot %d %s: Welt-Grundfläche %s außerhalb %s" % (slot, typ, f, plot))


def test_templates():
    names = OB.template_names()
    check(names[0] == "baustelle" and len(names) == 13, "13 Vorlagen erwartet: %s" % names)
    for typ in OW_TYPES:
        for s in range(1, 5):
            check("%s_%d" % (typ, s) in names, "Vorlage %s_%d fehlt" % (typ, s))
            check(OB.footprint("%s_%d" % (typ, s)) == (OW_ANCHORS[typ][3], OW_ANCHORS[typ][4]),
                  "%s: Grundfläche der Vorlage passt nicht zum Anker" % typ)
    w, d = OB.footprint("baustelle")
    check(all(w <= OW_ANCHORS[t][3] and d <= OW_ANCHORS[t][4] for t in OW_TYPES),
          "Baustelle muss auf jeden Anker passen")
    check(OB.BUDGET == (250, 4), "Budget 250 Parts / 4 Lichter")
    check(OB.MOVING <= OB.ANIM_KINDS | OB.TYCOON_ANIM_KINDS, "bewegte Anim-Arten müssen bekannt sein")


def test_kiesplatz():
    check("kiesplatz" in ORDER and ORDER[-1] == "kiesplatz", "kiesplatz muss als letzter District gebaut werden")
    st = contract.STATIONS.get("kiesplatz")
    check(st is not None and st[0] == "story" and st[1].startswith("Kiesplatz"), "Station kiesplatz (story)")
    ar = contract.ARRIVALS.get("kiesplatz")
    check(ar is not None and ar[1] == kiesplatz.Y_GRAVEL, "Ankunft kiesplatz auf Kieshöhe")
    x0, x1, z0, z1 = kiesplatz.LOT
    check(ar is not None and x0 < ar[0] < x1 and z0 < ar[2] < z1, "Ankunft liegt auf dem Platz")
    hx0, hx1, hz0, hz1 = kiesplatz.HUT
    check(st is not None and abs(st[2][0] - hx1) < 3 and hz0 < st[2][2] < hz1, "Station am Verkaufsfenster")
    # Stadtgrenzen (CITY_BOUNDS Z ±320 gilt für Zonen; der Platz liegt innerhalb der Hecke Z < 470, X < 590)
    check(x1 < 590 and z1 < 470, "Kiesplatz innerhalb der Hecke")
    check(kiesplatz.DRIVE[2] == 260.0 and kiesplatz.DRIVE[3] == kiesplatz.LOT[2], "Zufahrt vom Tankstellen-Gelände")
    for sx, sz in kiesplatz.SPOTS:
        check(x0 + 5 < sx < x1 - 5 and z0 + 9 < sz < z1 - 9, "Spot (%g, %g) liegt auf dem Kies" % (sx, sz))
    for n, ((sx, sz, sw, sd), (ex, ez, ew, ed)) in kiesplatz.ROUTES.items():
        dist = math.hypot(ex - sx, ez - sz)
        check(300 <= dist <= 600, "Lieferroute %d: %.0f Studs (300..600)" % (n, dist))
    check(sorted(kiesplatz.ROUTES) == [1, 2, 3], "Lieferrouten 1..3")


def test_place(path):
    from worldgen import checks, scan
    tree = scan.load(path)
    city, parts = scan.city_parts(tree)
    errors, warns, info = [], [], []
    checks.ow_checks(tree, parts, errors, warns, info, False)
    if city is not None:
        checks.mission_checks(city, parts, errors, warns, info)
        checks.kiesplatz_checks(city, errors, warns, info)
    for e in errors:
        check(False, "Place: " + e.strip())
    for line in info:
        print("  " + line)


def main(argv):
    test_anchors()
    test_templates()
    test_kiesplatz()
    for a in argv:
        if a.endswith(".rbxlx"):
            test_place(a)
    if FAILS:
        for f in FAILS:
            print("FEHLER:", f)
        print("%d Fehler" % len(FAILS))
        return 1
    print("OK (test_ow)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
