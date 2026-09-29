"""Stadt-Generator "Werkstattmeile" (docs/CITY_SPEC.md, docs/MERGE_CONTRACT.md §4).

tools/build_place.py ruft apply(tree, new_referent) auf dem Basisbaum auf:
* baut Workspace.City (Model) mit Ground, Roads, Lights, Districts, Stations, Arrivals, Animated,
  CitySpawn, PlotSlots, CarSpawns und Track (vehicles.py),
* trimmt die Plot-Vorlage Workspace.Werkstatt (§4.1) und setzt dort den Part CarSpawn,
* liefert eine Zusammenfassung (Parts und Lichter je Ordner) als String.

Einzeln testen: python3 -c "import sys; sys.path.insert(0,'tools'); ..." - einfacher über build_place.py.
"""
import importlib

from . import contract, ground_roads, plots, vehicles
from .lib import Lib, child, children, is_basepart, name_of
from .districts import ORDER as DISTRICTS

TOP = ["Ground", "Roads", "Lights", "Districts", "Stations", "Arrivals", "Animated", "PlotSlots"]
PART_BUDGET = 12000
LIGHT_BUDGET = 120


def _workspace(root):
    for it in root.findall("Item"):
        if it.get("class") == "Workspace":
            return it
    raise SystemExit("Workspace fehlt im Basisplace")


def apply(tree, new_referent):
    root = tree.getroot()
    ws = _workspace(root)
    old = child(ws, "City")
    if old is not None:
        ws.remove(old)
    lib = Lib(tree, new_referent)
    city = lib.model(ws, "City", attrs={"Spec": "Werkstattmeile", "Version": "3.0"})
    for nm in TOP:
        lib.folder(city, nm)
    ground_roads.build(city, lib, tree)
    plot_log = plots.build(city, lib, tree, ws)
    contract.build(city, lib, tree)
    for mod_name in DISTRICTS:
        mod = importlib.import_module(".districts." + mod_name, __name__)
        mod.build(city, lib, tree)
    vehicles.build(city, lib, tree, ws)
    return summary(city, lib, plot_log)


def count(item):
    parts = lights = cars = 0
    for it in item.iter("Item"):
        c = it.get("class")
        if is_basepart(it):
            parts += 1
        elif c in ("PointLight", "SpotLight", "SurfaceLight"):
            lights += 1
    return parts, lights


def summary(city, lib, plot_log):
    total_p, total_l = count(city)
    traffic = 0
    anim = child(city, "Animated")
    verkehr = child(anim, "Verkehr") if anim is not None else None
    if verkehr is not None:
        traffic = count(verkehr)[0]
    rows = []
    for it in children(city):
        p, l = count(it)
        rows.append("%s %d/%d" % (name_of(it), p, l))
    lines = ["City: %d Parts (Budget %d; darin Verkehr Lite-Autos + Bus %d), %d Lichter (Budget %d)"
             % (total_p, PART_BUDGET, traffic, total_l, LIGHT_BUDGET),
             "  Ordner Parts/Lichter: " + ", ".join(rows),
             "  Abschnitte: " + "; ".join(lib.budget_report())]
    if plot_log:
        lines.append("  Plot-Vorlage: " + "; ".join(plot_log))
    return "\n".join(lines)
