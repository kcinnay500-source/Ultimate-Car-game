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

Aufruf (aus dem Projektordner):
    python3 tools/economy_sim.py            # Tabellen ausgeben
    python3 tools/economy_sim.py --check    # zusätzlich Ziele prüfen (Exit-Code 1 bei Verstoß)
    python3 tools/economy_sim.py --write-doc  # Tabellenblock in docs/BALANCE.md ersetzen

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


def progression(hours=40, seed=7, cross=None):
    """Spielt nur Werkstatt-Aufträge. Kauft Bühnen, sobald freigeschaltet und bezahlbar, und die Geräte für neue
    Auftragsarten. cross = Funktion(Level) -> (Vergütungsfaktor, Diagnose-Verkürzung) für das Szenario mit
    Minispiel-Querboni. Rückgabe: Liste (Sekunden, Level, Geld) nach jedem Auftrag und die Ausbauausgaben."""
    rng = random.Random(seed)
    ws = Workshop(rng)
    d = {"money": float(C["StartMoney"]), "xp": 0.0, "level": 1, "bays": 1, "offerSlots": 3, "toolLevel": 1}
    owned = {e["id"]: e.get("starter", 0) for e in C["Equipment"]}
    t = 0.0
    timeline = [(0.0, 1, d["money"])]
    spent = 0.0
    while t < hours * 3600:
        # Ausbau: Bühnen zuerst, dann Geräte für freigeschaltete Aufträge
        bought = True
        while bought:
            bought = False
            if d["bays"] < 4 and d["level"] >= C["BayLevels"][d["bays"]]:
                cost = upgrade_cost("bays", d["bays"])
                if d["money"] - cost >= ASSUME["reserve"]:
                    d["money"] -= cost; spent += cost; d["bays"] += 1; bought = True
                    continue
            for j in C["Jobs"]:
                if j["level"] > d["level"]:
                    continue
                for k, v in required_equipment(j).items():
                    if owned.get(k, 0) < v and EQUIP[k]["level"] <= d["level"]:
                        cost = equipment_cost(k, owned.get(k, 0))
                        if d["money"] - cost >= ASSUME["reserve"]:
                            d["money"] -= cost; spent += cost; owned[k] = owned.get(k, 0) + 1; bought = True
                            gain_xp(d, 20)
            # Auftragsannahme und Werkzeugqualität gemäß Annahme-Tabelle nachkaufen
            for key, table in (("offerSlots", ASSUME["offer_slots"]), ("toolLevel", ASSUME["tool_level"])):
                if d[key] < at_level(table, d["level"]):
                    cost = upgrade_cost(key, d[key])
                    if d["money"] - cost >= ASSUME["reserve"]:
                        d["money"] -= cost; spent += cost; d[key] += 1; bought = True
                        gain_xp(d, 25)
        mult, diag = cross(d["level"]) if cross else (1.0, 0.0)
        j, car = ws.pick(d["level"], d["offerSlots"], owned, d["toolLevel"], d["bays"], mult, diag)
        net, x, cycle = job_numbers(j, car, d["toolLevel"], d["bays"], mult, diag)
        t += cycle
        d["money"] += net
        gain_xp(d, x)
        timeline.append((t, d["level"], d["money"]))
    return timeline, spent


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


def main():
    rows, cars, cars_cross, timeline, cross_line = build()
    md = markdown(rows, cars, cars_cross, timeline, cross_line)
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
        errors = check(rows, cars)
        for e in errors:
            print("ZIEL VERFEHLT: " + e)
        print(f"Balance-Ziele: {len(errors)} Verstöße")
        sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
