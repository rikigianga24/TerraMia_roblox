-- Animazioni delle piante, solo sullo schermo di chi guarda.
--
-- Il server (src/server/FarmView.luau) mette sulle piante nuove l'attributo
-- Fx con l'ora del server in FxAt:
--   "plant"    il sacchetto di semi spunta dalla terra
--   "grow"     la pianta passa alla fase dopo: rimbalzo elastico, foglioline
--   "ready"    è matura: salto con giravolta, stelline dorate e un'onda
--   "harvest"  un modello "RaccoltoFx" col prodotto: salta fuori e vola dal
--              contadino che l'ha raccolto
-- Le modifiche fatte qui restano locali: il server non le vede.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local FarmFx = {}

local FRESH = 2 -- secondi: un effetto più vecchio (chi entra dopo) non si gioca
local FAR = 300 -- stud: oltre questa distanza dalla telecamera non si anima

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local PUFF = "rbxasset://textures/particles/smoke_main.dds"

local LEAF = Color3.fromRGB(122, 196, 84)
local GOLD = Color3.fromRGB(255, 214, 92)
local DUST = Color3.fromRGB(176, 140, 98)

local function hexColor(hex: any): Color3
	if typeof(hex) == "string" and #hex == 6 then
		return Color3.fromHex(hex)
	end
	return GOLD
end

-- Uno sbuffo di particelle da un punto, poi si pulisce da solo.
local function burst(at: Vector3, color: Color3, count: number, opts: { [string]: any }?)
	local o = opts or {}
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(at)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Texture = o.texture or SPARK
	e.Color = ColorSequence.new(color)
	e.LightEmission = o.glow or 0.4
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, o.size or 0.8),
		NumberSequenceKeypoint.new(0.6, (o.size or 0.8) * 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.5, o.life or 1)
	e.Speed = NumberRange.new(o.speedMin or 8, o.speed or 16)
	e.SpreadAngle = Vector2.new(o.spread or 55, o.spread or 55)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, o.gravity or -40, 0)
	e.Drag = o.drag or 2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-260, 260)
	e.Parent = anchor
	anchor.Parent = workspace
	e:Emit(count)
	Debris:AddItem(anchor, 2)
end

-- Un'onda luminosa che si allarga sul terreno.
local function ring(at: Vector3, color: Color3, radius: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.25
	p.Size = Vector3.new(0.15, 1, 1)
	p.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.7)
end

-- Gira fn(t) a ogni fotogramma per "duration" secondi (t da 0 a 1), finché
-- il modello esiste. Alla fine richiama fn(1).
local function animate(m: Model, duration: number, fn: (number) -> ())
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not m.Parent then
			conn:Disconnect()
			return
		end
		local t = math.min((os.clock() - start) / duration, 1)
		fn(t)
		if t >= 1 then
			conn:Disconnect()
		end
	end)
end

-- Molla smorzata: parte da k0 e si assesta su 1 passando un po' oltre.
local function spring(t: number, k0: number, wobble: number?): number
	local w = wobble or 11
	return 1 - (1 - k0) * math.exp(-5.5 * t) * math.cos(w * t)
end

local function size(m: Model): (Vector3, number)
	local _, s = m:GetBoundingBox()
	return s, math.max(s.X, s.Z)
end

-- Pianta che spunta o cresce: dal piccolo al grande con un rimbalzo, un
-- dondolio e uno sbuffo di foglie e terra.
local function playGrow(m: Model, fromZero: boolean)
	local pivot = m:GetPivot()
	local base = m:GetScale()
	local s, wide = size(m)
	local k0 = if fromZero then 0.05 else 0.35
	m:ScaleTo(base * k0)
	burst(pivot.Position + Vector3.new(0, 0.3, 0), DUST, 10, {
		texture = PUFF, size = wide * 0.35, speed = 6, speedMin = 2, gravity = 0, drag = 4, glow = 0, spread = 80, life = 0.8,
	})
	burst(pivot.Position + Vector3.new(0, s.Y * 0.5, 0), LEAF, 14, { size = 0.7, speed = 14 })
	burst(pivot.Position + Vector3.new(0, s.Y * 0.6, 0), Color3.fromRGB(255, 250, 210), 6, { size = 0.5, speed = 10, glow = 1 })
	local tiltAxis = if math.random() < 0.5 then 1 else -1
	animate(m, 0.85, function(t)
		local k = if t >= 1 then 1 else spring(t, k0)
		m:ScaleTo(base * math.max(k, 0.01))
		-- dondola come una molla e si raddrizza
		local tilt = if t >= 1 then 0 else 0.22 * math.exp(-4.5 * t) * math.sin(16 * t)
		m:PivotTo(pivot * CFrame.Angles(tilt * tiltAxis, 0, tilt * 0.6))
	end)
end

-- Pianta matura: salta con una giravolta, atterra schiacciandosi un po',
-- stelline dorate e un'onda di luce.
local function playReady(m: Model, color: Color3)
	local pivot = m:GetPivot()
	local base = m:GetScale()
	local s, wide = size(m)
	local hop = math.clamp(s.Y * 0.35, 1.5, 4)
	burst(pivot.Position + Vector3.new(0, s.Y * 0.7, 0), GOLD, 22, { size = 0.9, speed = 20, glow = 1 })
	burst(pivot.Position + Vector3.new(0, s.Y * 0.6, 0), color, 12, { size = 0.7, speed = 15, glow = 0.6 })
	ring(pivot.Position, GOLD, wide * 0.9)
	animate(m, 1, function(t)
		local y, k, spin = 0, 1, 0
		if t < 0.4 then
			local u = t / 0.4
			y = hop * 4 * u * (1 - u) -- parabola
			spin = u * 2 * math.pi
			k = 1 + 0.12 * math.sin(u * math.pi) -- si allunga in aria
		elseif t < 1 then
			local u = (t - 0.4) / 0.6
			k = spring(u, 0.82, 14) -- atterra e rimbalza
		end
		m:ScaleTo(base * k)
		m:PivotTo(pivot * CFrame.new(0, y, 0) * CFrame.Angles(0, spin, 0))
	end)
end

local function ownerRoot(m: Model): BasePart?
	local farm = m.Parent
	while farm and farm:GetAttribute("OwnerUserId") == nil do
		farm = farm.Parent
	end
	local owner = farm and Players:GetPlayerByUserId(farm:GetAttribute("OwnerUserId"))
	local character = owner and owner.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function hide(m: Model)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = 1
		end
	end
end

-- Raccolto: il prodotto salta fuori gonfiandosi, gira, e vola dal contadino
-- rimpicciolendo; coriandoli del colore della pianta.
local function playHarvest(m: Model, color: Color3)
	local pivot = m:GetPivot()
	local base = m:GetScale()
	local start = pivot.Position
	local root = ownerRoot(m)
	burst(start + Vector3.new(0, 1, 0), color, 18, { size = 0.8, speed = 18, glow = 0.5 })
	burst(start + Vector3.new(0, 1, 0), GOLD, 10, { size = 0.6, speed = 12, glow = 1 })
	burst(start + Vector3.new(0, 0.3, 0), DUST, 8, {
		texture = PUFF, size = 1.6, speed = 5, speedMin = 2, gravity = 0, drag = 4, glow = 0, spread = 80, life = 0.7,
	})
	local peak = start + Vector3.new(0, 6, 0)
	animate(m, 1.1, function(t)
		local pos, k
		if t < 0.35 then
			local u = t / 0.35
			pos = start:Lerp(peak, 1 - (1 - u) ^ 3)
			k = spring(u, 0.3, 9) * 1.35
		else
			local u = (t - 0.35) / 0.65
			local target = if root then root.Position + Vector3.new(0, 1.5, 0) else peak + Vector3.new(0, 8, 0)
			local e = u * u
			pos = peak:Lerp(target, e) + Vector3.new(0, 3 * math.sin(u * math.pi), 0)
			k = 1.35 * (1 - e) + 0.05
		end
		m:ScaleTo(base * k)
		m:PivotTo(CFrame.new(pos) * (pivot - pivot.Position) * CFrame.Angles(0, t * 5 * math.pi, 0))
		if t >= 1 then
			hide(m)
			if root then
				burst(root.Position + Vector3.new(0, 1.5, 0), GOLD, 8, { size = 0.5, speed = 8, glow = 1 })
			end
		end
	end)
end

local function onModel(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local fx = m:GetAttribute("Fx")
	local at = m:GetAttribute("FxAt")
	if typeof(fx) ~= "string" or typeof(at) ~= "number" then
		return
	end
	if workspace:GetServerTimeNow() - at > FRESH then
		if fx == "harvest" then
			hide(m) -- arrivato tardi: il prodotto non resta a mezz'aria
		end
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - m:GetPivot().Position).Magnitude > FAR then
		if fx == "harvest" then
			hide(m)
		end
		return
	end
	local ok, err = pcall(function()
		if fx == "plant" then
			playGrow(m, true)
		elseif fx == "grow" then
			playGrow(m, false)
		elseif fx == "ready" then
			playReady(m, hexColor(m:GetAttribute("Color")))
		elseif fx == "harvest" then
			playHarvest(m, hexColor(m:GetAttribute("Color")))
		end
	end)
	if not ok then
		warn("FarmFx:", err)
	end
end

function FarmFx.init()
	local world = workspace:WaitForChild("Mondo")
	world.DescendantAdded:Connect(onModel)
end

return FarmFx
