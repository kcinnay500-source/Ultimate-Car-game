# Layout data for the "Spielermeile" city (design angle: player flow).
# X east, Z south (+Z = front/road side of rot-0 plots), Y up. 1 unit = 1 stud.
import math, json

# ---------------- plots ----------------
PLOT_LOCAL = dict(x0=-84, x1=56, z0=-44, z1=84)          # reserved trimmed footprint (plot-local)
HALL_LOCAL = dict(x0=-74, x1=34.4, z0=-33.4, z1=33.4)     # 4-bay hall
RECEPTION_LOCAL = dict(x0=-74, x1=-54, z0=15, z1=33)

def plot_world(px, pz, rot, r):
    if rot == 0:
        return (px + r['x0'], px + r['x1'], pz + r['z0'], pz + r['z1'])
    # 180 deg about Y: (lx,lz) -> (-lx,-lz)
    return (px - r['x1'], px - r['x0'], pz - r['z1'], pz - r['z0'])

def loc2world(px, pz, rot, lx, lz):
    return (px + lx, pz + lz) if rot == 0 else (px - lx, pz - lz)

# slot order = fill order (closest to plaza first), house number = street address
SLOTS = [
    # slot, house, px, pz, rot, label
    (1, 5, 262, -109, 0,   "Nord-Ost innen"),
    (2, 4, -262, 109, 180, "Sued-West innen"),
    (3, 3, -234, -109, 0,  "Nord-West innen"),
    (4, 6, 234, 109, 180,  "Sued-Ost innen"),
    (5, 7, 412, -109, 0,   "Nord-Ost aussen"),
    (6, 2, -412, 109, 180, "Sued-West aussen"),
    (7, 1, -384, -109, 0,  "Nord-West aussen"),
    (8, 8, 384, 109, 180,  "Sued-Ost aussen"),
]

# ---------------- roads ----------------
MEILE_Z = 0; MEILE_HALF = 13; MEILE_SW = 10
RING_X = 152; RING_HALF = 13; RING_SW = 9
NORD_Z = -342; SUED_Z = 200
RB = [(-518, 0), (518, 0)]; RB_ISLAND = 12; RB_ROAD = 38; RB_WALK = 46

ROADS = [  # name, (x0,z0)->(x1,z1) centerline, half carriageway, sidewalk width
    ("Spielermeile", (-480, 0), (480, 0), 13, 10),
    ("Marktstrasse West", (-152, -342), (-152, 200), 13, 9),
    ("Marktstrasse Ost", (152, -342), (152, 200), 13, 9),
    ("Nordring", (-152, -342), (152, -342), 13, 9),
    ("Suedring", (-152, 200), (152, 200), 13, 9),
]

def road_rects():
    out = []
    for n, (x0, z0), (x1, z1), h, sw in ROADS:
        if z0 == z1:  # E-W
            out.append((n, 'road', min(x0, x1), max(x0, x1), z0 - h, z0 + h))
            out.append((n, 'walk', min(x0, x1), max(x0, x1), z0 - h - sw, z0 - h))
            out.append((n, 'walk', min(x0, x1), max(x0, x1), z0 + h, z0 + h + sw))
        else:
            out.append((n, 'road', x0 - h, x0 + h, min(z0, z1), max(z0, z1)))
            out.append((n, 'walk', x0 - h - sw, x0 - h, min(z0, z1) - h - sw, max(z0, z1) + h + sw))
            out.append((n, 'walk', x0 + h, x0 + h + sw, min(z0, z1) - h - sw, max(z0, z1) + h + sw))
    # ring corners: extend E-W rings' sidewalks to outer corner
    return out

# ---------------- districts / buildings (rects) ----------------
# kind: 'bld' (solid building, walls), 'open' (walkable ground), 'fence' (perimeter)
B = []
def add(name, kind, x0, x1, z0, z1, ch, doors=(), h=None, ceil=None, floor=0):
    B.append(dict(name=name, kind=kind, x0=x0, x1=x1, z0=z0, z1=z1, ch=ch, doors=list(doors), h=h, ceil=ceil, floor=floor))

# Altstadt (north of Meile, between Marktstrassen) X -130..130, Z -23..-320
add("Stadtplatz", 'open', -60, 60, -175, -23, '.')
add("Spielhalle", 'bld', -130, -70, -111, -31, 'S', doors=[('E', -72, 12)], h=30, ceil=26)
add("Meisterschule", 'bld', -130, -70, -175, -121, 'M', doors=[('E', -148, 10)], h=28, ceil=24)
add("Auktionshaus", 'bld', 70, 130, -121, -31, 'K', doors=[('W', -76, 12)], h=34, ceil=30)
add("Credit-Center", 'bld', 70, 130, -175, -129, 'C', doors=[('W', -152, 10)], h=28, ceil=24)
add("Ankunftshalle", 'bld', -45, 45, -221, -181, 'A', doors=[('S', 0, 20), ('W', -201, 10), ('E', -201, 10), ('N', 0, 16)], h=28, ceil=24)
add("Parkplatz-Chaos", 'open', -130, 130, -320, -229, 'p')
add("Parkhaus (Deko)", 'bld', 70, 126, -316, -236, 'G', h=28)
add("Querachse Promenade W", 'open', -130, -45, -229, -175, ',')
add("Querachse Promenade O", 'open', 45, 130, -229, -175, ',')

# Autohaus block (south of Meile) X -130..130, Z 23..178
add("Autohaus Vorplatz", 'open', -130, 130, 23, 178, ',')
add("Gebrauchtwagen-Platz", 'open', -126, -68, 30, 150, 'l')
add("Autohaus Showroom", 'bld', -60, 60, 39, 111, 'H', doors=[('N', 0, 11), ('S', 0, 12)], h=31, ceil=26)
add("Uebergabe-Halle", 'bld', 80, 122, 56, 96, 'h', doors=[('W', 76, 24)], h=28, ceil=24)

# Schrottplatz NW2
add("Schrottplatz", 'fence', -468, -178, -364, -159, 'x', doors=[('E', -201, 20), ('S', -323, 10)])
add("Presse-Halle", 'bld', -380, -310, -250, -180, 'R', doors=[('E', -211, 34)], h=34, ceil=30)
add("Schrotthaendler-Kontor", 'bld', -236, -204, -246, -216, 'D', h=16)
add("Zerlegeplatz (Dach)", 'open', -286, -238, -188, -164, 'Z')
add("Magnetkran", 'bld', -425, -415, -267, -257, 'Y', h=66)
add("Schornstein", 'bld', -307, -301, -249, -243, 'R', h=56)
add("Aufgabebunker", 'bld', -402, -382, -222, -200, 'R', h=2)

# Tuning NE2
add("Tuning-Gelaende", 'open', 178, 468, -364, -159, ',')
add("Tuning-Zentrum Halle", 'bld', 214, 334, -290, -170, 'T', doors=[('W', -201, 14), ('W', -262, 24)], h=38, ceil=32)
add("Tuning-Treff", 'open', 350, 450, -300, -190, 'n')
add("Dragstrip", 'open', 190, 450, -350, -326, 'm')

# SE2 Tankstelle / Waschstrasse
add("Tankstellen-Gelaende", 'open', 178, 400, 159, 260, ',')
add("Tankstelle Dach", 'open', 196, 256, 170, 206, 'F')
add("Tankstellen-Shop", 'bld', 266, 300, 172, 204, 'f', h=12)
add("Waschstrasse", 'bld', 310, 370, 176, 200, 'w', doors=[('W', 188, 18), ('E', 188, 18)], h=28, ceil=24)

# SW2 Stadtpark
add("Stadtpark", 'open', -468, -178, 159, 340, ';')

# Teststrecke (south)
TRACK = dict(cx=0, cz=340, straight_half=85, r=70, width=24)
add("Tribuene", 'bld', -60, 60, 228, 252, 'B', h=14)

SPAWN = (0, -201)
ARRIVALS = {  # key: (x, z, facingDeg) facing: yaw where 0 = looking -Z (north), 90 = looking -X (west)... we give "look at" point instead
}

# ---------------- checks ----------------
def overlap(a, b, m=0):
    return a[0] < b[1] - m and b[0] < a[1] - m and a[2] < b[3] - m and b[2] < a[3] - m

def plots():
    out = []
    for slot, house, px, pz, rot, lab in SLOTS:
        fp = plot_world(px, pz, rot, PLOT_LOCAL)
        hall = plot_world(px, pz, rot, HALL_LOCAL)
        rec = plot_world(px, pz, rot, RECEPTION_LOCAL)
        arr = loc2world(px, pz, rot, -64, 31.5)
        home = loc2world(px, pz, rot, -64, 25.5)
        door = loc2world(px, pz, rot, -43, 31.6)
        out.append(dict(slot=slot, house=house, px=px, pz=pz, rot=rot, label=lab, fp=fp, hall=hall, rec=rec, arr=arr, home=home, door=door))
    return out

if __name__ == '__main__':
    P = plots()
    for p in P:
        print(p['slot'], p['house'], p['label'], 'fp', p['fp'], 'hall', tuple(round(v,1) for v in p['hall']), 'rec', p['rec'], 'arr', p['arr'], 'door', p['door'])
    # plot-plot overlap
    for i in range(len(P)):
        for j in range(i + 1, len(P)):
            if overlap(P[i]['fp'], P[j]['fp']):
                print('PLOT OVERLAP', P[i]['slot'], P[j]['slot'])
    # plot vs roads/buildings
    RR = road_rects()
    for p in P:
        for n, k, x0, x1, z0, z1 in RR:
            if overlap(p['fp'], (x0, x1, z0, z1)):
                print('PLOT/ROAD OVERLAP', p['slot'], n, k)
        for b in B:
            if overlap(p['fp'], (b['x0'], b['x1'], b['z0'], b['z1'])):
                print('PLOT/BLD OVERLAP', p['slot'], b['name'])
        # roundabout (square approx of walk circle)
        for cx, cz in RB:
            # exact circle-rect distance
            fx0, fx1, fz0, fz1 = p['fp']
            nx = min(max(cx, fx0), fx1); nz = min(max(cz, fz0), fz1)
            d = math.hypot(nx - cx, nz - cz)
            if d < RB_WALK:
                print('PLOT/ROUNDABOUT', p['slot'], d)
    # buildings vs roads
    for b in B:
        for n, k, x0, x1, z0, z1 in RR:
            if overlap((b['x0'], b['x1'], b['z0'], b['z1']), (x0, x1, z0, z1)):
                print('BLD/ROAD OVERLAP', b['name'], n, k)
    # min gap plot<->other things
    print('checks done')
