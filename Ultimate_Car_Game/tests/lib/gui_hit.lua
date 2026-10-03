-- GUI-Treffertest für den Mock (wie Roblox' Eingabeverteilung): welches sichtbare GuiObject bekommt einen Klick an
-- einem Bildschirmpunkt? Laden mit: local Hit = H.Load("tests/lib/gui_hit.lua")
--
-- Bildschirmkoordinaten = Kamera-ViewportSize (ganzes Fenster). ScreenGuis mit IgnoreGuiInset = false beginnen 36 px
-- tiefer (Roblox-Topbar). Berücksichtigt: ScreenGui.Enabled und DisplayOrder (höher = oben; gleich: spätere zuerst
-- unten), Visible aller Vorfahren, ZIndexBehavior (Sibling: Kinder über dem Elternteil, Geschwister nach ZIndex, dann
-- Baumreihenfolge; Global: ZIndex über alles, dann Baumreihenfolge), ClipsDescendants (ScrollingFrame schneidet immer),
-- UIScale (um den Ankerpunkt), UIPadding, UIListLayout/UIGridLayout (inkl. Ausrichtung), UISizeConstraint,
-- AutomaticSize (Text grob über Zeichenzahl × TextSize × 0,5 mit Umbruch) und ScrollingFrame.CanvasPosition.
-- Eingabe schlucken: GuiButton, TextBox oder Active = true. Andere Objekte lassen den Klick durch (wie Roblox).
-- Der Mock selbst rechnet AbsoluteSize ohne AutomaticSize/UIScale/Layouts – daher die eigene Geometrie hier.
local Hit = {}
Hit.Inset = 36

---------------------------------------------------------------- Hilfen
local function children(obj)
	local ok, list = pcall(function()
		return obj:GetChildren()
	end)
	return ok and list or {}
end

local function firstChild(obj, cls)
	for _, c in ipairs(children(obj)) do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end

local function isGuiObject(x)
	return x ~= nil and x:IsA("GuiObject")
end

local function viewportOf(player)
	local gui = player:FindFirstChild("PlayerGui")
	local any = gui and gui:FindFirstChildWhichIsA("ScreenGui")
	if any then
		local d = rawget(any, "__data")
		if d and d._env then
			return d._env.viewport, d._env.guiInset or Hit.Inset
		end
	end
	return Vector2.new(1280, 800), Hit.Inset
end

local function ownScale(obj)
	local s = firstChild(obj, "UIScale")
	return s and s.Scale or 1
end

local function padding(obj, w, h, cs)
	local p = firstChild(obj, "UIPadding")
	if not p then
		return 0, 0, 0, 0
	end
	local l = p.PaddingLeft.Scale * w + p.PaddingLeft.Offset * cs
	local r = p.PaddingRight.Scale * w + p.PaddingRight.Offset * cs
	local t = p.PaddingTop.Scale * h + p.PaddingTop.Offset * cs
	local b = p.PaddingBottom.Scale * h + p.PaddingBottom.Offset * cs
	return l, r, t, b
end

local function layoutOf(obj)
	for _, c in ipairs(children(obj)) do
		if c.ClassName == "UIListLayout" or c.ClassName == "UIGridLayout" then
			return c
		end
	end
	return nil
end

local function autoX(obj)
	local a = obj.AutomaticSize
	return a == Enum.AutomaticSize.X or a == Enum.AutomaticSize.XY
end

local function autoY(obj)
	local a = obj.AutomaticSize
	return a == Enum.AutomaticSize.Y or a == Enum.AutomaticSize.XY
end

local function textLen(s)
	local ok, n = pcall(utf8.len, s)
	return ok and n or #s
end

-- grobe Textmaße (Breite ≈ Zeichen × TextSize × 0,5; Zeilenhöhe TextSize × 1,2)
local function textSize(obj, maxW, cs)
	local text = obj.Text
	if type(text) ~= "string" or text == "" then
		return 0, 0
	end
	local size = (obj.TextSize or 14) * cs
	local w, lines = 0, 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local lw = textLen(line) * size * 0.5
		if obj.TextWrapped and maxW and maxW > 0 and lw > maxW then
			lines += math.ceil(lw / maxW)
			w = math.max(w, maxW)
		else
			lines += 1
			w = math.max(w, lw)
		end
	end
	return w, lines * size * 1.2
end

local function sortedGuiChildren(obj)
	local list = {}
	for i, c in ipairs(children(obj)) do
		if isGuiObject(c) then
			table.insert(list, { obj = c, i = i })
		end
	end
	return list
end

local function layoutItems(obj)
	local items = {}
	for _, e in ipairs(sortedGuiChildren(obj)) do
		if e.obj.Visible then
			table.insert(items, e)
		end
	end
	table.sort(items, function(a, b)
		if a.obj.LayoutOrder ~= b.obj.LayoutOrder then
			return a.obj.LayoutOrder < b.obj.LayoutOrder
		end
		return a.i < b.i
	end)
	return items
end

---------------------------------------------------------------- Größe
-- Größe eines GuiObjects (nach UIScale) im Inhaltsbereich (aw × ah) des Elternteils; pcs = Gesamtskalierung des
-- Elternteils. Liefert w, h, cs (Skalierung für die Kinder)
local measure

local function contentExtent(obj, innerW, innerH, cs)
	local layout = layoutOf(obj)
	local cw, ch = 0, 0
	if layout and layout.ClassName == "UIListLayout" then
		local horizontal = layout.FillDirection == Enum.FillDirection.Horizontal
		local pad = layout.Padding
		local gap = pad.Offset * cs + pad.Scale * (horizontal and innerW or innerH)
		local items = layoutItems(obj)
		for i, e in ipairs(items) do
			local w, h = measure(e.obj, innerW, innerH, cs)
			if horizontal then
				cw += w + (i > 1 and gap or 0)
				ch = math.max(ch, h)
			else
				ch += h + (i > 1 and gap or 0)
				cw = math.max(cw, w)
			end
		end
	elseif layout and layout.ClassName == "UIGridLayout" then
		local cell, cpad = layout.CellSize, layout.CellPadding
		local cellW = innerW * cell.X.Scale + cell.X.Offset * cs
		local cellH = innerH * cell.Y.Scale + cell.Y.Offset * cs
		local padX, padY = cpad.X.Offset * cs, cpad.Y.Offset * cs
		local n = #layoutItems(obj)
		local perRow = math.max(1, math.floor((innerW + padX) / math.max(1, cellW + padX)))
		local rows = math.ceil(n / perRow)
		cw = math.min(n, perRow) * (cellW + padX)
		ch = rows * (cellH + padY)
	else
		for _, e in ipairs(sortedGuiChildren(obj)) do
			local c = e.obj
			if c.Visible then
				local w, h = measure(c, innerW, innerH, cs)
				local pos = c.Position
				local x = innerW * pos.X.Scale + pos.X.Offset * cs - c.AnchorPoint.X * w
				local y = innerH * pos.Y.Scale + pos.Y.Offset * cs - c.AnchorPoint.Y * h
				cw = math.max(cw, x + w)
				ch = math.max(ch, y + h)
			end
		end
	end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		local tw, th = textSize(obj, (not autoX(obj)) and innerW or nil, cs)
		cw = math.max(cw, tw)
		ch = math.max(ch, th)
	end
	return cw, ch
end

measure = function(obj, aw, ah, pcs)
	local s = obj.Size
	local own = ownScale(obj)
	local w = aw * s.X.Scale + s.X.Offset * pcs
	local h = ah * s.Y.Scale + s.Y.Offset * pcs
	local cs = pcs * own
	if autoX(obj) or autoY(obj) then
		local l, r, t, b = padding(obj, w, h, pcs)
		local cw, ch = contentExtent(obj, math.max(0, w - l - r), math.max(0, h - t - b), pcs)
		if autoX(obj) then
			w = math.max(w, cw + l + r)
		end
		if autoY(obj) then
			h = math.max(h, ch + t + b)
		end
	end
	local limit = firstChild(obj, "UISizeConstraint")
	if limit then
		w = math.clamp(w, limit.MinSize.X, math.max(limit.MinSize.X, limit.MaxSize.X))
		h = math.clamp(h, limit.MinSize.Y, math.max(limit.MinSize.Y, limit.MaxSize.Y))
	end
	return w * own, h * own, cs
end

---------------------------------------------------------------- Lage
-- Rechteck { x, y, w, h, cs, layer } in Bildschirmkoordinaten; cache je Abfrage
local function rectOf(obj, cache, vp, inset)
	local hitc = cache[obj]
	if hitc then
		return hitc
	end
	local r
	if obj:IsA("ScreenGui") then
		local top = obj.IgnoreGuiInset and 0 or inset
		r = { x = 0, y = top, w = vp.X, h = vp.Y - top, cs = 1, layer = obj }
	elseif isGuiObject(obj) and obj.Parent and (obj.Parent:IsA("ScreenGui") or isGuiObject(obj.Parent)) then
		local p = rectOf(obj.Parent, cache, vp, inset)
		local pcs = p.cs
		local l, rr, t, b = 0, 0, 0, 0
		if isGuiObject(obj.Parent) then
			l, rr, t, b = padding(obj.Parent, p.w, p.h, pcs)
		end
		local ix, iy, iw, ih = p.x + l, p.y + t, math.max(0, p.w - l - rr), math.max(0, p.h - t - b)
		if obj.Parent:IsA("ScrollingFrame") then
			local cp = obj.Parent.CanvasPosition
			ix -= cp.X
			iy -= cp.Y
		end
		local w, h, cs = measure(obj, iw, ih, pcs)
		local x, y
		local layout = isGuiObject(obj.Parent) and layoutOf(obj.Parent) or nil
		if layout and layout.ClassName == "UIListLayout" then
			local horizontal = layout.FillDirection == Enum.FillDirection.Horizontal
			local pad = layout.Padding
			local gap = pad.Offset * pcs + pad.Scale * (horizontal and iw or ih)
			local items = layoutItems(obj.Parent)
			local offset, total, mine = 0, 0, nil
			for i, e in ipairs(items) do
				local cw, ch = measure(e.obj, iw, ih, pcs)
				local len = horizontal and cw or ch
				if e.obj == obj then
					mine = total + (i > 1 and gap or 0)
				end
				total += len + (i > 1 and gap or 0)
			end
			offset = mine or 0
			local main0 = 0
			if horizontal then
				local ha = layout.HorizontalAlignment
				if ha == Enum.HorizontalAlignment.Center then
					main0 = (iw - total) / 2
				elseif ha == Enum.HorizontalAlignment.Right then
					main0 = iw - total
				end
				local va = layout.VerticalAlignment
				local cross = 0
				if va == Enum.VerticalAlignment.Center then
					cross = (ih - h) / 2
				elseif va == Enum.VerticalAlignment.Bottom then
					cross = ih - h
				end
				x, y = ix + main0 + offset, iy + cross
			else
				local va = layout.VerticalAlignment
				if va == Enum.VerticalAlignment.Center then
					main0 = (ih - total) / 2
				elseif va == Enum.VerticalAlignment.Bottom then
					main0 = ih - total
				end
				local ha = layout.HorizontalAlignment
				local cross = 0
				if ha == Enum.HorizontalAlignment.Center then
					cross = (iw - w) / 2
				elseif ha == Enum.HorizontalAlignment.Right then
					cross = iw - w
				end
				x, y = ix + cross, iy + main0 + offset
			end
		elseif layout and layout.ClassName == "UIGridLayout" then
			local cell, cpad = layout.CellSize, layout.CellPadding
			local cellW = iw * cell.X.Scale + cell.X.Offset * pcs
			local cellH = ih * cell.Y.Scale + cell.Y.Offset * pcs
			local padX, padY = cpad.X.Offset * pcs, cpad.Y.Offset * pcs
			local perRow = math.max(1, math.floor((iw + padX) / math.max(1, cellW + padX)))
			local index = 0
			for i, e in ipairs(layoutItems(obj.Parent)) do
				if e.obj == obj then
					index = i - 1
				end
			end
			x = ix + (index % perRow) * (cellW + padX)
			y = iy + math.floor(index / perRow) * (cellH + padY)
			w, h = cellW, cellH
		else
			local pos = obj.Position
			local ax = ix + iw * pos.X.Scale + pos.X.Offset * pcs
			local ay = iy + ih * pos.Y.Scale + pos.Y.Offset * pcs
			x = ax - obj.AnchorPoint.X * w
			y = ay - obj.AnchorPoint.Y * h
		end
		r = { x = x, y = y, w = w, h = h, cs = cs, layer = p.layer }
	else
		r = { x = 0, y = 0, w = 0, h = 0, cs = 1, layer = nil, detached = true }
	end
	cache[obj] = r
	return r
end

local function newCache()
	return {}
end

-- Rechteck eines GuiObjects in Bildschirmkoordinaten: x, y, w, h
function Hit.Rect(player, obj)
	local vp, inset = viewportOf(player)
	local r = rectOf(obj, newCache(), vp, inset)
	return r.x, r.y, r.w, r.h
end

function Hit.Center(player, obj)
	local x, y, w, h = Hit.Rect(player, obj)
	return x + w / 2, y + h / 2
end

---------------------------------------------------------------- Sichtbarkeit / Reihenfolge
local function effectivelyVisible(obj)
	local cur = obj
	while cur do
		if cur:IsA("ScreenGui") then
			return cur.Enabled ~= false
		end
		if cur:IsA("LayerCollector") then
			return false -- BillboardGui/SurfaceGui: 3D, nicht Teil des Bildschirm-Treffertests
		end
		if isGuiObject(cur) and cur.Visible == false then
			return false
		end
		cur = cur.Parent
	end
	return false
end
Hit.Visible = effectivelyVisible

local function sinks(obj)
	return obj:IsA("GuiButton") or obj:IsA("TextBox") or obj.Active == true
end
Hit.Sinks = sinks

-- Alle sichtbaren GuiObjects aller ScreenGuis, von unten nach oben
local function drawOrder(player)
	local pg = player:FindFirstChild("PlayerGui")
	local layers = {}
	for i, c in ipairs(children(pg)) do
		if c:IsA("ScreenGui") and c.Enabled ~= false then
			table.insert(layers, { gui = c, i = i })
		end
	end
	table.sort(layers, function(a, b)
		if a.gui.DisplayOrder ~= b.gui.DisplayOrder then
			return a.gui.DisplayOrder < b.gui.DisplayOrder
		end
		return a.i < b.i
	end)
	local out = {}
	for _, layer in ipairs(layers) do
		local global = layer.gui.ZIndexBehavior == Enum.ZIndexBehavior.Global
		local flat = {}
		local seq = 0
		local function visit(node)
			local list = sortedGuiChildren(node)
			table.sort(list, function(a, b)
				if a.obj.ZIndex ~= b.obj.ZIndex then
					return a.obj.ZIndex < b.obj.ZIndex
				end
				return a.i < b.i
			end)
			for _, e in ipairs(list) do
				if e.obj.Visible then
					seq += 1
					table.insert(flat, { obj = e.obj, seq = seq })
					visit(e.obj)
				end
			end
		end
		visit(layer.gui)
		if global then
			table.sort(flat, function(a, b)
				if a.obj.ZIndex ~= b.obj.ZIndex then
					return a.obj.ZIndex < b.obj.ZIndex
				end
				return a.seq < b.seq
			end)
		end
		for _, e in ipairs(flat) do
			table.insert(out, e.obj)
		end
	end
	return out
end

local function inside(r, x, y)
	return r.w > 0 and r.h > 0 and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Liegt der Punkt in allen schneidenden Vorfahren?
local function insideClips(obj, x, y, cache, vp, inset)
	local cur = obj.Parent
	while cur and isGuiObject(cur) do
		if cur.ClipsDescendants or cur:IsA("ScrollingFrame") then
			if not inside(rectOf(cur, cache, vp, inset), x, y) then
				return false
			end
		end
		cur = cur.Parent
	end
	return true
end

-- Oberstes Objekt, das einen Klick am Punkt (x, y) bekommt (GuiButton/TextBox/Active), oder nil (Klick geht in die Welt).
-- Zweiter Rückgabewert: alle sichtbaren Objekte am Punkt, oben zuerst (für Fehlermeldungen).
function Hit.At(player, x, y)
	local vp, inset = viewportOf(player)
	local cache = newCache()
	local order = drawOrder(player)
	local stack = {}
	local hit
	for i = #order, 1, -1 do
		local obj = order[i]
		local r = rectOf(obj, cache, vp, inset)
		if inside(r, x, y) and insideClips(obj, x, y, cache, vp, inset) then
			table.insert(stack, obj)
			if not hit and sinks(obj) then
				hit = obj
			end
		end
	end
	return hit, stack
end

function Hit.Path(obj)
	if not obj then
		return "nichts"
	end
	local parts = {}
	local cur = obj
	while cur and not cur:IsA("PlayerGui") do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	local label = table.concat(parts, ".")
	local text = obj.Text
	if type(text) == "string" and text ~= "" then
		label = label .. " „" .. text:sub(1, 40) .. "“"
	end
	return label
end

-- Sichtbare, eingabeschluckende Objekte, die über `obj` gezeichnet werden und sich mit seinem Rechteck
-- überschneiden (außer Nachfahren von obj). Liefert eine Liste { obj, x, y, w, h }.
function Hit.Covering(player, obj)
	local vp, inset = viewportOf(player)
	local cache = newCache()
	local order = drawOrder(player)
	local me = rectOf(obj, cache, vp, inset)
	local out = {}
	local seen = false
	for _, o in ipairs(order) do
		if o == obj then
			seen = true
		elseif seen and sinks(o) and not o:IsDescendantOf(obj) and not obj:IsDescendantOf(o) then
			local r = rectOf(o, cache, vp, inset)
			local ox = math.min(me.x + me.w, r.x + r.w) - math.max(me.x, r.x)
			local oy = math.min(me.y + me.h, r.y + r.h) - math.max(me.y, r.y)
			if ox > 0.5 and oy > 0.5 and r.w > 0 and r.h > 0 then
				table.insert(out, { obj = o, x = r.x, y = r.y, w = r.w, h = r.h })
			end
		end
	end
	return out
end

-- Schneiden sich zwei sichtbare Objekte (Bildschirmrechtecke)?
function Hit.Overlap(player, a, b)
	local vp, inset = viewportOf(player)
	local cache = newCache()
	local ra, rb = rectOf(a, cache, vp, inset), rectOf(b, cache, vp, inset)
	local ox = math.min(ra.x + ra.w, rb.x + rb.w) - math.max(ra.x, rb.x)
	local oy = math.min(ra.y + ra.h, rb.y + rb.h) - math.max(ra.y, rb.y)
	return ox > 0.5 and oy > 0.5 and ra.w > 0 and ra.h > 0 and rb.w > 0 and rb.h > 0
end

-- Schiebt die ScrollingFrame-Vorfahren so, dass die Mitte von obj im sichtbaren Bereich liegt (wie Scrollen des Spielers)
function Hit.ScrollIntoView(player, obj)
	local cur = obj.Parent
	while cur and isGuiObject(cur) do
		if cur:IsA("ScrollingFrame") then
			local vp, inset = viewportOf(player)
			local cache = newCache()
			local fr = rectOf(cur, cache, vp, inset)
			local orr = rectOf(obj, cache, vp, inset)
			local cp = cur.CanvasPosition
			local cy, cx = cp.Y, cp.X
			local midY = orr.y + orr.h / 2
			if midY < fr.y + 4 or midY > fr.y + fr.h - 4 then
				cy = math.max(0, cy + (midY - (fr.y + fr.h / 2)))
			end
			local midX = orr.x + orr.w / 2
			if midX < fr.x + 4 or midX > fr.x + fr.w - 4 then
				cx = math.max(0, cx + (midX - (fr.x + fr.w / 2)))
			end
			cur.CanvasPosition = Vector2.new(cx, cy)
		end
		cur = cur.Parent
	end
end

---------------------------------------------------------------- Klicks
-- Klick wie ein Spieler: Mitte des Knopfs berechnen, Treffertest, Activated auf das tatsächlich getroffene Objekt.
-- Liegt etwas anderes darüber (oder ist der Knopf unsichtbar/außerhalb des Bildschirms), schlägt die Prüfung fehl.
-- opts.label = Beschreibung für die Meldung; opts.scroll = false: nicht automatisch in den sichtbaren Bereich scrollen.
-- Liefert true, wenn genau dieser Knopf getroffen wurde.
function Hit.Click(T, g, player, button, opts)
	opts = opts or {}
	local label = opts.label or (button and Hit.Path(button)) or "Knopf"
	if not T.check(button ~= nil, label .. ": Knopf fehlt") then
		return false
	end
	if not T.check(effectivelyVisible(button), label .. ": Knopf nicht sichtbar") then
		return false
	end
	if opts.scroll ~= false then
		Hit.ScrollIntoView(player, button)
	end
	local vp = viewportOf(player)
	local x, y = Hit.Center(player, button)
	if not T.check(x >= 0 and y >= 0 and x < vp.X and y < vp.Y, string.format("%s: Mitte (%d, %d) außerhalb des Bildschirms %dx%d", label, x, y, vp.X, vp.Y)) then
		return false
	end
	local hit, stack = Hit.At(player, x, y)
	if hit == button then
		g:Click(button)
		return true
	end
	local names = {}
	for i = 1, math.min(4, #stack) do
		table.insert(names, Hit.Path(stack[i]))
	end
	T.check(false, string.format("%s bei (%d, %d) %dx%d verdeckt: Klick landet auf %s [oben: %s]", label, x, y, vp.X, vp.Y, Hit.Path(hit), table.concat(names, " | ")))
	if hit and hit:IsA("GuiButton") then
		g:Click(hit, { force = true })
	end
	return false
end

-- Klick in die 3D-Welt an einem Bildschirmpunkt (Standard: Bildschirmmitte, dort steht das Ziel vor der Kamera).
-- Schluckt dort ein GuiObject die Eingabe, meldet Roblox processed = true und GarageClient ignoriert den Klick:
-- dann schlägt die Prüfung fehl und es wird kein Weltklick ausgelöst.
function Hit.ClickWorld(T, g, player, part, opts)
	opts = opts or {}
	local vp = viewportOf(player)
	local x, y = opts.x or vp.X / 2, opts.y or vp.Y / 2
	local hit = Hit.At(player, x, y)
	if not T.check(hit == nil, string.format("%s: Weltklick bei (%d, %d) %dx%d verschluckt von %s", opts.label or "Weltklick", x, y, vp.X, vp.Y, Hit.Path(hit))) then
		return false
	end
	g:ClickWorld(player, part)
	return true
end

return Hit
