#!/usr/bin/env python3
"""Exportiert den Place-Baum (ohne Skripte) als Lua-Fixture für den Roblox-Mock.

Erzeugt
-------
* ``tests/fixtures/base_tree.lua``    alle Nicht-Skript-Instanzen (Klasse, Name, Eigenschaften, Attribute,
                                      Tags, Kinder, Ref-Verweise wie PrimaryPart) des Places.
* ``tests/fixtures/base_scripts.lua`` die unveränderten 2.4.0-Skripte aus ``base/`` (Pfad, Klasse, Quelltext).
                                      Damit prüfen die Tests das Original-Verhalten (``H.Garage{scripts="base"}``).

Quelle des Baums
----------------
* ohne Argument: ``base/Ultimate_Car_Game_2.4.0.rbxlx`` + ``tools/worldgen`` (falls vorhanden), genau so,
  wie ``tools/build_place.py`` den Place baut (Skripte spielen für den Baum keine Rolle).
* mit Argument: ein beliebiger (gebauter) Place, z. B. ``Ultimate_Car_Game.rbxlx``.

Aktualität
----------
Die Fixture speichert Größe und Prüfsumme aller Quelldateien (Basisplace, build_place.py, worldgen-Dateien).
``tests/run_tests.lua`` rechnet dieselbe Prüfsumme nach und bricht mit einem Hinweis ab, wenn die Fixture
veraltet ist. ``--check`` prüft nur (Exitcode 1 = veraltet).

Aufrufe:
  python3 tools/export_fixture.py                  Fixture aus Basis + worldgen erzeugen
  python3 tools/export_fixture.py Place.rbxlx      Fixture aus einem gebauten Place erzeugen
  python3 tools/export_fixture.py --check          nur prüfen, ob die Fixtures aktuell sind
"""
import base64
import importlib.util
import math
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "base" / "Ultimate_Car_Game_2.4.0.rbxlx"
BUILDER = ROOT / "tools" / "build_place.py"
WORLDGEN = ROOT / "tools" / "worldgen"
OUT_DIR = ROOT / "tests" / "fixtures"
OUT_TREE = OUT_DIR / "base_tree.lua"
OUT_SCRIPTS = OUT_DIR / "base_scripts.lua"
FORMAT = 1
SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}

# ---------------------------------------------------------------- Prüfsumme (identisch in tests/run_tests.lua)
M1, B1 = 2147483647, 1000003
M2, B2 = 1000000007, 65599


def file_hash(data: bytes):
    """Zwei Polynom-Hashes über 3-Byte-Gruppen; exakt mit Luau-Doubles nachrechenbar."""
    h1, h2 = 0, 0
    n = len(data)
    pad = (-n) % 3
    buf = data + b"\0" * pad
    for i in range(0, len(buf), 3):
        w = buf[i] + buf[i + 1] * 256 + buf[i + 2] * 65536
        h1 = (h1 * B1 + w) % M1
        h2 = (h2 * B2 + w + 1) % M2
    return "%08x%08x" % (h1, h2)


def source_entry(path: Path):
    data = path.read_bytes()
    return {"path": path.relative_to(ROOT).as_posix(), "size": len(data), "hash": file_hash(data)}


def worldgen_files():
    if not WORLDGEN.exists():
        return []
    out = []
    for p in sorted(WORLDGEN.rglob("*")):
        if p.is_file() and "__pycache__" not in p.parts and not p.name.endswith(".pyc"):
            out.append(p)
    return out


# ---------------------------------------------------------------- Enums (Wert -> Name)
ENUMS = {
    "Material": {
        256: "Plastic", 272: "SmoothPlastic", 288: "Neon", 512: "Wood", 528: "WoodPlanks", 784: "Marble",
        788: "Basalt", 800: "Slate", 804: "CrackedLava", 816: "Concrete", 820: "Limestone", 832: "Granite",
        836: "Pavement", 848: "Brick", 864: "Pebble", 880: "Cobblestone", 896: "Rock", 912: "Sandstone",
        1040: "CorrodedMetal", 1056: "DiamondPlate", 1072: "Foil", 1088: "Metal", 1280: "Grass",
        1284: "LeafyGrass", 1296: "Sand", 1312: "Fabric", 1328: "Snow", 1344: "Mud", 1360: "Ground",
        1376: "Asphalt", 1392: "Salt", 1536: "Ice", 1552: "Glacier", 1568: "Glass", 1584: "ForceField",
        1792: "Air", 2048: "Water", 1348: "Cardboard", 1349: "Carpet", 1350: "CeramicTiles",
        1351: "ClayRoofTiles", 1352: "RoofShingles", 1353: "Leather", 1354: "Plaster", 1355: "Rubber",
    },
    "Font": {
        0: "Legacy", 1: "Arial", 2: "ArialBold", 3: "SourceSans", 4: "SourceSansBold", 5: "SourceSansLight",
        6: "SourceSansItalic", 7: "Bodoni", 8: "Garamond", 9: "Cartoon", 10: "Code", 11: "Highway", 12: "SciFi",
        13: "Arcade", 14: "Fantasy", 15: "Antique", 16: "SourceSansSemibold", 17: "Gotham", 18: "GothamMedium",
        19: "GothamBold", 20: "GothamBlack", 21: "AmaticSC", 22: "Bangers", 23: "Creepster", 24: "DenkOne",
        25: "Fondamento", 26: "FredokaOne", 27: "GrenzeGotisch", 28: "IndieFlower", 29: "JosefinSans",
        30: "Jura", 31: "Kalam", 32: "LuckiestGuy", 33: "Merriweather", 34: "Michroma", 35: "Nunito",
        36: "Oswald", 37: "PatrickHand", 38: "PermanentMarker", 39: "Roboto", 40: "RobotoCondensed",
        41: "RobotoMono", 42: "Sarpanch", 43: "SpecialElite", 44: "TitilliumWeb", 45: "Ubuntu",
        46: "BuilderSans", 47: "BuilderSansMedium", 48: "BuilderSansBold", 49: "BuilderSansExtraBold",
        50: "Arimo", 51: "ArimoBold",
    },
    "KeyCode": {
        0: "Unknown", 8: "Backspace", 9: "Tab", 13: "Return", 27: "Escape", 32: "Space",
        48: "Zero", 49: "One", 50: "Two", 51: "Three", 52: "Four", 53: "Five", 54: "Six", 55: "Seven",
        56: "Eight", 57: "Nine", **{97 + i: chr(65 + i) for i in range(26)},
        273: "Up", 274: "Down", 275: "Right", 276: "Left", 304: "LeftShift", 306: "LeftControl",
        1000: "ButtonX", 1001: "ButtonY", 1002: "ButtonA", 1003: "ButtonB", 1004: "ButtonR1", 1005: "ButtonL1",
        1006: "ButtonR2", 1007: "ButtonL2", 1008: "ButtonR3", 1009: "ButtonL3", 1010: "ButtonStart",
        1011: "ButtonSelect", 1012: "DPadLeft", 1013: "DPadRight", 1014: "DPadUp", 1015: "DPadDown",
    },
    "NormalId": {0: "Right", 1: "Top", 2: "Back", 3: "Left", 4: "Bottom", 5: "Front"},
    "PartType": {0: "Ball", 1: "Block", 2: "Cylinder", 3: "Wedge", 4: "CornerWedge"},
    "SurfaceGuiSizingMode": {0: "FixedSize", 1: "PixelsPerStud"},
    "ProximityPromptStyle": {0: "Default", 1: "Custom"},
    "ProximityPromptExclusivity": {0: "OnePerButton", 1: "OneGlobally", 2: "AlwaysShow"},
    "TextXAlignment": {0: "Left", 1: "Right", 2: "Center"},
    "TextYAlignment": {0: "Top", 1: "Center", 2: "Bottom"},
    "ZIndexBehavior": {0: "Global", 1: "Sibling"},
    "AutomaticSize": {0: "None", 1: "X", 2: "Y", 3: "XY"},
    "ScrollingDirection": {1: "X", 2: "Y", 4: "XY"},
    "FillDirection": {0: "Horizontal", 1: "Vertical"},
    "SortOrder": {0: "Name", 1: "Custom", 2: "LayoutOrder"},
    "HorizontalAlignment": {0: "Center", 1: "Left", 2: "Right"},
    "VerticalAlignment": {0: "Center", 1: "Top", 2: "Bottom"},
    "HighlightDepthMode": {0: "AlwaysOnTop", 1: "Occluded"},
    "MeshType": {0: "Head", 1: "Torso", 2: "Wedge", 3: "Sphere", 4: "Cylinder", 5: "FileMesh", 6: "Brick"},
    "SizeConstraint": {0: "RelativeXY", 1: "RelativeXX", 2: "RelativeYY"},
    "BorderMode": {0: "Outline", 1: "Middle", 2: "Inset"},
    "TextTruncate": {0: "None", 1: "AtEnd"},
    "ApplyStrokeMode": {0: "Contextual", 1: "Border"},
    "ScaleType": {0: "Stretch", 1: "Slice", 2: "Tile", 3: "Fit", 4: "Crop"},
    "ResamplerMode": {0: "Default", 1: "Pixelated"},
    "LightingStyle": {0: "Realistic", 1: "Soft"},
    "Technology": {0: "Legacy", 1: "Voxel", 2: "Compatibility", 3: "ShadowMap", 4: "Future"},
    "CameraType": {0: "Fixed", 1: "Attach", 2: "Watch", 3: "Track", 4: "Follow", 5: "Custom", 6: "Scriptable",
                   7: "Orbital"},
    "HumanoidRigType": {0: "R6", 1: "R15"},
}
# Eigenschaft -> Enum-Typ (nur wo der Name nicht dem Enum entspricht)
TOKEN_TYPES = {
    "Material": "Material", "Font": "Font", "KeyboardKeyCode": "KeyCode", "GamepadKeyCode": "KeyCode",
    "Face": "NormalId", "Shape": "PartType", "SizingMode": "SurfaceGuiSizingMode",
    "Style": "ProximityPromptStyle", "Exclusivity": "ProximityPromptExclusivity",
    "TextXAlignment": "TextXAlignment", "TextYAlignment": "TextYAlignment", "ZIndexBehavior": "ZIndexBehavior",
    "AutomaticSize": "AutomaticSize", "AutomaticCanvasSize": "AutomaticSize",
    "ScrollingDirection": "ScrollingDirection", "FillDirection": "FillDirection", "SortOrder": "SortOrder",
    "HorizontalAlignment": "HorizontalAlignment", "VerticalAlignment": "VerticalAlignment",
    "DepthMode": "HighlightDepthMode", "MeshType": "MeshType", "SizeConstraint": "SizeConstraint",
    "BorderMode": "BorderMode", "TextTruncate": "TextTruncate", "ApplyStrokeMode": "ApplyStrokeMode",
    "ScaleType": "ScaleType", "ResampleMode": "ResamplerMode", "Technology": "Technology",
    "CameraType": "CameraType", "RigType": "HumanoidRigType", "MaterialVariant": None,
}
RENAME = {"size": "Size", "shape": "Shape", "Color3uint8": "Color", "WorldPivotData": "WorldPivot",
          "formFactorRaw": None, "Tags": None, "AttributesSerialize": None, "SourceAssetId": None,
          "UniqueId": None, "HistoryId": None, "Capabilities": None, "DefinesCapabilities": None,
          "ScriptGuid": None, "LinkedSource": None, "Source": None}
# Nur visuell, für Skripte bedeutungslos: nicht exportieren (hält die Fixture klein)
SKIP = {"TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface",
        "TopSurfaceInput", "BottomSurfaceInput", "LeftSurfaceInput", "RightSurfaceInput", "FrontSurfaceInput",
        "BackSurfaceInput", "TopParamA", "TopParamB", "BottomParamA", "BottomParamB", "LeftParamA", "LeftParamB",
        "RightParamA", "RightParamB", "FrontParamA", "FrontParamB", "BackParamA", "BackParamB",
        "CollisionGroup", "CollisionGroupId", "CustomPhysicalProperties", "RootPriority", "Velocity",
        "RotVelocity", "AssemblyLinearVelocity", "AssemblyAngularVelocity", "Archivable", "Locked",
        "LevelOfDetail", "ModelStreamingMode", "NeedsPivotMigration", "MaterialVariantSerialized",
        "PhysicsGrid", "SmoothGrid", "MaterialColors", "AcquisitionMethod"}


# ---------------------------------------------------------------- Lua-Ausgabe
def lua_str(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if math.isnan(v):
        return "0/0"
    if math.isinf(v):
        return "math.huge" if v > 0 else "-math.huge"
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    r = repr(v)
    return r


def num(text):
    text = (text or "0").strip()
    try:
        v = int(text)
        return v
    except ValueError:
        pass
    low = text.lower()
    if low in ("inf", "+inf", "infinity"):
        return math.inf
    if low in ("-inf", "-infinity"):
        return -math.inf
    if low == "nan":
        return math.nan
    return float(text)


def sub(el, tag, default="0"):
    c = el.find(tag)
    return c.text if c is not None and c.text is not None else default


IDENTITY = (1, 0, 0, 0, 1, 0, 0, 0, 1)


def cframe_expr(el):
    x, y, z = (num(sub(el, k)) for k in ("X", "Y", "Z"))
    rot = tuple(num(sub(el, k, d)) for k, d in (("R00", "1"), ("R01", "0"), ("R02", "0"), ("R10", "0"),
                                                  ("R11", "1"), ("R12", "0"), ("R20", "0"), ("R21", "0"),
                                                  ("R22", "1")))
    if all(abs(a - b) < 1e-12 for a, b in zip(rot, IDENTITY)):
        return "CF(%s,%s,%s)" % (lua_num(x), lua_num(y), lua_num(z))
    return "CF(%s)" % ",".join(lua_num(v) for v in (x, y, z) + rot)


def enum_expr(enum_type, value):
    name = ENUMS.get(enum_type, {}).get(value)
    if name is not None:
        return "E.%s.%s" % (enum_type, name)
    return "EV(%s,%d)" % (lua_str(enum_type), value)


def seq_numbers(text):
    return [num(t) for t in (text or "").split()]


# ---------------------------------------------------------------- Attribute (AttributesSerialize)
class Reader:
    def __init__(self, data):
        self.d, self.i = data, 0

    def take(self, n):
        v = self.d[self.i:self.i + n]
        if len(v) < n:
            raise ValueError("Attribute abgeschnitten")
        self.i += n
        return v

    def u8(self):
        return self.take(1)[0]

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def i32(self):
        return struct.unpack("<i", self.take(4))[0]

    def f32(self):
        return struct.unpack("<f", self.take(4))[0]

    def f64(self):
        return struct.unpack("<d", self.take(8))[0]

    def string(self):
        return self.take(self.u32()).decode("utf-8", "replace")


AXIS_ROT = {  # Normal-ID-Kodierung axis-aligned Rotationen (Roblox binary format)
    0x02: (1, 0, 0, 0, 1, 0, 0, 0, 1), 0x03: (1, 0, 0, 0, 0, -1, 0, 1, 0), 0x05: (1, 0, 0, 0, -1, 0, 0, 0, -1),
    0x06: (1, 0, 0, 0, 0, 1, 0, -1, 0), 0x07: (0, 1, 0, 1, 0, 0, 0, 0, -1), 0x09: (0, 0, 1, 1, 0, 0, 0, 1, 0),
    0x0A: (0, -1, 0, 1, 0, 0, 0, 0, 1), 0x0C: (0, 0, -1, 1, 0, 0, 0, -1, 0), 0x0D: (0, 1, 0, 0, 0, 1, 1, 0, 0),
    0x0E: (0, 0, -1, 0, 1, 0, 1, 0, 0), 0x10: (0, -1, 0, 0, 0, -1, 1, 0, 0), 0x11: (0, 0, 1, 0, -1, 0, 1, 0, 0),
    0x14: (-1, 0, 0, 0, 1, 0, 0, 0, -1), 0x15: (-1, 0, 0, 0, 0, 1, 0, 1, 0), 0x17: (-1, 0, 0, 0, -1, 0, 0, 0, 1),
    0x18: (-1, 0, 0, 0, 0, -1, 0, -1, 0), 0x19: (0, 1, 0, -1, 0, 0, 0, 0, 1), 0x1B: (0, 0, -1, -1, 0, 0, 0, 1, 0),
    0x1C: (0, -1, 0, -1, 0, 0, 0, 0, -1), 0x1E: (0, 0, 1, -1, 0, 0, 0, -1, 0), 0x1F: (0, 1, 0, 0, 0, -1, -1, 0, 0),
    0x20: (0, 0, 1, 0, 1, 0, -1, 0, 0), 0x22: (0, -1, 0, 0, 0, 1, -1, 0, 0), 0x23: (0, 0, -1, 0, -1, 0, -1, 0, 0),
}


def attr_value(r):
    t = r.u8()
    if t == 0x02:
        return lua_str(r.string())
    if t == 0x03:
        return "true" if r.u8() else "false"
    if t == 0x04:
        return lua_num(r.i32())
    if t == 0x05:
        return lua_num(r.f32())
    if t == 0x06:
        return lua_num(r.f64())
    if t == 0x09:
        s, o = r.f32(), r.i32()
        return "U(%s,%s)" % (lua_num(s), lua_num(o))
    if t == 0x0A:
        xs, xo, ys, yo = r.f32(), r.i32(), r.f32(), r.i32()
        return "U2(%s)" % ",".join(lua_num(v) for v in (xs, xo, ys, yo))
    if t == 0x0E:
        return "BC(%d)" % r.u32()
    if t == 0x0F:
        return "C3(%s)" % ",".join(lua_num(r.f32()) for _ in range(3))
    if t == 0x10:
        return "V2(%s)" % ",".join(lua_num(r.f32()) for _ in range(2))
    if t == 0x11:
        return "V3(%s)" % ",".join(lua_num(r.f32()) for _ in range(3))
    if t == 0x14:
        pos = [r.f32() for _ in range(3)]
        rid = r.u8()
        rot = [r.f32() for _ in range(9)] if rid == 0 else list(AXIS_ROT.get(rid, IDENTITY))
        return "CF(%s)" % ",".join(lua_num(v) for v in pos + rot)
    if t == 0x15:
        n = r.u32()
        pts = []
        for _ in range(n):
            env, tm, val = r.f32(), r.f32(), r.f32()
            pts.append("%s,%s,%s" % (lua_num(tm), lua_num(val), lua_num(env)))
        return "NS({%s})" % ",".join(pts)
    if t == 0x17:
        n = r.u32()
        pts = []
        for _ in range(n):
            _env, tm, cr, cg, cb = r.f32(), r.f32(), r.f32(), r.f32(), r.f32()
            pts.append("%s,%s,%s,%s" % tuple(lua_num(v) for v in (tm, cr, cg, cb)))
        return "CS({%s})" % ",".join(pts)
    if t == 0x19:
        a, b = r.f32(), r.f32()
        return "NR(%s,%s)" % (lua_num(a), lua_num(b))
    if t == 0x1C:
        return "RC(%s)" % ",".join(lua_num(r.f32()) for _ in range(4))
    raise ValueError("Unbekannter Attributtyp 0x%02x" % t)


def decode_attributes(text):
    data = base64.b64decode((text or "").strip() or b"")
    if not data:
        return []
    r = Reader(data)
    out = []
    for _ in range(r.u32()):
        key = r.string()
        out.append((key, attr_value(r)))
    return out


def decode_tags(text):
    data = base64.b64decode((text or "").strip() or b"")
    return [t.decode("utf-8", "replace") for t in data.split(b"\0") if t]


# ---------------------------------------------------------------- Eigenschaften
def prop_expr(el, name, refs):
    """Liefert (Name, Lua-Ausdruck) oder None."""
    tag = el.tag
    if tag in ("string", "ProtectedString"):
        return name, lua_str(el.text or "")
    if tag == "bool":
        return name, "true" if (el.text or "").strip() == "true" else "false"
    if tag in ("int", "int64", "float", "double"):
        return name, lua_num(num(el.text))
    if tag == "token":
        enum_type = TOKEN_TYPES.get(name, name)
        if enum_type is None:
            return None
        return name, enum_expr(enum_type, int(num(el.text)))
    if tag == "Vector3":
        return name, "V3(%s)" % ",".join(lua_num(num(sub(el, k))) for k in ("X", "Y", "Z"))
    if tag == "Vector2":
        return name, "V2(%s)" % ",".join(lua_num(num(sub(el, k))) for k in ("X", "Y"))
    if tag == "CoordinateFrame":
        return name, cframe_expr(el)
    if tag == "OptionalCoordinateFrame":
        cf = el.find("CFrame")
        return (name, cframe_expr(cf)) if cf is not None else None
    if tag == "Color3uint8":
        v = int(num(el.text))
        return name, "C3u(%d,%d,%d)" % ((v >> 16) & 255, (v >> 8) & 255, v & 255)
    if tag == "Color3":
        return name, "C3(%s)" % ",".join(lua_num(num(sub(el, k))) for k in ("R", "G", "B"))
    if tag == "UDim2":
        return name, "U2(%s)" % ",".join(lua_num(num(sub(el, k))) for k in ("XS", "XO", "YS", "YO"))
    if tag == "UDim":
        return name, "U(%s,%s)" % (lua_num(num(sub(el, "S"))), lua_num(num(sub(el, "O"))))
    if tag == "Ref":
        target = (el.text or "").strip()
        if not target or target == "null":
            return None
        refs.add(target)
        return name, "R(%s)" % lua_str(target)
    if tag == "NumberRange":
        v = seq_numbers(el.text)
        return name, "NR(%s,%s)" % (lua_num(v[0]), lua_num(v[1] if len(v) > 1 else v[0]))
    if tag == "NumberSequence":
        v = seq_numbers(el.text)
        pts = []
        for i in range(0, len(v) - 2, 3):
            pts.append("%s,%s,%s" % (lua_num(v[i]), lua_num(v[i + 1]), lua_num(v[i + 2])))
        return name, "NS({%s})" % ",".join(pts)
    if tag == "ColorSequence":
        v = seq_numbers(el.text)
        pts = []
        for i in range(0, len(v) - 4, 5):
            pts.append("%s,%s,%s,%s" % tuple(lua_num(x) for x in v[i:i + 4]))
        return name, "CS({%s})" % ",".join(pts)
    if tag == "Content":
        url = el.find("url")
        return name, lua_str(url.text or "") if url is not None else lua_str("")
    if tag == "BrickColor":
        return name, "BC(%d)" % int(num(el.text))
    if tag == "Rect2D":
        mn, mx = el.find("min"), el.find("max")
        vals = [num(sub(mn, "X")), num(sub(mn, "Y")), num(sub(mx, "X")), num(sub(mx, "Y"))]
        return name, "RC(%s)" % ",".join(lua_num(v) for v in vals)
    return None  # Font, Faces, Axes, PhysicalProperties, SharedString, BinaryString …


def export_tree(root):
    """Liefert (Lua-Zeilen des Baums, Anzahl Instanzen)."""
    # 1. Referenzen einsammeln (Ref-Ziele bekommen eine id)
    refs = set()
    lines = []
    count = [0]

    def node(item, depth):
        cls = item.get("class")
        if cls in SCRIPT_CLASSES:
            return None
        count[0] += 1
        props = item.find("Properties")
        name = cls
        fields = []
        attrs = []
        tags = []
        if props is not None:
            for el in props:
                pname = el.get("name")
                if pname == "Name":
                    name = el.text or ""
                    continue
                if pname == "AttributesSerialize":
                    attrs = decode_attributes(el.text)
                    continue
                if pname == "Tags":
                    tags = decode_tags(el.text)
                    continue
                if pname in SKIP:
                    continue
                if pname in RENAME:
                    pname = RENAME[pname]
                    if pname is None:
                        continue
                got = prop_expr(el, pname, refs)
                if got:
                    fields.append("%s=%s" % got if got[0].isidentifier() else "[%s]=%s" % (lua_str(got[0]), got[1]))
        kids = []
        for c in item.findall("Item"):
            k = node(c, depth + 1)
            if k is not None:
                kids.append(k)
        parts = [lua_str(cls), lua_str(name), "{" + ",".join(fields) + "}"]
        if kids:
            parts.append("{\n" + ",\n".join(kids) + "}")
        extra = []
        ref = item.get("referent")
        if attrs:
            extra.append(("attrs", "{" + ",".join("[%s]=%s" % (lua_str(k), v) for k, v in attrs) + "}"))
        if tags:
            extra.append(("tags", "{" + ",".join(lua_str(t) for t in tags) + "}"))
        return ("{" + ",".join(parts) + "".join(",%s=%s" % (k, v) for k, v in extra)
                + ("\0REF%s\0" % ref) + "}")

    services = []
    for it in root.findall("Item"):
        n = node(it, 0)
        if n is not None:
            services.append(n)
    body = ",\n".join(services)
    # 2. Nur tatsächlich referenzierte Items behalten ihre id
    out = []
    i = 0
    while True:
        j = body.find("\0REF", i)
        if j < 0:
            out.append(body[i:])
            break
        k = body.find("\0", j + 1)
        ref = body[j + 4:k]
        out.append(body[i:j])
        if ref in refs:
            out.append(",id=%s" % lua_str(ref))
        i = k + 1
    return "".join(out), count[0]


def lua_long(s):
    level = 0
    while ("]" + "=" * level + "]") in s:
        level += 1
    eq = "=" * level
    # Führender Zeilenumbruch würde von Lua verschluckt: explizit voranstellen
    return "[" + eq + "[\n" + s + "]" + eq + "]"


# ---------------------------------------------------------------- Quellen
def load_builder():
    spec = importlib.util.spec_from_file_location("build_place", BUILDER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def tree_from_sources(place_arg):
    if place_arg:
        path = Path(place_arg)
        if not path.is_absolute():
            path = Path.cwd() / path
        return ET.parse(path).getroot(), [source_entry(path)], None, path
    builder = load_builder()
    tree = builder.load_base()
    world = builder.apply_worldgen(tree)
    sources = [source_entry(BASE), source_entry(BUILDER)] + [source_entry(p) for p in worldgen_files()]
    wg = [p.relative_to(WORLDGEN).as_posix() for p in worldgen_files() if p.parent == WORLDGEN]
    return tree.getroot(), sources, wg if WORLDGEN.exists() else None, world


def lua_sources_table(sources):
    return "{\n" + ",\n".join("\t\t{path=%s,size=%d,hash=%s}" % (lua_str(s["path"]), s["size"], lua_str(s["hash"]))
                              for s in sources) + "\n\t}"


def write_tree(place_arg):
    root, sources, wg, info = tree_from_sources(place_arg)
    body, count = export_tree(root)
    wg_lua = "false" if wg is None else "{" + ",".join(lua_str(x) for x in wg) + "}"
    text = (
        "-- Automatisch erzeugt von tools/export_fixture.py. Nicht von Hand bearbeiten.\n"
        "-- Neu erzeugen: python3 tools/export_fixture.py   (tests/run_tests.lua prüft die Prüfsummen)\n"
        "-- Knoten: {Klasse, Name, {Eigenschaften}, {Kinder}?, id=Referent?, attrs={...}?, tags={...}?}\n"
        "return {\n"
        "\tformat = %d,\n"
        "\tinstances = %d,\n"
        "\tsource = %s,\n"
        "\tsources = %s,\n"
        "\tworldgen = %s,\n"
        "\tbuild = function(T)\n"
        "\t\tlocal CF, V3, V2, C3, C3u, U, U2, E, EV, R, NS, CS, NR, BC, RC = T.CF, T.V3, T.V2, T.C3, T.C3u, T.U, T.U2, T.E, T.EV, T.R, T.NS, T.CS, T.NR, T.BC, T.RC\n"
        "\t\treturn {\n%s\n\t\t}\n"
        "\tend,\n"
        "}\n"
    ) % (FORMAT, count, lua_str(place_arg or "base+worldgen"), lua_sources_table(sources), wg_lua, body)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_TREE.write_text(text, encoding="utf-8", newline="\n")
    print("Fixture geschrieben: %s (%d Instanzen, %d KB)" % (OUT_TREE.relative_to(ROOT), count, len(text.encode()) // 1024))
    if not place_arg and info:
        print("worldgen: %s" % (info,))


def write_scripts():
    tree = ET.parse(BASE)
    out = []

    def walk(item, path):
        cls = item.get("class")
        props = item.find("Properties")
        name = None
        source = ""
        for el in props if props is not None else []:
            if el.get("name") == "Name":
                name = el.text or ""
            elif el.get("name") == "Source":
                source = el.text or ""
        here = path + [cls if not path else name]
        if cls in SCRIPT_CLASSES:
            out.append((here, cls, source))
        for c in item.findall("Item"):
            walk(c, here)

    for it in tree.getroot().findall("Item"):
        walk(it, [])
    entries = []
    for path, cls, source in out:
        entries.append("\t{path={%s},class=%s,source=%s}" % (",".join(lua_str(p) for p in path), lua_str(cls),
                                                              lua_long(source)))
    text = (
        "-- Automatisch erzeugt von tools/export_fixture.py: die unveränderten 2.4.0-Skripte aus dem Basisplace.\n"
        "-- path[1] ist die Dienstklasse, danach die Namen bis zum Skript.\n"
        "return {\n\tformat = %d,\n\tsources = %s,\n\tscripts = {\n%s\n\t},\n}\n"
    ) % (FORMAT, lua_sources_table([source_entry(BASE)]), ",\n".join(entries))
    OUT_SCRIPTS.write_text(text, encoding="utf-8", newline="\n")
    print("Fixture geschrieben: %s (%d Skripte)" % (OUT_SCRIPTS.relative_to(ROOT), len(out)))


# ---------------------------------------------------------------- Prüfen
def read_header_sources(path: Path):
    """Liest sources aus einer vorhandenen Fixture (ohne Lua-Interpreter)."""
    import re
    if not path.exists():
        return None
    head = path.read_text(encoding="utf-8")[:20000]
    return re.findall(r'\{path="([^"]+)",size=(\d+),hash="([0-9a-f]+)"\}', head)


def check():
    stale = []
    for fixture in (OUT_TREE, OUT_SCRIPTS):
        entries = read_header_sources(fixture)
        if entries is None:
            stale.append("%s fehlt" % fixture.relative_to(ROOT))
            continue
        for rel, size, digest in entries:
            p = ROOT / rel
            if not p.exists():
                stale.append("%s: Quelle %s fehlt" % (fixture.name, rel))
                continue
            e = source_entry(p)
            if e["size"] != int(size) or e["hash"] != digest:
                stale.append("%s: %s geändert" % (fixture.name, rel))
        if fixture == OUT_TREE:
            recorded = {rel for rel, _, _ in entries}
            text = fixture.read_text(encoding="utf-8")[:20000]
            if 'source = "base+worldgen"' in text:
                for p in worldgen_files():
                    if p.relative_to(ROOT).as_posix() not in recorded:
                        stale.append("%s: neue worldgen-Datei %s" % (fixture.name, p.relative_to(ROOT)))
    if stale:
        print("Fixtures veraltet:\n  " + "\n  ".join(stale) + "\nNeu erzeugen: python3 tools/export_fixture.py")
        return False
    print("Fixtures aktuell")
    return True


def main():
    args = sys.argv[1:]
    if args and args[0] == "--check":
        sys.exit(0 if check() else 1)
    place = args[0] if args else None
    write_tree(place)
    write_scripts()


if __name__ == "__main__":
    main()
