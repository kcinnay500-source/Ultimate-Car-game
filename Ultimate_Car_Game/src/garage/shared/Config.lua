-- Ultimate Car Game 2.0. All brands and vehicles below are fictional.
local C = {}
C.Title = "Ultimate Car Game"
C.WorkshopName = "Schrauberwerkstatt"
C.Version = "3.0.0" -- 3.0: Werkstatt + Minispiele + Stadt
C.DaySeconds = 1200 -- Twenty real minutes per shared in-game day.
C.DayStartHour = 8
C.EnableSaving = true
C.SaveInStudio = false
C.DataStoreName = "UltimateCarGame_v2"
C.StudioDataStoreName = "UltimateCarGame_Studio_v2"
C.AutosaveSeconds = 45
C.LeaseSeconds = 180
C.StartMoney = 800
C.MaxBays = 4
C.MaxPlots = 8
-- 3.0: Grundstücks-Pivots an der Spielermeile (docs/CITY_SPEC.md §4.2; x, z in Studs, rot um Y in Grad).
-- rot=0: Nordseite, Front (+Z) zur Meile; rot=180: Südseite. Reihenfolge = Belegung (nahe am Stadtplatz zuerst).
C.PlotSlots = {
    {x=262,z=-109,rot=0}, {x=-262,z=109,rot=180}, {x=-234,z=-109,rot=0}, {x=234,z=109,rot=180},
    {x=412,z=-109,rot=0}, {x=-412,z=109,rot=180}, {x=-384,z=-109,rot=0}, {x=384,z=109,rot=180},
}
C.LiftHeight = 3.6
C.NumberCap = 1e24
C.HotbarSize = 5
C.DefaultLoadout = {"scanner", "ratchet", "oil", "tire", "meter"}
C.ToolOrder = {"scanner", "ratchet", "oil", "tire", "meter", "torque", "screwdriver", "lamp"}
C.Tools = {
    scanner={name="OBD-Tester",short="OBD",color={72,202,221}},
    ratchet={name="Ratsche",short="Ratsche",color={220,226,232}},
    oil={name="Ölservice",short="Öl",color={255,191,82}},
    tire={name="Reifenheber",short="Reifen",color={174,155,250},equipment="wheel_jack"},
    meter={name="Multimeter",short="Messen",color={247,207,73},equipment="diagnostic_rig"},
    torque={name="Drehmomentschlüssel",short="Drehmoment",color={74,155,207},description="Alternative zur Ratsche bei Radbefestigung und Radmontage."},
    screwdriver={name="Schraubendreher",short="Schrauber",color={221,84,68},description="Alternative zur Ratsche beim Aus- und Einbau der Zündspule."},
    lamp={name="Prüfleuchte",short="Leuchte",color={107,218,169},description="Alternative zum OBD-Tester bei der Beleuchtungsprüfung."},
    hand={name="Freie Hand",short="Hand",color={236,196,160},description="Fester Extra-Platz: nichts in der Hand."}, -- 3.0: immer aktiv, nicht Teil von d.loadout
}
C.HandTool="hand" -- 3.0: Start- und Respawn-Werkzeug (freie Hand)
-- Three established marque names, three distinct models each; old IDs retain saved jobs.
C.CarBrands={"Komet","Nord","Vektor"}
C.Cars = {
    {id="komet",brand="Komet",name="Komet C1",body="compact",family="C",level=1,value=6500,reward=1,xp=1,color={48,170,157}},
    {id="komet_s2",brand="Komet",name="Komet S2",body="hot_hatch",family="C",level=3,value=16000,reward=1.25,xp=1.2,color={235,167,48}},
    {id="nord",brand="Nord",name="Nord R4",body="sedan",family="L",level=4,value=26000,reward=1.5,xp=1.35,color={79,132,215}},
    {id="komet_urban",brand="Komet",name="Komet Urban",body="crossover",family="C",level=7,value=32000,reward=1.85,xp=1.5,color={106,150,93}},
    {id="atlas",brand="Nord",name="Nord Atlas Tourer",body="wagon",family="L",level=10,value=48000,reward=2.2,xp=1.7,color={176,190,198}},
    {id="vektor",brand="Vektor",name="Vektor RS",body="sport",family="P",level=18,value=95000,reward=3.6,xp=2.25,color={192,62,77}},
    {id="vektor_gtx",brand="Vektor",name="Vektor GTX",body="gt_coupe",family="P",level=24,value=145000,reward=4.5,xp=2.6,color={117,82,177}},
    {id="aureon",brand="Vektor",name="Vektor Aureon V12",body="super",family="P",level=30,value=245000,reward=5.8,xp=3,color={224,172,60}},
    {id="elys",brand="Nord",name="Nord Elys E9",body="electric",family="P",level=38,value=310000,reward=7,xp=3.6,color={107,199,210}},
}
-- These are planning prices, not displayed as live prices. Set ProductId after creating
-- same-experience Developer Products. Never reuse one ProductId for a different reward.
C.CreditProducts={
    {key="starter",name="Kleine Werkzeugkasse",productId=0,baseRobux=80,credits=3000,bonus=0},
    {key="service",name="Service-Kasse",productId=0,baseRobux=400,credits=16500,bonus=10},
    {key="garage",name="Werkstatt-Kasse",productId=0,baseRobux=800,credits=34500,bonus=15},
    {key="master",name="Meister-Kasse",productId=0,baseRobux=1600,credits=72000,bonus=20},
    {key="fleet",name="Flotten-Kasse",productId=0,baseRobux=4000,credits=187500,bonus=25},
}
C.Families={C="C11 · Kompakt",L="L24 · Mittelklasse",P="P80 · Performance"}
C.Brands={
    {id="nexra",name="Nexra",price=1,quality=0},
    {id="ferrovia",name="Ferrovia",price=1.35,quality=4},
    {id="orvex",name="Orvex",price=1.75,quality=8},
}
C.PartTypes={
    {id="filter",name="Ölfilter",price=18,eta=0,level=1},
    {id="oil",name="Motoröl-Servicepaket",price=32,eta=0,level=1},
    {id="tire",name="Reifen",price=75,eta=60,level=2},
    {id="battery",name="Starterbatterie",price=85,eta=60,level=3},
    {id="brakes",name="Vorderachs-Bremsensatz",price=110,eta=75,level=5},
    {id="fluid",name="Bremsflüssigkeit",price=24,eta=0,level=5},
    {id="coil",name="Zündspule",price=95,eta=60,level=8},
    {id="hose",name="Kühlmittelschlauch",price=80,eta=75,level=12},
    {id="turbo",name="Turbolader",price=280,eta=120,level=18},
    {id="chain",name="Steuerkettensatz",price=320,eta=120,level=26},
    {id="hvmodule",name="HV-Steuermodul",price=480,eta=120,level=38},
}
C.Parts={}
for _,brand in ipairs(C.Brands) do
    for _,family in ipairs({"C","L","P"}) do
        for _,kind in ipairs(C.PartTypes) do
            local multiplier=({C=1,L=1.4,P=2.4})[family]
            table.insert(C.Parts,{id=brand.id.."_"..family.."_"..kind.id,brand=brand.name,name=kind.name,
                kind=kind.id,family=family,quality=brand.quality,price=math.floor(kind.price*brand.price*multiplier+0.5),
                eta=kind.eta,level=kind.level})
        end
    end
end
C.Equipment={
    {id="oil_drain",name="Ölauffanggerät",description="Sichtbarer Auffangbehälter für den Ölservice.",level=1,cost=250,max=5,starter=1},
    {id="wheel_jack",name="Radheber",description="Räder abnehmen, anheben und sicher montieren.",level=2,cost=350,max=5},
    {id="tire_machine",name="Reifenmontiermaschine",description="Neue Reifen montieren und auswuchten.",level=2,cost=700,max=5},
    {id="diagnostic_rig",name="Diagnosewagen",description="Multimeter und erweiterte elektrische Prüfungen.",level=3,cost=520,max=5},
    {id="brake_bleeder",name="Bremsflüssigkeitsgerät",description="Bremsflüssigkeit wechseln und Anlage entlüften.",level=5,cost=780,max=5},
    {id="compressor",name="Druckprüfgerät",description="Dichtheit von Kühlsystem und Leitungen prüfen.",level=12,cost=1650,max=5},
    {id="engine_crane",name="Motorheber",description="Schwere Motorarbeiten und Turboladerwechsel.",level=18,cost=2600,max=5},
    {id="hv_station",name="HV-Arbeitsstation",description="Erweiterte elektrische Fahrzeugaufträge.",level=38,cost=6200,max=5},
}
C.Jobs={
    {id="oil",name="Ölwechsel",level=1,reward=240,xp=42,
        complaint="Die Serviceanzeige leuchtet. Das Öl ist lange nicht gewechselt worden.",
        report="Serviceintervall: überschritten\nÖlzustand: stark gealtert\nFehlerspeicher: kein Eintrag",cause=1,
        answers={"Öl und Filter sind überfällig","Batterie ersetzen","Zündspule ersetzen"},
        steps={
            {name="Altöl an der Ölwanne ablassen",tool="oil",point="OilPort",lifted=true,equipment="oil_drain",effect="drain",seconds=5},
            {name="Passenden Ölfilter montieren",tool="ratchet",point="OilPort",lifted=true,part="filter",effect="filter",seconds=5},
            {name="Motoröl einfüllen",tool="oil",point="EnginePoint",hood=true,lifted=false,part="oil",effect="fill",seconds=4},
        }},
    {id="inspection",name="Fahrzeug-Check",level=1,reward=155,xp=32,
        complaint="Bitte einen Basis-Check vor der nächsten längeren Fahrt durchführen.",
        report="Beleuchtung: Sichtprüfung offen\nReifen: Sichtprüfung offen\nFehlerspeicher: kein Eintrag",cause=2,
        answers={"Motor ersetzen","Sicht- und Funktionsprüfung durchführen","Turbolader ersetzen"},
        steps={
            {name="Beleuchtung prüfen",tool="scanner",point="EnginePoint",lifted=false,seconds=4},
            {name="Reifen und Radbefestigung prüfen",tool="ratchet",point="WheelPoint",lifted=false,seconds=4},
            {name="Betriebswerte kontrollieren",tool="scanner",point="DiagnosticPoint",lifted=false,seconds=4},
        }},
    {id="tire",name="Reifen erneuern",level=2,reward=360,xp=54,
        complaint="Vorne links verliert das Auto ständig Luft.",report="Druck: 1,1 bar\nSchraube in der Lauffläche\nVentil und Felge unauffällig",cause=3,
        answers={"Nur Sensor zurücksetzen","Batterie laden","Beschädigten Reifen erneuern"},
        steps={
            {name="Rad mit Radheber abnehmen",tool="ratchet",point="WheelPoint",lifted=true,equipment="wheel_jack",effect="wheelOut",seconds=5},
            {name="Neuen Reifen montieren",tool="tire",point="WheelPoint",lifted=true,equipment="tire_machine",part="tire",effect="newTire",seconds=7},
            {name="Rad montieren",tool="ratchet",point="WheelPoint",lifted=true,equipment="wheel_jack",effect="wheelIn",seconds=5},
        }},
    {id="battery",name="Startprobleme",level=3,reward=425,xp=62,
        complaint="Beim Startversuch wird alles dunkel und der Anlasser klackt.",report="Ruhespannung 11,6 V\nStartspannung 7,8 V\nMasseleitung: Spannungsabfall unauffällig",cause=1,
        answers={"Batterie verschlissen","Reifendruck zu niedrig","Kühlmittel fehlt"},
        steps={
            {name="Batterie prüfen",tool="meter",point="BatteryPoint",hood=true,lifted=false,equipment="diagnostic_rig",seconds=5},
            {name="Alte Batterie ausbauen",tool="ratchet",point="BatteryPoint",hood=true,lifted=false,effect="batteryOut",seconds=5},
            {name="Neue Batterie einsetzen",tool="ratchet",point="BatteryPoint",hood=true,lifted=false,part="battery",effect="batteryIn",seconds=6},
        }},
    {id="brakes",name="Bremsen vorne",level=5,reward=720,xp=80,
        complaint="An der Vorderachse schleift es beim Bremsen metallisch.",report="Beläge vorne: 1 mm\nScheiben: eingelaufen\nBremsflüssigkeitsservice: fällig",cause=2,
        answers={"ABS-Steuergerät ersetzen","Vorderbremse und Flüssigkeit erneuern","Nur Motoröl wechseln"},
        steps={
            {name="Vorderräder abnehmen",tool="ratchet",point="WheelPoint",lifted=true,equipment="wheel_jack",effect="frontOut",seconds=6},
            {name="Bremsensatz vorne erneuern",tool="ratchet",point="WheelPoint",lifted=true,part="brakes",effect="brakes",seconds=8},
            {name="Vorderräder montieren",tool="ratchet",point="WheelPoint",lifted=true,equipment="wheel_jack",effect="frontIn",seconds=5},
            {name="Bremsflüssigkeit wechseln",tool="oil",point="EnginePoint",hood=true,lifted=false,equipment="brake_bleeder",part="fluid",seconds=7},
        }},
    {id="ignition",name="Zündspule ersetzen",level=8,reward=850,xp=95,
        complaint="Der Motor läuft unruhig. Die Motorkontrollleuchte ist an.",report="P0302: Zündaussetzer\nQuertausch: Fehler wandert mit der Zündspule\nKompression und Kraftstoffdruck: OK",cause=3,
        answers={"Motor mechanisch defekt","Kraftstoffpumpe ersetzen","Zündspule ersetzen"},
        steps={
            {name="Defekte Zündspule ausbauen",tool="ratchet",point="EnginePoint",hood=true,lifted=false,effect="coilOut",seconds=6},
            {name="Neue Zündspule einsetzen",tool="ratchet",point="EnginePoint",hood=true,lifted=false,part="coil",effect="coilIn",seconds=7},
            {name="Fehlerspeicher zurücksetzen",tool="scanner",point="DiagnosticPoint",lifted=false,equipment="diagnostic_rig",seconds=5},
        }},
    {id="cooling",name="Kühlmittelverlust",level=12,reward=1100,xp=115,
        complaint="Das Kühlmittel wird weniger. Unter dem Auto ist eine Pfütze.",report="Druckprüfung: Leck am Schlauch\nÖl und Kühlmittel nicht vermischt\nTemperatursensor plausibel",cause=1,
        answers={"Kühlmittelschlauch undicht","Zylinderkopf sicher defekt","Lambdasonde defekt"},
        steps={
            {name="Kühlsystem prüfen",tool="meter",point="EnginePoint",hood=true,lifted=false,equipment="compressor",seconds=7},
            {name="Schlauch ausbauen",tool="ratchet",point="EnginePoint",hood=true,lifted=false,effect="hoseOut",seconds=6},
            {name="Schlauch erneuern",tool="ratchet",point="EnginePoint",hood=true,lifted=false,part="hose",effect="hoseIn",seconds=8},
        }},
    {id="turbo",name="Turbolader ersetzen",level=18,reward=1800,xp=160,
        complaint="Leistungsverlust und ungewöhnliche Geräusche unter Last.",report="Ladeluftstrecke: dicht\nTurbo-Welle: starkes Spiel\nVerdichter: sichtbare Beschädigung",cause=2,
        answers={"Nur Luftfilter erneuern","Turbolader mechanisch defekt","Batterie laden"},
        steps={
            {name="Motorbereich vorbereiten",tool="ratchet",point="EnginePoint",hood=true,lifted=false,equipment="engine_crane",seconds=8},
            {name="Defekten Lader ausbauen",tool="ratchet",point="OilPort",lifted=true,equipment="engine_crane",effect="turboOut",seconds=10},
            {name="Neuen Turbolader einbauen",tool="ratchet",point="OilPort",lifted=true,equipment="engine_crane",part="turbo",effect="turboIn",seconds=12},
        }},
    {id="chain",name="Steuerkette erneuern",level=26,reward=2700,xp=220,
        complaint="Beim Kaltstart rasselt es. Steuerzeiten sind unplausibel.",report="Nocken-/Kurbelwellensignal: Abweichung\nKettenspanner und Kette: verschlissen\nÖldruck: plausibel",cause=3,
        answers={"Nur Zündkerzen erneuern","Reifen auswuchten","Steuertrieb instand setzen"},
        steps={
            {name="Motor abstützen",tool="ratchet",point="EnginePoint",hood=true,lifted=false,equipment="engine_crane",equipmentLevel=2,seconds=9},
            {name="Steuertrieb freilegen",tool="ratchet",point="EnginePoint",hood=true,lifted=false,seconds=11},
            {name="Neuen Kettensatz einsetzen",tool="ratchet",point="EnginePoint",hood=true,lifted=false,part="chain",seconds=14},
        }},
    {id="hv",name="HV-System Diagnose",level=38,reward=3900,xp=280,
        complaint="Das elektrische Antriebssystem meldet eine Störung.",report="Simulierter Prüfmodus aktiv\nKommunikationsfehler am Steuermodul\nLeitungsprüfung: ohne Befund",cause=1,
        answers={"Steuermodul nach Prüfbefund ersetzen","Starterbatterie blind ersetzen","Nur Reifen wechseln"},
        steps={
            {name="Simulierten Prüfmodus aktivieren",tool="scanner",point="DiagnosticPoint",lifted=false,equipment="hv_station",seconds=8},
            {name="Elektrisches Modul prüfen",tool="meter",point="EnginePoint",hood=true,lifted=false,equipment="hv_station",seconds=12},
            {name="Neues Steuermodul einsetzen",tool="ratchet",point="EnginePoint",hood=true,lifted=false,part="hvmodule",equipment="hv_station",seconds=14},
        }},
}
C.Upgrades={
    {key="bays",name="Weitere Hebebühne",description="Ein angebauter Hallenabschnitt mit eigener Hebebühne. Maximal vier Bühnen.",base=800,growth=1.7,max=4,start=1},
    {key="offerSlots",name="Auftragsannahme",description="Pro Stufe ein zusätzliches Kundenangebot am Empfang. Deine Bühnenzahl bleibt dabei gleich.",base=900,growth=1.48,max=30,start=3},
    {key="toolLevel",name="Werkzeugqualität",description="Jede Stufe erhöht die Arbeitsgeschwindigkeit um 8% der Basis und vergrößert den grünen Zielbereich.",base=700,growth=1.34,max=100,start=1},
}
C.Stations={"home","workshop","parts","upgrades","shop"}
C.StationNames={home="Übersicht",workshop="Werkstatt",parts="Teilehandel",upgrades="Ausbau",shop="Credits-Shop"}
C.StationNames.tools="Werkzeugkiste"
C.BayLevels={1,2,4,8}
-- Alternative hand tools reuse the existing repair steps and timing challenge.
C.Jobs[2].steps[1].alternatives={lamp=true}
C.Jobs[2].steps[2].alternatives={torque=true}
C.Jobs[3].steps[3].alternatives={torque=true}
C.Jobs[5].steps[3].alternatives={torque=true}
C.Jobs[6].steps[1].alternatives={screwdriver=true}
C.Jobs[6].steps[2].alternatives={screwdriver=true}
C.PointNames={DiagnosticPoint="OBD-Anschluss",EnginePoint="Motorraum",BatteryPoint="Batterie",WheelPoint="Rad vorne links",OilPort="Ölwanne / Ölfilter",HoodPoint="Motorhaube"}
-- Small yard tasks share the authoritative timing/reward path; no extra game mode.
-- 3.0: Fahrzeug-Check mit Fehlerspeicher und Kundenfreigabe per Handy (deterministisch je Auftrag).
C.Inspection={FindingChance=0.6,ApproveChance=0.8,RingSeconds=2.5,
    Customers={"Frau Becker","Herr Yilmaz","Frau Schulz","Herr Novak","Frau Weber","Herr Krüger","Frau Hoffmann","Herr Petrović","Frau Lange","Herr Schmitt"}}
-- 3.0: Fehlercodes je Auftragsart (Text nach dem Prüfbericht); leer = „Keine Fehler gespeichert“.
C.FaultCodes={
    oil={{code="P0521",text="Ölzustand: stark gealtert"},{code="S1001",text="Serviceintervall überschritten (Öl und Ölfilter)"}},
    inspection={},
    tire={{code="C0750",text="Reifendruck vorne links: 1,1 bar"},{code="C0751",text="Druckverlust: Schraube in der Lauffläche"}},
    battery={{code="P0562",text="Systemspannung zu niedrig: Ruhespannung 11,6 V"},{code="P0563",text="Startspannung 7,8 V"}},
    brakes={{code="C1095",text="Bremsbeläge vorne: 1 mm"},{code="C1096",text="Bremsflüssigkeitsservice fällig"}},
    ignition={{code="P0302",text="Zylinder 2: Zündaussetzer erkannt"}},
    cooling={{code="P2560",text="Kühlmittelstand zu niedrig: Leck am Schlauch"}},
    turbo={{code="P0299",text="Ladedruck zu niedrig: Turbo-Welle mit starkem Spiel"}},
    chain={{code="P0016",text="Nocken-/Kurbelwellensignal: Abweichung"}},
    hv={{code="U0293",text="Kommunikationsfehler am HV-Steuermodul"}},
}
-- 3.0: Live-Daten des OBD-Testers: Grundwerte und Abweichungen je Befund.
C.LiveValues={{name="Motordrehzahl",value="820 1/min"},{name="Kühlmitteltemperatur",value="88 °C"},
    {name="Batteriespannung",value="12,6 V"},{name="Öltemperatur",value="84 °C"},{name="Reifendruck vorne links",value="2,3 bar"}}
C.LiveFaults={oil={["Öltemperatur"]="96 °C",["Öl-Restlaufzeit"]="überfällig"},tire={["Reifendruck vorne links"]="1,1 bar"},
    battery={Batteriespannung="11,6 V"},brakes={["Bremsbelag vorne"]="1 mm"},ignition={["Zündaussetzer Zylinder 2"]="47 pro Minute"},
    cooling={["Kühlmitteltemperatur"]="104 °C",["Kühlmittelstand"]="zu niedrig"},turbo={Ladedruck="0,4 bar (Soll 1,2 bar)"},
    chain={["Nockenwellen-Versatz"]="+7,5 °KW"},hv={["HV-Kommunikation"]="gestört"}}
C.YardTasks={
    pressure={name="Reifendruck prüfen",tool="meter",seconds=4,reward=35,xp=6,cooldown=120},
    recycle={name="Altteile sortieren",tool=nil,seconds=3,reward=25,xp=5,cooldown=120},
}

C.JobById={}; for _,v in ipairs(C.Jobs) do C.JobById[v.id]=v end
C.CarById={}; for _,v in ipairs(C.Cars) do C.CarById[v.id]=v end
C.PartById={}; for _,v in ipairs(C.Parts) do C.PartById[v.id]=v end
C.EquipmentById={}; for _,v in ipairs(C.Equipment) do C.EquipmentById[v.id]=v end
C.UpgradeById={}; for _,v in ipairs(C.Upgrades) do C.UpgradeById[v.key]=v end


return C
