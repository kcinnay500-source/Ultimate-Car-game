"""Stationen, Ankunftspunkte und CitySpawn (CITY_SPEC §1.5, §5, §7; MERGE_CONTRACT §4).

Zentral und tabellengesteuert, damit der Vertrag unabhängig vom Stand der District-Module erfüllt ist.
District-Module legen KEINE eigenen Stations/Arrivals an, sondern bauen nur die Kulisse drumherum.

Station: City.Stations.<key>, unsichtbares verankertes Part 1x1x1, CanCollide false, Attribute MiniTab
(+ MiniTitle, optional Game / Soon), ProximityPrompt "Öffnen" (E, Hold 0,25, Reichweite 10, ohne Sichtlinie),
Kind-Attachment "Arrival" 6 Studs auf der Spielerseite, 3,5 über dem Boden, Blick zum Anker.
Arrival: City.Arrivals.<key>, unsichtbares Part 2x1x2 mit Mittelpunkt auf Bodenhöhe (CityService
teleportiert nach CFrame * (0, Size.Y/2 + 3, 0) = Boden + 3,5), LookVector = Blickrichtung.
"""
from .lib import CF, TEAL, yaw_towards

SIDE = {"N": (0, -1), "S": (0, 1), "E": (1, 0), "W": (-1, 0)}
LOOK_YAW = {"N": 0, "W": 90, "S": 180, "E": -90}

# key: (MiniTab, Titel, Anker (x,y,z), Spielerseite, Bodenhöhe dort, Extras)
STATIONS = {
    "overview": ("overview", "Empfang · Übersicht", (-26, 3, -208), "S", 0, {}),
    "map": ("map", "Stadtplan · Schnellreise", (26, 3, -208.5), "S", 0, {}),
    "goals": ("goals", "Tagesziele", (40, 3, -214), "W", 0, {}),
    "meile_map": ("map", "Meile-Verzeichnis", (-14, 2.5, -31.5), "S", -0.5, {}),     # Spec X -16 (Pylon verschoben)
    "goals_platz": ("goals", "Infotafel · Tagesziele", (30, 2.5, -145), "S", -0.5, {}),
    "leaderboard": ("leaderboard", "Bestenliste", (-30, 2.5, -145), "S", -0.5, {}),
    "arcade": ("arcade", "Spielhalle · Punkte-Schalter", (-80, 3, -97), "S", 0, {"Soon": True}),
    "quiz": ("quiz", "Meisterschule · Mechaniker-Quiz", (-116, 3, -148), "E", 0, {}),
    # Auktion: Spec X 81 -> 84.5, damit die Spielerseite neben der Portalwand 10 x 10 frei hat (plaza_buildings)
    "auction": ("auction", "Auktionshaus · Bieterkasse", (84.5, 3, -101), "S", 0, {"Soon": True}),
    "auction_consign": ("auction", "Auktionshaus · Einlieferung", (84.5, 3, -51), "N", 0, {"Soon": True}),
    "shop": ("shop", "Credit-Center", (114, 3, -152), "W", 0, {}),
    "parking": ("parking", "Parkplatz-Chaos", (-65, 2.5, -236.5), "S", -1.0, {}),
    "dealer": ("dealer", "Autohaus · Verkauf", (-20, 3, 100), "N", 0, {"Soon": True}),
    "testdrive": ("dealer", "Übergabe · Testfahrt", (90, 3, 70), "W", 0, {"Soon": True}),
    "tuning": ("tuning", "Tuning-Zentrum", (234, 3, -201), "W", 0, {}),
    "dyno": ("tuning", "Leistungsprüfstand", (310, 3, -206), "S", 0, {}),
    "press": ("press", "Schrottpresse", (-321, 3, -220), "E", 0, {}),
    "scrap_trader": ("press", "Schrotthändler · Ankauf", (-220, 3, -213), "S", -1.0, {}),     # Betonzufahrt
    "scrapyard": ("scrapyard", "Zerlegeplatz", (-262, 3, -191), "N", -0.85, {}),        # auf der Fahrzeugwaage
    "carwash": ("carwash", "Waschstraße", (304, 3, 218), "N", -1.0, {"Soon": True}),   # Spec 209: s. parking_misc
    "track": ("track", "Teststrecke", (0, 3, 224), "N", -0.5, {"Soon": True}),
}
ARCADE_GAMES = [
    ("arcade_1", "BLITZ-REAKTION", (-121, 3, -60), "E"),
    ("arcade_2", "BREMSWEG-PROFI", (-121, 3, -72), "E"),
    ("arcade_3", "BOXENSTOPP", (-121, 3, -84), "E"),
    ("arcade_4", "DREHMOMENT", (-121, 3, -96), "E"),
    ("arcade_5", "MOTOR-OHR", (-112, 3, -104), "S"),
    ("arcade_6", "EINPARK-PROFI", (-98, 3, -104), "S"),
    ("arcade_7", "RENNSIMULATOR 1", (-110, 3, -43.5), "S"),     # Spec Z -41: Simulatoren 2.5 nach Norden
    ("arcade_8", "RENNSIMULATOR 2", (-90, 3, -43.5), "S"),
]
for _k, _g, _p, _s in ARCADE_GAMES:
    STATIONS[_k] = ("arcade", "Spielhalle · " + _g.title(), _p, _s, 0, {"Soon": True, "Game": _g})

# key: (x, Bodenhöhe, z, Blickrichtung)
ARRIVALS = {
    "hub": (0, 0, -192, "S"),
    "plaza": (0, -0.5, -165, "S"),
    "arcade": (-63, -0.5, -72, "W"),
    "quiz": (-63, -0.5, -148, "W"),
    "auction": (63, -0.5, -76, "E"),
    "shop": (63, -0.5, -152, "E"),
    "parking": (-65, -1, -230, "N"),
    "dealer": (0, -0.5, 31, "S"),
    "tuning": (204, -1, -201, "E"),
    "press": (-300, -1, -211, "W"),
    "scrap_trader": (-220, -1, -205, "N"),
    "scrapyard": (-262, -0.85, -200, "S"),       # Fahrzeugwaage (Oberseite -0.85)
    "carwash": (186, -1, 190, "E"),
    "track": (0, -0.5, 218, "S"),
    "scrapyard_gate": (-168, -0.95, -201, "W"),   # liegt in der Schrott-Tor-Absenkung (-0.95)
    "park": (-186, -1, 165, "W"),
}
CITY_SPAWN = (0, 0.1, -201)


def build(city, lib, tree):
    st = lib.folder(city, "Stations")
    ar = lib.folder(city, "Arrivals")
    with lib.section("Stationen & Ankunft (unsichtbar)"):
        for key, (tab, title, (x, y, z), side, floor, extra) in STATIONS.items():
            part = lib.part(st, key, (1, 1, 1), CF(x, y, z), TEAL, "SmoothPlastic", transparency=1, collide=False,
                            touch=False, query=True, cast_shadow=False)
            attrs = {"MiniTab": tab, "MiniTitle": title, "PlayerSide": side}
            attrs.update(extra)
            lib.attrs(part, **attrs)
            lib.prompt(part, "Öffnen", title)
            dx, dz = SIDE[side]
            ax, az = dx * 6, dz * 6
            ay = floor + 3.5 - y
            look = CF.at(ax, ay, az, yaw_towards(-ax, -az))
            lib.attachment(part, "Arrival", look)
        for key, (x, fy, z, look) in ARRIVALS.items():
            lib.part(ar, key, (2, 1, 2), CF.at(x, fy, z, LOOK_YAW[look]), TEAL, "SmoothPlastic", transparency=1,
                     collide=False, touch=False, query=False, cast_shadow=False, attrs={"Look": look})
        sp = lib.spawn(city, "CitySpawn", (10, 0.2, 10), CF.at(CITY_SPAWN[0], CITY_SPAWN[1], CITY_SPAWN[2], 180))
    return sp
