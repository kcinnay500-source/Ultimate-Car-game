-- PhoneUI: das Handy des Spielers (wie bei GTA 5), immer dabei. Eigene ScreenGui "Handy" (DisplayOrder 19: UNTER
-- dem 2.4.0-UI (20) – Diagnose-/QTE-Dialoge, OBD-Tester, Tablet und Fahrzeugknöpfe E/F/H bekommen immer den Klick).
-- Öffnen/Schließen: Taste P oder der kleine Handy-Knopf am rechten Rand (für Touch). Das Handy fährt unten rechts mit
-- einem Tween hoch, hochkant (260 × 500 bei 1080p), auf niedrigen Bildschirmen (Handy quer) quer gedreht und verkleinert;
-- es liegt nie über der 2.4.0-HUD-Leiste oder den Fahrzeugknöpfen (Freiraum-Regeln aus PrestigeUI).
--
-- Apps (alle Symbole aus Frames gezeichnet, keine Asset-IDs):
--   Kunden         Aufträge, deren Kunde eine Reparatur freigeben muss (2.4.0-Phase "approval") -> „Anrufen“;
--                  Anruf-Bildschirm mit Avatar, Name, „Es klingelt …“ und der Antwort des Kunden als Sprechblase
--   Nachrichten    die letzten 30 Hinweise (Toasts, Anrufe), neueste oben
--   Aufträge       laufende Werkstatt-Aufträge mit Phase und nächstem Schritt (aus dem 2.4.0-Zustand)
--   Auto rufen     (3.x) großer Knopf „Auto rufen“ -> car_call {} (Server stellt das Lieblingsauto, Standard Flitzer, an
--                  die nächste Fahrbahn und setzt dich hinein; auch Taste G) und die Garage: Flitzer + eigene Autos aus
--                  dem Snapshot (cars), „Favorit“ -> car_favourite {id} (CarCatalog.StarterCarId = Flitzer)
--   Karte          öffnet den Stadtplan (Minispiel-Tab "map")
--   Konto          Credits, Level, Prestige-Rang, Tycoon-Bargeld (aus dem Minispiel-Snapshot)
--   Einstellungen  Beginner-/Passiv-Modus (bestehende Aktion lobby_settings); solange die Startwahl offen ist
--                  („Später entscheiden“), der Knopf „Startweg wählen“ (ctx.ReopenStart -> StartUI.Reopen)
--
-- Der Client sendet nur Absichten: phone_call {id} (Auftrags-ID, String), lobby_settings, car_call {} und
-- car_favourite {id} (Auto-Id als Zahl, keine Beträge) über MiniRemote. Ob und
-- wie der Kunde antwortet, entscheidet der Server (Ereignis "call": state = "ringing" | "answer" | "ended").
-- Das Handy blendet sich aus, solange QTE/Diagnose/OBD-Tester (ctx.IsBlocked), das Tablet, das Minispiel-Panel
-- oder die Fahrt (ScreenGui "Fahren") zu sehen sind; danach kommt es im selben Zustand wieder.
--
-- Start(ctx) – ctx aus MiniClient (siehe MiniClient.Start), zusätzlich zu den üblichen Feldern:
--   Remote        MiniRemote (Send)
--   IsBlocked()   QTE/Diagnose/Tester
--   IsTabletOpen()
--   IsPanelOpen() Minispiel-Panel offen (MiniClient.IsOpen)
--   Open(tab)     Minispiel-Tab öffnen (MiniClient.Open) – für die App „Karte“
--   GetState()    2.4.0-Zustand (GarageClient state: state.data.jobs …), optional
--   OnEvent(fn)   meldet fn(kind, value) für das 2.4.0-Server-Ereignis "call" an, optional; ohne Hook hört das Handy
--                 selbst am Remote "Event" auf "call"
--   Snapshot()    letzter Minispiel-Snapshot (MiniClient.Snapshot), optional (sonst PhoneUI.OnSnapshot)
--   ReopenStart() Startwahl wieder zeigen (StartUI.Reopen), optional
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhoneUI = {}

PhoneUI.DisplayOrder = 19
PhoneUI.Width = 260 -- hochkant, logische Pixel (bei 1080p 1:1)
PhoneUI.Height = 500
PhoneUI.Bezel = 8
PhoneUI.Margin = 8
PhoneUI.ButtonSize = 48
PhoneUI.AutoCloseSeconds = 3.5 -- nach einer Zusage des Kunden schließt das Handy von selbst
PhoneUI.MaxMessages = 30
PhoneUI.DialTimeout = 10 -- Sekunden ohne Antwort des Servers -> „Keine Verbindung“
PhoneUI.MinPortraitScale = 0.75 -- darunter wird das Handy quer gelegt, wenn es quer größer wäre
PhoneUI.Key = Enum.KeyCode.P
PhoneUI.Apps = {
	{ key = "kunden", title = "Kunden" },
	{ key = "nachrichten", title = "Nachrichten" },
	{ key = "auftraege", title = "Aufträge" },
	{ key = "auto", title = "Auto rufen" }, -- 3.x: Auto rufen + Garage (Lieblingsauto)
	{ key = "karte", title = "Karte" },
	{ key = "konto", title = "Konto" },
	{ key = "einstellungen", title = "Einstellungen" },
}

local TITLES = {}
for _, a in ipairs(PhoneUI.Apps) do
	TITLES[a.key] = a.title
end

local C = {
	bezel = Color3.fromRGB(8, 8, 10),
	edge = Color3.fromRGB(58, 62, 70),
	text = Color3.fromRGB(240, 244, 250),
	muted = Color3.fromRGB(170, 182, 198),
	card = Color3.fromRGB(22, 26, 36),
	cardLine = Color3.fromRGB(60, 68, 84),
	green = Color3.fromRGB(46, 196, 120),
	red = Color3.fromRGB(226, 62, 74),
	yellow = Color3.fromRGB(240, 186, 64),
	blue = Color3.fromRGB(58, 132, 230),
	wall1 = Color3.fromRGB(40, 22, 86),
	wall2 = Color3.fromRGB(18, 76, 140),
	wall3 = Color3.fromRGB(10, 14, 28),
}

local PHASES = {
	approval = "Freigabe offen",
	diagnose = "Diagnose offen",
	repair = "Reparatur",
	working = "Arbeit läuft",
	verify = "Endkontrolle offen",
	invoice = "Bereit zur Abrechnung",
}

local TEXT = {
	noCustomers = "Gerade wartet kein Kunde auf einen Anruf. Findet der OBD-Tester beim Fahrzeug-Check Fehler, rufst du hier den Kunden an.",
	noJobs = "Keine laufenden Aufträge. Nimm am Empfang einen neuen Auftrag an.",
	noMessages = "Noch keine Nachrichten.",
	loading = "Daten werden geladen …",
	dialing = "Wählt …",
	ringing = "Es klingelt",
	connected = "Verbunden",
	ended = "Anruf beendet",
	noSignal = "Keine Verbindung. Versuch es gleich noch einmal.",
	noTycoon = "kein Durchlauf",
	mapHint = "Öffnet den Stadtplan mit Schnellreise.",
	settingsHint = "Änderungen wirken sofort und werden gespeichert.",
	beginner = "Beginner-Modus",
	beginnerInfo = "Hinweis-Karten und Erklärungen",
	passive = "Passiv-Modus",
	passiveInfo = "Nur zuschauen und handeln, keine Missionen",
	-- 3.x: App „Auto rufen“
	callCar = "Auto rufen",
	callHint = "Dein Auto kommt an die nächste Straße neben dir. Taste G geht auch.",
	callOnlyOW = "Auto rufen geht nur in der Open World.",
	garage = "Garage – wähle dein Lieblingsauto",
	favourite = "Favorit",
	isFavourite = "★ Favorit",
	starterInfo = "Startauto · immer dabei · unverkäuflich",
	inAuction = "In Auktion",
	startTitle = "Startweg wählen",
	startInfo = "Du hast deinen Start noch nicht gewählt. Tipp hier, um die vier Startwege zu sehen.",
}

local ctx: any = {}
local started = false
local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local refs: any = {}
local isOpen = false
local app = "home" -- "home" | App-Schlüssel | "call"
local orientation = "portrait"
local scale = 1
local headerH = 36 -- Höhe des App-Kopfs (wächst mit touchH bei kleinem Maßstab)

-- Mindesthöhe einer Touch-Fläche in logischen Pixeln: nach UIScale immer ≥ 44 px
local function touchH(base: number?): number
	return math.max(base or 44, math.ceil(44 / math.max(0.3, scale)) + 1)
end
local latest: any = nil -- Minispiel-Snapshot (OnSnapshot)
local messages: { any } = {}
local callState: any = nil -- { job, state = "dialing"|"ringing"|"answer"|"ended"|"failed", customer, car, findingName, text, accepted, result, at }
local pendingSettings: any = nil -- { values, at } nach lobby_settings, bis der Snapshot sie bestätigt
local renderedKey = nil -- Signatur der gezeigten App (neu zeichnen nur bei Änderung)
local stepTimer = 0
local slideSerial = 0
local lastHidden: string? = nil
local useHookForCalls = false

---------------------------------------------------------------- Hilfen
local function call(fn: any, ...: any): any
	if type(fn) ~= "function" then
		return nil
	end
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	warn("[Handy] " .. tostring(res))
	return nil
end

local function make(class: string, parent: Instance?, props: { [string]: any }?): any
	local obj = Instance.new(class)
	for k, v in pairs(props or {}) do
		(obj :: any)[k] = v
	end
	obj.Parent = parent
	return obj
end

local function corner(obj: Instance, r: number?)
	make("UICorner", obj, { CornerRadius = UDim.new(0, r or 10) })
end

local function round(obj: Instance)
	make("UICorner", obj, { CornerRadius = UDim.new(1, 0) })
end

local function label(parent: Instance, name: string, text: string, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", parent, {
		Name = name, Text = text, BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13,
		TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	})
	for k, v in pairs(props or {}) do
		(l :: any)[k] = v
	end
	return l
end

local function button(parent: Instance, name: string, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = make("TextButton", parent, {
		Name = name, Text = text, AutoButtonColor = true, BackgroundColor3 = color, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
	})
	corner(b, 10)
	b.Activated:Connect(function()
		call(onClick)
	end)
	return b
end

local function num(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

local function fmt(n: any): string
	n = math.floor(num(n, 0))
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return (n < 0 and "-" or "") .. out
end

-- 2.4.0-Konfiguration/Regeln (Namen von Aufträgen, Autos, Kunden); fehlen sie, zeigt das Handy die Schlüssel
local Config, Rules
pcall(function()
	local shared = ReplicatedStorage:WaitForChild("GarageShared", 5)
	Config = shared and require(shared:WaitForChild("Config", 5))
	Rules = shared and require(shared:WaitForChild("Rules", 5))
end)

local PrestigeUI -- Freiraum-Regeln der 2.4.0-Oberfläche (FreeRect); optional
pcall(function()
	PrestigeUI = require(script.Parent:WaitForChild("PrestigeUI", 5))
end)

local function jobName(kind: any): string
	local def = Config and Config.JobById and Config.JobById[kind]
	return def and def.name or tostring(kind or "Auftrag")
end

local function carName(carId: any): string
	local def = Config and Config.CarById and Config.CarById[carId]
	return def and def.name or "Kundenauto"
end

local function customerName(job: any): string
	if Rules and Rules.CustomerName then
		local ok, name = pcall(Rules.CustomerName, job)
		if ok and type(name) == "string" then
			return name
		end
	end
	return "Kunde"
end

local function initials(name: string): string
	local parts = {}
	for w in string.gmatch(name, "%S+") do
		table.insert(parts, w)
	end
	local last = parts[#parts] or name
	return string.upper(string.sub(last, 1, 1))
end

local function clockText(): string
	local t = num(Lighting.ClockTime, 12) % 24
	local h = math.floor(t)
	local m = math.floor((t - h) * 60)
	return string.format("%02d:%02d", h, m)
end

local function snapshot(): any
	local s = ctx.Snapshot and call(ctx.Snapshot)
	if type(s) == "table" then
		return s
	end
	return latest
end

local function garageState(): any
	local s = ctx.GetState and call(ctx.GetState)
	return type(s) == "table" and s or nil
end

local function jobsOf(st: any): { any }
	local data = st and st.data
	local list = type(data) == "table" and data.jobs
	return type(list) == "table" and list or {}
end

---------------------------------------------------------------- Daten
-- Aufträge, deren Kunde eine Reparatur freigeben muss (2.4.0-Phase "approval")
function PhoneUI.ApprovalJobs(): { any }
	local out = {}
	for _, j in ipairs(jobsOf(garageState())) do
		if type(j) == "table" and j.phase == "approval" and type(j.id) == "string" then
			table.insert(out, j)
		end
	end
	return out
end

-- Nächster Schritt eines Auftrags in Worten (aus Phase und Schrittliste)
function PhoneUI.NextStep(j: any): string
	local def = Config and Config.JobById and Config.JobById[j.kind]
	local step = def and def.steps and def.steps[j.step]
	if j.phase == "approval" then
		return "Kunden anrufen (App „Kunden“) und die Reparatur freigeben lassen"
	elseif j.phase == "diagnose" then
		return "OBD-Tester wählen und am OBD-Anschluss (Fahrerseite) E drücken"
	elseif j.phase == "repair" then
		return step and ("Schritt " .. tostring(j.step) .. ": " .. tostring(step.name)) or "Nächsten Arbeitsschritt ausführen"
	elseif j.phase == "working" then
		return step and ("Läuft: " .. tostring(step.name)) or "Arbeit läuft …"
	elseif j.phase == "verify" then
		return "Endkontrolle: Bühne unten, Haube zu, dann mit dem OBD-Tester prüfen"
	elseif j.phase == "invoice" then
		return "Am Empfang abrechnen"
	end
	return "–"
end

function PhoneUI.Messages(): { any }
	return messages
end

-- Nachricht ins Handy (neueste oben, höchstens MaxMessages). Gleicher Text innerhalb 1 s zählt einmal.
function PhoneUI.Notify(text: any, from: string?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local now = os.clock()
	local first = messages[1]
	if first and first.text == text and now - first.at < 1 then
		return
	end
	table.insert(messages, 1, { text = text, from = from or "Werkstatt", time = clockText(), at = now })
	while #messages > PhoneUI.MaxMessages do
		table.remove(messages)
	end
	if app == "nachrichten" then
		renderedKey = nil
	end
	PhoneUI.UpdateBadge()
end

---------------------------------------------------------------- Sichtbarkeit
local function driving(): boolean
	local pg = player and player:FindFirstChild("PlayerGui")
	local drive = pg and pg:FindFirstChild("Fahren")
	if drive and drive:IsA("LayerCollector") and drive.Enabled == true then
		return true
	end
	local ok, seated = pcall(function()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		return seat ~= nil and seat:IsA("VehicleSeat")
	end)
	return ok and seated == true
end

-- Grund, warum das Handy gerade weichen muss (nil = darf sichtbar sein)
function PhoneUI.HiddenReason(): string?
	if call(ctx.IsBlocked) == true then
		return "blocked"
	end
	if call(ctx.IsTabletOpen) == true then
		return "tablet"
	end
	if call(ctx.IsPanelOpen) == true then
		return "panel"
	end
	if driving() then
		return "drive"
	end
	return nil
end

function PhoneUI.IsOpen(): boolean
	return isOpen
end

-- Ist das Handy wirklich zu sehen (offen und nicht ausgeblendet)?
function PhoneUI.IsVisible(): boolean
	return isOpen and gui ~= nil and gui.Enabled == true and refs.phone ~= nil and refs.phone.Visible == true
end

function PhoneUI.App(): string
	return app
end

function PhoneUI.CallState(): any
	return callState
end

---------------------------------------------------------------- Layout
-- Logische Größe des Handys je Ausrichtung
local function canvas(o: string): (number, number)
	if o == "landscape" then
		return PhoneUI.Height, PhoneUI.Width
	end
	return PhoneUI.Width, PhoneUI.Height
end

-- Freie Fläche unten rechts: neben den Fahrzeugknöpfen (über der HUD-Leiste) oder darüber
local function freeArea(w: number, h: number): (number, number, number)
	local m = PhoneUI.Margin
	if not PrestigeUI then
		return w - 2 * m, h - 146 - m, h - 146
	end
	local bottom = PrestigeUI.FreeBottom(h)
	local _, zy0, zx1 = PrestigeUI.VehicleZone(w, h)
	local g = PrestigeUI.GarageGap
	local besideW = w - m - (zx1 + g)
	local aboveBottom = zy0 - g
	-- neben den Knöpfen: volle Höhe bis über die Leiste, aber nur rechts von ihnen
	local besideH = bottom - m
	local aboveW, aboveH = w - 2 * m, aboveBottom - m
	return besideW, besideH, bottom, aboveW, aboveH, aboveBottom
end

local function bestFit(w: number, h: number): (string, number, number, number)
	local bw, bh, bBottom, aw, ah, aBottom = freeArea(w, h)
	local best = { s = -1 }
	for _, o in ipairs({ "portrait", "landscape" }) do
		local cw, ch = canvas(o)
		for _, area in ipairs({ { bw, bh, bBottom }, { aw or bw, ah or bh, aBottom or bBottom } }) do
			local s = math.min(1, area[1] / cw, area[2] / ch)
			if s > 0 then
				local cand = { o = o, s = s, bottom = area[3] }
				if o == "portrait" and s >= PhoneUI.MinPortraitScale and (best.o ~= "portrait" or s > best.s) then
					best = cand
					best.locked = true
				elseif not best.locked and s > best.s then
					best = cand
				end
			end
		end
	end
	if best.s <= 0 then
		return "portrait", 0.3, h - 146, 0
	end
	return best.o, best.s, best.bottom, 0
end

local function targetPosition(): (number, number)
	local w, h = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	local cw, ch = canvas(orientation)
	cw, ch = cw * scale, ch * scale
	local m = PhoneUI.Margin
	local x = w - m - cw
	local _, _, bottom = bestFit(w, h)
	local y = bottom - ch
	if PrestigeUI then
		local ok, fx, fy = pcall(PrestigeUI.FreeRect, w, h, x, y, cw, ch)
		if ok and type(fx) == "number" and type(fy) == "number" then
			x, y = fx, fy
		end
	end
	return math.floor(x), math.floor(math.max(m, y))
end

local function buttonPosition(): (number, number)
	local w, h = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	local s = PhoneUI.ButtonSize
	local x = w - PhoneUI.Margin - s
	local y = (PrestigeUI and PrestigeUI.FreeBottom(h) or (h - 146)) - s
	if PrestigeUI then
		local ok, fx, fy = pcall(PrestigeUI.FreeRect, w, h, x, y, s, s)
		if ok and type(fx) == "number" and type(fy) == "number" then
			x, y = fx, fy
		end
	end
	return math.floor(x), math.floor(math.max(PhoneUI.Margin, y))
end

local applyOrientation -- vorwärts

-- Größe, Ausrichtung und Lage neu berechnen (Bildschirmgröße geändert, Öffnen)
function PhoneUI.Layout()
	if not gui or not refs.phone then
		return
	end
	local w, h = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	if w <= 0 or h <= 0 then
		return
	end
	local o, s = bestFit(w, h)
	local changed = o ~= orientation or math.abs(s - scale) > 1e-3 -- auch der Maßstab ändert die Touch-Höhen
	orientation, scale = o, s
	local cw, ch = canvas(o)
	refs.phone.Size = UDim2.fromOffset(cw, ch)
	refs.scale.Scale = s
	if changed then
		applyOrientation()
	end
	local x, y = targetPosition()
	refs.phone.Position = UDim2.fromOffset(x, y)
	local bx, by = buttonPosition()
	refs.button.Position = UDim2.fromOffset(bx, by)
end

---------------------------------------------------------------- Aufbau: Hülle, Statusleiste, Navigation
local function drawSignal(parent: Instance)
	local bars = make("Frame", parent, { Name = "Signal", BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 10) })
	for i = 1, 4 do
		local hgt = 3 + i * 2
		local b = make("Frame", bars, {
			Name = "Bar" .. i, BackgroundColor3 = C.text, BorderSizePixel = 0,
			Position = UDim2.fromOffset((i - 1) * 4.5, 11 - hgt), Size = UDim2.fromOffset(3, hgt),
		})
		corner(b, 1)
	end
	return bars
end

local function drawBattery(parent: Instance)
	local bat = make("Frame", parent, { Name = "Battery", BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 11) })
	local body = make("Frame", bat, { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromOffset(19, 11) })
	corner(body, 3)
	make("UIStroke", body, { Color = C.text, Thickness = 1 })
	local fill = make("Frame", body, {
		Name = "Fill", BackgroundColor3 = C.green, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(0.82, -3, 1, -4),
	})
	corner(fill, 2)
	make("Frame", bat, { Name = "Nub", BackgroundColor3 = C.text, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 3), Size = UDim2.fromOffset(2, 5) })
	return bat, fill
end

-- App-Symbol aus Frames (keine Bilder)
local function drawIcon(parent: Instance, key: string)
	local colors = {
		kunden = { Color3.fromRGB(52, 210, 120), Color3.fromRGB(16, 130, 70) },
		nachrichten = { Color3.fromRGB(80, 170, 255), Color3.fromRGB(28, 90, 210) },
		auftraege = { Color3.fromRGB(255, 170, 60), Color3.fromRGB(210, 100, 20) },
		karte = { Color3.fromRGB(70, 220, 200), Color3.fromRGB(20, 140, 150) },
		konto = { Color3.fromRGB(255, 214, 80), Color3.fromRGB(214, 150, 20) },
		auto = { Color3.fromRGB(255, 120, 90), Color3.fromRGB(214, 50, 60) },
		einstellungen = { Color3.fromRGB(160, 168, 184), Color3.fromRGB(80, 88, 104) },
	}
	local pair = colors[key] or colors.einstellungen
	local tile = make("Frame", parent, {
		Name = "Tile", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(52, 52),
	})
	corner(tile, 14)
	make("UIGradient", tile, { Color = ColorSequence.new(pair[1], pair[2]), Rotation = 90 })
	local white = Color3.new(1, 1, 1)
	local function f(name: string, x: number, y: number, w: number, h: number, r: number?, color: Color3?): Frame
		local fr = make("Frame", tile, {
			Name = name, BackgroundColor3 = color or white, BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		})
		if r then
			corner(fr, r)
		end
		return fr
	end
	if key == "kunden" then
		local head = f("Head", 19, 9, 14, 14)
		round(head)
		f("Body", 12, 26, 28, 16, 8)
		-- Hörer-Andeutung
		f("Receiver", 34, 34, 10, 10, 3, Color3.fromRGB(16, 130, 70))
	elseif key == "nachrichten" then
		f("Bubble", 9, 11, 34, 24, 10)
		f("Tail", 14, 31, 8, 8, 2)
		for i = 1, 3 do
			local dot = f("Dot" .. i, 15 + (i - 1) * 8, 20, 5, 5, nil, pair[2])
			round(dot)
		end
	elseif key == "auftraege" then
		f("Board", 13, 9, 26, 34, 4)
		f("Clip", 20, 6, 12, 6, 2, Color3.fromRGB(110, 60, 20))
		for i = 1, 3 do
			f("Line" .. i, 17, 17 + (i - 1) * 7, 18, 3, 1, pair[2])
		end
	elseif key == "karte" then
		for i = 1, 3 do
			f("Strip" .. i, 9 + (i - 1) * 12, 11 + (i % 2) * 2, 11, 28, 2, i == 2 and Color3.fromRGB(200, 250, 240) or white)
		end
		local pin = f("Pin", 22, 14, 9, 9, nil, Color3.fromRGB(230, 60, 70))
		round(pin)
	elseif key == "auto" then
		-- 3.x: kleines Auto aus Frames (Dach, Karosserie, Fenster, zwei Räder)
		f("Roof", 15, 13, 22, 11, 5)
		f("Window", 19, 15, 14, 7, 3, pair[2])
		f("Body", 7, 22, 38, 12, 5)
		f("Lamp", 39, 25, 5, 4, 2, Color3.fromRGB(255, 236, 150))
		for i, x in ipairs({ 11, 31 }) do
			local w = f("Wheel" .. i, x, 30, 11, 11, nil, Color3.fromRGB(28, 30, 36))
			round(w)
			local hub = f("Hub" .. i, 3, 3, 5, 5, nil, Color3.fromRGB(220, 224, 230))
			hub.Parent = w
			round(hub)
		end
	elseif key == "konto" then
		local coin = f("Coin", 11, 11, 30, 30, nil, Color3.fromRGB(255, 240, 170))
		round(coin)
		make("UIStroke", coin, { Color = Color3.fromRGB(190, 130, 10), Thickness = 2 })
		label(coin, "Sign", "C", {
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextSize = 18,
			TextColor3 = Color3.fromRGB(170, 110, 0), TextXAlignment = Enum.TextXAlignment.Center,
		})
	else
		local gear = f("Gear", 12, 12, 28, 28, nil, white)
		round(gear)
		for i = 1, 4 do
			local horiz = i % 2 == 0
			f("Tooth" .. i, horiz and (i == 2 and 6 or 38) or 22, horiz and 22 or (i == 1 and 6 or 38), 8, 8, 2)
		end
		local hole = f("Hole", 20, 20, 12, 12, nil, pair[2])
		round(hole)
	end
	return tile
end

local function clearContent()
	for _, c in ipairs(refs.content:GetChildren()) do
		c:Destroy()
	end
end

local function header(title: string)
	local bh = touchH(44)
	local bw = math.max(48, bh)
	headerH = bh + 4
	local bar = make("Frame", refs.content, { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headerH) })
	local back = button(bar, "Back", "‹", Color3.fromRGB(40, 44, 56), function()
		PhoneUI.Back()
	end)
	back.Size = UDim2.fromOffset(bw, bh)
	back.Position = UDim2.fromOffset(6, 2)
	back.TextSize = 22
	label(bar, "Title", title, {
		Position = UDim2.fromOffset(bw + 12, 0), Size = UDim2.new(1, -(bw + 18), 1, 0), Font = Enum.Font.GothamBold, TextSize = 16,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return bar
end

-- Scrollbare Liste unter dem Kopf
local function list(): ScrollingFrame
	local sf = make("ScrollingFrame", refs.content, {
		Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, headerH + 2),
		Size = UDim2.new(1, 0, 1, -(headerH + 2)), CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	make("UIListLayout", sf, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	make("UIPadding", sf, {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8),
	})
	return sf
end

local function card(parent: Instance, name: string, order: number, h: number): Frame
	local c = make("Frame", parent, {
		Name = name, LayoutOrder = order, BackgroundColor3 = C.card, BackgroundTransparency = 0.08, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, h),
	})
	corner(c, 10)
	make("UIStroke", c, { Color = C.cardLine, Thickness = 1, Transparency = 0.3 })
	return c
end

local function note(parent: Instance, name: string, text: string, order: number, h: number?): TextLabel
	return label(parent, name, text, {
		LayoutOrder = order, Size = UDim2.new(1, 0, 0, h or 54), TextColor3 = C.muted, TextYAlignment = Enum.TextYAlignment.Top,
	})
end

---------------------------------------------------------------- Apps
local render = {}

function render.home()
	local grid = make("Frame", refs.content, { Name = "Home", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	make("UIPadding", grid, { PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
	-- 3.x: quer alle Apps in einer Reihe (sieben Apps: Zellen schmaler), hochkant drei Spalten
	local n = #PhoneUI.Apps
	local landW = math.min(74, math.floor((PhoneUI.Height - 2 * PhoneUI.Bezel - 16 - (n - 1) * 4) / math.max(1, n)))
	local layout = make("UIGridLayout", grid, {
		SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		CellSize = orientation == "landscape" and UDim2.fromOffset(landW, 78) or UDim2.fromOffset(72, 84),
		CellPadding = orientation == "landscape" and UDim2.fromOffset(4, 6) or UDim2.fromOffset(6, 12),
	})
	refs.grid = layout
	refs.icons = {}
	for i, a in ipairs(PhoneUI.Apps) do
		local b = make("TextButton", grid, {
			Name = "App_" .. a.key, LayoutOrder = i, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		})
		b.Activated:Connect(function()
			PhoneUI.ShowApp(a.key)
		end)
		drawIcon(b, a.key)
		label(b, "Name", a.title, {
			Position = UDim2.new(0, -4, 0, 56), Size = UDim2.new(1, 8, 0, 16),
			TextSize = (orientation == "landscape" and landW < 74) and 10 or 11, Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		refs.icons[a.key] = b
		if a.key == "kunden" then
			local badge = make("Frame", b, {
				Name = "Badge", BackgroundColor3 = C.red, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 26, 0, 2), Size = UDim2.fromOffset(20, 20), Visible = false,
			})
			round(badge)
			label(badge, "Count", "1", {
				Size = UDim2.fromScale(1, 1), TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
			})
			refs.homeBadge = badge
		end
	end
end

function render.kunden()
	header("Kunden")
	local sf = list()
	local jobs = PhoneUI.ApprovalJobs()
	if #jobs == 0 then
		note(sf, "Empty", garageState() and TEXT.noCustomers or TEXT.loading, 1, 90)
		return
	end
	for i, j in ipairs(jobs) do
		local callH = touchH(48)
		local c = card(sf, "Customer_" .. j.id, i, 56 + callH)
		local who = customerName(j)
		local avatar = make("Frame", c, {
			Name = "Avatar", BackgroundColor3 = C.blue, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(34, 34),
		})
		round(avatar)
		label(avatar, "Initial", initials(who), {
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center,
		})
		label(c, "Name", who, {
			Position = UDim2.fromOffset(52, 8), Size = UDim2.new(1, -60, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local finding = j.finding and jobName(j.finding) or "Befund"
		label(c, "Info", carName(j.carId) .. " · Befund: " .. finding, {
			Position = UDim2.fromOffset(52, 26), Size = UDim2.new(1, -60, 0, 22), TextSize = 11, TextColor3 = C.muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local b = button(c, "Call_" .. j.id, "Anrufen", C.green, function()
			PhoneUI.Call(j.id)
		end)
		b.Position = UDim2.new(0, 10, 1, -(callH + 6))
		b.Size = UDim2.new(1, -20, 0, callH)
	end
end

function render.nachrichten()
	header("Nachrichten")
	local sf = list()
	if #messages == 0 then
		note(sf, "Empty", TEXT.noMessages, 1, 30)
		return
	end
	for i, m in ipairs(messages) do
		local lines = math.clamp(math.ceil((utf8.len(m.text) or #m.text) / 30), 1, 5)
		local c = card(sf, "Message" .. i, i, 30 + math.ceil(lines) * 15)
		label(c, "From", m.from .. " · " .. m.time, {
			Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 0, 14), TextSize = 10, TextColor3 = C.muted,
			Font = Enum.Font.GothamBold,
		})
		label(c, "Text", m.text, {
			Position = UDim2.fromOffset(10, 20), Size = UDim2.new(1, -20, 1, -24), TextSize = 12,
			TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
end

function render.auftraege()
	header("Aufträge")
	local sf = list()
	local st = garageState()
	local jobs = jobsOf(st)
	local order = 0
	for _, j in ipairs(jobs) do
		if type(j) == "table" then
			order += 1
			local c = card(sf, "Job_" .. tostring(j.id), order, 84)
			local phase = PHASES[j.phase] or tostring(j.phase)
			label(c, "Name", jobName(j.kind) .. (j.bay and (" · Bühne " .. tostring(j.bay)) or ""), {
				Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), Font = Enum.Font.GothamBold, TextSize = 13,
				TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
			})
			label(c, "Phase", carName(j.carId) .. " · " .. phase, {
				Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 0, 16), TextSize = 11,
				TextColor3 = j.phase == "approval" and C.yellow or (j.phase == "invoice" and C.green or C.muted),
				TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
			})
			label(c, "Next", "Als Nächstes: " .. PhoneUI.NextStep(j), {
				Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 0, 36), TextSize = 11,
				TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd,
			})
		end
	end
	local parked = st and type(st.data) == "table" and type(st.data.parkedJobs) == "table" and #st.data.parkedJobs or 0
	if parked > 0 then
		order += 1
		note(sf, "Parked", tostring(parked) .. " Auftrag/Aufträge warten auf dem Hof auf eine freie Bühne.", order, 34)
	end
	if order == 0 then
		note(sf, "Empty", st and TEXT.noJobs or TEXT.loading, 1, 60)
	end
end

---------------------------------------------------------------- 3.x: App „Auto rufen“ (car_call, Garage/Lieblingsauto)
local pendingFav: any = nil -- { id, at } nach car_favourite, bis der Snapshot es bestätigt

local function starterId(): number
	local s = snapshot()
	local st = type(s) == "table" and type(s.starterCar) == "table" and s.starterCar or nil
	return st and num(st.id, -1) or -1
end

-- Gewähltes Lieblingsauto (Snapshot favCar; kurz nach dem Tippen die eigene Wahl)
function PhoneUI.Favourite(): number
	local s = snapshot()
	local fav = type(s) == "table" and num(s.favCar, starterId()) or starterId()
	if pendingFav then
		if pendingFav.id == fav or os.clock() - pendingFav.at > 3 then
			pendingFav = nil
		else
			return pendingFav.id
		end
	end
	return fav
end

local function openWorldOnly(): boolean
	local s = snapshot()
	return type(s) == "table" and type(s.mode) == "string" and s.mode ~= "openworld"
end

-- Auto rufen: Absicht car_call {} an den Server, Handy zu (man sieht das Auto kommen)
function PhoneUI.CallCar(): boolean
	if not ctx.Remote then
		return false
	end
	if openWorldOnly() then
		call(ctx.Toast, TEXT.callOnlyOW)
		return false
	end
	ctx.Remote.Send("car_call", {})
	PhoneUI.Close()
	return true
end

-- Lieblingsauto wählen: car_favourite {id} (Flitzer = snapshot.starterCar.id)
function PhoneUI.SetFavourite(id: any): boolean
	if type(id) ~= "number" or id ~= id or id % 1 ~= 0 or not ctx.Remote then
		return false
	end
	pendingFav = { id = id, at = os.clock() }
	ctx.Remote.Send("car_favourite", { id = id })
	renderedKey = nil
	return true
end

-- Garage-Liste: Flitzer zuerst, dann die eigenen Autos (snapshot.cars)
function PhoneUI.GarageCars(): { any }
	local s = snapshot()
	local out = {}
	local st = type(s) == "table" and type(s.starterCar) == "table" and s.starterCar or nil
	table.insert(out, {
		id = st and num(st.id, -1) or -1, name = st and type(st.name) == "string" and st.name or "Flitzer",
		info = TEXT.starterInfo, starter = true,
	})
	for _, c in ipairs(type(s) == "table" and type(s.cars) == "table" and s.cars or {}) do
		if type(c) == "table" and type(c.id) == "number" then
			local stats = type(c.stats) == "table" and c.stats or {}
			table.insert(out, {
				id = c.id, name = type(c.name) == "string" and c.name or "Auto", locked = c.locked == true,
				info = (stats.topSpeed and (tostring(math.floor(num(stats.topSpeed, 0))) .. " km/h") or "") .. (c.locked == true and (" · " .. TEXT.inAuction) or ""),
			})
		end
	end
	return out
end

function render.auto()
	header(TITLES.auto)
	local sf = list()
	local bh = touchH(52)
	local c = card(sf, "CallCard", 1, 44 + bh)
	label(c, "Hint", openWorldOnly() and TEXT.callOnlyOW or TEXT.callHint, {
		Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 32), TextSize = 11, TextColor3 = C.muted,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local b = button(c, "CallCar", TEXT.callCar .. (UserInputService.KeyboardEnabled and " [G]" or ""), C.green, function()
		PhoneUI.CallCar()
	end)
	b.Position = UDim2.new(0, 10, 1, -(bh + 6))
	b.Size = UDim2.new(1, -20, 0, bh)
	b.TextSize = 16
	note(sf, "GarageTitle", TEXT.garage, 2, 18)
	local fav = PhoneUI.Favourite()
	for i, car in ipairs(PhoneUI.GarageCars()) do
		local fh = touchH(44)
		local row = card(sf, "Car_" .. tostring(car.id), 2 + i, math.max(52, fh + 8))
		label(row, "Name", car.name, {
			Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -120, 0, 18), Font = Enum.Font.GothamBold, TextSize = 13,
			TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		label(row, "Info", car.info or "", {
			Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -120, 0, 22), TextSize = 10, TextColor3 = C.muted,
			TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local isFav = car.id == fav
		local fb = button(row, "Fav_" .. tostring(car.id), isFav and TEXT.isFavourite or TEXT.favourite,
			isFav and C.yellow or Color3.fromRGB(58, 66, 84), function()
				if not car.locked then
					PhoneUI.SetFavourite(car.id)
				end
			end)
		fb.AnchorPoint = Vector2.new(1, 0.5)
		fb.Position = UDim2.new(1, -8, 0.5, 0)
		fb.Size = UDim2.fromOffset(100, fh)
		fb.TextSize = 12
		fb.AutoButtonColor = not car.locked
		fb:SetAttribute("Favourite", isFav)
		if car.locked then
			fb.Text = TEXT.inAuction
			fb.TextColor3 = C.muted
		end
	end
end

function render.karte()
	header("Karte")
	local sf = list()
	note(sf, "Hint", TEXT.mapHint, 1, 34)
	local b = button(sf, "OpenMap", "Stadtplan öffnen", C.blue, function()
		PhoneUI.Close()
		call(ctx.Open, "map")
	end)
	b.LayoutOrder = 2
	b.Size = UDim2.new(1, 0, 0, 44)
end

local function row(parent: Instance, name: string, order: number, key: string, value: string, color: Color3?)
	local c = card(parent, name, order, 44)
	label(c, "Key", key, {
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.5, -10, 1, 0), TextSize = 12, TextColor3 = C.muted, TextWrapped = false,
	})
	label(c, "Value", value, {
		Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -10, 1, 0), TextSize = 14, Font = Enum.Font.GothamBold,
		TextColor3 = color or C.text, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

function render.konto()
	header("Konto")
	local sf = list()
	local s = snapshot()
	if type(s) ~= "table" then
		note(sf, "Empty", TEXT.loading, 1, 30)
		return
	end
	local pr = type(s.prestige) == "table" and s.prestige or {}
	local ty = type(s.tycoon) == "table" and s.tycoon or {}
	local run = type(ty.run) == "table" and ty.run or nil
	row(sf, "Credits", 1, "Credits", fmt(s.credits) .. " Cr", C.green)
	row(sf, "Level", 2, "Level", tostring(math.floor(num(s.level, 1))))
	local rank = math.floor(num(pr.rank, 0))
	row(sf, "Prestige", 3, "Prestige-Rang", rank > 0 and (tostring(rank) .. (type(pr.title) == "string" and pr.title ~= "" and (" · " .. pr.title) or "")) or "noch keiner", C.yellow)
	row(sf, "Cash", 4, "Tycoon-Bargeld", run and (fmt(run.cash) .. " $") or TEXT.noTycoon)
end

local function currentSettings(): any
	local s = snapshot()
	local meta = type(s) == "table" and type(s.meta) == "table" and s.meta or nil
	if not meta then
		return nil
	end
	local v = { single = meta.single == true, passive = meta.passive == true, beginner = meta.beginner == true }
	if pendingSettings then
		if pendingSettings.values.passive == v.passive and pendingSettings.values.beginner == v.beginner then
			pendingSettings = nil -- Server hat bestätigt
		elseif os.clock() - pendingSettings.at < 3 then
			return pendingSettings.values
		else
			pendingSettings = nil
		end
	end
	return v
end

function PhoneUI.SetSetting(key: string, on: boolean): boolean
	if key ~= "passive" and key ~= "beginner" then
		return false
	end
	local v = currentSettings()
	if not v or not ctx.Remote then
		return false
	end
	local values = { single = v.single == true, passive = v.passive == true, beginner = v.beginner == true }
	values[key] = on == true
	pendingSettings = { values = values, at = os.clock() }
	ctx.Remote.Send("lobby_settings", { single = values.single, passive = values.passive, beginner = values.beginner })
	renderedKey = nil
	return true
end

function render.einstellungen()
	header("Einstellungen")
	local sf = list()
	local v = currentSettings()
	if not v then
		note(sf, "Empty", TEXT.loading, 1, 30)
		return
	end
	local function toggle(order: number, key: string, title: string, info: string)
		local on = v[key] == true
		local th = touchH(44)
		local c = card(sf, "Setting_" .. key, order, math.max(58, th + 8))
		label(c, "Title", title, {
			Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -80, 0, 18), Font = Enum.Font.GothamBold, TextSize = 13, TextWrapped = false,
		})
		label(c, "Info", info, {
			Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -80, 0, 30), TextSize = 10, TextColor3 = C.muted,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local sw = make("TextButton", c, {
			Name = "Toggle", Text = "", AutoButtonColor = false, BackgroundColor3 = on and C.green or Color3.fromRGB(70, 76, 90),
			BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(math.max(56, th), th),
			BackgroundTransparency = 1,
		})
		local track = make("Frame", sw, {
			Name = "Track", BackgroundColor3 = on and C.green or Color3.fromRGB(70, 76, 90), BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(48, 26),
		})
		round(track)
		local knob = make("Frame", track, {
			Name = "Knob", BackgroundColor3 = C.text, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(on and 1 or 0, on and -13 or 13, 0.5, 0), Size = UDim2.fromOffset(20, 20),
		})
		round(knob)
		sw:SetAttribute("On", on)
		sw.Activated:Connect(function()
			PhoneUI.SetSetting(key, not on)
		end)
	end
	toggle(1, "beginner", TEXT.beginner, TEXT.beginnerInfo)
	toggle(2, "passive", TEXT.passive, TEXT.passiveInfo)
	note(sf, "Hint", TEXT.settingsHint, 3, 30)
	-- Startwahl verschoben („Später entscheiden“): hier kommt sie jederzeit zurück
	if PhoneUI.StartPending() and type(ctx.ReopenStart) == "function" then
		local sh = touchH(44)
		local c = card(sf, "Setting_start", 4, 52 + sh)
		label(c, "Info", TEXT.startInfo, {
			Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 32), TextSize = 11, TextColor3 = C.muted,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local b = make("TextButton", c, {
			Name = "ChooseStart", Text = TEXT.startTitle, AutoButtonColor = true, BackgroundColor3 = C.blue, BorderSizePixel = 0,
			Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
			Position = UDim2.new(0, 10, 1, -(sh + 6)), Size = UDim2.new(1, -20, 0, sh),
		})
		corner(b, 10)
		b.Activated:Connect(function()
			PhoneUI.ReopenStart()
		end)
	end
end

-- Ist die Startwahl noch offen (Minispiel-Snapshot start.pending)?
function PhoneUI.StartPending(): boolean
	local s = snapshot()
	return type(s) == "table" and type(s.start) == "table" and s.start.pending == true
end

-- „Startweg wählen“: Handy zu, Startwahl (StartUI) wieder auf
function PhoneUI.ReopenStart(): boolean
	if not PhoneUI.StartPending() or type(ctx.ReopenStart) ~= "function" then
		return false
	end
	PhoneUI.Close()
	return call(ctx.ReopenStart) == true
end

-- Anruf-Bildschirm: Avatar, Name, Status (klingelt / verbunden / beendet), Antwort als Sprechblase, Auflegen
function render.call()
	local cs = callState or {}
	local root = make("Frame", refs.content, { Name = "CallScreen", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	local land = orientation == "landscape"
	local left = make("Frame", root, {
		Name = "Caller", BackgroundTransparency = 1,
		Size = land and UDim2.new(0.42, 0, 1, 0) or UDim2.new(1, 0, 0, 190),
	})
	local pulse = make("Frame", left, {
		Name = "Pulse", BackgroundColor3 = C.green, BackgroundTransparency = 0.7, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, land and 52 or 62), Size = UDim2.fromOffset(84, 84),
	})
	round(pulse)
	refs.pulse = pulse
	local avatar = make("Frame", left, {
		Name = "Avatar", BackgroundColor3 = C.blue, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pulse.Position, Size = UDim2.fromOffset(72, 72),
	})
	round(avatar)
	make("UIGradient", avatar, { Color = ColorSequence.new(Color3.fromRGB(90, 160, 255), Color3.fromRGB(40, 80, 190)), Rotation = 90 })
	local who = type(cs.customer) == "string" and cs.customer or "Kunde"
	label(avatar, "Initial", initials(who), {
		Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center,
	})
	label(left, "CallName", who, {
		Position = UDim2.fromOffset(4, land and 96 or 108), Size = UDim2.new(1, -8, 0, 22), Font = Enum.Font.GothamBold, TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local info = (type(cs.car) == "string" and cs.car or "") .. (type(cs.findingName) == "string" and (" · Befund: " .. cs.findingName) or "")
	label(left, "CallInfo", info, {
		Position = UDim2.fromOffset(4, land and 118 or 130), Size = UDim2.new(1, -8, 0, 28), TextSize = 11, TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top,
	})
	refs.callStatus = label(left, "CallStatus", "", {
		Position = UDim2.fromOffset(4, land and 146 or 160), Size = UDim2.new(1, -8, 0, 20), TextSize = 13, Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false,
	})
	local right = make("Frame", root, {
		Name = "Talk", BackgroundTransparency = 1,
		Position = land and UDim2.new(0.42, 4, 0, 0) or UDim2.fromOffset(0, 194),
		Size = land and UDim2.new(0.58, -8, 1, 0) or UDim2.new(1, 0, 1, -194),
	})
	local bubble = make("Frame", right, {
		Name = "Bubble", BackgroundColor3 = Color3.fromRGB(236, 240, 246), BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 70), Visible = false,
	})
	corner(bubble, 14)
	make("Frame", bubble, {
		Name = "Tail", BackgroundColor3 = Color3.fromRGB(236, 240, 246), BorderSizePixel = 0, Position = UDim2.new(0, 14, 1, -6),
		Size = UDim2.fromOffset(12, 12),
	})
	refs.bubbleText = label(bubble, "Text", "", {
		Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 1, -12), TextSize = 13, TextColor3 = Color3.fromRGB(20, 24, 32),
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	refs.bubble = bubble
	refs.callResult = label(right, "CallResult", "", {
		Position = UDim2.fromOffset(10, 86), Size = UDim2.new(1, -20, 0, 40), TextSize = 12, TextColor3 = C.green,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local hang = button(right, "HangUp", "Auflegen", C.red, function()
		PhoneUI.HangUp()
	end)
	hang.AnchorPoint = Vector2.new(0.5, 1)
	hang.Position = UDim2.new(0.5, 0, 1, -6)
	hang.Size = UDim2.new(1, -40, 0, touchH(48))
	refs.hangUp = hang
	PhoneUI.UpdateCall()
end

-- Text/Animation des Anruf-Bildschirms aus callState (ohne Neuaufbau)
function PhoneUI.UpdateCall()
	if app ~= "call" or not refs.callStatus or not refs.callStatus.Parent then
		return
	end
	local cs = callState or {}
	local dots = string.rep(".", math.floor(os.clock() * 2) % 4)
	local st = cs.state
	local status, color = TEXT.dialing, C.muted
	if st == "dialing" then
		status = TEXT.dialing .. dots
	elseif st == "ringing" then
		status, color = TEXT.ringing .. " " .. dots, C.text
	elseif st == "answer" then
		status, color = TEXT.connected, C.green
	elseif st == "ended" then
		status, color = TEXT.ended, C.muted
	elseif st == "failed" then
		status, color = type(cs.text) == "string" and cs.text or TEXT.noSignal, C.yellow
	end
	refs.callStatus.Text = status
	refs.callStatus.TextColor3 = color
	refs.callStatus.TextWrapped = st == "failed"
	refs.callStatus.Size = UDim2.new(1, -8, 0, st == "failed" and 40 or 20)
	local answered = st == "answer" and type(cs.text) == "string"
	refs.bubble.Visible = answered
	refs.bubbleText.Text = answered and cs.text or ""
	refs.callResult.Text = st == "answer" and type(cs.result) == "string" and cs.result or ""
	refs.callResult.TextColor3 = cs.accepted == false and C.yellow or C.green
	refs.hangUp.Text = (st == "answer" or st == "ended" or st == "failed") and "Fertig" or "Auflegen"
	-- Klingeln: pulsierender Ring um den Avatar
	local ringing = st == "dialing" or st == "ringing"
	refs.pulse.Visible = ringing
	if ringing then
		local k = (os.clock() * 1.6) % 1
		local sz = 76 + 28 * k
		refs.pulse.Size = UDim2.fromOffset(sz, sz)
		refs.pulse.BackgroundTransparency = 0.55 + 0.45 * k
	end
end

local function signature(): string
	if app == "kunden" or app == "auftraege" then
		local parts = {}
		for _, j in ipairs(jobsOf(garageState())) do
			if type(j) == "table" then
				table.insert(parts, tostring(j.id) .. ":" .. tostring(j.phase) .. ":" .. tostring(j.step))
			end
		end
		local st = garageState()
		local parked = st and type(st.data) == "table" and type(st.data.parkedJobs) == "table" and #st.data.parkedJobs or 0
		return app .. "|" .. tostring(st ~= nil) .. "|" .. table.concat(parts, ",") .. "|" .. parked
	elseif app == "konto" then
		local s = snapshot()
		if type(s) ~= "table" then
			return "konto|nil"
		end
		local pr = type(s.prestige) == "table" and s.prestige or {}
		local run = type(s.tycoon) == "table" and type(s.tycoon.run) == "table" and s.tycoon.run or {}
		return "konto|" .. tostring(s.credits) .. "|" .. tostring(s.level) .. "|" .. tostring(pr.rank) .. "|" .. tostring(run.cash)
	elseif app == "einstellungen" then
		local v = currentSettings()
		return "einstellungen|" .. (v and (tostring(v.passive) .. tostring(v.beginner)) or "nil") .. "|" .. tostring(PhoneUI.StartPending())
	elseif app == "auto" then
		local parts = {}
		for _, car in ipairs(PhoneUI.GarageCars()) do
			table.insert(parts, tostring(car.id) .. ":" .. tostring(car.locked) .. ":" .. tostring(car.name))
		end
		return "auto|" .. tostring(PhoneUI.Favourite()) .. "|" .. tostring(openWorldOnly()) .. "|" .. table.concat(parts, ",")
	elseif app == "nachrichten" then
		return "nachrichten|" .. tostring(#messages) .. "|" .. tostring(messages[1] and messages[1].at)
	elseif app == "home" then
		return "home|" .. orientation
	elseif app == "call" then
		return "call|" .. orientation .. "|" .. tostring(callState and callState.job)
	end
	return app
end

-- Gezeigte App neu zeichnen (force) bzw. nur, wenn sich ihre Daten geändert haben
function PhoneUI.Render(force: boolean?)
	if not refs.content then
		return
	end
	local key = signature() .. "|" .. orientation
	if not force and key == renderedKey then
		return
	end
	renderedKey = key
	clearContent()
	refs.grid, refs.icons, refs.homeBadge = nil, nil, nil
	local fn = render[app] or render.home
	local ok, err = pcall(fn)
	if not ok then
		warn("[Handy] Anzeige " .. tostring(app) .. ": " .. tostring(err))
	end
	PhoneUI.UpdateBadge()
end

-- Zähler am Handy-Knopf und am Kunden-Symbol
function PhoneUI.UpdateBadge()
	local n = #PhoneUI.ApprovalJobs()
	if refs.buttonBadge then
		refs.buttonBadge.Visible = n > 0
		refs.buttonBadgeText.Text = tostring(n)
	end
	if refs.homeBadge and refs.homeBadge.Parent then
		refs.homeBadge.Visible = n > 0
		local t = refs.homeBadge:FindFirstChild("Count")
		if t then
			t.Text = tostring(n)
		end
	end
end

applyOrientation = function()
	if not refs.phone then
		return
	end
	local land = orientation == "landscape"
	refs.status.Size = UDim2.new(1, 0, 0, land and 20 or 24)
	local nh = touchH(44) -- Navigationsknöpfe nach UIScale ≥ 44 px
	local navH = nh + 6
	refs.content.Position = UDim2.fromOffset(0, land and 20 or 26)
	refs.content.Size = UDim2.new(1, 0, 1, -(land and 20 or 26) - navH)
	refs.nav.Size = UDim2.new(1, 0, 0, navH)
	for _, nb in ipairs(refs.navButtons or {}) do
		nb.Size = UDim2.fromOffset(math.max(64, nh), nh)
	end
	refs.notch.Size = UDim2.fromOffset(land and 60 or 74, land and 12 or 16)
	PhoneUI.Render(true)
end

---------------------------------------------------------------- Bedienung
function PhoneUI.ShowApp(key: string)
	if key ~= "home" and key ~= "call" and not TITLES[key] then
		return
	end
	app = key
	PhoneUI.Render(true)
end

function PhoneUI.Back()
	if app == "home" then
		PhoneUI.Close()
	elseif app == "call" then
		PhoneUI.HangUp()
	else
		PhoneUI.ShowApp("home")
	end
end

local function slide(open: boolean)
	if not gui or not refs.phone then
		return
	end
	slideSerial += 1
	local serial = slideSerial
	local x, y = targetPosition()
	local below = gui.AbsoluteSize.Y + 10
	if open then
		refs.phone.Visible = true
		refs.phone.Position = UDim2.fromOffset(x, below)
		local tw = TweenService:Create(refs.phone, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(x, y),
		})
		tw:Play()
	else
		local tw = TweenService:Create(refs.phone, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(x, below),
		})
		tw:Play()
		task.delay(0.2, function()
			if serial == slideSerial and not isOpen and refs.phone then
				refs.phone.Visible = false
				refs.phone.Position = UDim2.fromOffset(x, y)
			end
		end)
	end
end

-- Öffnet das Handy. opts.app = App-Schlüssel; opts.job = Auftrags-ID -> sofort den Kunden anrufen.
-- Liefert true, wenn das Handy offen ist (während QTE/Tablet/Fahrt bleibt es offen, aber ausgeblendet).
function PhoneUI.Open(opts: any?): boolean
	if not started or not gui then
		return false
	end
	opts = type(opts) == "table" and opts or {}
	local wasOpen = isOpen
	isOpen = true
	PhoneUI.Layout()
	if type(opts.job) == "string" then
		PhoneUI.Call(opts.job)
	elseif type(opts.app) == "string" and (TITLES[opts.app] or opts.app == "home") then
		PhoneUI.ShowApp(opts.app)
	elseif not wasOpen and app ~= "call" then
		-- wartet ein Kunde auf einen Anruf, öffnet sich gleich die Kunden-App
		PhoneUI.ShowApp(#PhoneUI.ApprovalJobs() > 0 and "kunden" or "home")
	else
		PhoneUI.Render()
	end
	if not wasOpen then
		slide(true)
	end
	PhoneUI.Refresh()
	return true
end

function PhoneUI.Close()
	if not isOpen then
		return
	end
	isOpen = false
	if app == "call" and callState and (callState.state == "answer" or callState.state == "ended" or callState.state == "failed") then
		callState = nil
		app = "home"
	end
	slide(false)
	PhoneUI.Refresh()
end

function PhoneUI.Toggle(): boolean
	if isOpen then
		PhoneUI.Close()
		return false
	end
	if PhoneUI.HiddenReason() ~= nil then
		return false -- während QTE/Diagnose/Tablet/Fahrt nicht öffnen
	end
	return PhoneUI.Open()
end

-- Kunden zum Auftrag anrufen: Absicht phone_call {id} an den Server; der Anruf-Bildschirm zeigt sofort „Wählt …“
function PhoneUI.Call(jobId: any): boolean
	if type(jobId) ~= "string" or jobId == "" or #jobId > 64 then
		return false
	end
	if callState and callState.job == jobId and (callState.state == "dialing" or callState.state == "ringing") then
		app = "call"
		PhoneUI.Render(true)
		return false -- läuft schon (Doppeltipp)
	end
	local job
	for _, j in ipairs(jobsOf(garageState())) do
		if type(j) == "table" and j.id == jobId then
			job = j
		end
	end
	callState = {
		job = jobId, state = "dialing", at = os.clock(),
		customer = job and customerName(job) or "Kunde",
		car = job and carName(job.carId) or nil,
		findingName = job and job.finding and jobName(job.finding) or nil,
	}
	if not isOpen then
		isOpen = true
		PhoneUI.Layout()
		slide(true)
	end
	app = "call"
	PhoneUI.Render(true)
	if ctx.Remote and ctx.Remote.Send then
		ctx.Remote.Send("phone_call", { id = jobId })
	end
	PhoneUI.Refresh()
	return true
end

function PhoneUI.HangUp()
	-- „Fertig“ nach Antwort/Ende/Absage beendet die Handy-Nutzung: Handy zu, Werkstatt und Tutorial wieder frei
	local cs = callState
	if cs and (cs.state == "answer" or cs.state == "ended" or cs.state == "failed") and isOpen then
		PhoneUI.Close()
		return
	end
	callState = nil
	app = "home"
	PhoneUI.Render(true)
end

---------------------------------------------------------------- Ereignisse
-- Server-Ereignis "call" (GarageServer.callCustomer): {job, state = "ringing"|"answer"|"ended", customer, car,
-- findingName, accepted, text, result}
function PhoneUI.OnCall(value: any)
	if type(value) ~= "table" or type(value.job) ~= "string" then
		return
	end
	local st = value.state
	local cs = callState
	if not cs or cs.job ~= value.job then
		if st ~= "ringing" then
			if st == "answer" and type(value.text) == "string" then
				PhoneUI.Notify(value.text, type(value.customer) == "string" and value.customer or "Kunde")
			end
			return
		end
		-- Anruf von anderswo gestartet (OBD-Tester ohne Handy-Hook): Handy übernimmt
		cs = { job = value.job, at = os.clock() }
		callState = cs
	end
	if type(value.customer) == "string" then
		cs.customer = value.customer
	end
	if type(value.car) == "string" then
		cs.car = value.car
	end
	if type(value.findingName) == "string" then
		cs.findingName = value.findingName
	end
	if st == "ringing" then
		cs.state = "ringing"
		cs.at = os.clock()
		if not isOpen then
			isOpen = true
			PhoneUI.Layout()
			slide(true)
		end
		if app ~= "call" then
			app = "call"
			PhoneUI.Render(true)
		end
	elseif st == "answer" then
		cs.state = "answer"
		cs.text = type(value.text) == "string" and value.text or nil
		cs.result = type(value.result) == "string" and value.result or nil
		cs.accepted = value.accepted == true
		if cs.text then
			PhoneUI.Notify(cs.text, cs.customer or "Kunde")
		end
		if cs.accepted then
			-- Zusage: nach kurzer Lesezeit legt das Handy selbst auf (der nächste Schritt wartet in der Werkstatt)
			task.delay(PhoneUI.AutoCloseSeconds, function()
				if callState == cs and cs.state == "answer" and isOpen and app == "call" then
					PhoneUI.Close()
				end
			end)
		end
	elseif st == "ended" then
		if cs.state ~= "answer" then
			cs.state = "ended"
		end
	end
	if app == "call" and renderedKey and string.find(renderedKey, "call|", 1, true) == 1 then
		PhoneUI.UpdateCall()
	end
	PhoneUI.Refresh()
end

-- Server-Toast (2.4.0-Format: String): ins Nachrichten-Archiv; während „Wählt …“ ist er die Antwort des Servers
function PhoneUI.OnToast(text: any)
	if type(text) ~= "string" or text == "" then
		return
	end
	PhoneUI.Notify(text)
	if callState and callState.state == "dialing" and os.clock() - callState.at < 3 then
		callState.state = "failed"
		callState.text = text
		PhoneUI.UpdateCall()
	end
end

local IGNORED_NOTICES = { leaderboard = true, tycoon_market = true, auction_update = true, mode = true }

-- Allgemeiner Eingang (MiniClient leitet weiter oder das Handy hört selbst am Remote): toast, mini_notice, call
function PhoneUI.OnEvent(kind: any, value: any)
	if kind == "call" then
		PhoneUI.OnCall(value)
	elseif kind == "toast" then
		PhoneUI.OnToast(value)
	elseif kind == "mini_notice" and type(value) == "table" and not IGNORED_NOTICES[value.kind] then
		local k = tostring(value.kind)
		if string.sub(k, 1, 7) ~= "arcade_" and string.sub(k, 1, 4) ~= "car_" and type(value.text) == "string" then
			PhoneUI.Notify(value.text)
		end
	end
end

function PhoneUI.OnSnapshot(s: any)
	if type(s) == "table" then
		latest = s
	end
end

---------------------------------------------------------------- Sichtbarkeit und Takt
function PhoneUI.Refresh()
	if not gui then
		return
	end
	local reason = PhoneUI.HiddenReason()
	gui.Enabled = reason == nil
	if refs.button then
		refs.button.Visible = not isOpen
	end
	if isOpen and refs.phone and not refs.phone.Visible then
		refs.phone.Visible = true
	end
	if reason ~= lastHidden then
		lastHidden = reason
		if reason == nil and isOpen then
			PhoneUI.Layout()
		end
	end
end

function PhoneUI.Step(dt: number?)
	if not started then
		return
	end
	if app == "call" then
		PhoneUI.UpdateCall()
		local cs = callState
		if cs and cs.state == "dialing" and os.clock() - cs.at > PhoneUI.DialTimeout then
			cs.state = "failed"
			cs.text = TEXT.noSignal
		end
	end
	stepTimer += num(dt, 0.2)
	if stepTimer < 0.25 then
		return
	end
	stepTimer = 0
	PhoneUI.Refresh()
	if refs.clock then
		refs.clock.Text = clockText()
	end
	PhoneUI.UpdateBadge()
	if isOpen and app ~= "call" then
		PhoneUI.Render()
	end
end

---------------------------------------------------------------- Start
local function build()
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("Handy")
	if old then
		old:Destroy()
	end
	gui = make("ScreenGui", nil, {
		Name = "Handy", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = PhoneUI.DisplayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	-- Handy-Knopf (Touch und Maus): kleines Telefon mit Zähler
	local b = make("TextButton", gui, {
		Name = "PhoneButton", Text = "", AutoButtonColor = true, BackgroundColor3 = C.bezel, BorderSizePixel = 0,
		Size = UDim2.fromOffset(PhoneUI.ButtonSize, PhoneUI.ButtonSize),
	})
	corner(b, 12)
	make("UIStroke", b, { Color = C.edge, Thickness = 2 })
	local mini = make("Frame", b, {
		Name = "Glyph", BackgroundColor3 = C.wall2, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 32),
	})
	corner(mini, 5)
	make("UIGradient", mini, { Color = ColorSequence.new(C.wall1, C.wall2), Rotation = 90 })
	make("Frame", mini, {
		Name = "Speaker", BackgroundColor3 = C.bezel, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(8, 2),
	})
	label(b, "Key", "P", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 1, 0), Size = UDim2.fromOffset(12, 14), TextSize = 10,
		Font = Enum.Font.GothamBold, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Right,
	})
	local badge = make("Frame", b, {
		Name = "Badge", BackgroundColor3 = C.red, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(18, 18), Visible = false,
	})
	round(badge)
	refs.buttonBadgeText = label(badge, "Count", "1", {
		Size = UDim2.fromScale(1, 1), TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
	})
	refs.buttonBadge = badge
	b.Activated:Connect(function()
		PhoneUI.Toggle()
	end)
	refs.button = b

	-- Handy: schwarzer Rahmen, Bildschirm mit Hintergrundverlauf
	local phone = make("Frame", gui, {
		Name = "Phone", BackgroundColor3 = C.bezel, BorderSizePixel = 0, Active = true, Visible = false,
		Size = UDim2.fromOffset(PhoneUI.Width, PhoneUI.Height),
	})
	corner(phone, 30)
	make("UIStroke", phone, { Color = C.edge, Thickness = 2 })
	refs.scale = make("UIScale", phone, { Scale = 1 })
	refs.phone = phone
	local screen = make("Frame", phone, {
		Name = "Screen", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ClipsDescendants = true,
		Position = UDim2.fromOffset(PhoneUI.Bezel, PhoneUI.Bezel), Size = UDim2.new(1, -2 * PhoneUI.Bezel, 1, -2 * PhoneUI.Bezel),
	})
	corner(screen, 22)
	make("UIGradient", screen, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.wall1), ColorSequenceKeypoint.new(0.55, C.wall2), ColorSequenceKeypoint.new(1, C.wall3),
		}),
		Rotation = 120,
	})
	-- Deko-Kreise im Hintergrund (Wallpaper)
	for i, spec in ipairs({ { 0.8, 0.18, 140 }, { 0.1, 0.7, 180 } }) do
		local blob = make("Frame", screen, {
			Name = "Blob" .. i, BackgroundColor3 = i == 1 and Color3.fromRGB(255, 120, 200) or Color3.fromRGB(80, 220, 255),
			BackgroundTransparency = 0.82, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]), Size = UDim2.fromOffset(spec[3], spec[3]),
		})
		round(blob)
	end
	refs.screen = screen

	-- Statusleiste: Uhr (Lighting.ClockTime), Kerbe, Empfang, Akku
	local status = make("Frame", screen, { Name = "StatusBar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24) })
	refs.status = status
	refs.clock = label(status, "Clock", clockText(), {
		Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(60, 22), Font = Enum.Font.GothamBold, TextSize = 12, TextWrapped = false,
	})
	local notch = make("Frame", status, {
		Name = "Notch", BackgroundColor3 = C.bezel, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(74, 16),
	})
	round(notch)
	refs.notch = notch
	local icons = make("Frame", status, {
		Name = "Icons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6),
		Size = UDim2.fromOffset(46, 12),
	})
	local sig = drawSignal(icons)
	sig.Position = UDim2.fromOffset(0, 0)
	local bat = drawBattery(icons)
	bat.Position = UDim2.fromOffset(24, 0)

	refs.content = make("Frame", screen, {
		Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -70),
	})

	-- Navigation unten: Zurück, Home, Schließen
	local nav = make("Frame", screen, {
		Name = "Nav", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 44),
	})
	refs.nav = nav
	local navList = make("UIListLayout", nav, {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
	})
	refs.navList = navList
	local function navButton(name: string, text: string, order: number, fn: () -> ())
		local nb = make("TextButton", nav, {
			Name = name, Text = text, LayoutOrder = order, AutoButtonColor = true, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.88, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C.text,
			Size = UDim2.fromOffset(64, 44),
		})
		corner(nb, 10)
		refs.navButtons = refs.navButtons or {}
		table.insert(refs.navButtons, nb)
		nb.Activated:Connect(function()
			call(fn)
		end)
		return nb
	end
	navButton("NavBack", "‹", 1, function()
		PhoneUI.Back()
	end)
	local home = navButton("NavHome", "", 2, function()
		if app == "home" then
			PhoneUI.Close()
		elseif app == "call" then
			PhoneUI.HangUp()
		else
			PhoneUI.ShowApp("home")
		end
	end)
	local pill = make("Frame", home, {
		Name = "Pill", BackgroundColor3 = C.text, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 6),
	})
	round(pill)
	navButton("NavClose", "×", 3, function()
		PhoneUI.Close()
	end)

	gui.Parent = pg
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		PhoneUI.Layout()
	end)
end

function PhoneUI.Start(c: any)
	if started then
		return
	end
	ctx = type(c) == "table" and c or {}
	build()
	started = true
	orientation = "portrait"
	PhoneUI.Layout()
	applyOrientation()
	PhoneUI.Refresh()

	-- Taste P (nicht beim Tippen im Chat/in Textfeldern)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= PhoneUI.Key then
			return
		end
		local ok, focused = pcall(function()
			return UserInputService:GetFocusedTextBox()
		end)
		if ok and focused then
			return
		end
		PhoneUI.Toggle()
	end)

	-- Server-Ereignisse: "call" über den 2.4.0-Hook (GarageClient), sonst direkt; Toasts/Hinweise immer direkt
	if type(ctx.OnEvent) == "function" then
		local ok = pcall(ctx.OnEvent, function(kind: any, value: any)
			if kind == "call" then
				PhoneUI.OnCall(value)
			end
		end)
		useHookForCalls = ok
	end
	task.spawn(function()
		local okE, Event = pcall(function()
			return ReplicatedStorage:WaitForChild("GarageShared", 10):WaitForChild("Remotes", 10):WaitForChild("Event", 10)
		end)
		if okE and Event then
			Event.OnClientEvent:Connect(function(kind: any, value: any)
				if kind == "call" then
					if not useHookForCalls then
						PhoneUI.OnCall(value)
					end
				elseif kind == "toast" or kind == "mini_notice" then
					PhoneUI.OnEvent(kind, value)
				elseif kind == "mini" then
					PhoneUI.OnSnapshot(value)
				end
			end)
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(PhoneUI.Step, dt)
		if not ok then
			warn("[Handy] " .. tostring(err))
		end
	end)
end

-- Für Tests und MiniClient: ScreenGui und Bausteine
function PhoneUI.Gui(): ScreenGui?
	return gui
end

function PhoneUI.Refs(): any
	return refs
end

function PhoneUI.Orientation(): (string, number)
	return orientation, scale
end

return PhoneUI
