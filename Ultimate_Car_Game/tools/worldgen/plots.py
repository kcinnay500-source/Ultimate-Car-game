"""Werkstatt-Grundstücke: Vorlagen-Trimm (CITY_SPEC §4.1) und Stadt-Deko je Slot (§4.3).

Workspace.Werkstatt ist die Plot-Vorlage (World.lua klont sie beim Laden nach ServerStorage.PlotTemplate).
Der Trimm entfernt alles, was in der Stadt stören würde, und behält jeden Anker, den Code referenziert
(docs/analysis_2.4.0/world.md, "Script-referenced names").
"""
import json
import math
from pathlib import Path

from .lib import (CF, AMBER, APRON, SLATE, STEEL, TEAL, WHITE, aabb, child, children, get_prop, is_basepart,
                  name_of, read_cf, read_size, set_attrs, set_scalar, write_cf, write_size)

HERE = Path(__file__).resolve().parent

# Slot, Hausnummer, Pivot x, z, rot (§4.2) - Füllreihenfolge = Listenreihenfolge
SLOTS = [
    (1, 5, 262, -109, 0),
    (2, 4, -262, 109, 180),
    (3, 3, -234, -109, 0),
    (4, 6, 234, 109, 180),
    (5, 7, 412, -109, 0),
    (6, 2, -412, 109, 180),
    (7, 1, -384, -109, 0),
    (8, 8, 384, 109, 180),
]
RECT = (-84, 56, -44, 84)          # reservierte plotlokale Fläche (x0,x1,z0,z1)
GRAVEL = (110, 104, 96)

# Code-referenzierte Anker, die der Trimm nie entfernen darf
KEEP_TOP = {"Root", "Architecture", "Details", "Bays", "ActiveCars", "Extensions", "EndWall", "ExpansionPoint",
            "Reception", "Office", "RollerDoor", "UpgradeBench", "Start", "YardActivities", "CreditShopStation",
            "Stations", "PartsArea", "EquipmentPositions", "Equipment"}
REMOVE_DETAILS = {"NeighbourBuilding", "NeighbourWindow", "GardenBed", "GardenCurb", "GrassBlade", "FencePost",
                  "FenceRail", "Road", "RoadMark", "LampBase", "LampPost", "LampArm", "YardLamp", "Birch",
                  "WorkshopPine", "LeafSpray", "Bollard", "BollardBand", "BenchLeg", "BenchSeat", "BenchBack",
                  "DrainGrate", "GrateSlot"}


def loc2world(px, pz, rot, lx, lz):
    return (px + lx, pz + lz) if rot == 0 else (px - lx, pz - lz)


def slot_cf(px, pz, rot):
    return CF.at(px, 0, pz, rot)


def write_slots_json():
    data = [{"slot": s, "house": h, "x": px, "z": pz, "rot": rot} for s, h, px, pz, rot in SLOTS]
    (HERE / "plot_slots.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return data


# ---------------------------------------------------------------- Vorlagen-Trimm (§4.1)
def _item_box(item):
    """AABB eines Parts oder Models (alle BaseParts darin)"""
    boxes = [aabb(it) for it in item.iter("Item") if is_basepart(it)]
    if not boxes:
        return None
    return (min(b[0] for b in boxes), max(b[1] for b in boxes), min(b[2] for b in boxes),
            max(b[3] for b in boxes), min(b[4] for b in boxes), max(b[5] for b in boxes))


def _inside(box, tol=0.6):
    x0, x1, z0, z1 = RECT
    return box[0] >= x0 - tol and box[1] <= x1 + tol and box[4] >= z0 - tol and box[5] <= z1 + tol


def _transform_item(item, T):
    for it in item.iter("Item"):
        if is_basepart(it):
            write_cf(it, T * read_cf(it))


def trim_template(werkstatt, lib):
    log = []
    arch = child(werkstatt, "Architecture")
    details = child(werkstatt, "Details")
    yard_acts = child(werkstatt, "YardActivities")
    # 1) Hofaktivitäten samt Zubehör verschieben und die Schilder nach +X drehen
    moves = {"recycle": (-72, 0.5, 60), "pressure": (-72, 1.5, 76)}
    for key, (nx, ny, nz) in moves.items():
        act = child(yard_acts, key)
        c = read_cf(act).p
        group = [act]
        for it in children(details):
            if is_basepart(it) or it.get("class") == "Model":
                b = _item_box(it)
                if b is None:
                    continue
                mx, mz = (b[0] + b[1]) / 2, (b[4] + b[5]) / 2
                if math.hypot(mx - c[0], mz - c[2]) < 7.5 and name_of(it) not in REMOVE_DETAILS:
                    group.append(it)
        T = CF(nx, ny, nz) * CF.yaw(90) * CF(-c[0], -c[1], -c[2])
        for it in group:
            _transform_item(it, T)
            if it is not act:
                set_attrs(it, {"YardGroup": key})
        log.append("%s + %d Teile -> (%g,%g,%g)" % (key, len(group) - 1, nx, ny, nz))
    # 2) Entfernen: Nachbarhäuser, Beete, Zäune, Straße, Laternen, Bäume, Grenzwände ...
    removed = 0
    for it in list(children(arch)):
        if name_of(it) == "Boundary":
            arch.remove(it)
            removed += 1
    for it in list(children(details)):
        nm = name_of(it)
        box = _item_box(it)
        if nm in REMOVE_DETAILS or box is None or not _inside(box):
            details.remove(it)
            removed += it_count(it)
    # 3) Hof auf die reservierte Fläche verkleinern, Vorfeld bis X 56 kürzen
    yard = child(arch, "Yard")
    write_size(yard, (140, 1, 128))
    write_cf(yard, CF(-14, -1.5, 20))
    apron = child(arch, "EntranceApron")
    s = read_size(apron)
    p = read_cf(apron).p
    x0, x1 = p[0] - s[0] / 2, min(p[0] + s[0] / 2, RECT[1])
    write_size(apron, (x1 - x0, s[1], s[2]))
    write_cf(apron, CF((x0 + x1) / 2, p[1], p[2]))
    # 4) Plot-Spawn aus (CitySpawn ist der einzige Spawn)
    start = child(werkstatt, "Start")
    set_scalar(start, "bool", "Enabled", "false")
    # 5) Kontrolle: alles außer Wurzel-Ankern liegt in der Fläche
    outside = []
    for it in children(werkstatt):
        for sub in it.iter("Item"):
            if is_basepart(sub):
                b = aabb(sub)
                if not _inside(b, 0.6):
                    outside.append(name_of(sub))
    missing = [k for k in KEEP_TOP if child(werkstatt, k) is None]
    log.append("%d Parts entfernt" % removed)
    if outside:
        log.append("außerhalb der Fläche: " + ", ".join(sorted(set(outside))))
    if missing:
        raise SystemExit("Plot-Vorlage: Anker fehlen: " + ", ".join(missing))
    return log


def it_count(item):
    return sum(1 for x in item.iter("Item") if is_basepart(x))


# ---------------------------------------------------------------- Deko je Slot (§4.3)
def build_slots(city, lib):
    root = lib.folder(city, "PlotSlots")
    lamps_done = []
    for slot, house, px, pz, rot in SLOTS:
        sf = lib.model(root, "Slot_%d" % slot, attrs={"Slot": slot, "House": house, "PivotX": px, "PivotZ": pz,
                                                     "Rot": rot})
        side = -1 if pz < 0 else 1          # Meile liegt bei side*(-1) ... Nordseite: side -1
        yaw = rot                            # +Z des Pylons zeigt zur Meile
        # Hausnummer-Pylon am Empfangs-Türachse
        ex, _ = loc2world(px, pz, rot, -64, 0)
        pzw = side * 21.4
        with lib.section("Plots: Pylonen"):
            pyl = lib.model(sf, "Pylon", attrs={"Anim": "pylon", "Slot": slot, "House": house, "Owner": ""})
            body = lib.part(pyl, "Body", (4.5, 12, 1.2), CF.at(ex, 5.5, pzw, yaw), SLATE, "Metal")
            lib.set_primary(pyl, body)
            gui = lib.surface_text(body, None, face="Back", name="StreetGui", canvas=(180, 480))
            lib.text_label(gui, str(house), AMBER, "GothamBlack", "Number", None, (0.9, 0.5), (0.05, 0.04))
            lib.text_label(gui, "FREI", WHITE, "GothamBold", "Owner", None, (0.9, 0.16), (0.05, 0.58))
            lib.text_label(gui, "WERKSTATTMEILE", TEAL, "GothamBold", "Street", None, (0.9, 0.08), (0.05, 0.82))
            gui2 = lib.surface_text(body, None, face="Front", name="PlotGui", canvas=(180, 480))
            lib.text_label(gui2, "FREI – Werkstatt Nr. %d" % house, AMBER, "GothamBold", "Welcome", None,
                           (0.9, 0.4), (0.05, 0.3))
            cap = lib.part(pyl, "Cap", (4.7, 0.5, 1.4), CF.at(ex, 11.75, pzw, yaw), AMBER, "Neon", deco=True)
            set_attrs(cap, {"FreeColor": _c3(AMBER), "OwnedColor": _c3(TEAL)})
            lib.part(pyl, "Plinth", (5.3, 0.6, 2.0), CF.at(ex, -0.2, pzw, yaw), STEEL, "Metal")
            # Plinth -0.5..0.1 steht auf dem Gehweg; Body beginnt bei -0.5 (steckt im Sockel)
        # Freies Grundstück: Schotter, Schild, 6 Leitkegel
        with lib.section("Plots: Freie Grundstücke"):
            vac = lib.model(sf, "Vacant", attrs={"Slot": slot})
            fx0, fz0 = loc2world(px, pz, rot, RECT[0], RECT[2])
            fx1, fz1 = loc2world(px, pz, rot, RECT[1], RECT[3])
            x0, x1, z0, z1 = min(fx0, fx1), max(fx0, fx1), min(fz0, fz1), max(fz0, fz1)
            lib.box(vac, "Schotter", x0, x1, -1.3, -1.0, z0, z1, GRAVEL, "Pebble")
            bx, bz = loc2world(px, pz, rot, 0, 66)
            lib.sign(vac, "FREIES GRUNDSTÜCK", (16, 5), CF.at(bx, 4.5, bz, yaw), AMBER, SLATE, name="Schild",
                     sub="Werkstatt Nr. %d · bald eröffnet" % house)
            for dx in (-6.5, 6.5):
                wx, wz = loc2world(px, pz, rot, dx, 66 - 0.36)
                lib.box(vac, "Schildpfosten", wx - 0.25, wx + 0.25, -1.0, 6.6, wz - 0.25, wz + 0.25, STEEL, "Metal")
            for k, (lx, lz) in enumerate(((-40, 72), (-20, 76), (0, 78), (20, 76), (40, 72), (-60, 70))):
                wx, wz = loc2world(px, pz, rot, lx, lz)
                lib.cone(vac, wx, -1.0, wz)
        # Lot: Straßenbaum am Bordstein (lokal X -44)
        with lib.section("Plots: Straßenbäume"):
            lot = lib.model(sf, "Lot", attrs={"Slot": slot})
            tx, _ = loc2world(px, pz, rot, -44, 0)
            lib.box(lot, "Baumscheibe", tx - 1.5, tx + 1.5, -0.5, -0.45, side * 16 - 1.5, side * 16 + 1.5, (70, 60, 50),
                    "Pebble", deco=True)
            lib.tree_lite(lot, tx, -0.45, side * 16, scale=1.1, seed=slot, name="Strassenbaum")
    return root


def _c3(rgb):
    from .lib import Color3
    return Color3(*rgb)


def build(city, lib, tree, workspace):
    from .lib import child as _child
    wk = _child(workspace, "Werkstatt")
    log = []
    if wk is not None:
        with lib.section("Plot-Vorlage (Trimm)"):
            log = trim_template(wk, lib)
    write_slots_json()
    build_slots(city, lib)
    return log
