-- Pezzi base per costruire il mondo da codice: grafica provvisoria a blocchi,
-- come la grafica SVG provvisoria del prototipo Godot. I colori seguono
-- docs/art_direction.md del progetto Godot: colori mediterranei caldi e vivi.

local Build = {}

Build.COLORS = {
	grass = Color3.fromRGB(122, 171, 74),
	grassDark = Color3.fromRGB(92, 136, 58),
	grassLocked = Color3.fromRGB(104, 140, 76),
	soil = Color3.fromRGB(140, 94, 58),
	soilWet = Color3.fromRGB(96, 62, 38),
	soilQueued = Color3.fromRGB(176, 140, 92),
	stone = Color3.fromRGB(196, 178, 150),
	stoneDark = Color3.fromRGB(142, 128, 110),
	plaster = { Color3.fromRGB(236, 200, 150), Color3.fromRGB(230, 170, 120), Color3.fromRGB(240, 222, 186),
		Color3.fromRGB(214, 150, 110), Color3.fromRGB(242, 208, 128) },
	roof = Color3.fromRGB(184, 86, 52),
	wood = Color3.fromRGB(122, 82, 50),
	woodLight = Color3.fromRGB(170, 124, 80),
	leaf = Color3.fromRGB(66, 110, 48),
	olive = Color3.fromRGB(128, 144, 96),
	cypress = Color3.fromRGB(46, 84, 44),
	road = Color3.fromRGB(222, 206, 170),
	ivy = Color3.fromRGB(70, 104, 52),
	window = Color3.fromRGB(255, 214, 140),
	shutter = Color3.fromRGB(70, 110, 80),
}

export type PartProps = { [string]: any }

-- Crea un Part ancorato con le proprietà date.
function Build.part(props: PartProps, parent: Instance?): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "ClassName" then
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Blocco con la faccia di sotto in "base" (Vector3) e la dimensione data.
function Build.block(base: Vector3, size: Vector3, color: Color3, material: Enum.Material?, parent: Instance?): BasePart
	return Build.part({
		Size = size,
		CFrame = CFrame.new(base + Vector3.new(0, size.Y / 2, 0)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

function Build.ball(center: Vector3, diameter: number, color: Color3, parent: Instance?): BasePart
	return Build.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(center),
		Color = color,
		CanCollide = false,
	}, parent)
end

function Build.cylinder(base: Vector3, height: number, diameter: number, color: Color3, parent: Instance?): BasePart
	return Build.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		-- il cilindro di Roblox è lungo l'asse X: lo si mette in piedi
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
	}, parent)
end

-- Tetto a due falde sopra un rettangolo (centro della base del tetto, larghezza
-- lungo X, profondità lungo Z, altezza del colmo).
function Build.roof(center: Vector3, width: number, depth: number, height: number, color: Color3, parent: Instance?)
	local half = depth / 2
	for _, side in { 1, -1 } do
		Build.part({
			ClassName = "WedgePart",
			Size = Vector3.new(width + 0.8, height, half + 0.4),
			-- il WedgePart è alto sul retro (+Z) e scende verso il davanti (-Z):
			-- la falda sud (+Z) va girata, così il colmo resta al centro
			CFrame = CFrame.new(center + Vector3.new(0, height / 2, side * (half / 2 + 0.2)))
				* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			Color = color,
			Material = Enum.Material.Slate,
		}, parent)
	end
end

-- Albero tondo (quercia, castagno...) o ulivo.
function Build.tree(base: Vector3, scale: number, leaf: Color3, parent: Instance?)
	local m = Instance.new("Model")
	m.Name = "Tree"
	Build.cylinder(base, 3 * scale, 0.9 * scale, Build.COLORS.wood, m)
	Build.ball(base + Vector3.new(0, 4.2 * scale, 0), 4.4 * scale, leaf, m)
	Build.ball(base + Vector3.new(0.9 * scale, 3.6 * scale, 0.6 * scale), 3 * scale, leaf, m)
	m.Parent = parent
	return m
end

function Build.cypress(base: Vector3, scale: number, parent: Instance?)
	local m = Instance.new("Model")
	m.Name = "Cypress"
	Build.cylinder(base, 1.5 * scale, 0.6 * scale, Build.COLORS.wood, m)
	-- cilindro coricato lungo X e poi messo in piedi
	Build.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8 * scale, 2 * scale, 2 * scale),
		CFrame = CFrame.new(base + Vector3.new(0, 5.5 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Build.COLORS.cypress,
		CanCollide = false,
	}, m)
	m.Parent = parent
	return m
end

-- Etichetta sopra un oggetto. Il testo lo mette il client, nella lingua del
-- giocatore: attributi L10nKey (chiave) e L10nArg (argomento facoltativo).
function Build.label(adornee: BasePart, key: string, arg: string?, offsetY: number, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 120
	gui.Adornee = adornee
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 248, 232)
	text.TextStrokeTransparency = 0.3
	text.TextStrokeColor3 = Color3.fromRGB(70, 44, 24)
	text.Text = ""
	text:SetAttribute("L10nKey", key)
	if arg then
		text:SetAttribute("L10nArg", arg)
	end
	text.Parent = gui
	gui.Parent = adornee
	return gui
end

return Build
