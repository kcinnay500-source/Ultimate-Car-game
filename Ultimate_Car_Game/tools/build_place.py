#!/usr/bin/env python3
"""Erzeugt den Roblox-Place (.rbxlx) aus src/.

Zuordnung (wie Rojo):
  src/shared/*.lua         -> ReplicatedStorage.Shared (ModuleScript)
  src/server/*.server.lua  -> ServerScriptService.Server (Script)
  src/server/*.lua         -> ServerScriptService.Server (ModuleScript)
  src/client/*.client.lua  -> StarterPlayer.StarterPlayerScripts (LocalScript)
  src/client/*.lua         -> StarterPlayer.StarterPlayerScripts.Client (ModuleScript)

Aufruf: python tools/build_place.py Ultimate_Car_Game.rbxlx
"""
import itertools
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

_ref = itertools.count(1)


def ref():
    return "RBX%08X" % next(_ref)


def classify(path: Path):
    name = path.name
    if name.endswith(".server.lua"):
        return "Script", name[: -len(".server.lua")]
    if name.endswith(".client.lua"):
        return "LocalScript", name[: -len(".client.lua")]
    return "ModuleScript", name[: -len(".lua")]


def cdata(text: str) -> str:
    # "]]>" darf in CDATA nicht vorkommen: aufteilen
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script_item(path: Path, indent: str) -> str:
    cls, name = classify(path)
    source = path.read_text(encoding="utf-8")
    props = [f'<string name="Name">{escape(name)}</string>']
    if cls != "ModuleScript":
        props.append('<bool name="Disabled">false</bool>')
    props.append(f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
    inner = "".join(props)
    return f'{indent}<Item class="{cls}" referent="{ref()}"><Properties>{inner}</Properties></Item>\n'


def container(cls: str, name: str, children: str, indent: str) -> str:
    return (
        f'{indent}<Item class="{cls}" referent="{ref()}">'
        f'<Properties><string name="Name">{escape(name)}</string></Properties>\n'
        f"{children}{indent}</Item>\n"
    )


def lua_files(folder: Path):
    return sorted(p for p in folder.glob("*.lua") if p.is_file())


def build() -> str:
    shared = "".join(script_item(p, "      ") for p in lua_files(SRC / "shared"))
    server = "".join(script_item(p, "      ") for p in lua_files(SRC / "server"))
    client_files = lua_files(SRC / "client")
    client_scripts = "".join(script_item(p, "        ") for p in client_files if p.name.endswith(".client.lua"))
    client_modules = "".join(script_item(p, "          ") for p in client_files if not p.name.endswith(".client.lua"))

    parts = [
        '<?xml version="1.0" encoding="utf-8"?>\n',
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n',
        "  <External>null</External>\n  <External>nil</External>\n",
        container("Workspace", "Workspace", "", "  "),
        container("ReplicatedStorage", "ReplicatedStorage", container("Folder", "Shared", shared, "    "), "  "),
        container("ServerScriptService", "ServerScriptService", container("Folder", "Server", server, "    "), "  "),
        container(
            "StarterPlayer",
            "StarterPlayer",
            container(
                "StarterPlayerScripts",
                "StarterPlayerScripts",
                client_scripts + container("Folder", "Client", client_modules, "        "),
                "    ",
            ),
            "  ",
        ),
        "</roblox>\n",
    ]
    return "".join(parts)


def export_locale_csv():
    """Exportiert Locale.Strings als Roblox-Lokalisierungstabelle (CSV)."""
    import csv
    import re

    text = (SRC / "shared" / "Locale.lua").read_text(encoding="utf-8")
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


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Ultimate_Car_Game.rbxlx"
    if not out.is_absolute():
        out = Path.cwd() / out
    xml = build()
    out.write_text(xml, encoding="utf-8")
    count = xml.count("<ProtectedString")
    print(f"Place gebaut: {out} ({count} Skripte)")
    csv_path, n = export_locale_csv()
    print(f"Texte exportiert: {csv_path.relative_to(ROOT)} ({n} Einträge)")


if __name__ == "__main__":
    main()
