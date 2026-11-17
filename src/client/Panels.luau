-- Le finestre del gioco, una alla volta al centro dello schermo:
--   shop        il Consorzio agrario: semi, alberi, concime, animali, strutture, decorazioni
--   orders      la bacheca: ordini degli abitanti e visitatori in paese
--   building    un edificio del borgo: la storia, il restauro, la produzione
--   land        un lotto di terra in vendita
--   structure   falegnameria o cucina posata sulla fattoria
--   warehouse   il magazzino, con la vendita dei prodotti
-- Porting di scenes/ui/*.gd e scenes/borgo/borgo.gd del progetto Godot.
-- Il contenuto si ricostruisce a ogni cambio di stato e ogni secondo (timer).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = require(Shared.GameData)
local Locale = require(Shared.Locale)
local Rules = require(Shared.Rules)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local C = Ui.C
local tr = Locale.tr
local act = ClientState.act

local Panels = {}

local gui: ScreenGui
local window: Frame
local titleLabel: TextLabel
local subLabel: TextLabel
local body: ScrollingFrame
local current: string? = nil
local arg: any = nil
local shopTab = "crops"

-- --- Finestra ---------------------------------------------------------------------

function Panels.init(screen: ScreenGui)
	gui = screen
	window = Ui.card(gui, UDim2.fromOffset(560, 0))
	window.Name = "Panel"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0, 560, 0.72, 0)
	window.Visible = false
	window.ZIndex = 10
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(math.huge, 620)
	size.Parent = window
	Ui.padding(window, 14)

	titleLabel = Ui.label(window, "", 26, C.terracottaDark)
	titleLabel.Size = UDim2.new(1, -40, 0, 30)
	titleLabel.AutomaticSize = Enum.AutomaticSize.None
	subLabel = Ui.label(window, "", 16, C.inkSoft, true)
	subLabel.Position = UDim2.fromOffset(0, 32)
	subLabel.Size = UDim2.new(1, -40, 0, 20)
	subLabel.AutomaticSize = Enum.AutomaticSize.None

	local close = Ui.button(window, "X", "secondary", function()
		Panels.close()
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.AutomaticSize = Enum.AutomaticSize.None
	close.Size = UDim2.fromOffset(36, 36)

	body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(0, 60)
	body.Size = UDim2.new(1, 0, 1, -60)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = C.border
	Ui.list(body, false, 8)
	body.Parent = window

	ClientState.changed:Connect(function()
		Panels.render()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			Panels.render()
		end
	end)
end

function Panels.open(name: string, a: any?)
	current = name
	arg = a
	window.Visible = true
	body.CanvasPosition = Vector2.zero
	Panels.render()
end

function Panels.toggle(name: string)
	if current == name then
		Panels.close()
	else
		Panels.open(name)
	end
end

function Panels.close()
	current = nil
	window.Visible = false
end

function Panels.isOpen(): boolean
	return current ~= nil
end

-- --- Pezzi comuni -----------------------------------------------------------------

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function text(parent: Instance, s: string, size: number?, color: Color3?, bodyFont: boolean?): TextLabel
	local t = Ui.label(parent, s, size or 17, color, bodyFont)
	t.LayoutOrder = nextOrder()
	return t
end

local function section(s: string)
	local t = text(body, s, 20, C.terracottaDark)
	t.Size = UDim2.new(1, 0, 0, 0)
end

-- Riquadro di una voce, con colonna di testo a sinistra e pulsanti a destra.
local function entry(): (Frame, Frame, Frame)
	local card = Ui.card(body, UDim2.new(1, -8, 0, 0))
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Color3.fromHex("fffaf0")
	card.LayoutOrder = nextOrder()
	Ui.padding(card, 10)
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.new(1, -170, 0, 0)
	left.AutomaticSize = Enum.AutomaticSize.Y
	Ui.list(left, false, 4)
	left.Parent = card
	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, 0, 0.5, 0)
	right.Size = UDim2.fromOffset(165, 0)
	right.AutomaticSize = Enum.AutomaticSize.Y
	Ui.list(right, false, 6, Enum.HorizontalAlignment.Right)
	right.Parent = card
	return card, left, right
end

local function button(parent: Instance, s: string, style: string, enabled: boolean, onClick: () -> ())
	local b = Ui.button(parent, s, style, function() end)
	Ui.setEnabled(b, enabled)
	b.Activated:Connect(function()
		if Ui.isEnabled(b) then
			onClick()
		end
	end)
	return b
end

-- "3 pomodori (2)": quantità chiesta e quante ne hai.
local function itemsLine(s: any, items: { [string]: number }): string
	local parts = {}
	for product, qty in items do
		table.insert(parts, string.format("%d %s (%d)", qty, string.lower(Locale.item(product)), Rules.itemCount(s, product)))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function kindName(kind: string): string
	return tr("KIND_" .. string.upper(kind))
end

-- --- Negozio ------------------------------------------------------------------------

local SHOP_TABS = {
	{ id = "crops", key = "SHOP_TAB_CROPS" },
	{ id = "trees", key = "SHOP_TAB_TREES" },
	{ id = "fertilizer", key = "SHOP_TAB_FERTILIZER" },
	{ id = "animals", key = "SHOP_TAB_ANIMALS" },
	{ id = "structures", key = "SHOP_TAB_STRUCTURES" },
	{ id = "decor", key = "SHOP_TAB_DECOR" },
}

local function startPlacing(kind: string, typ: string)
	ClientState.placing = { kind = kind, type = typ }
	Panels.close()
	ClientState.notify()
end

local function renderShop(s: any)
	titleLabel.Text = tr("SHOP_TITLE")
	subLabel.Text = tr("SHOP_SUBTITLE")
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 0)
	tabs.AutomaticSize = Enum.AutomaticSize.Y
	tabs.LayoutOrder = nextOrder()
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.333, -6, 0, 34)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tabs
	tabs.Parent = body
	for i, t in SHOP_TABS do
		local b = Ui.button(tabs, tr(t.key), if shopTab == t.id then "primary" else "secondary", function()
			shopTab = t.id
			Panels.render()
		end)
		b.LayoutOrder = i
		b.TextSize = 15
		b.AutomaticSize = Enum.AutomaticSize.None
	end

	if shopTab == "crops" or shopTab == "trees" then
		for _, id in GameData.allPlants() do
			local c = GameData.CROPS[id]
			local isTree = c.kind ~= "crop"
			if isTree ~= (shopTab == "trees") then
				continue
			end
			local _, left, right = entry()
			text(left, Locale.crop(id), 19)
			text(left, tr("SHOP_DETAIL", kindName(c.kind), GameData.formatTime(c.time), c.yield,
				string.lower(Locale.product(c.product)), c.sell_price), 14, C.inkSoft, true)
			if isTree then
				text(left, tr("SHOP_PERENNIAL"), 14, C.oliveDark, true)
			end
			text(left, tr("SHOP_PRICE", c.seed_cost) .. " · " .. tr("SHOP_OWNED", Rules.seedCount(s, id)), 14, C.inkSoft, true)
			if Rules.isUnlocked(s, id) then
				for _, qty in { 1, 5 } do
					button(right, tr("SHOP_BUY_QTY", qty), "primary", s.coins >= c.seed_cost * qty, function()
						act("buySeeds", id, qty)
						ClientState.setTool("seed", id)
					end)
				end
			else
				text(right, tr("SHOP_UNLOCK", c.level), 15, C.inkSoft).TextXAlignment = Enum.TextXAlignment.Right
			end
		end
	elseif shopTab == "fertilizer" then
		local _, left, right = entry()
		text(left, tr("TOOL_FERTILIZER"), 19)
		text(left, tr("SHOP_FERTILIZER_DESC"), 14, C.inkSoft, true)
		text(left, tr("SHOP_PRICE", GameData.FERTILIZER_PRICE) .. " · " .. tr("SHOP_OWNED", s.fertilizer), 14, C.inkSoft, true)
		if s.level >= GameData.FERTILIZER_LEVEL then
			for _, qty in { 1, 5 } do
				button(right, tr("SHOP_BUY_QTY", qty), "primary", s.coins >= GameData.FERTILIZER_PRICE * qty, function()
					act("buyFertilizer", qty)
				end)
			end
		else
			text(right, tr("SHOP_UNLOCK", GameData.FERTILIZER_LEVEL), 15, C.inkSoft)
		end
	elseif shopTab == "animals" then
		do
			local _, left, right = entry()
			text(left, tr("SHOP_BIBERON"), 19)
			text(left, tr("SHOP_BIBERON_DESC"), 14, C.inkSoft, true)
			text(left, tr("SHOP_PRICE", GameData.BIBERON_PRICE) .. " · " .. tr("SHOP_OWNED", s.biberon), 14, C.inkSoft, true)
			for _, qty in { 1, 5 } do
				button(right, tr("SHOP_BUY_QTY", qty), "primary", s.coins >= GameData.BIBERON_PRICE * qty, function()
					act("buyBiberon", qty)
				end)
			end
		end
		for _, id in GameData.ANIMAL_ORDER do
			local a = GameData.ANIMALS[id]
			local _, left, right = entry()
			text(left, Locale.animal(id, true) .. " · " .. Locale.animal(id), 19)
			text(left, tr("SHOP_ANIMAL_DESC", a.bottles, string.lower(Locale.product(a.product))), 14, C.inkSoft, true)
			text(left, tr("SHOP_PRICE", a.price), 14, C.inkSoft, true)
			if s.level >= a.level then
				button(right, tr("SHOP_BUY_PLACE"), "primary", s.coins >= a.price, function()
					startPlacing("animal", id)
				end)
			else
				text(right, tr("SHOP_UNLOCK", a.level), 15, C.inkSoft)
			end
		end
	elseif shopTab == "structures" then
		for _, id in GameData.STRUCTURE_ORDER do
			local st = GameData.STRUCTURES[id]
			local _, left, right = entry()
			text(left, Locale.structure(id), 19)
			text(left, tr("STRUCT_DESC_" .. string.upper(id)), 14, C.inkSoft, true)
			text(left, tr("SHOP_PRICE", st.price), 14, C.inkSoft, true)
			if s.level >= st.level then
				button(right, tr("SHOP_BUY_PLACE"), "primary", s.coins >= st.price, function()
					startPlacing("structure", id)
				end)
			else
				text(right, tr("SHOP_UNLOCK", st.level), 15, C.inkSoft)
			end
		end
	elseif shopTab == "decor" then
		local any = false
		for _, id in GameData.DECOR do
			local n = s.decor_inv[id] or 0
			if n > 0 then
				any = true
				local _, left, right = entry()
				text(left, string.format("%s ×%d", Locale.recipe(id), n), 19)
				button(right, tr("SHOP_DECOR_PLACE"), "primary", true, function()
					startPlacing("decor", id)
				end)
			end
		end
		if not any then
			text(body, tr("SHOP_DECOR_NONE"), 16, C.inkSoft, true)
		end
	end
end

-- --- Bacheca: ordini e visitatori ----------------------------------------------------

local function stars(r: number): string
	return tr("UI_RATING_N", r)
end

local function renderOrders(s: any)
	titleLabel.Text = tr("BORGO_ORDERS")
	subLabel.Text = tr("BORGO_ORDERS_SUB")
	for i, o in s.orders do
		local _, left, right = entry()
		text(left, tr("BORGO_ASKS", o.giver), 19)
		text(left, tr("ORDER_WHY_" .. tostring(o.why or 0)), 14, C.inkSoft, true)
		text(left, itemsLine(s, o.items), 16)
		text(left, tr("ORDER_REWARD", o.coins, o.xp), 14, C.oliveDark, true)
		button(right, tr("BORGO_DELIVER"), "primary", Rules.canFulfill(s, i), function()
			act("fulfillOrder", i)
		end)
	end
	section(tr("BORGO_TOURISTS"))
	text(body, string.format("%s: %s · %s", tr("UI_RATING"), stars(Rules.rating(s)), tr("UI_VISITORS", s.visitors_today)), 15, C.inkSoft, true)
	if not Rules.tourismActive(s) or #s.tourists == 0 then
		text(body, tr("BORGO_NO_TOURISTS"), 15, C.inkSoft, true)
	end
	for i, t in s.tourists do
		local _, left, right = entry()
		text(left, tr("BORGO_TOURIST_ASKS", tr("TOURIST_" .. string.upper(t.type)), t.size), 18)
		text(left, itemsLine(s, t.items), 16)
		text(left, tr("SHOP_PRICE", t.coins) .. " · " .. tr("BORGO_LEAVES", GameData.formatTime(t.leaves - Rules.now())), 14, C.inkSoft, true)
		button(right, tr("BORGO_SERVE"), "primary", Rules.canServeTourist(s, i), function()
			act("serveTourist", i)
		end)
	end
end

-- --- Edificio del borgo ----------------------------------------------------------------

local function renderBuilding(s: any, id: string)
	local b = GameData.BUILDINGS[id]
	titleLabel.Text = Locale.building(id)
	subLabel.Text = Locale.resident(id)
	if not Rules.isRestored(s, id) then
		text(body, "\"" .. Locale.story(id) .. "\"", 17, C.ink, true)
		section(tr("BUILDING_NEEDS"))
		local need = { string.format("%s: %d (%d)", tr("UI_COINS"), b.restore.coins, s.coins) }
		table.insert(need, itemsLine(s, b.restore.items))
		text(body, table.concat(need, "\n"), 17)
		text(body, tr("BUILDING_RETURNS", b.pop[1], b.pop[2], b.pop[3]), 15, C.oliveDark, true)
		if s.level < b.level then
			text(body, tr("BUILDING_LOCKED", b.level), 16, C.terracottaDark)
		end
		local row = Ui.row(body)
		row.LayoutOrder = nextOrder()
		button(row, tr("BUILDING_RESTORE"), "primary", Rules.canRestore(s, id), function()
			act("restore", id)
		end)
		return
	end
	local lines = GameData.BUILDING_LINES[id]
	if lines then
		text(body, "\"" .. tr(string.format("LINE_%s_%d", string.upper(id), os.time() // 8 % lines)) .. "\"", 17, C.ink, true)
	end
	text(body, tr("BUILDING_THANKS"), 15, C.oliveDark, true)
	if b.effect then
		text(body, Locale.effect(b.effect), 17)
		return
	end
	local product = GameData.buildingProduct(id) :: string
	section(tr("BUILDING_MAKES", string.lower(Locale.item(product))))
	text(body, string.format("%s  >  1 %s · %s", itemsLine(s, b.recipe.input), string.lower(Locale.item(product)),
		GameData.formatTime(b.recipe.time)), 16)
	text(body, tr("BUILDING_IN_STORE", Rules.itemCount(s, product)), 15, C.inkSoft, true)
	local row = Ui.row(body)
	row.LayoutOrder = nextOrder()
	if s.productions[id] then
		local progress = Rules.productionProgress(s, id)
		if progress >= 1 then
			text(body, tr("BUILDING_READY"), 16, C.oliveDark)
			button(row, tr("PANEL_COLLECT"), "green", true, function()
				act("collectProduction", id)
			end)
		else
			local bar, fill = Ui.bar(body, 12)
			bar.LayoutOrder = nextOrder()
			Ui.setBar(fill, progress)
			local left = b.recipe.time * (1 - progress)
			text(body, tr("PANEL_WORKING", GameData.formatTime(left)), 15, C.inkSoft, true)
		end
	else
		button(row, tr("BUILDING_START"), "primary", Rules.hasItems(s, b.recipe.input), function()
			act("startProduction", id)
		end)
	end
end

-- --- Terreno in vendita ----------------------------------------------------------------

local function renderLand(s: any, a: any)
	local sx, sy = a.sx, a.sy
	titleLabel.Text = tr("LAND_TITLE")
	subLabel.Text = tr("LAND_SUB")
	local cost = Rules.sectorCost(sx, sy)
	if not cost or Rules.isSectorOwned(s, sx, sy) then
		Panels.close()
		return
	end
	if not Rules.isSectorBuyable(s, sx, sy) then
		text(body, tr("LAND_NOT_ADJACENT"), 17, C.terracottaDark)
	end
	section(tr("LAND_NEED"))
	local lines = {
		string.format("%s (%d)", tr("LAND_LEVEL", cost.level), s.level),
		string.format("%s: %d (%d)", tr("UI_COINS"), cost.coins, s.coins),
	}
	for _, id in GameData.ANTIQUE_ORDER do
		local n = cost.antiques[id]
		if n then
			table.insert(lines, string.format("%d %s (%d)", n, Locale.antique(id), Rules.antiqueCount(s, id)))
		end
	end
	text(body, table.concat(lines, "\n"), 17)
	text(body, tr("LAND_HINT"), 14, C.inkSoft, true)
	local row = Ui.row(body)
	row.LayoutOrder = nextOrder()
	button(row, tr("LAND_BUY"), "primary", Rules.canBuySector(s, sx, sy), function()
		act("buySector", sx, sy)
		Panels.close()
	end)
end

-- --- Strutture sulla fattoria ----------------------------------------------------------

local function sellList(s: any)
	section(tr("PANEL_SELL_TITLE"))
	local any = false
	for _, product in GameData.SELL_ORDER do
		local n = Rules.itemCount(s, product)
		if n > 0 then
			any = true
			local _, left, right = entry()
			text(left, string.format("%s ×%d", Locale.item(product), n), 18)
			text(left, tr("SHOP_PRICE", GameData.SELL_PRICES[product]), 14, C.inkSoft, true)
			button(right, tr("PANEL_SELL"), "green", true, function()
				act("sell", product, 1)
			end)
		end
	end
	if not any then
		text(body, tr("PANEL_NOTHING_TO_SELL"), 15, C.inkSoft, true)
	end
end

local function renderStructure(s: any, uid: number)
	local o = Rules.getObject(s, uid)
	if not o then
		Panels.close()
		return
	end
	titleLabel.Text = Locale.structure(o.type)
	subLabel.Text = tr("STRUCT_DESC_" .. string.upper(o.type))
	if o.recipe then
		local progress = Rules.recipeProgress(s, uid)
		local r = GameData.RECIPES[o.recipe]
		local _, left, right = entry()
		text(left, tr("PANEL_WORKING", Locale.recipe(o.recipe)), 18)
		if progress >= 1 then
			button(right, tr("PANEL_COLLECT"), "green", true, function()
				act("collectRecipe", uid)
			end)
		else
			local bar, fill = Ui.bar(left, 10)
			bar.LayoutOrder = 99
			Ui.setBar(fill, progress)
			text(left, GameData.formatTime(r.time * (1 - progress)), 14, C.inkSoft, true)
		end
	end
	for _, rid in GameData.STRUCTURES[o.type].recipes do
		local r = GameData.RECIPES[rid]
		local _, left, right = entry()
		text(left, Locale.recipe(rid), 18)
		local cost = {}
		if next(r.input) then
			table.insert(cost, itemsLine(s, r.input))
		end
		if r.coins > 0 then
			table.insert(cost, tr("SHOP_PRICE", r.coins))
		end
		if r.espresso > 0 then
			table.insert(cost, string.format("%d %s", r.espresso, tr("UI_ESPRESSO")))
		end
		table.insert(cost, GameData.formatTime(r.time))
		text(left, table.concat(cost, " · "), 14, C.inkSoft, true)
		button(right, tr("PANEL_MAKE"), "primary", Rules.canStartRecipe(s, uid, rid), function()
			act("startRecipe", uid, rid)
		end)
	end
	if o.type == "cucina" then
		sellList(s)
	end
end

-- --- Magazzino ------------------------------------------------------------------------

local function renderWarehouse(s: any)
	titleLabel.Text = tr("UI_WAREHOUSE")
	subLabel.Text = ""
	local items = {}
	for product, n in s.inventory do
		if n > 0 then
			table.insert(items, string.format("%s ×%d", Locale.item(product), n))
		end
	end
	table.sort(items)
	text(body, if #items > 0 then table.concat(items, " · ") else tr("UI_WAREHOUSE_EMPTY"), 17)
	local seeds = {}
	for crop, n in s.seeds do
		table.insert(seeds, string.format("%s ×%d", Locale.crop(crop), n))
	end
	table.sort(seeds)
	if #seeds > 0 then
		section(tr("UI_SEEDS"))
		text(body, table.concat(seeds, " · "), 16)
	end
	local ant = {}
	for _, id in GameData.ANTIQUE_ORDER do
		local n = Rules.antiqueCount(s, id)
		if n > 0 then
			table.insert(ant, string.format("%s ×%d", Locale.antique(id), n))
		end
	end
	section(tr("UI_ANTIQUES"))
	text(body, if #ant > 0 then table.concat(ant, " · ") else "-", 16)
	sellList(s)
end

-- --- Disegno --------------------------------------------------------------------------

function Panels.render()
	if not current or not window then
		return
	end
	local s = ClientState.state
	if not s then
		return
	end
	local scroll = body.CanvasPosition
	Ui.clear(body)
	order = 0
	if current == "shop" then
		renderShop(s)
	elseif current == "orders" then
		renderOrders(s)
	elseif current == "building" then
		renderBuilding(s, arg)
	elseif current == "land" then
		renderLand(s, arg)
	elseif current == "structure" then
		renderStructure(s, arg)
	elseif current == "warehouse" then
		renderWarehouse(s)
	end
	body.CanvasPosition = scroll
end

-- Un edificio appena restaurato: torna il suo abitante.
function Panels.onRestored(id: string)
	if current == "building" and arg == id then
		Panels.render()
	end
end

return Panels
