import sys, math
sys.path.insert(0, '/tmp/claude-0/scratch_design_final')
from layout import *

X0, X1, Z0, Z1 = -600, 600, -400, 460
S = 10
cols = (X1 - X0) // S; rows = (Z1 - Z0) // S
g = [[' '] * cols for _ in range(rows)]
def paint(x0, x1, z0, z1, ch):
    for r in range(rows):
        zc = Z0 + r * S + S / 2
        if not (z0 <= zc < z1): continue
        for c in range(cols):
            xc = X0 + c * S + S / 2
            if x0 <= xc < x1: g[r][c] = ch
def pt(x, z, ch):
    c = int((x - X0) // S); r = int((z - Z0) // S)
    if 0 <= r < rows and 0 <= c < cols: g[r][c] = ch
def text(x, z, s):
    c = int((x - X0) // S); r = int((z - Z0) // S)
    for k, ch in enumerate(s):
        if 0 <= r < rows and 0 <= c + k < cols: g[r][c + k] = ch
def circle(cx, cz, r0, r1, ch):
    for r in range(rows):
        zc = Z0 + r * S + S / 2
        for c in range(cols):
            xc = X0 + c * S + S / 2
            d = math.hypot(xc - cx, zc - cz)
            if r0 <= d < r1: g[r][c] = ch

# city edge (hedge) : ground slab X -620..620 Z -420..500 ; hedge line at X+-590, Z -390/470
paint(-590, 590, -390, -380, '*'); paint(-590, 590, 450, 460, '*')
paint(-600, -590, -390, 460, '*'); paint(590, 600, -390, 460, '*')

# districts (open ground first)
for b in B:
    if b['kind'] in ('open', 'fence'):
        paint(b['x0'], b['x1'], b['z0'], b['z1'], b['ch'])
# Schrottplatz fence outline
sp = [b for b in B if b['name'] == 'Schrottplatz'][0]
paint(sp['x0'], sp['x1'], sp['z0'], sp['z0'] + 10, '+'); paint(sp['x0'], sp['x1'], sp['z1'] - 10, sp['z1'], '+')
paint(sp['x0'], sp['x0'] + 10, sp['z0'], sp['z1'], '+'); paint(sp['x1'] - 10, sp['x1'], sp['z0'], sp['z1'], '+')
paint(sp['x1'] - 10, sp['x1'], -211, -191, 'x')  # gate
paint(-310, -178, -209, -193, 'x')
pt(-323, -165, 'x')
# track
T = TRACK
def track_d(x, z):
    cx, cz, a, r = T['cx'], T['cz'], T['straight_half'], T['r']
    if -a <= x - cx <= a: return abs(abs(z - cz) - r)
    ex = cx + (a if x > cx else -a)
    return abs(math.hypot(x - ex, z - cz) - r)
for rr in range(rows):
    zc = Z0 + rr * S + S / 2
    for c in range(cols):
        xc = X0 + c * S + S / 2
        if track_d(xc, zc) <= T['width'] / 2: g[rr][c] = '%'
# roads
for n, k, x0, x1, z0, z1 in road_rects():
    if k == 'walk': paint(x0, x1, z0, z1, ':')
for n, k, x0, x1, z0, z1 in road_rects():
    if k == 'road': paint(x0, x1, z0, z1, '#')
for cx, cz in RB:
    circle(cx, cz, 0, RB_WALK, ':'); circle(cx, cz, RB_ISLAND, RB_ROAD, '#'); circle(cx, cz, 0, RB_ISLAND, '^')
paint(88, 112, 222, 262, '#')  # track connector
# plots
for p in plots():
    x0, x1, z0, z1 = p['fp']; paint(x0, x1, z0, z1, '_')
    x0, x1, z0, z1 = p['hall']; paint(x0, x1, z0, z1, 'W')
    x0, x1, z0, z1 = p['rec']; paint(x0, x1, z0, z1, 'E')
    hx = (p['hall'][0] + p['hall'][1]) / 2; hz = (p['hall'][2] + p['hall'][3]) / 2
    text(hx - 10, hz, f"#{p['house']}")
    pt(p['px'], p['pz'], 'r')
# buildings
for b in B:
    if b['kind'] == 'bld':
        paint(b['x0'], b['x1'], b['z0'], b['z1'], b['ch'])
# point features
circle(0, -100, 0, 15, 'o')          # fountain
pt(-30, -150, 'b'); pt(30, -150, 'b')  # boards
paint(-48, 48, -306, -246, 'g')      # 4x4 grid
circle(-320, 265, 0, 28, '~')        # pond
pt(-420, -290, 'Y')                  # crane
circle(-420,-290,44,52,'.') if False else None
pt(*SPAWN, '@')
# crosswalks
for x, z in [(0, 0), (-313, 0), (313, 0), (-152, -201), (152, -201), (-152, 165), (152, 165), (0, 200)]:
    pt(x, z, 'z')
for x in (-152, 152):
    for dz in (-25, 25): pt(x, dz, 'z')
    for dx in (-25, 25): pt(x + dx, 0, 'z')
# traffic lights
for x, z in [(-152, 0), (152, 0)]:
    pt(x, z, '+')
# gate arches
pt(-186, -10, '='); pt(-186, 10, '='); pt(186, -10, '='); pt(186, 10, '=')
pt(186, 162, 'P'); pt(190, -166, 'P')
# labels outside map area (margin text)
out = []
hdr = ''.join(('|' if (X0 + c * S) % 100 == 0 else ' ') for c in range(cols))
out.append('Z\\X   ' + ''.join((f"{X0 + c*S:<10d}" if (X0 + c*S) % 100 == 0 and c % 10 == 0 else '') for c in range(cols)))
for r in range(rows):
    z = Z0 + r * S
    out.append(f"{z:5d} " + ''.join(g[r]))
print('\n'.join(out))
