#!/usr/bin/env python3
"""Wirtschafts-Simulation für Ultimate Car Game 3.x (PHASE2_CONTRACT §7).

Liest die echten Balance-Zahlen über tools/economy_dump.lua (luaurun lädt GarageShared.Config, MiniConfig,
MiniCatalog, CarCatalog, ArcadeRules, TrackRules) und schätzt:

* Credits pro Minute je Tätigkeit auf Level 1, 5, 10, 20, 30, 40
  (2.4.0-Werkstatt mit Auftragsauswahl wie R.RefreshOffers, Arbeitszeiten wie R.StepDuration,
  Teilekosten, Qualität; Minispiele mit realistischen Spielraten, Abklingzeiten und Tageslimits),
* den Werkstatt-Verlauf (Level, Kontostand, Ausbau) über die Spielzeit und daraus die Zeit bis zum Kauf
  jedes Autos beim Händler,
* und prüft die Ziele aus §7 (Werkstatt am ergiebigsten, Minispiele ≤ 60 %, passiv ≤ 25 %,
  erstes Auto nach 20–30 Min., Sportwagen nach mehreren Stunden, Super/Elektro langfristig).
* Ausbaustufe 4 (PHASE4_CONTRACT): Level 50/90 im gemischten Spiel (MIX), Tycoon-Rundendauer je Gebäudetyp,
  Missionen/Kiesplatz ≤ 40 % der Werkstatt, OW-Gebäude ≤ 25 %, Shop-Preise (erste Kosmetik, DLC-Autos) und
  die Deckel der gestapelten Boni (CAPS). Die Zahlen liest economy_dump.lua aus GameConfig.

Aufruf (aus dem Projektordner):
    python3 tools/economy_sim.py            # Tabellen ausgeben
    python3 tools/economy_sim.py --check    # zusätzlich Ziele prüfen (Exit-Code 1 bei Verstoß)
    python3 tools/economy_sim.py --write-doc  # Tabellenblock in docs/BALANCE.md ersetzen
    python3 tools/economy_sim.py --tycoon   # Rundendauer des Tycoons (tools/tycoon_sim.lua, echte TycoonRules)

Die Annahmen über das Spielverhalten stehen gesammelt in ASSUME (unten) und in docs/BALANCE.md.
"""
import json
import math
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAURUN = os.path.join(ROOT, "tools", "luaurun", "target", "release", "luaurun")
LEVELS = [1, 5, 10, 20, 30, 40]

# ------------------------------------------------------------------ Annahmen zum Spielverhalten
ASSUME = {
    # Werkstatt (2.4.0): aktive Sekunden je Auftrag ohne die Arbeitsschritte selbst
    "job_fixed": 40.0,        # Empfang (annehmen), Diagnose (Scan 2,5 s + lesen + wählen), Endkontrolle, Abrechnen, Teile
    "job_per_step": 8.0,      # je Arbeitsschritt: hingehen, Werkzeug, Bühne/Haube, Mess-QTE
    "quality": 96,            # mittlere Qualität (gelegentlich ein verfehltes QTE oder eine falsche Diagnose)
    "offer_slots": {1: 3, 5: 3, 10: 4, 20: 5, 30: 6, 40: 7},   # gekaufte Auftragsannahme-Stufen je Level
    "tool_level": {1: 1, 5: 2, 10: 4, 20: 7, 30: 10, 40: 13},  # 2.4.0-Werkzeugqualität je Level
    # Minispiel-Stufen, die ein Spieler auf diesem Level typischerweise gekauft hat
    "tuning_level": {1: 1, 5: 2, 10: 4, 20: 7, 30: 10, 40: 13},
    "scrapyard_level": {1: 1, 5: 2, 10: 3, 20: 5, 30: 7, 40: 9},
    # Quiz: 20 Fragen im Katalog -> nach kurzer Zeit auswendig bekannt
    "quiz_seconds": 5.0,      # je Frage (lesen, tippen, Ergebnis ansehen; Abklingzeit 1 s)
    "quiz_correct": 0.95,
    # Parkplatz: Sekunden je Rätsel = Grundzeit + je Tipp
    "parking_base": 2.5, "parking_tap": 0.7, "parking_crash": 0.03,
    # Schrottplatz: kaufen, 8 s Vorbereitung, zerlegen, alle 5 Altteile verkaufen
    "scrapyard_overhead": 4.0,
    # Spielhalle: typische Punkte (0..1000) und Zusatzzeit je Runde (Countdown 3 s, Ergebnis, Neustart)
    "arcade_score": 700, "arcade_overhead": 9.0, "arcade_duration_share": 0.9,
    # Presse: Klicks pro Sekunde eines Menschen (Serverlimit 20/s), Zeit bis das Guthaben umgetauscht wird
    "press_cps": 6.0,
    # Teststrecke: Rundenzeiten (Oval ~780 Studs) und Zeit je Versuch inkl. Hinfahrt/Startampel
    "track_first": 16.0, "track_best": 10.0, "track_runs": 10, "track_run_seconds": 60.0, "track_drive_there": 60.0,
    # Spielzeit-Verlauf der Werkstatt
    "reserve": 0,             # Mindestguthaben, das beim Ausbau stehen bleibt
    # abgeschlossene Tuning-Projekte je Level (lassen die passive Tuning-Rate wachsen)
    "tuning_completed": {1: 0, 5: 2, 10: 8, 20: 25, 30: 50, 40: 80},
}


# ------------------------------------------------------------------ Daten laden
def load_data():
    out = subprocess.run([LUAURUN, "run", os.path.join(ROOT, "tools", "economy_dump.lua"), ROOT],
                         capture_output=True, text=True, cwd=ROOT)
    if out.returncode != 0:
        sys.exit("economy_dump.lua fehlgeschlagen:\n" + out.stderr + out.stdout)
    return json.loads(out.stdout.strip().splitlines()[-1])


D = load_data()
C = D["config"]
MC = D["mini"]
CARS = {c["id"]: c for c in C["Cars"]}
JOBS = {j["id"]: j for j in C["Jobs"]}
PART_TYPES = {p["id"]: p for p in C["PartTypes"]}
EQUIP = {e["id"]: e for e in C["Equipment"]}
UPGRADES = {u["key"]: u for u in C["Upgrades"]}
FAMILY_MULT = {"C": 1.0, "L": 1.4, "P": 2.4}


def at_level(table, level):
    """Wert der Annahme-Tabelle für das nächstniedrigere angegebene Level"""
    keys = sorted(table)
    val = table[keys[0]]
    for k in keys:
        if level >= k:
            val = table[k]
    return val


# ------------------------------------------------------------------ 2.4.0-Formeln (Rules.lua)
def xp_needed(level):
    return math.floor(80 + level * 22 + level ** 1.16 * 4)


def level_bonus(new_level):
    return 120 + new_level * 18


def part_price(kind, family):
    return math.floor(PART_TYPES[kind]["price"] * 1 * FAMILY_MULT[family] + 0.5)  # Nexra (Preis ×1, Qualität 0)


def step_duration(step, tool_level):
    eq = 1  # Gerätestufe 1 (vorsichtig; höhere Stufen verkürzen weiter)
    return max(1, step.get("seconds", 5) / ((1 + (tool_level - 1) * 0.08) * (1 + (eq - 1) * 0.12)))


def required_equipment(job):
    need = {}
    for s in job["steps"]:
        if s.get("equipment"):
            need[s["equipment"]] = max(need.get(s["equipment"], 0), s.get("equipmentLevel", 1))
    tools_eq = {"tire": "wheel_jack", "meter": "diagnostic_rig"}
    for s in job["steps"]:
        eq = tools_eq.get(s["tool"])
        if eq:
            need[eq] = max(need.get(eq, 0), 1)
    return need


def job_numbers(job_id, car_id, tool_level, bays, mult=1.0, diag=0.0):
    """(Netto-Credits, XP, Zykluszeit in s) eines Auftrags; mult = Querbonus (CrossBonus.WorkshopReward),
    diag = Diagnose-Verkürzung der Arbeitszeit (CrossBonus.DiagReduction)"""
    job, car = JOBS[job_id], CARS[car_id]
    reward = round(job["reward"] * car["reward"] * mult * (1 + ASSUME["quality"] * 0.0025))
    parts = sum(part_price(s["part"], car["family"]) for s in job["steps"] if s.get("part"))
    xp = round(job["xp"] * car["xp"])
    active = ASSUME["job_fixed"] + ASSUME["job_per_step"] * len(job["steps"])
    work = sum(step_duration(s, tool_level) for s in job["steps"]) * (1 - diag)
    cycle = max(active, (active + work) / bays)
    return reward - parts, xp, cycle


# ------------------------------------------------------------------ Auftragsauswahl (R.RefreshOffers)
def eligible_jobs(level, owned):
    out = []
    for j in C["Jobs"]:
        if j["level"] <= level and all(owned.get(k, 0) >= v for k, v in required_equipment(j).items()):
            out.append(j["id"])
    return out


def random_offer(rng, level):
    jobs = [j["id"] for j in C["Jobs"] if j["level"] <= level]
    cars = [c["id"] for c in C["Cars"] if c["level"] <= level]
    j = rng.choice(jobs)
    ok = [c for c in cars if c != "elys" or j in ("inspection", "tire", "brakes", "battery", "hv")]
    car = rng.choice(ok)
    if j == "hv":
        car = "elys"
    return (j, car)


class Workshop:
    """Angebotspool wie R.RefreshOffers: immer eine Inspektion, sonst zufällig bis offerSlots.
    Der Spieler nimmt das Angebot mit den meisten Credits je Minute, das er ausrüstungsmäßig annehmen kann."""

    def __init__(self, rng):
        self.rng = rng
        self.offers = []

    def refresh(self, level, slots):
        if not any(o[0] == "inspection" for o in self.offers):
            cars = [c["id"] for c in C["Cars"] if c["level"] <= level]
            self.offers.append(("inspection", self.rng.choice(cars)))
        while len(self.offers) < slots:
            self.offers.append(random_offer(self.rng, level))

    def pick(self, level, slots, owned, tool_level, bays, mult=1.0, diag=0.0):
        self.refresh(level, slots)
        allowed = set(eligible_jobs(level, owned))
        best, best_rate = None, -1e18
        for i, (j, car) in enumerate(self.offers):
            if j not in allowed:
                continue
            net, xp, cycle = job_numbers(j, car, tool_level, bays, mult, diag)
            if net / cycle > best_rate:
                best, best_rate = i, net / cycle
        offer = self.offers.pop(best)
        self.refresh(level, slots)
        return offer


def all_equipment_for(level):
    owned = {}
    for j in C["Jobs"]:
        if j["level"] <= level:
            for k, v in required_equipment(j).items():
                owned[k] = max(owned.get(k, 0), v)
    return owned


def bays_for(level):
    bays = 1
    while bays < 4 and level >= C["BayLevels"][bays]:
        bays += 1
    return bays


def workshop_rate(level, samples=4000, seed=1):
    """Credits/min, XP/min der Werkstatt auf festem Level (Ausrüstung und Bühnen gekauft, ohne Querboni)"""
    rng = random.Random(seed)
    ws = Workshop(rng)
    owned = all_equipment_for(level)
    slots = at_level(ASSUME["offer_slots"], level)
    tl = at_level(ASSUME["tool_level"], level)
    bays = bays_for(level)
    money = xp = t = 0.0
    for _ in range(samples):
        j, car = ws.pick(level, slots, owned, tl, bays)
        net, x, cycle = job_numbers(j, car, tl, bays)
        money += net
        xp += x
        t += cycle
    return money / t * 60, xp / t * 60


# ------------------------------------------------------------------ Verlauf: nur Werkstatt, Ausbau nach Bedarf
def equipment_cost(key, have):
    e = EQUIP[key]
    return min(1e24, round(e["cost"] * 1.75 ** have))


def upgrade_cost(key, stage):
    u = UPGRADES[key]
    return round(u["base"] * u["growth"] ** (stage - u["start"]))


class Career:
    """Werkstatt-Spieler: kauft Bühnen, sobald freigeschaltet und bezahlbar, die Geräte für neue Auftragsarten und
    Auftragsannahme/Werkzeugqualität nach der Annahme-Tabelle. job() spielt einen Auftrag."""

    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.ws = Workshop(self.rng)
        self.d = {"money": float(C["StartMoney"]), "xp": 0.0, "level": 1, "bays": 1, "offerSlots": 3, "toolLevel": 1}
        self.owned = {e["id"]: e.get("starter", 0) for e in C["Equipment"]}
        self.t = 0.0
        self.timeline = [(0.0, 1, self.d["money"])]
        self.spent = 0.0

    def buy(self):
        d, owned = self.d, self.owned
        bought = True
        while bought:
            bought = False
            if d["bays"] < 4 and d["level"] >= C["BayLevels"][d["bays"]]:
                cost = upgrade_cost("bays", d["bays"])
                if d["money"] - cost >= ASSUME["reserve"]:
                    d["money"] -= cost; self.spent += cost; d["bays"] += 1; bought = True
                    continue
            for j in C["Jobs"]:
                if j["level"] > d["level"]:
                    continue
                for k, v in required_equipment(j).items():
                    if owned.get(k, 0) < v and EQUIP[k]["level"] <= d["level"]:
                        cost = equipment_cost(k, owned.get(k, 0))
                        if d["money"] - cost >= ASSUME["reserve"]:
                            d["money"] -= cost; self.spent += cost; owned[k] = owned.get(k, 0) + 1; bought = True
                            gain_xp(d, 20)
            # Auftragsannahme und Werkzeugqualität gemäß Annahme-Tabelle nachkaufen
            for key, table in (("offerSlots", ASSUME["offer_slots"]), ("toolLevel", ASSUME["tool_level"])):
                if d[key] < at_level(table, d["level"]):
                    cost = upgrade_cost(key, d[key])
                    if d["money"] - cost >= ASSUME["reserve"]:
                        d["money"] -= cost; self.spent += cost; d[key] += 1; bought = True
                        gain_xp(d, 25)

    def job(self, mult=1.0, diag=0.0):
        d = self.d
        j, car = self.ws.pick(d["level"], d["offerSlots"], self.owned, d["toolLevel"], d["bays"], mult, diag)
        net, x, cycle = job_numbers(j, car, d["toolLevel"], d["bays"], mult, diag)
        self.t += cycle
        d["money"] += net
        gain_xp(d, x)
        self.timeline.append((self.t, d["level"], d["money"]))
        return net, x, cycle


def progression(hours=40, seed=7, cross=None):
    """Spielt nur Werkstatt-Aufträge (Career). cross = Funktion(Level) -> (Vergütungsfaktor, Diagnose-Verkürzung) für
    das Szenario mit Minispiel-Querboni. Rückgabe: Liste (Sekunden, Level, Geld) nach jedem Auftrag und die
    Ausbauausgaben."""
    c = Career(seed)
    while c.t < hours * 3600:
        c.buy()
        mult, diag = cross(c.d["level"]) if cross else (1.0, 0.0)
        c.job(mult, diag)
    return c.timeline, c.spent


def gain_xp(d, n):
    d["xp"] += n
    while d["xp"] >= xp_needed(d["level"]):
        d["xp"] -= xp_needed(d["level"])
        d["level"] += 1
        d["money"] += level_bonus(d["level"])


def time_to_level(timeline, level):
    for t, lv, _ in timeline:
        if lv >= level:
            return t
    return None


def time_to_afford(timeline, price, level):
    """erste Zeit, zu der Level erreicht und Kontostand ≥ Preis (der Spieler spart ab Start für genau dieses Auto)"""
    for t, lv, money in timeline:
        if lv >= level and money >= price:
            return t
    return None


# ------------------------------------------------------------------ Minispiele (MiniConfig & Co.)
def xp_value(level):
    """Credits je XP über den 2.4.0-Level-Bonus (120 + 18 × neues Level) auf diesem Level"""
    return level_bonus(level + 1) / xp_needed(level)


def exchange_rate():
    """Credits je Schrott beim Schrotthändler"""
    return MC["ScrapExchangePayout"] / MC["ScrapPerCredit"]


def quiz_rate(level):
    per_min = 60 / max(ASSUME["quiz_seconds"], MC["QuizCooldown"])
    correct = per_min * ASSUME["quiz_correct"]
    wrong = per_min - correct
    return {
        "cr": correct * MC["QuizCorrectCredits"],
        "xp": correct * MC["QuizCorrectXp"] + wrong * MC["QuizWrongXp"],
        "day": MC["QuizPaidPerDay"] * MC["QuizCorrectCredits"],
        "day_minutes": MC["QuizPaidPerDay"] / correct,
    }


def parking_path(target, n):
    r, c = divmod(target, n)
    path = [r * n + cc for cc in range(c + 1, n)]
    path += [rr * n + (n - 1) for rr in range(r + 1, n)]
    return path


def parking_reward(streak):
    return MC["ParkingRewardBase"] + min(streak, MC["ParkingRewardStreakCap"]) * MC["ParkingRewardPerStreak"]


def parking_rate(level, samples=20000, seed=3):
    rng = random.Random(seed)
    n = MC["ParkingSize"]
    exit_cell = n * n - 1
    streak = 0
    money = t = solved = 0.0
    for _ in range(samples):
        cells = rng.sample(range(exit_cell), MC["ParkingCars"])
        target = cells[0]
        blockers = len(set(parking_path(target, n)) & set(cells[1:]))
        t += ASSUME["parking_base"] + ASSUME["parking_tap"] * (blockers + 1)
        if rng.random() < ASSUME["parking_crash"]:
            streak = 0
            continue
        streak += 1
        solved += 1
        money += parking_reward(streak)
    per_solve = money / solved
    return {
        "cr": money / t * 60,
        "xp": solved / t * 60 * MC["ParkingXp"],
        "day": MC["ParkingPaidPerDay"] * per_solve,
        "day_minutes": MC["ParkingPaidPerDay"] * (t / solved) / 60,
    }


def rare_part_value(level):
    kinds = [k for k in C["PartTypes"] if k["level"] <= level]
    fams = sorted({c["family"] for c in C["Cars"] if c["level"] <= level})
    vals = [part_price(k["id"], f) for k in kinds for f in fams]
    return sum(vals) / len(vals)


def scrapyard_rate(level):
    tl = at_level(ASSUME["tool_level"], level)
    sl = at_level(ASSUME["scrapyard_level"], level)
    tool_bonus = 1 + (tl - 1) * 0.14                       # SideGameRules.ToolBonus
    found = max(2, (2 + 3) * tool_bonus * (1 + (sl - 1) * 0.12))
    rare = min(1, 0.08 + sl * 0.025)                       # SideGameRules.RareChance
    per_part = MC["ScrapyardSellCredits"] / MC["ScrapyardSellParts"]
    scrap = found * MC["ScrapyardScrapPerPart"]
    value = found * per_part + 45 + scrap * exchange_rate() + rare * rare_part_value(level) - MC["ScrapyardCarCost"]
    xp = (8 + found) + found / MC["ScrapyardSellParts"] * 5  # Zerlegen 8 + Funde, Verkauf 5 je Paket
    cycle = MC["ScrapyardDismantleSeconds"] + ASSUME["scrapyard_overhead"]
    return {
        "cr": value / cycle * 60,
        "xp": xp / cycle * 60,
        "day": value * MC["ScrapyardCarsPerDay"],
        "day_minutes": MC["ScrapyardCarsPerDay"] * cycle / 60,
        "per_car": value,
    }


def arcade_rates():
    A = D["arcade"]
    out = {}
    q = ASSUME["arcade_score"] / A["MaxScore"]
    for g in A["Games"]:
        dur = A["RoundSeconds"][g["key"]] * ASSUME["arcade_duration_share"] + ASSUME["arcade_overhead"]
        cr = math.floor(g["reward"] * q ** A["RewardCurve"] + 0.5)
        xp = math.floor(A["MaxXp"] * q + 1e-6)
        out[g["key"]] = {"title": g["title"], "cr": cr / dur * 60, "xp": xp / dur * 60, "round": cr, "full": g["reward"]}
    return out


def arcade_rate(level):
    xv = xp_value(level)
    best = max(arcade_rates().values(), key=lambda r: r["cr"] + r["xp"] * xv)
    A = D["arcade"]
    return {"cr": best["cr"], "xp": best["xp"], "day": A["DailyCap"], "day_minutes": A["DailyCap"] / best["cr"]}


def track_rate(level):
    c = D["cars"]["Track"]
    bonus = 1 + c["levelBonus"] * (level - 1)
    base = c["baselineSeconds"]
    # ehrlich: erste Runde, dann Verbesserungen bis zur erreichbaren Bestzeit
    honest = (c["firstReward"] + c["perSecond"] * max(0, min(ASSUME["track_first"], base) - ASSUME["track_best"])) * bonus
    t_honest = ASSUME["track_drive_there"] + ASSUME["track_runs"] * ASSUME["track_run_seconds"]
    # Ausreizen: absichtlich langsame erste Runde (bis zur Basiszeit), dann Bestzeit in wenigen Läufen
    gain = c["perSecond"] * max(0, base - ASSUME["track_best"])
    runs = max(1, math.ceil(gain / c["maxReward"]))
    greedy = (c["firstReward"] + min(gain, runs * c["maxReward"])) * bonus
    t_greedy = ASSUME["track_drive_there"] + max(ASSUME["track_run_seconds"], base + 15) + runs * ASSUME["track_run_seconds"]
    if greedy / t_greedy >= honest / t_honest:
        return {"cr": greedy / t_greedy * 60, "xp": (runs + 1) * c["xp"] / t_greedy * 60, "day": max(honest, greedy),
                "day_minutes": t_greedy / 60}
    return {"cr": honest / t_honest * 60, "xp": ASSUME["track_runs"] * c["xp"] / t_honest * 60, "day": max(honest, greedy),
            "day_minutes": t_honest / 60}


def press_sim(minutes, cps=None):
    """Nur Presse: Dauerklicken mit voller Combo, Upgrades gierig nach Schrott-Ertrag je Kosten
    (PressRules.ClickPower/MachinePower, MiniCatalog-Kosten). Rückgabe: Schrott/min gesamt,
    Maschinen-Schrott/min, Summe der Upgrade-Stufen"""
    cps = cps or ASSUME["press_cps"]
    ups = [u for u in D["pressUpgrades"] if u["type"] != 2]
    lv = [0] * len(ups)
    K = MC["PressComboMax"] * cps  # Dauerklicken hält die Combo voll (Fenster 1,8 s)
    g = MC["PressGlobalPerLevel"]
    B, M0, F = MC["PressBaseClick"], MC["PressBaseMachine"], MC["PressMachineEffectFactor"]
    growth = MC["PressUpgradeCostGrowth"]
    click = mach = 0.0
    total = 0
    scrap = 0.0

    def income(c, m, n):
        G = 1 + n * g
        return (B + c) * G * K + (M0 + m) * G

    t = 0.0
    while t < minutes * 60:
        dt = max(5.0, t * 0.01)
        scrap += income(click, mach, total) * dt
        t += dt
        base = income(click, mach, total)
        while True:
            best, best_ratio, best_cost = None, 0, 0
            for i, u in enumerate(ups):
                cost = max(1, math.floor(u["baseCost"] * growth ** lv[i]))
                if cost > scrap:
                    continue
                if u["type"] in (0, 3):
                    gain = income(click + u["baseEffect"], mach, total + 1) - base
                else:
                    gain = income(click, mach + u["baseEffect"] * F, total + 1) - base
                if gain / cost > best_ratio:
                    best, best_ratio, best_cost = i, gain / cost, cost
            if best is None:
                break
            u = ups[best]
            lv[best] += 1
            total += 1
            if u["type"] in (0, 3):
                click += u["baseEffect"]
            else:
                mach += u["baseEffect"] * F
            scrap -= best_cost
            base = income(click, mach, total)
    G = 1 + total * g
    return income(click, mach, total) * 60, (M0 + mach) * G * 60, total


PRESS_CACHE = {}


def press_state(level, timeline):
    # Vergleich bei gleicher investierter Zeit: so lange gepresst, wie die Werkstatt bis zu diesem Level braucht
    minutes = max(5.0, (time_to_level(timeline, level) or 0) / 60)
    key = round(minutes, 1)
    if key not in PRESS_CACHE:
        PRESS_CACHE[key] = press_sim(minutes) + (minutes,)
    return PRESS_CACHE[key]


def press_rate(level, timeline):
    per_min, machine, levels, minutes = press_state(level, timeline)
    return {"cr": per_min * exchange_rate(), "xp": 0.0, "minutes": minutes, "machine": machine * exchange_rate(),
            "levels": levels}


def press_cross(levels):
    glob = levels * MC["PressGlobalPerLevel"]
    return 1 + glob * MC["PressWorkshopShare"], 1 + glob * MC["PressTuningShare"]


def tuning_rates(level, press_tuning=1.0):
    tl = at_level(ASSUME["tuning_level"], level)
    factor = 1 + (tl - 1) * 0.085                                   # TuningRules.LevelFactor
    slots = min(MC["TuningSlotsMax"], MC["TuningSlotsBase"] + tl // MC["TuningSlotsEvery"])
    best, best_name, best_xp = 0.0, "", 0.0
    for p in MC["TuningProjects"]:
        if p["unlock"] > tl:
            continue
        base = round(MC["TuningRewardBase"] * p["minutes"] ** MC["TuningRewardExponent"])
        net = round(base * factor * press_tuning) - round(base * MC["TuningCostShare"])
        rate = net / p["minutes"]
        if rate > best:
            best, best_name = rate, p["name"]
            best_xp = max(1, round(p["minutes"] * MC["TuningXpPerMinute"])) / p["minutes"]
    completed = ASSUME["tuning_completed"].get(level, 0)
    idle = (10 + tl * 4 + completed ** 1.12 * 1.5) * press_tuning   # TuningRules.IdleRate (Formel fest im Code)
    return {"projects": best * slots, "projects_xp": best_xp * slots, "idle": idle, "idle_xp": idle / 80,
            "name": best_name, "slots": slots, "completed": completed}


def cross_bonus(level, timeline):
    """Querboni, die ein Spieler hat, der die Minispiele nebenbei nutzt (CrossBonus.WorkshopReward/DiagReduction)"""
    _, _, levels, _ = press_state(level, timeline)
    press_ws, _ = press_cross(levels)
    tl = at_level(ASSUME["tuning_level"], level)
    tuning_ws = 1 + (tl - 1) * 0.045
    customer = MC["CustomerBonusCap"]
    diag = MC["DiagReductionCap"]
    return press_ws * tuning_ws * customer, diag


# ------------------------------------------------------------------ Ausgabe
def fmt(n):
    if n is None:
        return "–"
    return f"{n:,.0f}".replace(",", ".")


def fmt_time(sec):
    if sec is None:
        return "> 40 Std."
    m = sec / 60
    if m < 90:
        return f"{m:.0f} Min."
    return f"{m / 60:.1f}".replace(".", ",") + " Std."


ACTIVE = [("quiz", "Mechaniker-Quiz"), ("parking", "Parkplatz-Chaos"), ("scrapyard", "Schrottplatz"),
          ("arcade", "Spielhalle (bester Automat)"), ("track", "Teststrecke (Bestzeiten)"),
          ("press", "Schrottpresse (Klicken → Händler)")]


def build():
    timeline, spent = progression()
    rows = {}
    for L in LEVELS:
        xv = xp_value(L)
        w_cr, w_xp = workshop_rate(L)
        r = {"xv": xv, "workshop_cr": w_cr, "workshop": w_cr + w_xp * xv}
        acts = {"quiz": quiz_rate(L), "parking": parking_rate(L), "scrapyard": scrapyard_rate(L),
                "arcade": arcade_rate(L), "track": track_rate(L), "press": press_rate(L, timeline)}
        for k, v in acts.items():
            r[k] = v["cr"] + v["xp"] * xv
            r[k + "_cr"] = v["cr"]
            r[k + "_day"] = v.get("day")
            r[k + "_day_minutes"] = v.get("day_minutes")
        press = acts["press"]
        _, press_tuning = press_cross(press["levels"])
        tun = tuning_rates(L, press_tuning)
        r["press_minutes"] = press["minutes"]
        r["press_levels"] = press["levels"]
        r["projects"] = tun["projects"] + tun["projects_xp"] * xv
        r["idle"] = tun["idle"] + tun["idle_xp"] * xv
        r["press_machine"] = press["machine"]
        r["tuning_name"] = tun["name"]
        r["tuning_slots"] = tun["slots"]
        r["passive"] = r["projects"] + r["idle"] + r["press_machine"]
        r["cross"] = cross_bonus(L, timeline)
        rows[L] = r
    cars = []
    for m in D["cars"]["Models"]:
        if not m.get("dealer"):
            continue
        cars.append((m, time_to_level(timeline, m["level"]), time_to_afford(timeline, m["price"], m["level"])))
    cross_line, _ = progression(cross=lambda lv: cross_bonus(min(lv, 40), timeline))
    cars_cross = {m["id"]: time_to_afford(cross_line, m["price"], m["level"]) for m, _, _ in cars}
    return rows, cars, cars_cross, timeline, cross_line


def markdown(rows, cars, cars_cross, timeline, cross_line):
    out = []
    head = "| Tätigkeit | " + " | ".join(f"Lv {L}" for L in LEVELS) + " |"
    sep = "|---|" + "---:|" * len(LEVELS)
    out.append("#### Credits pro Minute, aktiv gespielt (inkl. Wert der XP über den Level-Bonus)\n")
    out.append(head)
    out.append(sep)
    out.append("| **Werkstatt (2.4.0-Aufträge)** | " + " | ".join(f"**{fmt(rows[L]['workshop'])}**" for L in LEVELS) + " |")
    out.append("| davon reine Auftrags-Credits | " + " | ".join(fmt(rows[L]['workshop_cr']) for L in LEVELS) + " |")
    for key, name in ACTIVE:
        cells = []
        for L in LEVELS:
            v = rows[L][key]
            cells.append(f"{fmt(v)} ({v / rows[L]['workshop'] * 100:.0f} %)")
        out.append(f"| {name} | " + " | ".join(cells) + " |")
    out.append("| Wert von 1 XP (Level-Bonus) | " + " | ".join(f"{rows[L]['xv']:.2f}".replace(".", ",") for L in LEVELS) + " |")
    out.append("")
    out.append("In Klammern: Anteil an der Werkstatt auf demselben Level (Ziel ≤ 60 %). Schrottpresse: so lange "
               "gepresst, wie die Werkstatt bis zu diesem Level braucht (" + ", ".join(
                   f"Lv {L}: {rows[L]['press_minutes']:.0f} Min." for L in LEVELS) + ").\n")
    out.append("#### Passive Einnahmen pro Minute\n")
    out.append(head)
    out.append(sep)
    for key, name in (("projects", "Tuning-Projekte (bestes Projekt × Plätze)"), ("idle", "Passive Tuning-Einnahmen"),
                      ("press_machine", "Presse-Maschinen (→ Händler)")):
        out.append(f"| {name} | " + " | ".join(fmt(rows[L][key]) for L in LEVELS) + " |")
    out.append("| **Summe passiv** | " + " | ".join(
        f"**{fmt(rows[L]['passive'])}** ({rows[L]['passive'] / rows[L]['workshop'] * 100:.0f} %)" for L in LEVELS) + " |")
    out.append("| bestes Projekt (Plätze) | " + " | ".join(
        f"{rows[L]['tuning_name']} ({rows[L]['tuning_slots']})" for L in LEVELS) + " |")
    out.append("")
    out.append("In Klammern: Anteil an der Werkstatt (Ziel ≤ 25 %).\n")
    out.append("#### Tageslimits der Minispiele\n")
    out.append("| Minispiel | Limit je UTC-Tag | Credits/Tag Lv 1 | Credits/Tag Lv 40 | Minuten bis zum Limit |")
    out.append("|---|---|---:|---:|---:|")
    lim = {
        "quiz": f"{MC['QuizPaidPerDay']} bezahlte richtige Antworten",
        "parking": f"{MC['ParkingPaidPerDay']} bezahlte Lösungen",
        "scrapyard": f"{MC['ScrapyardCarsPerDay']} Unfallfahrzeuge",
        "arcade": f"{fmt(D['arcade']['DailyCap'])} Cr",
        "track": "nur neue Bestzeiten (Topf je Spieler)",
    }
    for key, name in ACTIVE[:5]:
        out.append(f"| {name} | {lim[key]} | {fmt(rows[1][key + '_day'])} | {fmt(rows[40][key + '_day'])} | "
                   f"{rows[1][key + '_day_minutes']:.0f} |")
    out.append("")
    out.append("#### Spielhalle je Automat (typisch 700 von 1000 Punkten)\n")
    out.append("| Automat | Credits bei 1000 P. | Credits/Runde | Credits/Min. |")
    out.append("|---|---:|---:|---:|")
    for key, r in arcade_rates().items():
        out.append(f"| {r['title']} | {r['full']} | {r['round']} | {fmt(r['cr'])} |")
    out.append("")
    out.append("#### Zeit bis zum Autokauf (ab Spielstart, Ersparnis nur für dieses Auto)\n")
    out.append("| Auto | Level | Preis | Level erreicht | Kaufbar: nur Werkstatt | Kaufbar: mit Querboni |")
    out.append("|---|---:|---:|---:|---:|---:|")
    for m, t_lv, t_buy in cars:
        out.append(f"| {m['name']} | {m['level']} | {fmt(m['price'])} Cr | {fmt_time(t_lv)} | **{fmt_time(t_buy)}** | "
                   f"{fmt_time(cars_cross[m['id']])} |")
    out.append("")
    out.append("Querboni (Spalte rechts): Parkplatz-Serie gedeckelt (×" + f"{MC['CustomerBonusCap']}".replace(".", ",")
               + "), Diagnosepunkte gedeckelt (−" + f"{MC['DiagReductionCap'] * 100:.0f}" + " % Arbeitszeit), "
               "Tuning-Abteilung wie Annahme, Presse-Anteil nach gleicher Presszeit.\n")
    out.append("#### Werkstatt-Verlauf (nur Aufträge)\n")
    out.append("| Level | 2 | 5 | 10 | 18 | 24 | 30 | 38 | 40 |")
    out.append("|---|" + "---:|" * 8)
    out.append("| erreicht nach | " + " | ".join(fmt_time(time_to_level(timeline, L)) for L in (2, 5, 10, 18, 24, 30, 38, 40)) + " |")
    out.append("")
    return "\n".join(out)


def check(rows, cars):
    errors = []
    for L in LEVELS:
        w = rows[L]["workshop"]
        for key, name in ACTIVE:
            if rows[L][key] > 0.6 * w + 1e-9:
                errors.append(f"Lv {L}: {name} {rows[L][key]:.0f} Cr/min > 60 % der Werkstatt ({w:.0f})")
        if rows[L]["passive"] > 0.25 * w + 1e-9:
            errors.append(f"Lv {L}: passiv {rows[L]['passive']:.0f} Cr/min > 25 % der Werkstatt ({w:.0f})")
    by = {m["id"]: t for m, _, t in cars}
    first = by.get("komet")
    if first is None or not (20 * 60 <= first <= 30 * 60):
        errors.append(f"erstes Auto (Komet C1) nach {fmt_time(first)} statt 20–30 Min.")
    sport = by.get("vektor")
    if sport is None or not (2.5 * 3600 <= sport <= 8 * 3600):
        errors.append(f"Sportwagen (Vektor RS) nach {fmt_time(sport)} statt mehreren Stunden (2,5–8 Std.)")
    for key in ("aureon", "elys"):
        t = by.get(key)
        if t is not None and t < 10 * 3600:
            errors.append(f"{key} nach {fmt_time(t)} – kein Langzeitziel (≥ 10 Std.)")
    prices = [m["price"] for m, _, _ in cars]
    if prices != sorted(prices):
        errors.append("Händlerpreise steigen nicht mit dem Level")
    return errors


# ------------------------------------------------------------------ Tycoon (Tycoon, PHASE4_CONTRACT §8)
def tycoon_sim():
    """Rundendauer je Gebäudetyp mit den echten Regeln (tools/tycoon_sim.lua: TycoonRules + GameConfig.Tycoon).

    Gieriger Spieler wie tests/test_tycoon_rules.lua: alle 15 s sammeln, teuerstes bezahlbares Angebot kaufen.
    Stellschrauben sind ausschließlich GameConfig.Tycoon.Tuning (Scale, CapSeconds, waits, stageWait, ...).
    """
    out = subprocess.run([LUAURUN, "run", os.path.join(ROOT, "tools", "tycoon_sim.lua"), ROOT],
                         capture_output=True, text=True, cwd=ROOT)
    if out.returncode != 0:
        sys.exit("tycoon_sim.lua fehlgeschlagen:\n" + out.stderr + out.stdout)
    return json.loads(out.stdout.strip().splitlines()[-1])


def tycoon_markdown(sim):
    out = ["#### Tycoon: Zeit bis Stufe 5 komplett (aktiv, gieriger Kauf alle 15 s)\n",
           "| Gebäude | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | **komplett** | 2. Runde (Rebirth +15 %) | Bargeld gesamt |",
           "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for t in sim["types"]:
        st = [fmt_time(x) if x is not None else "–" for x in t["stages"]]
        out.append(f"| {t['name']} | " + " | ".join(st) + f" | **{fmt_time(t['seconds'])}** | "
                   f"{fmt_time(t['second']) if t['second'] is not None else '–'} | {fmt(t['produced'])} |")
    lo, hi = sim["target"]["min"], sim["target"]["max"]
    out.append("")
    out.append(f"Ziel (Vertrag §8): ≈ 5 Std. je Durchlauf (geprüft: {fmt_time(lo)} bis {fmt_time(hi)}); "
               "Bargeld bleibt im Durchlauf und wird nie zu Credits.\n")
    return "\n".join(out)


def tycoon_check(sim):
    errors = []
    lo, hi = sim["target"]["min"], sim["target"]["max"]
    for t in sim["types"]:
        sec = t["seconds"]
        if sec is None:
            errors.append(f"Tycoon {t['name']}: Stufe 5 wird nie komplett")
        elif not (lo <= sec <= hi):
            errors.append(f"Tycoon {t['name']}: Rundendauer {fmt_time(sec)} statt {fmt_time(lo)}–{fmt_time(hi)}")
        if sec is not None and t["second"] is not None and t["second"] >= sec:
            errors.append(f"Tycoon {t['name']}: zweite Runde mit Rebirth-Boost nicht schneller")
    return errors


# ------------------------------------------------------------------ Ausbaustufe 4 (PHASE4_CONTRACT §3, §7, §8, §9)
G = D["game"]
XPC = G["XP"]
UNLOCK_LEVEL = {u["key"]: u["level"] for u in G["Unlocks"]}
P4_LEVELS = [1, 5, 10, 15, 20, 30, 40, 50, 72, 90]

# Annahmen zum gemischten Spiel (Ausbaustufe 4). Anteile der Spielzeit je Level-Abschnitt (bis einschließlich Level):
#   workshop = 2.4.0-Aufträge, minigames = Quiz/Parkplatz/Schrottplatz/Spielhalle/Teststrecke im Wechsel,
#   story = Story-Missionen, dann Nebenmissionen (Tageslimit), dann Kiesplatz-Verkäufe,
#   tycoon = Tycoon (eigener Place; XP nur je Stufe und Durchlauf),
#   free = Autos fahren/tunen, Auktionen, Waschstraße, Lobby, Party (keine XP)
MIX = {
    "phases": [
        (14, {"workshop": 0.55, "minigames": 0.15, "story": 0.15, "tycoon": 0.10, "free": 0.05}),
        (49, {"workshop": 0.45, "minigames": 0.10, "story": 0.10, "tycoon": 0.20, "free": 0.15}),
        (999, {"workshop": 0.30, "minigames": 0.10, "story": 0.10, "tycoon": 0.25, "free": 0.25}),
    ],
    "block_minutes": 60,       # die Anteile wechseln sich innerhalb jeder Spielstunde ab
    "hours_per_day": 2.0,      # Spielzeit je Tag (Nebenmissionen: Tageslimit, OW-Gebäude: Offline-Ertrag)
    "tycoon_order": ["werkstatt", "autohaus", "produktion", "schrottplatz"],
    # Kiesplatz: Sekunden für Hingehen/Lesen/Klicken je Kunde (dazu OfferInterval bzw. FailInterval)
    "sale_decide": 10.0,
    # Nebenmissionen: Minuten Aufwand je Mission (das Spiel selbst, ohne Hinweg zur Stadt)
    "side_minutes": {"s_delivery": 4, "s_timetrial": 4, "s_arcade": 3, "s_dismantle": 3, "s_auction": 3,
                     "s_wash": 2, "s_press": 3, "s_tune": 2, "s_quiz": 2, "s_parking": 2, "s_jobs": 5},
    # Werkstatt-Legende: (Level, an dem sie typischerweise fertig wird, Minuten Aufwand außerhalb der bezahlten Aufträge)
    "legend": {"l_jobs100": (10, 30), "l_equipment": (14, 30), "l_bays4": (8, 25)},
    # Wert eines Altteils (OW-Schrottplatz/Produktion) = Verkaufspreis am Schrottplatz je Teil
    "part_value": MC["ScrapyardSellCredits"] / MC["ScrapyardSellParts"],
}

# Dokumentierte Deckel (PHASE4_CONTRACT §4, §7, §8 und docs/BALANCE.md „Deckel der Boni“)
CAPS = {
    "prestige_income": 0.30, "prestige_discount": 0.10, "prestige_rebirth": 0.05,
    "tycoon": {"werkstatt": 0.10, "autohaus": 0.075, "produktion": 0.15, "schrottplatz": 0.15},
    "ow_perk": 0.25, "career": 1.6, "rebirth_pct": 150,
    "dealer_total": 0.30, "tuning_total": 0.40, "scrap_total": 0.40,
}

WS_CACHE = {}


def ws_rate(level):
    """(Credits/min, XP/min) der Werkstatt auf diesem Level (gecacht)"""
    if level not in WS_CACHE:
        WS_CACHE[level] = workshop_rate(level, samples=2500)
    return WS_CACHE[level]


def ws_total(level):
    cr, xp = ws_rate(level)
    return cr + xp * xp_value(level)


def mix_shares(level):
    for upto, shares in MIX["phases"]:
        if level <= upto:
            return shares
    return MIX["phases"][-1][1]


def unlocked(key, level):
    return key is None or UNLOCK_LEVEL.get(key, 1) <= level


# ------------------------------------------------ Story, Nebenmissionen, Kiesplatz
def story_chapters():
    return G["Story"]["Chapters"]


def mission_xp(ci, m):
    r = m.get("reward") or {}
    if r.get("xp") is not None:
        return r["xp"]
    return XPC["StoryMission"][min(ci, len(XPC["StoryMission"])) - 1]


def side_credits(defn, level):
    S = G["Story"]["Side"]
    if defn.get("legend"):
        return defn["credits"]
    f = min(S.get("LevelScaleCap", 3), 1 + S.get("LevelScale", 0) * (max(1, level) - 1))
    return math.floor(defn["credits"] * f + 0.5)


def side_xp(defn):
    return defn["xp"] if defn.get("xp") is not None else XPC["SideMission"]


def side_level(defn):
    key = defn.get("unlock")
    if key is None:
        req = G["Story"]["Requires"]
        if defn["kind"] == "stat":
            key = req["stat"].get(defn.get("stat"))
        elif defn["kind"] == "event":
            key = req["event"].get(defn.get("event"))
    return UNLOCK_LEVEL.get(key, 1) if key else 1


def sale_factor(level):
    S = G["Story"]["Sale"]
    return min(S.get("LevelFactorCap", 3), 1 + S.get("LevelFactor", 0) * (max(1, level) - 1))


def sale_rate(level, special_share=0.0):
    """Kiesplatz: (Credits/min, XP/min) mit der ergiebigsten Preisstufe (Erwartungswert)"""
    S = G["Story"]["Sale"]
    mult = 1 + special_share * (S.get("SpecialMultiplier", 1) - 1)
    best = (0.0, 0.0, -1)
    xv = xp_value(level)
    for t in S["Tiers"]:
        p = t["chance"]
        cr = p * math.floor(t["profit"] * sale_factor(level) + 0.5) * mult
        xp = p * S["Xp"][t["tier"] - 1]
        sec = MIX["sale_decide"] + p * S["OfferInterval"] + (1 - p) * S["FailInterval"]
        val = (cr + xp * xv) / sec
        if val > best[2]:
            best = (cr / sec * 60, xp / sec * 60, val)
    return best[0], best[1]


def mission_rows():
    """(Name, Level, Credits+XP-Wert je Minute, 40-%-Grenze) aller Story-, Neben- und Legenden-Missionen und des Kiesplatzes"""
    share = G["Story"]["Balance"]["Share"]
    rows = []
    for ci, ch in enumerate(story_chapters(), 1):
        L = ch["unlockLevel"]
        xv = xp_value(L)
        total_min = sum(m.get("minutes", 1) for m in ch["Missions"])
        chapter_bonus = XPC["StoryChapter"][min(ci, len(XPC["StoryChapter"])) - 1] * xv / total_min
        for m in ch["Missions"]:
            r = m.get("reward") or {}
            per = (r.get("credits", 0) + mission_xp(ci, m) * xv) / m.get("minutes", 1) + chapter_bonus
            rows.append((f"Story {m['id']}", L, per, share * ws_total(L)))
    side = G["Story"]["Side"]
    for defn in side["Pool"]:
        L0 = side_level(defn)
        for L in sorted({L0} | {x for x in P4_LEVELS if x >= L0}):
            per = (side_credits(defn, L) + side_xp(defn) * xp_value(L)) / MIX["side_minutes"][defn["id"]]
            rows.append((f"Neben {defn['id']}", L, per, share * ws_total(L)))
    for defn in side["Legend"]:
        L, minutes = MIX["legend"][defn["id"]]
        per = (defn["credits"] + side_xp(defn) * xp_value(L)) / minutes
        rows.append((f"Legende {defn['id']}", L, per, share * ws_total(L)))
    special_from = story_chapters()[G["Story"]["Sale"].get("SpecialChapter", 4) - 1]["unlockLevel"]
    for L in P4_LEVELS:
        sp = 1 / G["Story"]["Sale"].get("SpecialEvery", 3) if L >= special_from else 0.0
        cr, xp = sale_rate(L, sp)
        rows.append(("Kiesplatz-Verkauf", L, cr + xp * xp_value(L), share * ws_total(L)))
    return rows


# ------------------------------------------------ Open-World-Gebäude (passiv)
def ow_stage_per_min(typ, st):
    """Credits je Minute einer fertigen Stufe (Schrott über den Händlerkurs, Altteile zum Schrottplatz-Preis,
    Auto-Gutschein zum Händlerpreis des Modells)"""
    cr = st.get("yieldPerHour", 0) / 60
    cr += st.get("scrapPerHour", 0) * exchange_rate() / 60
    cr += st.get("partsPerHour", 0) * MIX["part_value"] / 60
    if st.get("partsEveryHours"):
        cr += st.get("partsPerPack", 0) / st["partsEveryHours"] * MIX["part_value"] / 60
    if st.get("carEveryHours") and st.get("carModel"):
        price = next((m["price"] for m in D["cars"]["Models"] if m["id"] == st["carModel"]), 0)
        cr += price / st["carEveryHours"] / 60
    return cr


def ow_rows():
    """je Gebäude und Stufe: (Typ, Stufe, Level, Cr/min, Anteil an der Werkstatt dieses Levels)"""
    out = []
    for typ in G["OW"]["Types"]:
        b = G["OW"]["Buildings"].get(typ)
        if not b:
            continue
        for st in b["Stages"]:
            L = st.get("level") or 1
            per = ow_stage_per_min(typ, st)
            out.append((b["name"], st["stage"], L, per, per / ws_total(L), st["price"]))
    return out


def ow_combined(level):
    """höchster OW-Ertrag/min auf diesem Level (je Gebäude die höchste baubare Stufe)"""
    total = 0.0
    for typ in G["OW"]["Types"]:
        b = G["OW"]["Buildings"].get(typ)
        if not b:
            continue
        best = 0.0
        for st in b["Stages"]:
            if (st.get("level") or 1) <= level:
                best = max(best, ow_stage_per_min(typ, st))
        total += best
    return total


# ------------------------------------------------ Boni und Deckel
def bonus_caps():
    """(Bezeichnung, Höchstwert, Deckel, ok) für alle Boni der Ausbaustufe 4 und ihre Stapel"""
    P = G["Prestige"]
    T = G["Tycoon"]["Bonus"]
    perks = G["OW"]["Perks"]
    hard = G["OW"].get("PerkCap", 0.25)
    max_bays = 4
    rows = []
    inc = min(P["MaxRank"] * P["IncomePerRank"], P["IncomeCap"])
    rows.append(("Prestige: Einnahmen", inc, CAPS["prestige_income"]))
    disc = min(P["MaxRank"] * P["DiscountPerRank"], P["DiscountCap"])
    rows.append(("Prestige: Händlerrabatt", disc, CAPS["prestige_discount"]))
    rows.append(("Prestige: Tycoon-Rebirth-Zusatz", P["RebirthBonus"], CAPS["prestige_rebirth"]))
    ty = {}
    for typ, cap in CAPS["tycoon"].items():
        ty[typ] = T[typ]["maxRuns"] * T[typ]["step"]
        rows.append((f"Tycoon-Bonus {typ}", ty[typ], cap))
    ow = {}
    for typ, p in perks.items():
        n = (max_bays - 1) if p.get("perBay") else len(G["OW"]["Buildings"][typ]["Stages"])
        ow[typ] = min(p["cap"], hard, n * p["per"])
        rows.append((f"OW-Perk {typ} ({p['label']})", ow[typ], CAPS["ow_perk"]))
    wcap = G.get("WorkshopRewardCap") or 1.6
    rows.append(("Werkstatt-Deckel (GameConfig.WorkshopRewardCap)", wcap, CAPS["career"]))
    career = min(wcap, (1 + ty["werkstatt"]) * (1 + ow["werkstatt"]))
    rows.append(("Werkstatt: Tycoon × OW-Perk (gedeckelt)", career, CAPS["career"]))
    rows.append(("Händlerrabatt gesamt (Prestige + Tycoon + OW)", disc + ty["autohaus"] + ow["autohaus"], CAPS["dealer_total"]))
    rows.append(("Tuning-Tempo gesamt (Tycoon × OW)", (1 + ty["produktion"]) * (1 + ow["produktion"]) - 1, CAPS["tuning_total"]))
    rows.append(("Schrott gesamt (Tycoon × OW)", (1 + ty["schrottplatz"]) * (1 + ow["schrottplatz"]) - 1, CAPS["scrap_total"]))
    rb = G["Tycoon"]["Rebirth"]["capPct"]
    rows.append(("Tycoon-Rebirth-Boost (%)", rb, CAPS["rebirth_pct"]))
    stacked = career * (1 + inc)
    return [(n, v, c, v <= c + 1e-9) for n, v, c in rows], stacked


# ------------------------------------------------ Gemischtes Spiel: Level 50 / Level 90
def minigame_rate(level, timeline):
    """(Credits/min, XP/min) im Wechsel aller freigeschalteten aktiven Minispiele"""
    acts = [("feature:quiz", quiz_rate), ("feature:parking", parking_rate), ("feature:scrapyard", scrapyard_rate),
            ("feature:arcade", arcade_rate), ("feature:track", track_rate)]
    rs = [f(level) for key, f in acts if unlocked(key, level)]
    if not rs:
        p = press_rate(level, timeline)
        return p["cr"], 0.0
    return sum(r["cr"] for r in rs) / len(rs), sum(r["xp"] for r in rs) / len(rs)


def mixed_progression(tycoon, hours=50, seed=11, ws_timeline=None):
    """Gemischtes Spiel nach MIX. Rückgabe: Zeitachse (s, Level, Geld) und XP je Quelle"""
    ws_timeline = ws_timeline or progression()[0]
    c = Career(seed)
    d = c.d
    src = {k: 0.0 for k in ("workshop", "minigames", "story", "side", "sale", "tycoon", "ow", "other")}

    def xp(kind, n):
        src[kind] += n
        gain_xp(d, n)

    tut = G["TutorialReward"]
    d["money"] += tut["credits"]
    xp("other", tut["xp"])
    missions = [(ci, ch["unlockLevel"], m) for ci, ch in enumerate(story_chapters(), 1) for m in ch["Missions"]]
    m_index, m_left = 0, None
    ty_runs = {t: 0 for t in MIX["tycoon_order"]}
    ty_done_total = 0
    ty_time, ty_stage = 0.0, 1
    ty_by = {t["typ"]: t for t in tycoon["types"]}
    ow_stage = {t: 0 for t in G["OW"]["Types"]}
    day_t, side_today = 0.0, 0
    play = 0.0
    block = MIX["block_minutes"] * 60
    while c.t < hours * 3600:
        L = d["level"]
        sh = mix_shares(L)
        t0 = c.t
        # Werkstatt
        end = c.t + sh["workshop"] * block
        while c.t < end:
            c.buy()
            # OW-Gebäude: nächste Stufe, sobald Level und Credits reichen (nach dem Werkstatt-Ausbau)
            for typ in G["OW"]["Types"]:
                b = G["OW"]["Buildings"].get(typ)
                if not b or not b["Stages"] or ow_stage[typ] >= len(b["Stages"]):
                    continue
                st = b["Stages"][ow_stage[typ]]
                if (st.get("level") or 1) <= d["level"] and d["money"] >= st["price"] * 1.5:
                    d["money"] -= st["price"]
                    ow_stage[typ] += 1
                    xp("ow", XPC.get("OwBuild", 0))
            ty_ws = 1 + min(ty_runs["werkstatt"], G["Tycoon"]["Bonus"]["werkstatt"]["maxRuns"]) * G["Tycoon"]["Bonus"]["werkstatt"]["step"]
            perk = G["OW"]["Perks"]["werkstatt"]
            ow_ws = 1 + min(perk["cap"], G["OW"]["PerkCap"], (d["bays"] - 1) * perk["per"])
            mult = min(G.get("WorkshopRewardCap") or 1.6, ty_ws * ow_ws)
            before = d["xp"], d["level"]
            _, x, _ = c.job(mult, 0.0)
            src["workshop"] += x
        # Minispiele
        mins = sh["minigames"] * block / 60
        cr, x = minigame_rate(L, ws_timeline)
        d["money"] += cr * mins
        xp("minigames", x * mins)
        # Story -> Nebenmissionen -> Kiesplatz
        left = sh["story"] * block / 60
        while left > 1e-9 and m_index < len(missions) and missions[m_index][1] <= d["level"]:
            ci, _, m = missions[m_index]
            if m_left is None:
                m_left = m.get("minutes", 1)
            use = min(left, m_left)
            left -= use
            m_left -= use
            if m_left <= 1e-9:
                d["money"] += (m.get("reward") or {}).get("credits", 0)
                xp("story", mission_xp(ci, m))
                m_index += 1
                m_left = None
                if m_index >= len(missions) or missions[m_index][0] != ci:
                    xp("story", XPC["StoryChapter"][min(ci, len(XPC["StoryChapter"])) - 1])
        side = G["Story"]["Side"]
        pool = [s for s in side["Pool"] if side_level(s) <= d["level"]]
        pool.sort(key=lambda s: -(side_credits(s, d["level"]) + side_xp(s) * xp_value(d["level"])) / MIX["side_minutes"][s["id"]])
        for s in pool[:side["Daily"]]:
            if side_today >= side["DailyLimit"] or left <= 1e-9:
                break
            mn = MIX["side_minutes"][s["id"]]
            if mn > left:
                break
            left -= mn
            side_today += 1
            d["money"] += side_credits(s, d["level"])
            xp("side", side_xp(s))
        if left > 1e-9:
            cr, x = sale_rate(d["level"])
            d["money"] += cr * left
            xp("sale", x * left)
        # Tycoon (eigener Durchlauf, XP je Stufe und je Durchlauf)
        tsec = sh["tycoon"] * block
        while tsec > 1e-9:
            typ = MIX["tycoon_order"][ty_done_total % len(MIX["tycoon_order"])]
            info = ty_by[typ]
            run_len = info["seconds"] if ty_done_total == 0 or info.get("second") is None else info["second"]
            scale = run_len / info["seconds"]
            marks = [s * scale for s in info["stages"]] + [run_len]
            step = min(tsec, run_len - ty_time)
            ty_time += step
            tsec -= step
            while ty_stage <= 4 and ty_time >= marks[ty_stage - 1] - 1e-9:
                ty_stage += 1
                xp("tycoon", XPC["TycoonStage"])
            if ty_time >= run_len - 1e-9:
                xp("tycoon", XPC["TycoonRun"])
                ty_runs[typ] += 1
                ty_done_total += 1
                ty_time, ty_stage = 0.0, 1
        # freie Zeit (Autos fahren, Auktionen, Lobby): keine XP
        c.t = t0 + block
        play += block
        # OW-Erträge: während des Spiels und je Tag einmal der Offline-Ertrag bis zum Deckel
        ow_per_min = sum(ow_stage_per_min(t, G["OW"]["Buildings"][t]["Stages"][ow_stage[t] - 1])
                         for t in G["OW"]["Types"] if G["OW"]["Buildings"].get(t) and ow_stage[t] > 0)
        d["money"] += ow_per_min * block / 60
        day_t += block
        if day_t >= MIX["hours_per_day"] * 3600 - 1e-9:
            day_t = 0.0
            side_today = 0
            offline = min(G["OW"]["PassiveCapHours"], 24 - MIX["hours_per_day"])
            d["money"] += ow_per_min * offline * 60
        c.timeline.append((c.t, d["level"], d["money"]))
    return c.timeline, src, ty_done_total, ow_stage


# ------------------------------------------------ Shop
def shop_rows(timeline):
    shop = G["Shop"]
    first_car = min((m for m in D["cars"]["Models"] if m.get("dealer")), key=lambda m: m["level"])
    buyable = [c for c in shop["Cosmetics"] if not c.get("rewardOnly") and c.get("creditsPrice")]
    cos = []
    for c in sorted(buyable, key=lambda c: (c["creditsPrice"], c.get("level", 1))):
        lv = max(first_car["level"], c.get("level", 1))
        cos.append((c, time_to_afford(timeline, first_car["price"] + c["creditsPrice"], lv)))
    dlc = []
    models = {m["id"]: m for m in D["cars"]["Models"]}
    for m in D["cars"]["Models"]:
        if not m.get("dlc"):
            continue
        base = models[m["base"]]
        price = math.floor(m["price"] * shop["DlcPriceFactor"] + 0.5)
        dlc.append((m, base, price, time_to_level(timeline, base["level"]), time_to_afford(timeline, price, m["level"])))
    return first_car, cos, dlc


def shop_check(first_car, cos, dlc):
    errors = []
    if not cos:
        return ["Shop: keine Kosmetik für Credits"]
    c0, t0 = cos[0]
    if t0 is None or t0 > 60 * 60:
        errors.append(f"Shop: erste Kosmetik ({c0['name']}) nach dem ersten Auto erst nach {fmt_time(t0)} statt ≤ 1 Std.")
    if c0["creditsPrice"] < 0.1 * first_car["price"]:
        errors.append(f"Shop: {c0['name']} ({c0['creditsPrice']} Cr) kostet weniger als 10 % des ersten Autos – kein Sparziel")
    by = {c["id"]: c for c, _ in cos}
    for p in G["Shop"]["Products"]:
        cl = (p.get("grants") or {}).get("cosmetics") or []
        if p.get("kind") == "bundle" and p.get("creditsPrice"):
            total = sum(by[i]["creditsPrice"] for i in cl if i in by)
            if p["creditsPrice"] > total:
                errors.append(f"Shop: Bündel {p['name']} teurer ({p['creditsPrice']}) als die Teile einzeln ({total})")
        elif p.get("kind") == "cosmetic" and p.get("creditsPrice") and len(cl) == 1 and cl[0] in by:
            if p["creditsPrice"] != by[cl[0]]["creditsPrice"]:
                errors.append(f"Shop: {p['key']} Credits-Preis {p['creditsPrice']} ≠ Kosmetik {by[cl[0]]['creditsPrice']}")
    for m, base, price, t_lv, t_buy in dlc:
        if m["level"] != base["level"]:
            errors.append(f"DLC {m['name']}: Level {m['level']} ≠ Basismodell {base['name']} ({base['level']})")
        if price < base["price"]:
            errors.append(f"DLC {m['name']}: {price} Cr billiger als das Basismodell ({base['price']})")
        if t_buy is not None and t_lv is not None and t_buy < t_lv:
            errors.append(f"DLC {m['name']}: vor dem Level des Basismodells kaufbar")
    return errors


# ------------------------------------------------ Gesamtrechnung, Ausgabe, Prüfung
def build_phase4(timeline):
    tycoon = tycoon_sim()
    mixed, src, runs, ow_stage = mixed_progression(tycoon, ws_timeline=timeline)
    return {"tycoon": tycoon, "mixed": mixed, "ws_timeline": timeline, "src": src, "runs": runs, "ow_stage": ow_stage,
            "missions": mission_rows(), "ow": ow_rows(), "caps": bonus_caps(), "shop": shop_rows(timeline)}


def phase4_markdown(p4, rows):
    out = ["### Ausbaustufe 4 (PHASE4_CONTRACT)\n"]
    mixed = p4["mixed"]
    marks = [5, 10, 20, 30, 40, 50, 60, 72, 90]
    out.append("#### Level im gemischten Spiel (Werkstatt + Minispiele + Story/Nebenmissionen/Kiesplatz + Tycoon)\n")
    out.append("| Level | " + " | ".join(str(L) for L in marks) + " |")
    out.append("|---|" + "---:|" * len(marks))
    out.append("| erreicht nach | " + " | ".join(fmt_time(time_to_level(mixed, L)) if time_to_level(mixed, L) is not None
                                             else "> 50 Std." for L in marks) + " |")
    out.append("")
    total = sum(p4["src"].values())
    names = {"workshop": "Werkstatt-Aufträge (inkl. Ausbau-XP)", "minigames": "Minispiele", "story": "Story-Missionen",
             "side": "Nebenmissionen", "sale": "Kiesplatz-Verkäufe", "tycoon": "Tycoon (Stufen + Durchläufe)",
             "ow": "OW-Gebäude bauen", "other": "Tutorial"}
    out.append(f"XP-Quellen in 50 Std. ({p4['runs']} Tycoon-Durchläufe):\n")
    out.append("| Quelle | XP | Anteil |")
    out.append("|---|---:|---:|")
    for k, n in sorted(p4["src"].items(), key=lambda kv: -kv[1]):
        out.append(f"| {names[k]} | {fmt(n)} | {n / total * 100:.0f} % |")
    out.append("")
    out.append("Spielzeit-Anteile: " + "; ".join(
        f"bis Level {upto if upto < 999 else '∞'}: " + ", ".join(f"{k} {v * 100:.0f} %" for k, v in sh.items())
        for upto, sh in MIX["phases"]) + ". Die Werkstatt-Aufträge allein erreichen Level 50 nach "
        f"{fmt_time(time_to_level(p4['ws_timeline'], 50))} und Level 90 nach {fmt_time(time_to_level(p4['ws_timeline'], 90))}.\n")
    # Missionen
    out.append("#### Missionen: Credits + XP-Wert je Minute (Grenze 40 % der Werkstatt des Levels)\n")
    out.append("| Mission | Level | Cr/Min | Grenze | Anteil |")
    out.append("|---|---:|---:|---:|---:|")
    seen = set()
    for name, L, per, cap in p4["missions"]:
        if name.startswith("Neben") or name.startswith("Kiesplatz"):
            key = name
            worst = max((r for r in p4["missions"] if r[0] == name), key=lambda r: r[2] / r[3])
            if key in seen:
                continue
            seen.add(key)
            name, L, per, cap = worst
        out.append(f"| {name} | {L} | {fmt(per)} | {fmt(cap)} | {per / cap * 40:.0f} % |")
    out.append("")
    out.append("Neben- und Kiesplatz-Zeilen: jeweils das ungünstigste Level (Nebenmissionen wachsen mit dem Level bis ×3, die "
               "Werkstatt wächst schneller). Aufwand der Nebenmissionen: Annahme `MIX.side_minutes`.\n")
    # OW
    out.append("#### Open-World-Gebäude: passiver Ertrag je Minute (Grenze 25 % der Werkstatt des Stufen-Levels)\n")
    out.append("| Gebäude | Stufe | ab Level | Preis | Cr/Min | Anteil |")
    out.append("|---|---:|---:|---:|---:|---:|")
    for name, stg, L, per, share, price in p4["ow"]:
        out.append(f"| {name} | {stg} | {L} | {fmt(price)} Cr | {fmt(per)} | {share * 100:.0f} % |")
    out.append("")
    out.append("| Level | " + " | ".join(f"Lv {L}" for L in LEVELS) + " |")
    out.append("|---|" + "---:|" * len(LEVELS))
    out.append("| alle OW-Gebäude (höchste baubare Stufe) | " + " | ".join(
        f"{fmt(ow_combined(L))} ({ow_combined(L) / rows[L]['workshop'] * 100:.0f} %)" for L in LEVELS) + " |")
    out.append("| dazu Tuning + Presse-Maschinen | " + " | ".join(
        f"{fmt(rows[L]['passive'])} ({rows[L]['passive'] / rows[L]['workshop'] * 100:.0f} %)" for L in LEVELS) + " |")
    out.append("")
    # Shop
    first_car, cos, dlc = p4["shop"]
    out.append(f"#### Shop: Kosmetik für Credits (Zeit ab Start, gespart für {first_car['name']} + dieses Teil)\n")
    out.append("| Kosmetik | Platz | Level | Preis | kaufbar nach |")
    out.append("|---|---|---:|---:|---:|")
    for c, t in cos:
        out.append(f"| {c['name']} | {c['slot']} | {c.get('level', 1)} | {fmt(c['creditsPrice'])} Cr | {fmt_time(t)} |")
    out.append("")
    out.append("| DLC-Auto | Basismodell | Level | Credits-Preis | Level erreicht | kaufbar (nur Werkstatt) |")
    out.append("|---|---|---:|---:|---:|---:|")
    for m, base, price, t_lv, t_buy in dlc:
        out.append(f"| {m['name']} | {base['name']} | {m['level']} | {fmt(price)} Cr | {fmt_time(t_lv)} | {fmt_time(t_buy)} |")
    out.append("")
    # Boni
    caps, stacked = p4["caps"]
    out.append("#### Deckel der Boni (Prestige, Tycoon, OW-Perks)\n")
    out.append("| Bonus | Höchstwert | Deckel | ok |")
    out.append("|---|---:|---:|---|")
    for n, v, c, ok in caps:
        if "%" in n:
            vs, cs = f"{v:.0f} %", f"{c:.0f} %"
        elif v >= 1 and c >= 1:
            vs, cs = f"×{v:.2f}".replace(".", ","), f"×{c:.2f}".replace(".", ",")
        else:
            vs, cs = f"{v * 100:.1f} %".replace(".", ","), f"{c * 100:.1f} %".replace(".", ",")
        out.append(f"| {n} | {vs} | {cs} | {'ja' if ok else '**nein**'} |")
    out.append("")
    out.append(f"Höchster Werkstatt-Faktor der Ausbaustufe 4: Tycoon × OW-Perk (gedeckelt) × Prestige = "
               f"×{stacked:.2f}".replace(".", ",") + " (dazu die ungedeckelten 3.x-Querboni Presse, Tuning-Abteilung, Kundenbonus).\n")
    return "\n".join(out)


def phase4_check(p4):
    errors = []
    mixed = p4["mixed"]
    t50, t90 = time_to_level(mixed, 50), time_to_level(mixed, 90)
    if t50 is None or not (6.5 * 3600 <= t50 <= 9.5 * 3600):
        errors.append(f"Level 50 im gemischten Spiel nach {fmt_time(t50)} statt ≈ 8 Std. (6,5–9,5)")
    if t90 is None or not (25 * 3600 <= t90 <= 35 * 3600):
        errors.append(f"Level 90 im gemischten Spiel nach {fmt_time(t90) if t90 else '> 50 Std.'} statt 25–35 Std.")
    for t in p4["tycoon"]["types"]:
        sec = t["seconds"]
        if sec is None or not (4 * 3600 <= sec <= 6.5 * 3600):
            errors.append(f"Tycoon {t['name']}: Stufe 5 komplett nach {fmt_time(sec)} statt 4–6,5 Std.")
    for name, L, per, cap in p4["missions"]:
        if per > cap + 1e-9:
            errors.append(f"{name} (Lv {L}): {per:.0f} Cr/min > 40 % der Werkstatt ({cap:.0f})")
    for name, stg, L, per, share, _ in p4["ow"]:
        if share > 0.25 + 1e-9:
            errors.append(f"OW {name} Stufe {stg} (ab Lv {L}): {per:.0f} Cr/min = {share * 100:.0f} % > 25 % der Werkstatt")
    for L in P4_LEVELS:
        if ow_combined(L) > 0.25 * ws_total(L) + 1e-9:
            errors.append(f"OW-Gebäude zusammen auf Lv {L}: {ow_combined(L):.0f} Cr/min > 25 % der Werkstatt")
    errors += shop_check(*p4["shop"])
    caps, _ = p4["caps"]
    for n, v, c, ok in caps:
        if not ok:
            errors.append(f"Deckel überschritten: {n} {v} > {c}")
    return errors


def main():
    if "--tycoon" in sys.argv:
        sim = tycoon_sim()
        print(tycoon_markdown(sim))
        if "--check" in sys.argv:
            errors = tycoon_check(sim)
            for e in errors:
                print("ZIEL VERFEHLT: " + e)
            print(f"Tycoon-Ziele: {len(errors)} Verstöße")
            sys.exit(1 if errors else 0)
        return
    rows, cars, cars_cross, timeline, cross_line = build()
    p4 = build_phase4(timeline)
    md = markdown(rows, cars, cars_cross, timeline, cross_line) + "\n" + tycoon_markdown(p4["tycoon"]) + "\n" \
        + phase4_markdown(p4, rows)
    if "--write-doc" in sys.argv:
        path = os.path.join(ROOT, "docs", "BALANCE.md")
        text = open(path, encoding="utf-8").read()
        a, b = "<!-- SIM:BEGIN -->", "<!-- SIM:END -->"
        i, j = text.index(a) + len(a), text.index(b)
        text = text[:i] + "\n" + md + "\n" + text[j:]
        open(path, "w", encoding="utf-8").write(text)
        print("docs/BALANCE.md aktualisiert")
    else:
        print(md)
    if "--check" in sys.argv:
        errors = check(rows, cars) + tycoon_check(p4["tycoon"]) + phase4_check(p4)
        for e in errors:
            print("ZIEL VERFEHLT: " + e)
        print(f"Balance-Ziele: {len(errors)} Verstöße")
        sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
