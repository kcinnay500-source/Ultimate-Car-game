#!/usr/bin/env python3
"""Baut den Roblox-Place aus dem 2.4.0-Basisplace und den Skripten in src/.

Grundidee
---------
* ``base/Ultimate_Car_Game_2.4.0.rbxlx`` liefert die gesamte Welt (Werkstatt, Autos, Geräte, Licht).
* Jedes Skript im Place wird aus ``src/`` befüllt. Bestehende Skripte behalten ihre Position im
  Baum (dadurch ergibt ein unveränderter ``src/garage`` einen byte-identischen Place).
* Neue Skripte (``src/mini``) werden in ihre Zielordner eingefügt.
* Welt-Erweiterungen kommen aus ``tools/worldgen`` (falls vorhanden) und werden als zusätzliche
  Items angehängt bzw. als Patches auf den Basisbaum angewendet.

Zuordnung (wie in default.project.json):
  src/garage/shared/*.lua          -> ReplicatedStorage.GarageShared
  src/garage/server/*.lua          -> ServerScriptService.Garage      (*.server.lua = Script)
  src/garage/client/*.lua          -> StarterPlayer.StarterPlayerScripts (*.client.lua = LocalScript)
  src/mini/shared/*.lua            -> ReplicatedStorage.GarageShared.Mini
  src/mini/server/*.lua            -> ServerScriptService.Garage.Mini
  src/mini/client/*.lua            -> StarterPlayer.StarterPlayerScripts.Mini

Places (Ausbaustufe 4, docs/PHASE4_CONTRACT.md §1): ``--place all|lobby|openworld|tycoon`` (ohne Angabe ``all``).
Der Builder setzt das Attribut ``PlaceKind`` auf ``ReplicatedStorage.GarageShared`` und reicht den Place an
``worldgen.apply(tree, new_referent, place)`` weiter (all = Stadt + Lobby + Tycoon, sonst nur die eine Zone; die
Plot-Vorlage Workspace.Werkstatt und alle Skripte sind in jedem Place enthalten).

Aufrufe:
  python tools/build_place.py Ultimate_Car_Game.rbxlx        Place bauen (PlaceKind all)
  python tools/build_place.py --place lobby Lobby.rbxlx      nur die Lobby-Halle (PlaceKind lobby)
  python tools/build_place.py --extract                      Skripte aus dem Basisplace nach src/garage schreiben
  python tools/build_place.py --roundtrip                    Prüfen: Basis + src/garage == Basis (bis auf Skript-Quelltexte)
"""
import csv
import hashlib
import importlib.util
import itertools
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
BASE = ROOT / "base" / "Ultimate_Car_Game_2.4.0.rbxlx"
SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")

# (Quellordner, Zielpfad im Place)
MAPPING = [
    ("garage/shared", ("ReplicatedStorage", "GarageShared")),
    ("garage/server", ("ServerScriptService", "Garage")),
    ("garage/client", ("StarterPlayer", "StarterPlayerScripts")),
    ("mini/shared", ("ReplicatedStorage", "GarageShared", "Mini")),
    ("mini/server", ("ServerScriptService", "Garage", "Mini")),
    ("mini/client", ("StarterPlayer", "StarterPlayerScripts", "Mini")),
]

_new_ref = itertools.count(1)


def new_referent():
    return "RBXN%07d" % next(_new_ref)


# ---------------------------------------------------------------- XML-Hilfen
def props_of(item):
    return item.find("Properties")


def prop(item, name):
    p = props_of(item)
    if p is None:
        return None
    for c in p:
        if c.get("name") == name:
            return c
    return None


def name_of(item):
    n = prop(item, "Name")
    return n.text if n is not None else None


def child(item, name):
    for c in item.findall("Item"):
        if name_of(c) == name:
            return c
    return None


def find_path(root, path):
    """path = (Dienst, Kind, Kind, ...); Dienste werden über den Klassennamen gefunden."""
    node = None
    for it in root.findall("Item"):
        if it.get("class") == path[0]:
            node = it
            break
    if node is None:
        return None
    for part in path[1:]:
        node = child(node, part)
        if node is None:
            return None
    return node


def make_item(cls, name, extra_props=()):
    item = ET.Element("Item", {"class": cls, "referent": new_referent()})
    props = ET.SubElement(item, "Properties")
    n = ET.SubElement(props, "string", {"name": "Name"})
    n.text = name
    for tag, pname, value in extra_props:
        e = ET.SubElement(props, tag, {"name": pname})
        e.text = value
    return item


def ensure_folder(root, path):
    node = find_path(root, path[:1])
    if node is None:
        raise SystemExit(f"Dienst {path[0]} fehlt im Basisplace")
    for part in path[1:]:
        nxt = child(node, part)
        if nxt is None:
            nxt = make_item("Folder", part)
            node.append(nxt)
        node = nxt
    return node


def classify(path: Path):
    name = path.name
    if name.endswith(".server.lua"):
        return "Script", name[: -len(".server.lua")]
    if name.endswith(".client.lua"):
        return "LocalScript", name[: -len(".client.lua")]
    return "ModuleScript", name[: -len(".lua")]


def script_filename(cls, name):
    if cls == "Script":
        return name + ".server.lua"
    if cls == "LocalScript":
        return name + ".client.lua"
    return name + ".lua"


def read_source(path: Path):
    # newline="" erhält Zeilenenden exakt
    with path.open("r", encoding="utf-8", newline="") as f:
        return f.read()


def place_scripts(root):
    """Alle Skripte im Baum: {(Pfad...): Item}"""
    out = {}

    def walk(item, path):
        here = path + (name_of(item) if item.get("class") not in _SERVICE_CLASSES else item.get("class"),)
        if item.get("class") in SCRIPT_CLASSES:
            out[here] = item
        for c in item.findall("Item"):
            walk(c, here)

    for it in root.findall("Item"):
        walk(it, ())
    return out


_SERVICE_CLASSES = {"Workspace", "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "ServerStorage", "Lighting", "StarterGui", "SoundService"}


def src_files():
    """{(Zielpfad..., Name): (Klasse, Datei)} für alle Dateien in src/"""
    out = {}
    for rel, target in MAPPING:
        folder = SRC / rel
        if not folder.exists():
            continue
        for f in sorted(folder.glob("*.lua")):
            cls, name = classify(f)
            key = target + (name,)
            if key in out:
                raise SystemExit(f"Doppeltes Skript {'.'.join(key)}")
            out[key] = (cls, f)
    return out


# ---------------------------------------------------------------- Aufbau
def load_base():
    return ET.parse(BASE)


def apply_scripts(tree):
    root = tree.getroot()
    existing = place_scripts(root)
    files = src_files()
    for key, item in existing.items():
        if key not in files:
            raise SystemExit(f"Skript {'.'.join(key)} aus dem Basisplace hat keine Datei in src/ (würde verloren gehen)")
        cls, f = files[key]
        if cls != item.get("class"):
            raise SystemExit(f"{'.'.join(key)}: Klasse {item.get('class')} im Basisplace, {cls} in src/")
        prop(item, "Source").text = read_source(f)
    added = 0
    for key, (cls, f) in files.items():
        if key in existing:
            continue
        parent = ensure_folder(root, key[:-1])
        extra = [("ProtectedString", "Source", read_source(f))]
        if cls != "ModuleScript":
            extra.insert(0, ("bool", "Disabled", "false"))
        parent.append(make_item(cls, key[-1], extra))
        added += 1
    return len(existing), added


PLACES = ("all", "lobby", "openworld", "tycoon")


def load_worldgen():
    gen = ROOT / "tools" / "worldgen" / "__init__.py"
    if not gen.exists():
        return None
    mod = sys.modules.get("worldgen")
    if mod is not None and getattr(mod, "__file__", None) == str(gen):
        return mod
    spec = importlib.util.spec_from_file_location("worldgen", gen, submodule_search_locations=[str(gen.parent)])
    mod = importlib.util.module_from_spec(spec)
    sys.modules["worldgen"] = mod
    spec.loader.exec_module(mod)
    return mod


def apply_worldgen(tree, place="all"):
    mod = load_worldgen()
    if mod is None:
        return None
    return mod.apply(tree, new_referent, place)


def apply_place_kind(tree, place="all"):
    """Attribut PlaceKind (string) auf ReplicatedStorage.GarageShared (Vertrag §1); die Skripte lesen es mit
    GarageShared:GetAttribute("PlaceKind"). Attribute liegen serialisiert in AttributesSerialize (worldgen.lib)."""
    if place not in PLACES:
        raise SystemExit(f"Unbekannter Place '{place}' (erlaubt: {', '.join(PLACES)})")
    shared = find_path(tree.getroot(), ("ReplicatedStorage", "GarageShared"))
    if shared is None:
        raise SystemExit("ReplicatedStorage.GarageShared fehlt im Basisplace")
    mod = load_worldgen()
    if mod is None:
        raise SystemExit("tools/worldgen fehlt (wird für das Attribut PlaceKind gebraucht)")
    mod.lib.set_attrs(shared, {"PlaceKind": place})
    return place


def build_tree(place="all"):
    """Basis + Skripte + Welt + PlaceKind - genau der Baum, den cmd_build schreibt (auch für validate.py)."""
    tree = load_base()
    replaced, added = apply_scripts(tree)
    world = apply_worldgen(tree, place)
    apply_place_kind(tree, place)
    return tree, replaced, added, world


def write(tree, out: Path):
    tree.write(out, encoding="utf-8", xml_declaration=True)


def export_locale_csv():
    """Exportiert die deutschen Texte (Mini-Locale) als Roblox-Lokalisierungstabelle."""
    path = SRC / "mini" / "shared" / "MiniLocale.lua"
    if not path.exists():
        return None, 0
    text = path.read_text(encoding="utf-8")
    if "Locale.Strings = {" not in text:
        return None, 0
    block = text[text.index("Locale.Strings = {"):]
    block = block[: block.index("\n}")]
    rows = re.findall(r'^\t([a-z_]+) = "((?:[^"\\]|\\.)*)",$', block, re.M)
    out = ROOT / "localization" / "Locale_de.csv"
    out.parent.mkdir(exist_ok=True)
    with out.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Key", "Source", "Context", "Example", "de"])
        for key, value in rows:
            w.writerow([key, value, "", "", value])
    return out, len(rows)


def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------- Befehle
def cmd_extract():
    tree = load_base()
    scripts = place_scripts(tree.getroot())
    by_target = {target: rel for rel, target in MAPPING}
    for key, item in scripts.items():
        rel = by_target.get(key[:-1])
        if rel is None:
            raise SystemExit(f"Keine Zuordnung für {'.'.join(key)}")
        f = SRC / rel / script_filename(item.get("class"), key[-1])
        f.parent.mkdir(parents=True, exist_ok=True)
        with f.open("w", encoding="utf-8", newline="") as h:
            h.write(prop(item, "Source").text or "")
        print(f"  {'.'.join(key)} -> {f.relative_to(ROOT)}")
    print(f"{len(scripts)} Skripte extrahiert")


def _without_sources(root):
    """Serialisiert den Baum mit geleerten Skript-Quelltexten (für den Vergleich "nur Skripte geändert")."""
    for item in place_scripts(root).values():
        prop(item, "Source").text = ""
    return ET.tostring(root, encoding="utf-8")


def cmd_roundtrip():
    """Basis + src/garage (ohne Mini, ohne Welt) mit der Basis vergleichen.

    Solange src/garage unverändert ist, muss das Ergebnis byte-identisch sein. Seit dem 3.0-Merge ändert
    src/garage einzelne Skripte (Kommentar "-- 3.0:"); dann gilt: dieselben Skripte an denselben Stellen,
    und außer den Quelltexten ist der Place byte-identisch ("nur Skripte geändert")."""
    tree = load_base()
    root = tree.getroot()
    existing = place_scripts(root)
    files = src_files()
    missing = [".".join(k) for k in existing if k not in files]
    if missing:
        print("Roundtrip WEICHT AB: Skripte ohne Datei in src/: " + ", ".join(missing))
        return False
    changed = []
    for key, item in existing.items():
        cls, f = files[key]
        if cls != item.get("class"):
            print(f"Roundtrip WEICHT AB: {'.'.join(key)} ist {item.get('class')} im Basisplace, {cls} in src/")
            return False
        source = read_source(f)
        if (prop(item, "Source").text or "") != source:
            changed.append(".".join(key))
        prop(item, "Source").text = source
    out = ROOT / "base" / ".roundtrip.rbxlx"
    write(tree, out)
    same = out.read_bytes() == BASE.read_bytes()
    out.unlink()
    if same:
        print("Roundtrip byte-identisch")
        return True
    if _without_sources(root) == _without_sources(ET.parse(BASE).getroot()):
        print(f"Roundtrip: nur Skripte geändert ({len(changed)}: {', '.join(changed)})")
        return True
    print("Roundtrip WEICHT AB: außer den Skripten hat sich der Place geändert")
    return False


def cmd_build(out: Path, place="all"):
    tree, replaced, added, world = build_tree(place)
    write(tree, out)
    print(f"Place gebaut: {out.name} (PlaceKind {place}, {replaced} Basisskripte aus src/, {added} neue Skripte)")
    if world:
        print(f"Welt: {world}")
    csv_path, n = export_locale_csv()
    if csv_path:
        print(f"Texte exportiert: {csv_path.relative_to(ROOT)} ({n} Einträge)")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--extract":
        cmd_extract()
        return
    if args and args[0] == "--roundtrip":
        sys.exit(0 if cmd_roundtrip() else 1)
    place = "all"
    if "--place" in args:
        i = args.index("--place")
        if i + 1 >= len(args) or args[i + 1] not in PLACES:
            raise SystemExit(f"--place erwartet einen von: {', '.join(PLACES)}")
        place = args[i + 1]
        del args[i:i + 2]
    out = Path(args[0]) if args else ROOT / "Ultimate_Car_Game.rbxlx"
    if not out.is_absolute():
        out = Path.cwd() / out
    cmd_build(out, place)


if __name__ == "__main__":
    main()
