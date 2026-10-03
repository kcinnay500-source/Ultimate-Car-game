-- Automatisch erzeugt von tools/export_fixture.py: die unveränderten 2.4.0-Skripte aus dem Basisplace.
-- path[1] ist die Dienstklasse, danach die Namen bis zum Skript.
return {
	format = 1,
	sources = {
		{path="base/Ultimate_Car_Game_2.4.0.rbxlx",size=5636778,hash="481beef3348e9985"}
	},
	scripts = {
	{path={"ReplicatedStorage","GarageShared","Config"},class="ModuleScript",source=[[
-- Ultimate Car Game 2.0. All brands and vehicles below are fictional.
local C = {}
C.Title = "Ultimate Car Game"
C.WorkshopName = "Schrauberwerkstatt"
C.Version = "2.4.0"
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
}
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
]]},
	{path={"ReplicatedStorage","GarageShared","Rules"},class="ModuleScript",source=[[
-- Authoritative economy and progression. No client-provided prices or rewards.
local C=require(game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Config"))
local R={}
local function number(v,default,lo,hi)
    if type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return default end
    return math.max(lo or 0,math.min(hi or C.NumberCap,v))
end
local function integer(v,default,lo,hi) return math.floor(number(v,default,lo,hi)) end
local function clone(v,depth)
    if type(v)~="table" then return v end
    if (depth or 0)>12 then return nil end
    local t={};for k,x in pairs(v) do t[k]=clone(x,(depth or 0)+1) end;return t
end
local function add(d,key,amount) d[key]=math.min(C.NumberCap,math.max(0,(d[key] or 0)+amount)) end
local function id(d,prefix) d.serial=d.serial+1;return prefix..d.serial end
local function round(n) return math.floor(n+0.5) end
local function finiteCost(base,growth,level) return math.min(C.NumberCap,round(base*growth^math.min(level,1000))) end
function R.Snapshot(d) return clone(d) end
function R.DayClock(at,epoch)
    local hours=C.DayStartHour+math.max(0,at-epoch)*24/C.DaySeconds
    return hours%24,math.floor(hours/24)
end
function R.NewData(now)
    local d={version=2,workshopVersion=1,days=0,money=C.StartMoney,xp=0,level=1,reputation=0,bays=1,offerSlots=3,
        toolLevel=1,jobs={},offers={},orders={},inventory={nexra_C_filter=3,nexra_C_oil=3},
        equipment={},equipmentBays={},serial=0,completed=0,loadout=clone(C.DefaultLoadout),yardReady={},parkedJobs={}}
    for _,e in ipairs(C.Equipment) do d.equipment[e.id]=e.starter or 0 end
    return d
end
function R.LoadData(raw,_,now)
    now=now or os.time()
    local d=R.NewData(now)
    if type(raw)~="table" or raw.version~=2 then return d end
    d.days=integer(raw.days,0,0,1000000000)
    for _,key in ipairs({"money","xp","reputation","completed"}) do d[key]=number(raw[key],d[key]) end
    for _,key in ipairs({"level"}) do d[key]=integer(raw[key],1,1,1000000) end
    for _,key in ipairs({"serial"}) do d[key]=integer(raw[key],0,0,10000000) end
    for _,u in ipairs(C.Upgrades) do d[u.key]=integer(raw[u.key],u.start,u.start,u.max) end
    -- Retain earned progress from the old six-bay layout. Retired bays are
    -- refunded once; their unfinished jobs wait for a free bay, with parts intact.
    if not raw.workshopVersion and type(raw.bays)=="number" and raw.bays>=5 and raw.bays<=6 then
        for i=5,math.floor(raw.bays) do add(d,"money",finiteCost(800,1.7,i-3)) end
    end
    for _,e in ipairs(C.Equipment) do d.equipment[e.id]=integer(type(raw.equipment)=="table" and raw.equipment[e.id],e.starter or 0,e.starter or 0,e.max) end
    -- Migrate old saves without changing their datastore/schema identity.
    if type(raw.loadout)=="table" then
        d.loadout={};local seen={}
        for i=1,C.HotbarSize do
            local key=raw.loadout[i]
            if type(key)=="string" and C.Tools[key] and not seen[key] then
                table.insert(d.loadout,key);seen[key]=true
            end
        end
        for _,key in ipairs(C.DefaultLoadout) do
            if #d.loadout<C.HotbarSize and not seen[key] then table.insert(d.loadout,key);seen[key]=true end
        end
    end
    for key,def in pairs(C.YardTasks) do
        d.yardReady[key]=number(type(raw.yardReady)=="table" and raw.yardReady[key],0,0,now+def.cooldown)
    end
    if type(raw.inventory)=="table" then
        d.inventory={}
        for sku,count in pairs(raw.inventory) do if C.PartById[sku] then d.inventory[sku]=integer(count,0,0,1000000) end end
    end
    local occupied,seen={},{}
    for _,source in ipairs({type(raw.jobs)=="table" and raw.jobs or {},type(raw.parkedJobs)=="table" and raw.parkedJobs or {}}) do
        for _,j in ipairs(source) do
            local def=type(j)=="table" and C.JobById[j.kind]
            if def and C.CarById[j.carId] and type(j.id)=="string" and #j.id<80 and not seen[j.id] and #d.jobs+#d.parkedJobs<6 then
                local bay=integer(j.bay,1,1,d.bays)
                if occupied[bay] then
                    bay=nil;for i=1,d.bays do if not occupied[i] then bay=i;break end end
                end
                if bay or #d.parkedJobs<2 then
                    seen[j.id]=true;if bay then occupied[bay]=true end
                    local phase=({diagnose=true,repair=true,working=true,verify=true,invoice=true})[j.phase] and j.phase or "diagnose"
                    local entry={id=j.id,kind=j.kind,carId=j.carId,bay=bay,phase=phase,
                        step=integer(j.step,1,1,#def.steps+1),quality=integer(j.quality,100,0,100),scanReady=j.scanReady==true,
                        workUntil=number(j.workUntil,now,0,now+120),selectedParts={},usedParts={}}
                    if entry.step>#def.steps and phase~="invoice" then entry.phase="verify" end
                    if type(j.selectedParts)=="table" then
                        for kind,sku in pairs(j.selectedParts) do
                            local part=C.PartById[sku]
                            if part and part.kind==kind and part.family==C.CarById[j.carId].family then entry.selectedParts[kind]=sku end
                        end
                    end
                    if type(j.usedParts)=="table" then
                        for _,sku in ipairs(j.usedParts) do if C.PartById[sku] and #entry.usedParts<8 then table.insert(entry.usedParts,sku) end end
                    end
                    table.insert(bay and d.jobs or d.parkedJobs,entry)
                end
            end
        end
    end
    if type(raw.orders)=="table" then
        for _,o in ipairs(raw.orders) do
            if type(o)=="table" and C.PartById[o.sku] and #d.orders<30 then
                table.insert(d.orders,{id=type(o.id)=="string" and o.id or id(d,"delivery_"),sku=o.sku,
                    qty=integer(o.qty,1,1,20),eta=number(o.eta,now,0,now+120)})
            end
        end
    end
    local equipmentSlots={}
    for _,e in ipairs(C.Equipment) do
        local bay=type(raw.equipmentBays)=="table" and raw.equipmentBays[e.id]
        if d.equipment[e.id]>0 and type(bay)=="number" and bay%1==0 and bay>=1 and bay<=d.bays and not equipmentSlots[bay] then
            d.equipmentBays[e.id]=bay;equipmentSlots[bay]=true
        end
    end
    R.Advance(d,now)
    return d
end
local function restoreParked(d)
    local occupied={};for _,j in ipairs(d.jobs) do occupied[j.bay]=true end
    for i=1,d.bays do
        if not occupied[i] and d.parkedJobs and #d.parkedJobs>0 then
            local j=table.remove(d.parkedJobs,1);j.bay=i;table.insert(d.jobs,j)
        end
    end
end
function R.XPNeeded(d) return math.floor(80+d.level*22+d.level^1.16*4) end
function R.GainXP(d,n)
    add(d,"xp",n)
    local gained=0
    while d.xp>=R.XPNeeded(d) and d.level<1000000 and gained<1000 do
        d.xp=d.xp-R.XPNeeded(d);d.level=d.level+1;gained=gained+1
        add(d,"money",120+d.level*18);add(d,"reputation",2)
    end
    return gained
end
function R.Advance(d,now)
    local changed,arrived=false,0
    for i=#d.orders,1,-1 do
        local o=d.orders[i]
        if now>=o.eta then
            d.inventory[o.sku]=(d.inventory[o.sku] or 0)+o.qty
            arrived=arrived+o.qty;table.remove(d.orders,i);changed=true
        end
    end
    for _,job in ipairs(d.jobs) do
        if job.phase=="working" and now>=job.workUntil then
            job.step=job.step+1
            job.phase=job.step>#C.JobById[job.kind].steps and "verify" or "repair"
            changed=true
        end
    end
    return changed,arrived
end
function R.FindJob(d,jobId)
    for i,j in ipairs(d.jobs) do if j.id==jobId then return j,i end end
end
function R.ToolActive(d,key)
    for _,id in ipairs(d.loadout) do if id==key then return true end end
    return false
end
function R.ToolUnlocked(d,key)
    local tool=C.Tools[key]
    return tool and (not tool.equipment or (d.equipment[tool.equipment] or 0)>0) or false
end
function R.ToolMatches(step,key)
    return step and (step.tool==key or (step.alternatives and step.alternatives[key])) or false
end
function R.SwapTool(d,slot,key)
    if type(slot)~="number" or slot%1~=0 or slot<1 or slot>C.HotbarSize or not C.Tools[key] then return false,"Ungültiger Werkzeugplatz." end
    if not R.ToolUnlocked(d,key) then return false,"Kaufe zuerst das zugehörige Werkstattgerät." end
    for i,id in ipairs(d.loadout) do
        if id==key then d.loadout[i],d.loadout[slot]=d.loadout[slot],id;return true,"Werkzeugplätze getauscht." end
    end
    d.loadout[slot]=key;return true,"Werkzeug aus der Kiste in die Leiste gelegt."
end
function R.FinishYard(d,key,time)
    local def=C.YardTasks[key]
    if not def or time<(d.yardReady[key] or 0) then return false end
    d.yardReady[key]=time+def.cooldown
    add(d,"money",def.reward);R.GainXP(d,def.xp)
    return true
end
function R.RefreshOffers(d,random)
    random=random or math.random
    local target=math.min(35,d.offerSlots)
    local jobs,cars={},{}
    for _,j in ipairs(C.Jobs) do if j.level<=d.level then table.insert(jobs,j) end end
    for _,c in ipairs(C.Cars) do if c.level<=d.level then table.insert(cars,c) end end
    -- Always retain a free, equipment-independent service job so progression cannot stall.
    local hasInspection=false
    for _,o in ipairs(d.offers) do if o.kind=="inspection" then hasInspection=true end end
    if not hasInspection then table.insert(d.offers,{id=id(d,"offer_"),kind="inspection",carId=cars[random(1,#cars)].id}) end
    while #d.offers<target do
        local j=jobs[random(1,#jobs)]
        local eligible={}
        for _,candidate in ipairs(cars) do
            local electricOk=candidate.id~="elys" or ({inspection=true,tire=true,brakes=true,battery=true,hv=true})[j.id]
            if electricOk then table.insert(eligible,candidate) end
        end
        local car=eligible[random(1,#eligible)]
        if j.id=="hv" then car=C.CarById.elys end
        table.insert(d.offers,{id=id(d,"offer_"),kind=j.id,carId=car.id})
    end
end
function R.RequiredEquipment(d,def)
    for _,step in ipairs(def.steps) do
        if step.equipment and (d.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) then return step.equipment,step.equipmentLevel or 1 end
        local tool=C.Tools[step.tool]
        if tool.equipment and (d.equipment[tool.equipment] or 0)==0 then return tool.equipment,1 end
    end
end
function R.Accept(d,offerId)
    if #d.jobs>=d.bays then return nil,"Alle eigenen Bühnen sind belegt." end
    local offer,index
    for i,o in ipairs(d.offers) do if o.id==offerId then offer,index=o,i;break end end
    if not offer then return nil,"Dieser Auftrag ist nicht mehr verfügbar." end
    local def=C.JobById[offer.kind]
    if not def or def.level>d.level or not C.CarById[offer.carId] or C.CarById[offer.carId].level>d.level then return nil,"Dein Level reicht noch nicht aus." end
    if R.RequiredEquipment(d,def) then return nil,"Kaufe zuerst die benötigten Werkstattgeräte im Ausbau." end
    local used={};for _,j in ipairs(d.jobs) do used[j.bay]=true end
    local bay=1;while used[bay] do bay=bay+1 end
    local job={id=id(d,"job_"),kind=offer.kind,carId=offer.carId,bay=bay,phase="diagnose",step=1,
        quality=100,scanReady=false,selectedParts={},usedParts={}}
    table.insert(d.jobs,job);table.remove(d.offers,index)
    return job
end
function R.Diagnose(job,choice)
    if job.phase~="diagnose" or not job.scanReady then return false,"Lies zuerst die Messwerte aus." end
    local def=C.JobById[job.kind]
    if type(choice)~="number" or choice%1~=0 or not def.answers[choice] then return false,"Ungültige Auswahl." end
    if choice~=def.cause then job.quality=math.max(0,job.quality-5);return false,"Der Befund passt noch nicht. Lies die Messwerte erneut." end
    job.phase="repair";return true,"Diagnose richtig. Die Arbeitsschritte sind freigeschaltet."
end
function R.Compatible(sku,job,kind)
    local part=C.PartById[sku]
    return part and part.kind==kind and part.family==C.CarById[job.carId].family
end
function R.ChoosePart(d,job,kind)
    local preferred=job.selectedParts[kind]
    if preferred then
        if R.Compatible(preferred,job,kind) and (d.inventory[preferred] or 0)>0 then return preferred end
        return nil -- A specifically selected brand is never silently substituted.
    end
    local best
    for _,p in ipairs(C.Parts) do
        if R.Compatible(p.id,job,kind) and (d.inventory[p.id] or 0)>0 and (not best or p.price<C.PartById[best].price) then best=p.id end
    end
    return best
end
function R.SelectPart(d,job,sku)
    local part=C.PartById[sku]
    if not part or part.family~=C.CarById[job.carId].family then return false,"Dieses Teil passt nicht zum Fahrzeug." end
    local required=false
    for _,s in ipairs(C.JobById[job.kind].steps) do if s.part==part.kind then required=true end end
    if not required then return false,"Dieses Teil gehört nicht zu diesem Auftrag." end
    job.selectedParts[part.kind]=sku
    return true,"Marke und passendes Teil sind für den Auftrag ausgewählt."
end
function R.Order(d,sku,qty,now)
    local part=C.PartById[sku]
    if not part or type(qty)~="number" or qty%1~=0 or qty<1 or qty>20 then return false,"Ungültige Bestellung." end
    if part.level>d.level then return false,"Dieses Ersatzteil wird später freigeschaltet." end
    if #d.orders>=30 and part.eta>0 then return false,"Zu viele offene Lieferungen." end
    local cost=part.price*qty
    if d.money<cost then return false,"Nicht genug Werkstatt-Credits." end
    d.money=d.money-cost
    if part.eta==0 then
        d.inventory[sku]=(d.inventory[sku] or 0)+qty
        return true,"Service-Teile sind sofort im Lager."
    end
    table.insert(d.orders,{id=id(d,"delivery_"),sku=sku,qty=qty,eta=now+part.eta})
    return true,"Bestellung aufgegeben. Du kannst inzwischen ein anderes Kundenauto bearbeiten."
end
function R.StepDuration(d,step)
    local eq=step.equipment and (d.equipment[step.equipment] or 1) or 1
    return math.max(1,(step.seconds or 5)/((1+(d.toolLevel-1)*0.08)*(1+(eq-1)*0.12)))
end
function R.StartWork(d,job,now)
    local step=C.JobById[job.kind].steps[job.step]
    if job.phase~="repair" or not step then return false,"Dieser Arbeitsschritt ist nicht verfügbar." end
    if step.equipment and (d.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) then return false,"Das benötigte Gerät fehlt." end
    if step.part then
        local sku=R.ChoosePart(d,job,step.part)
        if not sku then return false,"Das ausgewählte passende Ersatzteil fehlt noch." end
        d.inventory[sku]=d.inventory[sku]-1;table.insert(job.usedParts,sku)
    end
    job.phase="working";job.workUntil=now+R.StepDuration(d,step)
    return true,"Arbeit läuft. Du kannst inzwischen einen anderen Auftrag bearbeiten."
end
function R.Reward(d,job)
    local def,car=C.JobById[job.kind],C.CarById[job.carId]
    local partQuality=0
    for _,sku in ipairs(job.usedParts) do partQuality=partQuality+C.PartById[sku].quality end
    if #job.usedParts>0 then partQuality=partQuality/#job.usedParts end
    local base=def.reward*car.reward
    local reward=round(base*(1+job.quality*0.0025+partQuality*0.01))
    return math.min(C.NumberCap,reward),round(def.xp*car.xp)
end
function R.Settle(d,jobId,now)
    local job,index=R.FindJob(d,jobId)
    if not job or job.phase~="invoice" then return nil,"Die Endkontrolle ist noch nicht abgeschlossen." end
    local reward,xp=R.Reward(d,job)
    table.remove(d.jobs,index) -- Remove before granting anything: replay-safe.
    restoreParked(d)
    add(d,"money",reward);add(d,"completed",1);add(d,"reputation",2)
    local levels=R.GainXP(d,xp)
    return {money=reward,xp=xp,levels=levels,name=C.JobById[job.kind].name,quality=job.quality}
end
function R.CancelJob(d,jobId)
    local _,index=R.FindJob(d,jobId)
    if not index then return false end
    table.remove(d.jobs,index);restoreParked(d);return true
end
function R.EquipmentCost(d,key)
    local e=C.EquipmentById[key]
    return e and finiteCost(e.cost,1.75,d.equipment[key] or 0) or C.NumberCap
end
function R.AssignEquipment(d,key,bay)
    if not C.EquipmentById[key] or (d.equipment[key] or 0)<1 then return false,"Dieses Gerät ist nicht gekauft." end
    if type(bay)~="number" or bay%1~=0 or bay<0 or bay>d.bays then return false,"Diese Bühne ist nicht freigeschaltet." end
    if (d.equipmentBays[key] or 0)==bay then return true,"Das Gerät steht bereits dort." end
    for _,j in ipairs(d.jobs) do
        local step=C.JobById[j.kind].steps[j.step]
        if j.phase=="working" and ((step and step.equipment==key) or j.bay==bay) then return false,"Beende zuerst die Arbeit an dieser Bühne." end
    end
    if bay>0 then
        for other,assigned in pairs(d.equipmentBays) do
            if other~=key and assigned==bay then return false,"Der Geräteplatz ist belegt. Stelle das andere Gerät zuerst ins Lager." end
        end
    end
    d.equipmentBays[key]=bay>0 and bay or nil
    return true,bay>0 and "Gerät an Bühne "..bay.." bereitgestellt." or "Gerät ins Lager zurückgestellt."
end
function R.BuyEquipment(d,key)
    local e=C.EquipmentById[key]
    if not e then return false,"Unbekanntes Gerät." end
    if d.level<e.level then return false,"Dein Level reicht für dieses Gerät noch nicht aus." end
    if (d.equipment[key] or 0)>=e.max then return false,"Dieses Gerät ist bereits voll ausgebaut." end
    local cost=R.EquipmentCost(d,key)
    if d.money<cost then return false,"Nicht genug Werkstatt-Credits." end
    d.money=d.money-cost;d.equipment[key]=(d.equipment[key] or 0)+1;R.GainXP(d,20)
    return true,"Gerät gekauft. Es steht jetzt sichtbar in deiner Werkstatt."
end
function R.UpgradeCost(d,key)
    local u=C.UpgradeById[key]
    return u and finiteCost(u.base,u.growth,d[key]-u.start) or C.NumberCap
end
function R.BuyUpgrade(d,key,expectedStage)
    local u=C.UpgradeById[key]
    if not u or d[key]>=u.max then return false,"Maximale Ausbaustufe erreicht." end
    if key=="bays" and expectedStage~=d.bays then return false,"Der Ausbauzustand hat sich geändert. Öffne den Kauf erneut." end
    if key=="bays" and d.level<C.BayLevels[d.bays+1] then return false,"Die nächste Bühne braucht ein höheres Level." end
    local cost=R.UpgradeCost(d,key)
    if d.money<cost then return false,"Nicht genug Werkstatt-Credits." end
    d.money=d.money-cost;d[key]=d[key]+1
    -- Expansion has one exact price, without a hidden level-up credit grant.
    if key~="bays" then R.GainXP(d,25) end
    return true,"Ausbau abgeschlossen."
end
function R.GaugePosition(now,startAt,period)
    local phase=math.max(0,(now-startAt)/period)%2
    return phase<=1 and phase or 2-phase
end
function R.GaugeHit(now,c)
    return now>=c.startAt+0.12 and now<=c.expires and math.abs(R.GaugePosition(now,c.startAt,c.period)-c.center)<=c.width/2
end
return R
]]},
	{path={"ReplicatedStorage","GarageShared","Locale"},class="ModuleScript",source=[[
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
]]},
	{path={"ServerScriptService","Garage","Profiles"},class="ModuleScript",source=[[
-- Version 2 stores warehouse, deliveries, active jobs and the shared career.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("Rules"))
local Profiles = {}
local store
local enabled = Config.EnableSaving and (not RunService:IsStudio() or Config.SaveInStudio)
if enabled then
    local ok, result = pcall(function()
        return DataStoreService:GetDataStore(RunService:IsStudio() and Config.StudioDataStoreName or Config.DataStoreName)
    end)
    if ok then store = result end
end

function Profiles.Load(player)
    local profile = {data = Rules.LoadData(nil, Config), writable = false, saving = false, status = "Nur diese Sitzung"}
    if not enabled then return profile end
    if not store then profile.status = "Speicher nicht erreichbar"; return profile end
    profile.key = "Player_" .. player.UserId
    profile.token = HttpService:GenerateGUID(false)
    for attempt = 1, 3 do
        local blocked = false
        local ok, result = pcall(function()
            return store:UpdateAsync(profile.key, function(old)
                old = type(old) == "table" and old or {}
                local lock = type(old.lock) == "table" and old.lock or {}
                if type(lock.expires) == "number" and lock.expires > os.time() and lock.token ~= profile.token then
                    blocked = true
                    return nil
                end
                blocked = false
                local data = Rules.LoadData(old.data, Config)
                return {version = 2, data = data, receipts=type(old.receipts)=="table" and old.receipts or {}, lock = {token = profile.token, expires = os.time() + Config.LeaseSeconds}}
            end)
        end)
        if ok and result and not blocked then
            profile.receipts = result.receipts or {}
            profile.data = result.data
            profile.writable = true
            profile.status = "Speicherung aktiv"
            return profile
        end
        if blocked then
            profile.status = "Andere Sitzung aktiv · temporär"
            return profile
        end
        if attempt < 3 then task.wait(attempt) end
    end
    profile.status = "Laden fehlgeschlagen · temporär"
    return profile -- Never overwrite a profile that failed to load.
end

function Profiles.Save(profile, release)
    if not profile.writable or not store or profile.receiptPending then return false end
    if profile.saving then
        if not release then return false end
        local deadline = os.clock() + 12
        while profile.saving and os.clock() < deadline do task.wait(0.1) end
        if profile.saving then return false end
    end
    -- Another concurrent close/save may have released the lease while we waited.
    if not profile.writable or profile.receiptPending then return false end
    profile.saving = true
    local snapshot = Rules.Snapshot(profile.data)
    local success = false
    for attempt = 1, 3 do
        local lostLock = false
        local ok, result = pcall(function()
            return store:UpdateAsync(profile.key, function(old)
                if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.token ~= profile.token then
                    lostLock = true
                    return nil
                end
                local lock
                if not release then lock = {token = profile.token, expires = os.time() + Config.LeaseSeconds} end
                return {version = 2, data = snapshot, receipts=old.receipts or {}, lock = lock}
            end)
        end)
        if ok and result and not lostLock then success = true; break end
        if lostLock then
            profile.writable = false
            profile.status = "Sitzung abgelaufen · temporär"
            break
        end
        if attempt < 3 then task.wait(attempt) end
    end
    profile.saving = false
    if success then
        profile.status = "Gespeichert"
        if release then profile.writable = false end
    elseif profile.writable then
        profile.status = "Speichern wartet auf Verbindung"
    end
    return success
end

-- Credit and receipt marker commit together under the profile lease. An uncertain write
-- keeps economy mutations/saves locked until the same immutable transaction is resolved.
function Profiles.GrantCredits(profile,purchaseId,amount)
    if not profile.writable or not store or type(purchaseId)~="string" or #purchaseId>160 or type(amount)~="number" or amount<=0 or amount%1~=0 then return false end
    if profile.receipts and profile.receipts[purchaseId] then return true,false end
    if profile.receiptPending and profile.receiptPending.id~=purchaseId then return false end
    local deadline=os.clock()+10
    while profile.saving and os.clock()<deadline do task.wait(0.1) end
    if profile.saving or not profile.writable then return false end
    if profile.receipts and profile.receipts[purchaseId] then return true,false end
    if not profile.receiptPending then
        local snapshot=Rules.Snapshot(profile.data)
        local balance=snapshot.money+amount
        if balance>Config.NumberCap or balance-snapshot.money~=amount then return false end
        snapshot.money=balance
        profile.receiptPending={id=purchaseId,amount=amount,snapshot=snapshot}
    end
    local pending=profile.receiptPending
    profile.saving=true;profile.transacting=true
    for attempt=1,3 do
        local lost=false
        local ok,result=pcall(function()
            return store:UpdateAsync(profile.key,function(old)
                if type(old)~="table" or type(old.lock)~="table" or old.lock.token~=profile.token then lost=true;return nil end
                local receipts=type(old.receipts)=="table" and Rules.Snapshot(old.receipts) or {}
                if receipts[purchaseId] then return old end
                receipts[purchaseId]=true
                return {version=2,data=pending.snapshot,receipts=receipts,lock={token=profile.token,expires=os.time()+Config.LeaseSeconds}}
            end)
        end)
        if ok and result and not lost and result.receipts and result.receipts[purchaseId] then
            profile.data.money=result.data.money;profile.receipts=result.receipts
            profile.receiptPending=nil;profile.transacting=false;profile.saving=false;profile.status="Gespeichert"
            return true,true
        end
        if lost then profile.writable=false;profile.status="Kaufbestätigung wartet auf erneuten Beitritt";break end
        if attempt<3 then task.wait(attempt) end
    end
    profile.saving=false;profile.status="Kaufbestätigung wird erneut versucht"
    return false
end

return Profiles
]]},
	{path={"ServerScriptService","Garage","Purchases"},class="ModuleScript",source=[[
local Marketplace=game:GetService("MarketplaceService")
local Players=game:GetService("Players")
local C=require(game:GetService("ReplicatedStorage").GarageShared.Config)
local Profiles=require(script.Parent.Profiles)
local Purchases={}
function Purchases.ByProduct(id)
    if type(id)~="number" or id<=0 then return nil end
    local found
    for _,p in ipairs(C.CreditProducts) do
        if p.productId==id then if found then return nil end;found=p end
    end
    return found
end
function Purchases.Init(getSession,onGranted)
    local retries={}
    local function grant(session,receipt,product)
        local granted,new=Profiles.GrantCredits(session.profile,receipt.PurchaseId,product.credits)
        if granted and new and not session.closing then onGranted(session,product) end
        return granted
    end
    Marketplace.ProcessReceipt=function(receipt)
        local product=Purchases.ByProduct(receipt.ProductId)
        local player=Players:GetPlayerByUserId(receipt.PlayerId)
        local session=player and getSession(player)
        if not product or not session or session.closing or type(receipt.PurchaseId)~="string" then return Enum.ProductPurchaseDecision.NotProcessedYet end
        if grant(session,receipt,product) then return Enum.ProductPurchaseDecision.PurchaseGranted end
        -- Roblox also retries receipts on rejoin. Resolve ambiguous store writes while
        -- the owner remains present so they do not have to spend Robux a second time.
        if not retries[receipt.PurchaseId] and session.profile.receiptPending then
            retries[receipt.PurchaseId]=true
            task.spawn(function()
                while getSession(player)==session and not session.closing and session.profile.writable do
                    task.wait(8)
                    if grant(session,receipt,product) then break end
                end
                retries[receipt.PurchaseId]=nil
            end)
        end
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end
return Purchases
]]},
	{path={"ServerScriptService","Garage","CarFactory"},class="ModuleScript",source=[[
local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local Config = require(Shared.Config)
local Factory = {}

function Factory.Spawn(def, bay, userId, parent, jobId)
    local template = ServerStorage.CarTemplates:FindFirstChild(def.body)
    assert(template, "Missing car template: " .. def.body)
    local car = template:Clone()
    car.Name = jobId or ("Kundenauto_" .. userId)
    car:SetAttribute("OwnerUserId", userId)
    car:SetAttribute("JobId", jobId)
    for _, part in ipairs(car:GetDescendants()) do
        if part:IsA("BasePart") and (part.Name == "Paint" or part.Name == "Hood" or part.Name == "Mirror") then
            part.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
        end
    end
    car:PivotTo(bay.CarOrigin.CFrame)
    car.Parent = parent
    Factory.SetHood(car, false)
    return car
end

function Factory.SetHood(car, open)
    local hood = car:FindFirstChild("Hood")
    if not hood then return end
    local root = car.PrimaryPart.CFrame
    hood.CFrame = root * CFrame.new(0, 3.9, -3.55) * CFrame.Angles(open and math.rad(65) or 0, 0, 0) * CFrame.new(0,0,-1.95)
end

function Factory.AddPrompt(part, callback)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "WorkPrompt"
    prompt.ActionText = "Arbeiten"
    prompt.ObjectText = "Kundenauto"
    prompt.MaxActivationDistance = 8
    prompt.HoldDuration = 0.12
    prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
    prompt.Style = Enum.ProximityPromptStyle.Custom
    prompt:SetAttribute("VehicleAction","work")
    prompt.RequiresLineOfSight = false
    prompt.ClickablePrompt = true
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
    prompt.Enabled = false
    prompt.Parent = part
    prompt.Triggered:Connect(callback)
    return prompt
end

local function visible(car, prefix, show)
    for _, part in ipairs(car:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:sub(1, #prefix) == prefix and part.Name:sub(-5)~="Point" then
            part.Transparency = show and 0 or 1
            part.CanCollide = show
            part.CanQuery = show
        end
    end
end
function Factory.TargetParts(car,job)
    if job.phase=="diagnose" or job.phase=="verify" then return {car:FindFirstChild("OBDPort")} end
    local step=Config.JobById[job.kind].steps[job.step]
    if not step then return {} end
    if step.part=="filter" then return {car.OilFilter,car.OilPan} end
    if step.point=="OilPort" then return {car.OilPan,car.DrainBolt,car.Turbo} end
    if step.point=="BatteryPoint" then return {car.Battery,car.EngineBayFloor} end
    if step.point=="WheelPoint" then return {car.WheelFLTire,car.WheelFLRim,car.BrakeFL} end
    if step.point=="DiagnosticPoint" then return {car:FindFirstChild("OBDPort")} end
    if step.point=="EnginePoint" then return {car.Engine,car.Ignition,car.Hose,car.EngineBayFloor} end
    return {}
end

function Factory.Effect(car, effect)
    if effect == "wheelOut" or effect == "frontOut" then visible(car, "WheelFL", false) end
    if effect == "frontOut" then visible(car, "WheelFR", false) end
    if effect == "wheelIn" or effect == "frontIn" then visible(car, "WheelFL", true) end
    if effect == "frontIn" then visible(car, "WheelFR", true) end
    if effect == "batteryOut" then visible(car, "Battery", false) end
    if effect == "batteryIn" then visible(car, "Battery", true); car.Battery.Color = Color3.fromRGB(70, 172, 132) end
    if effect == "coilOut" then visible(car, "Ignition", false) end
    if effect == "coilIn" then visible(car, "Ignition", true); car.Ignition.Color = Color3.fromRGB(75, 176, 132) end
    if effect == "hoseOut" then visible(car, "Hose", false) end
    if effect == "hoseIn" then visible(car, "Hose", true); car.Hose.Color = Color3.fromRGB(56, 153, 194) end
    if effect == "filter" then car.OilFilter.Color = Color3.fromRGB(241, 186, 69) end
    if effect == "brakes" then
        car.BrakeFL.Color = Color3.fromRGB(220, 229, 236)
        car.BrakeFR.Color = Color3.fromRGB(220, 229, 236)
    end
    if effect == "turboOut" then visible(car,"Turbo",false) end
    if effect == "turboIn" then visible(car,"Turbo",true) end
    if effect == "drain" then car.OilPan.Color=Color3.fromRGB(88,97,105) end
end

function Factory.Equip(player, toolId)
    local character = player.Character
    if not character then return end
    local previous = character:FindFirstChild("GarageTool")
    if previous then previous:Destroy() end
    local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
    if not hand then return end
    local tool = Instance.new("Model")
    tool.Name = "GarageTool"
    tool:SetAttribute("ToolId",toolId)
    local color = Config.Tools[toolId].color
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.16,1.3,0.16)
    if toolId=="scanner" then handle.Size=Vector3.new(0.94,1.24,0.28)
    elseif toolId=="meter" then handle.Size=Vector3.new(0.65,0.95,0.22)
    elseif toolId=="oil" then handle.Size=Vector3.new(1.05,1.2,0.52)
    elseif toolId=="tire" or toolId=="torque" then handle.Size=Vector3.new(0.18,1.65,0.16)
    elseif toolId=="screwdriver" then handle.Size=Vector3.new(0.11,1.2,0.11)
    elseif toolId=="lamp" then handle.Size=Vector3.new(0.25,0.65,0.22) end
    handle.Color = Color3.fromRGB(color[1], color[2], color[3])
    handle.Material = Enum.Material.SmoothPlastic
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    local attachment=hand:FindFirstChild("RightGripAttachment")
    local handGrip=attachment and attachment.CFrame or CFrame.new(0,-hand.Size.Y/2,0)
    local offset=CFrame.Angles(math.rad(-65),0,0)*CFrame.new(0,0.38,0)
    if toolId=="scanner" or toolId=="ratchet" or toolId=="oil" then
        -- Use the attachment's palm position, not its rig-specific tool rotation.
        -- These models are built upright along local Y (R6 and R15 alike).
        handGrip=CFrame.new(handGrip.Position)
    end
    if toolId=="scanner" then
        offset=CFrame.new(0,0,-hand.Size.Z/2-0.04)*CFrame.Angles(math.rad(-55),math.pi,0)*CFrame.new(0,0.4,-0.14)
    elseif toolId=="meter" then
        offset=CFrame.new(0,0.05,-0.28)*CFrame.Angles(math.rad(-25),math.pi,0)
    elseif toolId=="ratchet" then
        offset=CFrame.new(0,-0.02,-hand.Size.Z/2-0.04)*CFrame.Angles(math.rad(-45),0,0)*CFrame.new(0,0.36,0)
    elseif toolId=="oil" then
        offset=CFrame.new(0,0,-0.18)*CFrame.Angles(math.rad(-5),math.pi,0)*CFrame.new(0,-0.79,0)
    elseif toolId=="lamp" then offset=CFrame.Angles(math.rad(-45),0,0)*CFrame.new(0,0.18,0) end
    handle.CFrame=hand.CFrame*handGrip*offset
    handle.Parent = tool
    local weld = Instance.new("Weld")
    weld.Name="ToolGrip"
    weld.C0=handGrip*offset
    weld.Part0 = hand
    weld.Part1 = handle
    weld.Parent = handle
    local function detail(name,size,offset,rgb,shape)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=Color3.fromRGB(rgb[1],rgb[2],rgb[3]);p.Material=Enum.Material.SmoothPlastic
        p.Massless=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
        if shape then p.Shape=shape end
        p.CFrame=handle.CFrame*offset;p.Parent=tool
        local link=Instance.new("WeldConstraint");link.Part0=handle;link.Part1=p;link.Parent=p
        return p
    end
    if toolId=="meter" then
        -- Keep the existing multimeter geometry exactly; only its hand grip changed.
        local screen=detail("Screen",Vector3.new(0.52,0.45,0.025),CFrame.new(0,0.12,-0.125),{23,55,59})
        local surface=Instance.new("SurfaceGui");surface.Face=Enum.NormalId.Front;surface.CanvasSize=Vector2.new(240,160);surface.Parent=screen
        local readout=Instance.new("TextLabel");readout.Name="Readout";readout.Size=UDim2.fromScale(1,1);readout.BackgroundTransparency=1;readout.Text="0.00 V";readout.TextColor3=Color3.fromRGB(86,241,177);readout.TextScaled=true;readout.Font=Enum.Font.Code;readout.Parent=surface
        for i=-1,1 do detail("Key",Vector3.new(0.09,0.09,0.025),CFrame.new(i*0.16,-0.25,-0.13),{37,45,57}) end
        detail("RedProbe",Vector3.new(0.06,0.65,0.06),CFrame.new(0.42,-0.2,0),{219,62,72})
        detail("BlackProbe",Vector3.new(0.06,0.65,0.06),CFrame.new(-0.42,-0.2,0),{25,30,37})
    elseif toolId=="scanner" then
        detail("RubberCase",Vector3.new(1.02,1.32,0.24),CFrame.new(0,0,0.025),{28,40,46})
        local screen=detail("Screen",Vector3.new(0.76,0.64,0.04),CFrame.new(0,0.18,-0.16),{16,47,54})
        local surface=Instance.new("SurfaceGui");surface.Face=Enum.NormalId.Front;surface.CanvasSize=Vector2.new(285,240);surface.Parent=screen
        local readout=Instance.new("TextLabel");readout.Name="Readout";readout.Size=UDim2.fromScale(1,1);readout.BackgroundTransparency=1;readout.Text="OBD READY";readout.TextColor3=Color3.fromRGB(90,238,190);readout.TextScaled=true;readout.Font=Enum.Font.Code;readout.Parent=surface
        for i=-1,1 do detail("Key",Vector3.new(0.14,0.12,0.05),CFrame.new(i*0.24,-0.33,-0.17),{70,192,189}) end
        detail("Connector",Vector3.new(0.35,0.16,0.18),CFrame.new(0,0.72,0),{39,44,49})
        detail("Cable",Vector3.new(0.08,0.38,0.08),CFrame.new(0.08,0.93,0)*CFrame.Angles(0,0,-0.4),{28,31,35})
        detail("OBDPlug",Vector3.new(0.34,0.22,0.18),CFrame.new(0.18,1.16,0),{46,51,58})
    elseif toolId=="ratchet" or toolId=="torque" then
        handle.Material=Enum.Material.Metal;handle.Color=Color3.fromRGB(188,204,215)
        local y=toolId=="torque" and 0.87 or 0.69
        local head=detail("RatchetHead",Vector3.new(0.18,0.48,0.48),CFrame.new(0,y,0)*CFrame.Angles(0,math.pi/2,0),{184,199,210},Enum.PartType.Cylinder);head.Material=Enum.Material.Metal
        detail("Socket",Vector3.new(0.34,0.23,0.23),CFrame.new(0,y,-0.25)*CFrame.Angles(0,math.pi/2,0),{203,213,223},Enum.PartType.Cylinder)
        detail("DirectionSwitch",Vector3.new(0.13,0.07,0.08),CFrame.new(0,y,0.12),{40,54,64})
        detail("Grip",Vector3.new(0.29,0.64,0.28),CFrame.new(0,-0.36,0),toolId=="torque" and {47,131,180} or {38,55,66})
        for i=1,4 do detail("GripBand",Vector3.new(0.30,0.035,0.29),CFrame.new(0,-0.64+i*0.12,0),{28,37,43}) end
        if toolId=="ratchet" then
            local release=detail("QuickRelease",Vector3.new(0.045,0.18,0.18),CFrame.new(0,y,0.12)*CFrame.Angles(0,math.pi/2,0),{226,234,238},Enum.PartType.Cylinder)
            release.Material=Enum.Material.Metal
            local neck=detail("PolishedNeck",Vector3.new(0.22,0.27,0.17),CFrame.new(0,0.43,0),{207,220,229});neck.Material=Enum.Material.Metal
        end
        if toolId=="torque" then detail("TorqueScale",Vector3.new(0.2,0.3,0.04),CFrame.new(0,0.13,-0.10),{239,220,158}) end
    elseif toolId=="oil" then
        detail("HandleLeft",Vector3.new(0.12,0.27,0.18),CFrame.new(-0.2,0.66,0),{47,53,58})
        detail("HandleRight",Vector3.new(0.12,0.27,0.18),CFrame.new(0.2,0.66,0),{47,53,58})
        detail("CarryHandle",Vector3.new(0.5,0.13,0.18),CFrame.new(0,0.79,0),{47,53,58})
        detail("Spout",Vector3.new(0.18,0.55,0.18),CFrame.new(0.45,0.6,0)*CFrame.Angles(0,0,-0.65),{237,195,71})
        detail("Cap",Vector3.new(0.25,0.12,0.25),CFrame.new(0.61,0.83,0)*CFrame.Angles(0,0,-0.65),{35,40,47})
        local label=detail("OilLabel",Vector3.new(0.7,0.55,0.03),CFrame.new(0,-0.06,-0.28),{35,74,89})
        local surface=Instance.new("SurfaceGui");surface.Face=Enum.NormalId.Front;surface.CanvasSize=Vector2.new(280,220);surface.Parent=label
        local title=Instance.new("TextLabel");title.Name="OilTitle";title.Size=UDim2.fromScale(1,1);title.BackgroundTransparency=1
        title.Text="Öl";title.TextColor3=Color3.fromRGB(255,235,164);title.TextScaled=true;title.Font=Enum.Font.GothamBold;title.Parent=surface
    elseif toolId=="tire" then
        handle.Material=Enum.Material.Metal;handle.Color=Color3.fromRGB(177,192,204)
        detail("CurvedNeck",Vector3.new(0.18,0.36,0.14),CFrame.new(0,0.88,-0.08)*CFrame.Angles(-0.55,0,0),{190,202,212})
        detail("PryTip",Vector3.new(0.38,0.25,0.08),CFrame.new(0,1.10,-0.16),{194,203,213})
        detail("Grip",Vector3.new(0.29,0.65,0.28),CFrame.new(0,-0.38,0),{92,73,133})
    elseif toolId=="screwdriver" then
        handle.Material=Enum.Material.Metal;handle.Color=Color3.fromRGB(196,208,215)
        detail("Grip",Vector3.new(0.32,0.6,0.32),CFrame.new(0,-0.35,0),{215,68,58})
        detail("Blade",Vector3.new(0.19,0.22,0.045),CFrame.new(0,0.66,0),{206,218,223})
    elseif toolId=="lamp" then
        detail("LampBody",Vector3.new(0.38,0.85,0.24),CFrame.new(0,0.65,0),{39,63,60})
        local lens=detail("Lens",Vector3.new(0.27,0.68,0.04),CFrame.new(0,0.66,-0.14),{223,255,236});lens.Material=Enum.Material.Neon
        local light=Instance.new("PointLight");light.Range=8;light.Brightness=0.6;light.Parent=lens
    end
    tool.Parent = character
end

function Factory.WorkEffect(car,toolId,point,duration,effect)
    local old=car:FindFirstChild("WorkEffect");if old then old:Destroy() end
    if not point then return end
    local fx=Instance.new("Model");fx.Name="WorkEffect";fx.Parent=car
    local Tween=game:GetService("TweenService")
    local function part(name,size,position,rgb,shape)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=CFrame.new(position);p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
        p.Material=Enum.Material.Neon;p.Color=Color3.fromRGB(rgb[1],rgb[2],rgb[3]);if shape then p.Shape=shape end;p.Parent=fx;return p
    end
    if toolId=="oil" then
        local origin=effect=="drain" and car.OilPan.Position or point.Position+Vector3.new(0,0.6,0)
        local stream=part("OilStream",Vector3.new(0.13,1.7,0.13),origin-Vector3.new(0,0.85,0),effect=="drain" and {87, 60,35} or {224,177,57})
        stream.Material=Enum.Material.SmoothPlastic
        Tween:Create(stream,TweenInfo.new(duration),{Transparency=0.7}):Play()
    elseif toolId=="tire" then
        local wheel=part("RotatingWheel",Vector3.new(0.7,2.2,2.2),point.Position+Vector3.new(-1,0,0),{49,55,65},Enum.PartType.Cylinder)
        wheel.Material=Enum.Material.SmoothPlastic
        local spoke=part("WheelStripe",Vector3.new(0.08,1.8,0.12),wheel.Position+Vector3.new(-0.4,0,0),{203,218,224})
        spoke.Anchored=false;spoke.Massless=true
        local link=Instance.new("WeldConstraint");link.Part0=wheel;link.Part1=spoke;link.Parent=spoke
        Tween:Create(wheel,TweenInfo.new(math.min(2,duration),Enum.EasingStyle.Linear,Enum.EasingDirection.InOut,2),{CFrame=wheel.CFrame*CFrame.Angles(math.pi,0,0)}):Play()
    elseif toolId=="ratchet" or toolId=="torque" or toolId=="screwdriver" then
        local socket=part("TurningSocket",Vector3.new(0.2,0.75,0.2),point.Position,{202,213,220})
        Tween:Create(socket,TweenInfo.new(0.22,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,math.floor(duration/0.44),true),{CFrame=socket.CFrame*CFrame.Angles(0,0,0.8)}):Play()
    else
        local orb=part("TestPulse",Vector3.new(0.4,0.4,0.4),point.Position,toolId=="scanner" and {67,222,211} or {249,206,83},Enum.PartType.Ball)
        Tween:Create(orb,TweenInfo.new(0.4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,math.floor(duration/0.8),true),{Size=Vector3.new(0.85,0.85,0.85),Transparency=0.65}):Play()
    end
    task.delay(duration+0.1,function() if fx.Parent then fx:Destroy() end end)
end

return Factory
]]},
	{path={"ServerScriptService","Garage","World"},class="ModuleScript",source=[[
local SS=game:GetService("ServerStorage")
local TweenService=game:GetService("TweenService")
local C=require(game:GetService("ReplicatedStorage").GarageShared.Config)
local R=require(game:GetService("ReplicatedStorage").GarageShared.Rules)
local F=require(script.Parent.CarFactory)
local W={plots={},slots={}}
local template=workspace:WaitForChild("Werkstatt"):Clone()
template.Name="PlotTemplate";template.Parent=SS
workspace.Werkstatt:Destroy()
local folder=Instance.new("Folder");folder.Name="PlayerWorkshops";folder.Parent=workspace
local function clear(parent) for _,v in ipairs(parent:GetChildren()) do v:Destroy() end end
local function label(model,text)
    local gui=model:FindFirstChildWhichIsA("SurfaceGui",true)
    if gui then local t=gui:FindFirstChildWhichIsA("TextLabel",true);if t then t.Text=text end end
end
local function bindBay(w,bay)
    local prompt=bay.LiftControl:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        prompt.Style=Enum.ProximityPromptStyle.Custom;prompt.MaxActivationDistance=8;prompt:SetAttribute("VehicleAction","lift")
        prompt.Triggered:Connect(function(p) if p==w.owner then w.callback("lift",tonumber(bay.Name:match("%d+"))) end end)
    end
end
local function layout(w,d)
    if w.stage~=d.bays then
        for i=2,d.bays do
            if not W.Bay(w,i) then
                local section=SS.WorkshopExtensions["Stage_"..i]:Clone()
                section:PivotTo(w.model:GetPivot());section.Parent=w.model.Extensions
                local bay=section["Bay_"..i];bay.Parent=w.model.Bays;bindBay(w,bay)
            end
        end
        w.model.EndWall:PivotTo(w.model:GetPivot()*CFrame.new(-32+(d.bays-1)*22,0,0))
        local point=w.model:FindFirstChild("ExpansionPoint")
        if point then
            if d.bays>=C.MaxBays then point:Destroy()
            else point:PivotTo(w.model:GetPivot()*CFrame.new((d.bays-1)*22,0,0)) end
        end
        w.stage=d.bays
    end
    local point=w.model:FindFirstChild("ExpansionPoint")
    if point then
        local cost=R.UpgradeCost(d,"bays");local level=C.BayLevels[d.bays+1]
        local ready=d.money>=cost and d.level>=level
        local status=d.money<cost and "Es fehlen "..math.ceil(cost-d.money).." Cr" or "Guthaben reicht"
        status=status..(d.level<level and " · ab Level "..level or " · E zum Kaufdialog")
        label(point.Sign,"HALLENANBAU + BÜHNE "..(d.bays+1).."\n"..cost.." Cr · Guthaben "..math.floor(d.money).." Cr\n"..status)
        point.Activate.ProximityPrompt.ObjectText="Anbau + Bühne "..(d.bays+1).." · "..cost.." Cr"
        point.Ring.Color=ready and Color3.fromRGB(62,217,166) or Color3.fromRGB(247,176,63)
    end
end
function W.Create(player,callback)
    local slot;for i=1,C.MaxPlots do if not W.slots[i] then slot=i;break end end
    if not slot then return end
    W.slots[slot]=player
    local model=template:Clone();model.Name="Plot_"..player.UserId;model:SetAttribute("OwnerUserId",player.UserId)
    model:PivotTo(CFrame.new(((slot-1)%4)*330,0,math.floor((slot-1)/4)*260));model.Parent=folder
    local w={model=model,slot=slot,cars={},callback=callback,owner=player,doorOpen=true};W.plots[player]=w
    model.RollerDoor:SetAttribute("Open",true)
    model.RollerDoor.Control.ProximityPrompt.Triggered:Connect(function(p) if p==player then callback("door") end end)
    for _,station in ipairs(model.Stations:GetChildren()) do
        local prompt=station:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt.Triggered:Connect(function(p) if p==player then callback("station",station.Name) end end) end
    end
    for _,bay in ipairs(model.Bays:GetChildren()) do bindBay(w,bay) end
    model.ExpansionPoint.Activate.ProximityPrompt.Triggered:Connect(function(p) if p==player then callback("expand") end end)
    local yard=model:FindFirstChild("YardActivities")
    if yard then for _,point in ipairs(yard:GetChildren()) do
        local prompt=point:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt.Triggered:Connect(function(p) if p==player then callback("yard",point.Name) end end) end
    end end
    return w
end
function W.Bay(w,index) return w.model.Bays:FindFirstChild("Bay_"..index) end
local function doorwayOccupied(w)
    local origin=w.model.RollerDoor.ClosedOrigin.Position
    for _,player in ipairs(game:GetService("Players"):GetPlayers()) do
        local character=player.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
        if root then
            local delta=root.Position-origin
            if math.abs(delta.X)<11 and math.abs(delta.Z)<2 and math.abs(delta.Y)<7 then return true end
        end
    end
    return false
end
function W.RollDoor(w,done)
    if w.doorMoving then return false,"Warte, bis das Rolltor stillsteht." end
    local opening=not w.doorOpen
    if not opening and doorwayOccupied(w) then return false,"Der Torbereich ist belegt." end
    local door=w.model.RollerDoor;local panel=door.Panel;local prompt=door.Control.ProximityPrompt
    w.doorMoving=true;prompt.Enabled=false;panel.CanCollide=false
    local height=opening and 0.3 or 11.8
    local target=door.ClosedOrigin.CFrame*CFrame.new(0,(11.8-height)/2,0)
    local tween=TweenService:Create(panel,TweenInfo.new(1.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Size=Vector3.new(19.8,height,0.25),CFrame=target})
    w.doorTween=tween
    local link
    link=tween.Completed:Connect(function(result)
        link:Disconnect()
        if w.doorTween~=tween or result~=Enum.PlaybackState.Completed or not w.model.Parent then return end
        w.doorTween=nil;w.doorMoving=false;w.doorOpen=opening
        if not opening and doorwayOccupied(w) then
            W.RollDoor(w,done);return
        end
        panel.CanCollide=not opening;door:SetAttribute("Open",opening)
        prompt.ActionText=opening and "Rolltor schließen" or "Rolltor öffnen";prompt.Enabled=true
        if done then done() end
    end)
    tween:Play();return true
end
function W.SafeArrival(w,target)
    for _,v in pairs(w.cars) do
        if target:IsDescendantOf(v.model) or target:IsDescendantOf(v.bay) then
            local arrival=v.bay:FindFirstChild("PlayerArrival")
            local pos=arrival and arrival.Position or (v.origin*CFrame.new(-6.4,3.5,6)).Position
            local toward=Vector3.new(v.origin.Position.X,pos.Y,v.origin.Position.Z)
            return CFrame.lookAt(pos,toward)
        end
    end
end
function W.Spawn(w,job)
    if w.cars[job.id] then return w.cars[job.id] end
    local bay=W.Bay(w,job.bay)
    local car=F.Spawn(C.CarById[job.carId],bay,w.owner.UserId,w.model.ActiveCars,job.id)
    local v={model=car,bay=bay,lifted=false,hood=false,moving=false,origin=bay.CarOrigin.CFrame,liftOrigin=bay.MovingLift:GetPivot()}
    w.cars[job.id]=v
    local def=C.JobById[job.kind]
    local completed=job.step-1+(job.phase=="working" and 1 or 0)
    for i=1,math.min(completed,#def.steps) do F.Effect(car,def.steps[i].effect) end
    for _,key in ipairs({"DiagnosticPoint","EnginePoint","BatteryPoint","WheelPoint","OilPort"}) do
        local prompt=F.AddPrompt(car[key],function(p) if p==w.owner then w.callback("work",job.id,key) end end)
        prompt:SetAttribute("JobId",job.id)
    end
    local hood=F.AddPrompt(car.HoodPoint,function(p) if p==w.owner then w.callback("hood",job.id) end end)
    hood.Name="HoodPrompt";hood.ActionText="Motorhaube öffnen";hood.Enabled=true
    hood.KeyboardKeyCode=Enum.KeyCode.H;hood.GamepadKeyCode=Enum.KeyCode.ButtonY
    hood:SetAttribute("VehicleAction","hood");hood:SetAttribute("JobId",job.id)
    return v
end
function W.Remove(w,id)
    local v=w.cars[id];if not v then return end
    w.cars[id]=nil
    if v.tween then v.tween:Cancel() end
    if v.link then v.link:Disconnect() end
    if v.value then v.value:Destroy() end
    v.bay.MovingLift:PivotTo(v.liftOrigin);v.model:Destroy()
end
function W.Hood(v)
    if v.moving then return false end
    v.hood=not v.hood;F.SetHood(v.model,v.hood);return true
end
function W.Lift(w,id,done)
    local v=w.cars[id];if not v or v.moving then return false end
    v.moving=true
    local value=Instance.new("NumberValue");v.value=value;value.Value=v.lifted and C.LiftHeight or 0
    local target=v.lifted and 0 or C.LiftHeight
    v.link=value.Changed:Connect(function(y)
        if w.cars[id]~=v then return end
        v.model:PivotTo(v.origin+Vector3.new(0,y,0));v.bay.MovingLift:PivotTo(v.liftOrigin+Vector3.new(0,y,0));F.SetHood(v.model,v.hood)
    end)
    v.tween=TweenService:Create(value,TweenInfo.new(2,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Value=target})
    v.tween.Completed:Connect(function()
        if w.cars[id]~=v then return end
        v.link:Disconnect();value:Destroy();v.value=nil;v.link=nil;v.tween=nil
        v.lifted=target>0;v.moving=false;done()
    end)
    v.tween:Play();return true
end
function W.Objective(w,job)
    if not job then return "Nimm am Empfang einen Auftrag an.",w.model.Stations.workshop end
    local v=w.cars[job.id];if not v then return "",nil end
    local step=C.JobById[job.kind].steps[job.step]
    if v.moving then return "Die Hebebühne bewegt sich.",v.bay.LiftControl end
    if job.phase=="working" then return "Arbeit läuft · andere Kundenautos können bearbeitet werden.",v.model.EnginePoint end
    if job.phase=="invoice" then return "Rechnung am Empfang abschließen.",w.model.Stations.workshop end
    if job.phase=="diagnose" then return "Mit dem OBD-Tester die Messwerte auslesen.",v.model.DiagnosticPoint end
    if job.phase=="verify" then
        if v.lifted then return "Bühne für die Endkontrolle absenken.",v.bay.LiftControl end
        if v.hood then return "Motorhaube für die Endkontrolle schließen.",v.model.HoodPoint end
        return "Endkontrolle mit dem OBD-Tester durchführen.",v.model.DiagnosticPoint
    end
    if step then
        if v.lifted~=step.lifted then return step.lifted and "Hebebühne anheben." or "Hebebühne absenken.",v.bay.LiftControl end
        if step.hood and not v.hood then return "Motorhaube öffnen.",v.model.HoodPoint end
        return step.name.." · "..C.Tools[step.tool].name,v.model[step.point]
    end
    return "",nil
end
function W.Sync(w,d)
    layout(w,d)
    for id in pairs(w.cars) do
        local exists=false;for _,j in ipairs(d.jobs) do if j.id==id then exists=true end end
        if not exists then W.Remove(w,id) end
    end
    for _,j in ipairs(d.jobs) do W.Spawn(w,j) end
    for i=1,d.bays do
        local bay=W.Bay(w,i)
        local name="Bühne "..i.." · frei"
        for _,j in ipairs(d.jobs) do if j.bay==i then name="Bühne "..i.." · "..C.CarById[j.carId].name end end
        label(bay.Sign,name)
        local control=bay.LiftControl:FindFirstChildOfClass("ProximityPrompt")
        if control then
            control:SetAttribute("JobId",nil)
            control.Enabled=false;control.KeyboardKeyCode=Enum.KeyCode.F;control.GamepadKeyCode=Enum.KeyCode.ButtonB
            for _,j in ipairs(d.jobs) do if j.bay==i then
                local v=w.cars[j.id];control.Enabled=not v.moving and j.phase~="working" and w.interactionJob~=j.id
                control:SetAttribute("JobId",j.id)
                control.ActionText=v.lifted and "Bühne absenken" or "Bühne anheben"
            end end
        end
    end
    for _,j in ipairs(d.jobs) do
        local v=w.cars[j.id];local _,target=W.Objective(w,j)
        local step=C.JobById[j.kind].steps[j.step]
        for _,part in ipairs(v.model:GetChildren()) do
            if part:IsA("BasePart") then part:SetAttribute("WorkPoint",nil) end
            local prompt=part:FindFirstChild("WorkPrompt")
            if prompt then
                prompt.Enabled=part==target and not v.moving and j.phase~="working" and w.interactionJob~=j.id
                prompt.ObjectText=C.CarById[j.carId].name.." · "..(C.PointNames[part.Name] or "")
                prompt.ActionText=j.phase=="diagnose" and "OBD: Diagnose öffnen" or (j.phase=="verify" and "OBD: Endkontrolle" or (step and step.name or "Arbeiten"))
            end
        end
        local hood=v.model.HoodPoint.HoodPrompt
        hood.Enabled=not v.moving and j.phase~="working" and w.interactionJob~=j.id;hood.ActionText=v.hood and "Motorhaube schließen" or "Motorhaube öffnen"
        local parts=F.TargetParts(v.model,j)
        if target and target:FindFirstChild("WorkPrompt") and not v.moving and j.phase~="working" then
            for _,part in ipairs(parts) do if part then part:SetAttribute("WorkPoint",target.Name) end end
        end
        v.model.Hood:SetAttribute("WorkPoint","HoodPoint")
        local port=v.model:FindFirstChild("OBDPort");if port then port:SetAttribute("WorkPoint","DiagnosticPoint") end
    end
end
function W.Equipment(w,d)
    for _,e in ipairs(C.Equipment) do
        local level=d.equipment[e.id] or 0
        if level>0 then
            local device=w.model.Equipment:FindFirstChild(e.id)
            if not device then
                device=SS.EquipmentTemplates[e.id]:Clone();device.Name=e.id;device.Parent=w.model.Equipment
                local lamp=Instance.new("Part");lamp.Name="LevelIndicator";lamp.Anchored=true;lamp.CanCollide=false;lamp.CanQuery=false;lamp.CanTouch=false
                lamp.Color=Color3.fromRGB(62,217,166);lamp.Material=Enum.Material.Neon;lamp.CFrame=device.PrimaryPart.CFrame*CFrame.new(1.1,2,0);lamp.Parent=device
                local mount=Instance.new("Part");mount.Name="IndicatorMount";mount.Anchored=true;mount.CanCollide=false;mount.CanQuery=false;mount.CanTouch=false;mount.Size=Vector3.new(0.12,1.6,0.12)
                mount.Color=Color3.fromRGB(100,116,124);mount.CFrame=device.PrimaryPart.CFrame*CFrame.new(1.1,1.22,0);mount.Parent=device
                local prompt=Instance.new("ProximityPrompt");prompt.Name="AssignPrompt";prompt.ActionText="Bühne zuweisen";prompt.ObjectText=e.name
                prompt.MaxActivationDistance=8;prompt.HoldDuration=0.25;prompt.RequiresLineOfSight=false;prompt.Parent=device.Badge
                prompt.Triggered:Connect(function(p) if p==w.owner then w.callback("deviceMenu",e.id) end end)
            end
            local assigned=d.equipmentBays[e.id];local bay=assigned and W.Bay(w,assigned)
            device:PivotTo(bay and bay.EquipmentSpot.CFrame or w.model.EquipmentPositions[e.id].CFrame)
            device.LevelIndicator.Size=Vector3.new(0.22,0.3+level*0.22,0.22)
            label(device,e.name.." · Stufe "..level..(assigned and " · Bühne "..assigned or " · Lager"))
            device:SetAttribute("AssignedBay",assigned)
            device:SetAttribute("EquipmentId",e.id)
        end
    end
end
function W.Deliver(w,count)
    local box=Instance.new("Part");box.Name="Teilelieferung";box.Size=Vector3.new(2.3,1.5,2);box.Color=Color3.fromRGB(175,125,66);box.Anchored=true
    box.CFrame=w.model.PartsArea.DeliveryOrigin.CFrame*CFrame.new((#w.model.PartsArea.DeliveryBoxes:GetChildren()%3)*2.5,0.75,0)
    box.Parent=w.model.PartsArea.DeliveryBoxes
    task.delay(40,function() if box.Parent then box:Destroy() end end)
end
function W.Destroy(player)
    local w=W.plots[player];if not w then return end
    if w.doorTween then local tween=w.doorTween;w.doorTween=nil;tween:Cancel() end
    for id in pairs(w.cars) do W.Remove(w,id) end
    w.model:Destroy();W.slots[w.slot]=nil;W.plots[player]=nil
end
return W
]]},
	{path={"ServerScriptService","Garage","GarageServer"},class="Script",source=[[
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local C,R=require(Shared:WaitForChild("Config")),require(Shared:WaitForChild("Rules"))
local P,F,W=require(script.Parent.Profiles),require(script.Parent.CarFactory),require(script.Parent.World)
local Purchases=require(script.Parent.Purchases)
local RunService=game:GetService("RunService")
local Remotes=Shared:WaitForChild("Remotes")
local Command,Event=Remotes:WaitForChild("Command"),Remotes:WaitForChild("Event")
local sessions={}
local joining={}
local function now() return workspace:GetServerTimeNow() end
local Lighting=game:GetService("Lighting")
local dayEpoch=now()
Lighting.ClockTime=C.DayStartHour
local function advanceDays(p,at)
    if p.profile.transacting then return end
    local _,cycle=R.DayClock(at,dayEpoch)
    local elapsed=math.max(0,cycle-p.dayCycle)
    if elapsed>0 then p.profile.data.days=math.min(1000000000,p.profile.data.days+elapsed);p.revision=p.revision+1 end
    p.dayCycle=cycle
end
local function emit(p,kind,data) if p.player.Parent then Event:FireClient(p.player,kind,data) end end
local function toast(p,message) if message then emit(p,"toast",message) end end
local function near(p,part,distance)
    local ch=p.player.Character;local root=ch and ch:FindFirstChild("HumanoidRootPart")
    local humanoid=ch and ch:FindFirstChildOfClass("Humanoid")
    return root and humanoid and humanoid.Health>0 and part and (root.Position-part.Position).Magnitude<=(distance or 15)
end
local function station(p,key) return near(p,p.world.model.Stations:FindFirstChild(key),key=="tools" and 9 or 10) end
local function selected(p,id) return R.FindJob(p.profile.data,id or p.selected) end
local function resetInteraction(p,expected)
    local active=p.pending
    if expected and active~=expected then return false end
    p.pending=nil;p.world.interactionJob=nil
    W.Sync(p.world,p.profile.data)
    emit(p,"interactionReset",active and {token=active.token} or nil)
    return true
end
local function validateInteraction(p)
    local c=p.pending;if not c then return end
    local j=c.job and selected(p,c.job)
    local invalid=now()>c.expires or p.player.Character~=c.character or p.tool~=c.tool or not near(p,c.point,8)
    if c.job then invalid=invalid or not j or p.selected~=c.job or j.phase~=c.phase or j.step~=c.step end
    if invalid then resetInteraction(p,c) end
end
local function beginInteraction(p,c)
    c.character=p.player.Character;c.tool=p.tool
    p.confirm=nil
    p.pending=c;p.world.interactionJob=c.job
    W.Sync(p.world,p.profile.data)
    -- Register cleanup before notifying the client. Every kind has a deadline.
    task.delay(math.max(0,c.expires-now())+0.1,function()
        if sessions[p.player]==p and p.pending==c then resetInteraction(p,c) end
    end)
end
local function objectiveFor(p,job)
    local d=p.profile.data
    local objective,target=W.Objective(p.world,job)
    if job and job.phase=="repair" then
        local step=C.JobById[job.kind].steps[job.step]
        if step and step.equipment and d.equipmentBays[step.equipment]~=job.bay then
            local device=p.world.model.Equipment:FindFirstChild(step.equipment)
            objective="Stelle "..C.EquipmentById[step.equipment].name.." an Bühne "..job.bay.." bereit."
            target=device and device.Badge or p.world.model.Stations.upgrades
        end
        if step and step.part and not R.ChoosePart(d,job,step.part) then objective="Passendes Ersatzteil im Teilehandel bestellen oder eine andere Marke auswählen.";target=p.world.model.Stations.parts end
    end
    return objective,target
end
local function push(p)
    local d=p.profile.data;local job=selected(p)
    if not job then p.selected=d.jobs[1] and d.jobs[1].id;job=selected(p) end
    local objective,target=objectiveFor(p,job)
    local visuals={};for id,v in pairs(p.world.cars) do visuals[id]={lifted=v.lifted,hood=v.hood,moving=v.moving,model=v.model} end
    emit(p,"state",{data=R.Snapshot(d),revision=p.revision,selected=p.selected,tool=p.tool,objective=objective,target=target,
        time=now(),dayEpoch=dayEpoch,interaction=p.pending and {token=p.pending.token,kind=p.pending.kind,expires=p.pending.expires},neededXP=R.XPNeeded(d),shopReady=p.profile.writable and not RunService:IsStudio() and not p.profile.transacting,saveStatus=p.profile.status,visuals=visuals,plot=p.world.model})
    p.player.leaderstats.Credits.Value=math.floor(d.money);p.player.leaderstats.Level.Value=d.level
    p.lastPush=now();p.dirty=false
end
local function changed(p)
    p.revision=p.revision+1;W.Sync(p.world,p.profile.data);push(p)
end
local function messageResult(p,ok,message)
    toast(p,message);if ok then changed(p) else push(p) end
end
local function moveTo(p,part)
    if not part or not p.player.Character then return end
    local plotY=p.world.model.PrimaryPart.Position.Y
    local destination=W.SafeArrival(p.world,part)
    local ch=p.player.Character;local root=ch:FindFirstChild("HumanoidRootPart")
    local humanoid=ch:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health<=0 then return end
    humanoid.Sit=false
    ch:PivotTo(destination or CFrame.new(part.Position.X,plotY+3.5,part.Position.Z+6))
    root.AssemblyLinearVelocity=Vector3.new();root.AssemblyAngularVelocity=Vector3.new()
end
local function jobConditions(p,j,v)
    if v.moving then return false,"Warte, bis die Bühne stillsteht." end
    local step=C.JobById[j.kind].steps[j.step]
    if not step or j.phase~="repair" then return false,"Dieser Arbeitsschritt ist gerade nicht verfügbar." end
    if v.lifted~=step.lifted then return false,step.lifted and "Hebebühne zuerst anheben." or "Hebebühne zuerst absenken." end
    if step.hood and not v.hood then return false,"Öffne zuerst die Motorhaube." end
    if not R.ToolActive(p.profile.data,p.tool) or not R.ToolMatches(step,p.tool) then return false,"Wähle das passende Werkzeug: "..C.Tools[step.tool].name end
    if step.equipment and (p.profile.data.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) then return false,"Das benötigte Gerät fehlt." end
    if step.equipment and p.profile.data.equipmentBays[step.equipment]~=j.bay then return false,"Stelle zuerst "..C.EquipmentById[step.equipment].name.." an Bühne "..j.bay.." bereit." end
    if step.equipment then
        for _,other in ipairs(p.profile.data.jobs) do
            local otherStep=C.JobById[other.kind].steps[other.step]
            if other.id~=j.id and other.phase=="working" and otherStep and otherStep.equipment==step.equipment then
                return false,"Dieses Gerät ist gerade an einem anderen Auto im Einsatz."
            end
        end
    end
    if step.part and not R.ChoosePart(p.profile.data,j,step.part) then return false,"Bestelle zuerst das passende Ersatzteil oder wähle einen vorhandenen Hersteller." end
    if not near(p,v.model[step.point],8) then return false,"Gehe zum markierten Bauteil am Fahrzeug." end
    return true
end
local function report(p,j)
    local def=C.JobById[j.kind]
    emit(p,"diagnose",{job=j.id,car=C.CarById[j.carId].name,report=def.report,answers=j.phase=="diagnose" and def.answers or {},phase=j.phase})
end
local function work(p,id,point,scanOnly)
    local j=selected(p,id);if not j then return end
    local v=p.world.cars[j.id];if not v then return end
    if p.pending then return toast(p,"Schließe zuerst die laufende Interaktion ab.") end
    p.selected=j.id
    if scanOnly or j.phase=="diagnose" or j.phase=="verify" then
        if j.phase=="working" then return toast(p,"Warte, bis der Arbeitsschritt beendet ist.") end
        if point and point~="DiagnosticPoint" then return toast(p,"Nutze den OBD-Anschluss an der Fahrerseite.") end
        if v.moving or not near(p,v.model.DiagnosticPoint,8) then return toast(p,"Gehe zum OBD-Anschluss an der Fahrerseite.") end
        if p.tool~="scanner" or not R.ToolActive(p.profile.data,"scanner") then return toast(p,"Wähle den OBD-Tester aus deiner Werkzeugleiste.") end
        if j.phase=="verify" and (v.lifted or v.hood) then return toast(p,"Senke die Bühne ab und schließe die Motorhaube.") end
        if j.scanReady and j.phase~="verify" then report(p,j);return push(p) end
        local pending={kind="scan",job=j.id,phase=j.phase,step=j.step,token=Http:GenerateGUID(false),point=v.model.DiagnosticPoint,expires=now()+3}
        beginInteraction(p,pending)
        emit(p,"scan",{duration=2.5,tool="scanner",point=v.model.DiagnosticPoint})
        F.WorkEffect(v.model,"scanner",v.model.DiagnosticPoint,2.5)
        task.delay(2.5,function()
            if sessions[p.player]~=p or p.pending~=pending then return end
            resetInteraction(p,pending)
            if p.player.Character~=pending.character or selected(p,j.id)~=j or not near(p,v.model.DiagnosticPoint,8) or v.moving or p.tool~="scanner" then
                emit(p,"interactionReset");return toast(p,"Prüfung abgebrochen: Gehe zurück zum Fahrzeug.")
            end
            if j.phase=="diagnose" then
                j.scanReady=true;report(p,j)
            elseif j.phase=="verify" and not v.lifted and not v.hood then
                j.phase="invoice";toast(p,"Endkontrolle bestanden. Rechnung am Empfang abschließen.");report(p,j)
            else report(p,j) end
            changed(p)
        end)
    elseif j.phase=="repair" then
        if point and point~=C.JobById[j.kind].steps[j.step].point then return toast(p,"Wähle das markierte Bauteil für diesen Arbeitsschritt.") end
        local ok,msg=jobConditions(p,j,v);if not ok then return toast(p,msg) end
        local c={kind="gauge",job=j.id,step=j.step,token=Http:GenerateGUID(false),startAt=now()+0.7,period=1.5,
            center=0.62,width=math.min(0.48,0.28+(p.profile.data.toolLevel-1)*0.006),expires=now()+12}
        c.phase=j.phase;c.point=v.model[C.JobById[j.kind].steps[j.step].point]
        beginInteraction(p,c);emit(p,"challenge",c)
    elseif j.phase=="invoice" then toast(p,"Hole die Vergütung am Empfang über Abrechnen ab.")
    else toast(p,"Dieser Arbeitsschritt läuft bereits.") end
    push(p)
end
local function token(p,key,job)
    p.confirm={token=Http:GenerateGUID(false),key=key,job=job,expires=now()+30}
    emit(p,"confirm",p.confirm)
end
local function expansionAccess(p)
    local point=p.world.model:FindFirstChild("ExpansionPoint")
    return station(p,"upgrades") or (point and near(p,point.Activate,10))
end
local function expansionQuote(p)
    local d=p.profile.data
    if p.pending then return toast(p,"Beende zuerst die laufende Interaktion.") end
    if not expansionAccess(p) then return toast(p,"Gehe zum Ausbaukreis oder zum Büro-PC.") end
    if d.bays>=C.MaxBays then return toast(p,"Deine Werkstatt hat bereits alle vier Hebebühnen.") end
    -- Repeated input reuses one quote. The client never chooses the stage or price.
    local c=p.confirm
    if not c or c.key~="bays" or c.stage~=d.bays or now()>c.expires then
        c={token=Http:GenerateGUID(false),key="bays",stage=d.bays,cost=R.UpgradeCost(d,"bays"),
            level=C.BayLevels[d.bays+1],expires=now()+30};p.confirm=c
    end
    emit(p,"confirm",c)
end
local function act(p,action,a)
    local d=p.profile.data
    if action=="hello" then return push(p) end
    if action=="travel" then
        if not C.StationNames[a.key] then return end
        if a.key=="shop" then resetInteraction(p);emit(p,"page","shop");return push(p) end
        resetInteraction(p);p.confirm=nil
        moveTo(p,p.world.model.Stations[a.key]);emit(p,"page",a.key);return push(p)
    end
    if action=="select" then
        if selected(p,a.id) then
            if p.selected~=a.id then resetInteraction(p);p.confirm=nil end
            p.selected=a.id;push(p)
        end
        return
    end
    if action=="target" then
        local j=selected(p,a.id)
        if a.id and not j then return end
        resetInteraction(p);p.confirm=nil
        local _,target=objectiveFor(p,j);if j then p.selected=j.id end
        if a.car and j then target=p.world.cars[j.id].model.DiagnosticPoint end
        moveTo(p,target);emit(p,"close");return push(p)
    end
    if action=="swapTool" then
        if p.pending then return toast(p,"Beende zuerst die laufende Interaktion.") end
        if not station(p,"tools") then return toast(p,"Gehe zuerst zur Werkzeugkiste.") end
        local ok,msg=R.SwapTool(d,a.slot,a.id)
        if ok and not R.ToolActive(d,p.tool) then
            p.tool=a.id;F.Equip(p.player,p.tool)
        end
        return messageResult(p,ok,msg)
    end
    if action=="tool" then
        local t=C.Tools[a.id];if not t then return end
        if not R.ToolActive(d,a.id) then return toast(p,"Dieses Werkzeug liegt in der Werkzeugkiste.") end
        if not R.ToolUnlocked(d,a.id) then return toast(p,"Kaufe zuerst das zugehörige Werkstattgerät.") end
        if p.pending and a.id~=p.tool then resetInteraction(p) end
        if p.tool==a.id and p.player.Character and p.player.Character:FindFirstChild("GarageTool") then return push(p) end
        p.tool=a.id;F.Equip(p.player,p.tool);return push(p)
    end
    if action=="accept" then
        if not station(p,"workshop") then return toast(p,"Gehe zuerst zum Empfang.") end
        local j,msg=R.Accept(d,a.id)
        if j then resetInteraction(p);p.selected=j.id;R.RefreshOffers(d);toast(p,"Auftrag angenommen. Dein Fahrzeug steht auf Bühne "..j.bay..".") end
        return messageResult(p,j,msg)
    end
    if action=="work" or action=="scan" then return work(p,a.id or p.selected,a.point,action=="scan") end
    if action=="door" then
        if p.pending or not near(p,p.world.model.RollerDoor.Control,8) then return toast(p,"Gehe ohne laufende Interaktion zum Torschalter.") end
        local ok,msg=W.RollDoor(p.world,function() if sessions[p.player]==p then push(p) end end)
        toast(p,msg);if ok then push(p) end;return
    end
    if action=="lift" or action=="hood" then
        local j=selected(p,a.id);if not j then return end
        local v=p.world.cars[j.id]
        if p.pending or j.phase=="working" then return toast(p,"Beende zuerst die Arbeit an diesem Fahrzeug.") end
        if not v or not near(p,action=="lift" and v.bay.LiftControl or v.model.HoodPoint,8) then return toast(p,"Gehe zum Schalter oder zur Motorhaube.") end
        if action=="lift" then W.Lift(p.world,j.id,function() if sessions[p.player]==p then changed(p) end end) else W.Hood(v) end
        return changed(p)
    end
    if action=="diagnose" then
        local j=selected(p,a.id);if not j then return end
        local v=p.world.cars[j.id]
        if p.pending or not v or v.moving or p.tool~="scanner" or not near(p,v.model.DiagnosticPoint,8) then return end
        local ok,msg=R.Diagnose(j,a.choice)
        if ok then emit(p,"diagnosisDone",j.id) end
        return messageResult(p,ok,msg)
    end
    if action=="hit" then
        local c=p.pending
        if not c or c.kind~="gauge" or a.token~=c.token then return end
        resetInteraction(p,c)
        local j=selected(p,c.job);local v=j and p.world.cars[j.id]
        if not j or not v or j.step~=c.step then return end
        local ok,msg=jobConditions(p,j,v);if not ok then return toast(p,msg) end
        local at=a.at
        if type(at)~="number" or at~=at or at<now()-0.5 or at>now()+0.06 or not R.GaugeHit(at,c) then
            j.quality=math.max(0,j.quality-2);toast(p,"Knapp daneben. Versuche es erneut im grünen Bereich.");return changed(p)
        end
        local success,message=R.StartWork(d,j,now())
        if success then
            local step=C.JobById[j.kind].steps[j.step];F.Effect(v.model,step.effect)
            F.WorkEffect(v.model,p.tool,v.model[step.point],j.workUntil-now(),step.effect)
            emit(p,"workFX",{tool=p.tool,point=v.model[step.point],duration=j.workUntil-now()})
        end
        return messageResult(p,success,message)
    end
    if action=="abortInteraction" then
        -- A delayed abort from an old dialog must not cancel a newer interaction.
        if p.pending and a.token~=p.pending.token then return end
        resetInteraction(p);return push(p)
    end
    if action=="yard" then
        if type(a.id)~="string" or not C.YardTasks[a.id] then return end
        local def=C.YardTasks[a.id];local tasks=p.world.model:FindFirstChild("YardActivities")
        local point=tasks and tasks:FindFirstChild(a.id)
        if not def or not point or not near(p,point,8) or p.pending then return end
        if now()<(d.yardReady[a.id] or 0) then return toast(p,"Hier gibt es bald wieder Arbeit: "..math.ceil(d.yardReady[a.id]-now()).." s.") end
        -- The air station supplies its own gauge; a player need not own the diagnostic cart.
        local pending={kind="yard",token=Http:GenerateGUID(false),point=point,expires=now()+def.seconds+0.5}
        beginInteraction(p,pending)
        emit(p,"scan",{tool=def.tool or p.tool,point=point,duration=def.seconds});toast(p,def.name.." …")
        task.delay(def.seconds,function()
            if sessions[p.player]~=p or p.pending~=pending then return end
            resetInteraction(p,pending)
            if p.player.Character~=pending.character or not near(p,point,8) or p.profile.transacting then emit(p,"interactionReset");return toast(p,"Außenarbeit abgebrochen. Versuche es erneut an der Station.") end
            if R.FinishYard(p.profile.data,a.id,now()) then
                emit(p,"purchaseFX",{title=def.name,detail="+"..def.reward.." Cr · +"..def.xp.." XP"});changed(p)
            end
        end)
        return
    end
    if action=="settle" then
        if not station(p,"workshop") then return toast(p,"Gehe zur Abrechnung an den Empfang.") end
        local receipt,msg=R.Settle(d,a.id,now())
        if receipt then emit(p,"receipt",receipt);R.RefreshOffers(d) end
        return messageResult(p,receipt,msg)
    end
    if action=="confirm" then
        if a.key=="cancel" and selected(p,a.id) then token(p,"cancel",a.id)
        elseif a.key=="bays" then expansionQuote(p)
        end
        return
    end
    if action=="commit" then
        local c=p.confirm;if not c or c.token~=a.token or now()>c.expires then return end
        p.confirm=nil
        if c.key=="cancel" then resetInteraction(p);R.CancelJob(d,c.job)
        elseif c.key=="bays" then
            if p.pending or not expansionAccess(p) then return toast(p,"Gehe ohne laufende Interaktion zum Ausbaukreis oder Büro-PC.") end
            local ok,msg=R.BuyUpgrade(d,"bays",c.stage)
            if not ok then return messageResult(p,ok,msg) end
            emit(p,"purchaseFX",{title="Hallenanbau · Bühne "..d.bays,detail="−"..c.cost.." Cr · Ausbau abgeschlossen"})
            changed(p)
            task.spawn(function() P.Save(p.profile,false);if sessions[p.player]==p then push(p) end end)
            return
        end
        return changed(p)
    end
    if action=="partSelect" then
        local j=selected(p,a.job);if j then return messageResult(p,R.SelectPart(d,j,a.sku)) end;return
    end
    if action=="order" then
        if not station(p,"parts") then return toast(p,"Gehe zum Teilehandel.") end
        local before=d.money;local ok,msg=R.Order(d,a.sku,a.qty,now())
        if ok then local part=C.PartById[a.sku];emit(p,"purchaseFX",{title=part.eta==0 and "Teile gekauft" or "Teile bestellt",detail=a.qty.." × "..part.brand.." · −"..math.floor(before-d.money).." Cr"});return changed(p) end
        return messageResult(p,ok,msg)
    end
    if action=="deviceMenu" or action=="assignEquipment" then
        local device=type(a.id)=="string" and p.world.model.Equipment:FindFirstChild(a.id)
        if not device or not (station(p,"upgrades") or near(p,device.Badge,8)) then return toast(p,"Gehe zum Gerät oder zum Büro-PC.") end
        if p.pending then return toast(p,"Beende zuerst die laufende Interaktion.") end
        if action=="deviceMenu" then emit(p,"device",{id=a.id});return push(p) end
        for _,j in ipairs(d.jobs) do
            if (j.bay==a.bay or j.bay==d.equipmentBays[a.id]) and p.world.cars[j.id].moving then return toast(p,"Warte, bis die Bühne stillsteht.") end
        end
        local ok,msg=R.AssignEquipment(d,a.id,a.bay)
        if ok then W.Equipment(p.world,d);emit(p,"interactionReset") end
        return messageResult(p,ok,msg)
    end
    if action=="equipment" or action=="upgrade" then
        if action=="upgrade" and a.id=="bays" then return expansionQuote(p) end
        if not station(p,"upgrades") then return toast(p,"Gehe zur Ausbau-Werkbank.") end
        local before=d.money;local ok,msg
        if action=="equipment" then ok,msg=R.BuyEquipment(d,a.id) else ok,msg=R.BuyUpgrade(d,a.id) end
        if ok then
            W.Equipment(p.world,d);R.RefreshOffers(d)
            local def=action=="equipment" and C.EquipmentById[a.id] or C.UpgradeById[a.id]
            emit(p,"purchaseFX",{title=def.name,detail="Stufe "..(action=="equipment" and d.equipment[a.id] or d[a.id]).." · gekauft"})
            return changed(p)
        end
        return messageResult(p,ok,msg)
    end
    if action=="buyCredits" then
        if p.pending then return toast(p,"Beende zuerst die laufende Arbeit.") end
        if RunService:IsStudio() or not p.profile.writable or p.profile.transacting then return toast(p,"Robux-Käufe sind hier noch nicht verfügbar.") end
        if now()<(p.nextPurchasePrompt or 0) then return end
        local product
        for _,candidate in ipairs(C.CreditProducts) do if candidate.key==a.key then product=candidate end end
        if not product or not Purchases.ByProduct(product.productId) then return toast(p,"Dieses Credit-Paket ist noch nicht verfügbar.") end
        if d.money+product.credits>C.NumberCap or d.money+product.credits-d.money~=product.credits then return toast(p,"Dein Credit-Guthaben ist bereits zu hoch für dieses Paket.") end
        p.nextPurchasePrompt=now()+3;emit(p,"purchasePrompt",{productId=product.productId});return
    end
    if action=="save" and now()>(p.nextSave or 0) then
        p.nextSave=now()+30;task.spawn(function() P.Save(p.profile,false);if sessions[p.player]==p then push(p);toast(p,p.profile.status) end end)
    end
end
local function request(player,action,a)
    local p=sessions[player];if not p or p.closing or type(action)~="string" or #action>32 then return end
    if p.profile.transacting and action~="hello" and action~="abortInteraction" then return toast(p,"Dein Kauf wird sicher gespeichert. Bitte einen Moment warten.") end
    a=type(a)=="table" and a or {}
    local count=0;for k,v in pairs(a) do count=count+1;if count>10 or type(k)~="string" or #k>24 or (type(v)~="string" and type(v)~="number" and type(v)~="boolean") or (type(v)=="string" and #v>100) or (type(v)=="number" and (v~=v or math.abs(v)>1e25)) then return end end
    validateInteraction(p)
    local finishing=p.pending and a.token==p.pending.token and (action=="hit" or action=="abortInteraction")
    local time=now();p.budget=math.min(30,(p.budget or 30)+(time-(p.budgetTime or time))*20);p.budgetTime=time
    if not finishing then if p.budget<1 then return end;p.budget=p.budget-1 end
    if action~="hello" and action~="hit" and action~="abortInteraction" then
        if time-(p.cooldowns[action] or -10)<0.12 then return end;p.cooldowns[action]=time
    end
    local changedTime,arrived=R.Advance(p.profile.data,time)
    advanceDays(p,time)
    if arrived>0 then W.Deliver(p.world,arrived);toast(p,"Deine Teilelieferung ist angekommen.") end
    if changedTime then p.revision=p.revision+1;W.Sync(p.world,p.profile.data) end
    act(p,action,a)
end
Command.OnServerEvent:Connect(request)
Purchases.Init(function(player) return sessions[player] end,function(p,product)
    emit(p,"purchaseFX",{title="Credits erhalten",detail="+"..product.credits.." Credits"});changed(p)
end)
local function join(player)
    if sessions[player] or joining[player] then return end
    joining[player]=true
    local profile=P.Load(player)
    if not player.Parent then joining[player]=nil;P.Save(profile,true);return end
    local p={player=player,profile=profile,tool="scanner",revision=1,cooldowns={},lastPush=0}
    local _,cycle=R.DayClock(now(),dayEpoch);p.dayCycle=cycle
    p.world=W.Create(player,function(kind,value,point)
        if sessions[player]~=p then return end
        if kind=="station" then if station(p,value) then resetInteraction(p);emit(p,"page",value);push(p) end
        elseif kind=="expand" then request(player,"confirm",{key="bays"})
        elseif kind=="lift" then for _,j in ipairs(p.profile.data.jobs) do if j.bay==value then request(player,"lift",{id=j.id});break end end
        else request(player,kind,{id=value,point=point}) end
    end)
    if not p.world then joining[player]=nil;P.Save(profile,true);player:Kick("Alle Werkstätten sind belegt. Bitte nutze einen anderen Server.");return end
    sessions[player]=p
    joining[player]=nil
    local stats=Instance.new("Folder");stats.Name="leaderstats";stats.Parent=player
    for _,name in ipairs({"Credits","Level"}) do local n=Instance.new("NumberValue");n.Name=name;n.Parent=stats end
    R.RefreshOffers(profile.data);W.Sync(p.world,profile.data);W.Equipment(p.world,profile.data)
    local function character(ch)
        local root=ch:WaitForChild("HumanoidRootPart",10)
        local humanoid=ch:WaitForChild("Humanoid",10)
        local hand=ch:FindFirstChild("Right Arm") or ch:WaitForChild("RightHand",10)
        if not root or not humanoid or not hand or sessions[player]~=p or player.Character~=ch then return end
        resetInteraction(p);p.confirm=nil
        if not R.ToolActive(profile.data,p.tool) or not R.ToolUnlocked(profile.data,p.tool) then
            for _,key in ipairs(profile.data.loadout) do if R.ToolUnlocked(profile.data,key) then p.tool=key;break end end
        end
        moveTo(p,p.world.model.Stations.home);F.Equip(player,p.tool);push(p)
    end
    player.CharacterAdded:Connect(character)
    if player.Character then task.spawn(character,player.Character) end
    push(p)
end
Players.PlayerAdded:Connect(join)
for _,player in ipairs(Players:GetPlayers()) do task.spawn(join,player) end
Players.PlayerRemoving:Connect(function(player)
    local p=sessions[player];if not p then return end
    advanceDays(p,now());p.closing=true;p.pending=nil;P.Save(p.profile,true);sessions[player]=nil;W.Destroy(player)
end)
task.spawn(function()
    while true do
        task.wait(0.5)
        Lighting.ClockTime=R.DayClock(now(),dayEpoch)
        for _,p in pairs(sessions) do if not p.closing then
            advanceDays(p,now())
            validateInteraction(p)
            local change,arrived=R.Advance(p.profile.data,now())
            if change then p.revision=p.revision+1;W.Sync(p.world,p.profile.data) end
            if arrived>0 then W.Deliver(p.world,arrived);toast(p,"Teilelieferung angekommen. Die Ersatzteile liegen im Lager.") end
            push(p)
        end end
    end
end)
task.spawn(function()
    while true do task.wait(C.AutosaveSeconds);for _,p in pairs(sessions) do if not p.closing then task.spawn(function() P.Save(p.profile,false) end) end end end
end)
game:BindToClose(function()
    local remaining=0
    for _,p in pairs(sessions) do remaining=remaining+1;advanceDays(p,now());p.closing=true;task.spawn(function() P.Save(p.profile,true);remaining=remaining-1 end) end
    local deadline=os.clock()+25;while remaining>0 and os.clock()<deadline do task.wait(0.1) end
end)
]]},
	{path={"StarterPlayer","StarterPlayerScripts","ClientEffects"},class="ModuleScript",source=[[
local Tween=game:GetService("TweenService")
local Run=game:GetService("RunService")
local E={}
function E.new(player,translate)
    local t=translate;local fx={};local work;local arm,armBase,grip,gripBase
    local layer=Instance.new("ScreenGui");layer.Name="GarageCelebrations";layer.ResetOnSpawn=false;layer.IgnoreGuiInset=false;layer.DisplayOrder=45;layer.Parent=player:WaitForChild("PlayerGui")
    local green=Color3.fromRGB(55,218,155);local gold=Color3.fromRGB(250,198,71)
    local function tween(obj,seconds,props,style)
        local tw=Tween:Create(obj,TweenInfo.new(seconds,style or Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props);tw:Play();return tw
    end
    local function make(class,parent,props) local v=Instance.new(class);for k,x in pairs(props) do v[k]=x end;v.Parent=parent;return v end
    local function label(parent,value,pos,size,color,textSize)
        return make("TextLabel",parent,{Text=t(value),Position=pos,Size=size,TextColor3=color,TextSize=textSize,TextWrapped=true,Font=Enum.Font.GothamBold,BackgroundTransparency=1})
    end
    function fx.Purchase(data)
        local panel=make("Frame",layer,{Name="PurchaseFeedback",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.79),Size=UDim2.fromOffset(300,84),BackgroundColor3=Color3.fromRGB(16,39,35),BorderSizePixel=0})
        make("UICorner",panel,{CornerRadius=UDim.new(0,15)})
        make("UIStroke",panel,{Color=green,Thickness=1.5,Transparency=0.25})
        local scale=make("UIScale",panel,{Scale=0.75});tween(scale,0.3,{Scale=1},Enum.EasingStyle.Back)
        label(panel,"✓",UDim2.fromOffset(8,12),UDim2.fromOffset(46,52),green,36)
        label(panel,data.title or "Gekauft",UDim2.fromOffset(58,8),UDim2.fromOffset(228,37),Color3.fromRGB(235,250,246),16)
        label(panel,data.detail or "",UDim2.fromOffset(58,46),UDim2.fromOffset(228,28),green,14)
        task.delay(1.8,function() if panel.Parent then tween(panel,0.22,{Position=UDim2.fromScale(0.5,0.83),BackgroundTransparency=1});tween(scale,0.22,{Scale=0.85});task.delay(0.23,function() panel:Destroy() end) end end)
    end
    function fx.Level(level,gained)
        local panel=make("Frame",layer,{Name="LevelCelebration",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.26),Size=UDim2.fromOffset(340,124),BackgroundColor3=Color3.fromRGB(38,33,24),BorderSizePixel=0})
        make("UICorner",panel,{CornerRadius=UDim.new(0,18)});make("UIStroke",panel,{Color=gold,Thickness=2})
        local scale=make("UIScale",panel,{Scale=0.45});tween(scale,0.5,{Scale=1},Enum.EasingStyle.Back)
        label(panel,"LEVELAUFSTIEG",UDim2.fromOffset(12,9),UDim2.fromOffset(316,26),gold,16)
        label(panel,t("LEVEL {level}",{level=level}),UDim2.fromOffset(12,37),UDim2.fromOffset(316,48),Color3.fromRGB(255,245,218),34)
        label(panel,"Neue Möglichkeiten in deiner Werkstatt",UDim2.fromOffset(12,89),UDim2.fromOffset(316,24),gold,12)
        for i=1,22 do
            local bit=make("Frame",layer,{Name="Confetti",Size=UDim2.fromOffset(i%3+5,10),Position=UDim2.fromScale(0.5,0.26),BackgroundColor3=i%2==0 and gold or green,BorderSizePixel=0,Rotation=i*19})
            tween(bit,1.3+(i%4)*0.15,{Position=UDim2.fromScale(0.15+(i*37%70)/100,0.5+(i%4)*0.07),Rotation=i*53,BackgroundTransparency=1})
            task.delay(2,function() bit:Destroy() end)
        end
        task.delay(3,function() if panel.Parent then tween(scale,0.25,{Scale=0});task.delay(0.26,function() panel:Destroy() end) end end)
    end
    local function restore()
        if arm and arm.Parent and armBase then arm.C0=armBase end
        if grip and grip.Parent and gripBase then grip.C0=gripBase end
        arm,armBase,grip,gripBase=nil,nil,nil,nil
    end
    function fx.StopWork()
        restore();work=nil
        local ch=player.Character;local tool=ch and ch:FindFirstChild("GarageTool");local readout=tool and tool:FindFirstChild("Readout",true)
        if readout then readout.Text=tool:GetAttribute("ToolId")=="scanner" and "OBD READY" or "BEREIT" end
    end
    function fx.Work(data)
        fx.StopWork();work={tool=data.tool,untilTime=workspace:GetServerTimeNow()+(data.duration or 2.5),start=workspace:GetServerTimeNow(),point=data.point}
    end
    Run.RenderStepped:Connect(function()
        if not work then return end
        local ch=player.Character;local tool=ch and ch:FindFirstChild("GarageTool");local root=ch and ch:FindFirstChild("HumanoidRootPart")
        if workspace:GetServerTimeNow()>=work.untilTime or not tool or tool:GetAttribute("ToolId")~=work.tool or (root and work.point and (root.Position-work.point.Position).Magnitude>18) then fx.StopWork();return end
        local currentGrip=tool:FindFirstChild("ToolGrip",true)
        if currentGrip~=grip then restore();grip=currentGrip;gripBase=grip and grip.C0;arm=ch:FindFirstChild("RightShoulder",true) or ch:FindFirstChild("Right Shoulder",true);armBase=arm and arm.C0 end
        local elapsed=workspace:GetServerTimeNow()-work.start
        local turning=work.tool=="ratchet" or work.tool=="torque" or work.tool=="screwdriver"
        local swing=math.sin(elapsed*(turning and 18 or 6))
        local angle=work.tool=="oil" and -0.9 or turning and swing*0.45 or work.tool=="tire" and swing*0.65 or swing*0.08
        if grip and gripBase then grip.C0=gripBase*CFrame.Angles(0,0,angle) end
        if arm and armBase then arm.C0=armBase*CFrame.Angles(-0.35+swing*0.08,0,work.tool=="oil" and -0.2 or swing*0.12) end
        local readout=tool:FindFirstChild("Readout",true)
        if readout then readout.Text=work.tool=="scanner" and ("OBD SCAN\n"..math.floor(math.min(99,elapsed/(work.untilTime-work.start)*100)).."%") or string.format("%.2f V",12.4+math.sin(elapsed*9)*0.2) end
    end)
    player.CharacterAdded:Connect(function() fx.StopWork() end)
    return fx
end
return E
]]},
	{path={"StarterPlayer","StarterPlayerScripts","InputController"},class="ModuleScript",source=[[
-- Own the input before Roblox's movement bindings; keep jump suppressed until key-up.
local CAS=game:GetService("ContextActionService")
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local I={}
function I.new(player,callbacks)
    local control={locked=false,releaseAt=nil,sent=false,held=false}
    local humanoid,wasEnabled,wasAuto
    local function restore()
        if humanoid and humanoid.Parent then
            humanoid.Jump=false;humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,wasEnabled)
            if wasAuto~=nil then humanoid.AutoJumpEnabled=wasAuto end
        end
        humanoid=nil;control.locked=false;control.releaseAt=nil;control.held=false
    end
    function control.Lock()
        if not control.locked then
            local ch=player.Character;humanoid=ch and ch:FindFirstChildOfClass("Humanoid")
            if humanoid then wasEnabled=humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping);wasAuto=humanoid.AutoJumpEnabled;humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,false);humanoid.AutoJumpEnabled=false;humanoid.Jump=false end
        end
        control.locked=true;control.sent=false;control.releaseAt=nil
    end
    function control.Unlock()
        -- Do not pass the very Space press that closes the QTE to the jump controller.
        if control.locked then control.releaseAt=os.clock()+0.15 end
    end
    CAS:BindActionAtPriority("UCG_QTEStop",function(_,state)
        if not control.locked then return Enum.ContextActionResult.Pass end
        if humanoid then humanoid.Jump=false end
        if state==Enum.UserInputState.Begin then
            control.held=true
            if not control.sent then control.sent=true;callbacks.StopQTE() end
        elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then control.held=false end
        return Enum.ContextActionResult.Sink
    end,false,10000,Enum.KeyCode.Space,Enum.KeyCode.ButtonA,Enum.PlayerActions.CharacterJump)
    CAS:BindActionAtPriority("UCG_WorkshopMenu",function(_,state)
        if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if state==Enum.UserInputState.Begin and not control.locked then callbacks.ToggleMenu() end
        return Enum.ContextActionResult.Sink
    end,false,10000,Enum.KeyCode.Tab)
    local keys={Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five}
    CAS:BindActionAtPriority("UCG_Hotbar",function(_,state,input)
        if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if state==Enum.UserInputState.Begin and not control.locked and callbacks.SelectTool then
            for slot,key in ipairs(keys) do if input.KeyCode==key then callbacks.SelectTool(slot);break end end
        end
        return Enum.ContextActionResult.Sink
    end,false,3000,Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five)
    UIS.InputEnded:Connect(function(input)
        if input.KeyCode==Enum.KeyCode.Space or input.KeyCode==Enum.KeyCode.ButtonA then control.held=false end
    end)
    Run.RenderStepped:Connect(function()
        if not control.locked then return end
        if humanoid then humanoid.Jump=false end
        local holdingSpace=UIS:IsKeyDown(Enum.KeyCode.Space)
        if control.releaseAt and os.clock()>=control.releaseAt and not control.held and not holdingSpace then restore() end
    end)
    player.CharacterAdded:Connect(function() restore() end)
    return control
end
return I
]]},
	{path={"StarterPlayer","StarterPlayerScripts","GarageClient"},class="LocalScript",source=[[
-- Workshop UI: compact HUD, confirmed purchases, responsive panels and protected QTE input.
local Players=game:GetService("Players")
local StarterGui=game:GetService("StarterGui")
local Marketplace=game:GetService("MarketplaceService")
local Tween=game:GetService("TweenService")
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local PromptService=game:GetService("ProximityPromptService")
local Lighting=game:GetService("Lighting")
local player=Players.LocalPlayer
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
-- A replicated folder can arrive before its children. Wait for each dependency.
local C,R,L=require(Shared:WaitForChild("Config")),require(Shared:WaitForChild("Rules")),require(Shared:WaitForChild("Locale"))
local Remotes=Shared:WaitForChild("Remotes")
local Command,Event=Remotes:WaitForChild("Command"),Remotes:WaitForChild("Event")
local language="de" -- Switch after completing the corresponding Locale catalogue.
local function t(s,args) return L.t(s,args,language) end
local function send(action,args) Command:FireServer(action,args or {}) end
local Effects=require(script.Parent:WaitForChild("ClientEffects"))
local InputController=require(script.Parent:WaitForChild("InputController"))
local effects=Effects.new(player,t)
local inputControl
local productInfo={}
local productLoading={}
local colors={bg=Color3.fromRGB(11,16,25),panel=Color3.fromRGB(20,29,43),card=Color3.fromRGB(28,40,57),line=Color3.fromRGB(49,67,87),
    text=Color3.fromRGB(235,243,250),muted=Color3.fromRGB(156,176,199),green=Color3.fromRGB(50,192,137),blue=Color3.fromRGB(59,134,218),red=Color3.fromRGB(212,65,89),yellow=Color3.fromRGB(235,184,72),purple=Color3.fromRGB(143,82,214),purpleDark=Color3.fromRGB(79,47,124)}
local function make(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent;return obj
end
local function corner(obj,r) make("UICorner",obj,{CornerRadius=UDim.new(0,r or 10)}) end
local function frame(parent,size,pos,color)
    local f=make("Frame",parent,{Size=size,Position=pos or UDim2.new(),BackgroundColor3=color or colors.card,BorderSizePixel=0});corner(f);return f
end
local function text(parent,value,x,y,w,h,size,color)
    return make("TextLabel",parent,{Text=t(value),Position=UDim2.fromOffset(x,y),Size=UDim2.new(1,w,0,h),BackgroundTransparency=1,
        Font=Enum.Font.Gotham,TextSize=size or 17,TextColor3=color or colors.text,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center})
end
local function button(parent,value,x,y,width,callback,color)
    local b=make("TextButton",parent,{Text=t(value),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,38),BackgroundColor3=color or colors.green,
        TextColor3=colors.text,Font=Enum.Font.GothamBold,TextSize=15,TextWrapped=true,AutoButtonColor=true,BorderSizePixel=0});corner(b,8)
    local press=make("UIScale",b,{Scale=1})
    b.Activated:Connect(function()
        press.Scale=0.95
        Tween:Create(press,TweenInfo.new(0.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
        callback()
    end);return b
end
local function fmt(n)
    n=tonumber(n) or 0
    for _,unit in ipairs({{1e18,"Tsd. Brd."},{1e15,"Brd."},{1e12,"Bio."},{1e9,"Mrd."},{1e6,"Mio."},{1e3,"Tsd."}}) do
        if math.abs(n)>=unit[1] then return string.format("%.1f %s",n/unit[1],unit[2]) end
    end
    return tostring(math.floor(n))
end
local state,page=nil,"home"
local visible=true
local bindings={}
local family,partIndex,quantity="C",1,1
local diagnosis,challenge=nil,nil
local overlay
local toolSlot=1
local rebuild,showPage,refresh,protectCoreUI
local width,height,scale=1060,700,1
local gui=make("ScreenGui",player:WaitForChild("PlayerGui"),{Name="UltimateCarGame",ResetOnSpawn=false,DisplayOrder=20,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local top=frame(gui,UDim2.fromOffset(310,46),UDim2.new(0.5,0,0,8),colors.bg);top.Name="CompactProgress";top.AnchorPoint=Vector2.new(0.5,0)
local headline=text(top,"ULTIMATE CAR GAME",10,2,-20,13,10,colors.muted);headline.TextXAlignment=Enum.TextXAlignment.Center
local stats=text(top,"Karriere wird geladen …",10,15,-20,21,13);stats.Font=Enum.Font.GothamBold;stats.TextXAlignment=Enum.TextXAlignment.Center
local xpTrack=frame(top,UDim2.new(1,-20,0,3),UDim2.fromOffset(10,39),colors.line)
local xpFill=frame(xpTrack,UDim2.new(0,0,1,0),UDim2.new(),colors.green)
local tablet=frame(gui,UDim2.fromOffset(width,height),UDim2.new(0.5,0,0.5,35),colors.bg);tablet.AnchorPoint=Vector2.new(0.5,0.5)
local tabletScale=make("UIScale",tablet,{Scale=1})
local title=text(tablet,"Ultimate Car Game",22,10,-100,34,24);title.Font=Enum.Font.GothamBold
local subtitle=text(tablet,"Deine Werkstatt. Dein nächster Auftrag.",22,45,-44,23,15,colors.muted)
local closeButton=button(tablet,"×",width-60,14,38,function() visible=false;tablet.Visible=false end,colors.card)
local nav=make("ScrollingFrame",tablet,{Position=UDim2.fromOffset(20,80),Size=UDim2.new(1,-40,0,48),CanvasSize=UDim2.fromOffset(600,0),ScrollingDirection=Enum.ScrollingDirection.X,ScrollBarThickness=3,BackgroundTransparency=1,BorderSizePixel=0})
local navButtons={}
local navOrder={};for _,key in ipairs(C.Stations) do table.insert(navOrder,key) end;table.insert(navOrder,2,"tools")
local navX=0
for i,key in ipairs(navOrder) do
    local shop=key=="shop";local w=shop and 172 or 112
    local b=button(nav,C.StationNames[key],navX,0,w,function() send("travel",{key=key}) end,shop and colors.purpleDark or colors.card)
    b.Name="Nav_"..key
    if shop then b.Size=UDim2.fromOffset(w,44);b.TextSize=18 end
    navButtons[key]=b;navX=navX+w+8
end
nav.CanvasSize=UDim2.fromOffset(navX,0)
local body=make("ScrollingFrame",tablet,{Position=UDim2.fromOffset(20,140),Size=UDim2.new(1,-40,1,-178),CanvasSize=UDim2.new(),ScrollBarThickness=5,BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.None})
local foot=text(tablet,"",22,height-30,-44,23,12,colors.muted)
local hud=frame(gui,UDim2.new(0.96,0,0,132),UDim2.new(0.02,0,1,-138),colors.bg)
hud.Visible=false
local objective=text(hud,"Lade deine Werkstatt …",12,5,-24,39,16)
local go=button(hud,"Zum Ziel",12,47,110,function() send("target",{id=state and state.selected}) end,colors.blue)
local workButton=button(hud,"Arbeiten [E]",130,47,140,function() if state then send("work",{id=state.selected}) end end)
local menu=button(hud,"Menü [Tab]",278,47,120,function() visible=not visible;tablet.Visible=visible;if visible and rebuild then rebuild() end end,colors.card)
local toolButtons={}
for i=1,C.HotbarSize do
    toolButtons[i]=button(hud,i.." · —",12+(i-1)*98,90,92,function()
        if state and not overlay.Visible then send("tool",{id=state.data.loadout[i]}) end
    end,colors.card)
    toolButtons[i].Name="ToolSlot"..i;toolButtons[i].Size=UDim2.fromOffset(92,30)
end
local toastPanel=frame(gui,UDim2.fromOffset(330,60),UDim2.new(0.5,0,0,62),colors.panel);toastPanel.AnchorPoint=Vector2.new(0.5,0);toastPanel.Visible=false
local toastLabel=text(toastPanel,"",14,3,-28,54,14)
local toastSerial=0
local function toast(value)
    toastSerial=toastSerial+1;local serial=toastSerial
    toastLabel.Text=t(value);toastPanel.Visible=true
    task.delay(4,function() if serial==toastSerial then toastPanel.Visible=false end end)
end
overlay=make("Frame",gui,{Name="InteractionOverlay",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(),BackgroundTransparency=0.25,BorderSizePixel=0,Visible=false,ZIndex=10,Active=true})
local modal=frame(overlay,UDim2.fromOffset(580,440),UDim2.fromScale(0.5,0.5),colors.panel);modal.AnchorPoint=Vector2.new(0.5,0.5)
local modalScale=make("UIScale",modal,{Scale=1})
local function clearModal() for _,v in ipairs(modal:GetChildren()) do if not v:IsA("UIScale") and not v:IsA("UICorner") then v:Destroy() end end end
local function dismiss() challenge=nil;diagnosis=nil;overlay.Visible=false;effects.StopWork();if inputControl then inputControl.Unlock() end end
local function submitChallenge()
    if not challenge or challenge.submitted then return end
    challenge.submitted=true
    -- The server owns completion. Keep the dialog until its acknowledgement.
    send("hit",{token=challenge.token,at=workspace:GetServerTimeNow()})
end
local function modalTitle(value)
    clearModal();overlay.Visible=true;local h=text(modal,value,24,17,-48,40,24);h.Font=Enum.Font.GothamBold
end
local function bind(obj,getter) table.insert(bindings,{obj=obj,getter=getter});obj.Text=t(getter()) end
local y=0
local function card(h)
    local c=frame(body,UDim2.new(1,-8,0,h),UDim2.fromOffset(0,y),colors.card);y=y+h+12;return c
end
local function heading(c,value,sub,descriptionHeight)
    local h=text(c,value,16,8,-32,32,#t(value)>40 and 16 or 20);h.Font=Enum.Font.GothamBold
    if sub then text(c,sub,16,42,-32,descriptionHeight or 42,15,colors.muted) end
end
local function note(value)
    local c=card(70);text(c,value,16,8,-32,54,16,colors.muted);return c
end
local function d() return state and state.data end
local function job(id) return state and R.FindJob(d(),id or state.selected) end
local function timer(at) return math.max(0,math.ceil((at or 0)-workspace:GetServerTimeNow())) end
local function phase(j)
    if j.phase=="working" then return t("Arbeit läuft: {s} s",{s=timer(j.workUntil)}) end
    if j.phase=="repair" then return t(C.JobById[j.kind].steps[j.step].name) end
    return t(({diagnose="Diagnose offen",verify="Endkontrolle offen",invoice="Bereit zur Abrechnung"})[j.phase] or j.phase)
end
local function viewport(parent,carId,x,yy,w,h,paintId)
    local previews=Shared:FindFirstChild("PreviewCars")
    local template=previews and previews:FindFirstChild(C.CarById[carId].body)
    -- A late decorative preview must never abort state handling or hide the HUD.
    if not template or not template.PrimaryPart then return end
    local view=make("ViewportFrame",parent,{Position=UDim2.fromOffset(x,yy),Size=UDim2.fromOffset(w,h),BackgroundColor3=colors.bg,BorderSizePixel=0,
        Ambient=Color3.fromRGB(150,166,187),LightColor=Color3.fromRGB(245,246,255),LightDirection=Vector3.new(-1,-1,-1)})
    corner(view)
    local world=make("WorldModel",view,{})
    local car=template:Clone();car.Parent=world
    local rgb=C.CarById[carId].color
    for _,part in ipairs(car:GetDescendants()) do if part:IsA("BasePart") and (part.Name=="Paint" or part.Name=="Hood" or part.Name=="Mirror") then part.Color=Color3.fromRGB(rgb[1],rgb[2],rgb[3]) end end
    local camera=make("Camera",view,{CFrame=CFrame.lookAt(Vector3.new(18,11,-23),Vector3.new(0,2,0)),FieldOfView=40})
    view.CurrentCamera=camera;return view
end
local function homePage()
    local c=card(210);heading(c,"Deine Schrauberwerkstatt","Arbeite an mehreren Kundenautos, bestelle passende Teile und baue deine Geräte aus.")
    bind(text(c,"",16,84,-32,54,17),function() return t("Level {level} · {jobs} / {bays} Bühnen belegt\n{xp} / {need} XP · {done} Aufträge abgeschlossen",{level=d().level,jobs=#d().jobs,bays=d().bays,xp=fmt(d().xp),need=fmt(state.neededXP),done=d().completed}) end)
    button(c,"Werkstatt",16,151,128,function() send("travel",{key="workshop"}) end)
    button(c,"Speichern",152,151,112,function() send("save") end,colors.card)
    if d().parkedJobs and #d().parkedJobs>0 then note("Aufträge aus dem früheren Ausbau warten auf freie Bühnen. Sie werden mit ihrem bisherigen Fortschritt automatisch wieder eingesetzt.") end
    local nextCar
    for _,v in ipairs(C.Cars) do if v.level>d().level then nextCar=v;break end end
    if nextCar then
        c=card(200);heading(c,t("Nächstes Fahrzeug: {name}",{name=nextCar.name}),t("Ab Level {level} · Fahrzeugwert {value} Cr · mehr Vergütung und XP",{level=nextCar.level,value=fmt(nextCar.value)}))
        viewport(c,nextCar.id,16,88,math.min(width-88,390),100)
    else note("Alle Fahrzeugklassen sind freigeschaltet. Baue Geräte aus und übernimm anspruchsvolle Aufträge.") end
    note("Starte mit Ölservice oder Fahrzeug-Check. Kaufe Geräte im Ausbau, bestelle passende Teile und bearbeite mehrere Kundenautos parallel.")
    for _,car in ipairs(C.Cars) do
        local preview=card(178)
        heading(preview,car.name,t("{brand} · ab Level {level} · {family}",{brand=car.brand,level=car.level,family=C.Families[car.family]}))
        viewport(preview,car.id,16,84,math.min(width-88,390),85)
    end
end
local function workshopPage()
    note("Jedes Kundenauto hat eine eigene Bühne und eigene Arbeitsschritte. Wähle Zum Auto, bediene Bühne und Haube und arbeite mit dem passenden Werkzeug.")
    for _,j in ipairs(d().jobs) do
        local id=j.id;local def,car=C.JobById[j.kind],C.CarById[j.carId]
        local c=card(202);heading(c,t("Bühne {bay} · {car} · {name}",{bay=j.bay,car=car.name,name=def.name}))
        bind(text(c,"",16,44,-32,51,16,colors.muted),function() local cur=job(id);return cur and phase(cur).."\n"..t("Qualität {q}% · Teilefamilie {family}",{q=cur.quality,family=C.Families[car.family]}) or "" end)
        button(c,"Zum Auto",16,102,120,function() send("target",{id=id,car=true});visible=false;tablet.Visible=false end)
        button(c,"Teile wählen",144,102,130,function() send("select",{id=id});family=car.family;local cur=job(id);local step=cur and def.steps[cur.step];if step and step.part then for i,k in ipairs(C.PartTypes) do if k.id==step.part then partIndex=i end end end;send("travel",{key="parts"}) end,colors.blue)
        button(c,"Abrechnen",282,102,120,function() send("settle",{id=id}) end,colors.blue)
        button(c,"Auftrag abbrechen",16,150,190,function() send("confirm",{key="cancel",id=id}) end,colors.red)
        local expected=R.Reward(d(),j);text(c,t("Erwartet: {cr} Cr + {xp} XP",{cr=fmt(expected),xp=fmt(def.xp*car.xp)}),215,152,-230,40,14,colors.yellow)
    end
    if #d().jobs==0 then note("Noch kein Kundenauto in der Werkstatt. Nimm unten deinen ersten Auftrag an.") end
    for _,o in ipairs(d().offers) do
        local offerId=o.id;local def,car=C.JobById[o.kind],C.CarById[o.carId]
        local missing,level=R.RequiredEquipment(d(),def)
        local c=card(184);heading(c,def.name.." · "..car.name,def.complaint)
        text(c,t("Familie {family} · Basis {cr} Cr · {xp} XP",{family=C.Families[car.family],cr=fmt(def.reward*car.reward),xp=fmt(def.xp*car.xp)}),16,86,-32,25,14,colors.yellow)
        button(c,"Auftrag annehmen",16,128,176,function() send("accept",{id=offerId}) end)
        if missing then text(c,t("Benötigt: {device} Stufe {level}",{device=C.EquipmentById[missing].name,level=level}),207,119,-223,59,14,colors.muted) end
    end
end
local function toolsPage()
    note("Fünf aktive Werkzeuge: Wähle einen Platz und dann ein Werkzeug. Alles andere bleibt in der Kiste. Tauschen geht nur hier vor Ort.")
    local c=card(112);heading(c,"Deine Werkzeugleiste")
    local bw=math.min(176,(width-80)/5-6)
    for i=1,C.HotbarSize do
        local id=d().loadout[i]
        button(c,i.." · "..C.Tools[id].short,16+(i-1)*(bw+6),54,bw,function() toolSlot=i;rebuild() end,toolSlot==i and colors.green or colors.card)
    end
    for _,id in ipairs(C.ToolOrder) do
        local def=C.Tools[id];local unlocked=R.ToolUnlocked(d(),id)
        local status=R.ToolActive(d(),id) and "Aktiv in der Leiste" or "In der Werkzeugkiste"
        local description=def.description or ({scanner="Fehlerspeicher, Diagnose und Endkontrolle.",ratchet="Befestigungen und Reparaturen am Fahrzeug.",oil="Ölservice und Flüssigkeitswechsel.",tire="Reifenmontage mit der Montiermaschine.",meter="Elektrische Messungen und Fehlersuche."})[id]
        c=card(184);heading(c,def.name,description)
        text(c,unlocked and status or ("Benötigt: "..C.EquipmentById[def.equipment].name),16,89,-32,30,14,colors.muted)
        button(c,"Auf Platz "..toolSlot.." legen",16,132,220,function() send("swapTool",{slot=toolSlot,id=id}) end,unlocked and colors.green or colors.card)
    end
end
local function partsPage()
    local selectedJob=job()
    local c=card(215);heading(c,"Teilehandel · Lager & Bestellung","Nexra, Ferrovia und Orvex liefern passende Teile. Bessere Marken erhöhen den Qualitätsbonus bei der Abrechnung.")
    button(c,C.Families[family],16,99,182,function() family=({C="L",L="P",P="C"})[family];rebuild() end,colors.blue)
    button(c,C.PartTypes[partIndex].name,206,99,196,function() partIndex=partIndex%#C.PartTypes+1;rebuild() end,colors.blue)
    button(c,"Menge: "..quantity,16,149,125,function() quantity=quantity==1 and 3 or 1;rebuild() end,colors.card)
    for _,b in ipairs(C.Brands) do
        local sku=b.id.."_"..family.."_"..C.PartTypes[partIndex].id;local p=C.PartById[sku]
        c=card(174);heading(c,p.brand.." · "..p.name)
        bind(text(c,"",16,44,-32,52,15,colors.muted),function() return t("{price} Cr / Stück · Lager {stock} · Level {level}\n{eta} · Qualitätsbonus +{quality}",{price=fmt(p.price),stock=d().inventory[sku] or 0,level=p.level,eta=p.eta==0 and "Sofort verfügbar" or t("Lieferung in {s} s",{s=p.eta}),quality=p.quality}) end)
        button(c,"Bestellen",16,116,130,function() send("order",{sku=sku,qty=quantity}) end)
        if selectedJob and R.Compatible(sku,selectedJob,p.kind) then
            button(c,selectedJob.selectedParts[p.kind]==sku and "Ausgewählt" or "Für Auftrag wählen",154,116,210,function() send("partSelect",{job=selectedJob.id,sku=sku}) end,colors.blue)
        end
    end
    if selectedJob then note(t("Aktiver Auftrag: {name} · Familie {family}. Ein ausdrücklich gewählter Hersteller wird nicht automatisch ausgetauscht.",{name=C.CarById[selectedJob.carId].name,family=C.Families[C.CarById[selectedJob.carId].family]})) end
    for _,o in ipairs(d().orders) do
        local deliveryId=o.id;local c2=card(82)
        bind(text(c2,"",16,7,-32,66,17),function() for _,current in ipairs(d().orders) do if current.id==deliveryId then local p=C.PartById[current.sku];return t("{qty} × {brand} {name}\nAnkunft in {s} s",{qty=current.qty,brand=p.brand,name=p.name,s=timer(current.eta)}) end end;return t("Geliefert") end)
    end
    note("Service-Teile sind sofort verfügbar. Andere Teile benötigen 60–120 Sekunden.")
end
local function upgradesPage()
    note("Geräte hinten im Lager oder hier am PC einer Bühne zuweisen. Je Bühne ein Geräteplatz. Höhere Gerätestufen verkürzen die passenden Arbeiten.")
    for _,e in ipairs(C.Equipment) do
        local key=e.id;local level=d().equipment[key] or 0
        local c=card(level>0 and 230 or 174);heading(c,e.name,e.description)
        text(c,t("Stufe {n}/{max} · ab Level {level} · {cost} Cr",{n=level,max=e.max,level=e.level,cost=fmt(R.EquipmentCost(d(),key))}),16,87,-32,25,15,colors.yellow)
        button(c,level>=e.max and "Voll ausgebaut" or level==0 and "Gerät kaufen" or "Gerät verbessern",16,123,220,function() send("equipment",{id=key}) end,level>=e.max and colors.card or colors.green)
        if level>0 then
            local assigned=d().equipmentBays[key]
            text(c,assigned and "Bereit an Bühne "..assigned or "Standort: hinteres Gerätelager",16,154,-32,24,14,colors.muted)
            button(c,"Gerät zuweisen",16,184,220,function() send("deviceMenu",{id=key}) end,colors.blue)
        end
    end
    for _,u in ipairs(C.Upgrades) do
        local key=u.key;local c=card(210);heading(c,u.name,u.description,60)
        local full=d()[key]>=u.max
        local description=full and "Voll ausgebaut" or t("Stufe {n}/{max} · {cost} Cr",{n=d()[key],max=u.max,cost=fmt(R.UpgradeCost(d(),key))})
        if key=="bays" and not full then description=description..t(" · Anbau + Bühne {n} ab Level {level}",{n=d().bays+1,level=C.BayLevels[d().bays+1]}) end
        text(c,description,16,112,-32,37,15,colors.muted)
        button(c,full and "Voll ausgebaut" or "Ausbauen",16,160,180,function() if not full then send("upgrade",{id=key}) end end)
    end

end
local function shopPage()
    local hero=card(132);hero.BackgroundColor3=colors.purpleDark
    heading(hero,"Credits-Shop","Credits für deine Werkstatt. Roblox zeigt vor dem Kauf den verbindlichen Preis. Alle Geräte bleiben auch erspielbar.",70)
    for _,pack in ipairs(C.CreditProducts) do
        local product=pack;local c=card(181);heading(c,product.name)
        text(c,t("{credits} Credits",{credits=string.format("%.0f",product.credits)}),16,43,-32,36,25,colors.yellow)
        bind(text(c,"",16,81,-32,37,14,colors.muted),function()
            local info=productInfo[product.productId];local base=C.CreditProducts[1];local baseInfo=productInfo[base.productId]
            if product.key==base.key then return "Das Einstiegspaket für deine Werkstatt" end
            if info and baseInfo and info.PriceInRobux>0 and baseInfo.PriceInRobux>0 then
                local bonus=math.floor((product.credits/info.PriceInRobux/(base.credits/baseInfo.PriceInRobux)-1)*100+0.5)
                if bonus>0 then return t("{bonus}% mehr Credits pro Robux als im kleinsten Paket",{bonus=bonus}) end
            end
            return "Mehr Credits für deinen nächsten Werkstattausbau"
        end)
        local buy=button(c,"Preis wird geladen …",16,127,260,function()
            local info=productInfo[product.productId]
            if not state.shopReady or not info or not info.IsForSale or not info.PriceInRobux or info.PriceInRobux<=0 then return toast("Dieses Paket ist derzeit nicht verfügbar.") end
            send("buyCredits",{key=product.key})
        end,colors.purple)
        bind(buy,function()
            if product.productId<=0 then return "In Kürze verfügbar" end
            if Run:IsStudio() then return "Käufe im veröffentlichten Spiel" end
            if not state.shopReady then return "Speicherung wird benötigt" end
            local info=productInfo[product.productId]
            return info and info.IsForSale and (t("Kaufen").." · "..tostring(info.PriceInRobux).." Robux") or "Zurzeit nicht verfügbar"
        end)
        if product.productId>0 and not productInfo[product.productId] and not productLoading[product.productId] then
            productLoading[product.productId]=true
            task.spawn(function()
                local ok,info=pcall(function() return Marketplace:GetProductInfoAsync(product.productId,Enum.InfoType.Product) end)
                if ok and info and type(info.PriceInRobux)=="number" and info.PriceInRobux>0 then productInfo[product.productId]=info end
                productLoading[product.productId]=nil
            end)
        end
    end
end
local pages={home=homePage,workshop=workshopPage,parts=partsPage,upgrades=upgradesPage,shop=shopPage,tools=toolsPage}
rebuild=function(reset)
    if not state then return end
    local scroll=reset and 0 or body.CanvasPosition.Y
    for _,v in ipairs(body:GetChildren()) do v:Destroy() end
    bindings={};y=0;pages[page]();body.CanvasSize=UDim2.fromOffset(0,y+12);body.CanvasPosition=Vector2.new(0,math.min(scroll,math.max(0,y-body.AbsoluteSize.Y)))
    title.Text=t(C.StationNames[page]).." / ULTIMATE CAR GAME"
    for key,b in pairs(navButtons) do
        b.BackgroundColor3=key=="shop" and (key==page and colors.purple or colors.purpleDark) or (key==page and colors.green or colors.card)
    end
end
showPage=function(key)
    if not pages[key] then return end
    local different=page~=key;page=key;visible=true;tablet.Visible=true;rebuild(different)
end
refresh=function()
    hud.Visible=not visible and not overlay.Visible
    if not state then return end
    stats.Text=t("Lv. {level}  ·  {credits} Cr",{credits=fmt(d().money),level=d().level})
    local clock=R.DayClock(workspace:GetServerTimeNow(),state.dayEpoch)
    headline.Text=t("TAG {day} · {hour}:{minute}",{day=d().days+1,hour=string.format("%02d",math.floor(clock)),minute=string.format("%02d",math.floor(clock%1*60))})
    xpFill.Size=UDim2.new(math.clamp(d().xp/state.neededXP,0,1),0,1,0)
    objective.Text=t(state.objective);foot.Text=t(state.saveStatus).." · v"..C.Version.." · "..t("TAB Menü · 1–5 Werkzeug · E Arbeit · H Haube · F Bühne")
    local current=job();local visual=current and state.visuals[current.id]
    workButton.Text=t("Arbeiten [E]")
    if current then
        local aim=state.target
        if aim and aim.Name=="LiftControl" then workButton.Text=t("Bühne bedienen")
        elseif aim and aim.Name=="HoodPoint" then workButton.Text=t("Haube bedienen") end
        if aim and aim.Parent and aim.Parent:GetAttribute("EquipmentId") then workButton.Text=t("Gerät zuweisen") end
    end
    for i,b in ipairs(toolButtons) do
        local id=d().loadout[i];local unlocked=R.ToolUnlocked(d(),id)
        b.Text=i.." · "..C.Tools[id].short;b.BackgroundColor3=state.tool==id and colors.green or colors.card
        b.TextColor3=unlocked and colors.text or colors.muted
    end
    for _,binding in ipairs(bindings) do if binding.obj.Parent then binding.obj.Text=t(binding.getter()) end end
end
-- HUD action follows the currently marked station/part.
workButton:Destroy()
workButton=button(hud,"Arbeiten [E]",130,47,140,function()
    if not state then return end
    local aim=state.target
    if aim and aim.Name=="LiftControl" then send("lift",{id=state.selected})
    elseif aim and aim.Name=="HoodPoint" then send("hood",{id=state.selected})
    elseif aim and aim.Name=="parts" then send("travel",{key="parts"})
    elseif aim and aim.Name=="workshop" then send("travel",{key="workshop"})
    elseif aim and aim.Parent and aim.Parent:GetAttribute("EquipmentId") then send("deviceMenu",{id=aim.Parent:GetAttribute("EquipmentId")})
    else send("work",{id=state.selected}) end
end)
local marker=make("BillboardGui",gui,{Name="Ziel",Size=UDim2.fromOffset(170,38),StudsOffset=Vector3.new(0,2,0),AlwaysOnTop=true,Enabled=false})
local markerText=make("TextLabel",marker,{Size=UDim2.fromScale(1,1),Text=t("▼ DEIN NÄCHSTER SCHRITT"),Font=Enum.Font.GothamBold,TextSize=12,TextColor3=colors.green,BackgroundTransparency=1})
local highlight=make("Highlight",gui,{Name="WorkPartHighlight",Enabled=false,FillTransparency=0.75,OutlineColor=colors.green,FillColor=colors.green,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop})
-- Reuse native prompt input/availability, but lay out E/F/H in fixed screen rows.
-- World-space billboards can overlap at any camera angle despite UI offsets.
local shownPrompts,vehicleButtons={},{ }
local vehicleActions=frame(gui,UDim2.fromOffset(360,126),UDim2.new(0,12,1,-276),colors.bg)
vehicleActions.Name="VehicleActions";vehicleActions.Visible=false
for index,entry in ipairs({{"E","work"},{"F","lift"},{"H","hood"}}) do
    local record={key=entry[1],action=entry[2]};vehicleButtons[index]=record
    record.button=button(vehicleActions,"",6,(index-1)*42,348,function()
        local prompt=record.prompt
        if not prompt or not prompt.Parent or not prompt.Enabled or overlay.Visible or visible then return end
        send(record.action,{id=prompt:GetAttribute("JobId"),point=record.action=="work" and prompt.Parent.Name or nil})
    end,entry[1]=="E" and colors.green or colors.card)
    record.button.Name="VehicleAction_"..entry[1];record.button.Size=UDim2.new(1,-12,0,36)
end
local function refreshVehicleActions()
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local count=0
    for _,record in ipairs(vehicleButtons) do
        local chosen,nearest=nil,math.huge
        for prompt in pairs(shownPrompts) do
            if not prompt.Parent or not prompt:IsDescendantOf(workspace) then shownPrompts[prompt]=nil
            elseif root and prompt.Enabled and prompt:GetAttribute("VehicleAction")==record.action then
                local distance=(root.Position-prompt.Parent.Position).Magnitude
                if distance<=prompt.MaxActivationDistance and distance<nearest then chosen=prompt;nearest=distance end
            end
        end
        record.prompt=chosen;record.button.Visible=chosen~=nil
        if chosen then
            record.button.Text=record.key.." · "..chosen.ActionText
            record.button.Position=UDim2.fromOffset(6,count*42);count=count+1
        end
    end
    local screen=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,800)
    vehicleActions.Size=UDim2.fromOffset(math.min(360,screen.X-24),count*42)
    vehicleActions.Position=UDim2.new(0,12,1,-150-count*42)
    vehicleActions.Visible=count>0 and not visible and not overlay.Visible
end
local function markTarget()
    local target=state and state.target
    marker.Adornee=target;marker.Enabled=target~=nil and not overlay.Visible
    markerText.Text="▼ "..(target and (C.PointNames[target.Name] or ({LiftControl="F · HEBEBÜHNE",tools="WERKZEUGKISTE"})[target.Name]) or "DEIN NÄCHSTER SCHRITT")
    local part=target
    if target and target.Parent then
        for _,candidate in ipairs(target.Parent:GetChildren()) do
            if candidate:IsA("BasePart") and candidate:GetAttribute("WorkPoint")==target.Name and candidate.Transparency<1 then part=candidate;break end
        end
    end
    highlight.Adornee=part;highlight.Enabled=part~=nil and not overlay.Visible
end
Event.OnClientEvent:Connect(function(kind,value)
    if kind=="state" then
        local oldRevision=state and state.revision;local first=not state;local oldLevel=state and state.data.level;state=value
        if challenge and (not state.interaction or state.interaction.token~=challenge.token) then dismiss() end
        if oldLevel and state.data.level>oldLevel then effects.Level(state.data.level,state.data.level-oldLevel) end
        markTarget()
        refresh()
        if first or oldRevision~=state.revision then rebuild() end
    elseif kind=="page" then showPage(value)
    elseif kind=="close" then visible=false;tablet.Visible=false
    elseif kind=="toast" then toast(value)
    elseif kind=="purchaseFX" then effects.Purchase(value)
    elseif kind=="workFX" then effects.Work(value)
    elseif kind=="purchasePrompt" then
        task.spawn(function()
            local ok,info=pcall(function() return Marketplace:GetProductInfoAsync(value.productId,Enum.InfoType.Product) end)
            if not ok or not info or not info.IsForSale then return toast("Der Kauf ist gerade nicht verfügbar.") end
            productInfo[value.productId]=info
            local prompted=pcall(function() Marketplace:PromptProductPurchase(player,value.productId) end)
            if not prompted then toast("Der Roblox-Kaufdialog konnte nicht geöffnet werden.") end
        end)
    elseif kind=="interactionReset" then
        if not challenge or not value or value.token==challenge.token then dismiss() end
    elseif kind=="diagnosisDone" then if diagnosis and diagnosis.job==value then dismiss() end
    elseif kind=="scan" then effects.Work(value);if value.tool=="scanner" then toast(t("Messwerte werden ausgelesen … Bleibe am Auto.")) end
    elseif kind=="diagnose" then
        effects.StopWork();diagnosis=value;visible=false;tablet.Visible=false;modalTitle("Fahrzeugdiagnose · OBD")
        text(modal,value.report,24,67,-48,130,18,colors.muted)
        for i,answer in ipairs(value.answers) do button(modal,answer,24,213+(i-1)*52,532,function() send("diagnose",{id=value.job,choice=i}) end,colors.blue) end
        if #value.answers==0 then text(modal,value.phase=="invoice" and "Endkontrolle bestanden. Rechnung am Empfang abschließen." or "Diagnose bestätigt. Folge den markierten Arbeitsschritten.",24,220,-48,104,18,colors.green) end
        button(modal,"Schließen",24,383,150,dismiss,colors.card)
    elseif kind=="challenge" then
        challenge=value;inputControl.Lock();effects.Work({tool=value.tool,point=value.point,duration=12});visible=false;tablet.Visible=false;modalTitle("Präzise arbeiten")
        text(modal,"Stoppe den Zeiger im grünen Bereich. Tippe auf STOPP oder drücke die Leertaste.",24,70,-48,70,19,colors.muted)
        local track=frame(modal,UDim2.fromOffset(532,48),UDim2.fromOffset(24,184),colors.bg)
        frame(track,UDim2.new(value.width,0,1,0),UDim2.new(value.center-value.width/2,0,0,0),colors.green)
        challenge.cursor=frame(track,UDim2.fromOffset(5,60),UDim2.new(0,-2,0,-6),colors.yellow)
        button(modal,"STOPP",24,264,532,submitChallenge)
        button(modal,"Abbrechen",24,366,180,function() send("abortInteraction",{token=value.token}) end,colors.card)
    elseif kind=="challengeEnd" then dismiss()
    elseif kind=="receipt" then
        modalTitle("Auftrag abgeschlossen")
        text(modal,value.name,24,76,-48,64,23,colors.muted)
        text(modal,t("+{credits} Credits\n+{xp} XP",{credits=fmt(value.money),xp=fmt(value.xp)}),24,151,-48,126,32,colors.green)
        button(modal,"Weiter",24,348,532,dismiss)
    elseif kind=="device" then
        local def=C.EquipmentById[value.id];if not def then return end
        modalTitle(def.name.." bereitstellen")
        text(modal,"Wähle einen freien Geräteplatz. Laufende Arbeiten und bewegte Bühnen sperren das Umstellen.",24,70,-48,70,18,colors.muted)
        for bay=1,C.MaxBays do
            local unlocked=bay<=d().bays;local occupant
            for key,assigned in pairs(d().equipmentBays) do if assigned==bay then occupant=key end end
            local available=unlocked and (not occupant or occupant==value.id)
            local status=not unlocked and "gesperrt" or occupant==value.id and "hier bereit" or occupant and "belegt" or "frei"
            button(modal,"Bühne "..bay.." · "..status,24+((bay-1)%2)*274,160+math.floor((bay-1)/2)*56,258,function()
                if available then send("assignEquipment",{id=value.id,bay=bay}) end
            end,available and colors.green or colors.card)
        end
        button(modal,"Zurück ins Lager",24,285,532,function() send("assignEquipment",{id=value.id,bay=0}) end,colors.blue)
        button(modal,"Schließen",24,366,180,dismiss,colors.card)
    elseif kind=="confirm" then
        local expansion=value.key=="bays"
        local ready=not expansion or (d().money>=value.cost and d().level>=value.level)
        modalTitle(expansion and t("Hallenanbau · Bühne {n}",{n=value.stage+1}) or "Auftrag abbrechen?")
        local description="Dieses Kundenauto wird entfernt. Bereits eingebaute Teile werden nicht erstattet. Andere Aufträge bleiben bestehen."
        if expansion then
            description=t("Neuer Hallenabschnitt mit Hebebühne {n}.\nPreis: {cost} Cr · Guthaben: {money} Cr\nAb Level {level} · Dein Level: {current}\n{status}",{n=value.stage+1,cost=fmt(value.cost),money=fmt(d().money),level=value.level,current=d().level,status=ready and "Kauf möglich" or "Noch nicht genug Credits oder Level"})
        end
        text(modal,description,24,83,-48,218,20,colors.muted)
        button(modal,"Zurück",24,330,248,dismiss,colors.card)
        button(modal,ready and "Bestätigen" or "Noch gesperrt",288,330,268,function() if ready then send("commit",{token=value.token});dismiss() end end,expansion and (ready and colors.green or colors.card) or colors.red)
    end
end)
inputControl=InputController.new(player,{
    ToggleMenu=function()
        if overlay.Visible then return end
        visible=not visible;tablet.Visible=visible;if visible then rebuild() end;if protectCoreUI then protectCoreUI() end
    end,
    StopQTE=submitChallenge,
    SelectTool=function(slot)
        if state and not overlay.Visible then send("tool",{id=state.data.loadout[slot]}) end
    end,
})
local originalPlayerList=true
pcall(function() originalPlayerList=StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) end)
local lastListSetting
local backpackDisabled=false
protectCoreUI=function()
    if not backpackDisabled then backpackDisabled=pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false) end) end
    local desired=(not visible and not overlay.Visible) and originalPlayerList or false
    if desired~=lastListSetting then
        local ok=pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,desired) end)
        if ok then lastListSetting=desired end
    end
    local focused=UIS:GetFocusedTextBox()
    local editingChat=focused and not focused:IsDescendantOf(gui)
    local screen=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,800)
    local chatOpen=false
    if screen.X<900 then pcall(function() chatOpen=StarterGui:GetCore("ChatActive")==true end) end
    top.Visible=not editingChat and not chatOpen
end
local function resize()
    local camera=workspace.CurrentCamera;local screen=camera and camera.ViewportSize or Vector2.new(1280,800)
    width=screen.X<700 and 480 or 1060;height=screen.Y<500 and 520 or 700
    local progressWidth=screen.X>=900 and math.clamp(screen.X-840,180,310) or math.min(270,screen.X-30)
    top.Size=UDim2.fromOffset(progressWidth,46)
    stats.TextSize=progressWidth<240 and 12 or 13
    toastPanel.Size=UDim2.fromOffset(math.min(330,screen.X-28),60)
    scale=math.min(1.1,(screen.X-24)/width,(screen.Y-90)/height)
    tablet.Size=UDim2.fromOffset(width,height);tabletScale.Scale=scale
    closeButton.Position=UDim2.fromOffset(width-60,14);foot.Position=UDim2.fromOffset(22,height-30)
    modalScale.Scale=math.min(1,(screen.X-24)/580,(screen.Y-30)/440)
    local usable=screen.X*0.96-24;local tw=math.min(92,(usable-24)/5)
    for i,b in ipairs(toolButtons) do b.Position=UDim2.fromOffset(12+(i-1)*(tw+6),90);b.Size=UDim2.fromOffset(tw,30);b.TextSize=screen.X<500 and 11 or 14 end
    local first=math.min(110,usable*0.26);go.Size=UDim2.fromOffset(first,38)
    workButton.Position=UDim2.fromOffset(18+first,47);workButton.Size=UDim2.fromOffset(usable*0.35,38)
    menu.Position=UDim2.fromOffset(24+first+usable*0.35,47);menu.Size=UDim2.fromOffset(math.min(120,usable*0.3-12),38)
    if state then rebuild() end
end
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
resize()
local mouse=player:GetMouse()
UIS.InputBegan:Connect(function(input,processed)
    if processed or UIS:GetFocusedTextBox() or visible or overlay.Visible or not state then return end
    if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    local part=mouse.Target;if not part then return end
    local car=part
    while car and car~=workspace and not car:GetAttribute("JobId") do car=car.Parent end
    if not car or car==workspace or car:GetAttribute("OwnerUserId")~=player.UserId then return end
    local id=car:GetAttribute("JobId");local point=part:GetAttribute("WorkPoint")
    local current=job(id);local step=current and C.JobById[current.kind].steps[current.step]
    if state.tool=="scanner" and not (point and current and current.phase=="repair" and step and step.tool=="scanner" and step.point==point) then send("scan",{id=id})
    elseif point=="HoodPoint" then send("hood",{id=id})
    elseif point=="DiagnosticPoint" and not (current and current.phase=="repair" and step and step.point==point) then send("scan",{id=id,point=point})
    elseif point then send("work",{id=id,point=point})
    elseif state.tool=="scanner" then send("scan",{id=id}) end
end)
player.CharacterAdded:Connect(function() dismiss() end)
PromptService.PromptShown:Connect(function(prompt)
    local ancestor=prompt.Parent
    while ancestor and ancestor~=workspace do
        local owner=ancestor:GetAttribute("OwnerUserId")
        if owner and owner~=player.UserId then prompt.Enabled=false;return end
        ancestor=ancestor.Parent
    end
    if prompt:GetAttribute("VehicleAction") then shownPrompts[prompt]=true;refreshVehicleActions() end
end)
PromptService.PromptHidden:Connect(function(prompt) shownPrompts[prompt]=nil;refreshVehicleActions() end)
local nextLightUpdate=0
Run.RenderStepped:Connect(function()
    if state and os.clock()>=nextLightUpdate then
        -- Presentation interpolates the one server epoch; no client-owned days.
        Lighting.ClockTime=R.DayClock(workspace:GetServerTimeNow(),state.dayEpoch);nextLightUpdate=os.clock()+0.1
    end
    if challenge and challenge.cursor then challenge.cursor.Position=UDim2.new(R.GaugePosition(workspace:GetServerTimeNow(),challenge.startAt,challenge.period),-2,0,-6) end
end)
task.spawn(function() while gui.Parent do task.wait(0.25);protectCoreUI();if state then refresh();markTarget();refreshVehicleActions() end end end)
-- Retry only until the server has finished loading the profile. Same existing remote.
task.spawn(function()
    while gui.Parent and not state do send("hello");task.wait(1) end
end)
]]}
	},
}
