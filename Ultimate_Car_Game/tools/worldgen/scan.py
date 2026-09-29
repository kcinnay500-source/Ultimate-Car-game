"""Liest einen gebauten Place (rbxlx) und liefert die BaseParts der Stadt (und der Zonen Lobby/Tycoon) als
flache Datensätze. Gemeinsame Grundlage für checks.py und render.py (ohne Roblox)."""
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from worldgen.lib import (CF, BASEPART_CLASSES, child, children, get_attrs, get_prop, name_of, read_cf,
                              read_size, u8_color)
    from worldgen.plots import SLOTS, slot_cf
else:
    from .lib import CF, BASEPART_CLASSES, child, children, get_attrs, get_prop, name_of, read_cf, read_size, u8_color
    from .plots import SLOTS, slot_cf

DEFAULT_PLACE = "/tmp/claude-0/foundation.rbxlx"
MAT = {256: "Plastic", 272: "SmoothPlastic", 288: "Neon", 512: "Wood", 528: "WoodPlanks", 784: "Marble",
       800: "Slate", 816: "Concrete", 832: "Granite", 848: "Brick", 864: "Pebble", 880: "Cobblestone",
       1040: "CorrodedMetal", 1056: "DiamondPlate", 1072: "Foil", 1088: "Metal", 1280: "Grass", 1296: "Sand",
       1312: "Fabric", 1376: "Asphalt", 1568: "Glass"}


class P:
    """Ein BasePart"""
    __slots__ = ("item", "name", "cls", "path", "size", "cf", "color", "transp", "material", "shape",
                 "anchored", "collide", "attrs", "car", "top")

    def corners(self):
        hx, hy, hz = self.size[0] / 2, self.size[1] / 2, self.size[2] / 2
        if self.cls == "WedgePart":
            loc = [(sx * hx, -hy, sz * hz) for sx in (-1, 1) for sz in (-1, 1)] + \
                  [(sx * hx, hy, hz) for sx in (-1, 1)]
        else:
            loc = [(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        return [self.cf.point(v) for v in loc]

    def aabb(self):
        c = self.corners()
        return (min(p[0] for p in c), max(p[0] for p in c), min(p[1] for p in c), max(p[1] for p in c),
                min(p[2] for p in c), max(p[2] for p in c))


def _prop_text(item, name, default=None):
    e = get_prop(item, name)
    return e.text if e is not None and e.text is not None else default


def load(path=DEFAULT_PLACE):
    return ET.parse(path)


def workspace(tree):
    return next(i for i in tree.getroot().findall("Item") if i.get("class") == "Workspace")


def record(item, path, car=False, xf=None):
    p = P()
    p.item = item
    p.name = name_of(item)
    p.cls = item.get("class")
    p.path = path
    p.size = read_size(item)
    p.cf = read_cf(item) if xf is None else xf * read_cf(item)
    p.color = u8_color(_prop_text(item, "Color3uint8", "0"))
    p.transp = float(_prop_text(item, "Transparency", "0"))
    p.material = MAT.get(int(float(_prop_text(item, "Material", "256"))), "?")
    p.shape = int(float(_prop_text(item, "shape", "1"))) if p.cls in ("Part", "SpawnLocation") else 1
    p.anchored = _prop_text(item, "Anchored", "false") == "true"
    p.collide = _prop_text(item, "CanCollide", "true") == "true"
    p.attrs = get_attrs(item)
    p.car = car
    ab = p.aabb()
    p.top = ab[3]
    return p


def walk(item, path="", car=False, xf=None, out=None):
    out = [] if out is None else out
    for c in children(item):
        nm = name_of(c)
        here = path + "." + nm if path else nm
        iscar = car or (c.get("class") == "Model" and "Body" in get_attrs(c))
        if c.get("class") in BASEPART_CLASSES:
            out.append(record(c, here, iscar, xf))
        walk(c, here, iscar, xf, out)
    return out


def city_parts(tree):
    ws = workspace(tree)
    city = child(ws, "City")
    if city is None:
        return None, []
    return city, walk(city, "City")


ZONES = ("Lobby", "Tycoon")


def zone_parts(tree, name):
    """Eine Zone (Workspace.Lobby / Workspace.Tycoon, PHASE4_CONTRACT §1) als (Model, Parts) - wie city_parts."""
    ws = workspace(tree)
    zone = child(ws, name)
    if zone is None:
        return None, []
    return zone, walk(zone, name)


def plot_parts(tree, slots=None):
    """Die getrimmte Werkstatt-Vorlage an allen (oder den gegebenen) Slots, wie W.Create sie pivotiert."""
    ws = workspace(tree)
    wk = child(ws, "Werkstatt")
    out = []
    if wk is None:
        return out
    for slot, house, px, pz, rot in SLOTS:
        if slots and slot not in slots:
            continue
        walk(wk, "Plot%d" % slot, False, slot_cf(px, pz, rot), out)
    return out
