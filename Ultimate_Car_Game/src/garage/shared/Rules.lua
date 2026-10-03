-- Authoritative economy and progression. No client-provided prices or rewards.
local C=require(game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Config"))
-- 3.0: Minispiel-Daten (d.games) und Querboni auf die Werkstatt.
local Mini=game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniRules,CrossBonus=require(Mini:WaitForChild("MiniRules")),require(Mini:WaitForChild("CrossBonus"))
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
-- 3.0: Schnappschuss für den Client: Würfel-Salz (salt) nie, Befund des Fahrzeug-Checks erst nach dem OBD-Scan.
-- 3.0: So steht weder der Fehlerspeicher noch die Kundenantwort vor dem Auslesen auf dem Client (kein Annehmen/Abbrechen-Würfeln).
function R.ClientSnapshot(d)
    local s=clone(d)
    for _,list in ipairs({s.jobs or {},s.parkedJobs or {},s.offers or {}}) do
        for _,j in ipairs(list) do
            if type(j)=="table" then
                j.salt=nil
                if j.phase==nil or j.phase=="diagnose" then j.finding=nil;j.approved=nil end
            end
        end
    end
    return s
end
function R.DayClock(at,epoch)
    local hours=C.DayStartHour+math.max(0,at-epoch)*24/C.DaySeconds
    return hours%24,math.floor(hours/24)
end
function R.NewData(now)
    local d={version=2,workshopVersion=1,days=0,money=C.StartMoney,xp=0,level=1,reputation=0,bays=1,offerSlots=3,
        toolLevel=1,jobs={},offers={},orders={},inventory={nexra_C_filter=3,nexra_C_oil=3},
        equipment={},equipmentBays={},serial=0,completed=0,loadout=clone(C.DefaultLoadout),yardReady={},parkedJobs={}}
    for _,e in ipairs(C.Equipment) do d.equipment[e.id]=e.starter or 0 end
    d.games=MiniRules.DefaultGames() -- 3.0: Minispiele; data.version bleibt 2
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
            if type(key)=="string" and C.Tools[key] and key~=C.HandTool and not seen[key] then -- 3.0: freie Hand ist kein Leistenplatz
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
                    local phase=({diagnose=true,repair=true,working=true,verify=true,invoice=true,approval=true})[j.phase] and j.phase or "diagnose" -- 3.0: approval
                    local entry={id=j.id,kind=j.kind,carId=j.carId,bay=bay,phase=phase,
                        step=integer(j.step,1,1,#def.steps+1),quality=integer(j.quality,100,0,100),scanReady=j.scanReady==true,
                        workUntil=number(j.workUntil,now,0,now+120),selectedParts={},usedParts={}}
                    -- 3.0: Fahrzeug-Check: Befund, Kundenentscheidung und Check-Bonus (whitelist; alte Saves ohne Befund = kein Befund)
                    local finding=type(j.finding)=="string" and C.JobById[j.finding] and j.finding~="inspection" and j.finding or nil
                    if finding and (j.kind=="inspection" or j.kind==finding) then entry.finding=finding end
                    if type(j.salt)=="number" and j.salt==j.salt and j.salt%1==0 and j.salt>=1 and j.salt<=2147483646 then entry.salt=j.salt end -- 3.0: server-geheimes Würfel-Salz
                    if type(j.approved)=="boolean" and entry.finding then entry.approved=j.approved end
                    if entry.finding and j.kind==entry.finding and j.approved==true then entry.inspectionBonus=integer(j.inspectionBonus,0,0,1000000) end
                    if phase=="approval" and not (j.kind=="inspection" and entry.finding) then entry.phase=j.kind=="inspection" and "repair" or "diagnose" end
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
    d.games=MiniRules.LoadGames(raw.games,d,now) -- 3.0: whitelist-normalisiert, idempotent
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
    if key==C.HandTool then return true end -- 3.0: freie Hand ist immer verfügbar (fester Extra-Platz)
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
    if type(slot)~="number" or slot%1~=0 or slot<1 or slot>C.HotbarSize or not C.Tools[key] or key==C.HandTool then return false,"Ungültiger Werkzeugplatz." end -- 3.0: Hand nicht in die Leiste
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
    local target=math.min(35,d.offerSlots+CrossBonus.OfferBonus(d)) -- 3.0: Parkplatz-Serie bringt Zusatzangebote
    local jobs,cars={},{}
    for _,j in ipairs(C.Jobs) do if j.level<=d.level then table.insert(jobs,j) end end
    for _,c in ipairs(C.Cars) do if c.level<=d.level then table.insert(cars,c) end end
    -- Always retain a free, equipment-independent service job so progression cannot stall.
    local hasInspection=false
    for _,o in ipairs(d.offers) do if o.kind=="inspection" then hasInspection=true end end
    -- 3.0: salt (server-geheim, nie im Client-Schnappschuss) legt Befund und Kundenantwort des Checks fest
    if not hasInspection then table.insert(d.offers,{id=id(d,"offer_"),kind="inspection",carId=cars[random(1,#cars)].id,salt=random(1,2147483646)}) end
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
    if job.kind=="inspection" then -- 3.0: Fehlerspeicher (deterministisch je Angebot + server-geheimem Salz)
        job.salt=type(offer.salt)=="number" and offer.salt or math.random(1,2147483646)
        job.finding=R.InspectionFinding(d,job.id,job.carId,job.salt)
    end
    table.insert(d.jobs,job);table.remove(d.offers,index)
    return job
end
-- 3.0: Fahrzeug-Check mit Fehlerspeicher. Alles deterministisch aus der Auftrags-ID (Random.new(seed)).
local function mul32(a,b) -- 3.0: exakte 32-Bit-Multiplikation (ohne Genauigkeitsverlust bei Doubles)
    local aHi,aLo=math.floor(a/65536),a%65536
    return ((aHi*(b%65536)+aLo*math.floor(b/65536))%65536*65536+aLo*(b%65536))%4294967296
end
local function seedOf(text,salt) -- 3.0: FNV-1a + Murmur-Finalizer, gut gestreut auch für job_1, job_2, …
    local h=bit32.bxor(2166136261,(salt or 0)*2654435761%4294967296)
    text=tostring(text)
    for i=1,#text do h=mul32(bit32.bxor(h,string.byte(text,i)),16777619) end
    h=mul32(bit32.bxor(h,bit32.rshift(h,16)),0x85ebca6b)
    h=mul32(bit32.bxor(h,bit32.rshift(h,13)),0xc2b2ae35)
    h=bit32.bxor(h,bit32.rshift(h,16))
    return h%2147483646+1
end
R.SeedOf=seedOf -- 3.0
local function rngFor(text,salt) -- 3.0: ähnliche IDs (job_1, job_2) sollen nicht ähnlich würfeln
    local rng=Random.new(seedOf(text,salt))
    for _=1,4 do rng:NextNumber() end
    return rng
end
local electricJobs={inspection=true,tire=true,brakes=true,battery=true,hv=true} -- 3.0: wie R.RefreshOffers
local function partAvailable(d,carId,kind) -- 3.0: Teil im Lager oder bestellbar (Level)
    local family=C.CarById[carId] and C.CarById[carId].family
    for _,p in ipairs(C.Parts) do
        if p.kind==kind and p.family==family and ((d.inventory[p.id] or 0)>0 or p.level<=d.level) then return true end
    end
    return false
end
-- 3.0: Mögliche Befunde: freigeschaltete Auftragsarten außer dem Check, passend zum Auto, Geräte vorhanden,
-- Teile im Lager oder bestellbar. Gewicht 1/Vergütung (günstige Arbeiten häufiger).
function R.FindingCandidates(d,carId)
    local out={}
    for _,def in ipairs(C.Jobs) do
        local ok=def.id~="inspection" and def.level<=d.level and C.CarById[carId]~=nil and not R.RequiredEquipment(d,def)
        if ok and carId=="elys" and not electricJobs[def.id] then ok=false end
        if ok and def.id=="hv" and carId~="elys" then ok=false end
        if ok then for _,step in ipairs(def.steps) do if step.part and not partAvailable(d,carId,step.part) then ok=false end end end
        if ok then table.insert(out,{id=def.id,weight=1/math.max(1,def.reward)}) end
    end
    return out
end
function R.InspectionFinding(d,jobId,carId,salt) -- 3.0: mit salt nur vom Angebot abhängig (Abbrechen würfelt nicht neu)
    local rng=salt and rngFor("check:"..tostring(salt),0) or rngFor(jobId,0)
    if rng:NextNumber()>=C.Inspection.FindingChance then return nil end
    local list=R.FindingCandidates(d,carId)
    if #list==0 then return nil end
    local total=0;for _,c in ipairs(list) do total=total+c.weight end
    local roll=rng:NextNumber()*total
    for _,c in ipairs(list) do roll=roll-c.weight;if roll<0 then return c.id end end
    return list[#list].id
end
function R.CustomerName(job) -- 3.0
    local names=C.Inspection.Customers
    return names[rngFor(job.id,11):NextInteger(1,#names)]
end
function R.CustomerDecision(job) -- 3.0: true = Kunde gibt die Reparatur frei
    return rngFor(job.salt and "check:"..tostring(job.salt) or job.id,23):NextNumber()<C.Inspection.ApproveChance -- 3.0: salt bleibt auf dem Server
end
-- 3.0: Ergebnis des OBD-Scans eines Fahrzeug-Checks: mit Befund -> Kundenfreigabe, sonst direkt zur Sichtprüfung.
function R.InspectionScanned(job)
    if job.kind~="inspection" or job.phase~="diagnose" then return false end
    job.scanReady=true
    job.phase=job.finding and "approval" or "repair";job.step=1
    return true
end
function R.Approve(d,job,accepted) -- 3.0
    if not job or job.phase~="approval" or job.kind~="inspection" or not job.finding or not C.JobById[job.finding] then return false,"Für diesen Auftrag ist keine Freigabe offen." end
    local finding=C.JobById[job.finding]
    job.approved=accepted==true;job.step=1;job.phase="repair";job.scanReady=true
    if job.approved then
        local car=C.CarById[job.carId]
        job.inspectionBonus=round(C.JobById.inspection.reward*(car and car.reward or 1))
        job.kind=job.finding;job.selectedParts={}
        return true,"Kunde sagt Ja: „"..finding.name.."“ ist freigegeben. Der Check wird mitbezahlt."
    end
    return true,"Kunde sagt Nein: nur den Fahrzeug-Check fertig machen."
end
-- 3.0: Daten für den OBD-Tester (Fehlerspeicher und Live-Daten). Nach der Reparatur ist der Speicher leer.
function R.Tester(job)
    local kind=job.kind=="inspection" and job.finding or job.kind
    -- Abgelehnter Befund bleibt gespeichert; reparierte Fehler sind nach der Arbeit gelöscht.
    local cleared=(job.phase=="verify" or job.phase=="invoice") and not (job.kind=="inspection" and job.approved==false)
    local codes={}
    if kind and not cleared then for _,c in ipairs(C.FaultCodes[kind] or {}) do table.insert(codes,{code=c.code,text=c.text}) end end
    local faults=(not cleared and kind and C.LiveFaults[kind]) or {}
    local live,seen={},{}
    for _,v in ipairs(C.LiveValues) do table.insert(live,{name=v.name,value=faults[v.name] or v.value});seen[v.name]=true end
    local extra={};for name in pairs(faults) do if not seen[name] then table.insert(extra,name) end end
    table.sort(extra);for _,name in ipairs(extra) do table.insert(live,{name=name,value=faults[name]}) end
    return codes,live
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
    -- 3.0: Diagnosepunkte (Quiz) verkürzen die Reparatur um höchstens 35 % (richtige Richtung, anders als 3.0/HTML).
    return math.max(1,(step.seconds or 5)*(1-CrossBonus.DiagReduction(d))/((1+(d.toolLevel-1)*0.08)*(1+(eq-1)*0.12)))
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
    -- 3.0: Querboni (Presse-Anteil ×0,6, Tuning-Stufe +4,5 %/Stufe, Parkplatz-Kundenbonus ≤ ×1,7), nil-sicher.
    local base=def.reward*car.reward*CrossBonus.WorkshopReward(d)
    local reward=round(base*(1+job.quality*0.0025+partQuality*0.01))+(job.inspectionBonus or 0) -- 3.0: Check-Bonus bei freigegebenem Befund
    return math.min(C.NumberCap,reward),round(def.xp*car.xp)
end
function R.Settle(d,jobId,now)
    local job,index=R.FindJob(d,jobId) -- 3.0: Auftrag für das Check-Salz
    if not job or job.phase~="invoice" then return nil,"Die Endkontrolle ist noch nicht abgeschlossen." end
    local reward,xp=R.Reward(d,job)
    table.remove(d.jobs,index) -- Remove before granting anything: replay-safe.
    restoreParked(d)
    add(d,"money",reward);add(d,"completed",1);add(d,"reputation",2)
    local levels=R.GainXP(d,xp)
    local name=C.JobById[job.kind].name;if job.inspectionBonus then name=C.JobById.inspection.name.." + "..name end -- 3.0
    return {money=reward,xp=xp,levels=levels,name=name,quality=job.quality,inspectionBonus=job.inspectionBonus} -- 3.0: Check-Bonus
end
function R.CancelJob(d,jobId)
    local job,index=R.FindJob(d,jobId) -- 3.0: Auftrag für das Check-Salz
    if not index then return false end
    table.remove(d.jobs,index);restoreParked(d)
    -- 3.0: Ein abgebrochener Fahrzeug-Check kommt mit demselben Salz als Angebot zurück (statt eines frisch gewürfelten),
    -- 3.0: damit Annehmen und Abbrechen keinen neuen Befund bringt.
    if type(job.salt)=="number" and (job.kind=="inspection" or job.inspectionBonus or job.finding) then
        local restored={id=id(d,"offer_"),kind="inspection",carId=job.carId,salt=job.salt}
        local replaced=false
        for i,o in ipairs(d.offers) do if o.kind=="inspection" then d.offers[i]=restored;replaced=true;break end end
        if not replaced then table.insert(d.offers,1,restored) end
    end
    return true
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
