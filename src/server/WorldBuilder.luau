-- Costruisce all'avvio del server la parte fissa del mondo: luce, prato,
-- strade, la collina del borgo (Terrain) con vigne, uliveti e boschi, le
-- mura, le case e gli edifici da restaurare con la bacheca in piazza.
--
-- La pianta viene da src/shared/BorgoLayout.luau (tools/gen_borgo.py), la
-- stessa del gioco Godot. Ogni edificio del gioco ha due versioni: "Ruin"
-- (visibile) e "Restored" (nascosta). Il client mostra quella giusta per la
-- partita del giocatore (src/client/BorgoLocal.luau).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BorgoLayout = require(Shared.BorgoLayout)
local GameData = require(Shared.GameData)
local WorldConfig = require(Shared.WorldConfig)
local Build = require(script.Parent.Build)

local C = Build.COLORS
local CELL = WorldConfig.BORGO_CELL
-- Il Terrain sta un po' sopra il prato, per non sovrapporsi alla base.
local TERRAIN_LIFT = 1

local WorldBuilder = {}

local rng = Random.new(11) -- deterministico: lo stesso borgo a ogni avvio

local MATERIALS = {
	[" "] = Enum.Material.Grass,
	["v"] = Enum.Material.LeafyGrass,
	["o"] = Enum.Material.Grass,
	["b"] = Enum.Material.LeafyGrass,
	["r"] = Enum.Material.Sand,
	["."] = Enum.Material.Ground,
	["w"] = Enum.Material.Grass,
	["#"] = Enum.Material.Cobblestone,
	["p"] = Enum.Material.Sandstone,
	["c"] = Enum.Material.Limestone,
}

local function setupLighting()
	Lighting.ClockTime = 15.5
	Lighting.GeographicLatitude = 42 -- Italia centrale
	Lighting.Brightness = 2.4
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 135, 120)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Haze = 1.2
	atmosphere.Color = Color3.fromRGB(240, 214, 180)
	atmosphere.Decay = Color3.fromRGB(150, 120, 100)
	atmosphere.Parent = Lighting
	local grading = Lighting:FindFirstChild("TerraMiaColor") or Instance.new("ColorCorrectionEffect")
	grading.Name = "TerraMiaColor"
	;(grading :: ColorCorrectionEffect).TintColor = Color3.fromRGB(255, 246, 232)
	;(grading :: ColorCorrectionEffect).Saturation = 0.12
	grading.Parent = Lighting
end

local function cellTop(cx: number, cy: number): number
	return WorldConfig.cellHeight(cx, cy) + TERRAIN_LIFT
end

-- Prato, strade e il punto di arrivo dei giocatori.
local function buildGround(folder: Instance)
	Build.part({
		Name = "Prato",
		Size = Vector3.new(1600, 4, 1600),
		CFrame = CFrame.new(0, -2, 0),
		Color = C.grass,
		Material = Enum.Material.Grass,
	}, folder)
	local roadColor = C.road
	local south = WorldConfig.BORGO_SIZE_Z / 2
	local farEnd = WorldConfig.FIRST_ROW_FRONT_Z + WorldConfig.PLOT_ROWS * (WorldConfig.PLOT_SIDE + WorldConfig.PLOT_GAP)
	-- strada bianca dalla porta del borgo giù fino alle fattorie
	Build.block(Vector3.new(WorldConfig.ROAD_X, 0, (south + farEnd) / 2), Vector3.new(WorldConfig.ROAD_WIDTH, 0.2, farEnd - south + 8),
		roadColor, Enum.Material.Sand, folder).Name = "Strada"
	-- una stradina davanti a ogni fila di fattorie
	for row = 0, WorldConfig.PLOT_ROWS - 1 do
		local z = WorldConfig.FIRST_ROW_FRONT_Z + row * (WorldConfig.PLOT_SIDE + WorldConfig.PLOT_GAP) - WorldConfig.PLOT_GAP / 2
		local left = WorldConfig.plotOrigin(1).X
		local right = WorldConfig.plotOrigin(WorldConfig.PLOTS_PER_ROW).X + WorldConfig.PLOT_SIDE
		Build.block(Vector3.new((left + right) / 2, 0, z), Vector3.new(right - left, 0.2, 8), roadColor, Enum.Material.Sand, folder).Name = "Stradina"
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Arrivo"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(WorldConfig.ROAD_X, 0.5, WorldConfig.FIRST_ROW_FRONT_Z - WorldConfig.PLOT_GAP / 2)
	spawn.Color = roadColor
	spawn.Material = Enum.Material.Sand
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = folder
end

-- La collina del borgo, cella per cella, con vigne, ulivi e boschi.
local function buildHill(folder: Instance)
	local terrain = workspace.Terrain
	local plants = Instance.new("Folder")
	plants.Name = "Campagna"
	plants.Parent = folder
	local walls = Instance.new("Folder")
	walls.Name = "Mura"
	walls.Parent = folder
	for cy = 0, BorgoLayout.SIZE_Y - 1 do
		for cx = 0, BorgoLayout.SIZE_X - 1 do
			local t = WorldConfig.terrainAt(cx, cy)
			local top = cellTop(cx, cy)
			local p = WorldConfig.borgoCell(cx, cy)
			local bottom = -4
			terrain:FillBlock(
				CFrame.new(p.X, (top + bottom) / 2, p.Z),
				Vector3.new(CELL, top - bottom, CELL),
				MATERIALS[t] or Enum.Material.Grass
			)
			local ground = Vector3.new(p.X, top - 0.3, p.Z)
			local jitter = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
			if t == "w" then
				local wall = Build.block(Vector3.new(p.X, top - 1, p.Z), Vector3.new(CELL, 8, CELL), C.stone, Enum.Material.Cobblestone, walls)
				wall.Name = "Mura"
			elseif t == "b" then
				local r = rng:NextNumber()
				if r < 0.12 then
					Build.cypress(ground + jitter, rng:NextNumber(0.9, 1.3), plants)
				elseif r < 0.6 then
					Build.tree(ground + jitter, rng:NextNumber(1, 1.5), C.leaf, plants)
				end
			elseif t == "o" then
				if rng:NextNumber() < 0.5 then
					Build.tree(ground + jitter, rng:NextNumber(0.6, 0.8), C.olive, plants)
				end
			elseif t == "v" then
				-- due filari di vite per cella
				for _, dz in { -2, 2 } do
					Build.block(ground + Vector3.new(0, 0, dz), Vector3.new(CELL - 1, 1.8, 1), C.leaf, Enum.Material.Grass, plants).CanCollide = false
				end
			elseif t == " " and rng:NextNumber() < 0.03 then
				Build.cypress(ground + jitter, rng:NextNumber(0.9, 1.2), plants)
			end
		end
	end
end

-- Altezza del terreno sotto un lotto (spianato dal generatore).
local function lotBase(x: number, y: number, w: number, d: number): number
	local h = -math.huge
	for cy = y, y + d - 1 do
		for cx = x, x + w - 1 do
			h = math.max(h, cellTop(cx, cy))
		end
	end
	return h - 0.3
end

local function lotCenter(x: number, y: number, w: number, d: number, base: number): Vector3
	local a = WorldConfig.borgoCell(x, y)
	local b = WorldConfig.borgoCell(x + w - 1, y + d - 1)
	return Vector3.new((a.X + b.X) / 2, base, (a.Z + b.Z) / 2)
end

-- Casa restaurata: muri intonacati, tetto in coppi, finestre e porta.
local function buildHouse(parent: Instance, base: Vector3, width: number, depth: number, height: number, plaster: Color3, lit: boolean)
	Build.block(base, Vector3.new(width, height, depth), plaster, Enum.Material.Plaster, parent).Name = "Muri"
	Build.roof(base + Vector3.new(0, height, 0), width, depth, height * 0.45, C.roof, parent)
	-- porta e finestre sul lato sud (+Z)
	local front = base.Z + depth / 2 + 0.05
	Build.part({
		Name = "Porta",
		Size = Vector3.new(2.6, 4.4, 0.3),
		CFrame = CFrame.new(base.X, base.Y + 2.2, front),
		Color = C.wood,
		Material = Enum.Material.Wood,
	}, parent)
	for _, dx in { -width / 2 + 2.5, width / 2 - 2.5 } do
		local win = Build.part({
			Name = "Finestra",
			Size = Vector3.new(1.8, 2, 0.3),
			CFrame = CFrame.new(base.X + dx, base.Y + height - 3, front),
			Color = if lit then C.window else C.shutter,
			Material = if lit then Enum.Material.Neon else Enum.Material.Wood,
			CanCollide = false,
		}, parent)
		if lit then
			local light = Instance.new("PointLight")
			light.Color = C.window
			light.Range = 10
			light.Brightness = 1.2
			light.Parent = win
		end
	end
end

-- Rudere: muri spezzati, macerie ed edera.
local function buildRuin(parent: Instance, base: Vector3, width: number, depth: number)
	local t = 1.2
	local walls = {
		{ Vector3.new(0, 0, depth / 2 - t / 2), Vector3.new(width, 0, t) },
		{ Vector3.new(0, 0, -depth / 2 + t / 2), Vector3.new(width, 0, t) },
		{ Vector3.new(width / 2 - t / 2, 0, 0), Vector3.new(t, 0, depth) },
		{ Vector3.new(-width / 2 + t / 2, 0, 0), Vector3.new(t, 0, depth) },
	}
	for i, wdef in walls do
		local h = rng:NextNumber(2, 6.5)
		local size = wdef[2] + Vector3.new(0, h, 0)
		if i == 1 then
			-- il muro davanti ha un varco: due pezzi
			local half = Vector3.new((width - 3.4) / 2, h, t)
			Build.block(base + wdef[1] + Vector3.new(-(width + 3.4) / 4, 0, 0), half, C.stoneDark, Enum.Material.Cobblestone, parent)
			Build.block(base + wdef[1] + Vector3.new((width + 3.4) / 4, 0, 0), half - Vector3.new(0, h * 0.4, 0), C.stoneDark, Enum.Material.Cobblestone, parent)
		else
			Build.block(base + wdef[1], size, C.stoneDark, Enum.Material.Cobblestone, parent)
		end
	end
	for _ = 1, 5 do
		local s = rng:NextNumber(1, 2.4)
		local p = Build.block(base + Vector3.new(rng:NextNumber(-width / 3, width / 3), 0, rng:NextNumber(-depth / 3, depth / 3)),
			Vector3.new(s, s * 0.7, s), C.stone, Enum.Material.Slate, parent)
		p.CFrame *= CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3))
	end
	Build.ball(base + Vector3.new(-width / 2 + 1, 3.5, depth / 2 - 1), 4, C.ivy, parent)
	Build.ball(base + Vector3.new(width / 2 - 1.5, 2.2, -depth / 2 + 1.5), 3.2, C.ivy, parent)
end

-- Nasconde la versione restaurata: la mostrerà il client, se tocca.
local function hideRestored(folder: Instance)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
			d:SetAttribute("BaseCanCollide", d.CanCollide)
			d.Transparency = 1
			d.CanCollide = false
			d.CastShadow = false
		elseif d:IsA("Light") or d:IsA("Smoke") or d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
end

local function addPrompt(model: Model, at: Vector3, kind: string, id: string)
	local anchor = Build.part({
		Name = "Prompt",
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(at),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, model)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Open"
	prompt.ActionText = ""
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PromptKind", kind)
	prompt:SetAttribute("PromptId", id)
	prompt.Parent = anchor
	return anchor
end

-- Un edificio del gioco: rudere e restauro, cartello col nome e prompt.
local function buildGameBuilding(folder: Instance, id: string, x: number, y: number, w: number, d: number)
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("BuildingId", id)
	local base = lotBase(x, y, w, d)
	local center = lotCenter(x, y, w, d, base)
	local width, depth = w * CELL - 2, d * CELL - 2
	local ruin = Instance.new("Folder")
	ruin.Name = "Ruin"
	ruin.Parent = model
	local restored = Instance.new("Folder")
	restored.Name = "Restored"
	restored.Parent = model
	local height = 9
	if id == "campanile" then
		-- chiesa con il campanile di Don Peppino
		local church = Vector3.new(center.X - 2, base, center.Z + 2)
		buildHouse(restored, church, width - 6, depth - 4, 12, C.plaster[3], true)
		local tower = Vector3.new(center.X + width / 2 - 3.5, base, center.Z - depth / 2 + 3.5)
		Build.block(tower, Vector3.new(6, 26, 6), C.stone, Enum.Material.Limestone, restored)
		Build.roof(tower + Vector3.new(0, 26, 0), 6, 6, 4, C.roof, restored)
		local bell = Build.ball(tower + Vector3.new(0, 23, 0), 2.4, Color3.fromRGB(196, 150, 60), restored)
		bell.Material = Enum.Material.Metal
		buildRuin(ruin, church, width - 6, depth - 4)
		Build.block(tower, Vector3.new(6, 11, 6), C.stoneDark, Enum.Material.Cobblestone, ruin)
		height = 26
	else
		buildHouse(restored, center, width, depth, height, C.plaster[rng:NextInteger(1, #C.plaster)], true)
		-- comignolo con il fumo
		local chimney = Build.block(center + Vector3.new(width / 4, height + 1.5, 0), Vector3.new(1.4, 4, 1.4), C.stoneDark, Enum.Material.Brick, restored)
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(235, 230, 225)
		smoke.Opacity = 0.12
		smoke.RiseVelocity = 3
		smoke.Size = 1.2
		smoke.Parent = chimney
		buildRuin(ruin, center, width, depth)
	end
	hideRestored(restored)
	local prompt = addPrompt(model, center + Vector3.new(0, 3, depth / 2 + 1.5), "building", id)
	Build.label(prompt, "BLD_" .. string.upper(id), nil, height + 2, 140)
	model.Parent = folder
end

-- Una casa qualsiasi del borgo: per ora resta com'è (vecchia, con le persiane chiuse).
local function buildPlainHouse(folder: Instance, x: number, y: number, w: number, d: number)
	local base = lotBase(x, y, w, d)
	local center = lotCenter(x, y, w, d, base)
	local m = Instance.new("Model")
	m.Name = "Casa"
	buildHouse(m, center, w * CELL - 2, d * CELL - 2, rng:NextNumber(8, 11), C.plaster[rng:NextInteger(1, #C.plaster)], false)
	m.Parent = folder
end

-- La bacheca degli ordini in piazza.
local function buildBoard(folder: Instance)
	local sx, sz, n = 0, 0, 0
	local cells = {}
	for cy = 0, BorgoLayout.SIZE_Y - 1 do
		for cx = 0, BorgoLayout.SIZE_X - 1 do
			if WorldConfig.terrainAt(cx, cy) == "p" then
				local p = WorldConfig.borgoCell(cx, cy)
				sx += p.X
				sz += p.Z
				n += 1
				table.insert(cells, { cx, cy })
			end
		end
	end
	if n == 0 then
		return
	end
	-- la cella di piazza più vicina al centro
	local mid = Vector3.new(sx / n, 0, sz / n)
	local best, bestD = cells[1], math.huge
	for _, c in cells do
		local d = (WorldConfig.borgoCell(c[1], c[2]) - mid).Magnitude
		if d < bestD then
			best, bestD = c, d
		end
	end
	local base = WorldConfig.borgoCell(best[1], best[2]) + Vector3.new(0, cellTop(best[1], best[2]) - 0.3, 0)
	local m = Instance.new("Model")
	m.Name = "Bacheca"
	for _, dx in { -2.6, 2.6 } do
		Build.block(base + Vector3.new(dx, 0, 0), Vector3.new(0.5, 6, 0.5), C.wood, Enum.Material.Wood, m)
	end
	Build.block(base + Vector3.new(0, 2.6, 0), Vector3.new(6, 3, 0.4), C.woodLight, Enum.Material.Wood, m).Name = "Tavola"
	for i = 1, 3 do
		Build.block(base + Vector3.new(-3.2 + i * 1.6, 3.2, 0.25), Vector3.new(1.1, 1.4, 0.05), Color3.fromRGB(250, 240, 214), Enum.Material.Fabric, m)
	end
	Build.roof(base + Vector3.new(0, 6, 0), 6.4, 1.6, 0.8, C.roof, m)
	local prompt = addPrompt(m, base + Vector3.new(0, 3, 2), "board", "bacheca")
	Build.label(prompt, "BLD_BACHECA", nil, 5, 140)
	m.Parent = folder
end

function WorldBuilder.build()
	setupLighting()
	local world = Instance.new("Folder")
	world.Name = "Mondo"
	world.Parent = workspace
	buildGround(world)
	local borgo = Instance.new("Folder")
	borgo.Name = "Borgo"
	borgo.Parent = world
	buildHill(borgo)
	local buildings = Instance.new("Folder")
	buildings.Name = "Edifici"
	buildings.Parent = borgo
	for _, lot in BorgoLayout.LOTS do
		local x, y, id, w, d = lot[1], lot[2], lot[3], lot[4], lot[5]
		if id ~= "" and GameData.BUILDINGS[id] then
			buildGameBuilding(buildings, id, x, y, w, d)
		else
			buildPlainHouse(buildings, x, y, w, d)
		end
	end
	buildBoard(borgo)
	return world
end

return WorldBuilder
