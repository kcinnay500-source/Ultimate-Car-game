-- QuizBank: Fragen des Mechaniker-Quiz mit Lösung – nur auf dem Server (ServerScriptService.Garage.Mini).
-- Index 1 der Antworten ist richtig; die Reihenfolge mischt der Server pro Frage (SideGameRules.NewQuestion).
-- Der Client bekommt nur Fragetext und gemischte Antworten, nie den Schlüssel.
local QuizBank = {}

QuizBank.Questions = {
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


return QuizBank
