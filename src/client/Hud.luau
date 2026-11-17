-- L'interfaccia sempre visibile (equivalente dell'HUD di scenes/main.gd):
-- in alto livello, monete, Nostalgie, gocce, espresso e abitanti del borgo;
-- in basso gli strumenti, i semi e i pulsanti Negozio, Ordini, Magazzino,
-- Fattoria e Borgo; al centro i messaggi.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = require(Shared.GameData)
local Locale = require(Shared.Locale)
local Rules = require(Shared.Rules)

local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Panels)
local Ui = require(script.Parent.Ui)

local C = Ui.C
local Hud = {}

local gui: ScreenGui
local refs: { [string]: any } = {}

-- --- Messaggi -------------------------------------------------------------------

local toastBox: Frame

function Hud.toast(text: string)
	local card = Ui.card(toastBox, UDim2.fromOffset(0, 0))
	card.AutomaticSize = Enum.AutomaticSize.XY
	card.BackgroundColor3 = C.cream
	Ui.padding(card, 10)
	local t = Ui.label(card, text, 18)
	t.Size = UDim2.fromOffset(0, 0)
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.TextWrapped = false
	task.delay(3.5, function()
		if card.Parent then
			local tween = TweenService:Create(card, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
			TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			tween:Play()
			tween.Completed:Wait()
			card:Destroy()
		end
	end)
	-- al massimo 4 messaggi insieme
	local cards = {}
	for _, c in toastBox:GetChildren() do
		if c:IsA("Frame") then
			table.insert(cards, c)
		end
	end
	if #cards > 4 then
		cards[1]:Destroy()
	end
end

-- --- Costruzione ----------------------------------------------------------------

local TOOLS = {
	{ id = "hand", key = "TOOL_HAND" },
	{ id = "hoe", key = "TOOL_HOE" },
	{ id = "seed", key = "TOOL_SEED" },
	{ id = "water", key = "TOOL_WATER" },
	{ id = "fertilizer", key = "TOOL_FERTILIZER" },
}

local function dot(parent: GuiObject): Frame
	local d = Instance.new("Frame")
	d.Name = "Dot"
	d.Size = UDim2.fromOffset(14, 14)
	d.Position = UDim2.new(1, -6, 0, -6)
	d.BackgroundColor3 = Color3.fromRGB(230, 60, 40)
	d.BorderSizePixel = 0
	d.Visible = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = d
	d.Parent = parent
	return d
end

local function buildTop()
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.Position = UDim2.fromOffset(12, 12)
	top.Size = UDim2.new(1, -24, 0, 40)
	Ui.list(top, true, 8)
	top.Parent = gui

	-- livello con la barra dell'esperienza
	local lv = Ui.card(top, UDim2.fromOffset(190, 40))
	Ui.padding(lv, 6)
	local lvText = Ui.label(lv, "", 15)
	lvText.Size = UDim2.new(1, 0, 0, 16)
	lvText.AutomaticSize = Enum.AutomaticSize.None
	local _, xpFill = Ui.bar(lv, 8)
	xpFill.Parent.Position = UDim2.fromOffset(0, 20)
	refs.level = lvText
	refs.xp = xpFill

	local function pill(name: string, color: Color3?)
		local f, t = Ui.pill(top, color)
		f.Size = UDim2.fromOffset(0, 40)
		refs[name] = t
		return f
	end
	pill("coins", Color3.fromHex("fff1c9"))
	pill("nostalgie", Color3.fromHex("f6e2f0"))
	pill("water", Color3.fromHex("e3f1fb"))
	pill("espresso", Color3.fromHex("efe2d2"))
	pill("population", Color3.fromHex("e8f2d8"))

	-- lingua, in alto a destra
	local lang = Ui.button(gui, "", "secondary", function()
		local langs = Locale.langs()
		local i = table.find(langs, Locale.current()) or 1
		Locale.setLang(langs[i % #langs + 1])
		Hud.refresh()
		ClientState.notify()
	end)
	lang.AnchorPoint = Vector2.new(1, 0)
	lang.Position = UDim2.new(1, -12, 0, 12)
	refs.lang = lang
end

local function buildBottom()
	local bottom = Instance.new("Frame")
	bottom.Name = "Bottom"
	bottom.BackgroundTransparency = 1
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -12)
	bottom.Size = UDim2.new(1, -24, 0, 44)
	Ui.list(bottom, true, 8, Enum.HorizontalAlignment.Center)
	bottom.Parent = gui

	refs.tools = {}
	for i, t in TOOLS do
		local b = Ui.button(bottom, "", "secondary", function()
			if t.id == "seed" then
				refs.seeds.Visible = not refs.seeds.Visible or ClientState.tool ~= "seed"
			else
				refs.seeds.Visible = false
			end
			ClientState.setTool(t.id)
		end)
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(0, 44)
		refs.tools[t.id] = b
	end
	local gap = Instance.new("Frame")
	gap.BackgroundTransparency = 1
	gap.Size = UDim2.fromOffset(16, 1)
	gap.LayoutOrder = 10
	gap.Parent = bottom
	local function nav(name: string, order: number, style: string, onClick: () -> ())
		local b = Ui.button(bottom, "", style, onClick)
		b.LayoutOrder = order
		b.Size = UDim2.fromOffset(0, 44)
		refs[name] = b
		refs[name .. "Dot"] = dot(b)
	end
	nav("shop", 11, "primary", function()
		Panels.toggle("shop")
	end)
	nav("orders", 12, "primary", function()
		Panels.toggle("orders")
	end)
	nav("store", 13, "secondary", function()
		Panels.toggle("warehouse")
	end)
	nav("farm", 14, "green", function()
		Panels.close()
		ClientState.act("goto", "farm")
	end)
	nav("borgo", 15, "green", function()
		Panels.close()
		ClientState.act("goto", "borgo")
	end)

	-- semi: si aprono sopra la barra
	local seeds = Ui.card(gui, UDim2.fromOffset(0, 0))
	seeds.Name = "Seeds"
	seeds.AnchorPoint = Vector2.new(0.5, 1)
	seeds.Position = UDim2.new(0.5, 0, 1, -66)
	seeds.AutomaticSize = Enum.AutomaticSize.XY
	seeds.Visible = false
	Ui.padding(seeds, 8)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(130, 34)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirectionMaxCells = 6
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = seeds
	refs.seeds = seeds
end

local function buildPlacing()
	local f = Ui.card(gui, UDim2.fromOffset(0, 0))
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -66)
	f.Visible = false
	Ui.padding(f, 8)
	Ui.list(f, true, 10)
	local t = Ui.label(f, "", 18)
	t.Size = UDim2.fromOffset(0, 0)
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.TextWrapped = false
	local cancel = Ui.button(f, "", "secondary", function()
		ClientState.placing = nil
		ClientState.notify()
	end)
	refs.placing = f
	refs.placingText = t
	refs.placingCancel = cancel
end

local function buildLoading()
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = C.cream
	f.ZIndex = 50
	local title = Ui.label(f, "Terra Mia", 64, C.terracotta)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.42)
	title.Size = UDim2.fromOffset(600, 0)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 51
	local sub = Ui.label(f, Locale.tr("UI_LOADING"), 22, C.inkSoft)
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.52)
	sub.Size = UDim2.fromOffset(600, 0)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.ZIndex = 51
	f.Parent = gui
	refs.loading = f
end

function Hud.init(screen: ScreenGui)
	gui = screen
	toastBox = Instance.new("Frame")
	toastBox.Name = "Toasts"
	toastBox.BackgroundTransparency = 1
	toastBox.AnchorPoint = Vector2.new(0.5, 0)
	toastBox.Position = UDim2.new(0.5, 0, 0, 64)
	toastBox.Size = UDim2.new(0.8, 0, 0, 200)
	Ui.list(toastBox, false, 6, Enum.HorizontalAlignment.Center)
	toastBox.ZIndex = 20
	toastBox.Parent = gui
	buildTop()
	buildBottom()
	buildPlacing()
	buildLoading()
	ClientState.changed:Connect(Hud.refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			Hud.refresh()
		end
	end)
	Hud.refresh()
end

-- --- Aggiornamento --------------------------------------------------------------

local lastSeedsSig = ""

local function refreshSeeds(s: any)
	local unlocked = GameData.plantableCrops(s.level)
	local parts = {}
	for _, id in unlocked do
		table.insert(parts, id .. Rules.seedCount(s, id))
	end
	local sig = table.concat(parts, ",") .. ClientState.crop .. Locale.current()
	if sig == lastSeedsSig then
		return
	end
	lastSeedsSig = sig
	Ui.clear(refs.seeds)
	local any = false
	for i, id in unlocked do
		local n = Rules.seedCount(s, id)
		if n <= 0 then
			continue
		end
		any = true
		local b = Ui.button(refs.seeds, string.format("%s ×%d", Locale.crop(id), n), if id == ClientState.crop then "green" else "secondary", function()
			ClientState.setTool("seed", id)
			refs.seeds.Visible = false
		end)
		b.LayoutOrder = i
		b.TextSize = 16
		b.AutomaticSize = Enum.AutomaticSize.None
	end
	if not any then
		local t = Ui.label(refs.seeds, Locale.tr("UI_NO_SEEDS"), 16)
		t.Size = UDim2.fromOffset(260, 34)
		t.AutomaticSize = Enum.AutomaticSize.None
	end
end

function Hud.refresh()
	if not gui then
		return
	end
	local s = ClientState.state
	refs.lang.Text = Locale.raw("LANG_NAME")
	refs.loading.Visible = s == nil
	for _, t in TOOLS do
		local b = refs.tools[t.id]
		local text = Locale.tr(t.key)
		if t.id == "seed" and s then
			text = string.format("%s: %s ×%d", text, Locale.crop(ClientState.crop), Rules.seedCount(s, ClientState.crop))
		elseif t.id == "fertilizer" and s then
			text = Locale.tr("TOOL_FERTILIZER_N", s.fertilizer)
		end
		b.Text = text
		b.BackgroundColor3 = if ClientState.tool == t.id then Color3.fromHex("ffe6a8") else Color3.fromHex("fffaf0")
	end
	refs.shop.Text = Locale.tr("UI_SHOP")
	refs.orders.Text = Locale.tr("UI_ORDERS")
	refs.store.Text = Locale.tr("UI_WAREHOUSE")
	refs.farm.Text = Locale.tr("UI_FARM")
	refs.borgo.Text = Locale.tr("UI_BORGO")
	refs.placingCancel.Text = Locale.tr("PLACE_CANCEL")
	refs.placing.Visible = ClientState.placing ~= nil
	refs.placingText.Text = Locale.tr("PLACE_HINT")
	if ClientState.placing then
		refs.seeds.Visible = false
	end
	if not s then
		return
	end
	local nextXp = GameData.xpForLevel(s.level + 1)
	refs.level.Text = if s.level >= GameData.MAX_LEVEL then Locale.tr("UI_LEVEL_MAX")
		else Locale.tr("UI_LEVEL_XP", s.level, s.xp, nextXp)
	Ui.setBar(refs.xp, Rules.xpProgress(s))
	refs.coins.Text = string.format("%s %d", Locale.tr("UI_COINS"), s.coins)
	refs.nostalgie.Text = string.format("%s %d", Locale.tr("UI_NOSTALGIE"), s.nostalgie)
	local water = string.format("%s %d/%d", Locale.tr("UI_WATER"), s.water, GameData.WATER_MAX)
	local nextDrop = Rules.waterSecondsToNext(s)
	if nextDrop > 0 then
		water ..= "  " .. Locale.tr("UI_WATER_NEXT", GameData.formatTime(nextDrop))
	end
	refs.water.Text = water
	refs.espresso.Text = string.format("%s %d/%d", Locale.tr("UI_ESPRESSO"), s.espresso, GameData.MOKA_MAX)
	refs.population.Text = string.format("%s %d/%d", Locale.tr("UI_POPULATION"), Rules.population(s), GameData.maxPopulation())
	refs.ordersDot.Visible = Rules.anyOrderReady(s)
	refs.borgoDot.Visible = Rules.anyRestorable(s)
	refs.shopDot.Visible = false
	refs.storeDot.Visible = false
	refs.farmDot.Visible = false
	refreshSeeds(s)
end

-- Messaggi ed eventi arrivati dal server.
function Hud.onMessages(list: { any })
	for _, m in list do
		if m.kind == "toast" then
			Hud.toast(Locale.message(m.data))
		elseif m.kind == "restored" then
			Panels.onRestored(m.data.id)
		end
	end
end

Hud.player = Players.LocalPlayer

return Hud
