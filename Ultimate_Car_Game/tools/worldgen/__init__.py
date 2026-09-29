"""Welt-Generator: Stadt "Werkstattmeile" (docs/CITY_SPEC.md, docs/MERGE_CONTRACT.md §4) und die Zonen der
Ausbaustufe 4 (docs/PHASE4_CONTRACT.md §1): Lobby-Halle (lobby.py) und Tycoon-Gelände (tycoon.py).

tools/build_place.py ruft apply(tree, new_referent, place) auf dem Basisbaum auf; place ist die PlaceKind:
* "all"        Workspace.City + Workspace.Lobby + Workspace.Tycoon (die Datei für Roblox Studio)
* "openworld"  nur Workspace.City (wie bisher)
* "lobby"      nur Workspace.Lobby
* "tycoon"     nur Workspace.Tycoon
In jedem Place wird die Plot-Vorlage Workspace.Werkstatt getrimmt (§4.1) und bekommt den Part CarSpawn - World.lua
klont sie in jedem Place (Vertrag §1, "Grundstücke").
apply() liefert eine Zusammenfassung (Parts und Lichter je Ordner/Zone) als String.
"""
import importlib

from . import contract, ground_roads, lobby, plots, tycoon, vehicles
from .lib import Lib, child, children, is_basepart, name_of
from .districts import ORDER as DISTRICTS

TOP = ["Ground", "Roads", "Lights", "Districts", "Stations", "Arrivals", "Animated", "PlotSlots"]
PART_BUDGET = 12000
LIGHT_BUDGET = 120
PLACES = ("all", "lobby", "openworld", "tycoon")
ZONE_MODELS = {"lobby": "Lobby", "openworld": "City", "tycoon": "Tycoon"}


def _workspace(root):
    for it in root.findall("Item"):
        if it.get("class") == "Workspace":
            return it
    raise SystemExit("Workspace fehlt im Basisplace")


def zones_for(place):
    """Welche Zonen-Modelle ein Place enthält (Reihenfolge = Baureihenfolge)."""
    if place not in PLACES:
        raise SystemExit("Unbekannter Place '%s' (erlaubt: %s)" % (place, ", ".join(PLACES)))
    return ["openworld", "lobby", "tycoon"] if place == "all" else [place]


def apply(tree, new_referent, place="all"):
    root = tree.getroot()
    ws = _workspace(root)
    for nm in ZONE_MODELS.values():
        old = child(ws, nm)
        if old is not None:
            ws.remove(old)
    lib = Lib(tree, new_referent)
    wanted = zones_for(place)
    city = None
    plot_log = []
    if "openworld" in wanted:
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
    else:
        # Plot-Vorlage in jedem Place gleich: Trimm + CarSpawn (ohne Stadt)
        wk = child(ws, "Werkstatt")
        if wk is not None:
            with lib.section("Plot-Vorlage (Trimm)"):
                plot_log = plots.trim_template(wk, lib)
            with lib.section("Fahrzeuge (unsichtbar)"):
                vehicles.build_plot_spawn(wk, lib)
    zones = []
    if "lobby" in wanted:
        zones.append(lobby.build(ws, lib, tree))
    if "tycoon" in wanted:
        zones.append(tycoon.build(ws, lib, tree))
    return summary(city, zones, lib, plot_log, place)


def count(item):
    parts = lights = cars = 0
    for it in item.iter("Item"):
        c = it.get("class")
        if is_basepart(it):
            parts += 1
        elif c in ("PointLight", "SpotLight", "SurfaceLight"):
            lights += 1
    return parts, lights


def summary(city, zones, lib, plot_log, place="all"):
    lines = ["PlaceKind %s" % place]
    if city is not None:
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
        lines.append("City: %d Parts (Budget %d; darin Verkehr Lite-Autos + Bus %d), %d Lichter (Budget %d)"
                     % (total_p, PART_BUDGET, traffic, total_l, LIGHT_BUDGET))
        lines.append("  Ordner Parts/Lichter: " + ", ".join(rows))
    for z in zones:
        nm = name_of(z)
        budget = lobby.LOBBY_BUDGET if nm == "Lobby" else tycoon.TYCOON_BUDGET
        p, l = count(z)
        rows = ["%s %d/%d" % (name_of(it), *count(it)) for it in children(z)]
        lines.append("%s: %d Parts (Budget %d), %d Lichter (Budget %d)" % (nm, p, budget[0], l, budget[1]))
        lines.append("  Ordner Parts/Lichter: " + ", ".join(rows))
    lines.append("  Abschnitte: " + "; ".join(lib.budget_report()))
    if plot_log:
        lines.append("  Plot-Vorlage: " + "; ".join(plot_log))
    return "\n".join(lines)
