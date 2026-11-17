-- La fattoria di un giocatore nel mondo 3D: 18×18 mattonelle, piante,
-- animali, strutture, decorazioni, forziere e cartelli dei lotti in vendita.
--
-- È costruita dal server, così ognuno vede anche le fattorie degli altri.
-- refresh(state) confronta una "firma" per ogni quadrante e oggetto e
-- ricostruisce solo quello che è cambiato (si chiama ogni secondo).
--
-- Ogni pezzo toccabile ha (lui o un antenato) gli attributi CellX e CellY;
-- la cartella della fattoria ha OwnerUserId. Il client li usa per capire
-- quale quadrante è stato toccato (src/client/FarmInput.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = require(Shared.GameData)
local Rules = require(Shared.Rules)
local WorldConfig = require(Shared.WorldConfig)
local Build = require(script.Parent.Build)

local C = Build.COLORS
local CELL = WorldConfig.FARM_CELL
local TILE_H = WorldConfig.FARM_TILE_HEIGHT
local N = GameData.worldSize()
local S = GameData.SECTOR_SIZE

local FarmView = {}
FarmView.__index = FarmView

local function tag(inst: Instance, x: number, y: number)
	inst:SetAttribute("CellX", x)
	inst:SetAttribute("CellY", y)
end

function FarmView.new(index: number, player: Player)
	local self = setmetatable({}, FarmView)
	self.index = index
	self.folder = Instance.new("Folder")
	self.folder.Name = "Fattoria_" .. index
	self.folder:SetAttribute("OwnerUserId", player.UserId)
	self.folder:SetAttribute("PlotIndex", index)
	self.tiles = {} :: { [string]: BasePart }
	self.tileSig = {} :: { [string]: string }
	self.things = {} :: { [string]: Instance } -- piante e forziere per quadrante
	self.thingSig = {} :: { [string]: string }
	self.objects = {} :: { [number]: Instance } -- oggetti posati per uid
	self.objectSig = {} :: { [number]: string }
	self.signs = {} :: { [string]: Instance }
	self.signSig = {} :: { [string]: string }

	local tiles = Instance.new("Folder")
	tiles.Name = "Quadranti"
	tiles.Parent = self.folder
	for y = 0, N - 1 do
		for x = 0, N - 1 do
			local p = WorldConfig.farmCell(index, x, y)
			local tile = Build.part({
				Name = GameData.key(x, y),
				Size = Vector3.new(CELL, TILE_H, CELL),
				CFrame = CFrame.new(p - Vector3.new(0, TILE_H / 2, 0)),
				Color = C.grassLocked,
				Material = Enum.Material.Grass,
			}, tiles)
			tag(tile, x, y)
			self.tiles[GameData.key(x, y)] = tile
		end
	end
	self.plants = Instance.new("Folder")
	self.plants.Name = "Piante"
	self.plants.Parent = self.folder
	self.objectFolder = Instance.new("Folder")
	self.objectFolder.Name = "Oggetti"
	self.objectFolder.Parent = self.folder

	-- cartello col nome del contadino, davanti alla fattoria
	local front = WorldConfig.plotOrigin(index) + Vector3.new(WorldConfig.PLOT_SIDE / 2, 0, -WorldConfig.PLOT_SIDE - 3)
	local post = Build.block(front, Vector3.new(0.6, 5, 0.6), C.wood, Enum.Material.Wood, self.folder)
	Build.block(front + Vector3.new(0, 3.2, 0), Vector3.new(7, 2, 0.4), C.woodLight, Enum.Material.Wood, self.folder)
	Build.label(post, "UI_YOUR_FARM", player.DisplayName, 6, 200)

	self.folder.Parent = workspace:WaitForChild("Mondo")
	return self
end

function FarmView:destroy()
	self.folder:Destroy()
end

-- --- Mattonelle ---------------------------------------------------------------

local function tileLook(s: any, x: number, y: number): (string, Color3, Enum.Material, number)
	if not Rules.isInGrid(s, x, y) then
		return "locked", C.grassLocked, Enum.Material.Grass, -0.3
	end
	if Rules.isPlowQueued(s, x, y) then
		return "queued", C.soilQueued, Enum.Material.Ground, 0
	end
	if Rules.isTilled(s, x, y) then
		if Rules.isGrowing(s, x, y) then
			return "wet", C.soilWet, Enum.Material.Mud, 0
		end
		return "soil", C.soil, Enum.Material.Ground, 0
	end
	local light = (x + y) % 2 == 0
	return if light then "grass1" else "grass2", if light then C.grass else C.grassDark, Enum.Material.Grass, 0
end

-- --- Piante -------------------------------------------------------------------

local function plantStage(s: any, x: number, y: number): string
	if Rules.needsWater(s, x, y) then
		return "bag"
	end
	local p = Rules.plotProgress(s, x, y)
	if p >= 1 then
		return "ready"
	elseif p < 0.34 then
		return "s1"
	elseif p < 0.67 then
		return "s2"
	end
	return "s3"
end

local function seedBag(m: Model, base: Vector3, color: Color3, big: boolean)
	local k = if big then 1.3 else 1
	Build.block(base, Vector3.new(1.3 * k, 1.4 * k, 1 * k), Color3.fromRGB(214, 186, 140), Enum.Material.Fabric, m).CanCollide = false
	Build.block(base + Vector3.new(0, 0.8 * k, 0), Vector3.new(1.32 * k, 0.4 * k, 1.02 * k), color, Enum.Material.Fabric, m).CanCollide = false
end

local function buildPlant(cropId: string, stage: string, fertilized: boolean, base: Vector3): Model
	local c = GameData.CROPS[cropId]
	local color = GameData.color(c.color)
	local m = Instance.new("Model")
	m.Name = cropId
	local perennial = GameData.isPerennial(cropId)
	if fertilized then
		Build.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 3, 3),
			CFrame = CFrame.new(base + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(226, 214, 120),
			Material = Enum.Material.Sand,
			CanCollide = false,
		}, m)
	end
	if stage == "bag" then
		seedBag(m, base, color, perennial)
		return m
	end
	local leaf = if c.kind == "crop" then Color3.fromRGB(88, 150, 60) else C.leaf
	local growth = if stage == "s1" then 0.4 elseif stage == "s2" then 0.7 else 1
	if c.kind == "tree" then
		local trunkH = 1.2 + 2 * growth
		local trunk = Build.cylinder(base, trunkH, 0.35 + 0.35 * growth, C.wood, m)
		trunk.CanCollide = false
		local canopy = Build.ball(base + Vector3.new(0, trunkH + 0.8 * growth, 0), 1.4 + 2.4 * growth, leaf, m)
		if stage == "ready" then
			for i = 1, 6 do
				local a = i * math.pi / 3
				Build.ball(canopy.Position + Vector3.new(math.cos(a) * 1.4, -0.3 + (i % 2) * 0.8, math.sin(a) * 1.4), 0.6, color, m)
			end
		end
	elseif c.kind == "bush" then
		local d = 1 + 1.6 * growth
		Build.ball(base + Vector3.new(0, d / 2, 0), d, leaf, m)
		if stage == "ready" then
			for i = 1, 5 do
				local a = i * 2 * math.pi / 5
				Build.ball(base + Vector3.new(math.cos(a) * d / 2.4, d * 0.6, math.sin(a) * d / 2.4), 0.45, color, m)
			end
		end
	else
		-- coltura: ciuffo che cresce; il grano diventa dorato, le altre fanno i frutti
		local h = 0.5 + 1.6 * growth
		local golden = cropId == "grano" and stage == "ready"
		for i = 1, 3 do
			local a = i * 2 * math.pi / 3
			local stalk = Build.block(base + Vector3.new(math.cos(a) * 0.5, 0, math.sin(a) * 0.5),
				Vector3.new(0.35, h, 0.35), if golden then color else leaf, Enum.Material.Grass, m)
			stalk.CanCollide = false
			stalk.CFrame *= CFrame.Angles(math.sin(a) * 0.25, 0, math.cos(a) * 0.25)
		end
		if stage == "s3" or stage == "ready" then
			Build.ball(base + Vector3.new(0, h * 0.7, 0), 1.2, leaf, m)
		end
		if stage == "ready" and not golden then
			for i = 1, 3 do
				local a = i * 2 * math.pi / 3 + 0.5
				Build.ball(base + Vector3.new(math.cos(a) * 0.7, h * 0.6, math.sin(a) * 0.7), 0.7, color, m)
			end
		end
	end
	if stage == "ready" then
		local spark = Instance.new("Sparkles")
		spark.SparkleColor = Color3.fromRGB(255, 236, 160)
		spark.TimeScale = 0.5
		spark.Parent = m:FindFirstChildWhichIsA("BasePart")
	end
	return m
end

local function buildChest(base: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "Forziere"
	Build.block(base, Vector3.new(2.4, 1.6, 1.6), Color3.fromRGB(120, 72, 36), Enum.Material.Wood, m)
	Build.block(base + Vector3.new(0, 1.6, 0), Vector3.new(2.5, 0.5, 1.7), Color3.fromRGB(140, 86, 44), Enum.Material.Wood, m)
	Build.block(base + Vector3.new(0, 0.7, 0), Vector3.new(2.5, 0.3, 1.7), Color3.fromRGB(222, 176, 70), Enum.Material.Metal, m)
	local spark = Instance.new("Sparkles")
	spark.SparkleColor = Color3.fromRGB(255, 220, 120)
	spark.Parent = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	return m
end

-- --- Oggetti posati -----------------------------------------------------------

local INDICATOR = {
	bottle = Color3.fromRGB(150, 205, 240),
	hungry = Color3.fromRGB(232, 197, 71),
}

local function indicator(m: Model, at: Vector3, color: Color3)
	local b = Build.ball(at, 0.9, color, m)
	b.Material = Enum.Material.Neon
	b.Name = "Indicatore"
end

local function buildAnimal(o: any, base: Vector3): Model
	local m = Instance.new("Model")
	m.Name = o.type
	local adult = Rules.isAdult(o)
	local k = if adult then 1 else 0.6
	local top
	if o.type == "gallina" then
		Build.ball(base + Vector3.new(0, 0.8 * k, 0), 1.5 * k, Color3.fromRGB(246, 240, 226), m)
		Build.ball(base + Vector3.new(0, 1.7 * k, 0.5 * k), 0.8 * k, Color3.fromRGB(246, 240, 226), m)
		Build.block(base + Vector3.new(0, 2.05 * k, 0.5 * k), Vector3.new(0.2, 0.35, 0.4) * k, Color3.fromRGB(210, 50, 40), nil, m)
		top = 2.8 * k
	elseif o.type == "mucca" then
		Build.block(base + Vector3.new(0, 1.2 * k, 0), Vector3.new(1.8, 1.6, 3) * k, Color3.fromRGB(250, 248, 240), nil, m)
		Build.block(base + Vector3.new(0, 2 * k, 1.8 * k), Vector3.new(1.2, 1.1, 1) * k, Color3.fromRGB(250, 248, 240), nil, m)
		Build.ball(base + Vector3.new(0.5 * k, 2 * k, -0.4 * k), 1 * k, Color3.fromRGB(40, 36, 34), m)
		for _, d in { { -0.6, -1.1 }, { 0.6, -1.1 }, { -0.6, 1.1 }, { 0.6, 1.1 } } do
			Build.block(base + Vector3.new(d[1] * k, 0, d[2] * k), Vector3.new(0.4, 1.2, 0.4) * k, Color3.fromRGB(60, 50, 44), nil, m)
		end
		top = 3.4 * k
	else -- pecora
		for _, d in { { 0, 0 }, { 0.5, 0.6 }, { -0.5, 0.6 }, { 0.5, -0.6 }, { -0.5, -0.6 } } do
			Build.ball(base + Vector3.new(d[1] * k, 1.3 * k, d[2] * k), 1.4 * k, Color3.fromRGB(244, 236, 216), m)
		end
		Build.ball(base + Vector3.new(0, 1.6 * k, 1.3 * k), 0.9 * k, Color3.fromRGB(60, 50, 44), m)
		top = 2.8 * k
	end
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
		end
	end
	local st = Rules.animalState(o)
	if st == "ready" then
		local product = GameData.ANIMALS[o.type].product
		indicator(m, base + Vector3.new(0, top + 0.8, 0), if product == "uova" then Color3.fromRGB(250, 236, 200) else Color3.fromRGB(255, 255, 255))
	elseif INDICATOR[st] then
		indicator(m, base + Vector3.new(0, top + 0.8, 0), INDICATOR[st])
	end
	return m
end

local function buildStructure(o: any, base: Vector3, s: any): Model
	local m = Instance.new("Model")
	m.Name = o.type
	local w, d = GameData.footprint(o.kind, o.type)
	local width, depth = w * CELL - 1, d * CELL - 1
	if o.type == "falegnameria" then
		Build.block(base, Vector3.new(width, 5, depth), C.woodLight, Enum.Material.WoodPlanks, m)
		Build.roof(base + Vector3.new(0, 5, 0), width, depth, 2.4, C.wood, m)
		Build.block(base + Vector3.new(0, 0, depth / 2 + 0.6), Vector3.new(2.4, 1, 1.2), C.wood, Enum.Material.Wood, m)
	else -- cucina
		Build.block(base, Vector3.new(width, 5, depth), C.plaster[3], Enum.Material.Plaster, m)
		Build.roof(base + Vector3.new(0, 5, 0), width, depth, 2.4, C.roof, m)
		local chimney = Build.block(base + Vector3.new(width / 4, 6, 0), Vector3.new(1, 3, 1), C.stoneDark, Enum.Material.Brick, m)
		if o.recipe then
			local smoke = Instance.new("Smoke")
			smoke.Opacity = 0.15
			smoke.RiseVelocity = 3
			smoke.Size = 1
			smoke.Parent = chimney
		end
	end
	if o.recipe and Rules.recipeProgress(s, o.uid) >= 1 then
		indicator(m, base + Vector3.new(0, 9, 0), Color3.fromRGB(255, 214, 90))
	end
	return m
end

local function buildDecor(o: any, base: Vector3): Model
	local m = Instance.new("Model")
	m.Name = o.type
	if o.type == "staccionata" then
		for _, dx in { -1.6, 0, 1.6 } do
			Build.block(base + Vector3.new(dx, 0, 0), Vector3.new(0.3, 1.8, 0.3), C.woodLight, Enum.Material.Wood, m)
		end
		for _, h in { 0.6, 1.3 } do
			Build.block(base + Vector3.new(0, h, 0), Vector3.new(3.6, 0.25, 0.2), C.woodLight, Enum.Material.Wood, m)
		end
	elseif o.type == "secchio" then
		Build.cylinder(base, 1, 1, Color3.fromRGB(160, 166, 170), m).Material = Enum.Material.Metal
	elseif o.type == "barile" then
		Build.cylinder(base, 2, 1.6, C.wood, m).Material = Enum.Material.Wood
	else -- panchina
		Build.block(base + Vector3.new(0, 0.9, 0), Vector3.new(3.2, 0.25, 1), C.woodLight, Enum.Material.Wood, m)
		Build.block(base + Vector3.new(0, 1.4, -0.45), Vector3.new(3.2, 0.8, 0.15), C.woodLight, Enum.Material.Wood, m)
		for _, dx in { -1.3, 1.3 } do
			Build.block(base + Vector3.new(dx, 0, 0), Vector3.new(0.3, 0.9, 0.8), C.wood, Enum.Material.Wood, m)
		end
	end
	return m
end

local function objectSig(o: any, s: any): string
	if o.kind == "animal" then
		return table.concat({ o.kind, o.type, o.cell, tostring(Rules.isAdult(o)), Rules.animalState(o) }, "|")
	elseif o.kind == "structure" then
		local st = if not o.recipe then "idle" elseif Rules.recipeProgress(s, o.uid) >= 1 then "ready" else "work"
		return table.concat({ o.kind, o.type, o.cell, st }, "|")
	end
	return table.concat({ o.kind, o.type, o.cell }, "|")
end

-- --- Cartelli dei lotti -------------------------------------------------------

local function buildSign(index: number, sx: number, sy: number): Model
	local m = Instance.new("Model")
	m.Name = "Cartello"
	local cx = sx * S + S / 2 - 0.5
	local cy = sy * S + S / 2 - 0.5
	local base = WorldConfig.farmCell(index, cx, cy)
	local post = Build.block(base, Vector3.new(0.5, 4, 0.5), C.wood, Enum.Material.Wood, m)
	Build.block(base + Vector3.new(0, 2.6, 0), Vector3.new(4.5, 2.2, 0.3), Color3.fromRGB(250, 236, 200), Enum.Material.Fabric, m)
	Build.label(post, "LAND_SIGN", nil, 5, 160)
	-- tocco sul cartello = tocco su un quadrante del lotto
	tag(m, sx * S + S // 2, sy * S + S // 2)
	return m
end

-- --- Aggiornamento ------------------------------------------------------------

function FarmView:refresh(s: any)
	for y = 0, N - 1 do
		for x = 0, N - 1 do
			local k = GameData.key(x, y)
			-- mattonella
			local sig, color, material, dy = tileLook(s, x, y)
			if self.tileSig[k] ~= sig then
				self.tileSig[k] = sig
				local tile = self.tiles[k]
				tile.Color = color
				tile.Material = material
				local p = WorldConfig.farmCell(self.index, x, y)
				tile.CFrame = CFrame.new(p - Vector3.new(0, TILE_H / 2 - dy, 0))
			end
			-- pianta o forziere
			local thing = ""
			local plot = Rules.getPlot(s, x, y)
			if plot then
				thing = plot.crop .. "|" .. plantStage(s, x, y) .. "|" .. tostring(plot.fertilized)
			elseif Rules.isChestCell(s, x, y) then
				thing = "chest"
			end
			if self.thingSig[k] ~= thing then
				self.thingSig[k] = thing
				if self.things[k] then
					self.things[k]:Destroy()
					self.things[k] = nil
				end
				local base = WorldConfig.farmCell(self.index, x, y)
				local m
				if plot then
					m = buildPlant(plot.crop, plantStage(s, x, y), plot.fertilized, base)
				elseif thing == "chest" then
					m = buildChest(base)
				end
				if m then
					tag(m, x, y)
					m.Parent = self.plants
					self.things[k] = m
				end
			end
		end
	end
	-- oggetti posati
	local alive = {}
	for _, o in s.placed do
		alive[o.uid] = true
		local sig = objectSig(o, s)
		if self.objectSig[o.uid] ~= sig then
			self.objectSig[o.uid] = sig
			if self.objects[o.uid] then
				self.objects[o.uid]:Destroy()
			end
			local ox, oy = GameData.unkey(o.cell)
			local w, d = GameData.footprint(o.kind, o.type)
			local a = WorldConfig.farmCell(self.index, ox, oy)
			local b = WorldConfig.farmCell(self.index, ox + w - 1, oy + d - 1)
			local base = (a + b) / 2
			local m
			if o.kind == "animal" then
				m = buildAnimal(o, base)
			elseif o.kind == "structure" then
				m = buildStructure(o, base, s)
			else
				m = buildDecor(o, base)
			end
			tag(m, ox, oy)
			m:SetAttribute("Uid", o.uid)
			m.Parent = self.objectFolder
			self.objects[o.uid] = m
		end
	end
	for uid, m in self.objects do
		if not alive[uid] then
			m:Destroy()
			self.objects[uid] = nil
			self.objectSig[uid] = nil
		end
	end
	-- cartelli "In vendita" sui lotti che si possono comprare
	for sy = 0, GameData.WORLD_SECTORS - 1 do
		for sx = 0, GameData.WORLD_SECTORS - 1 do
			local k = GameData.key(sx, sy)
			local want = if Rules.isSectorBuyable(s, sx, sy) then "sale" else ""
			if self.signSig[k] ~= want then
				self.signSig[k] = want
				if self.signs[k] then
					self.signs[k]:Destroy()
					self.signs[k] = nil
				end
				if want ~= "" then
					local m = buildSign(self.index, sx, sy)
					m.Parent = self.plants
					self.signs[k] = m
				end
			end
		end
	end
end

return FarmView
