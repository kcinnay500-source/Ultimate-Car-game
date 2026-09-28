-- Effects: Klick-Feedback nur auf dem Client, gepoolt (keine Instanzflut, kein Speicherleck).
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Effects = {}

local POOL_SIZE = 16
local SPARKS = 10
local popPool, popIndex = {}, 0
local sparkPool, sparkIndex = {}, 0
local sound

function Effects.Init(host)
	for i = 1, POOL_SIZE do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(0, 160, 0, 30)
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Font = Enum.Font.GothamBlack
		l.TextSize = 22
		l.TextColor3 = Color3.fromRGB(255, 189, 62)
		l.TextStrokeTransparency = 0.4
		l.Visible = false
		l.ZIndex = 12
		l.Parent = host
		popPool[i] = l
	end
	for i = 1, SPARKS do
		local s = Instance.new("Frame")
		s.BorderSizePixel = 0
		s.Size = UDim2.new(0, 6, 0, 6)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
		s.Visible = false
		s.ZIndex = 11
		s.Parent = host
		sparkPool[i] = s
	end
	sound = Instance.new("Sound")
	sound.Name = "PressClick"
	sound.SoundId = "rbxasset://sounds/clickfast.wav"
	sound.Volume = 0.35
	sound.Parent = SoundService
end

-- Zahl fliegt hoch (Position relativ zum Host, 0..1)
function Effects.Pop(text, x, y)
	popIndex = popIndex % POOL_SIZE + 1
	local l = popPool[popIndex]
	if not l then
		return
	end
	l.Text = text
	l.Position = UDim2.fromScale(x, y)
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0.4
	l.Visible = true
	local tween = TweenService:Create(l, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(x, y - 0.35),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
end

function Effects.Sparks(x, y)
	for _ = 1, 3 do
		sparkIndex = sparkIndex % SPARKS + 1
		local s = sparkPool[sparkIndex]
		if s then
			s.Position = UDim2.fromScale(x, y)
			s.BackgroundTransparency = 0
			s.Visible = true
			local dx = (math.random() - 0.5) * 0.3
			local dy = -math.random() * 0.25
			TweenService:Create(s, TweenInfo.new(0.35), { Position = UDim2.fromScale(x + dx, y + dy), BackgroundTransparency = 1 }):Play()
		end
	end
end

-- Wackeln: Rotation kurz hin und zurück
function Effects.Shake(frame)
	frame.Rotation = (math.random() < 0.5) and -3 or 3
	TweenService:Create(frame, TweenInfo.new(0.08), { Rotation = 0 }):Play()
end

function Effects.Click()
	if sound then
		sound.PlaybackSpeed = 0.9 + math.random() * 0.2
		sound:Play()
	end
end

return Effects
