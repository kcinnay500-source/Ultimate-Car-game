"""District-Module der Stadt "Spielermeile". Jedes Modul hat build(city, lib, tree).

Regeln für alle Module (siehe tools/worldgen/lib.py und docs/CITY_SPEC.md):
* Jeder District ist ein Model unter City.Districts (lib.model(lib.folder(city, "Districts"), NAME)).
* Stationen, Ankunftspunkte und CitySpawn baut zentral tools/worldgen/contract.py - hier nur Kulisse.
* Animierte Objekte (Attribut Anim) gehören unter City.Animated (lib.folder(city, "Animated")).
* Höhen-Stapel §1.2 einhalten (keine überlappenden Oberseiten auf gleicher Höhe), alles verankert.
* Budget: Teile unter `with lib.section("D<n> Name"):` bauen, damit die Zählung pro District stimmt.
"""
ORDER = ["plaza_arrival", "plaza_buildings", "scrapyard", "tuning", "dealer_track", "parking_misc", "kiesplatz",
         "grosswerkstatt"]   # grosswerkstatt zuletzt: räumt sein Gelände (Grenze, Skyline) erst nach den anderen frei
