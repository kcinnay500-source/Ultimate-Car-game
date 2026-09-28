import math, heapq, sys
sys.path.insert(0, '/tmp/claude-0/scratch_design_final')
from layout import *

R = 2  # studs per cell
GX0, GX1, GZ0, GZ1 = -620, 620, -420, 500
W = (GX1 - GX0) // R; H = (GZ1 - GZ0) // R
walk = [[True] * W for _ in range(H)]
def cell(x, z): return int((x - GX0) // R), int((z - GZ0) // R)
def block_rect(x0, x1, z0, z1, val=False):
    i0, j0 = cell(x0, z0); i1, j1 = cell(x1 - 0.01, z1 - 0.01)
    for j in range(max(0, j0), min(H, j1 + 1)):
        for i in range(max(0, i0), min(W, i1 + 1)):
            walk[j][i] = val
def walls(x0, x1, z0, z1, doors, t=2):
    block_rect(x0, x1, z0, z0 + t); block_rect(x0, x1, z1 - t, z1)
    block_rect(x0, x0 + t, z0, z1); block_rect(x1 - t, x1, z0, z1)
    for side, c, w in doors:
        if side == 'E': block_rect(x1 - t, x1, c - w / 2, c + w / 2, True)
        if side == 'W': block_rect(x0, x0 + t, c - w / 2, c + w / 2, True)
        if side == 'N': block_rect(c - w / 2, c + w / 2, z0, z0 + t, True)
        if side == 'S': block_rect(c - w / 2, c + w / 2, z1 - t, z1, True)

for b in B:
    if b['kind'] == 'bld':
        if b['doors']:
            walls(b['x0'], b['x1'], b['z0'], b['z1'], b['doors'])
        else:
            block_rect(b['x0'], b['x1'], b['z0'], b['z1'])
    if b['kind'] == 'fence':
        walls(b['x0'], b['x1'], b['z0'], b['z1'], b['doors'], t=1)
# plots: hall+reception block (4-bay), reception door + roller door open (front face)
for p in plots():
    x0, x1, z0, z1 = p['hall']
    px, pz, rot = p['px'], p['pz'], p['rot']
    # front face local z=33.4 ; openings local x -65.4..-61.6 (Empfang) and -53..-33 (roller)
    fz = 'S' if rot == 0 else 'N'
    def wx(lx): return px + lx if rot == 0 else px - lx
    doors = [(fz, wx(-63.5), 4), (fz, wx(-43), 20)]
    walls(x0, x1, z0, z1, doors)
# fountain + pond
def block_circle(cx, cz, r):
    for j in range(H):
        z = GZ0 + (j + .5) * R
        if abs(z - cz) > r: continue
        for i in range(W):
            x = GX0 + (i + .5) * R
            if (x - cx) ** 2 + (z - cz) ** 2 <= r * r: walk[j][i] = False
block_circle(0, -100, 15)
block_circle(-320, 265, 28)

def dijkstra(src):
    si, sj = cell(*src)
    dist = {(si, sj): 0.0}; pq = [(0.0, si, sj)]
    steps = [(1,0,1),(-1,0,1),(0,1,1),(0,-1,1),(1,1,1.4142),(1,-1,1.4142),(-1,1,1.4142),(-1,-1,1.4142)]
    while pq:
        d, i, j = heapq.heappop(pq)
        if d > dist.get((i, j), 1e18): continue
        for di, dj, c in steps:
            ni, nj = i + di, j + dj
            if 0 <= ni < W and 0 <= nj < H and walk[nj][ni]:
                if di and dj and not (walk[j][ni] and walk[nj][i]): continue
                nd = d + c * R
                if nd < dist.get((ni, nj), 1e18):
                    dist[(ni, nj)] = nd; heapq.heappush(pq, (nd, ni, nj))
    return dist

TARGETS = {
 'Stadtplatz (Brunnenrand)': (0, -118),
 'Spielhalle Tuer': (-66, -72),
 'Meisterschule Tuer': (-66, -148),
 'Auktionshaus Tuer': (66, -76),
 'Credit-Center Tuer': (66, -152),
 'Parkplatz-Chaos Haeuschen': (-62, -240),
 'Schrottplatz Tor': (-174, -201),
 'Schrottpresse (Station)': (-318, -204),
 'Schrotthaendler (Station)': (-220, -212),
 'Zerlegeplatz (Station)': (-262, -192),
 'Tuning-Zentrum Tuer': (210, -201),
 'Tuning Auftragstresen': (228, -208),
 'Pruefstand': (290, -214),
 'Autohaus Tuer': (0, 37),
 'Autohaus Verkauf': (-40, 104),
 'Tankstelle': (190, 188),
 'Waschstrasse Terminal': (304, 206),
 'Stadtpark Eingang': (-180, 168),
 'Stadtpark Teich': (-290, 265),
 'Teststrecke Tribuene': (0, 226),
}
if __name__ == '__main__':
    d = dijkstra(SPAWN)
    def dd(pt):
        i, j = cell(*pt)
        best = None
        for di in range(-2, 3):
            for dj in range(-2, 3):
                v = d.get((i + di, j + dj))
                if v is not None and (best is None or v < best): best = v
        return best
    print('FROM CitySpawn', SPAWN)
    for k, v in TARGETS.items():
        x = dd(v); print(f"  {k:28s} {v} path={x:.0f} studs  t={x/19:.1f}s" if x else f"  {k} UNREACHABLE")
    print('plots (arrival points):')
    for p in plots():
        a = p['arr']; x = dd(a)
        print(f"  slot {p['slot']} Nr.{p['house']} {p['label']:18s} arr={a} path={x:.0f} t={x/19:.1f}s")
    # from farthest plot to districts
    for s in (7, 8):
        p = [q for q in plots() if q['slot'] == s][0]
        d2 = dijkstra(p['arr'])
        def dd2(pt):
            i, j = cell(*pt); return min(d2.get((i+a, j+b), 1e9) for a in range(-2,3) for b in range(-2,3))
        print('FROM slot', s, 'arrival', p['arr'])
        for k in ('Stadtplatz (Brunnenrand)', 'Schrottplatz Tor', 'Tuning-Zentrum Tuer', 'Autohaus Tuer', 'Spielhalle Tuer'):
            print(f"   {k:28s} {dd2(TARGETS[k]):.0f}")
