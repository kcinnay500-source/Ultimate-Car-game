import sys, math
sys.path.insert(0,'/tmp/claude-0/scratch_design_final')
from layout import *
f=lambda v: f"{v:.1f}".rstrip('0').rstrip('.')
P=lambda x,z: f"({f(x)},{f(z)})"
def ring(cx,cz,r,a0,a1,step):
    n=max(1,int(round(abs(a1-a0)/step))); return [(cx+r*math.cos(math.radians(a0+(a1-a0)*k/n)), cz+r*math.sin(math.radians(a0+(a1-a0)*k/n))) for k in range(n+1)]
# ---- loops
L=25; ex=math.sqrt(L*L-6.5*6.5); th=math.degrees(math.atan2(6.5,-ex))
A=[(-518+ex,6.5),(-186,6.5),(-9,6.5),(118,6.5),(518-ex,6.5)]+ring(518,0,L,th,-th,30)[1:]+[(186,-6.5),(9,-6.5),(-118,-6.5)]+ring(-518,0,L,-(180-th),-(180-th)-(360-2*(180-th)),30)
def rect_loop(xl,xr,zt,zb,r,cw,step=15):
    p=[]
    if cw:
        p+=[(xl+r,zt),(xr-r,zt)]+ring(xr-r,zt+r,r,-90,0,step)[1:]+[(xr,zb-r)]+ring(xr-r,zb-r,r,0,90,step)[1:]
        p+=[(xl+r,zb)]+ring(xl+r,zb-r,r,90,180,step)[1:]+[(xl,zt+r)]+ring(xl+r,zt+r,r,180,270,step)[1:-1]
    else:
        p+=[(xr-r,zt),(xl+r,zt)]+ring(xl+r,zt+r,r,270,180,step)[1:]+[(xl,zb-r)]+ring(xl+r,zb-r,r,180,90,step)[1:]
        p+=[(xr-r,zb)]+ring(xr-r,zb-r,r,90,0,step)[1:]+[(xr,zt+r)]+ring(xr-r,zt+r,r,0,-90,step)[1:-1]
    return p
RB1=float(sys.argv[1]) if len(sys.argv)>1 else 14
B1=rect_loop(-145.5,145.5,-335.5,193.5,RB1,True)
B2=rect_loop(-158.5,158.5,-348.5,206.5,27,False)
T=[(-85,270),(85,270)]+ring(85,340,70,-90,90,15)[1:]+[(-85,410)]+ring(-85,340,70,90,270,15)[1:-1]
LOOPS={'A':A,'B1':B1,'B2':B2,'T':T}
def length(p): return sum(math.dist(p[i],p[(i+1)%len(p)]) for i in range(len(p)))
# ---- asphalt model
RECTS=[(-484,484,-13,13),(-165,-139,-355,213),(139,165,-355,213),(-165,165,-355,-329),(-165,165,187,213)]
CH=8
def chamfers():
    tris=[]
    nodes=[(-152,0,[(1,1),(1,-1),(-1,1),(-1,-1)]),(152,0,[(1,1),(1,-1),(-1,1),(-1,-1)]),
           (-152,-342,[(1,1)]),(152,-342,[(-1,1)]),(-152,200,[(1,-1)]),(152,200,[(-1,-1)])]
    for cx,cz,qs in nodes:
        for sx,sz in qs:
            c=(cx+sx*13,cz+sz*13); tris.append((c,(c[0]+sx*CH,c[1]),(c[0],c[1]+sz*CH)))
    return tris
TRIS=chamfers()
def in_tri(p,t):
    (x1,y1),(x2,y2),(x3,y3)=t; x,y=p
    d=(y2-y3)*(x1-x3)+(x3-x2)*(y1-y3)
    a=((y2-y3)*(x-x3)+(x3-x2)*(y-y3))/d; b=((y3-y1)*(x-x3)+(x1-x3)*(y-y3))/d
    return a>=-1e-9 and b>=-1e-9 and 1-a-b>=-1e-9
def asphalt(p):
    x,z=p
    for x0,x1,z0,z1 in RECTS:
        if x0<=x<=x1 and z0<=z<=z1: return True
    for cx in (-518,518):
        r=math.hypot(x-cx,z)
        if 12<=r<=38: return True
    return any(in_tri(p,t) for t in TRIS)
def track(p):
    x,z=p
    if -85<=x<=85: return abs(z-270)<=12 or abs(z-410)<=12
    cx=85 if x>0 else -85; return abs(math.hypot(x-cx,z-340)-70)<=12
def samples(p,step=1.0):
    out=[]
    for i in range(len(p)):
        a,b=p[i],p[(i+1)%len(p)]; n=max(1,int(math.dist(a,b)/step))
        for k in range(n): out.append((a[0]+(b[0]-a[0])*k/n, a[1]+(b[1]-a[1])*k/n, math.atan2(b[1]-a[1],b[0]-a[0])))
    return out
def disc_ok(x,z,r,fn):
    return all(fn((x+r*math.cos(math.radians(a)),z+r*math.sin(math.radians(a)))) for a in range(0,360,15)) and fn((x,z))
print('== NPC loops (car disc r=5)')
S={}
for n,p in LOOPS.items():
    s=samples(p); S[n]=s; fn=track if n=='T' else asphalt
    bad=[(round(x,1),round(z,1)) for x,z,h in s if not disc_ok(x,z,5,fn)]
    print(f' loop {n}: {len(p)} wp, length {length(p):.0f}, off-asphalt samples {len(bad)}', bad[:3])
# lane sharing / crossings
print('== loop interactions')
names=list(LOOPS)
for i in range(len(names)):
    for j in range(i+1,len(names)):
        a,b=names[i],names[j]; share=0; cross=set()
        import bisect
        for x,z,h in S[a][::2]:
            for x2,z2,h2 in S[b][::2]:
                if abs(x-x2)<4 and abs(z-z2)<4:
                    dh=abs((h-h2+math.pi)%(2*math.pi)-math.pi)
                    if dh<0.5: share+=1
                    elif dh>1.0: cross.add((round(x/26)*26,round(z/26)*26))
        print(f' {a}-{b}: same-lane samples {share}, crossing zones {sorted(cross)}')
# closest approach of any loop to crosswalk/signal nodes
print('== B1 corner radius used', RB1)
# ---- plot driveways / pylons / trees / lamps
print('== plot dressing')
PL=plots()
drives=[]
for p in PL:
    xs=sorted([loc2world(p['px'],p['pz'],p['rot'],-30,0)[0],loc2world(p['px'],p['pz'],p['rot'],30,0)[0]])
    rd=sorted([loc2world(p['px'],p['pz'],p['rot'],-53,0)[0],loc2world(p['px'],p['pz'],p['rot'],-33,0)[0]])
    drives.append((p['slot'],xs,rd))
lamps=[]
for p in PL:
    for lx in (-76,44):
        x,_=loc2world(p['px'],p['pz'],p['rot'],lx,0); z=-14.5 if p['rot']==0 else 14.5
        if abs(abs(x)-186)<6: continue
        lamps.append(('Meile',x,z))
for x in (-100,-20,20,100):
    lamps.append(('Meile',x,-14.5 if x in (-100,20) else 14.5)); lamps.append(('Meile',x,14.5 if x in (-100,20) else -14.5))
for x in (-186,186): lamps+= [('Bogen',x,-18),('Bogen',x,18)]
for cx in (-518,518):
    s=1 if cx>0 else -1
    for a in (50,-50): lamps.append(('Kreisel',cx+s*42*math.cos(math.radians(a)),42*math.sin(math.radians(a))))
zs=[-305,-265,-215,-145,-80,45,105,175]
for sg in (-1,1):
    for i,z in enumerate(zs): lamps.append(('Markt'+('W' if sg<0 else 'O'),sg*(137.5 if i%2==0 else 166.5),z))
for x in (-100,-35,35,100): lamps+= [('Nordring',x,-327.5),('Suedring',x,185.5)]
bad=[l for l in lamps if asphalt((l[1],l[2]))]
print(' street lamps',len(lamps),'on asphalt:',bad)
XW=[(-6,6),(-327,-319),(319,327),(-183,-175),(-129,-121),(121,129),(175,183)]
bad=[]
for n,x,z in lamps:
    if n=='Meile':
        for s,xs,rd in drives:
            if xs[0]-2<=x<=xs[1]+2 or rd[0]-2<=x<=rd[1]+2: bad.append((n,x,z,'driveway',s))
        for a,b in XW:
            if a-3<=x<=b+3: bad.append((n,x,z,'crosswalk'))
    for p in PL:
        if overlap(p['fp'],(x-1,x+1,z-1,z+1)): bad.append((n,x,z,'plot',p['slot']))
print(' lamp conflicts:',bad)
from collections import defaultdict
g=defaultdict(list)
for n,x,z in lamps: g[n].append(P(x,z))
for n,v in g.items(): print('  ',n,len(v),' '.join(v))
for p in PL:
    pyl=loc2world(p['px'],p['pz'],p['rot'],-64,0); tree=loc2world(p['px'],p['pz'],p['rot'],-44,0)
    s,xs,rd=[d for d in drives if d[0]==p['slot']][0]
    emp=loc2world(p['px'],p['pz'],p['rot'],-63.5,33.4)
    home=p['home']
    print(f"  slot {p['slot']} Nr{p['house']} pivot ({p['px']},0,{p['pz']}) rot {p['rot']} fp X{p['fp'][0]}..{p['fp'][1]} Z{p['fp'][2]}..{p['fp'][3]} hall X{p['hall'][0]:.1f}..{p['hall'][1]:.1f} Z{p['hall'][2]:.1f}..{p['hall'][3]:.1f} Empfang X{p['rec'][0]}..{p['rec'][1]} door {P(*emp)} arr {P(*p['arr'])} home {P(*home)} roll {P(*p['door'])} pylon ({f(pyl[0])},{-21.4 if p['rot']==0 else 21.4}) tree ({f(tree[0])},{-16 if p['rot']==0 else 16}) drive X{xs[0]}..{xs[1]} rollapproach X{rd[0]}..{rd[1]}")
# ---- crane reach
print('== Magnetkran reach (mast (-420,-262), usable r 12..62)')
for n,(x,z) in {'Aufgabebunker':(-392,-211),'Haufen 1':(-445,-315),'Haufen 2':(-390,-305),'Haufen 3':(-452,-215)}.items():
    d=math.hypot(x+420,z+262); print(f'  {n} {P(x,z)} r={d:.1f}', 'OK' if 12<=d<=62 else 'FAIL')
print('  chimney (-304,-246) r=%.1f (must be >66 so jib never meets it)'%math.hypot(-304+420,-246+262))
for n,b in [(b['name'],b) for b in B if b['name'] in ('Presse-Halle',)]:
    # nearest point of hall to mast
    nx=min(max(-420,b['x0']),b['x1']); nz=min(max(-262,b['z0']),b['z1']); print('  press hall nearest r=%.1f, hall roof top 41 < jib underside 54'%math.hypot(nx+420,nz+262))
# ---- building-building overlaps (excluding intended nesting)
print('== building/building overlaps')
NEST={('Autohaus Vorplatz','Gebrauchtwagen-Platz'),('Autohaus Vorplatz','Autohaus Showroom'),('Autohaus Vorplatz','Uebergabe-Halle'),
('Schrottplatz','Presse-Halle'),('Schrottplatz','Schrotthaendler-Kontor'),('Schrottplatz','Zerlegeplatz (Dach)'),('Schrottplatz','Magnetkran'),('Schrottplatz','Schornstein'),('Schrottplatz','Aufgabebunker'),
('Tuning-Gelaende','Tuning-Zentrum Halle'),('Tuning-Gelaende','Tuning-Treff'),('Tuning-Gelaende','Dragstrip'),('Parkplatz-Chaos','Parkhaus (Deko)'),
('Tankstellen-Gelaende','Tankstelle Dach'),('Tankstellen-Gelaende','Tankstellen-Shop'),('Tankstellen-Gelaende','Waschstrasse')}
n=0
for i in range(len(B)):
    for j in range(i+1,len(B)):
        a,b=B[i],B[j]
        if overlap((a['x0'],a['x1'],a['z0'],a['z1']),(b['x0'],b['x1'],b['z0'],b['z1'])) and (a['name'],b['name']) not in NEST and (b['name'],a['name']) not in NEST:
            print('  OVERLAP',a['name'],b['name']); n+=1
print('  unintended overlaps:',n)
# track vs roads/buildings
tb=(-167,167,258,422)
print('== track box vs roads/buildings:',[r[0] for r in road_rects() if overlap(tb,r[2:])],[b['name'] for b in B if overlap(tb,(b['x0'],b['x1'],b['z0'],b['z1']))])
# ceilings
print('== enterable interiors ceiling >= 24:')
for b in B:
    if b['kind']=='bld' and b.get('ceil'): print('  ',b['name'],'ceil',b['ceil'],'OK' if b['ceil']>=24 else 'LOW')
