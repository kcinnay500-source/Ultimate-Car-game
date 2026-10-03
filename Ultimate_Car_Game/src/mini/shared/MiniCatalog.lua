-- MiniCatalog: Presse-Upgrades (die Quizfragen stehen serverseitig in QuizBank).
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

-- Quizfragen samt Lösung liegen nur auf dem Server (ServerScriptService.Garage.Mini.QuizBank),
-- damit der Antwortschlüssel nie in ReplicatedStorage beim Client landet.

return Catalog
