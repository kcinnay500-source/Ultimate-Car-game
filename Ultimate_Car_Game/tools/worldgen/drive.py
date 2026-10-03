"""Befahrbarkeit der Stadt (ohne Roblox): senkrechte Strahlen durch alle kollidierenden Parts.

Ein Auto fährt eine Linie in Spuren (seitlicher Versatz) ab. Je Probe (alle 0.5 Studs) wird der Boden bestimmt:
die höchste Oberseite, die höchstens STEP (0.6) über dem bisherigen Boden liegt. Jeder kollidierende Part, der
zwischen Boden + STEP und Boden + CLEAR (Fahrzeughöhe) in die Spur ragt, ist ein Hindernis (Bordstein > 0.6,
Pfosten, Wand, unsichtbare Wand ...). Deko-Parts mit CanCollide false zählen nicht, genau wie in Roblox.

Genutzt von checks.py (Fahrschleifen, Spawn-Ausfahrten, Plot-Einfahrten) und tests/test_worldgen_drive.py.
"""
import math
from collections import defaultdict

STEP = 0.6          # höchste erlaubte Stufe auf einer Fahrlinie
CLEAR = 6.8         # lichte Höhe über dem Boden, die frei sein muss (höchste Karosserie 6.62)
SAMPLE = 0.5
CELL = 8.0
CAR_HALF_W = 5.2    # halbe Breite der Vorlagen-Autos (X -5.08..4.92)
CAR_HALF_L = 9.8    # halbe Länge (Z -8.1..9.71)


def _slab(o, d, lo, hi, t0, t1):
    """Strahl o + t d gegen lo <= x <= hi (eine Achse) -> (t0, t1) verengt oder None"""
    if abs(d) < 1e-9:
        if o < lo - 1e-9 or o > hi + 1e-9:
            return None
        return t0, t1
    a, b = (lo - o) / d, (hi - o) / d
    if a > b:
        a, b = b, a
    t0, t1 = max(t0, a), min(t1, b)
    return (t0, t1) if t0 <= t1 else None


def _quad(a, b, c, t0, t1):
    """a t² + b t + c <= 0 innerhalb (t0, t1)"""
    if abs(a) < 1e-12:
        if abs(b) < 1e-12:
            return (t0, t1) if c <= 0 else None
        r = -c / b
        return _slab(0, 1, -1e18, r, t0, t1) if b > 0 else _slab(0, 1, r, 1e18, t0, t1)
    disc = b * b - 4 * a * c
    if disc < 0:
        return None
    s = math.sqrt(disc)
    r0, r1 = sorted(((-b - s) / (2 * a), (-b + s) / (2 * a)))
    t0, t1 = max(t0, r0), min(t1, r1)
    return (t0, t1) if t0 <= t1 else None


def vertical_interval(p, x, z, inv=None):
    """Y-Intervall (lo, hi), in dem die Senkrechte durch (x, z) im Part p liegt, oder None"""
    inv = inv or p.cf.inverse()
    o = inv.point((x, 0.0, z))
    d = inv.vector((0.0, 1.0, 0.0))
    hx, hy, hz = p.size[0] / 2, p.size[1] / 2, p.size[2] / 2
    t0, t1 = -1e9, 1e9
    if p.cls == "Part" and p.shape == 0:       # Kugel
        r = p.size[0] / 2
        res = _quad(sum(v * v for v in d), 2 * sum(o[i] * d[i] for i in range(3)), sum(v * v for v in o) - r * r,
                    t0, t1)
        return res
    if p.cls == "Part" and p.shape == 2:       # Zylinder, Achse lokal X
        r = p.size[1] / 2
        s = _slab(o[0], d[0], -hx, hx, t0, t1)
        if s is None:
            return None
        return _quad(d[1] ** 2 + d[2] ** 2, 2 * (o[1] * d[1] + o[2] * d[2]), o[1] ** 2 + o[2] ** 2 - r * r, *s)
    s = (t0, t1)
    for i, h in enumerate((hx, hy, hz)):
        s = _slab(o[i], d[i], -h, h, *s)
        if s is None:
            return None
    if p.cls == "WedgePart":
        # innen: y * hz - z * hy <= 0 (Schräge von (-hy, -hz) nach (+hy, +hz))
        a = d[1] * hz - d[2] * hy
        c = o[1] * hz - o[2] * hy
        s = _slab(0, 1, -1e18, 1e18, *s)
        if abs(a) < 1e-12:
            if c > 1e-9:
                return None
        else:
            r = -c / a
            s = _slab(0, 1, -1e18, r, *s) if a > 0 else _slab(0, 1, r, 1e18, *s)
            if s is None:
                return None
    if p.cls == "CornerWedgePart":
        return s   # grob (kommt in der Stadt nicht vor)
    return s


class World:
    """Kollidierende Parts in einem XZ-Raster für schnelle Senkrechten-Abfragen."""

    def __init__(self, parts, skip_prefix=("City.Animated.Verkehr", "City.CarSpawns", "City.Track")):
        self.items = []
        self.grid = defaultdict(list)
        for p in parts:
            if not p.collide or p.path.startswith(skip_prefix) or p.car and p.path.startswith("City.Animated"):
                continue
            k = len(self.items)
            b = p.aabb()
            self.items.append((p, p.cf.inverse(), b))
            for gx in range(int(math.floor(b[0] / CELL)), int(math.floor(b[1] / CELL)) + 1):
                for gz in range(int(math.floor(b[4] / CELL)), int(math.floor(b[5] / CELL)) + 1):
                    self.grid[(gx, gz)].append(k)

    def column(self, x, z):
        out = []
        for k in self.grid.get((int(math.floor(x / CELL)), int(math.floor(z / CELL))), ()):
            p, inv, b = self.items[k]
            if not (b[0] - 1e-6 <= x <= b[1] + 1e-6 and b[4] - 1e-6 <= z <= b[5] + 1e-6):
                continue
            iv = vertical_interval(p, x, z, inv)
            if iv is not None:
                out.append((iv[0], iv[1], p))
        return out

    def ground(self, x, z, near_y, step=STEP):
        """Höchste Oberseite <= near_y + step (None, wenn nichts darunter liegt)"""
        best = None
        for lo, hi, p in self.column(x, z):
            if hi <= near_y + step + 1e-4 and (best is None or hi > best):
                best = hi
        return best

    def obstacles(self, x, z, g, step=STEP, clear=CLEAR):
        return [(lo, hi, p) for lo, hi, p in self.column(x, z) if hi > g + step + 1e-3 and lo < g + clear]


def polyline_samples(pts, closed=False, step=SAMPLE):
    """[(x, z, dx, dz)] entlang der Linie"""
    segs = list(zip(pts, pts[1:] + (pts[:1] if closed else [])))
    out = []
    for a, b in segs:
        ln = math.dist(a, b)
        if ln < 1e-6:
            continue
        dx, dz = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        n = max(1, int(ln / step))
        for k in range(n):
            f = k / n
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, dx, dz))
    if not closed and segs:
        a, b = segs[-1]
        ln = max(1e-6, math.dist(a, b))
        out.append((b[0], b[1], (b[0] - a[0]) / ln, (b[1] - a[1]) / ln))
    return out


def drive(world, pts, start_y, closed=False, offsets=(-5.0, 0.0, 5.0), step=STEP, clear=CLEAR):
    """Fährt die Linie in allen Spuren ab. Rückgabe: Liste von Problemen
    (Art, x, z, Spur, Detail) mit Art 'kein Boden' | 'Hindernis'. Je Spur und Part nur die erste Stelle."""
    samples = polyline_samples(list(pts), closed)
    problems = []
    for off in offsets:
        g = None
        seen = set()
        for x0, z0, dx, dz in samples:
            x, z = x0 - dz * off, z0 + dx * off          # rechts von der Fahrtrichtung = +off
            ng = world.ground(x, z, start_y if g is None else g, step)
            if ng is None or (g is not None and ng < g - 3.0):
                key = ("kein Boden", round(x / 20), round(z / 20))
                if key not in seen:
                    seen.add(key)
                    problems.append(("kein Boden", round(x, 1), round(z, 1), off, "Boden bei %s" % (
                        "?" if g is None else "%.2f" % g)))
                continue
            g = ng
            for lo, hi, p in world.obstacles(x, z, g, step, clear):
                if id(p.item) in seen:
                    continue
                seen.add(id(p.item))
                problems.append(("Hindernis", round(x, 1), round(z, 1), off,
                                 "%s (%.2f..%.2f über Boden %.2f)" % (p.path, lo, hi, g)))
    return problems


def footprint_blockers(world, x, floor, z, yaw_deg, half_w=CAR_HALF_W, half_l=CAR_HALF_L, clear=CLEAR, step=0.25):
    """Stellfläche eines Autos (Mitte x,z, Blickrichtung yaw wie CF.at) auf Boden 'floor': (Boden fehlt an
    [Punkten], [Hindernis-Pfade])"""
    a = math.radians(yaw_deg)
    lx, lz = -math.sin(a), -math.cos(a)            # LookVector
    rx, rz = -lz, lx                               # rechts (wie CarService)
    no_floor, block = [], set()
    n_w, n_l = int(2 * half_w / 1.0), int(2 * half_l / 1.0)
    for i in range(n_w + 1):
        s = -half_w + 2 * half_w * i / n_w
        for j in range(n_l + 1):
            t = -half_l + 2 * half_l * j / n_l
            x1, z1 = x + rx * s + lx * t, z + rz * s + lz * t
            g = world.ground(x1, z1, floor, step)
            if g is None or g < floor - 0.3:
                no_floor.append((round(x1, 1), round(z1, 1)))
                continue
            for lo, hi, p in world.obstacles(x1, z1, max(g, floor), step, clear):
                block.add(p.path)
    return no_floor, sorted(block)


def look_right(yaw_deg):
    a = math.radians(yaw_deg)
    lx, lz = -math.sin(a), -math.cos(a)
    return (lx, lz), (-lz, lx)
