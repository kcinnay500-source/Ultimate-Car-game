-- ArcadeUI: Tab "arcade" (Spielhalle). Automatenauswahl, Anleitung und die 2D-Oberflächen der 8 Automaten.
-- Der Client zeigt nur an und sendet Absichten: mini_arcade_start {game}, mini_arcade_input {token, at, value}
-- (at = workspace:GetServerTimeNow() im Moment der Eingabe), mini_arcade_finish {token}. Punkte und Credits
-- bestimmt allein der Server (ArcadeService). Für eine flüssige Anzeige rechnet der Client mit denselben reinen
-- Regeln (ArcadeRules) vor; lehnt der Server eine Eingabe ab (mini_notice "arcade_step" mit reject), wird der
-- lokale Zustand ohne diese Eingabe neu aufgebaut. MOTOR-OHR kennt die Lösung nicht und wartet auf den Server.
--
-- Schnittstelle (MiniClient): Build(page, ctx), Render(snapshot), OnShow(), OnNotice(data) für die Hinweise
-- "arcade_round", "arcade_step", "arcade_result", Select(gameKeyOrName) (Station eines Automaten), IsPlaying().
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local ArcadeRules = require(Mini:WaitForChild("ArcadeRules"))
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local ArcadeUI = {}

local ACTION = "UCG_ArcadeControls"
local PRIORITY = 3500 -- über Figur/Kamera (2000) und der 2.4.0-Werkzeugleiste (3000), unter Tab (10000)
local FINISH_RETRY = 4 -- Sekunden ohne Ergebnis, dann Abrechnung erneut anfragen (wiederholt, der Server zahlt je Token nur einmal)
local FINISH_GIVEUP = 15 -- Sekunden ohne Ergebnis, dann zurück zur Übersicht (die Nachfrage läuft im Hintergrund weiter)
local FINISH_STOP = 30 -- Sekunden ohne Ergebnis, dann endet auch die Nachfrage (ungültiges Token: Server antwortet nur per Toast)
local START_GAP = 2.5

local UI, Remote, Toast
local page
local refs = {}
local views = {}
local arcadeSnap = nil
local mode = "lobby"
local selected = nil
local cur = nil
local conn = nil
local bound = false
local startSentAt = -math.huge
local releaseConn = nil

-- Spielhallen-Farben (CITY_SPEC D3: Nachtlila, Magenta, Violett, Cyan)
local N = {
	night = Color3.fromRGB(35, 22, 50),
	deep = Color3.fromRGB(20, 12, 32),
	screen = Color3.fromRGB(14, 10, 24),
	magenta = Color3.fromRGB(255, 64, 180),
	violet = Color3.fromRGB(150, 80, 255),
	cyan = Color3.fromRGB(60, 220, 255),
	amber = Color3.fromRGB(235, 184, 72),
	green = Color3.fromRGB(50, 192, 137),
	red = Color3.fromRGB(230, 60, 80),
	white = Color3.fromRGB(235, 243, 250),
	soft = Color3.fromRGB(190, 176, 215),
	dim = Color3.fromRGB(90, 76, 118),
	asphalt = Color3.fromRGB(52, 54, 62),
	steel = Color3.fromRGB(150, 158, 170),
	blue = Color3.fromRGB(59, 134, 218),
}

---------------------------------------------------------------- Bausteine
local function make(class, props, parent)
	local x = Instance.new(class)
	for k, v in pairs(props or {}) do
		x[k] = v
	end
	if parent then
		x.Parent = parent
	end
	return x
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = N.night
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function text(parent, str, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = N.white
	l.TextSize = 16
	l.TextWrapped = true
	l.Text = str or ""
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function corner(obj, px)
	return make("UICorner", { CornerRadius = UDim.new(0, px or 8) }, obj)
end

local function circle(obj)
	return make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, obj)
end

-- Rahmen um die Fläche (Border), nicht um den Text
local function stroke(obj, color, thickness, transparency)
	return make("UIStroke", {
		Color = color, Thickness = thickness or 2, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, obj)
end

local function maxText(label, size)
	make("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = 8 }, label)
end

local function tween(obj, time, goals, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end

local function defColor(def)
	return Color3.fromRGB(def.color[1], def.color[2], def.color[3])
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function fmt(n, places)
	return ArcadeRules.Format(n, places)
end

local function num(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v or nil
end

-- Großer Knopf für die Spielsteuerung: reagiert sofort beim Drücken (MouseButton1Down, auch bei Touch)
local function padButton(parent, label, color, onDown, onUp, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Text = label
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 22
	b.TextColor3 = N.white
	b.Size = UDim2.new(1, 0, 1, 0)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 10)
	stroke(b, N.white, 2, 0.65)
	local scale = make("UIScale", { Scale = 1 }, b)
	b.MouseButton1Down:Connect(function()
		scale.Scale = 0.92
		tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		if onDown then
			onDown()
		end
	end)
	if onUp then
		b.MouseButton1Up:Connect(onUp)
	end
	b.Parent = parent
	return b
end

---------------------------------------------------------------- Effekte im Bildschirm
local function pop(str, color, x, y, size)
	if not refs.fx then
		return
	end
	x, y = x or 0.5, y or 0.42
	local l = text(refs.fx, str, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.new(0.9, 0, 0, (size or 26) + 10),
		TextSize = size or 26, Font = Enum.Font.GothamBlack, TextColor3 = color or N.white,
		TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.new(0, 0, 0), ZIndex = 30,
	})
	local s = make("UIScale", { Scale = 0.5 }, l)
	tween(s, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(l, 1.0, { Position = UDim2.fromScale(x, y - 0.14), TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(1.05, function()
		l:Destroy()
	end)
end

local function flash(color, strength)
	local f = refs.flash
	if not f then
		return
	end
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (strength or 0.45)
	f.Visible = true
	tween(f, 0.4, { BackgroundTransparency = 1 })
end

local function shake()
	local s = refs.shaker
	if not s then
		return
	end
	s.Position = UDim2.new(0, 9, 0, -3)
	tween(s, 0.35, { Position = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Elastic)
end

local function hint(str, color)
	if refs.hint then
		refs.hint.Text = str or ""
		refs.hint.TextColor3 = color or N.soft
	end
end

---------------------------------------------------------------- Runde: Eingaben und lokaler Zustand
-- Sendet eine Eingabe mit dem Zeitstempel at (Serverzeit). Rückgabe: at, rid oder nil (außerhalb der Runde)
local function sendInput(value, at)
	if not cur or cur.finishing or cur.result then
		return nil
	end
	at = at or serverNow()
	if at < cur.startAt or at > cur.endAt then
		return nil
	end
	local rid = Remote.Send("mini_arcade_input", { token = cur.token, at = at, value = value })
	cur.lastSend = at
	return at, rid
end

-- Eingabe auf den lokalen Zustand anwenden (gleiche Regeln wie der Server)
local function applyLocal(t, v, rid)
	local K = ArcadeRules.Kinds[cur.kind]
	table.insert(cur.inputs, { t = t, v = v, rid = rid })
	return K.input(cur.p, cur.st, t, v, nil)
end

-- Vom Server abgelehnte Eingabe entfernen und den lokalen Zustand neu aufbauen
local function rebuildLocal(dropRid)
	local K = ArcadeRules.Kinds[cur.kind]
	local keep = {}
	for _, e in ipairs(cur.inputs) do
		if e.rid ~= dropRid then
			table.insert(keep, e)
		end
	end
	cur.inputs = keep
	cur.st = K.new(cur.p)
	for _, e in ipairs(keep) do
		K.input(cur.p, cur.st, e.t, e.v, nil)
	end
	-- BLITZ-REAKTION: bereits bestätigte Server-Bewertungen behalten
	if cur.serverRes and cur.st.res then
		for i, res in pairs(cur.serverRes) do
			cur.st.res[i] = res
		end
	end
end

local finishRound -- vorwärts

---------------------------------------------------------------- BLITZ-REAKTION
local LAMP_OFF = Color3.fromRGB(58, 22, 30)
local LAMP_ON = Color3.fromRGB(255, 42, 62)

local function makeReaction(host, controlsHost)
	local v = {}
	local root = frame(host, { Name = "Reaktion", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.root = root
	local gantry = frame(root, { Name = "Ampelbruecke", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.08), Size = UDim2.fromScale(0.9, 0.32), BackgroundColor3 = Color3.fromRGB(16, 13, 22) })
	corner(gantry, 12)
	local gantryStroke = stroke(gantry, N.dim, 2, 0.1)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.025, 0), SortOrder = Enum.SortOrder.LayoutOrder,
	}, gantry)
	local lamps = {}
	for i = 1, 5 do
		local lamp = frame(gantry, { Name = "Lampe" .. i, Size = UDim2.fromScale(0.15, 0.78), BackgroundColor3 = LAMP_OFF, LayoutOrder = i })
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, lamp)
		circle(lamp)
		lamps[i] = { f = lamp, glow = stroke(lamp, LAMP_ON, 4, 1), on = false }
	end
	local big = text(root, "", { Name = "Anzeige", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(0.92, 0.2), TextScaled = true, Font = Enum.Font.GothamBlack })
	maxText(big, 46)
	local sub = text(root, "", { Name = "Info", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromScale(0.92, 0.1), TextScaled = true, Font = Enum.Font.Gotham, TextColor3 = N.soft })
	maxText(sub, 16)
	local dotsRow = frame(root, { Name = "Starts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.96), Size = UDim2.fromScale(0.9, 0.13) })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder }, dotsRow)
	local dots = {}
	for i = 1, 5 do
		local d = text(dotsRow, "–", { Size = UDim2.fromScale(0.17, 1), BackgroundTransparency = 0, BackgroundColor3 = N.deep, TextScaled = true, LayoutOrder = i, TextColor3 = N.soft })
		maxText(d, 16)
		corner(d, 6)
		dots[i] = d
	end

	local ctl = frame(controlsHost, { Name = "Reaktion", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.controls = ctl
	v.button = padButton(ctl, "START!", N.magenta, function()
		v.input("press", true)
	end, nil, { Name = "Druecken" })

	local shownAttempt, goFlash, missed = nil, {}, {}

	local function setLamps(count)
		for i, lamp in ipairs(lamps) do
			local on = i <= count
			if lamp.on ~= on then
				lamp.on = on
				lamp.f.BackgroundColor3 = on and LAMP_ON or LAMP_OFF
				lamp.glow.Transparency = on and 0.35 or 1
			end
		end
	end

	local function refreshDots()
		for i, d in ipairs(dots) do
			local res = cur.st.res[i]
			if res and res.early then
				d.Text, d.TextColor3 = "FRÜH", N.red
			elseif res then
				d.Text, d.TextColor3 = tostring(res.points), res.points >= 150 and N.green or N.amber
			elseif missed[i] then
				d.Text, d.TextColor3 = "0", N.red
			else
				d.Text, d.TextColor3 = "–", N.soft
			end
		end
	end

	function v.start()
		shownAttempt, goFlash, missed = nil, {}, {}
		setLamps(0)
		big.Text = "Gleich geht's los"
		big.TextColor3 = N.white
		sub.Text = "Drücke, sobald alle Lampen ausgehen."
		gantryStroke.Color = N.dim
		refreshDots()
	end

	-- Die Ausgeh-Zeitpunkte g kennt der Client erst durch "arcade_go" (Server sendet sie im Moment selbst).
	-- Bis dahin bleiben nach dem Aufleuchten alle Lampen an.
	function v.frame(t)
		local p = cur.p
		local idx, a
		for i, at in ipairs(p.attempts) do
			if t >= at.l or i == 1 then
				idx, a = i, at
			end
		end
		if not a or (a.g and t > a.g + p.window and idx == #p.attempts) then
			setLamps(0)
			if not a then
				return
			end
		end
		if t >= a.l and shownAttempt ~= idx then
			shownAttempt = idx
			big.Text = "Achtung …"
			big.TextColor3 = N.white
			sub.Text = "Start " .. idx .. " von " .. #p.attempts
			gantryStroke.Color = N.dim
		end
		local count = 0
		if t >= a.l and (a.g == nil or t < a.g) then
			count = math.min(p.lights, math.floor((t - a.l) / p.lightStep) + 1)
		end
		setLamps(count)
		if a.g and t >= a.g and not goFlash[idx] then
			goFlash[idx] = true
			gantryStroke.Color = N.green
		end
		-- Fenster vorbei ohne Druck: verpasst
		for i, at in ipairs(p.attempts) do
			if not missed[i] and not cur.st.res[i] and at.g and t > at.g + p.window then
				missed[i] = true
				big.Text = "Verpasst!"
				big.TextColor3 = N.red
				refreshDots()
			end
		end
	end

	function v.input(action, down)
		if action ~= "press" or not down then
			return
		end
		local at0 = serverNow()
		local i = ArcadeRules.ReactionAttempt(cur.p, at0 - cur.startAt)
		if not i or cur.st.res[i] then
			return -- zwischen den Starts oder schon gedrückt
		end
		local at, rid = sendInput(1, at0)
		if not at then
			return
		end
		local _, info = applyLocal(at - cur.startAt, 1, rid)
		if not info then
			return
		end
		if info.early then
			big.Text = "FRÜHSTART!"
			big.TextColor3 = N.red
			flash(N.red)
			shake()
		else
			big.Text = fmt(info.reaction, 3) .. " s"
			big.TextColor3 = info.points >= 150 and N.green or (info.points > 0 and N.amber or N.red)
			pop("+" .. info.points, N.cyan, 0.5, 0.45)
			if info.points >= 190 then
				flash(N.green, 0.25)
			end
		end
		refreshDots()
	end

	-- Bewertung des Servers (arcade_step) übernehmen: sie gilt, auch wenn "arcade_go" beim Drücken noch unterwegs war
	function v.step(info)
		local i = num(info.attempt)
		if not i or not cur.p.attempts[i] then
			return
		end
		local res = info.early and { early = true, points = 0 } or { r = num(info.reaction) or 0, points = num(info.points) or 0 }
		cur.serverRes = cur.serverRes or {}
		cur.serverRes[i] = res
		local before = cur.st.res[i]
		cur.st.res[i] = res
		if not before or before.early ~= res.early or before.points ~= res.points then
			if res.early then
				big.Text = "FRÜHSTART!"
				big.TextColor3 = N.red
			else
				big.Text = fmt(res.r, 3) .. " s"
				big.TextColor3 = res.points >= 150 and N.green or (res.points > 0 and N.amber or N.red)
			end
		end
		refreshDots()
	end

	function v.resync()
		refreshDots()
	end

	function v.score()
		local s = 0
		for _, res in pairs(cur.st.res) do
			s += res.points
		end
		return "Punkte: " .. s
	end

	return v
end

---------------------------------------------------------------- BREMSWEG-PROFI
local function makeBrake(host, controlsHost)
	local v = {}
	local root = frame(host, { Name = "Bremsweg", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.root = root
	local sky = frame(root, { Name = "Himmel", Size = UDim2.fromScale(1, 0.4), BackgroundColor3 = Color3.new(1, 1, 1) })
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(40, 30, 80), Color3.fromRGB(90, 60, 130)), Rotation = 90 }, sky)
	local info = text(root, "", { Name = "Info", Position = UDim2.fromScale(0.03, 0.03), Size = UDim2.fromScale(0.94, 0.14), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(info, 18)
	local dist = text(root, "", { Name = "Bremsweg", Position = UDim2.fromScale(0.03, 0.18), Size = UDim2.fromScale(0.94, 0.14), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, TextColor3 = N.cyan })
	maxText(dist, 22)
	local road = frame(root, { Name = "Strasse", Position = UDim2.fromScale(0, 0.42), Size = UDim2.fromScale(1, 0.3), BackgroundColor3 = N.asphalt })
	frame(road, { Name = "Rand", Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = N.white })
	frame(road, { Name = "Rand2", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = N.white })
	local line = frame(road, { Name = "Haltelinie", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = N.white, ZIndex = 2 })
	for i = 0, 3 do
		frame(line, { Size = UDim2.fromScale(1, 0.125), Position = UDim2.fromScale(0, i * 0.25), BackgroundColor3 = N.red, ZIndex = 2 })
	end
	local posts = {}
	for i = 1, 16 do
		local post = frame(root, { Name = "Pfosten" .. i, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(0, 4, 0.07, 0), BackgroundColor3 = N.white, Visible = false })
		frame(post, { Size = UDim2.new(1, 0, 0.35, 0), BackgroundColor3 = Color3.fromRGB(20, 20, 20) })
		local lbl = text(post, "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.new(0, 40, 0, 14), TextSize = 12, TextColor3 = N.soft })
		posts[i] = { f = post, l = lbl }
	end
	local car = frame(road, { Name = "Auto", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(0.06, 0.5), BackgroundColor3 = N.cyan, ZIndex = 3 })
	corner(car, 6)
	frame(car, { Name = "Scheibe", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.78, 0.5), Size = UDim2.fromScale(0.2, 0.8), BackgroundColor3 = Color3.fromRGB(30, 40, 60), ZIndex = 4 })
	local brakeL = frame(car, { Name = "Bremslicht", Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(0.08, 0.8), BackgroundColor3 = N.red, ZIndex = 4, Visible = false })
	local verdict = text(root, "", { Name = "Ergebnis", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.75), Size = UDim2.fromScale(0.94, 0.13), TextScaled = true, Font = Enum.Font.GothamBlack })
	maxText(verdict, 24)
	local runsLbl = text(root, "", { Name = "Anfahrten", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.99), Size = UDim2.fromScale(0.94, 0.1), TextScaled = true, Font = Enum.Font.Gotham, TextColor3 = N.soft })
	maxText(runsLbl, 14)

	local ctl = frame(controlsHost, { Name = "Bremsweg", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.controls = ctl
	padButton(ctl, "BREMSEN!", Color3.fromRGB(200, 50, 70), function()
		v.input("press", true)
	end, nil, { Name = "Bremsen" })

	local runIndex, span, missed = nil, 50, {}

	local function runsText()
		local parts = {}
		for i = 1, #cur.p.runs do
			local res = cur.st.res[i]
			parts[i] = res and tostring(res.points) or (missed[i] and "0" or "–")
		end
		runsLbl.Text = "Anfahrten: " .. table.concat(parts, " · ")
	end

	local function setupRun(i)
		runIndex = i
		local run = cur.p.runs[i]
		local cond = ArcadeRules.Brake.conditions[run.cond]
		span = run.line + 12
		info.Text = string.format("Anfahrt %d/%d · %d km/h · %s", i, #cur.p.runs, run.kmh, cond and cond.name or "")
		dist.Text = "Bremsweg ca. " .. run.dist .. " m"
		line.Position = UDim2.fromScale(run.line / span, 0)
		car.Size = UDim2.fromScale(4.5 / span, 0.5)
		local k = 0
		for d = 10, math.floor(run.line), 10 do
			k += 1
			local post = posts[k]
			if not post then
				break
			end
			post.f.Visible = true
			post.f.Position = UDim2.fromScale((run.line - d) / span, 0.42)
			post.l.Text = d .. " m"
		end
		for j = k + 1, #posts do
			posts[j].f.Visible = false
		end
		verdict.Text = ""
		brakeL.Visible = false
		runsText()
	end

	function v.start()
		runIndex, missed = nil, {}
		setupRun(1)
		verdict.Text = "Bremse genau dort, wo der Bremsweg beginnt."
		verdict.TextColor3 = N.soft
	end

	function v.frame(t)
		local runs = cur.p.runs
		local i = 1
		for j, run in ipairs(runs) do
			if t >= run.at then
				i = j
			end
		end
		if i ~= runIndex then
			setupRun(i)
		end
		local run = runs[i]
		local res = cur.st.res[i]
		local rt = math.max(0, t - run.at)
		local pos = ArcadeRules.BrakePosition(run, res and res.tb or nil, rt)
		car.Position = UDim2.fromScale(math.clamp(pos / span, 0, 1.2), 0.5)
		brakeL.Visible = res ~= nil and rt >= res.tb
		if not res and not missed[i] and t > run.at + run.pass then
			missed[i] = true
			verdict.Text = "Nicht gebremst!"
			verdict.TextColor3 = N.red
			runsText()
		end
	end

	local function showVerdict(run, err, points)
		local e = err / (run.kmh / 3.6)
		if math.abs(e) <= ArcadeRules.Brake.perfect then
			verdict.Text = "PERFEKT! " .. fmt(math.abs(err), 1) .. " m"
			verdict.TextColor3 = N.green
			flash(N.green, 0.25)
		elseif err < 0 then
			verdict.Text = fmt(-err, 1) .. " m vor der Linie"
			verdict.TextColor3 = N.amber
		else
			verdict.Text = fmt(err, 1) .. " m über die Linie!"
			verdict.TextColor3 = N.red
			flash(N.red)
			shake()
		end
		pop("+" .. points, N.cyan, 0.5, 0.36)
	end

	function v.input(action, down)
		if action ~= "press" or not down then
			return
		end
		local at0 = serverNow()
		local i, run = ArcadeRules.BrakeRun(cur.p, at0 - cur.startAt)
		if not i or cur.st.res[i] then
			return
		end
		local at, rid = sendInput(1, at0)
		if not at then
			return
		end
		local _, res = applyLocal(at - cur.startAt, 1, rid)
		if res then
			showVerdict(run, res.err, res.points)
			runsText()
		end
	end

	function v.resync()
		runsText()
	end

	function v.score()
		local s = 0
		for _, res in pairs(cur.st.res) do
			s += res.points
		end
		return "Punkte: " .. s
	end

	return v
end

---------------------------------------------------------------- BOXENSTOPP
local function makePitstop(host, controlsHost)
	local v = {}
	local root = frame(host, { Name = "Boxenstopp", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.root = root
	local wheel = frame(root, { Name = "Rad", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.03, 0.5), Size = UDim2.fromScale(0.56, 0.92), BackgroundColor3 = Color3.fromRGB(22, 22, 26) })
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, wheel)
	circle(wheel)
	stroke(wheel, Color3.fromRGB(70, 70, 78), 3, 0)
	local wheelScale = make("UIScale", { Scale = 1 }, wheel)
	local rim = frame(wheel, { Name = "Felge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.74, 0.74), BackgroundColor3 = Color3.fromRGB(120, 128, 140) })
	circle(rim)
	for s = 0, 4 do
		local spoke = frame(rim, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.1, 0.95), BackgroundColor3 = Color3.fromRGB(95, 102, 114), Rotation = s * 36 })
		corner(spoke, 4)
	end
	local hub = frame(wheel, { Name = "Nabe", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.26, 0.26), BackgroundColor3 = Color3.fromRGB(60, 64, 72), ZIndex = 2 })
	circle(hub)
	local nuts = {}
	for pos = 1, 5 do
		local a = math.rad(-90 + (pos - 1) * 72)
		local b = Instance.new("TextButton")
		b.Name = "Mutter" .. pos
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(0.5 + 0.3 * math.cos(a), 0.5 + 0.3 * math.sin(a))
		b.Size = UDim2.fromScale(0.2, 0.2)
		b.BackgroundColor3 = N.steel
		b.Text = ""
		b.Font = Enum.Font.GothamBlack
		b.TextScaled = true
		b.TextColor3 = Color3.fromRGB(20, 20, 26)
		b.ZIndex = 3
		circle(b)
		local st = stroke(b, Color3.fromRGB(40, 40, 46), 3, 0)
		maxText(b, 26)
		local sc = make("UIScale", { Scale = 1 }, b)
		b.MouseButton1Down:Connect(function()
			v.tap(pos)
		end)
		b.Parent = wheel
		nuts[pos] = { b = b, stroke = st, scale = sc }
	end
	local side = frame(root, { Name = "Info", BackgroundTransparency = 1, Position = UDim2.fromScale(0.62, 0.06), Size = UDim2.fromScale(0.36, 0.88) })
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	local wheelName = text(side, "", { Size = UDim2.new(1, 0, 0.18, 0), TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = N.amber, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(wheelName, 20)
	local rule = text(side, "", { Size = UDim2.new(1, 0, 0.3, 0), TextScaled = true, Font = Enum.Font.Gotham, TextColor3 = N.soft, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	maxText(rule, 15)
	local progress = text(side, "", { Size = UDim2.new(1, 0, 0.14, 0), TextScaled = true, LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(progress, 17)
	local mistakes = text(side, "", { Size = UDim2.new(1, 0, 0.14, 0), TextScaled = true, LayoutOrder = 4, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(mistakes, 17)
	local clock = text(side, "", { Size = UDim2.new(1, 0, 0.18, 0), TextScaled = true, Font = Enum.Font.GothamBlack, LayoutOrder = 5, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = N.cyan })
	maxText(clock, 26)

	local ctl = frame(controlsHost, { Name = "Boxenstopp", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	text(ctl, "Tippe die Radmuttern im Rad an.", { Size = UDim2.fromScale(1, 1), TextColor3 = N.soft, Font = Enum.Font.Gotham, TextSize = 15 })
	v.controls = ctl

	local shownWheel, rimAngle = nil, 0

	local function orderOf(w, pos)
		for n = 0, 4 do
			if ArcadeRules.NutAt(w.start, n, w.dir) == pos then
				return n + 1
			end
		end
		return nil
	end

	local function refresh()
		local st, p = cur.st, cur.p
		local wIndex = math.min(st.w, #p.wheels)
		local w = p.wheels[wIndex]
		if shownWheel ~= wIndex then
			shownWheel = wIndex
			wheelScale.Scale = 0.75
			tween(wheelScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		wheelName.Text = "Rad " .. wIndex .. "/" .. #p.wheels .. " · " .. w.name
		rule.Text = w.numbered and "Nach Nummern anziehen." or "Profi: ab der 1 über Kreuz – immer eine Mutter überspringen!"
		for pos, nut in ipairs(nuts) do
			local tight = st.tight[wIndex * 10 + pos] == true
			if w.numbered then
				nut.b.Text = tostring(orderOf(w, pos) or "")
			else
				nut.b.Text = pos == w.start and "1" or ""
			end
			nut.b.BackgroundColor3 = tight and N.green or N.steel
			nut.stroke.Color = tight and Color3.fromRGB(20, 110, 70) or Color3.fromRGB(40, 40, 46)
		end
		progress.Text = "Muttern: " .. st.done .. "/" .. (#p.wheels * p.nuts)
		mistakes.Text = "Fehler: " .. st.mistakes .. (st.mistakes > 0 and (" (+" .. st.mistakes * p.penalty .. " s)") or "")
		mistakes.TextColor3 = st.mistakes > 0 and N.red or N.white
	end

	function v.start()
		shownWheel, rimAngle = nil, 0
		rim.Rotation = 0
		refresh()
	end

	function v.frame(t)
		local st = cur.st
		local shown = st.finish or math.max(0, t)
		clock.Text = fmt(shown, 1) .. " s"
		clock.TextColor3 = st.finish and N.green or (cur.p.limit - t < 6 and N.red or N.cyan)
	end

	function v.tap(pos)
		if not cur or cur.kind ~= "pitstop" then
			return
		end
		local st = cur.st
		local t0 = serverNow() - cur.startAt
		if st.finish or t0 < st.ready or t0 < 0 then
			return
		end
		local at, rid = sendInput(pos)
		if not at then
			return
		end
		local ok, info = applyLocal(at - cur.startAt, pos, rid)
		local nut = nuts[pos]
		if ok and info then
			if info.ok then
				nut.scale.Scale = 1.25
				tween(nut.scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
				rimAngle += 72
				tween(rim, 0.15, { Rotation = rimAngle })
				if info.finished then
					pop("FERTIG!", N.green, 0.3, 0.45, 34)
					flash(N.green, 0.3)
				elseif info.wheelDone then
					pop("Rad fertig!", N.green, 0.3, 0.45)
				end
			else
				nut.b.BackgroundColor3 = N.red
				pop("+" .. cur.p.penalty .. " s", N.red, 0.3, 0.4)
				flash(N.red, 0.3)
				shake()
			end
		end
		refresh()
	end

	function v.input() end

	function v.resync()
		refresh()
	end

	function v.done()
		return cur.st.finish ~= nil
	end

	function v.score()
		return "Muttern: " .. cur.st.done .. "/20"
	end

	return v
end

---------------------------------------------------------------- DREHMOMENT
local function makeTorque(host, controlsHost)
	local v = {}
	local COLS, DOTS, SPAN = 40, 36, 5
	local root = frame(host, { Name = "Drehmoment", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.root = root
	local chart = frame(root, { Name = "Schreiber", Position = UDim2.fromScale(0.03, 0.14), Size = UDim2.fromScale(0.72, 0.8), BackgroundColor3 = Color3.fromRGB(12, 16, 22), ClipsDescendants = true })
	corner(chart, 8)
	stroke(chart, N.dim, 1.5, 0.2)
	for _, y in ipairs({ 0.25, 0.5, 0.75 }) do
		frame(chart, { Position = UDim2.fromScale(0, y), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = N.dim, BackgroundTransparency = 0.6 })
	end
	local red = frame(chart, { Name = "Rot", Size = UDim2.fromScale(1, 1 - ArcadeRules.Torque.red / ArcadeRules.Torque.max), BackgroundColor3 = N.red, BackgroundTransparency = 0.7, ZIndex = 2 })
	text(red, "ÜBERDREHT", { Size = UDim2.fromScale(1, 1), TextScaled = true, TextColor3 = N.red, ZIndex = 2, TextTransparency = 0.3 })
	local cols = {}
	for j = 1, COLS do
		cols[j] = frame(chart, { Name = "Band" .. j, BackgroundColor3 = N.green, BackgroundTransparency = 0.5, Size = UDim2.fromScale(1 / COLS, 0.1), ZIndex = 3 })
	end
	frame(chart, { Name = "Jetzt", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = N.white, BackgroundTransparency = 0.3, ZIndex = 4 })
	local dots = {}
	for k = 1, DOTS do
		local d = frame(chart, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 5, 0, 5), BackgroundColor3 = N.cyan, ZIndex = 5, Visible = false })
		circle(d)
		dots[k] = d
	end
	local marker = frame(chart, { Name = "Marke", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0, 12, 0, 12), BackgroundColor3 = N.white, ZIndex = 6 })
	circle(marker)
	local gauge = frame(root, { Name = "Anzeige", Position = UDim2.fromScale(0.79, 0.14), Size = UDim2.fromScale(0.18, 0.66), BackgroundColor3 = Color3.fromRGB(12, 16, 22) })
	corner(gauge, 8)
	stroke(gauge, N.dim, 1.5, 0.2)
	local fill = frame(gauge, { Name = "Fuellung", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = N.amber })
	corner(fill, 8)
	local value = text(root, "0 Nm", { Name = "Wert", Position = UDim2.fromScale(0.77, 0.82), Size = UDim2.fromScale(0.22, 0.12), TextScaled = true, Font = Enum.Font.GothamBlack })
	maxText(value, 20)
	local status = text(root, "", { Name = "Status", Position = UDim2.fromScale(0.03, 0.02), Size = UDim2.fromScale(0.94, 0.1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(status, 17)

	local ctl = frame(controlsHost, { Name = "Drehmoment", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.controls = ctl
	local pointerHold = false
	local btn = padButton(ctl, "ANZIEHEN (halten)", N.violet, function()
		pointerHold = true
		v.input("press", true)
	end, function()
		pointerHold = false
		v.input("press", false)
	end, { Name = "Anziehen" })
	btn.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			pointerHold = true
			v.input("press", true)
		end
	end)
	v.button = btn

	local nextEval, lastPct = 0, 0

	local function watchRelease()
		if releaseConn then
			return
		end
		-- Loslassen außerhalb des Knopfs (Finger rutscht ab) zählt auch
		releaseConn = UserInputService.InputEnded:Connect(function(io)
			if pointerHold and (io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1) then
				pointerHold = false
				v.input("press", false)
			end
		end)
	end

	function v.start()
		nextEval, lastPct = 0, 0
		pointerHold = false
		status.Text = "Halte das Drehmoment im grünen Bereich."
		status.TextColor3 = N.soft
		watchRelease()
	end

	function v.frame(t)
		local p = cur.p
		local events = cur.st.events
		local tau = ArcadeRules.TorqueAt(p, events, math.max(0, t))
		for j, col in ipairs(cols) do
			local tj = t - SPAN / 2 + (j - 0.5) * SPAN / COLS
			if tj < 0 or tj > cur.duration then
				col.Visible = false
			else
				local c, half = ArcadeRules.TorqueBand(p, tj)
				col.Visible = true
				col.Position = UDim2.fromScale((j - 1) / COLS, 1 - (c + half) / p.max)
				col.Size = UDim2.fromScale(1 / COLS + 0.002, 2 * half / p.max)
				col.BackgroundTransparency = tj > t and 0.72 or 0.45
			end
		end
		for k, d in ipairs(dots) do
			local tk = t - (k - 1) * (SPAN / 2) / DOTS
			if tk < 0 then
				d.Visible = false
			else
				d.Visible = true
				d.Position = UDim2.fromScale(0.5 - (t - tk) / SPAN, 1 - ArcadeRules.TorqueAt(p, events, tk) / p.max)
			end
		end
		marker.Position = UDim2.fromScale(0.5, 1 - tau / p.max)
		local c, half = ArcadeRules.TorqueBand(p, math.max(0, t))
		local inBand = math.abs(tau - c) <= half
		local col = tau > p.red and N.red or (inBand and N.green or N.amber)
		fill.Size = UDim2.fromScale(1, tau / p.max)
		fill.BackgroundColor3 = col
		marker.BackgroundColor3 = col
		value.Text = math.floor(tau * p.display + 0.5) .. " Nm"
		value.TextColor3 = col
		if t >= 0 and os.clock() >= nextEval then
			nextEval = os.clock() + 0.25
			local inTime = ArcadeRules.TorqueEval(p, events, t)
			lastPct = math.floor(100 * inTime / math.max(1, math.min(t, cur.duration)) + 0.5)
			status.Text = (inBand and "Im Bereich" or (tau > p.red and "Überdreht!" or (tau < c and "Mehr Kraft!" or "Nachlassen!"))) .. " · bisher " .. lastPct .. " % im Soll"
			status.TextColor3 = col
		end
	end

	function v.input(action, down)
		if action ~= "press" or not cur or cur.kind ~= "torque" then
			return
		end
		if down == cur.st.hold then
			return
		end
		local at, rid = sendInput(down and 1 or 0)
		if not at then
			return
		end
		applyLocal(at - cur.startAt, down and 1 or 0, rid)
		btn.BackgroundColor3 = down and N.magenta or N.violet
	end

	function v.stop()
		pointerHold = false
		btn.BackgroundColor3 = N.violet
	end

	function v.resync() end

	function v.score()
		return "Im Soll: " .. lastPct .. " %"
	end

	return v
end

---------------------------------------------------------------- MOTOR-OHR
local function makeEngine(host, controlsHost)
	local v = {}
	local BARS = 32
	local root = frame(host, { Name = "MotorOhr", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.root = root
	local head = text(root, "", { Name = "Frage", Position = UDim2.fromScale(0.03, 0.02), Size = UDim2.fromScale(0.94, 0.09), TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = N.green, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(head, 17)
	local body = text(root, "", { Name = "Beschreibung", Position = UDim2.fromScale(0.03, 0.11), Size = UDim2.fromScale(0.94, 0.15), TextScaled = true, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	maxText(body, 15)
	local timerBack = frame(root, { Position = UDim2.fromScale(0.03, 0.27), Size = UDim2.new(0.94, 0, 0, 4), BackgroundColor3 = N.deep })
	local timerFill = frame(timerBack, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = N.green })
	local options = {}
	for k = 1, 4 do
		local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
		local b = Instance.new("TextButton")
		b.Name = "Motor" .. k
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.Text = ""
		b.BackgroundColor3 = Color3.fromRGB(10, 26, 22)
		b.Position = UDim2.fromScale(0.03 + col * 0.48, 0.31 + row * 0.345)
		b.Size = UDim2.fromScale(0.46, 0.32)
		corner(b, 8)
		local st = stroke(b, Color3.fromRGB(40, 90, 70), 2, 0)
		text(b, "Motor " .. string.char(64 + k), { Position = UDim2.fromScale(0.04, 0.02), Size = UDim2.fromScale(0.6, 0.24), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = N.green })
		local scope = frame(b, { Name = "Oszilloskop", BackgroundTransparency = 1, Position = UDim2.fromScale(0.04, 0.28), Size = UDim2.fromScale(0.92, 0.66), ClipsDescendants = true })
		frame(scope, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = N.green, BackgroundTransparency = 0.6 })
		local bars = {}
		for j = 1, BARS do
			bars[j] = frame(scope, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale((j - 1) / BARS, 1), Size = UDim2.fromScale(0.7 / BARS, 0.1), BackgroundColor3 = Color3.fromRGB(90, 255, 180) })
		end
		b.MouseButton1Down:Connect(function()
			v.choose(k)
		end)
		b.Parent = root
		options[k] = { b = b, stroke = st, bars = bars, wave = "" }
	end
	local feedback = text(root, "", { Name = "Rueckmeldung", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.64), Size = UDim2.fromScale(0.9, 0.14), TextScaled = true, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.3, ZIndex = 5 })
	maxText(feedback, 28)

	local ctl = frame(controlsHost, { Name = "MotorOhr", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	text(ctl, "Tippe auf den Motor, der zur Beschreibung passt.", { Size = UDim2.fromScale(1, 1), TextColor3 = N.soft, Font = Enum.Font.Gotham, TextSize = 15 })
	v.controls = ctl

	local q, qAt, answered, timeoutSent, shownQ, points, finished, waitUntil

	local function paintOptions(correct, wrong)
		for k, o in ipairs(options) do
			if k == correct then
				o.stroke.Color, o.stroke.Thickness = N.green, 4
			elseif k == wrong then
				o.stroke.Color, o.stroke.Thickness = N.red, 4
			else
				o.stroke.Color, o.stroke.Thickness = Color3.fromRGB(40, 90, 70), 2
			end
		end
	end

	local function showQuestion(index)
		shownQ = index
		local question = cur.p.questions[index]
		head.Text = "Diagnose " .. index .. " von " .. #cur.p.questions .. " · " .. question.title
		body.Text = question.text
		for k, o in ipairs(options) do
			o.wave = question.waves[k] or ""
		end
		paintOptions(nil, nil)
		feedback.Text = ""
	end

	function v.start()
		q, qAt, answered, timeoutSent, shownQ, points, finished, waitUntil = 1, 0, false, false, nil, 0, false, nil
		showQuestion(1)
	end

	local function advanceLocal(nextAt)
		q += 1
		qAt = nextAt
		answered = false
		timeoutSent = false
		waitUntil = nil
		if q > #cur.p.questions then
			finished = true
		end
	end

	function v.frame(t)
		local n = #cur.p.questions
		local offset = math.floor(math.max(0, t) * 14)
		for _, o in ipairs(options) do
			local w = o.wave
			if #w > 0 then
				for j, bar in ipairs(o.bars) do
					local idx = (offset + j - 1) % #w + 1
					local val = tonumber(string.sub(w, idx, idx)) or 0
					bar.Size = UDim2.fromScale(0.7 / BARS, math.max(0.03, val / 9 * 0.95))
				end
			end
		end
		if finished or q > n then
			return
		end
		if t >= qAt and shownQ ~= q then
			showQuestion(q)
		end
		local left = qAt + cur.p.limit - t
		timerFill.Size = UDim2.fromScale(math.clamp(left / cur.p.limit, 0, 1), 1)
		timerFill.BackgroundColor3 = left < 2 and N.red or N.green
		if not answered and left < -0.02 and not timeoutSent then
			-- Zeit abgelaufen: Server lösen lassen (er zeigt die richtige Antwort)
			timeoutSent = true
			answered = true
			sendInput(0)
			feedback.Text = "Zeit abgelaufen!"
			feedback.TextColor3 = N.red
			waitUntil = t + 2
		end
		if waitUntil and t > waitUntil then
			-- keine Antwort vom Server: lokal weiter (Frage zählt als verpasst)
			advanceLocal(qAt + cur.p.limit + cur.p.pause)
		end
	end

	function v.choose(k)
		if not cur or cur.kind ~= "engine" or answered or finished then
			return
		end
		local t = serverNow() - cur.startAt
		if t < qAt or t > qAt + cur.p.limit then
			return
		end
		local at = sendInput(k)
		if not at then
			return
		end
		answered = true
		waitUntil = t + 2.5
		options[k].stroke.Color, options[k].stroke.Thickness = N.white, 4
		feedback.Text = "…"
		feedback.TextColor3 = N.white
	end

	function v.step(data)
		local dq = num(data.q)
		if not dq or dq < q then
			return
		end
		local letter = data.answer and string.char(64 + data.answer) or "?"
		if data.timeout then
			feedback.Text = "Zeit abgelaufen – es war Motor " .. letter
			feedback.TextColor3 = N.red
			paintOptions(data.answer, nil)
		elseif data.correct then
			feedback.Text = "Richtig!"
			feedback.TextColor3 = N.green
			paintOptions(data.answer, nil)
			pop("+" .. (data.points or 0), N.green, 0.5, 0.5)
		else
			feedback.Text = "Falsch – es war Motor " .. letter
			feedback.TextColor3 = N.red
			paintOptions(data.answer, data.choice)
			shake()
		end
		points += num(data.points) or 0
		q = dq
		advanceLocal(num(data.nextAt) or (qAt + cur.p.limit + cur.p.pause))
		if data.done then
			finished = true
		end
	end

	function v.input() end

	function v.resync() end

	function v.reject()
		-- Antwort nicht gewertet (z. B. Verbindung): Frage bleibt offen, solange Zeit ist
		answered = false
		waitUntil = nil
		feedback.Text = ""
	end

	function v.done()
		return finished
	end

	function v.score()
		return "Punkte: " .. points
	end

	return v
end

---------------------------------------------------------------- EINPARK-PROFI
local CAR_COLORS = {
	Color3.fromRGB(79, 132, 215), Color3.fromRGB(192, 62, 77), Color3.fromRGB(176, 190, 198), Color3.fromRGB(106, 150, 93),
	Color3.fromRGB(117, 82, 177), Color3.fromRGB(236, 238, 240), Color3.fromRGB(28, 30, 34),
}
local ARROW = { "▲", "▶", "▼", "◀" }

local function makePark(host, controlsHost)
	local v = {}
	local W, H = ArcadeRules.Park.w, ArcadeRules.Park.h
	local root = frame(host, { Name = "Einparken", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.root = root
	local lot = frame(root, { Name = "Parkplatz", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.02, 0.5), Size = UDim2.fromScale(0.7, 0.94), BackgroundColor3 = N.asphalt })
	make("UIAspectRatioConstraint", { AspectRatio = W / H }, lot)
	corner(lot, 6)
	local cells = {}
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local bay = y == 0 or y == H - 1
			local c = frame(lot, {
				Name = "Feld" .. x .. "_" .. y, Position = UDim2.fromScale(x / W, y / H), Size = UDim2.fromScale(1 / W, 1 / H),
				BackgroundColor3 = bay and Color3.fromRGB(60, 62, 72) or N.asphalt, BackgroundTransparency = 0,
			})
			if bay then
				frame(c, { Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = N.white })
				frame(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = N.white })
			end
			local car = frame(c, { Name = "Auto", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.84), Visible = false, ZIndex = 2 })
			corner(car, 5)
			frame(car, { Position = UDim2.fromScale(0.12, 0.2), Size = UDim2.fromScale(0.76, 0.22), BackgroundColor3 = Color3.fromRGB(30, 40, 60), ZIndex = 2 })
			local cone = frame(c, { Name = "Kegel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.42), BackgroundColor3 = Color3.fromRGB(255, 140, 30), Visible = false, ZIndex = 2 })
			circle(cone)
			local ring = frame(cone, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = N.white, ZIndex = 2 })
			circle(ring)
			cells[y * W + x + 1] = { f = c, car = car, cone = cone }
		end
	end
	local target = frame(lot, { Name = "Ziel", BackgroundColor3 = N.green, BackgroundTransparency = 0.6, Size = UDim2.fromScale(1 / W, 1 / H), ZIndex = 3 })
	local targetStroke = stroke(target, N.green, 3, 0)
	local targetArrow = text(target, "", { Size = UDim2.fromScale(1, 0.6), TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = N.white, ZIndex = 3 })
	local targetMode = text(target, "", { Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.35), TextScaled = true, TextColor3 = N.white, ZIndex = 3 })
	local me = frame(lot, { Name = "MeinAuto", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.62 / W, 0.84 / H), BackgroundColor3 = N.amber, ZIndex = 5 })
	corner(me, 5)
	stroke(me, Color3.fromRGB(120, 80, 10), 2, 0)
	frame(me, { Name = "Scheibe", Position = UDim2.fromScale(0.12, 0.16), Size = UDim2.fromScale(0.76, 0.22), BackgroundColor3 = Color3.fromRGB(30, 40, 60), ZIndex = 5 })
	frame(me, { Name = "RueckL", Position = UDim2.fromScale(0.08, 0.9), Size = UDim2.fromScale(0.22, 0.08), BackgroundColor3 = N.red, ZIndex = 5 })
	frame(me, { Name = "RueckR", Position = UDim2.fromScale(0.7, 0.9), Size = UDim2.fromScale(0.22, 0.08), BackgroundColor3 = N.red, ZIndex = 5 })
	local side = frame(root, { Name = "Info", BackgroundTransparency = 1, Position = UDim2.fromScale(0.74, 0.05), Size = UDim2.fromScale(0.25, 0.9) })
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	local taskLbl = text(side, "", { Size = UDim2.new(1, 0, 0.14, 0), TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = N.cyan, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(taskLbl, 18)
	local modeLbl = text(side, "", { Size = UDim2.new(1, 0, 0.2, 0), TextScaled = true, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(modeLbl, 16)
	local movesLbl = text(side, "", { Size = UDim2.new(1, 0, 0.2, 0), TextScaled = true, Font = Enum.Font.Gotham, LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(movesLbl, 15)
	local bumpLbl = text(side, "", { Size = UDim2.new(1, 0, 0.12, 0), TextScaled = true, Font = Enum.Font.Gotham, LayoutOrder = 4, TextXAlignment = Enum.TextXAlignment.Left })
	maxText(bumpLbl, 15)

	local ctl = frame(controlsHost, { Name = "Einparken", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.controls = ctl
	local order = { 4, 1, 3, 2 } -- ◀ ▲ ▼ ▶
	for i, d in ipairs(order) do
		padButton(ctl, ARROW[d], N.blue, function()
			v.move(d)
		end, nil, { Name = "Pfeil" .. d, Size = UDim2.new(0.25, -6, 1, 0), Position = UDim2.new((i - 1) * 0.25, 3, 0, 0), TextSize = 26 })
	end

	local shownTask, angle, parkedWait = nil, 0, false

	local function rotationFor(h)
		return (h - 1) * 90
	end

	local function placeCar(x, y, h, animate)
		local goal = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H)
		local want = rotationFor(h)
		local delta = ((want - angle) % 360 + 540) % 360 - 180
		angle += delta
		if animate then
			tween(me, 0.12, { Position = goal, Rotation = angle })
		else
			me.Position = goal
			me.Rotation = angle
		end
	end

	local function loadTask(i)
		shownTask = i
		parkedWait = false
		local task = cur.p.tasks[i]
		if not task then
			return
		end
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local cell = cells[y * W + x + 1]
				local ch = string.sub(task.grid, y * W + x + 1, y * W + x + 1)
				cell.car.Visible = ch == "c"
				cell.cone.Visible = ch == "k"
				if ch == "c" then
					cell.car.BackgroundColor3 = CAR_COLORS[(x * 3 + y * 5 + i) % #CAR_COLORS + 1]
					cell.car.Rotation = y == 0 and 0 or 180
				end
			end
		end
		target.Position = UDim2.fromScale(task.tx / W, task.ty / H)
		targetArrow.Text = ARROW[task.th]
		targetMode.Text = task.mode == "forward" and "VORWÄRTS" or "RÜCKWÄRTS"
		angle = rotationFor(task.sh)
		placeCar(task.sx, task.sy, task.sh, false)
		taskLbl.Text = "Aufgabe " .. i .. "/" .. #cur.p.tasks
		modeLbl.Text = task.mode == "forward" and "Vorwärts in die grüne Lücke" or "Rückwärts in die grüne Lücke"
		modeLbl.TextColor3 = task.mode == "forward" and N.green or N.amber
	end

	local function refreshInfo()
		local st = cur.st
		local task = cur.p.tasks[math.min(st.i, #cur.p.tasks)]
		if st.i <= #cur.p.tasks and shownTask == st.i then
			movesLbl.Text = "Züge: " .. st.moves .. " (bestmöglich " .. task.par .. ")"
			bumpLbl.Text = "Blechschaden: " .. st.bumps
			bumpLbl.TextColor3 = st.bumps > 0 and N.red or N.soft
		end
	end

	function v.start()
		shownTask, parkedWait = nil, false
		loadTask(1)
		refreshInfo()
	end

	function v.frame(t)
		local st = cur.st
		if shownTask ~= st.i and st.i <= #cur.p.tasks and t >= st.taskAt then
			loadTask(st.i)
			refreshInfo()
		end
		targetStroke.Transparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(os.clock() * 6))
	end

	function v.move(d)
		if not cur or cur.kind ~= "park" then
			return
		end
		local st = cur.st
		local t0 = serverNow() - cur.startAt
		if st.i > #cur.p.tasks or t0 < st.taskAt or t0 - st.last < ArcadeRules.Park.minGap or parkedWait then
			return
		end
		local at, rid = sendInput(d)
		if not at then
			return
		end
		local ok, info = applyLocal(at - cur.startAt, d, rid)
		if not ok or not info then
			return
		end
		if info.bump then
			flash(N.red, 0.3)
			shake()
			pop("Rums!", N.red, 0.36, 0.45)
		else
			placeCar(info.x, info.y, info.h, true)
			if info.parked then
				parkedWait = true
				pop("Eingeparkt! +" .. (info.points or 0), N.green, 0.36, 0.45, 28)
				flash(N.green, 0.25)
				movesLbl.Text = "Geschafft in " .. (cur.st.res[info.task] and cur.st.res[info.task].moves or 0) .. " Zügen"
				bumpLbl.Text = ""
				return
			end
		end
		refreshInfo()
	end

	function v.input(action, down)
		if not down then
			return
		end
		local d = action == "up" and 1 or action == "right" and 2 or action == "down" and 3 or action == "left" and 4 or nil
		if d then
			v.move(d)
		end
	end

	function v.resync()
		local st = cur.st
		if st.i <= #cur.p.tasks then
			if shownTask ~= st.i then
				loadTask(st.i)
			end
			placeCar(st.x, st.y, st.h, false)
			parkedWait = false
		end
		refreshInfo()
	end

	function v.done()
		return cur.st.i > #cur.p.tasks
	end

	function v.score()
		local s = 0
		for _, res in pairs(cur.st.res) do
			s += res.points
		end
		return "Punkte: " .. math.floor(s + 1e-6)
	end

	return v
end

---------------------------------------------------------------- RENNSIMULATOR 1/2
local function makeRace(host, controlsHost)
	local v = {}
	local POOL, SPEED, CAR_Y, AHEAD, BEHIND = 48, 0.36, 0.82, 2.4, 0.4
	local root = frame(host, { Name = "Rennen", Size = UDim2.fromScale(1, 1), Visible = false, BackgroundColor3 = Color3.fromRGB(60, 120, 70) })
	v.root = root
	-- Fahrbahn im festen Seitenverhältnis (Handy quer: sonst flache, breite Autos)
	local road = frame(root, { Name = "Fahrbahn", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.62, 1), BackgroundColor3 = N.asphalt, ClipsDescendants = true })
	make("UIAspectRatioConstraint", { AspectRatio = 0.8, AspectType = Enum.AspectType.FitWithinMaxSize }, road)
	local kerbL = frame(road, { Name = "RandL", Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = N.white, ZIndex = 2 })
	local kerbR = frame(road, { Name = "RandR", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = N.white, ZIndex = 2 })
	local dividers = {}
	for i = 1, 3 do
		local col = {}
		for j = 1, 8 do
			col[j] = frame(road, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 4, 0.07, 0), BackgroundColor3 = N.white, Visible = false })
		end
		dividers[i] = col
	end
	local items = {}
	for i = 1, POOL do
		local f = frame(road, { Name = "Objekt" .. i, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = 2 })
		local a = frame(f, { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
		local ac = corner(a, 6)
		local b = frame(f, { ZIndex = 3 })
		local c = frame(f, { ZIndex = 3 })
		items[i] = { f = f, a = a, ac = ac, b = b, c = c, key = nil }
	end
	local beam = frame(road, { Name = "Licht", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(255, 240, 180), BackgroundTransparency = 0.2, ZIndex = 3, Visible = false })
	make("UIGradient", { Transparency = NumberSequence.new(0.35, 1), Rotation = -90 }, beam)
	local car = frame(road, { Name = "MeinAuto", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = N.magenta, ZIndex = 4 })
	corner(car, 7)
	stroke(car, N.white, 2, 0.4)
	frame(car, { Position = UDim2.fromScale(0.14, 0.18), Size = UDim2.fromScale(0.72, 0.22), BackgroundColor3 = Color3.fromRGB(30, 40, 60), ZIndex = 4 })
	frame(car, { Position = UDim2.fromScale(0.14, 0.62), Size = UDim2.fromScale(0.72, 0.14), BackgroundColor3 = Color3.fromRGB(30, 40, 60), ZIndex = 4 })
	local livesRow = frame(root, { Name = "Leben", BackgroundTransparency = 1, Position = UDim2.fromScale(0.02, 0.03), Size = UDim2.fromScale(0.15, 0.08) })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, livesRow)
	local hearts = {}
	for i = 1, 3 do
		local h = frame(livesRow, { Size = UDim2.fromScale(0.28, 1), BackgroundColor3 = N.red, LayoutOrder = i })
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, h)
		circle(h)
		stroke(h, N.white, 1.5, 0.3)
		hearts[i] = h
	end
	local stat = text(root, "", { Name = "Stand", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.98, 0.03), Size = UDim2.fromScale(0.17, 0.16), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack })
	maxText(stat, 16)

	local ctl = frame(controlsHost, { Name = "Rennen", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	v.controls = ctl
	padButton(ctl, "◀", N.violet, function()
		v.input("left", true)
	end, nil, { Name = "Links", Size = UDim2.new(0.5, -5, 1, 0), TextSize = 30 })
	padButton(ctl, "▶", N.violet, function()
		v.input("right", true)
	end, nil, { Name = "Rechts", Size = UDim2.new(0.5, -5, 1, 0), Position = UDim2.new(0.5, 5, 0, 0), TextSize = 30 })

	local lanes, taken, firstRow, lastBeat, night = 3, {}, 1, 0, false

	local function laneX(l)
		return (l - 0.5) / lanes
	end

	local function style(item, obj, k, l)
		local a, b, c = item.a, item.b, item.c
		item.f.Size = UDim2.fromScale(0.62 / lanes, 0.13)
		a.Visible, b.Visible, c.Visible = true, false, false
		a.Rotation = 0
		if obj == "1" then
			local barrier = (k * 7 + l * 3) % 5 == 0
			if barrier then
				a.BackgroundColor3 = Color3.fromRGB(255, 140, 30)
				a.Size = UDim2.fromScale(1, 0.45)
				a.Position = UDim2.fromScale(0, 0.3)
				item.ac.CornerRadius = UDim.new(0, 3)
				b.Visible = true
				b.BackgroundColor3 = N.white
				b.Position = UDim2.fromScale(0.2, 0.3)
				b.Size = UDim2.fromScale(0.18, 0.45)
				c.Visible = true
				c.BackgroundColor3 = N.white
				c.Position = UDim2.fromScale(0.62, 0.3)
				c.Size = UDim2.fromScale(0.18, 0.45)
			else
				a.BackgroundColor3 = CAR_COLORS[(k * 5 + l) % #CAR_COLORS + 1]
				a.Size = UDim2.fromScale(0.78, 1)
				a.Position = UDim2.fromScale(0.11, 0)
				item.ac.CornerRadius = UDim.new(0, 6)
				b.Visible = true
				b.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
				b.Position = UDim2.fromScale(0.2, 0.6)
				b.Size = UDim2.fromScale(0.6, 0.2)
				c.Visible = night
				c.BackgroundColor3 = N.red
				c.Position = UDim2.fromScale(0.15, 0.05)
				c.Size = UDim2.fromScale(0.7, 0.08)
			end
		elseif obj == "2" then
			-- Pokal: Schale, Fuß, Sockel
			a.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
			a.Size = UDim2.fromScale(0.4, 0.5)
			a.Position = UDim2.fromScale(0.3, 0.1)
			item.ac.CornerRadius = UDim.new(0.5, 0)
			b.Visible = true
			b.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
			b.Position = UDim2.fromScale(0.46, 0.55)
			b.Size = UDim2.fromScale(0.08, 0.2)
			c.Visible = true
			c.BackgroundColor3 = Color3.fromRGB(220, 160, 40)
			c.Position = UDim2.fromScale(0.34, 0.72)
			c.Size = UDim2.fromScale(0.32, 0.1)
		else
			a.BackgroundColor3 = Color3.fromRGB(12, 10, 16)
			a.Size = UDim2.fromScale(0.8, 0.6)
			a.Position = UDim2.fromScale(0.1, 0.2)
			item.ac.CornerRadius = UDim.new(0.5, 0)
			a.Rotation = 8
			b.Visible = true
			b.BackgroundColor3 = Color3.fromRGB(110, 60, 160)
			b.Position = UDim2.fromScale(0.3, 0.35)
			b.Size = UDim2.fromScale(0.2, 0.12)
		end
	end

	local function refreshLives()
		for i, h in ipairs(hearts) do
			h.BackgroundColor3 = i <= cur.st.lives and N.red or N.dim
		end
	end

	local function effect(e)
		if e.kind == "crash" then
			flash(N.red, 0.5)
			shake()
			pop("Rums! -1 Leben", N.red, 0.5, 0.55)
			refreshLives()
		elseif e.kind == "dead" then
			flash(N.red, 0.7)
			shake()
			pop("TOTALSCHADEN!", N.red, 0.5, 0.45, 34)
			refreshLives()
		elseif e.kind == "pick" then
			taken[e.row] = true
			pop("+" .. cur.p.pickPts, N.amber, 0.5, 0.62, 22)
		elseif e.kind == "oil" then
			pop("Rutschig!", N.violet, 0.5, 0.6, 22)
			tween(car, 0.3, { Rotation = 18 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.delay(0.3, function()
				tween(car, 0.3, { Rotation = 0 })
			end)
		end
	end

	function v.start()
		local p = cur.p
		lanes = p.lanes
		taken, firstRow, lastBeat = {}, 1, 0
		night = p.theme == "night"
		root.BackgroundColor3 = night and Color3.fromRGB(10, 10, 24) or Color3.fromRGB(60, 120, 70)
		road.BackgroundColor3 = night and Color3.fromRGB(26, 26, 38) or N.asphalt
		kerbL.BackgroundColor3 = night and N.cyan or N.white
		kerbR.BackgroundColor3 = night and N.magenta or N.white
		for i, col in ipairs(dividers) do
			for _, dash in ipairs(col) do
				dash.Visible = i < lanes
				dash.BackgroundColor3 = night and N.violet or N.white
			end
		end
		for _, item in ipairs(items) do
			item.f.Visible = false
			item.key = nil
		end
		car.Size = UDim2.fromScale(0.6 / lanes, 0.15)
		car.Position = UDim2.fromScale(laneX(cur.st.lane), CAR_Y)
		car.Rotation = 0
		beam.Visible = night
		beam.Size = UDim2.fromScale(0.5 / lanes, 0.35)
		refreshLives()
	end

	function v.frame(t)
		local p, st = cur.p, cur.st
		if t >= 0 and not cur.finishing then
			local evs = ArcadeRules.RaceAdvance(p, st, t, false)
			if evs then
				for _, e in ipairs(evs) do
					effect(e)
				end
			end
			-- Takt: aktuelle Spur alle 0,5 s melden (der Server prüft sie gegen sein Modell)
			if not st.dead and t - lastBeat >= 0.5 and serverNow() - (cur.lastSend or -math.huge) >= 0.25 then
				lastBeat = t
				local at, rid = sendInput(st.lane)
				if at then
					applyLocal(at - cur.startAt, st.lane, rid)
				end
			end
		end
		local scroll = (math.max(0, t) * SPEED) % 0.25
		for i, col in ipairs(dividers) do
			if i < lanes then
				for j, dash in ipairs(col) do
					dash.Position = UDim2.fromScale(i / lanes, (j - 1) * 0.25 - 0.25 + scroll)
				end
			end
		end
		while p.times[firstRow] and p.times[firstRow] < t - BEHIND do
			firstRow += 1
		end
		local used = 0
		local k = firstRow
		while p.times[k] and p.times[k] - t <= AHEAD do
			local row = p.rows[k]
			local y = CAR_Y - (p.times[k] - t) * SPEED
			for l = 1, lanes do
				local obj = string.sub(row, l, l)
				if obj ~= "0" and not (obj == "2" and taken[k]) and used < POOL then
					used += 1
					local item = items[used]
					local key = k * 10 + l
					if item.key ~= key then
						item.key = key
						style(item, obj, k, l)
					end
					item.f.Position = UDim2.fromScale(laneX(l), y)
					item.f.Visible = true
				end
			end
			k += 1
		end
		for i = used + 1, POOL do
			if items[i].f.Visible then
				items[i].f.Visible = false
				items[i].key = nil
			end
		end
		local blink = t < st.invuln and math.floor(t * 10) % 2 == 0
		car.BackgroundTransparency = blink and 0.6 or 0
		beam.Position = UDim2.fromScale(car.Position.X.Scale, CAR_Y - 0.07)
		stat.Text = "Reihen " .. st.passed .. "\nPokale " .. st.picks
	end

	function v.input(action, down)
		if not down or not cur or cur.kind ~= "race" then
			return
		end
		local dir = action == "left" and -1 or action == "right" and 1 or nil
		if not dir then
			return
		end
		local p, st = cur.p, cur.st
		local at0 = serverNow()
		local t = at0 - cur.startAt
		if t < 0 or cur.finishing then
			return
		end
		local evs = ArcadeRules.RaceAdvance(p, st, t, false)
		if evs then
			for _, e in ipairs(evs) do
				effect(e)
			end
		end
		local lane = st.lane + dir
		if st.dead or lane < 1 or lane > p.lanes then
			return
		end
		if t < st.slide then
			hint("Rutschig – kurz nicht lenkbar!", N.violet)
			return
		end
		if t - st.lastSwitch < p.minSwitch then
			return
		end
		local at, rid = sendInput(lane, at0)
		if not at then
			return
		end
		applyLocal(t, lane, rid)
		tween(car, 0.08, { Position = UDim2.fromScale(laneX(st.lane), CAR_Y) })
	end

	function v.resync()
		car.Position = UDim2.fromScale(laneX(cur.st.lane), CAR_Y)
		refreshLives()
	end

	function v.done()
		return cur.st.dead == true
	end

	function v.score()
		local p = cur.p
		return "Punkte: " .. (p.maxPoints > 0 and math.floor(1000 * cur.st.points / p.maxPoints + 1e-6) or 0)
	end

	return v
end

---------------------------------------------------------------- Ansichten verwalten
local BUILDERS = {
	reaction = makeReaction, brake = makeBrake, pitstop = makePitstop, torque = makeTorque,
	engine = makeEngine, park = makePark, race = makeRace,
}

local function getView(kind)
	local v = views[kind]
	if not v then
		v = BUILDERS[kind](refs.shaker, refs.controls)
		v.done = v.done or function()
			return false
		end
		v.step = v.step or function() end
		v.stop = v.stop or function() end
		v.reject = v.reject or function() end
		views[kind] = v
	end
	return v
end

---------------------------------------------------------------- Tastatur / Controller
local KEYMAP = {
	[Enum.KeyCode.Space] = "press", [Enum.KeyCode.ButtonA] = "press",
	[Enum.KeyCode.Left] = "left", [Enum.KeyCode.A] = "left", [Enum.KeyCode.DPadLeft] = "left",
	[Enum.KeyCode.Right] = "right", [Enum.KeyCode.D] = "right", [Enum.KeyCode.DPadRight] = "right",
	[Enum.KeyCode.Up] = "up", [Enum.KeyCode.W] = "up", [Enum.KeyCode.DPadUp] = "up",
	[Enum.KeyCode.Down] = "down", [Enum.KeyCode.S] = "down", [Enum.KeyCode.DPadDown] = "down",
}

local function onAction(_, state, input)
	local action = input and KEYMAP[input.KeyCode]
	-- Nach Rundenende (finishing/result) gehören die Tasten wieder der Figur (Laufen, Springen)
	if not action or not cur or not cur.view or cur.result or cur.finishing then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		cur.view.input(action, true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		cur.view.input(action, false)
	end
	return Enum.ContextActionResult.Sink
end

local function bindKeys()
	if bound then
		return
	end
	bound = true
	local keys = {}
	for key in pairs(KEYMAP) do
		table.insert(keys, key)
	end
	ContextActionService:BindActionAtPriority(ACTION, onAction, false, PRIORITY, table.unpack(keys))
end

local function unbindKeys()
	if bound then
		bound = false
		ContextActionService:UnbindAction(ACTION)
	end
end

---------------------------------------------------------------- Modus, Layout
local function pageShown()
	local x = page
	while x and x:IsA("GuiObject") do
		if not x.Visible then
			return false
		end
		x = x.Parent
	end
	if x and x:IsA("LayerCollector") then
		return x.Enabled
	end
	return x ~= nil
end

local function layout()
	if not refs.screen then
		return
	end
	local w = refs.play.AbsoluteSize.X
	if w <= 0 and page then
		w = page.AbsoluteSize.X
	end
	-- Titelzeile, Zeitbalken, Bildschirm und Steuerung sollen ohne Scrollen passen (Handy quer: ~320 px Inhalt)
	local h = w > 0 and w * 0.62 or 290
	local avail = UI.Content and UI.Content.AbsoluteSize.Y or 0
	if avail > 0 then
		h = math.min(h, avail - 150)
	end
	h = math.clamp(math.floor(h), 160, 420)
	refs.screen.Size = UDim2.new(1, 0, 0, h)
	local gw = refs.grid.AbsoluteSize.X
	if gw >= 640 then
		refs.gridLayout.CellSize = UDim2.new(0.25, -8, 0, 124)
	else
		refs.gridLayout.CellSize = UDim2.new(0.5, -5, 0, 118)
	end
end

local function setMode(m)
	mode = m
	refs.head.Visible = m == "lobby" or m == "intro"
	refs.lobby.Visible = m == "lobby"
	refs.intro.Visible = m == "intro"
	refs.play.Visible = m == "play" or m == "result"
	refs.controls.Visible = m == "play"
	refs.quit.Visible = m == "play"
	refs.hint.Visible = m == "play"
	if UI.Content then
		UI.Content.CanvasPosition = Vector2.new(0, 0)
	end
	layout()
end

local function capLeft()
	local a = arcadeSnap
	if type(a) ~= "table" then
		return ArcadeRules.DailyCap
	end
	return math.max(0, (num(a.cap) or ArcadeRules.DailyCap) - (num(a.earnedToday) or 0))
end

local function bestOf(key)
	local a = arcadeSnap
	return type(a) == "table" and type(a.best) == "table" and num(a.best[key]) or 0
end

local function renderIntro()
	local def = selected and ArcadeRules.GameByKey[selected]
	if not def then
		return
	end
	local col = defColor(def)
	refs.introStripe.BackgroundColor3 = col
	refs.introTitle.Text = def.name
	refs.introTitle.TextColor3 = col
	refs.introHow.Text = def.howto
	refs.introControls.Text = "Steuerung: " .. def.controls
	local best = bestOf(def.key)
	local left = capLeft()
	refs.introStats.Text = string.format(
		"Dein Rekord: %s · bis zu %s bei 1000 Punkten · %s",
		best > 0 and (best .. " Punkte") or "noch keiner", MiniLocale.Credits(def.reward),
		left > 0 and ("heute noch " .. MiniLocale.Credits(left) .. " möglich") or "Tageslimit erreicht: nur Übung und Rekorde"
	)
	local waiting = os.clock() - startSentAt < START_GAP
	refs.playBtn.Text = waiting and "Startet …" or "Spielen"
	UI.SetEnabled(refs.playBtn, not waiting, col)
end

local function renderHead()
	local a = arcadeSnap
	local cap = type(a) == "table" and num(a.cap) or ArcadeRules.DailyCap
	local earned = type(a) == "table" and num(a.earnedToday) or 0
	UI.SetProgress(refs.capFill, cap > 0 and earned / cap or 0)
	refs.capText.Text = "Heute verdient: " .. MiniLocale.Credits(earned) .. " von " .. MiniLocale.Credits(cap)
		.. (earned >= cap and " · Limit erreicht, Rekorde zählen weiter" or "")
	for key, tile in pairs(refs.tiles) do
		local best = bestOf(key)
		tile.best.Text = best > 0 and ("Rekord " .. best) or "Neu"
	end
end

---------------------------------------------------------------- Runde: Ablauf
local function disconnect()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if releaseConn then
		releaseConn:Disconnect()
		releaseConn = nil
	end
end

local function stopRound()
	unbindKeys()
	disconnect()
	if cur and cur.view then
		pcall(cur.view.stop)
	end
end

finishRound = function()
	if not cur or cur.finishing or cur.result then
		return
	end
	cur.finishing = true
	cur.finishAt = os.clock()
	cur.retryAt = cur.finishAt
	-- Tasten sofort freigeben: kommt die Auswertung nie an, bliebe die Figur sonst auf der Tastatur eingefroren
	unbindKeys()
	if cur.view then
		pcall(cur.view.stop)
	end
	Remote.Send("mini_arcade_finish", { token = cur.token })
	refs.count.Visible = true
	refs.count.Text = "Auswertung …"
	refs.countScale.Scale = 0.6
	hint("", nil)
end

local function onFrame()
	if not cur then
		disconnect()
		return
	end
	local now = serverNow()
	local t = now - cur.startAt
	if not cur.finishing and not pageShown() then
		-- Panel geschlossen oder anderer Tab: Runde endet mit dem bisher Erreichten
		finishRound()
	end
	if cur.finishing then
		if not cur.result then
			-- B-012: Bleibt das Ergebnis aus (Abrechnung verworfen), weiter nachfragen statt für immer „Auswertung …“
			local c = os.clock()
			local waited = c - cur.finishAt
			if waited > FINISH_STOP then
				disconnect()
				cur = nil
				return
			end
			if c - cur.retryAt > FINISH_RETRY then
				cur.retryAt = c
				Remote.Send("mini_arcade_finish", { token = cur.token })
			end
			if waited > FINISH_GIVEUP and not cur.gaveUp then
				cur.gaveUp = true
				refs.count.Visible = false
				if mode == "play" then
					setMode("lobby")
					renderHead()
				end
			end
		end
		return
	end
	-- Countdown 3-2-1-LOS
	if t < 0 then
		local n = math.ceil(-t - 1e-6)
		if cur.lastCount ~= n then
			cur.lastCount = n
			refs.count.Visible = true
			refs.count.Text = tostring(n)
			refs.count.TextColor3 = N.white
			refs.countScale.Scale = 1.6
			tween(refs.countScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	elseif not cur.goShown then
		cur.goShown = true
		refs.count.Text = "LOS!"
		refs.count.TextColor3 = defColor(cur.def)
		refs.countScale.Scale = 1.5
		tween(refs.countScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(0.6, function()
			if cur and cur.goShown and not cur.finishing then
				refs.count.Visible = false
			end
		end)
	end
	UI.SetProgress(refs.timeFill, math.clamp(t / cur.duration, 0, 1))
	local ok, err = pcall(cur.view.frame, t)
	if not ok then
		warn("[Spielhalle] Anzeige: " .. tostring(err))
	end
	refs.playScore.Text = cur.view.score()
	if t >= cur.duration or (t >= 0 and cur.view.done()) then
		finishRound()
	end
end

local function onRound(data)
	local def = ArcadeRules.GameByKey[data.game]
	if not def or type(data.params) ~= "table" or not num(data.token) or not num(data.startAt) then
		return
	end
	stopRound()
	local kind = data.gameKind or def.kind
	local K = ArcadeRules.Kinds[kind]
	if not K then
		return
	end
	cur = {
		token = data.token, key = def.key, def = def, kind = kind,
		startAt = data.startAt, endAt = num(data.endAt) or (data.startAt + (num(data.duration) or 60)),
		duration = num(data.duration) or 60, p = data.params,
		inputs = {}, finishing = false, result = nil, lastCount = nil, goShown = false,
	}
	if kind ~= "engine" then
		cur.st = K.new(cur.p)
	end
	selected = def.key
	startSentAt = -math.huge
	cur.view = getView(kind)
	for k, v in pairs(views) do
		v.root.Visible = k == kind
		v.controls.Visible = k == kind
	end
	refs.result.Visible = false
	refs.count.Visible = false
	refs.playTitle.Text = def.name
	refs.playTitle.TextColor3 = defColor(def)
	refs.screenStroke.Color = defColor(def)
	refs.timeFill.BackgroundColor3 = defColor(def)
	hint(num(data.capLeft) == 0 and "Tageslimit erreicht: Diese Runde zählt für deinen Rekord, bringt aber keine Credits." or def.controls, N.soft)
	setMode("play")
	cur.view.start() -- nach stopRound(): Ansichten dürfen hier eigene Verbindungen (releaseConn) anlegen
	bindKeys()
	conn = RunService.Heartbeat:Connect(onFrame)
	onFrame()
end

local function showResult(data)
	local def = ArcadeRules.GameByKey[data.game] or (cur and cur.def)
	local score = num(data.score) or 0
	refs.count.Visible = false
	refs.result.Visible = true
	refs.resScale.Scale = 0.85
	tween(refs.resScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	if data.expired then
		refs.resRating.Text = "Runde abgelaufen"
		refs.resRating.TextColor3 = N.red
	elseif data.abandoned then
		refs.resRating.Text = "Runde abgebrochen"
		refs.resRating.TextColor3 = N.red
	else
		refs.resRating.Text = type(data.rating) == "string" and data.rating or ArcadeRules.Rating(score)
		refs.resRating.TextColor3 = score >= 750 and N.green or (score >= 300 and N.amber or N.soft)
	end
	refs.resScore.Text = score .. " Punkte"
	refs.resBest.Visible = data.newBest == true
	local credits = num(data.credits) or 0
	if credits > 0 then
		refs.resCredits.Text = "+" .. MiniLocale.Credits(credits) .. (data.capped and " (Tageslimit erreicht)" or "")
		refs.resCredits.TextColor3 = N.amber
	elseif data.capped then
		refs.resCredits.Text = "Tageslimit erreicht – heute keine Credits mehr"
		refs.resCredits.TextColor3 = N.soft
	elseif score < ArcadeRules.MinRewardScore and not data.expired and not data.abandoned then
		refs.resCredits.Text = "Ab " .. ArcadeRules.MinRewardScore .. " Punkten gibt es Credits"
		refs.resCredits.TextColor3 = N.soft
	else
		refs.resCredits.Text = "Keine Credits"
		refs.resCredits.TextColor3 = N.soft
	end
	local detail = type(data.detail) == "string" and data.detail or ""
	if data.aborted then
		detail = (detail ~= "" and (detail .. " · ") or "") .. "vorzeitig beendet"
	end
	refs.resDetail.Text = detail
	if def then
		refs.again.Text = "Nochmal"
		UI.SetEnabled(refs.again, true, defColor(def))
	end
	if data.newBest then
		flash(N.amber, 0.35)
	end
end

local function onResult(data)
	-- Rekord und Tageszähler sofort übernehmen (der Snapshot folgt)
	if type(arcadeSnap) == "table" and not data.replay then
		arcadeSnap.best = type(arcadeSnap.best) == "table" and arcadeSnap.best or {}
		if data.newBest and data.game then
			arcadeSnap.best[data.game] = num(data.score) or 0
		end
		arcadeSnap.earnedToday = (num(arcadeSnap.earnedToday) or 0) + (num(data.credits) or 0)
	end
	if not cur or data.token ~= cur.token then
		return
	end
	if cur.result then
		return -- schon angezeigt (Wiederholung)
	end
	if cur.gaveUp then
		-- Die Übersicht ist längst wieder frei: Anzeige nicht umreißen, nur das Ergebnis melden
		cur = nil
		stopRound()
		renderHead()
		if (num(data.credits) or 0) > 0 then
			Toast("Spielhalle: " .. (num(data.score) or 0) .. " Punkte, +" .. MiniLocale.Credits(num(data.credits) or 0))
		end
		return
	end
	cur.result = data
	stopRound()
	setMode("result")
	showResult(data)
	renderHead()
	if not pageShown() and (num(data.credits) or 0) > 0 then
		Toast("Spielhalle: " .. (num(data.score) or 0) .. " Punkte, +" .. MiniLocale.Credits(num(data.credits) or 0))
	end
end

local REJECT_TEXT = {
	late = "Verbindung zu langsam – diese Eingabe wurde nicht gewertet.",
	early = "Uhrzeit weicht ab – diese Eingabe wurde nicht gewertet.",
	order = "Eingabe außer der Reihe – nicht gewertet.",
	limit = "Zu viele Eingaben – nicht gewertet.",
	invalid = "Ungültige Eingabe.",
}

local function onStep(data)
	if not cur or data.token ~= cur.token or cur.result then
		return
	end
	if data.reject then
		if cur.kind ~= "engine" then
			rebuildLocal(data.rid)
			pcall(cur.view.resync)
		else
			pcall(cur.view.reject, data)
		end
		if REJECT_TEXT[data.reject] then
			hint(REJECT_TEXT[data.reject], N.red)
		end
		return
	end
	if cur.kind == "engine" or (cur.kind == "reaction" and cur.view.step) then
		cur.view.step(data)
	end
end

-- BLITZ-REAKTION: Lampen aus (mini_notice "arcade_go" {token, attempt, g})
local function onGo(data)
	if not cur or data.token ~= cur.token or cur.kind ~= "reaction" or cur.result then
		return
	end
	local i, g = num(data.attempt), num(data.g)
	local a = i and cur.p.attempts and cur.p.attempts[i]
	if a and g then
		a.g = g
	end
end

local function startGame(key)
	local def = ArcadeRules.GameByKey[key]
	if not def or os.clock() - startSentAt < START_GAP then
		return
	end
	selected = key
	startSentAt = os.clock()
	Remote.Send("mini_arcade_start", { game = key })
	if mode == "intro" then
		renderIntro()
	elseif mode == "result" then
		refs.again.Text = "Startet …"
		UI.SetEnabled(refs.again, false)
	end
	task.delay(START_GAP + 0.1, function()
		if mode == "intro" then
			renderIntro()
		elseif mode == "result" and refs.again then
			refs.again.Text = "Nochmal"
			UI.SetEnabled(refs.again, true, def and defColor(def))
		end
	end)
end

local function backToLobby()
	if cur and not cur.result and not cur.finishing then
		finishRound()
	end
	stopRound()
	setMode("lobby")
	renderHead()
end

---------------------------------------------------------------- Aufbau
local function makeTile(parent, def, order)
	local col = defColor(def)
	local b = Instance.new("TextButton")
	b.Name = "Automat_" .. def.key
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.LayoutOrder = order
	corner(b, 10)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(48, 30, 70), N.deep), Rotation = 90 }, b)
	local st = stroke(b, col, 2, 0.15)
	local stripe = frame(b, { Size = UDim2.new(1, -16, 0, 4), Position = UDim2.new(0, 8, 0, 8), BackgroundColor3 = col })
	corner(stripe, 2)
	local name = text(b, def.name, {
		Font = Enum.Font.GothamBlack, TextColor3 = col, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 10, 0, 16), Size = UDim2.new(1, -20, 0, 22), TextWrapped = false,
	})
	maxText(name, 17)
	text(b, def.blurb, {
		Font = Enum.Font.Gotham, TextColor3 = N.soft, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.new(0, 10, 0, 40), Size = UDim2.new(1, -20, 1, -66),
	})
	local best = text(b, "Neu", {
		TextSize = 13, TextColor3 = N.cyan, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 10, 1, -24), Size = UDim2.new(0.55, -10, 0, 18),
	})
	text(b, "bis " .. def.reward .. " Cr", {
		TextSize = 13, TextColor3 = N.amber, TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.55, 0, 1, -24), Size = UDim2.new(0.45, -10, 0, 18),
	})
	local scale = make("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function()
		tween(st, 0.15, { Thickness = 3.5, Transparency = 0 })
	end)
	b.MouseLeave:Connect(function()
		tween(st, 0.15, { Thickness = 2, Transparency = 0.15 })
	end)
	b.Activated:Connect(function()
		scale.Scale = 0.95
		tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		ArcadeUI.Select(def.key)
	end)
	b.Parent = parent
	return { root = b, best = best, stroke = st }
end

function ArcadeUI.Build(pg, ctx)
	page = pg
	UI, Remote = ctx.UI, ctx.Remote
	Toast = ctx.Toast or function() end
	refs, views = {}, {}
	cur, mode, selected = nil, "lobby", nil
	local T = UI.Theme

	-- Kopf: Titel, Tageslimit
	local head = UI.Card(page, 1)
	head.Name = "Spielhalle"
	head.BackgroundColor3 = N.night
	stroke(head, N.violet, 1.5, 0.3)
	local title = UI.Title(head, "SPIELHALLE · Geschick statt Glück", 1)
	title.TextColor3 = N.magenta
	title.Font = UI.FontBig or Enum.Font.GothamBlack
	UI.Small(head, "Acht Automaten, nur Können zählt: Credits gibt es allein nach Punkten – ohne Einsatz, ohne Zufall. Pro Tag ist die Summe begrenzt, Rekorde zählen immer.", 2).TextColor3 = N.soft
	local _, capFill = UI.Progress(head, N.cyan, 3)
	refs.capFill = capFill
	refs.capText = UI.Small(head, "", 4)
	refs.head = head

	-- Automaten
	local lobby = UI.Card(page, 2)
	lobby.Name = "Automaten"
	lobby.BackgroundColor3 = N.deep
	UI.Title(lobby, "Automaten", 1).TextColor3 = N.cyan
	local grid = frame(lobby, { Name = "Raster", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	refs.gridLayout = make("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 118), CellPadding = UDim2.new(0, 10, 0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	refs.grid = grid
	refs.tiles = {}
	for i, def in ipairs(ArcadeRules.Games) do
		refs.tiles[def.key] = makeTile(grid, def, i)
	end
	refs.lobby = lobby

	-- Anleitung
	local intro = UI.Card(page, 3)
	intro.Name = "Anleitung"
	intro.BackgroundColor3 = N.night
	intro.Visible = false
	refs.introStripe = frame(intro, { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = N.magenta, LayoutOrder = 1 })
	refs.introTitle = UI.Title(intro, "", 2)
	refs.introTitle.Font = UI.FontBig or Enum.Font.GothamBlack
	refs.introHow = UI.Label(intro, "", { LayoutOrder = 3 })
	refs.introControls = UI.Small(intro, "", 4)
	refs.introStats = UI.Small(intro, "", 5)
	refs.introStats.TextColor3 = N.amber
	refs.playBtn = UI.Button(intro, "Spielen", N.magenta, function()
		startGame(selected)
	end, { Name = "Spielen", LayoutOrder = 6, TextSize = 18 })
	UI.Button(intro, "Zurück zur Übersicht", T.card, function()
		setMode("lobby")
		renderHead()
	end, { Name = "Zurueck", LayoutOrder = 7 })
	refs.intro = intro

	-- Spiel
	local play = UI.Card(page, 4)
	play.Name = "Automat"
	play.BackgroundColor3 = N.deep
	play.Visible = false
	local top = frame(play, { Name = "Kopf", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1 })
	refs.playTitle = text(top, "", { Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.6, 1), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	refs.playScore = text(top, "", { Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.6, 0), Size = UDim2.fromScale(0.4, 1), TextColor3 = N.amber, TextWrapped = false })
	local _, timeFill = UI.Progress(play, N.cyan, 2)
	refs.timeFill = timeFill
	local screen = frame(play, { Name = "Bildschirm", Size = UDim2.new(1, 0, 0, 290), BackgroundColor3 = N.screen, ClipsDescendants = true, LayoutOrder = 3 })
	corner(screen, 10)
	refs.screenStroke = stroke(screen, N.magenta, 2, 0.05)
	refs.screen = screen
	refs.shaker = frame(screen, { Name = "Inhalt", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	refs.fx = frame(screen, { Name = "Effekte", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20 })
	refs.flash = frame(screen, { Name = "Blitz", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 25, Visible = false })
	refs.count = text(screen, "", {
		Name = "Countdown", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.36),
		TextScaled = true, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.2, ZIndex = 40, Visible = false,
	})
	maxText(refs.count, 90)
	refs.countScale = make("UIScale", { Scale = 1 }, refs.count)

	-- Ergebnis über dem Bildschirm
	local res = frame(screen, { Name = "Ergebnis", Size = UDim2.fromScale(1, 1), BackgroundColor3 = N.deep, BackgroundTransparency = 0.08, ZIndex = 50, Visible = false })
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
	}, res)
	refs.resScale = make("UIScale", { Scale = 1 }, res)
	refs.resRating = text(res, "", { Font = Enum.Font.GothamBlack, TextSize = 26, Size = UDim2.new(1, -20, 0, 32), LayoutOrder = 1, ZIndex = 51 })
	refs.resScore = text(res, "", { Font = Enum.Font.GothamBlack, TextSize = 36, Size = UDim2.new(1, -20, 0, 42), LayoutOrder = 2, ZIndex = 51, TextColor3 = N.white })
	refs.resBest = text(res, "NEUER REKORD!", { Font = Enum.Font.GothamBlack, TextSize = 18, Size = UDim2.new(1, -20, 0, 22), LayoutOrder = 3, ZIndex = 51, TextColor3 = N.amber, Visible = false })
	refs.resCredits = text(res, "", { TextSize = 18, Size = UDim2.new(1, -20, 0, 24), LayoutOrder = 4, ZIndex = 51 })
	refs.resDetail = text(res, "", { Font = Enum.Font.Gotham, TextSize = 14, Size = UDim2.new(1, -24, 0, 36), LayoutOrder = 5, ZIndex = 51, TextColor3 = N.soft })
	local row = frame(res, { Name = "Knoepfe", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, UI.MinTouch or 44), LayoutOrder = 6, ZIndex = 51 })
	refs.again = UI.Button(row, "Nochmal", N.magenta, function()
		startGame(cur and cur.key or selected)
	end, { Name = "Nochmal", Size = UDim2.new(0.5, -5, 1, 0), ZIndex = 52 })
	UI.Button(row, "Übersicht", T.card, backToLobby, { Name = "Uebersicht", Size = UDim2.new(0.5, -5, 1, 0), Position = UDim2.new(0.5, 5, 0, 0), ZIndex = 52 })
	refs.result = res

	refs.controls = frame(play, { Name = "Steuerung", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 4 })
	refs.hint = UI.Small(play, "", 5)
	refs.quit = UI.Button(play, "Runde beenden", T.card, function()
		finishRound()
	end, { Name = "Beenden", LayoutOrder = 6 })
	refs.play = play

	page:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	if UI.Content then
		UI.Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	end
	setMode("lobby")
	renderHead()
end

---------------------------------------------------------------- Schnittstelle
function ArcadeUI.Render(s)
	if type(s) ~= "table" or not refs.head then
		return
	end
	if type(s.arcade) == "table" then
		arcadeSnap = s.arcade
	end
	renderHead()
	if mode == "intro" then
		renderIntro()
	end
end

function ArcadeUI.OnShow()
	layout()
	if mode == "lobby" then
		renderHead()
	end
end

-- Station eines Automaten (mini_open mit game = Schlüssel oder Anzeigename): Anleitung dieses Automaten zeigen
function ArcadeUI.Select(x)
	local def = ArcadeRules.Resolve(x)
	if not def or not refs.intro then
		return false
	end
	if cur and not cur.result and not cur.gaveUp then
		return false -- laufende Runde nicht unterbrechen
	end
	if not (cur and cur.gaveUp) then
		stopRound() -- nach der Aufgabe (gaveUp) läuft nur noch die Nachfrage – die bleibt
	end
	selected = def.key
	setMode("intro")
	renderIntro()
	return true
end

-- mini_notice mit kind "arcade_round" | "arcade_step" | "arcade_result"
function ArcadeUI.OnNotice(data)
	if type(data) ~= "table" or not refs.head then
		return
	end
	local ok, err = pcall(function()
		if data.kind == "arcade_round" then
			onRound(data)
		elseif data.kind == "arcade_step" then
			onStep(data)
		elseif data.kind == "arcade_go" then
			onGo(data)
		elseif data.kind == "arcade_result" then
			onResult(data)
		end
	end)
	if not ok then
		warn("[Spielhalle] " .. tostring(data.kind) .. ": " .. tostring(err))
	end
end

function ArcadeUI.IsPlaying()
	return cur ~= nil and cur.result == nil and not cur.gaveUp
end

-- Laufende Runde (für Tests)
function ArcadeUI.Current()
	return cur
end

return ArcadeUI
