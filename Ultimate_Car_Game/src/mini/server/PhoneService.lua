-- PhoneService: das Handy auf dem Server. Aktionen: phone_hangup {} (Auflegen während des Klingelns: der Anruf wird
-- nicht ausgewertet, der Auftrag bleibt in der Freigabe) und phone_call {id} – der Spieler ruft den Kunden eines
-- Fahrzeug-Checks an, dessen OBD-Tester Fehler im Fehlerspeicher gefunden hat (2.4.0-Phase "approval").
-- Der Server prüft die Nutzlast (String, Länge, Zeichen), eine Abklingzeit je Spieler und ruft dann
-- api.callCustomer(p, id) – das ist GarageServer.callCustomer (über MiniService ctx/api durchgereicht). Ob der Kunde
-- freigibt, entscheidet allein der Server (Rules.CustomerDecision); der Client bekommt "call"-Ereignisse
-- (ringing/answer/ended) und Toasts. Geht der Anruf nicht, gibt es einen deutschen Toast.
-- Kein Geld, keine Zeitstempel vom Client.
--
--   Register(Actions, api)   Aktion phone_call registrieren. api = MiniService-api (toast, now …) plus
--                            api.callCustomer(p, id) -> ok: boolean, msg: string?
--                            api.hangUpCall(p) -> boolean (true = ein Anruf lief und ist beendet)
local PhoneService = {}

PhoneService.Cooldown = 3 -- Sekunden zwischen zwei Anrufen eines Spielers (MiniNet.Cooldowns.phone_call ≤ dieser Wert)
PhoneService.MaxIdLength = 64

PhoneService.Text = {
	invalid = "Diesen Auftrag gibt es nicht mehr.",
	cooldown = "Einen Moment – du hast gerade erst angerufen.",
	noSignal = "Das Handy hat gerade keinen Empfang. Versuch es gleich noch einmal.",
	failed = "Gerade muss kein Kunde angerufen werden.",
}

local api: any = nil

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function toast(ms: any, text: string)
	if api and type(api.toast) == "function" then
		api.toast(ms, text)
	end
end

-- Gültige Auftrags-ID: nicht leer, höchstens 64 Zeichen, nur Buchstaben/Ziffern/_/- (2.4.0: "job_<n>")
function PhoneService.ValidId(id: any): boolean
	return type(id) == "string" and #id > 0 and #id <= PhoneService.MaxIdLength and string.match(id, "^[%w_%-]+$") ~= nil
end

-- Steht der Auftrag in den Profildaten (d.jobs)?
local function hasJob(d: any, id: string): boolean
	local jobs = type(d) == "table" and d.jobs
	if type(jobs) ~= "table" then
		return false
	end
	for _, j in ipairs(jobs) do
		if type(j) == "table" and j.id == id then
			return true
		end
	end
	return false
end

-- Handler (ms, data, d, now) wie bei den anderen Diensten. Rückgabe true = Anruf gestartet.
function PhoneService.Call(ms: any, data: any, d: any, now: any): boolean?
	local id = type(data) == "table" and data.id or nil
	if not PhoneService.ValidId(id) or not hasJob(d, id) then
		toast(ms, PhoneService.Text.invalid)
		return nil
	end
	local t = finite(now) and now or (api and type(api.now) == "function" and api.now()) or os.clock()
	local last = ms.phoneCallAt
	if finite(last) and t >= last and t - last < PhoneService.Cooldown then
		toast(ms, PhoneService.Text.cooldown)
		return nil
	end
	local fn = api and api.callCustomer
	if type(fn) ~= "function" or not ms.p then
		toast(ms, PhoneService.Text.noSignal)
		return nil
	end
	ms.phoneCallAt = t
	local ok, started, msg = pcall(fn, ms.p, id)
	if not ok then
		warn("[Handy] Anruf fehlgeschlagen: " .. tostring(started))
		toast(ms, PhoneService.Text.noSignal)
		return nil
	end
	if started ~= true then
		ms.phoneCallAt = nil -- nichts gewählt: sofort wieder erlaubt
		toast(ms, type(msg) == "string" and msg ~= "" and msg or PhoneService.Text.failed)
		return nil
	end
	return true
end

-- Auflegen (reine Absicht, keine Nutzlast): bricht den klingelnden Anruf ab. Ohne laufenden Anruf passiert nichts.
function PhoneService.HangUp(ms: any, _data: any, _d: any, _now: any): boolean?
	local fn = api and api.hangUpCall
	if type(fn) ~= "function" or not ms or not ms.p then
		return nil
	end
	local ok, ended = pcall(fn, ms.p)
	if not ok then
		warn("[Handy] Auflegen fehlgeschlagen: " .. tostring(ended))
		return nil
	end
	return ended == true or nil
end

function PhoneService.Register(Actions: any, a: any)
	api = a
	Actions.Register("phone_call", PhoneService.Call)
	Actions.Register("phone_hangup", PhoneService.HangUp)
end

-- Nur für Tests: api ohne Actions setzen
function PhoneService._SetApi(a: any)
	api = a
end

return PhoneService
