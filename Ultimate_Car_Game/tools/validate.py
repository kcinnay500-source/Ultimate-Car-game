#!/usr/bin/env python3
"""Prüft den gebauten Place und das Projekt (3.0 = 2.4.0-Basisplace + src/garage + src/mini + Welt).

1. Place: exakt so gebaut wie tools/build_place.py (Basisplace + src/** + tools/worldgen); jedes Skript
   im Place stammt aus src/, genau die erwarteten Skripte, Klassen und Quelltexte stimmen, Skriptnamen eindeutig;
   Attribut PlaceKind = "all" auf ReplicatedStorage.GarageShared, Zonen City/Lobby/Tycoon vorhanden
   (PHASE4_CONTRACT §1); die Varianten lobby/openworld/tycoon werden in ein Arbeitsverzeichnis gebaut und geprüft
   (nur die eigene Zone, Werkstatt-Vorlage mit CarSpawn, dieselben Skripte, passendes PlaceKind)
2. Basis: außer Skript-Quelltexten ist der Basisplace unverändert ("nur Skripte geändert"); jede Änderung an
   src/garage gegenüber 2.4.0 ist mit "-- 3.0:" kommentiert; src/garage enthält genau die 2.4.0-Skripte
3. Luau-Compiler: alle Skripte in src/ und alle Test-Dateien
4. Statische Prüfungen: requires, Aktionen (MiniNet <-> Handler <-> Client), Client sendet keine Beträge,
   Begriff A2, keine externen Asset-IDs, Version 3.0.0, DataStore-Identität, Lokalisierungstabelle
5. Test-Fixtures aktuell (tools/export_fixture.py --check)
6. Automatisierte Tests (tests/run_tests.lua im Roblox-Mock)

Aufruf: python tools/validate.py Ultimate_Car_Game.rbxlx
Der Luau-Runner wird bei Bedarf mit cargo aus tools/luaurun gebaut.
"""
import csv
import difflib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
RUNNER_DIR = ROOT / "tools" / "luaurun"
RUNNER = RUNNER_DIR / "target" / "release" / ("luaurun.exe" if os.name == "nt" else "luaurun")

# Erwartete Identität (darf sich durch den Merge nicht ändern)
VERSION = "3.0.0"
PROFILE_STORE = "UltimateCarGame_v2"
STUDIO_STORE = "UltimateCarGame_Studio_v2"
LEADERBOARD_STORE = "UltimateCarGame_ScrapLeaderboard_v1"
# Nutzlast-Felder, die ein Client nie senden darf (Serverautorität)
FORBIDDEN_FIELDS = {"amount", "price", "cost", "credits", "money", "scrap", "reward", "gain", "xp", "time", "now", "timestamp", "result", "correct"}
# Ausnahmen laut PHASE2_CONTRACT §4: ein Gebot ist eine Absicht (Server prüft Mindestgebot, Deckel und Guthaben).
# PHASE4_CONTRACT §10: tycoon_trade_offer {to, item, qty, price} (price = gewählter Bargeld-Preis, qty 1..999; Server
# prüft Lager und Bargeld) und story_sell {offer, price} (price = Preisstufe 1..3) sind ebenfalls Absichten.
INTENT_FIELDS = {("mini_auction_bid", "amount"),
                 ("mini_tycoon_trade_offer", "price"), ("mini_tycoon_trade_offer", "qty"),
                 ("mini_story_sell", "price"),
                 ("tycoon_trade_offer", "price"), ("tycoon_trade_offer", "qty"), ("story_sell", "price")}
# 3.x Entwickler-Menü: dev_set {field, value} trägt einen gewünschten Wert (Level, XP, Credits, Tycoon-Bargeld) – die
# einzige Aktion, deren Zahl der Server übernimmt. Zulässig, weil DevService.Set bei JEDEM Aufruf DevService.IsDev
# prüft (Studio, Ersteller/Gruppenbesitzer, GameConfig.Dev.AllowedUserIds) und den Wert rundet und deckelt; alle
# anderen Spieler bekommen keine Antwort. validate_static prüft, dass diese Berechtigungsprüfung im Handler steht.
SERVER_AUTHORIZED = {("dev_set", "value"): ("src/mini/server/DevService.lua", "function DevService.Set", "DevService.IsDev(ms.player)")}
# print() im Spielcode nur als bewusstes Protokoll: DevService schreibt jede Entwickler-Änderung als "[Dev] …" ins
# Server-Log (nachvollziehbar, wer im veröffentlichten Spiel Level/Credits gesetzt hat).
PRINT_ALLOWED = {"DevService.lua"}
PLACES = ("all", "lobby", "openworld", "tycoon")
ZONE_MODELS = {"lobby": "Lobby", "openworld": "City", "tycoon": "Tycoon"}

errors = []
warnings = []
checks = 0


def check(cond, msg):
    global checks
    checks += 1
    if not cond:
        errors.append(msg)
    return cond


def load_builder():
    spec = importlib.util.spec_from_file_location("build_place_validate", ROOT / "tools" / "build_place.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


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


def rel(p: Path):
    return p.relative_to(ROOT).as_posix()


def lua_sources():
    return sorted(p for p in SRC.rglob("*.lua"))


def test_sources():
    return sorted(p for p in (ROOT / "tests").rglob("*.lua"))


def side_of(path: Path):
    parts = path.relative_to(SRC).parts
    return parts[0], parts[1] if len(parts) > 2 else ""  # ("garage"|"mini", "shared"|"server"|"client")


def module_name(path: Path):
    return re.sub(r"\.(server|client)\.lua$|\.lua$", "", path.name)


# ---------------------------------------------------------------- 1. Place
def validate_place(place: Path, builder):
    print(f"[1] Place: {place.name}")
    if not check(place.exists(), f"Place fehlt: {place} (python3 tools/build_place.py {place.name})"):
        return
    # a) exakt wie build_place.py: Basis + Skripte + Welt + PlaceKind, in einem frischen Builder gebaut
    fresh = load_builder()
    tree, _, _, world = fresh.build_tree("all")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "expected.rbxlx"
        fresh.write(tree, out)
        same = out.read_bytes() == place.read_bytes()
    check(same, f"{place.name} entspricht nicht Basisplace + src/**" + (" + tools/worldgen" if world else "") + " – neu bauen: python3 tools/build_place.py " + place.name)
    del tree
    # b) Skripte im Place: genau die aus src/, gleiche Klasse, gleicher Quelltext
    root = ET.parse(place).getroot()
    in_place = builder.place_scripts(root)
    expected = builder.src_files()
    for key, (cls, f) in expected.items():
        item = in_place.get(key)
        if check(item is not None, f"{rel(f)} fehlt im Place unter {'.'.join(key)}"):
            check(item.get("class") == cls, f"{'.'.join(key)}: Klasse {item.get('class')} statt {cls}")
            source = builder.prop(item, "Source")
            check(source is not None and (source.text or "") == builder.read_source(f).replace("\r\n", "\n").replace("\r", "\n"),
                  f"{'.'.join(key)}: Quelltext weicht von {rel(f)} ab – Place neu bauen")
    for key in in_place:
        check(key in expected, f"Skript {'.'.join(key)} im Place stammt nicht aus src/")
    check(len(in_place) == len(expected), f"Place enthält {len(in_place)} Skripte, src/ hat {len(expected)}")
    # c) Skriptnamen im ganzen Place eindeutig (Vertrag §1)
    names = {}
    for key in in_place:
        names.setdefault(key[-1], []).append(".".join(key))
    for name, where in sorted(names.items()):
        check(len(where) == 1, f"Skriptname {name} mehrfach im Place: {', '.join(where)}")
    # d) keine externen Assets im ganzen Place
    text = place.read_text(encoding="utf-8")
    check("rbxassetid://" not in text and "roblox.com/asset" not in text, f"{place.name}: externe Asset-ID (rbxassetid) gefunden")
    del text
    # e) PlaceKind "all" und alle drei Zonen (PHASE4_CONTRACT §1)
    validate_zones(root, "all", place.name, builder, set(in_place))
    print(f"    {len(in_place)} Skripte, Welt: {world or 'ohne tools/worldgen'}")
    del root
    # f) Varianten lobby/openworld/tycoon: gebaut wie build_place.py --place, je nur die eigene Zone
    validate_variants(builder, set(in_place))


def place_kind_of(root, builder):
    shared = builder.find_path(root, ("ReplicatedStorage", "GarageShared"))
    if shared is None:
        return None
    wg = builder.load_worldgen()
    return wg.lib.get_attrs(shared).get("PlaceKind") if wg is not None else None


def validate_zones(root, place, label, builder, script_keys=None):
    """Zonen-Modelle im Workspace passend zur PlaceKind; Werkstatt-Vorlage mit CarSpawn in jedem Place."""
    kind = place_kind_of(root, builder)
    check(kind == place, f"{label}: Attribut PlaceKind auf GarageShared ist {kind!r} statt {place!r}")
    ws = builder.find_path(root, ("Workspace",))
    wanted = set(ZONE_MODELS.values()) if place == "all" else {ZONE_MODELS[place]}
    for kind_key, model in ZONE_MODELS.items():
        item = builder.child(ws, model)
        if model in wanted:
            check(item is not None and item.get("class") == "Model", f"{label}: Workspace.{model} (Model) fehlt")
        else:
            check(item is None, f"{label}: Workspace.{model} gehört nicht in den Place {place}")
    wk = builder.child(ws, "Werkstatt")
    if check(wk is not None, f"{label}: Plot-Vorlage Workspace.Werkstatt fehlt"):
        check(builder.child(wk, "CarSpawn") is not None, f"{label}: Werkstatt.CarSpawn fehlt (vehicles.build_plot_spawn)")
        check(builder.child(builder.child(wk, "Architecture"), "Boundary") is None, f"{label}: Plot-Vorlage nicht getrimmt (Boundary vorhanden)")
    # Zonen-Inhalt: Stationen/Ankunft/Spawn (die Geometrie prüft tools/worldgen/checks.py)
    for model, spawn, stations in (("Lobby", "LobbySpawn", ("mode_tycoon", "mode_openworld", "settings", "party", "tutorial")),
                                   ("Tycoon", "TycoonSpawn", ("tycoon_market", "tycoon")),
                                   ("City", "CitySpawn", ("overview", "map"))):
        if model not in wanted:
            continue
        item = builder.child(ws, model)
        if item is None:
            continue
        sp = builder.child(item, spawn)
        if check(sp is not None and sp.get("class") == "SpawnLocation", f"{label}: {model}.{spawn} fehlt"):
            en = builder.prop(sp, "Enabled")
            want = "true" if model == "City" else "false"
            check(en is not None and en.text == want, f"{label}: {model}.{spawn}.Enabled soll {want} sein")
        st = builder.child(item, "Stations")
        names = {builder.name_of(c) for c in st.findall("Item")} if st is not None else set()
        check(set(stations) <= names, f"{label}: {model}.Stations unvollständig ({sorted(set(stations) - names)})")
        ar = builder.child(item, "Arrivals")
        check(ar is not None and builder.child(ar, "hub") is not None, f"{label}: {model}.Arrivals.hub fehlt")
        if model == "Tycoon":
            plots = builder.child(item, "Plots")
            slots = {builder.name_of(c) for c in plots.findall("Item")} if plots is not None else set()
            check(slots == {f"Slot_{i}" for i in range(1, 9)}, f"{label}: Tycoon.Plots.Slot_1..8 erwartet, gefunden {sorted(slots)}")
    if script_keys is not None:
        keys = set(builder.place_scripts(root))
        check(keys == script_keys, f"{label}: Skripte weichen vom all-Place ab ({sorted(keys ^ script_keys)[:5]})")


def scratch_dir():
    """Arbeitsverzeichnis für die Varianten: die Sitzungs-Scratchpad (Umgebung) oder ein temporäres Verzeichnis."""
    env = os.environ.get("CLAUDE_SCRATCHPAD") or os.environ.get("SCRATCHPAD")
    if env and Path(env).is_dir():
        d = Path(env) / "validate_places"
        d.mkdir(parents=True, exist_ok=True)
        return d, None
    tmp = tempfile.TemporaryDirectory(prefix="ucg_places_")
    return Path(tmp.name), tmp


def validate_default_outputs(builder):
    """B-013: ohne Dateinamen schreibt jeder Place in eine eigene Datei – eine Variante nie über den Haupt-Place."""
    main = builder.ROOT / "Ultimate_Car_Game.rbxlx"
    outs = {place: builder.default_out(place) for place in builder.PLACES}
    check(outs["all"] == main, f"build_place: Standard-Ausgabe für all ist {outs['all'].name} statt {main.name}")
    for place, out in outs.items():
        if place != "all":
            check(out.name.lower() != main.name.lower(),
                  f"build_place --place {place} ohne Dateinamen würde den Haupt-Place {main.name} überschreiben")
        check(out.parent == builder.ROOT, f"build_place: Standard-Ausgabe für {place} liegt nicht im Projektordner")
    names = {out.name.lower() for out in outs.values()}
    check(len(names) == len(outs), f"build_place: Standard-Ausgaben nicht eindeutig ({sorted(o.name for o in outs.values())})")


def validate_variants(builder, script_keys):
    validate_default_outputs(builder)
    out_dir, keep = scratch_dir()
    fresh = load_builder()
    for place in ("lobby", "openworld", "tycoon"):
        tree, replaced, added, world = fresh.build_tree(place)
        out = out_dir / f"Ultimate_Car_Game_{place}.rbxlx"
        fresh.write(tree, out)
        root = tree.getroot()
        validate_zones(root, place, out.name, builder, script_keys)
        first = (world or "").split("\n")
        print(f"    Variante {place}: {out.name} ({replaced + added} Skripte; {'; '.join(l.strip() for l in first[1:3])})")
        del tree, root
    if keep is not None:
        keep.cleanup()


# ---------------------------------------------------------------- 2. Basis und 2.4.0-Änderungen
def validate_base(builder):
    print("[2] Basis 2.4.0 und markierte Änderungen")
    with io.StringIO() as buf:
        stdout = sys.stdout
        sys.stdout = buf
        try:
            ok = builder.cmd_roundtrip()
        finally:
            sys.stdout = stdout
        msg = buf.getvalue().strip()
    print("    " + msg)
    check(ok, "Basisplace + src/garage: " + msg)
    base_root = builder.load_base().getroot()
    base_scripts = builder.place_scripts(base_root)
    garage_targets = {tuple(t) for r, t in builder.MAPPING if r.startswith("garage/")}
    garage_files = {k: v for k, v in builder.src_files().items() if k[:-1] in garage_targets}
    for key in garage_files:
        check(key in base_scripts, f"src/garage enthält ein Skript, das es in 2.4.0 nicht gibt: {'.'.join(key)} (neue Skripte gehören nach src/mini)")
    unmarked = 0
    changed_files = 0
    for key, item in base_scripts.items():
        entry = garage_files.get(key)
        if not check(entry is not None, f"2.4.0-Skript {'.'.join(key)} fehlt in src/garage"):
            continue
        old = (builder.prop(item, "Source").text or "").split("\n")
        new = builder.read_source(entry[1]).split("\n")
        if old == new:
            continue
        changed_files += 1
        sm = difflib.SequenceMatcher(a=old, b=new, autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == "equal":
                continue
            window = new[max(0, j1 - 2): min(len(new), j2 + 2)]
            if not any("3.0" in line and "--" in line for line in window):
                unmarked += 1
                check(False, f"{rel(entry[1])}: Änderung in Zeile {j1 + 1} ohne Kommentar '-- 3.0:'")
    print(f"    {changed_files} 2.4.0-Skripte geändert, {unmarked} Änderungen ohne '-- 3.0:'")


# ---------------------------------------------------------------- 3. Compiler
def validate_compile(runner):
    print("[3] Luau-Compiler")
    files = [str(p) for p in lua_sources()] + [str(p) for p in test_sources()]
    result = subprocess.run([str(runner), "check", *files], cwd=ROOT, capture_output=True, text=True)
    out = (result.stdout + result.stderr).strip()
    print("    " + out.replace("\n", "\n    "))
    check(result.returncode == 0, "Luau-Compiler meldet Fehler")


# ---------------------------------------------------------------- 4. Statische Prüfungen
def block(text, start):
    i = text.index(start)
    rest = text[i:]
    return rest[: rest.index("\n}")]


def validate_static():
    print("[4] Statische Prüfungen")
    sources = lua_sources()
    texts = {p: p.read_text(encoding="utf-8") for p in sources}
    modules = {}  # Name -> Seite ("shared"/"server"/"client")
    for p in sources:
        if not p.name.endswith((".server.lua", ".client.lua")):
            modules[module_name(p)] = side_of(p)[1]

    # requires zeigen auf vorhandene Module; Client lädt keine Server-Module, Shared nur Shared
    req_patterns = [
        re.compile(r'WaitForChild\("([A-Za-z]+)"(?:\s*,\s*\d+)?\)\s*\)'),
        re.compile(r'require\(\s*script\.Parent(?:\.Parent)?\.([A-Za-z]+)\s*\)'),
        re.compile(r'require\(\s*game:GetService\("ReplicatedStorage"\)\.GarageShared\.([A-Za-z]+)\s*\)'),
        re.compile(r'require\(\s*[A-Za-z]+\.([A-Za-z]+)\s*\)'),
    ]
    required = 0
    for p, text in texts.items():
        side = side_of(p)[1]
        for line in text.split("\n"):
            if "require(" not in line:
                continue
            for pat in req_patterns:
                for name in pat.findall(line):
                    if name in ("Mini", "GarageShared", "Remotes", "Parent"):
                        continue
                    required += 1
                    if not check(name in modules, f"{rel(p)}: require auf unbekanntes Modul {name}"):
                        continue
                    target = modules[name]
                    if side == "client":
                        check(target != "server", f"{rel(p)}: Client lädt Server-Modul {name}")
                    if side == "shared":
                        check(target == "shared", f"{rel(p)}: Shared lädt {target}-Modul {name}")
                    if side == "server":
                        check(target != "client", f"{rel(p)}: Server lädt Client-Modul {name}")

    # Aktionen: MiniNet.Actions <-> genau ein Handler; Client sendet nur definierte Aktionen ohne Beträge
    net = texts[SRC / "mini" / "shared" / "MiniNet.lua"]
    actions = {}
    # PHASE4_CONTRACT §10: Lobby/Tutorial/Prestige-Aktionen tragen kein mini_-Präfix (lobby_mode, party_join, …)
    for name, fields in re.findall(r"^\t([a-z_]+) = \{([^}]*)\}", block(net, "MiniNet.Actions = {"), re.M):
        actions[name] = set(re.findall(r"([a-zA-Z_]+)\s*=", fields))
    check(len(actions) >= 20, f"MiniNet.Actions unvollständig ({len(actions)})")
    for name, fields in actions.items():
        for f in fields:
            check(f not in FORBIDDEN_FIELDS or (name, f) in INTENT_FIELDS, f"MiniNet.Actions.{name}: Feld {f} wäre ein Client-Betrag")
    for (a, field), (path, func, guard) in SERVER_AUTHORIZED.items():
        check(field in actions.get(a, set()), f"MiniNet.Actions.{a}: Feld {field} fehlt (SERVER_AUTHORIZED)")
        src = texts.get(ROOT / path, "")
        body = src[src.find(func):] if func in src else ""
        body = body[: body.find("\nend\n")] if "\nend\n" in body else body
        check(guard in body, f"{path}: {func} prüft die Berechtigung nicht ({guard})")
    registered = []
    for p, text in texts.items():
        if side_of(p) == ("mini", "server"):
            registered += re.findall(r'Actions\.Register\("([a-z_]+)"', text)
    for a in actions:
        check(registered.count(a) == 1, f"Aktion {a}: {registered.count(a)} Server-Handler")
    for a in registered:
        check(a in actions, f"Handler für undefinierte Aktion {a}")
    sent_mini = set()
    for p, text in texts.items():
        if side_of(p) == ("mini", "client"):
            for m in re.finditer(r'[Rr]emote\.Send(?:Raw)?\(\s*"([a-z_]+)"(?:\s*,\s*\{([^}]*)\})?', text):
                a = m.group(1)
                sent_mini.add(a)
                check(a in actions, f"{rel(p)}: sendet undefinierte Aktion {a}")
                for field in re.findall(r"([a-zA-Z_]+)\s*=", m.group(2) or ""):
                    check(field not in FORBIDDEN_FIELDS or (a, field) in INTENT_FIELDS, f"{rel(p)}: Client sendet verbotenes Feld {field} ({a})")
                    check(field in actions.get(a, set()), f"{rel(p)}: {a} sendet Feld {field}, das MiniNet nicht kennt")
            check("Command:FireServer" not in text or p.name == "MiniRemote.lua", f"{rel(p)}: sendet am MiniRemote vorbei")
    for a in actions:
        if a != "mini_sync":
            check(a in sent_mini, f"Aktion {a} wird vom Client nie gesendet")
    # 2.4.0-Client: jede gesendete Aktion hat eine Behandlung in GarageServer (act/request)
    server = texts[SRC / "garage" / "server" / "GarageServer.server.lua"]
    handled = set(re.findall(r'action==\"([A-Za-z]+)\"', server)) | set(re.findall(r'request\(player,\"([A-Za-z]+)\"', server))
    client = texts[SRC / "garage" / "client" / "GarageClient.client.lua"]
    for a in set(re.findall(r'\bsend\("([A-Za-z]+)"', client)):
        check(a in handled, f"GarageClient sendet {a}, GarageServer behandelt es nicht")
    check("Mini.Handles(action)" in server and "Mini.Handle(p,action,a)" in server, "GarageServer.request leitet Minispiel-Aktionen nicht an MiniService weiter")
    for hook in ("Mini.Init(", "Mini.Hello(p)", "Mini.OnJoin(p)", "Mini.Tick(p,", "Mini.OnSettled(p)", "Mini.OnActivity(p)", "Mini.OnLeave(p,", "Mini.Pending()",
                 "Mini.OnCharacter(p)", "Mini.OnStation(p,"):
        check(hook in server, f"GarageServer: Anbindung {hook} fehlt (Vertrag §3)")
    remotes = set(re.findall(r'Instance\.new\("(Remote(?:Event|Function)|UnreliableRemoteEvent)"', "\n".join(texts.values())))
    check(not remotes, "src/ legt eigene Remotes an (Vertrag: keine neuen Remotes)")

    # A2: der Begriff der alten Punktewährung kommt nirgends vor; keine externen Asset-IDs; keine Debug-Ausgaben
    for p, text in texts.items():
        check("Autopunkt" not in text and "car points" not in text.lower(), f"{rel(p)}: Begriff 'Autopunkte' gefunden")
        check(re.search(r"\bAP\b", text) is None, f"{rel(p)}: Begriff 'AP' gefunden")
        check("rbxassetid://" not in text and "roblox.com/asset" not in text, f"{rel(p)}: externe Asset-ID")
        if side_of(p)[0] == "mini" and p.name not in PRINT_ALLOWED and re.search(r"^\s*print\(", text, re.M):
            warnings.append(f"{rel(p)}: print() im Spielcode")

    # PHASE4_CONTRACT §9 (Meilenstein 8): ProcessReceipt nur in Purchases.lua; Produkt-/Pass-Ids eindeutig (0 = Platzhalter)
    purchases_path = SRC / "garage" / "server" / "Purchases.lua"
    for p, text in texts.items():
        if p != purchases_path and side_of(p)[1] != "client":
            check(re.search(r"\.ProcessReceipt\s*=", text) is None, f"{rel(p)}: ProcessReceipt außerhalb von Purchases.lua gesetzt")
    check(re.search(r"\.ProcessReceipt\s*=", texts[purchases_path]) is not None, "Purchases.lua: ProcessReceipt fehlt")
    game_config = texts[SRC / "mini" / "shared" / "GameConfig.lua"]
    shop_products = block(game_config, "local PRODUCTS: { ShopProduct } = {")
    shop_passes = block(game_config, "Shop.Passes = {")
    if check(shop_products != "" and shop_passes != "", "GameConfig.Shop: Products/Passes-Blöcke nicht gefunden"):
        product_ids = re.findall(r"productId\s*=\s*(\d+)", texts[SRC / "garage" / "shared" / "Config.lua"])
        product_ids += re.findall(r"productId\s*=\s*(\d+)", shop_products)
        live = [i for i in product_ids if i != "0"]
        check(len(live) == len(set(live)), "Developer-Product-Ids doppelt (C.CreditProducts / GameConfig.Shop.Products)")
        pass_ids = re.findall(r"\bid\s*=\s*(\d+)", shop_passes)
        pass_ids += re.findall(r"\bid\s*=\s*(\d+)", block(texts[SRC / "mini" / "shared" / "MiniConfig.lua"], "MiniConfig.GamePasses = {"))
        live = [i for i in pass_ids if i != "0"]
        check(len(live) == len(set(live)), "Game-Pass-Ids doppelt (GameConfig.Shop.Passes / MiniConfig.GamePasses)")
        for kind in ("car", "cosmetic", "bundle"):
            check(f'kind = "{kind}"' in shop_products, f"GameConfig.Shop.Products: kein Produkt der Art {kind}")
        check(re.search(r"\bkind\s*=\s*\"(crate|box|lootbox|random)\"", shop_products) is None, "GameConfig.Shop.Products: Zufallskäufe sind nicht erlaubt")

    # Version und DataStore-Identität
    config = texts[SRC / "garage" / "shared" / "Config.lua"]
    m = re.search(r'^C\.Version\s*=\s*"([^"]+)"', config, re.M)
    check(m is not None and m.group(1) == VERSION, f"C.Version ist {m and m.group(1)} statt {VERSION}")
    m = re.search(r'^C\.DataStoreName\s*=\s*"([^"]+)"', config, re.M)
    check(m is not None and m.group(1) == PROFILE_STORE, f"DataStore-Identität geändert: C.DataStoreName = {m and m.group(1)}")
    m = re.search(r'^C\.StudioDataStoreName\s*=\s*"([^"]+)"', config, re.M)
    check(m is not None and m.group(1) == STUDIO_STORE, f"Studio-DataStore geändert: {m and m.group(1)}")
    rules = texts[SRC / "garage" / "shared" / "Rules.lua"]
    check(re.search(r"local d=\{version=2,", rules) is not None, "R.NewData: data.version ist nicht mehr 2")
    check("version = 2, data = data" in texts[SRC / "garage" / "server" / "Profiles.lua"], "Profiles: Hülle {version=2,data,receipts,lock} geändert")
    mini_config = texts[SRC / "mini" / "shared" / "MiniConfig.lua"]
    check(f'MiniConfig.LeaderboardStoreName = "{LEADERBOARD_STORE}"' in mini_config, "Bestenlisten-Store umbenannt (Werte gingen verloren)")
    slots = re.search(r"C\.PlotSlots\s*=\s*\{(.*?)\n\}", config, re.S)
    if check(slots is not None, "C.PlotSlots fehlt in GarageShared.Config"):
        entries = re.findall(r"\{\s*x\s*=\s*-?[\d.]+\s*,\s*z\s*=\s*-?[\d.]+\s*,\s*rot\s*=\s*(\d+)\s*\}", slots.group(1))
        max_plots = re.search(r"^C\.MaxPlots\s*=\s*(\d+)", config, re.M)
        check(max_plots is not None and len(entries) == int(max_plots.group(1)), f"C.PlotSlots hat {len(entries)} Einträge statt C.MaxPlots")
        check(all(r in ("0", "180") for r in entries), "C.PlotSlots: rot nur 0 oder 180")

    # Lokalisierungstabelle aktuell (build_place.py exportiert sie aus MiniLocale)
    locale = texts[SRC / "mini" / "shared" / "MiniLocale.lua"]
    rows = re.findall(r'^\t([a-z_]+) = "((?:[^"\\]|\\.)*)",$', block(locale, "MiniLocale.Strings = {"), re.M)
    csv_path = ROOT / "localization" / "Locale_de.csv"
    if check(csv_path.exists(), "localization/Locale_de.csv fehlt – python3 tools/build_place.py"):
        with csv_path.open(encoding="utf-8", newline="") as f:
            table = [(r[0], r[4]) for r in list(csv.reader(f))[1:]]
        check(table == rows, "localization/Locale_de.csv ist veraltet – python3 tools/build_place.py")
    print(f"    {len(actions)} Minispiel-Aktionen, {len(registered)} Handler, {len(sent_mini)} vom Client gesendet, {required} requires geprüft")


# ---------------------------------------------------------------- 5./6. Fixtures und Tests
def validate_fixtures():
    print("[5] Test-Fixtures")
    result = subprocess.run([sys.executable, str(ROOT / "tools" / "export_fixture.py"), "--check"], cwd=ROOT, capture_output=True, text=True)
    out = (result.stdout + result.stderr).strip()
    print("    " + out.replace("\n", "\n    "))
    check(result.returncode == 0, "Test-Fixtures veraltet – python3 tools/export_fixture.py")


def validate_tests(runner):
    print("[6] Automatisierte Tests (Roblox-Mock)")
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
    builder = load_builder()
    validate_place(place, builder)
    validate_base(builder)
    runner = find_runner()
    test_checks = 0
    if check(runner is not None, "Luau-Runner fehlt (Rust/cargo installieren oder LUAURUN setzen)"):
        validate_compile(runner)
    validate_static()
    validate_fixtures()
    if runner is not None:
        test_checks = validate_tests(runner)
    print()
    for w in warnings:
        print("WARNUNG " + w)
    for e in errors:
        print("FEHLER " + e)
    print(f"Ergebnis: {checks} Validierungsprüfungen + {test_checks} Testprüfungen, {len(errors)} Fehler, {len(warnings)} Warnungen")
    sys.exit(1 if errors or warnings else 0)


if __name__ == "__main__":
    main()
