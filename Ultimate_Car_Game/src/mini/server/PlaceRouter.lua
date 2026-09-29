-- PlaceRouter: Ortswechsel zwischen Lobby, Open World (Stadt) und Schnellem Spiel (Tycoon)
-- (docs/PHASE4_CONTRACT.md §1). Ein Code für alle Places; das Verhalten richtet sich nach dem Attribut
-- PlaceKind an ReplicatedStorage.GarageShared ("all" | "lobby" | "openworld" | "tycoon").
--
--   PlaceRouter.Init(ctx)                        ctx = { emit(p, kind, data), toast(p, text), moveTo(p, part)?, now(),
--                                                getSession(player)?, onTeleportFailed(p, kind, result)? }
--                                                (der GarageServer-Kontext aus MiniService.Init; nur emit/toast sind Pflicht).
--                                                Verbindet einmalig TeleportService.TeleportInitFailed: schlägt ein
--                                                TeleportAsync erst asynchron fehl (GameFull, Flooded, Failure …), holt
--                                                der Server die Sitzung über ctx.getSession, warnt, zeigt den Toast und
--                                                simuliert den Ortswechsel (Simulate) – je Spieler, Party-Mitglieder
--                                                bekommen ihr eigenes Ereignis.
--   PlaceRouter.PlaceKind() -> string            Attribut PlaceKind (fehlt es: "all")
--   PlaceRouter.InitialMode(p, placeKind, joinData) -> mode, info
--                                                Modus beim Beitritt: lobby-Place -> "lobby"; openworld/tycoon -> dieser Modus;
--                                                all -> d.games.meta.lastMode (erster Beitritt: "lobby"). TeleportData aus
--                                                Player:GetJoinData() (Whitelist, Typen, Längen) überschreibt mode (nur im
--                                                all-Place) und single für diese Sitzung. Setzt p.mode, p.single, p.partyCode.
--   PlaceRouter.Go(p, kind, data) -> ok, result   Reise: data = { single = bool?, party = string?, players = { Player }? }.
--                                                Ziel-Id > 0, kein Studio, Ziel-Id ~= game.PlaceId -> TeleportService:TeleportAsync
--                                                (Singleplayer: ReserveServer + ReservedServerAccessCode; players = Party reist
--                                                gemeinsam) mit TeleportData { mode, single, party }, alles in pcall.
--                                                Sonst (oder nach einem Fehler + Toast) -> Simulate.
--   PlaceRouter.Simulate(p, kind, data) -> ok, result
--                                                Studio-Simulation: p.mode = kind, MetaRules.SetMode, Figur zur Zonen-Ankunft
--                                                (<Zone>.Arrivals.hub; Open World ohne Stadt: eigene Werkstatt), mini_notice
--                                                { kind = "mode", mode, simulated = true, single }. Fehlt die Zone in diesem
--                                                Place: bleiben + Toast, nichts geändert.
--   PlaceRouter.MoveToZone(p, kind) -> ok, msg    Figur zur Zonen-Ankunft versetzen (ohne Moduswechsel), z. B. nach dem Erscheinen.
--                                                Open World mit laufendem Tutorial: die eigene Werkstatt (dort beginnt es),
--                                                sonst die Stadt-Ankunft.
--   PlaceRouter.ArrivedText(kind) -> string      Ankunfts-Toast; Schnelles Spiel ohne Tycoon-Dienst (GameConfig.Tycoon leer):
--                                                „eröffnet bald“ mit dem Rückweg.
--   PlaceRouter.WouldTeleport(kind) -> bool      true, wenn Go einen echten Teleport versuchen würde (für den Snapshot)
--   PlaceRouter.SanitizeTeleportData(raw) -> table  Whitelist nach GameConfig.TeleportDataKeys (nur string/number/boolean)
-- Kein Geld, keine Speicherung außer meta.lastMode (MetaRules.SetMode). Teleports laufen nur in pcall, TeleportData gilt als
-- unvertrauenswürdig. Texte für den Spieler: Deutsch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("GarageShared")
local MiniShared = Shared:WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))
local TutorialRules = require(MiniShared:WaitForChild("TutorialRules"))
local CityService = require(script.Parent:WaitForChild("CityService"))

local PlaceRouter = {}

export type GoData = { single: boolean?, party: string?, players: { Player }? }
export type GoResult = { mode: string, teleported: boolean, simulated: boolean, placeId: number?, message: string? }

local TEXT = {
	unknown = "Diesen Ort gibt es nicht.",
	zoneMissing = "Dieser Bereich ist in diesem Place nicht vorhanden. Du bleibst hier.",
	noCharacter = "Warte kurz, bis deine Figur da ist.",
	teleportFailed = "Der Teleport hat nicht geklappt. Wir wechseln den Ort hier im Server.",
	arrived = { lobby = "Willkommen in der Lobby!", openworld = "Willkommen in der Werkstattmeile!", tycoon = "Schnelles Spiel: Viel Erfolg bei deiner Tycoon-Runde!" },
	tycoonSoon = "Das Schnelle Spiel eröffnet bald! Zurück geht's mit M → Tab „Lobby“ → „Zurück zur Lobby“.",
}
PlaceRouter.Text = TEXT

local ctx = nil -- { emit, toast, moveTo?, now?, getSession?, onTeleportFailed? }
local failedConnection = nil -- TeleportService.TeleportInitFailed (einmal je Server)

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function toast(p: any, text: string)
	if ctx and type(ctx.toast) == "function" and p and p.player and p.player.Parent then
		ctx.toast(p, text)
	end
end

local function emit(p: any, kind: string, data: any)
	if ctx and type(ctx.emit) == "function" and p and p.player and p.player.Parent then
		ctx.emit(p, kind, data)
	end
end

-- Gibt es das Schnelle Spiel schon (TycoonService, Meilenstein 4)? Solange GameConfig.Tycoon leer ist: nein.
function PlaceRouter.TycoonOpen(): boolean
	local t = GameConfig.Tycoon
	return type(t) == "table" and next(t) ~= nil
end

-- Ankunfts-Toast eines Modus
function PlaceRouter.ArrivedText(kind: string): string?
	if kind == "tycoon" and not PlaceRouter.TycoonOpen() then
		return TEXT.tycoonSoon
	end
	return TEXT.arrived[kind]
end

-- Modus zu einer Place-Id (Rückwärtssuche in GameConfig.Places); nil für unbekannte Ids
function PlaceRouter.ModeForPlace(placeId: any): string?
	if not finite(placeId) or placeId <= 0 then
		return nil
	end
	for _, kind in ipairs(GameConfig.Modes) do
		if PlaceRouter.PlaceId(kind) == placeId then
			return kind
		end
	end
	return nil
end

-- TeleportService.TeleportInitFailed(player, result, errorMessage, placeId, options): der übliche asynchrone
-- Fehlerweg eines echten Teleports. Sitzung holen, Ziel aus den TeleportData (SanitizeTeleportData) bzw. der Place-Id,
-- warnen, Toast und Simulation. Kein Ziel bestimmbar oder Simulation unmöglich: lastMode auf den aktuellen Modus zurück.
function PlaceRouter.OnTeleportInitFailed(player: any, result: any, message: any, placeId: any, options: any)
	local p = ctx and type(ctx.getSession) == "function" and ctx.getSession(player) or nil
	if not p or not p.profile or type(p.profile.data) ~= "table" then
		return
	end
	local td = {}
	if typeof(options) == "Instance" then
		local okData, raw = pcall(function()
			return options:GetTeleportData()
		end)
		if okData then
			td = PlaceRouter.SanitizeTeleportData(raw)
		end
	end
	local kind = PlaceRouter.IsMode(td.mode) and td.mode or PlaceRouter.ModeForPlace(placeId)
	warn("[Ortswechsel] Teleport von " .. tostring(player and player.Name) .. " nach " .. tostring(kind or placeId)
		.. " fehlgeschlagen: " .. tostring(result) .. " – " .. tostring(message))
	toast(p, TEXT.teleportFailed)
	local ok, res = false, nil
	if kind and kind ~= p.mode then
		ok, res = PlaceRouter.Simulate(p, kind, { single = td.single, party = td.party })
	end
	if not ok then
		MetaRules.SetMode(p.profile.data, p.mode) -- Reise ist nicht zustande gekommen: letzter Modus = hier
	end
	if ctx and type(ctx.onTeleportFailed) == "function" then
		pcall(ctx.onTeleportFailed, p, kind, ok and res or nil)
	end
end

function PlaceRouter.Init(c: any)
	ctx = type(c) == "table" and c or nil
	if failedConnection then
		return
	end
	local ok, err = pcall(function()
		failedConnection = TeleportService.TeleportInitFailed:Connect(function(player, result, message, placeId, options)
			local okF, errF = pcall(PlaceRouter.OnTeleportInitFailed, player, result, message, placeId, options)
			if not okF then
				warn("[Ortswechsel] TeleportInitFailed: " .. tostring(errF))
			end
		end)
	end)
	if not ok then
		warn("[Ortswechsel] TeleportInitFailed nicht verbunden: " .. tostring(err))
	end
end

function PlaceRouter.Initialized(): boolean
	return ctx ~= nil
end

---------------------------------------------------------------- Place und Modus
function PlaceRouter.PlaceKind(): string
	local ok, kind = pcall(function()
		return Shared:GetAttribute("PlaceKind")
	end)
	if ok and type(kind) == "string" and GameConfig.PlaceKindSet[kind] then
		return kind
	end
	return "all"
end

function PlaceRouter.IsMode(kind: any): boolean
	return type(kind) == "string" and GameConfig.ModeSet[kind] == true
end

-- Ziel-Id des Modus (0 = Platzhalter, nichts veröffentlicht)
function PlaceRouter.PlaceId(kind: string): number
	local id = GameConfig.Places[kind]
	if finite(id) and id > 0 and id % 1 == 0 then
		return id
	end
	return 0
end

-- true, wenn Go(kind) einen echten Teleport versuchen würde: Ziel-Id > 0, kein Studio, Ziel ~= dieser Place.
function PlaceRouter.WouldTeleport(kind: string): boolean
	local id = PlaceRouter.PlaceId(kind)
	if id <= 0 then
		return false
	end
	local okStudio, studio = pcall(function()
		return RunService:IsStudio()
	end)
	if okStudio and studio then
		return false
	end
	return id ~= game.PlaceId
end

-- TeleportData ist unvertrauenswürdig: nur die Schlüssel aus GameConfig.TeleportDataKeys mit passendem Typ,
-- Strings höchstens TeleportDataMaxLength Zeichen, Zahlen endlich.
function PlaceRouter.SanitizeTeleportData(raw: any): { [string]: any }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, kind in pairs(GameConfig.TeleportDataKeys) do
		local v = raw[key]
		if type(v) == kind then
			if kind == "string" then
				if #v > 0 and #v <= GameConfig.TeleportDataMaxLength then
					out[key] = v
				end
			elseif kind == "number" then
				if finite(v) then
					out[key] = v
				end
			else
				out[key] = v
			end
		end
	end
	return out
end

-- Modus beim Beitritt (Vertrag §1). joinData = Player:GetJoinData() (oder nil). Setzt p.mode, p.single, p.partyCode.
-- Rückgabe: mode, info = { mode, single, party, source = "place" | "saved" | "teleport", placeKind }
function PlaceRouter.InitialMode(p: any, placeKind: any, joinData: any): (string, { [string]: any })
	local kind = (type(placeKind) == "string" and GameConfig.PlaceKindSet[placeKind]) and placeKind or PlaceRouter.PlaceKind()
	local d = p and p.profile and p.profile.data or nil
	local mode, source
	if kind == "all" then
		mode, source = MetaRules.Mode(d), "saved"
	elseif kind == "lobby" then
		mode, source = "lobby", "place"
	else
		mode, source = kind, "place"
	end
	if not GameConfig.ModeSet[mode] then
		mode = GameConfig.DefaultMode
	end
	local single = false
	local party = nil
	local td = PlaceRouter.SanitizeTeleportData(type(joinData) == "table" and joinData.TeleportData or nil)
	if kind == "all" and PlaceRouter.IsMode(td.mode) then
		mode, source = td.mode, "teleport"
	end
	if type(td.single) == "boolean" then
		single = td.single
	elseif d then
		single = MetaRules.Settings(d).single
	end
	if type(td.party) == "string" then
		party = string.upper(td.party)
	end
	if p then
		p.mode = mode
		p.single = single
		p.partyCode = party
	end
	if d then
		MetaRules.SetMode(d, mode)
	end
	return mode, { mode = mode, single = single, party = party, source = source, placeKind = kind }
end

---------------------------------------------------------------- Zonen (Simulation)
local function zoneModel(kind: string): Instance?
	local zone = GameConfig.Zones[kind]
	if not zone then
		return nil
	end
	return workspace:FindFirstChild(zone.model)
end

local function arrivalCFrame(model: Instance, key: string): CFrame?
	local arrivals = model:FindFirstChild("Arrivals")
	local target = arrivals and arrivals:FindFirstChild(key)
	if target and target:IsA("BasePart") then
		return target.CFrame * CFrame.new(0, target.Size.Y / 2 + 3, 0)
	elseif target and target:IsA("Model") then
		return target:GetPivot() * CFrame.new(0, 3, 0)
	elseif target and target:IsA("Attachment") then
		return target.WorldCFrame * CFrame.new(0, 3, 0)
	end
	return nil
end

-- Zonen-Ankunft des Modus (nil, wenn die Zone in diesem Place fehlt)
function PlaceRouter.ZoneArrival(kind: string): CFrame?
	local zone = GameConfig.Zones[kind]
	local model = zoneModel(kind)
	if not zone or not model then
		return nil
	end
	return arrivalCFrame(model, zone.arrival or "hub")
end

-- true, wenn die Zone des Modus in diesem Place steht (Open World: die Stadt oder wenigstens die eigene Werkstatt)
function PlaceRouter.ZoneAvailable(p: any, kind: string): boolean
	if zoneModel(kind) then
		return true
	end
	if kind == "openworld" then
		local stations = p and p.world and p.world.model and p.world.model:FindFirstChild("Stations")
		return stations ~= nil and stations:FindFirstChild("home") ~= nil
	end
	return false
end

local function placeCharacter(p: any, destination: CFrame): (boolean, string?)
	local ch = p.player and p.player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
	if not ch or not root or not humanoid or humanoid.Health <= 0 then
		return false, TEXT.noCharacter
	end
	CityService.Unseat(humanoid) -- SeatWeld weg, sonst reist das ganze Auto mit
	ch:PivotTo(destination)
	root.AssemblyLinearVelocity = Vector3.new()
	root.AssemblyAngularVelocity = Vector3.new()
	return true
end

-- Figur zur Zonen-Ankunft versetzen (ohne Moduswechsel). Open World ohne Stadt: eigene Werkstatt (ctx.moveTo bzw.
-- CityService.Travel). Rückgabe: ok, Hinweistext bei Fehlschlag.
-- Open World: Ankunft in der eigenen Werkstatt (ctx.moveTo bzw. CityService.Travel). Rückgabe: ok, Hinweistext.
local function moveHome(p: any): (boolean, string?)
	if not (ctx and type(ctx.moveTo) == "function") then
		return false, TEXT.zoneMissing
	end
	local ch = p.player and p.player.Character
	local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
	if not ch or not humanoid or humanoid.Health <= 0 then
		return false, TEXT.noCharacter
	end
	CityService.Unseat(humanoid) -- SeatWeld weg, sonst reist das ganze Auto mit (GarageServer.moveTo löst es ebenfalls)
	local ok, err = pcall(CityService.Travel, p, "workshop", ctx.moveTo)
	if ok and err ~= false then
		return true
	end
	return false, type(err) == "string" and err or TEXT.noCharacter
end

-- Neue Spieler mit laufendem Tutorial kommen in ihrer Werkstatt an (Schritt 1 „Willkommen in deiner Werkstatt“,
-- Schritt 3 „Geh zum Empfang“ – die Grundstücke liegen bis zu 500 Studs vom Stadt-Hub entfernt).
function PlaceRouter.PrefersWorkshop(p: any, kind: string): boolean
	if kind ~= "openworld" then
		return false
	end
	local d = p and p.profile and p.profile.data or nil
	return TutorialRules.Active(d) == true
end

function PlaceRouter.MoveToZone(p: any, kind: string): (boolean, string?)
	if not PlaceRouter.IsMode(kind) then
		return false, TEXT.unknown
	end
	if PlaceRouter.PrefersWorkshop(p, kind) and PlaceRouter.ZoneAvailable(p, kind) then
		local ok, msg = moveHome(p)
		if ok then
			return true
		end
		if msg == TEXT.noCharacter then
			return false, msg
		end
		-- Werkstatt (noch) nicht erreichbar: Stadt-Ankunft
	end
	local destination = PlaceRouter.ZoneArrival(kind)
	if destination then
		return placeCharacter(p, destination)
	end
	if kind == "openworld" and PlaceRouter.ZoneAvailable(p, kind) then
		return moveHome(p)
	end
	return false, TEXT.zoneMissing
end

-- Studio-Simulation (auch nach einem fehlgeschlagenen Teleport): Modus wechseln, Figur versetzen, Hinweis senden.
function PlaceRouter.Simulate(p: any, kind: string, data: GoData?): (boolean, GoResult | string)
	if not PlaceRouter.IsMode(kind) then
		return false, TEXT.unknown
	end
	if not p or not p.profile or type(p.profile.data) ~= "table" then
		return false, TEXT.unknown
	end
	if not PlaceRouter.ZoneAvailable(p, kind) then
		toast(p, TEXT.zoneMissing)
		return false, TEXT.zoneMissing
	end
	data = type(data) == "table" and data or {}
	local d = p.profile.data
	p.mode = kind
	if type(data.single) == "boolean" then
		p.single = data.single
	end
	MetaRules.SetMode(d, kind)
	local moved, msg = PlaceRouter.MoveToZone(p, kind)
	if not moved and msg and msg ~= TEXT.noCharacter then
		-- Zone vorhanden, aber Figur nicht versetzbar: Modus gilt trotzdem (LobbyService.OnCharacter holt es nach)
		toast(p, msg)
	end
	emit(p, "mini_notice", { kind = "mode", mode = kind, simulated = true, single = p.single == true, moved = moved == true, party = data.party or "" })
	return true, { mode = kind, teleported = false, simulated = true, placeId = 0 }
end

---------------------------------------------------------------- Teleport
local function teleport(p: any, kind: string, placeId: number, data: GoData)
	local options = Instance.new("TeleportOptions")
	if data.single == true then
		-- Einzelspieler: eigener reservierter Server (ReserveServer liefert den Zugangscode)
		local code = TeleportService:ReserveServer(placeId)
		options.ReservedServerAccessCode = code
	end
	options:SetTeleportData({
		mode = kind,
		single = data.single == true,
		party = type(data.party) == "string" and string.sub(data.party, 1, GameConfig.TeleportDataMaxLength) or "",
	})
	local players = {}
	local seen = {}
	for _, pl in ipairs(type(data.players) == "table" and data.players or {}) do
		if typeof(pl) == "Instance" and pl:IsA("Player") and pl.Parent and not seen[pl] then
			seen[pl] = true
			table.insert(players, pl)
		end
	end
	if not seen[p.player] and p.player.Parent then
		table.insert(players, 1, p.player)
	end
	if #players == 0 then
		error("keine Spieler für den Teleport")
	end
	return TeleportService:TeleportAsync(placeId, players, options)
end

-- Reise (Vertrag §1). Rückgabe: ok, result (GoResult) bzw. ok = false, Hinweistext.
function PlaceRouter.Go(p: any, kind: string, data: GoData?): (boolean, GoResult | string)
	if not PlaceRouter.IsMode(kind) then
		return false, TEXT.unknown
	end
	if not p or not p.player or not p.profile then
		return false, TEXT.unknown
	end
	data = type(data) == "table" and data or {}
	local attempted = false
	if PlaceRouter.WouldTeleport(kind) then
		local placeId = PlaceRouter.PlaceId(kind)
		attempted = true
		-- Der gewählte Modus gilt am Ziel als letzter Modus (Profil wird beim Verlassen gespeichert). Er wird VOR dem
		-- Aufruf gemerkt: TeleportInitFailed kann noch innerhalb von TeleportAsync feuern und setzt ihn dann zurück
		-- bzw. auf das Ziel der Simulation – ein SetMode danach überschriebe diese Korrektur.
		MetaRules.SetMode(p.profile.data, kind)
		local ok, err = pcall(teleport, p, kind, placeId, data)
		if ok then
			return true, { mode = kind, teleported = true, simulated = false, placeId = placeId }
		end
		warn("[Ortswechsel] Teleport nach " .. kind .. " (" .. tostring(placeId) .. "): " .. tostring(err))
		toast(p, TEXT.teleportFailed)
	end
	local okS, res = PlaceRouter.Simulate(p, kind, data)
	if not okS and attempted then
		MetaRules.SetMode(p.profile.data, p.mode) -- Reise ist nicht zustande gekommen: letzter Modus = hier
	end
	return okS, res
end

return PlaceRouter
