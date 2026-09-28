#!/usr/bin/env python3
"""Prüft den gebauten Place und das Projekt.

1. Place-Struktur: alle Skripte aus src/ an der richtigen Stelle, Quelltext identisch
2. Luau-Compiler: alle Skripte und Tests kompilieren
3. Statische Prüfungen: requires, Remote-Aktionen, verbotene Begriffe, externe Assets
4. Automatisierte Tests (tests/run_tests.lua im Roblox-Mock)

Aufruf: python tools/validate.py Ultimate_Car_Game.rbxlx
Der Luau-Runner wird bei Bedarf mit cargo aus tools/luaurun gebaut.
"""
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
RUNNER_DIR = ROOT / "tools" / "luaurun"
RUNNER = RUNNER_DIR / "target" / "release" / ("luaurun.exe" if os.name == "nt" else "luaurun")

errors = []
warnings = []
checks = 0


def check(cond, msg):
    global checks
    checks += 1
    if not cond:
        errors.append(msg)
    return cond


def find_runner():
    env = os.environ.get("LUAURUN")
    if env and Path(env).exists():
        return Path(env)
    if RUNNER.exists():
        return RUNNER
    if shutil.which("cargo"):
        print("Baue Luau-Runner (einmalig, dauert etwa eine Minute) …")
        subprocess.run(["cargo", "build", "--release", "-q"], cwd=RUNNER_DIR, check=True)
        return RUNNER
    return None


def lua_sources():
    return sorted(p for p in SRC.rglob("*.lua"))


def expected_location(path: Path):
    rel = path.relative_to(SRC)
    name = path.name
    if name.endswith(".server.lua"):
        cls, inst = "Script", name[:-11]
    elif name.endswith(".client.lua"):
        cls, inst = "LocalScript", name[:-11]
    else:
        cls, inst = "ModuleScript", name[:-4]
    top = rel.parts[0]
    if top == "shared":
        parent = ("ReplicatedStorage", "Shared")
    elif top == "server":
        parent = ("ServerScriptService", "Server")
    else:
        parent = ("StarterPlayer", "StarterPlayerScripts") if cls == "LocalScript" else ("StarterPlayer", "StarterPlayerScripts", "Client")
    return parent, inst, cls


def place_index(place: Path):
    tree = ET.parse(place)
    index = {}

    def walk(item, path):
        props = item.find("Properties")
        name = None
        source = None
        if props is not None:
            for p in props:
                if p.get("name") == "Name":
                    name = p.text
                if p.get("name") == "Source":
                    source = p.text or ""
        here = path + (name,)
        if source is not None:
            index[here] = (item.get("class"), source)
        for child in item.findall("Item"):
            walk(child, here)

    for item in tree.getroot().findall("Item"):
        walk(item, ())
    return index


def validate_place(place: Path):
    print(f"[1] Place-Struktur: {place.name}")
    if not check(place.exists(), f"Place fehlt: {place}"):
        return
    index = place_index(place)
    sources = lua_sources()
    for path in sources:
        parent, name, cls = expected_location(path)
        key = parent + (name,)
        entry = index.get(key)
        if check(entry is not None, f"{path.relative_to(ROOT)} fehlt im Place unter {'.'.join(key)}"):
            check(entry[0] == cls, f"{'.'.join(key)}: Klasse {entry[0]} statt {cls}")
            check(entry[1] == path.read_text(encoding="utf-8"), f"{'.'.join(key)}: Quelltext veraltet – Place neu bauen")
    check(len(index) == len(sources), f"Place enthält {len(index)} Skripte, src/ hat {len(sources)}")


def validate_compile(runner):
    print("[2] Luau-Compiler")
    files = [str(p) for p in lua_sources()] + [str(p) for p in sorted((ROOT / "tests").glob("*.lua"))]
    result = subprocess.run([str(runner), "check", *files], cwd=ROOT, capture_output=True, text=True)
    out = (result.stdout + result.stderr).strip()
    print("    " + out.replace("\n", "\n    "))
    check(result.returncode == 0, "Luau-Compiler meldet Fehler")


def validate_static():
    print("[3] Statische Prüfungen")
    texts = {p: p.read_text(encoding="utf-8") for p in lua_sources()}
    modules = {
        "shared": {p.name[:-4] for p in (SRC / "shared").glob("*.lua")},
        "server": {re.sub(r"\.(server\.)?lua$", "", p.name) for p in (SRC / "server").glob("*.lua")},
        "client": {re.sub(r"\.(client\.)?lua$", "", p.name) for p in (SRC / "client").glob("*.lua")},
    }
    all_modules = modules["shared"] | modules["server"] | modules["client"]

    # requires zeigen auf vorhandene Module
    for path, text in texts.items():
        for m in re.finditer(r'require\([^\n]*?WaitForChild\("([A-Za-z]+)"\)\)', text):
            check(m.group(1) in all_modules, f"{path.relative_to(ROOT)}: require auf unbekanntes Modul {m.group(1)}")
        # Client darf keine Server-Module laden, Shared keine Client/Server-Module
        top = path.relative_to(SRC).parts[0]
        for m in re.finditer(r'require\([^\n]*?WaitForChild\("([A-Za-z]+)"\)\)', text):
            name = m.group(1)
            if top == "client":
                check(name not in modules["server"] or name in modules["shared"] or name in modules["client"], f"{path.name}: Client lädt Server-Modul {name}")
            if top == "shared":
                check(name in modules["shared"], f"{path.name}: Shared lädt {name}")

    # Remote-Aktionen: jede definierte Aktion hat genau einen Server-Handler, jede gesendete ist definiert
    net = texts[SRC / "shared" / "Net.lua"]
    block = net[net.index("Net.Actions = {"):]
    block = block[: block.index("\n}")]
    actions = set(re.findall(r"^\t([a-z_]+) = \{", block, re.M))
    check(len(actions) >= 20, f"Net.Actions unvollständig ({len(actions)})")
    registered = []
    for path, text in texts.items():
        if path.parent.name == "server":
            registered += re.findall(r'Actions\.Register\("([a-z_]+)"', text)
    for a in actions:
        check(registered.count(a) == 1, f"Aktion {a}: {registered.count(a)} Server-Handler")
    for a in registered:
        check(a in actions, f"Handler für undefinierte Aktion {a}")
    for path, text in texts.items():
        if path.parent.name == "client":
            for a in re.findall(r'Remote\.Send(?:Raw)?\("([a-z_]+)"', text):
                check(a in actions, f"{path.name}: sendet undefinierte Aktion {a}")

    # A2: der Begriff Autopunkte/AP kommt nirgends vor; keine externen Asset-IDs
    for path, text in texts.items():
        check("Autopunkt" not in text, f"{path.name}: Begriff 'Autopunkte' gefunden")
        check(re.search(r"\bAP\b", text) is None, f"{path.name}: Begriff 'AP' gefunden")
        check("rbxassetid://" not in text and "roblox.com/asset" not in text, f"{path.name}: externe Asset-ID")
        # Client sendet keine Beträge/Preise/Zeitstempel
        if path.parent.name == "client":
            for m in re.finditer(r'Remote\.Send(?:Raw)?\("[a-z_]+",\s*\{([^}]*)\}', text):
                for field in re.findall(r"([a-zA-Z_]+)\s*=", m.group(1)):
                    check(field not in {"amount", "price", "cost", "credits", "scrap", "reward", "time", "now", "timestamp"},
                          f"{path.name}: Client sendet verbotenes Feld {field}")
        # keine Debug-Ausgaben im Spielcode
        if re.search(r"^\s*print\(", text, re.M):
            warnings.append(f"{path.name}: print() im Spielcode")

    # Version
    check('Config.Version = "3.0.0"' in texts[SRC / "shared" / "Config.lua"], "Version ist nicht 3.0.0")
    check('Config.ProfileStoreName = "UltimateCarGame_v2"' in texts[SRC / "shared" / "Config.lua"], "DataStore-Identität geändert")


def validate_tests(runner):
    print("[4] Automatisierte Tests (Roblox-Mock)")
    result = subprocess.run([str(runner), "run", "tests/run_tests.lua", "."], cwd=ROOT, capture_output=True, text=True)
    lines = [l for l in (result.stdout + result.stderr).splitlines() if l.startswith("FEHLER") or l.startswith("Tests:")]
    for l in lines:
        print("    " + l)
    summary = [l for l in lines if l.startswith("Tests:")]
    check(result.returncode == 0 and summary and " 0 Fehler" in summary[-1], "Tests fehlgeschlagen")
    m = re.search(r"(\d+) Prüfungen", summary[-1]) if summary else None
    return int(m.group(1)) if m else 0


def main():
    place = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Ultimate_Car_Game.rbxlx"
    if not place.is_absolute():
        place = Path.cwd() / place
    validate_place(place)
    runner = find_runner()
    test_checks = 0
    if check(runner is not None, "Luau-Runner fehlt (Rust/cargo installieren oder LUAURUN setzen)"):
        validate_compile(runner)
        validate_static()
        test_checks = validate_tests(runner)
    else:
        validate_static()
    print()
    for w in warnings:
        print("WARNUNG " + w)
    for e in errors:
        print("FEHLER " + e)
    print(f"Ergebnis: {checks} Validierungsprüfungen + {test_checks} Testprüfungen, {len(errors)} Fehler, {len(warnings)} Warnungen")
    sys.exit(1 if errors or warnings else 0)


if __name__ == "__main__":
    main()
