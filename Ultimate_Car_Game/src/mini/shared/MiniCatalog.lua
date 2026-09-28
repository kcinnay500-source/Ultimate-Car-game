-- MiniCatalog: Presse-Upgrades und Quizfragen.
-- Presse-Upgrades bilden die 100 HTML-Clicker-Upgrades 1:1 ab (Typ = Index % 5, Kosten und Effekt wie HTML).
local Config = require(script.Parent:WaitForChild("MiniConfig"))

local Catalog = {}

-- Typ 0 und 3: Klickstärke, Typ 1 und 4: Schrott pro Sekunde, Typ 2: Ruf- und Credit-Bonus beim Kauf
local NAMES_BY_TYPE = {
	[0] = { "Brecheisen", "Vorschlaghammer", "Hydraulikschere", "Trennschleifer", "Druckluftmeißel", "Rettungsspreizer", "Plasmaschneider", "Hydraulikzylinder", "Pressstempel", "Stahlbacken", "Titanbacken", "Doppelzylinder", "Schneidwerk", "Hochdruckpumpe", "Große Pressplatte", "Diamantschneide", "Turbo-Hydraulik", "Presskammer XXL", "Schwerlast-Kolben", "Meisterpresse" },
	[1] = { "Förderband", "Magnetkran", "Schredder", "Schrottgreifer", "Paketierpresse", "Sortieranlage", "Rüttelsieb", "Wirbelstromabscheider", "Scherenpresse", "Kettenschredder", "Doppelschredder", "Verladekran", "Hammermühle", "Presslinie", "Robotergreifer", "Nachtpresse", "Groß-Schredder", "Recyclingstraße", "Hafenkran", "Schrott-Fabrik" },
	[2] = { "Kleinanzeige", "Abschleppdienst-Deal", "Versicherungskontakt", "Autohaus-Vertrag", "Werkstatt-Netzwerk", "Kommunen-Vertrag", "Flottenrückläufer", "Messestand", "Stahlwerk-Vertrag", "Exportlizenz", "Bahnanschluss", "Großhändler", "Hafenlizenz", "Recycling-Zertifikat", "Umweltsiegel", "Branchenpreis", "Landesvertrag", "Europa-Netz", "Weltmarkt-Kontakt", "Schrott-Imperium" },
	[3] = { "Arbeitshandschuhe", "Schlagschrauber", "Winkelschleifer", "Säbelsäge", "Druckluftschrauber", "Brennschneider", "Kettenzug", "Hebelzange", "Bolzenschneider", "Schneidbrenner Pro", "Akku-Schere", "Pneumatikhammer", "Hydraulikspreizer", "Laserschneider", "Wasserstrahlschneider", "Titanwerkzeug", "Präzisionsschere", "Carbon-Hammer", "Schwerlastzange", "Meisterwerkzeug" },
	[4] = { "Praktikant", "Aushilfe", "Sortierer", "Pressenbediener", "Kranführer", "Schweißer", "Vorarbeiter", "Schichtleiter", "Nachtschicht", "Wochenendteam", "Meister", "Ingenieur", "Spezialistenteam", "Doppelschicht", "Logistikteam", "Werksleiter", "Qualitätsteam", "Zweite Halle", "Dritte Halle", "Konzernzentrale" },
}

Catalog.PressUpgradeTypeLabel = {
	[0] = "Klick",
	[1] = "Maschine",
	[2] = "Händler",
	[3] = "Klick",
	[4] = "Mitarbeiter",
}

Catalog.PressUpgrades = {}
Catalog.PressUpgradeById = {}
for i = 0, Config.PressUpgradeCount - 1 do
	local kind = i % 5
	local u = {
		id = "pu" .. i,
		index = i + 1,
		name = NAMES_BY_TYPE[kind][math.floor(i / 5) + 1],
		type = kind,
		baseCost = math.floor(Config.PressUpgradeCostBase * Config.PressUpgradeCostStep ^ i + 0.5),
		baseEffect = 1 + math.floor(i / 5),
	}
	table.insert(Catalog.PressUpgrades, u)
	Catalog.PressUpgradeById[u.id] = u
end

-- Fragen: Index 1 der Antworten ist richtig; die Reihenfolge mischt der Server pro Frage.
Catalog.Questions = {
	{ q = "Welche Ursache passt am ehesten zu einem zu niedrigen Ladedruck?", a = { "Defektes Wastegate", "Zu hoher Reifendruck", "Leere Wischwasseranlage", "Defekte Innenleuchte" } },
	{ q = "Wofür steht OBD?", a = { "On-Board-Diagnose", "Öl-Brems-Druck", "Offene Batterie-Dose", "Online-Bauteil-Daten" } },
	{ q = "Welche Sicherung schützt einen Stromkreis?", a = { "Schmelzsicherung", "Radlager", "Zündkerze", "Lambdasonde" } },
	{ q = "Was misst eine Lambdasonde?", a = { "Restsauerstoff im Abgas", "Öldruck", "Kühlmittelstand", "Reifentemperatur" } },
	{ q = "Was passiert bei Luft im Bremssystem?", a = { "Pedal kann weich werden", "Motor dreht höher", "Licht wird heller", "Reifen verlieren Profil" } },
	{ q = "Welche Aufgabe hat der Ladeluftkühler?", a = { "Ansaugluft abkühlen", "Motoröl filtern", "Bremsen kühlen", "Kraftstoff erwärmen" } },
	{ q = "Welche Spannung hat ein klassisches Pkw-Bordnetz meist?", a = { "12 Volt", "5 Volt", "48 Kilovolt", "230 Volt" } },
	{ q = "Wozu dient der Zahnriemen bzw. die Steuerkette?", a = { "Nockenwelle und Kurbelwelle synchronisieren", "Klimaanlage befüllen", "Reifen auswuchten", "Scheinwerfer einstellen" } },
	{ q = "Was zeigt die Motorkontrollleuchte an?", a = { "Einen gespeicherten Fehler der Motorsteuerung", "Leeren Tank", "Offene Tür", "Eingeschaltetes Fernlicht" } },
	{ q = "Womit misst man den Säurezustand einer Blei-Batterie klassisch?", a = { "Säureheber (Aräometer)", "Drehmomentschlüssel", "Messschieber", "Kompressionstester" } },
	{ q = "Was prüft ein Kompressionstest?", a = { "Dichtheit der Brennräume", "Reifendruck", "Bremsflüssigkeit", "Ladestrom der Lichtmaschine" } },
	{ q = "Welche Aufgabe hat die Lichtmaschine?", a = { "Bordnetz versorgen und Batterie laden", "Scheinwerfer ausrichten", "Motor starten", "Kühlmittel pumpen" } },
	{ q = "Woran erkennt man abgenutzte Bremsbeläge oft zuerst?", a = { "Quietschen oder Warnleuchte", "Höherer Ölstand", "Hellere Scheinwerfer", "Lauterer Blinker" } },
	{ q = "Wozu dient ein Drehmomentschlüssel?", a = { "Schrauben mit vorgegebener Kraft anziehen", "Spannung messen", "Öl absaugen", "Reifen aufpumpen" } },
	{ q = "Was bewirkt ein Thermostat im Kühlkreislauf?", a = { "Regelt, wann der große Kühlkreislauf öffnet", "Misst die Außentemperatur", "Heizt den Innenraum elektrisch", "Kühlt das Getriebeöl" } },
	{ q = "Wofür ist der Katalysator zuständig?", a = { "Schadstoffe im Abgas umwandeln", "Kraftstoff einspritzen", "Motor schmieren", "Luft ansaugen" } },
	{ q = "Was sollte man vor Arbeiten an einem Hochvolt-System tun?", a = { "System spannungsfrei schalten und prüfen", "Motor laufen lassen", "Nur Handschuhe aus Stoff tragen", "Batterie überbrücken" } },
	{ q = "Was misst ein Multimeter im Modus Ohm?", a = { "Widerstand", "Druck", "Drehzahl", "Temperatur" } },
	{ q = "Welches Bauteil zündet das Gemisch beim Benziner?", a = { "Zündkerze", "Glühkerze", "Einspritzpumpe", "Lambdasonde" } },
	{ q = "Wofür steht ABS?", a = { "Antiblockiersystem", "Automatische Bremsschaltung", "Abgas-Behandlungs-System", "Achsbalance-Steuerung" } },
}

return Catalog
