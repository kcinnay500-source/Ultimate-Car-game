-- Localization uses the German source phrase as the stable key.
-- Add translations here or import localization/Ultimate_Car_Game.csv in Creator Hub.
local L={Default="de",Catalog={}}
L.Catalog.en={
    ["Übersicht"]="Overview",["Werkstatt"]="Workshop",["Schrauberwerkstatt"]="Repair workshop",
    ["Teilehandel"]="Parts store",
    ["Diagnose"]="Diagnosis",["Ausbau"]="Upgrades",
    ["Credits"]="Credits",["Level"]="Level",["Ersatzteile"]="Parts",["Ruf"]="Reputation",
    ["Schließen"]="Close",["Zurück"]="Back",["Kaufen"]="Buy",["Auswählen"]="Select",
    ["Auftrag annehmen"]="Accept job",["Ölfilter"]="Oil filter",["Starterbatterie"]="Starter battery",
    ["Radheber"]="Wheel lift",["Ölauffanggerät"]="Oil drain cart",["Bremsflüssigkeitsgerät"]="Brake bleeder",
    ["Motorheber"]="Engine crane",["Diagnosewagen"]="Diagnostic cart",["Reifenmontiermaschine"]="Tire changer",
    ["Druckprüfgerät"]="Pressure tester",["HV-Arbeitsstation"]="High-voltage workstation",
    ["Ölwechsel"]="Oil change",["Fahrzeug-Check"]="Vehicle inspection",["Reifen erneuern"]="Replace tire",
    ["Startprobleme"]="Starting problems",["Bremsen vorne"]="Front brakes",["Zündspule ersetzen"]="Replace ignition coil",
    ["Kühlmittelverlust"]="Coolant leak",["Turbolader ersetzen"]="Replace turbocharger",["Steuerkette erneuern"]="Replace timing chain",
    ["Speicherung aktiv"]="Saving enabled",["Gespeichert"]="Saved",["Nur diese Sitzung"]="Session only",
    ["Werkzeug wählen"]="Choose tool",["Motorhaube öffnen"]="Open hood",["Motorhaube schließen"]="Close hood",
    ["Hebebühne anheben"]="Raise lift",["Hebebühne absenken"]="Lower lift",["Messwerte auslesen"]="Read measurements",
    ["Endkontrolle"]="Final inspection",["Abrechnen"]="Collect payment",["Sofort verfügbar"]="Available immediately",
    ["Nicht genug Werkstatt-Credits."]="Not enough workshop credits.",["Nicht genug Autopunkte."]="Not enough car points.",
}
function L.t(source,args,language)
    local key=tostring(source or "")
    local lang=(language or L.Default):sub(1,2)
    local text=(L.Catalog[lang] and L.Catalog[lang][key]) or key
    if args then
        text=text:gsub("{([%w_]+)}",function(name)
            local value=args[name]
            if value==nil then return "{"..name.."}" end
            if type(value)=="string" then return L.t(value,nil,language) end
            return tostring(value)
        end)
    end
    return text
end
return L
