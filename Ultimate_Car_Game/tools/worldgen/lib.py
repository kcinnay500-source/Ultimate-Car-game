"""Kleine Bau-API für die Stadt "Werkstattmeile" (tools/worldgen).

Alle District-Module bauen ausschließlich über diese Funktionen, damit Eigenschaften, Stil und Zählung
einheitlich bleiben. Das XML-Format entspricht exakt den Parts im 2.4.0-Basisplace
(CoordinateFrame "CFrame" mit X,Y,Z,R00..R22; Vector3 "size"; Color3uint8; token Material/shape; ...).

Koordinaten: X Ost, Y oben, Z Süd. yaw in Grad wie CFrame.Angles(0, math.rad(yaw), 0):
  yaw 0 -> lokales +Z zeigt nach Süden, yaw 90 -> +Z zeigt nach Osten, yaw 180 -> Norden, -90 -> Westen.
  Vorlagen-Autos schauen nach lokal -Z, also yaw 0 = Nase Nord, 90 = West, 180 = Süd, -90 = Ost.
Schilder zeigen ihren Text auf der +Z-Seite (SurfaceGui Face = Back, wie 2.4.0); Schild mit Text nach
Süden: yaw 0, nach Norden: 180, nach Osten: 90, nach Westen: -90.
"""
import base64
import copy
import math
import struct
import xml.etree.ElementTree as ET
from contextlib import contextmanager

# ---------------------------------------------------------------- Enums (Werte wie im Basisplace)
MATERIALS = {
    "Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528, "Marble": 784,
    "Slate": 800, "Concrete": 816, "Granite": 832, "Brick": 848, "Pebble": 864, "Cobblestone": 880,
    "CorrodedMetal": 1040, "DiamondPlate": 1056, "Foil": 1072, "Metal": 1088, "Grass": 1280, "Sand": 1296,
    "Fabric": 1312, "Asphalt": 1376, "Glass": 1568,
}
SHAPES = {"Ball": 0, "Block": 1, "Cylinder": 2}
FONTS = {"GothamBold": 19, "GothamBlack": 20, "Gotham": 17, "GothamMedium": 18, "Arcade": 13,
         "Oswald": 36, "Michroma": 34, "SciFi": 12, "Antique": 15, "Garamond": 8, "RobotoMono": 41}
FACES = {"Right": 0, "Top": 1, "Back": 2, "Left": 3, "Bottom": 4, "Front": 5}
BASEPART_CLASSES = ("Part", "WedgePart", "SpawnLocation", "CornerWedgePart", "TrussPart", "MeshPart")

# ---------------------------------------------------------------- Palette (CITY_SPEC §1.4)
SLATE = (31, 43, 55)
GRAPHITE = (42, 48, 55)
FRAME = (66, 80, 94)
TRUSS = (79, 91, 103)
STEEL = (156, 170, 177)
AMBER = (247, 176, 63)
TEAL = (47, 169, 163)
GLASS = (116, 159, 178)
YARD = (83, 88, 91)
APRON = (114, 121, 124)
ASPHALT = (46, 52, 59)
SIDEWALK = (128, 134, 138)
PLAZA = (126, 130, 128)
PLAZA_BAND = (96, 100, 102)
BLACK = (22, 26, 31)
WHITE = (224, 231, 230)
GRASS = (73, 91, 64)
HEDGE = (61, 100, 65)
FOLIAGE = [(57, 91, 58), (61, 97, 62), (65, 104, 66), (69, 111, 70)]
TRUNK = (96, 74, 56)
LAMP = (255, 224, 169)
RED = (200, 50, 50)


# ---------------------------------------------------------------- CFrame
class CF:
    """Minimaler CFrame: Position p und Rotationsmatrix R (Zeilen, wie R00..R22)."""
    __slots__ = ("p", "R")

    def __init__(self, x=0.0, y=0.0, z=0.0, R=None):
        self.p = (float(x), float(y), float(z))
        self.R = R or ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))

    # -- Konstruktoren
    @staticmethod
    def angles(rx=0.0, ry=0.0, rz=0.0):
        """wie CFrame.Angles (Bogenmaß): Rx * Ry * Rz"""
        cx, sx = math.cos(rx), math.sin(rx)
        cy, sy = math.cos(ry), math.sin(ry)
        cz, sz = math.cos(rz), math.sin(rz)
        Rx = ((1, 0, 0), (0, cx, -sx), (0, sx, cx))
        Ry = ((cy, 0, sy), (0, 1, 0), (-sy, 0, cy))
        Rz = ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))
        return CF(R=_mm(_mm(Rx, Ry), Rz))

    @staticmethod
    def yaw(deg):
        return CF.angles(0, math.radians(deg), 0)

    @staticmethod
    def at(x, y, z, yaw=0.0):
        c = CF.yaw(yaw)
        c.p = (float(x), float(y), float(z))
        return c

    @staticmethod
    def from_axes(pos, right, up, back):
        """Spalten = RightVector, UpVector, -LookVector"""
        R = tuple((right[i], up[i], back[i]) for i in range(3))
        return CF(pos[0], pos[1], pos[2], R)

    @staticmethod
    def look_at(pos, target, up=(0.0, 1.0, 0.0)):
        look = _norm(_sub(target, pos))
        right = _cross(look, up)
        if _len(right) < 1e-6:
            right = (1.0, 0.0, 0.0)
        right = _norm(right)
        up2 = _cross(right, look)
        return CF.from_axes(pos, right, up2, (-look[0], -look[1], -look[2]))

    # -- Verknüpfung
    def __mul__(self, o):
        if isinstance(o, CF):
            return CF(*_add(self.p, _mv(self.R, o.p)), R=_mm(self.R, o.R))
        return self.point(o)

    def point(self, v):
        return _add(self.p, _mv(self.R, v))

    def vector(self, v):
        return _mv(self.R, v)

    def inverse(self):
        Rt = tuple(tuple(self.R[j][i] for j in range(3)) for i in range(3))
        ip = _mv(Rt, self.p)
        return CF(-ip[0], -ip[1], -ip[2], R=Rt)

    def offset(self, dx=0.0, dy=0.0, dz=0.0):
        """wie cf * CFrame.new(dx,dy,dz)"""
        return self * CF(dx, dy, dz)

    def moved(self, dx=0.0, dy=0.0, dz=0.0):
        """Welt-Verschiebung (Rotation bleibt)"""
        return CF(self.p[0] + dx, self.p[1] + dy, self.p[2] + dz, R=self.R)

    def rotation(self):
        return CF(R=self.R)

    @property
    def look(self):
        return (-self.R[0][2], -self.R[1][2], -self.R[2][2])

    def __repr__(self):
        return "CF(%.2f,%.2f,%.2f)" % self.p


def _mm(A, B):
    return tuple(tuple(sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def _mv(A, v):
    return tuple(sum(A[i][k] * v[k] for k in range(3)) for i in range(3))


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _len(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def _norm(a):
    n = _len(a) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def yaw_towards(dx, dz):
    """yaw (Grad), bei dem die LookVector (-Z) in Richtung (dx, dz) zeigt"""
    return math.degrees(math.atan2(-dx, -dz))


def to_cf(c):
    """CF | (x,y,z) | (x,y,z,yaw) -> CF"""
    if isinstance(c, CF):
        return c
    if len(c) == 4:
        return CF.at(*c)
    return CF(*c)


def rot_point(x, z, yaw):
    """Dreht (x,z) um die Y-Achse wie CF.yaw(yaw)"""
    a = math.radians(yaw)
    return (x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a))


# ---------------------------------------------------------------- XML-Formatierung
def fnum(v):
    v = float(v)
    if abs(v) < 5e-10:
        v = 0.0
    s = ("%.6f" % v).rstrip("0")
    if s.endswith("."):
        s += "0"
    return s


def color_u8(rgb):
    r, g, b = (max(0, min(255, int(round(c)))) for c in rgb)
    return str(0xFF000000 | (r << 16) | (g << 8) | b)


def u8_color(text):
    v = int(float(text))
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def _sub_el(parent, tag, name, text=None):
    e = ET.SubElement(parent, tag, {"name": name})
    if text is not None:
        e.text = text
    return e


def _vec3_el(parent, name, v):
    e = ET.SubElement(parent, "Vector3", {"name": name})
    for k, val in zip("XYZ", v):
        ET.SubElement(e, k).text = fnum(val)
    return e


def _color3_el(parent, name, rgb):
    e = ET.SubElement(parent, "Color3", {"name": name})
    for k, val in zip("RGB", rgb):
        ET.SubElement(e, k).text = fnum(val / 255.0)
    return e


def _cf_fill(e, cf):
    for c in list(e):
        e.remove(c)
    for k, val in zip("XYZ", cf.p):
        ET.SubElement(e, k).text = fnum(val)
    for i in range(3):
        for j in range(3):
            ET.SubElement(e, "R%d%d" % (i, j)).text = fnum(cf.R[i][j])


def _cf_el(parent, name, cf):
    e = ET.SubElement(parent, "CoordinateFrame", {"name": name})
    _cf_fill(e, cf)
    return e


def _udim2_el(parent, name, xs, xo, ys, yo):
    e = ET.SubElement(parent, "UDim2", {"name": name})
    for k, val in (("XS", xs), ("XO", xo), ("YS", ys), ("YO", yo)):
        ET.SubElement(e, k).text = fnum(val) if k.endswith("S") else str(int(val))
    return e


def props(item):
    return item.find("Properties")


def get_prop(item, name):
    p = props(item)
    if p is None:
        return None
    for c in p:
        if c.get("name") == name:
            return c
    return None


def name_of(item):
    e = get_prop(item, "Name")
    return e.text if e is not None else None


def read_cf(item, name="CFrame"):
    e = get_prop(item, name)
    if e is None:
        return None
    v = {c.tag: float(c.text) for c in e}
    R = tuple(tuple(v["R%d%d" % (i, j)] for j in range(3)) for i in range(3))
    return CF(v["X"], v["Y"], v["Z"], R)


def write_cf(item, cf, name="CFrame"):
    e = get_prop(item, name)
    if e is None:
        e = _cf_el(props(item), name, cf)
    else:
        _cf_fill(e, cf)


def read_size(item):
    e = get_prop(item, "size")
    if e is None:
        return None
    v = {c.tag: float(c.text) for c in e}
    return (v["X"], v["Y"], v["Z"])


def write_size(item, size):
    e = get_prop(item, "size")
    for c in list(e):
        e.remove(c)
    for k, val in zip("XYZ", size):
        ET.SubElement(e, k).text = fnum(val)


def set_scalar(item, tag, name, text):
    e = get_prop(item, name)
    if e is None:
        e = _sub_el(props(item), tag, name)
    e.text = text


def children(item):
    return item.findall("Item")


def child(item, name):
    for c in item.findall("Item"):
        if name_of(c) == name:
            return c
    return None


def is_basepart(item):
    return item.get("class") in BASEPART_CLASSES


def aabb(item):
    """Welt-AABB eines BaseParts: (x0,x1,y0,y1,z0,z1)"""
    cf, s = read_cf(item), read_size(item)
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    ext = [abs(cf.R[i][0]) * hx + abs(cf.R[i][1]) * hy + abs(cf.R[i][2]) * hz for i in range(3)]
    return (cf.p[0] - ext[0], cf.p[0] + ext[0], cf.p[1] - ext[1], cf.p[1] + ext[1], cf.p[2] - ext[2], cf.p[2] + ext[2])


# ---------------------------------------------------------------- Attribute (AttributesSerialize)
class Color3:
    def __init__(self, r, g, b):
        self.rgb = (r, g, b)


class Vec3:
    def __init__(self, x, y, z):
        self.v = (x, y, z)


def _attr_bytes(attrs):
    out = [struct.pack("<I", len(attrs))]
    for key, val in attrs.items():
        kb = key.encode("utf-8")
        out.append(struct.pack("<I", len(kb)) + kb)
        if isinstance(val, bool):
            out.append(b"\x03" + (b"\x01" if val else b"\x00"))
        elif isinstance(val, (int, float)):
            out.append(b"\x06" + struct.pack("<d", float(val)))
        elif isinstance(val, str):
            vb = val.encode("utf-8")
            out.append(b"\x02" + struct.pack("<I", len(vb)) + vb)
        elif isinstance(val, Color3):
            out.append(b"\x0f" + struct.pack("<fff", *(c / 255.0 for c in val.rgb)))
        elif isinstance(val, Vec3):
            out.append(b"\x11" + struct.pack("<fff", *val.v))
        else:
            raise TypeError("Attributtyp nicht unterstützt: %r" % (val,))
    return b"".join(out)


def _attr_decode(text):
    data = base64.b64decode((text or "").strip() or b"")
    out = {}
    if not data:
        return out
    i = 0

    def take(n):
        nonlocal i
        v = data[i:i + n]
        i += n
        return v
    for _ in range(struct.unpack("<I", take(4))[0]):
        key = take(struct.unpack("<I", take(4))[0]).decode("utf-8")
        t = take(1)[0]
        if t == 0x02:
            out[key] = take(struct.unpack("<I", take(4))[0]).decode("utf-8")
        elif t == 0x03:
            out[key] = bool(take(1)[0])
        elif t == 0x06:
            out[key] = struct.unpack("<d", take(8))[0]
        elif t == 0x05:
            out[key] = struct.unpack("<f", take(4))[0]
        elif t == 0x0F:
            out[key] = Color3(*(round(c * 255) for c in struct.unpack("<fff", take(12))))
        elif t == 0x11:
            out[key] = Vec3(*struct.unpack("<fff", take(12)))
        else:
            raise ValueError("Attributtyp 0x%02x" % t)
    return out


def get_attrs(item):
    e = get_prop(item, "AttributesSerialize")
    return _attr_decode(e.text) if e is not None else {}


def set_attrs(item, attrs):
    """Setzt/ergänzt Attribute (bestehende bleiben erhalten)."""
    merged = get_attrs(item)
    merged.update(attrs)
    set_scalar(item, "BinaryString", "AttributesSerialize", base64.b64encode(_attr_bytes(merged)).decode("ascii"))


# ---------------------------------------------------------------- Builder
class Lib:
    """Bau-API. Eine Instanz pro Build (hält new_referent, Budget und Baum)."""

    CF = CF

    def __init__(self, tree, new_referent):
        self.tree = tree
        self.root = tree.getroot()
        self.ref = new_referent
        self.counts = {}        # Abschnitt -> Parts
        self.lights = {}        # Abschnitt -> Lichter
        self.cars = {}          # Abschnitt -> Vorlagen-Autos
        self._section = ["Sonstiges"]
        self._templates = None

    # ---------------------------------------------------- Budget
    @contextmanager
    def section(self, name):
        self._section.append(name)
        try:
            yield
        finally:
            self._section.pop()

    def _count(self, table, n=1):
        s = self._section[-1]
        table[s] = table.get(s, 0) + n

    def budget_report(self):
        rows = []
        for s in sorted(set(self.counts) | set(self.lights)):
            rows.append("%s: %d Parts, %d Lichter%s" % (s, self.counts.get(s, 0), self.lights.get(s, 0),
                                                       ", %d Autos" % self.cars[s] if self.cars.get(s) else ""))
        return rows

    # ---------------------------------------------------- Grundbausteine
    def item(self, parent, cls, name):
        it = ET.Element("Item", {"class": cls, "referent": self.ref()})
        p = ET.SubElement(it, "Properties")
        _sub_el(p, "string", "Name", name)
        if parent is not None:
            parent.append(it)
        return it

    def folder(self, parent, name):
        """Ordner holen oder anlegen"""
        ex = child(parent, name)
        if ex is not None:
            return ex
        return self.item(parent, "Folder", name)

    def model(self, parent, name, attrs=None, primary=None):
        m = self.item(parent, "Model", name)
        if primary is not None:
            self.set_primary(m, primary)
        if attrs:
            set_attrs(m, attrs)
        return m

    def set_primary(self, model, part):
        e = get_prop(model, "PrimaryPart")
        if e is None:
            e = _sub_el(props(model), "Ref", "PrimaryPart")
        e.text = part.get("referent")

    def attrs(self, item, **kw):
        set_attrs(item, kw)
        return item

    def part(self, parent, name, size, cf, color=SLATE, material="SmoothPlastic", transparency=0.0,
             shape="Block", collide=True, anchored=True, reflectance=0.0, deco=False, attrs=None,
             cast_shadow=None, touch=None, query=None, cls="Part"):
        """Ein BasePart. cf: CF | (x,y,z) | (x,y,z,yaw). deco=True: CanCollide/CanTouch/CanQuery/CastShadow aus."""
        cf = to_cf(cf)
        if deco:
            collide = False
            touch = False if touch is None else touch
            query = False if query is None else query
            cast_shadow = False if cast_shadow is None else cast_shadow
        touch = True if touch is None else touch
        query = True if query is None else query
        if cast_shadow is None:
            cast_shadow = transparency < 0.95
        it = self.item(parent, cls, name)
        p = props(it)
        _sub_el(p, "bool", "Anchored", "true" if anchored else "false")
        _sub_el(p, "bool", "CanCollide", "true" if collide else "false")
        _sub_el(p, "bool", "CanTouch", "true" if touch else "false")
        _sub_el(p, "bool", "CanQuery", "true" if query else "false")
        _sub_el(p, "bool", "CastShadow", "true" if cast_shadow else "false")
        _sub_el(p, "float", "Transparency", fnum(transparency))
        _sub_el(p, "Color3uint8", "Color3uint8", color_u8(color))
        _sub_el(p, "token", "Material", str(MATERIALS[material]))
        _vec3_el(p, "size", size)
        _sub_el(p, "token", "TopSurface", "0")
        _sub_el(p, "token", "BottomSurface", "0")
        if cls in ("Part", "SpawnLocation"):
            _sub_el(p, "token", "shape", str(SHAPES[shape]))
        _cf_el(p, "CFrame", cf)
        if reflectance:
            _sub_el(p, "float", "Reflectance", fnum(reflectance))
        if attrs:
            set_attrs(it, attrs)
        self._count(self.counts)
        return it

    def box(self, parent, name, x0, x1, y0, y1, z0, z1, color=SLATE, material="SmoothPlastic", **kw):
        """Achsparalleler Quader aus Weltgrenzen"""
        return self.part(parent, name, (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
                         CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, **kw)

    def wedge(self, parent, name, size, cf, color=SLATE, material="SmoothPlastic", **kw):
        """WedgePart: volle Höhe bei lokal +Z, Schräge nach vorn-oben (-Z, +Y)"""
        return self.part(parent, name, size, cf, color, material, cls="WedgePart", **kw)

    def cylinder(self, parent, name, center, length, diameter, axis="Y", color=STEEL, material="Metal",
                 yaw=0.0, **kw):
        """Zylinder; axis 'Y' (senkrecht), 'X' oder 'Z' (liegend, nach yaw gedreht)."""
        cx, cy, cz = center
        if axis == "Y":
            cf = CF(cx, cy, cz) * CF.angles(0, math.radians(yaw), math.pi / 2)
        elif axis == "Z":
            cf = CF(cx, cy, cz) * CF.yaw(yaw + 90)
        else:
            cf = CF(cx, cy, cz) * CF.yaw(yaw)
        return self.part(parent, name, (length, diameter, diameter), cf, color, material, shape="Cylinder", **kw)

    def ball(self, parent, name, center, diameter, color=AMBER, material="Neon", **kw):
        return self.part(parent, name, (diameter, diameter, diameter), CF(*center), color, material,
                         shape="Ball", **kw)

    def beam(self, parent, name, a, b, thickness, color=STEEL, material="Metal", depth=None, **kw):
        """Quader von Punkt a nach Punkt b (Länge entlang lokal Z)"""
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
        length = _len(_sub(b, a))
        d = _norm(_sub(b, a))
        up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.99 else (1.0, 0.0, 0.0)
        cf = CF.look_at(mid, _add(mid, d), up)
        return self.part(parent, name, (thickness, depth or thickness, length), cf, color, material, **kw)

    def flat_tri(self, parent, name, right, a, b, y0, y1, color=SIDEWALK, material="Concrete", **kw):
        """Liegender Keil (Dreieck in der XZ-Ebene) von y0 bis y1.
        right = Ecke mit rechtem Winkel, a/b = die beiden anderen Ecken (je (x,z))."""
        R3 = (right[0], 0.0, right[1])
        A3 = (a[0], 0.0, a[1])
        B3 = (b[0], 0.0, b[1])
        # WedgePart-Querschnitt (lokal y,z): rechter Winkel bei (-h,+d), Ecken (-h,-d) und (+h,+d)
        ez = _norm(_sub(R3, A3))          # von (-h,-d) nach (-h,+d)
        ey = _norm(_sub(B3, R3))          # von (-h,+d) nach (+h,+d)
        ex = _cross(ey, ez)
        sy, sz = _len(_sub(B3, R3)), _len(_sub(R3, A3))
        c = _add(_add(R3, tuple(v * sy / 2 for v in ey)), tuple(-v * sz / 2 for v in ez))
        cf = CF.from_axes((c[0], (y0 + y1) / 2, c[2]), ex, ey, ez)
        return self.part(parent, name, (abs(y1 - y0), sy, sz), cf, color, material, cls="WedgePart", **kw)

    def convex_slab(self, parent, name, pts, y0, y1, color=SIDEWALK, material="Concrete", **kw):
        """Liegende Platte mit konvexem Grundriss pts [(x,z), ...] von y0 bis y1: Fächer-Dreiecke, jedes an seiner
        Höhe in 2 rechtwinklige Keile geteilt (2 * (n - 2) WedgeParts, lückenlos, ohne Überlappung)."""
        out = []
        for i in range(1, len(pts) - 1):
            tri = [pts[0], pts[i], pts[i + 1]]
            # Höhe von der Ecke gegenüber der längsten Seite fällen (Fußpunkt liegt dann auf dieser Seite)
            k = max(range(3), key=lambda j: math.dist(tri[(j + 1) % 3], tri[(j + 2) % 3]))
            p, q, r = tri[k], tri[(k + 1) % 3], tri[(k + 2) % 3]
            qr = (r[0] - q[0], r[1] - q[1])
            ln2 = qr[0] ** 2 + qr[1] ** 2
            if ln2 < 1e-9:
                continue
            t = ((p[0] - q[0]) * qr[0] + (p[1] - q[1]) * qr[1]) / ln2
            f = (q[0] + t * qr[0], q[1] + t * qr[1])
            if math.dist(p, f) < 1e-4:
                continue
            for c in (q, r):
                if math.dist(c, f) > 1e-4:
                    out.append(self.flat_tri(parent, name, f, c, p, y0, y1, color, material, **kw))
        return out

    def ring_slab(self, parent, name, cx, cz, r_in, r_out, n, y0, y1, color=SIDEWALK, material="Concrete",
                  phase=0.0, skip=(), **kw):
        """Vieleck-Ring aus n Trapez-Sektoren (Apothemen r_in..r_out) ohne Überlappung: je Sektor ein Quader mit der
        inneren Sehnenbreite + 2 Keile für die Aufweitung; alle Oberseiten auf y1. phase = Winkel der ersten
        Sektormitte (Grad, 0 = +X, 90 = +Z); skip = Indizes ausgelassener Sektoren."""
        out = []
        half = math.pi / n
        wi, wo = r_in * math.tan(half), r_out * math.tan(half)
        for k in range(n):
            if k in skip:
                continue
            a = math.radians(phase) + 2 * half * k
            ux, uz = math.cos(a), math.sin(a)
            tx, tz = -uz, ux

            def w(rad, t):
                return (cx + ux * rad + tx * t, cz + uz * rad + tz * t)
            rm = (r_in + r_out) / 2
            out.append(self.part(parent, name, (2 * wi, y1 - y0, r_out - r_in),
                                 CF.at(cx + ux * rm, (y0 + y1) / 2, cz + uz * rm, yaw_towards(ux, uz)), color,
                                 material, **kw))
            for sgn in (-1, 1):
                out.append(self.flat_tri(parent, name, w(r_out, sgn * wi), w(r_in, sgn * wi), w(r_out, sgn * wo),
                                         y0, y1, color, material, **kw))
        return out

    # ---------------------------------------------------- GUI / Licht / Prompt
    def surface_text(self, part, text, face="Back", canvas=None, text_color=AMBER, font="GothamBold",
                     name="SurfaceGui", label="Label", bg=None, size=(0.96, 0.88), pos=(0.02, 0.06),
                     px_per_stud=40):
        """SurfaceGui + TextLabel exakt wie die 2.4.0-Schilder (LightInfluence 0, TextScaled, GothamBold)."""
        if canvas is None:
            s = read_size(part)
            w, h = {"Back": (s[0], s[1]), "Front": (s[0], s[1]), "Left": (s[2], s[1]), "Right": (s[2], s[1]),
                    "Top": (s[0], s[2]), "Bottom": (s[0], s[2])}[face]
            canvas = (max(50, round(w * px_per_stud)), max(20, round(h * px_per_stud)))
        gui = self.item(part, "SurfaceGui", name)
        p = props(gui)
        _sub_el(p, "token", "Face", str(FACES[face]))
        _sub_el(p, "token", "SizingMode", "0")
        v = ET.SubElement(p, "Vector2", {"name": "CanvasSize"})
        ET.SubElement(v, "X").text = str(int(canvas[0]))
        ET.SubElement(v, "Y").text = str(int(canvas[1]))
        _sub_el(p, "float", "LightInfluence", "0")
        _sub_el(p, "bool", "AlwaysOnTop", "false")
        if text is not None:
            self.text_label(gui, text, text_color, font, label, bg, size, pos)
        return gui

    def text_label(self, gui, text, text_color=AMBER, font="GothamBold", name="Label", bg=None,
                   size=(0.96, 0.88), pos=(0.02, 0.06)):
        lab = self.item(gui, "TextLabel", name)
        p = props(lab)
        _udim2_el(p, "Size", size[0], 0, size[1], 0)
        _udim2_el(p, "Position", pos[0], 0, pos[1], 0)
        _sub_el(p, "float", "BackgroundTransparency", "1" if bg is None else "0")
        if bg is not None:
            _color3_el(p, "BackgroundColor3", bg)
            _sub_el(p, "int", "BorderSizePixel", "0")
        _sub_el(p, "string", "Text", text)
        _sub_el(p, "bool", "TextScaled", "true")
        _sub_el(p, "bool", "TextWrapped", "true")
        _sub_el(p, "token", "Font", str(FONTS[font]))
        _color3_el(p, "TextColor3", text_color)
        return lab

    def sign(self, parent, text, size, cf, text_color=AMBER, bg_color=SLATE, font="GothamBold", name="Sign",
             thickness=0.2, bolts=True, sub=None, sub_color=WHITE, material="SmoothPlastic", collide=False):
        """Schildplatte (Text auf der +Z-Seite von cf) mit SurfaceGui und 4 Stahl-Eckbolzen.
        size = (Breite, Höhe). sub = optionale zweite Zeile (kleiner, sekundäre Farbe)."""
        cf = to_cf(cf)
        w, h = size
        plate = self.part(parent, name, (w, h, thickness), cf, bg_color, material, deco=not collide,
                          collide=collide)
        if sub:
            gui = self.surface_text(plate, None)
            self.text_label(gui, text, text_color, font, "Label", None, (0.96, 0.56), (0.02, 0.05))
            self.text_label(gui, sub, sub_color, font, "Sub", None, (0.9, 0.3), (0.05, 0.64))
        else:
            self.surface_text(plate, text, text_color=text_color, font=font)
        if bolts and w >= 1.5 and h >= 1.0:
            ix, iy = min(1.0, w * 0.1), min(0.25, h * 0.1)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    self.part(parent, "SignBolt", (0.17, 0.17, 0.08),
                              cf * CF(sx * (w / 2 - ix), sy * (h / 2 - iy), thickness / 2 + 0.04),
                              STEEL, "Metal", deco=True)
        return plate

    def point_light(self, part, range_=26, brightness=0.9, color=LAMP, shadows=False, name="Light"):
        lt = self.item(part, "PointLight", name)
        p = props(lt)
        _sub_el(p, "float", "Range", fnum(range_))
        _sub_el(p, "float", "Brightness", fnum(brightness))
        _color3_el(p, "Color", color)
        _sub_el(p, "bool", "Shadows", "true" if shadows else "false")
        self._count(self.lights)
        return lt

    def spot_light(self, part, range_=30, brightness=1.4, color=(255, 244, 230), angle=60, face="Bottom",
                   shadows=True, name="Spot"):
        lt = self.item(part, "SpotLight", name)
        p = props(lt)
        _sub_el(p, "float", "Range", fnum(range_))
        _sub_el(p, "float", "Brightness", fnum(brightness))
        _color3_el(p, "Color", color)
        _sub_el(p, "float", "Angle", fnum(angle))
        _sub_el(p, "token", "Face", str(FACES[face]))
        _sub_el(p, "bool", "Shadows", "true" if shadows else "false")
        self._count(self.lights)
        return lt

    def prompt(self, part, action_text="Öffnen", object_text="", key="E", hold=0.25, range_=10, los=False):
        pr = self.item(part, "ProximityPrompt", "ProximityPrompt")
        p = props(pr)
        _sub_el(p, "string", "ActionText", action_text)
        _sub_el(p, "string", "ObjectText", object_text)
        _sub_el(p, "float", "HoldDuration", fnum(hold))
        _sub_el(p, "float", "MaxActivationDistance", fnum(range_))
        _sub_el(p, "bool", "RequiresLineOfSight", "true" if los else "false")
        _sub_el(p, "bool", "ClickablePrompt", "true")
        _sub_el(p, "token", "KeyboardKeyCode", str(ord(key.lower())))
        _sub_el(p, "token", "GamepadKeyCode", "1002")
        return pr

    def attachment(self, part, name, local_cf):
        at = self.item(part, "Attachment", name)
        _cf_el(props(at), "CFrame", to_cf(local_cf))
        return at

    def spawn(self, parent, name, size, cf, color=TEAL, enabled=True):
        """SpawnLocation (unsichtbar). enabled=False: der Server entscheidet (Zonen-Spawns, PHASE4_CONTRACT §5)."""
        it = self.part(parent, name, size, cf, color, "SmoothPlastic", transparency=1, collide=False,
                       touch=False, query=False, cast_shadow=False, cls="SpawnLocation")
        p = props(it)
        _sub_el(p, "bool", "Neutral", "true")
        _sub_el(p, "bool", "Enabled", "true" if enabled else "false")
        _sub_el(p, "int", "Duration", "0")
        _sub_el(p, "bool", "AllowTeamChangeOnTouch", "false")
        return it

    # ---------------------------------------------------- Autos
    def templates(self):
        if self._templates is None:
            self._templates = {}
            ss = next(i for i in self.root.findall("Item") if i.get("class") == "ServerStorage")
            ct = child(ss, "CarTemplates")
            for m in children(ct):
                self._templates[name_of(m)] = m
        return self._templates

    def clone_car(self, parent, template, cf, paint=TEAL, name=None, attrs=None, hide=(), extra_color=None):
        """Tiefe Kopie von ServerStorage.CarTemplates.<template> mit frischen Referents.
        Jede BasePart-CFrame wird wie bei PivotTo transformiert (Root liegt im Ursprung): new = cf * old.
        Paint/Hood/Mirror werden wie in CarFactory.Spawn umgefärbt. hide = Namenspräfixe, die unsichtbar werden."""
        cf = to_cf(cf)
        src = self.templates()[template]
        m = copy.deepcopy(src)
        remap = {}
        for it in m.iter("Item"):
            old = it.get("referent")
            new = self.ref()
            remap[old] = new
            it.set("referent", new)
        for it in m.iter("Item"):
            for e in props(it):
                if e.tag == "Ref" and (e.text or "") in remap:
                    e.text = remap[e.text]
            if is_basepart(it):
                write_cf(it, cf * read_cf(it))
                nm = name_of(it)
                if nm in ("Paint", "Hood", "Mirror"):
                    set_scalar(it, "Color3uint8", "Color3uint8", color_u8(paint))
                if hide and any(nm.startswith(h) for h in hide):
                    set_scalar(it, "float", "Transparency", "1")
                    set_scalar(it, "bool", "CanCollide", "false")
                self._count(self.counts)
        set_scalar(m, "string", "Name", name or template)
        if attrs:
            set_attrs(m, attrs)
        set_attrs(m, {"Body": template})
        parent.append(m)
        self._count(self.cars)
        return m

    LITE_KEEP = ("Root", "Chassis", "Paint", "Hood", "SideGlass", "FrontQuarterGlass", "RearQuarterGlass",
                 "Windscreen", "RearGlass", "Bumper", "Headlamp", "TailLamp")

    def lite_car(self, parent, template, cf, paint=TEAL, name=None, attrs=None):
        """"Lite"-Auto (~35 Parts) aus ServerStorage.CarTemplates.<template>: nur Karosserie (Paint/Hood), Chassis,
        Verglasung, Stoßfänger, Lampen und die 4 Reifen - ohne Motorraum, Felgendetails, Innenraum und Messpunkte.
        Maße und Farben stammen 1:1 aus der Vorlage (umgefärbt wie clone_car)."""
        m = self.clone_car(parent, template, cf, paint, name, attrs)
        removed = 0
        for it in list(children(m)):
            if not is_basepart(it):
                continue
            nm = name_of(it)
            if nm in self.LITE_KEEP or nm.endswith("Tire"):
                continue
            m.remove(it)
            removed += 1
        self._count(self.counts, -removed)
        set_attrs(m, {"Lite": True})
        return m

    # ---------------------------------------------------- Deko-Rezepte
    def tree_lite(self, parent, x, y, z, scale=1.0, seed=0, name="Baum"):
        """Leichter Baum, 11 Parts: Stamm, 2 Äste, 8 Laub-Keile (2.4.0-Stil)"""
        m = self.model(parent, name)
        s = scale
        self.cylinder(m, "Trunk", (x, y + 4.5 * s, z), 9 * s, 1.1 * s, "Y", TRUNK, "Wood", deco=False)
        for ang in ((seed * 40 + 20) % 360, (seed * 40 + 145) % 360):
            a = math.radians(ang)
            dx, dz = math.cos(a) * 1.4 * s, math.sin(a) * 1.4 * s
            self.beam(m, "Branch", (x, y + 5.5 * s, z), (x + dx, y + 7.8 * s, z + dz), 0.5 * s, TRUNK, "Wood",
                      deco=True)
        # Krone: 2 Stufen aus je 4 nach außen geneigten Keilen (Walmdach-Pyramide), obere Stufe 45° versetzt
        for tier, (y0, h, d, rot) in enumerate(((5.2, 4.6, 3.7, seed * 17), (8.6, 4.0, 2.6, seed * 17 + 45))):
            for k in range(4):
                a = math.radians(rot + k * 90)
                ox, oz = math.cos(a), math.sin(a)
                cf = CF.at(x + ox * d * s / 2, y + (y0 + h / 2) * s, z + oz * d * s / 2, yaw_towards(ox, oz))
                col = FOLIAGE[(k + tier * 2 + seed) % 4]
                self.wedge(m, "Foliage", (2 * d * s, h * s, d * s), cf, col, "Grass", deco=True)
        return m

    def street_lamp(self, parent, x, z, base_y, dir_x, dir_z, name="Strassenlaterne", range_=26, brightness=0.9):
        """2.4.0-Laterne (4 Parts): Sockel, 12,5-Mast, Ausleger, Kopf (255,224,169) mit PointLight.
        (dir_x, dir_z) = Richtung des Auslegers (zur Fahrbahn)."""
        m = self.model(parent, name)
        self.box(m, "LampBase", x - 0.6, x + 0.6, base_y, base_y + 0.8, z - 0.6, z + 0.6, BLACK, "Metal")
        self.cylinder(m, "LampPost", (x, base_y + 0.8 + 6.25, z), 12.5, 0.45, "Y", STEEL, "Metal")
        top = base_y + 0.8 + 12.5
        hx, hz = x + dir_x * 2.2, z + dir_z * 2.2
        self.beam(m, "LampArm", (x, top - 0.2, z), (hx, top - 0.2, hz), 0.25, STEEL, "Metal", deco=True)
        head = self.part(m, "LampHead", (1.6, 0.35, 1.6), CF.at(hx, top - 0.5, hz, yaw_towards(dir_x, dir_z)),
                         LAMP, "SmoothPlastic", deco=True)
        set_attrs(head, {"NightNeon": True})
        self.point_light(head, range_, brightness, LAMP)
        return m

    def cone(self, parent, x, y, z, name="Pylone"):
        """Leitkegel, 2 Parts"""
        m = self.model(parent, name)
        self.box(m, "ConeBase", x - 0.7, x + 0.7, y, y + 0.15, z - 0.7, z + 0.7, (225, 95, 30), "Plastic",
                 deco=True)
        self.cylinder(m, "ConeBody", (x, y + 0.15 + 0.8, z), 1.6, 0.7, "Y", (240, 110, 35), "Plastic", deco=True)
        return m
