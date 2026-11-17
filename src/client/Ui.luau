-- Pezzi d'interfaccia riusati (equivalente di scripts/ui/ui_kit.gd e del
-- tema tools/build_theme.gd del progetto Godot): stessi colori, font Fredoka.
-- Gli stili stanno qui, non sparsi nei pannelli.

local Ui = {}

Ui.C = {
	cream = Color3.fromHex("fbf3e2"),
	creamDark = Color3.fromHex("f1e3c6"),
	parchment = Color3.fromHex("e9d6b0"),
	border = Color3.fromHex("c9a97a"),
	ink = Color3.fromHex("4a3423"),
	inkSoft = Color3.fromHex("7a5e44"),
	terracotta = Color3.fromHex("d0643c"),
	terracottaDark = Color3.fromHex("a94c2a"),
	olive = Color3.fromHex("7c9a3c"),
	oliveDark = Color3.fromHex("5e7a28"),
	disabled = Color3.fromHex("d9ccb4"),
	wood = Color3.fromHex("8a5a2b"),
	white = Color3.new(1, 1, 1),
}

Ui.FONT = Enum.Font.FredokaOne
Ui.FONT_BODY = Enum.Font.Gotham

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

function Ui.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
end

function Ui.list(parent: Instance, horizontal: boolean?, gap: number?, align: Enum.HorizontalAlignment?)
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

-- Riquadro color crema con bordo, come le "Card" del tema Godot.
function Ui.card(parent: Instance?, size: UDim2?): Frame
	local f = Instance.new("Frame")
	f.Size = size or UDim2.fromScale(1, 0)
	f.BackgroundColor3 = Ui.C.cream
	f.BorderSizePixel = 0
	corner(f, 14)
	stroke(f, Ui.C.border, 2)
	f.Parent = parent
	return f
end

-- Pastiglia per i contatori in alto (monete, gocce...).
function Ui.pill(parent: Instance?, color: Color3?): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 34)
	f.BackgroundColor3 = color or Ui.C.cream
	f.BorderSizePixel = 0
	corner(f, 17)
	stroke(f, Ui.C.border, 2)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 12)
	p.PaddingRight = UDim.new(0, 12)
	p.Parent = f
	local t = Ui.label(f, "", 18)
	t.Size = UDim2.fromScale(0, 1)
	t.AutomaticSize = Enum.AutomaticSize.X
	f.Parent = parent
	return f, t
end

function Ui.label(parent: Instance?, text: string, size: number?, color: Color3?, body: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = if body then Ui.FONT_BODY else Ui.FONT
	t.TextSize = size or 18
	t.TextColor3 = color or Ui.C.ink
	t.Text = text
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Parent = parent
	return t
end

-- Pulsante: "primary" terracotta, "secondary" crema, "tool" per la barra.
function Ui.button(parent: Instance?, text: string, style: string?, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Font = Ui.FONT
	b.TextSize = 18
	b.Text = text
	b.Size = UDim2.fromOffset(0, 38)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.BorderSizePixel = 0
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 14)
	p.PaddingRight = UDim.new(0, 14)
	p.Parent = b
	corner(b, 12)
	if style == "primary" then
		b.BackgroundColor3 = Ui.C.terracotta
		b.TextColor3 = Ui.C.white
		stroke(b, Ui.C.terracottaDark, 2)
	elseif style == "green" then
		b.BackgroundColor3 = Ui.C.olive
		b.TextColor3 = Ui.C.white
		stroke(b, Ui.C.oliveDark, 2)
	else
		b.BackgroundColor3 = Color3.fromHex("fffaf0")
		b.TextColor3 = Ui.C.ink
		stroke(b, Ui.C.wood, 2)
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	b.Parent = parent
	return b
end

function Ui.setEnabled(b: TextButton, enabled: boolean)
	b.Active = enabled
	b.AutoButtonColor = enabled
	b:SetAttribute("Enabled", enabled)
	b.BackgroundTransparency = if enabled then 0 else 0.45
	b.TextTransparency = if enabled then 0 else 0.4
end

function Ui.isEnabled(b: TextButton): boolean
	return b:GetAttribute("Enabled") ~= false
end

-- Barra di avanzamento 0..1.
function Ui.bar(parent: Instance?, height: number?, color: Color3?): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, height or 10)
	back.BackgroundColor3 = Ui.C.parchment
	back.BorderSizePixel = 0
	corner(back, (height or 10) // 2)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color or Ui.C.olive
	fill.BorderSizePixel = 0
	corner(fill, (height or 10) // 2)
	fill.Parent = back
	back.Parent = parent
	return back, fill
end

function Ui.setBar(fill: Frame, value: number)
	fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
end

-- Riga orizzontale che si allarga col contenuto.
function Ui.row(parent: Instance?, gap: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	Ui.list(f, true, gap or 8)
	f.Parent = parent
	return f
end

function Ui.clear(container: Instance)
	for _, c in container:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

return Ui
