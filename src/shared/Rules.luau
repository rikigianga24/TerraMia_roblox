-- Regole della partita: monete, esperienza, magazzino, quadranti, ordini, borgo.
-- Porting di scripts/autoload/game_state.gd del progetto Godot.
--
-- Lo stato di un giocatore è una tabella semplice (vedi Rules.newGame), la
-- stessa che finisce nel DataStore e che il server manda al client. Le
-- funzioni che la cambiano girano SOLO sul server; quelle che la leggono
-- (avanzamento, "si può fare?") le usa anche il client per l'interfaccia.
--
-- Tutti i timer sono timestamp Unix assoluti (Rules.now()), quindi il tempo
-- scorre anche a gioco chiuso: al rientro basta confrontarli con l'ora attuale.
--
-- Messaggi ed eventi non sono testo: Rules.emit(tipo, dati) li passa al
-- server, che li gira al client; il client li traduce (vedi Locale.luau).
-- Un argomento di un messaggio può essere un numero, una stringa,
-- {k = "CHIAVE", lower = true} (testo da tradurre) o {list = {...}}.

local RunService = game:GetService("RunService")

local GameData = require(script.Parent.GameData)

local Rules = {}

-- Spostamento dell'orologio, per i test.
Rules.timeOffset = 0
Rules.rng = Random.new()

-- Viene sostituita dal server per raccogliere i messaggi di ogni azione.
Rules.emit = function(_kind: string, _data: any) end

-- Ora del server, uguale su server e client. Fuori dal gioco (test lanciati
-- dalla barra dei comandi di Studio) si usa l'orologio del computer.
function Rules.now(): number
	if RunService:IsRunning() then
		return workspace:GetServerTimeNow() + Rules.timeOffset
	end
	return DateTime.now().UnixTimestampMillis / 1000 + Rules.timeOffset
end

function Rules.today(): string
	local d = os.date("!*t", math.floor(Rules.now())) :: any
	return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

local key = GameData.key
local unkey = GameData.unkey

local function toast(k: string, ...)
	Rules.emit("toast", { key = k, args = { ... } })
end

local function pick<T>(list: { T }): T
	return list[Rules.rng:NextInteger(1, #list)]
end

local function randi(a: number, b: number): number
	return Rules.rng:NextInteger(a, b)
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- --- Avvio e progresso offline ---------------------------------------------

function Rules.newGame(): any
	local t = Rules.now()
	local s = {
		version = 1,
		coins = GameData.START_COINS,
		nostalgie = 0,
		xp = 0,
		level = 1,
		espresso = 1,
		moka_last_tick = t,
		water = GameData.WATER_START,
		water_last_tick = t,
		fertilizer = 0,
		inventory = {}, -- prodotto -> quantità
		seeds = table.clone(GameData.START_SEEDS), -- coltura -> semi posseduti
		tilled = {}, -- "x,y" -> true: terra lavorata con la zappa
		plow_queue = {}, -- { {cell = "x,y", start = unix, ["end"] = unix} }
		plots = {}, -- "x,y" -> {crop, planted_at, watered, fertilized, harvests}
		owned_sectors = { GameData.START_SECTOR }, -- lotti 6×6 posseduti, come "x,y"
		antiques = {}, -- oggetto antico -> quantità
		chest = {}, -- forziere di oggi: {cell = "x,y"}, vuoto se non c'è
		last_chest_day = "",
		orders = {}, -- { {giver, why, items = {prodotto = qty}, coins, xp} }
		restored = {}, -- id degli edifici restaurati
		productions = {}, -- edificio -> {started_at = unix}
		placed = {}, -- oggetti sulla fattoria (vedi "Oggetti sulla fattoria")
		next_uid = 1,
		decor_inv = {}, -- decorazione -> quante da posizionare
		biberon = 0,
		tourists = {}, -- { {type, size, items, coins, arrived, leaves} }
		next_tourist_at = 0,
		reviews = {}, -- ultime recensioni, da 1 a 5 stelle
		visitors_today = 0,
		visitors_day = "",
		last_bocce_day = "",
	}
	for _, c in GameData.START_TILLED do
		s.tilled[key(c[1], c[2])] = true
	end
	Rules.refillOrders(s)
	return s
end

-- Completa un salvataggio caricato con i campi che mancano (salvataggi
-- vecchi): ogni campo nuovo prende il valore di una partita nuova.
function Rules.migrate(d: any): any
	local fresh = Rules.newGame()
	if type(d) ~= "table" then
		return fresh
	end
	for k, v in fresh do
		if d[k] == nil then
			d[k] = v
		end
	end
	Rules.refillOrders(d)
	return d
end

-- Applica in un colpo il tempo passato a gioco chiuso (e, sul server, ogni
-- secondo). Le colture non hanno bisogno di nulla (timestamp assoluti).
-- Restituisce true se lo stato è cambiato.
function Rules.tick(s: any): boolean
	local dirty = false
	dirty = Rules.tickMoka(s) or dirty
	dirty = Rules.tickWater(s) or dirty
	dirty = Rules.updatePlowing(s) or dirty
	dirty = Rules.tickChest(s) or dirty
	dirty = Rules.tickTourism(s) or dirty
	return dirty
end

-- Ricarica a tempo: restituisce nuovo valore e nuovo ultimo tick.
local function regen(value: number, lastTick: number, interval: number, maxValue: number): (number, number)
	local t = Rules.now()
	if value >= maxValue then
		return value, t
	end
	local made = math.floor((t - lastTick) / interval)
	if made <= 0 then
		return value, lastTick
	end
	value = math.min(value + made, maxValue)
	lastTick = if value >= maxValue then t else lastTick + made * interval
	return value, lastTick
end

function Rules.tickMoka(s: any): boolean
	local v, last = regen(s.espresso, s.moka_last_tick, GameData.MOKA_INTERVAL, GameData.MOKA_MAX)
	local gained = v ~= s.espresso
	s.espresso, s.moka_last_tick = v, last
	return gained
end

function Rules.tickWater(s: any): boolean
	local v, last = regen(s.water, s.water_last_tick, GameData.WATER_INTERVAL, GameData.WATER_MAX)
	local gained = v ~= s.water
	s.water, s.water_last_tick = v, last
	return gained
end

-- Secondi alla prossima goccia (0 se il pozzo è pieno).
function Rules.waterSecondsToNext(s: any): number
	if s.water >= GameData.WATER_MAX then
		return 0
	end
	return math.max(0, math.ceil(s.water_last_tick + GameData.WATER_INTERVAL - Rules.now()))
end

-- --- Terra e zappa ----------------------------------------------------------

-- Dentro la mappa (posseduto o no).
function Rules.isInWorld(x: number, y: number): boolean
	local w = GameData.worldSize()
	return x >= 0 and y >= 0 and x < w and y < w
end

function Rules.isSectorOwned(s: any, sx: number, sy: number): boolean
	return table.find(s.owned_sectors, key(sx, sy)) ~= nil
end

-- Quadrante utilizzabile: dentro un lotto posseduto.
function Rules.isInGrid(s: any, x: number, y: number): boolean
	if not Rules.isInWorld(x, y) then
		return false
	end
	return Rules.isSectorOwned(s, GameData.sectorOf(x, y))
end

function Rules.isTilled(s: any, x: number, y: number): boolean
	return s.tilled[key(x, y)] == true
end

function Rules.plowJobIndex(s: any, x: number, y: number): number?
	local k = key(x, y)
	for i, job in s.plow_queue do
		if job.cell == k then
			return i
		end
	end
	return nil
end

function Rules.isPlowQueued(s: any, x: number, y: number): boolean
	return Rules.plowJobIndex(s, x, y) ~= nil
end

-- Mette in coda la zappatura di un quadrante d'erba.
function Rules.queuePlow(s: any, x: number, y: number): boolean
	if not Rules.isInGrid(s, x, y) or Rules.isTilled(s, x, y) or Rules.isPlowQueued(s, x, y)
		or Rules.objectAt(s, x, y) ~= nil or Rules.isChestCell(s, x, y) then
		return false
	end
	if #s.plow_queue >= GameData.PLOW_QUEUE_MAX then
		toast("MSG_QUEUE_FULL")
		return false
	end
	local start = Rules.now()
	local last = s.plow_queue[#s.plow_queue]
	if last then
		start = math.max(start, last["end"])
	end
	table.insert(s.plow_queue, { cell = key(x, y), start = start, ["end"] = start + GameData.PLOW_TIME })
	return true
end

-- Dopo una cancellazione i lavori successivi slittano in avanti.
local function rescheduleQueue(s: any)
	local t = Rules.now()
	for _, job in s.plow_queue do
		if job.start <= t then
			t = job["end"] -- lavoro già iniziato: resta com'è
			continue
		end
		job.start = t
		job["end"] = t + GameData.PLOW_TIME
		t = job["end"]
	end
end

function Rules.cancelPlow(s: any, x: number, y: number): boolean
	local i = Rules.plowJobIndex(s, x, y)
	if not i then
		return false
	end
	table.remove(s.plow_queue, i)
	rescheduleQueue(s)
	return true
end

-- Sposta tra la terra lavorata i quadranti la cui zappatura è finita.
function Rules.updatePlowing(s: any): boolean
	local t = Rules.now()
	local done = 0
	while #s.plow_queue > 0 and s.plow_queue[1]["end"] <= t do
		s.tilled[s.plow_queue[1].cell] = true
		table.remove(s.plow_queue, 1)
		done += 1
	end
	if done > 0 then
		Rules.addXp(s, done) -- 1 punto esperienza per quadrante lavorato
	end
	return done > 0
end

function Rules.plowProgress(s: any, x: number, y: number): number
	local i = Rules.plowJobIndex(s, x, y)
	if not i then
		return 0
	end
	local job = s.plow_queue[i]
	return math.clamp((Rules.now() - job.start) / GameData.PLOW_TIME, 0, 1)
end

-- --- Semi e concime ---------------------------------------------------------

function Rules.seedCount(s: any, cropId: string): number
	return s.seeds[cropId] or 0
end

function Rules.isUnlocked(s: any, cropId: string): boolean
	return GameData.isPlant(cropId) and GameData.CROPS[cropId].level <= s.level
end

function Rules.buySeeds(s: any, cropId: string, qty: number): boolean
	if not Rules.isUnlocked(s, cropId) or qty <= 0 then
		return false
	end
	local cost = GameData.CROPS[cropId].seed_cost * qty
	if s.coins < cost then
		toast("MSG_NO_COINS")
		return false
	end
	s.coins -= cost
	s.seeds[cropId] = Rules.seedCount(s, cropId) + qty
	return true
end

function Rules.buyFertilizer(s: any, qty: number): boolean
	if qty <= 0 then
		return false
	end
	if s.level < GameData.FERTILIZER_LEVEL then
		toast("MSG_FERTILIZER_LOCKED", GameData.FERTILIZER_LEVEL)
		return false
	end
	local cost = GameData.FERTILIZER_PRICE * qty
	if s.coins < cost then
		toast("MSG_NO_COINS")
		return false
	end
	s.coins -= cost
	s.fertilizer += qty
	return true
end

-- --- Coltivazione -----------------------------------------------------------

function Rules.getPlot(s: any, x: number, y: number): any
	return s.plots[key(x, y)]
end

local function plotDuration(p: any): number
	return GameData.CROPS[p.crop].time
end

-- Avanzamento 0..1 della pianta sul quadrante (0 se vuoto o non annaffiata).
function Rules.plotProgress(s: any, x: number, y: number): number
	local p = Rules.getPlot(s, x, y)
	if not p or not p.watered then
		return 0
	end
	return math.clamp((Rules.now() - p.planted_at) / plotDuration(p), 0, 1)
end

-- La pianta sta crescendo: è stata annaffiata e non è ancora pronta.
function Rules.isGrowing(s: any, x: number, y: number): boolean
	local p = Rules.getPlot(s, x, y)
	return p ~= nil and p.watered and Rules.plotProgress(s, x, y) < 1
end

-- Seminata (o raccolta, se è un albero) e in attesa d'acqua.
function Rules.needsWater(s: any, x: number, y: number): boolean
	local p = Rules.getPlot(s, x, y)
	return p ~= nil and not p.watered
end

function Rules.isReady(s: any, x: number, y: number): boolean
	return Rules.getPlot(s, x, y) ~= nil and Rules.plotProgress(s, x, y) >= 1
end

function Rules.plotSecondsLeft(s: any, x: number, y: number): number
	local p = Rules.getPlot(s, x, y)
	if not p then
		return 0
	end
	if not p.watered then
		return plotDuration(p)
	end
	return math.max(0, math.ceil(p.planted_at + plotDuration(p) - Rules.now()))
end

function Rules.plant(s: any, x: number, y: number, cropId: string): boolean
	if not Rules.isInGrid(s, x, y) or Rules.getPlot(s, x, y) ~= nil then
		return false
	end
	if not Rules.isTilled(s, x, y) then
		toast("MSG_HOE_FIRST")
		return false
	end
	if not Rules.isUnlocked(s, cropId) then
		return false
	end
	if Rules.seedCount(s, cropId) <= 0 then
		toast("MSG_NO_SEEDS_OF", { k = "CROP_" .. string.upper(cropId), lower = true })
		return false
	end
	s.seeds[cropId] -= 1
	if s.seeds[cropId] <= 0 then
		s.seeds[cropId] = nil
	end
	-- Resta un sacchetto di semi finché non viene annaffiato.
	s.plots[key(x, y)] = { crop = cropId, planted_at = 0, watered = false, fertilized = false, harvests = 0 }
	return true
end

-- Annaffiare fa partire la crescita (una goccia, una volta per ciclo).
function Rules.waterPlot(s: any, x: number, y: number): boolean
	if not Rules.needsWater(s, x, y) then
		return false
	end
	if s.water <= 0 then
		toast("MSG_WELL_EMPTY")
		return false
	end
	if s.water >= GameData.WATER_MAX then
		s.water_last_tick = Rules.now() -- da pieno riparte la ricarica
	end
	s.water -= 1
	local p = Rules.getPlot(s, x, y)
	p.planted_at = Rules.now()
	p.watered = true
	return true
end

-- Il concime moltiplica il raccolto (una volta per ciclo).
function Rules.fertilizePlot(s: any, x: number, y: number): boolean
	local p = Rules.getPlot(s, x, y)
	if not p or Rules.isReady(s, x, y) or p.fertilized then
		return false
	end
	if s.fertilizer <= 0 then
		toast("MSG_NO_FERTILIZER")
		return false
	end
	s.fertilizer -= 1
	p.fertilized = true
	return true
end

function Rules.harvest(s: any, x: number, y: number): boolean
	if not Rules.isReady(s, x, y) then
		return false
	end
	local k = key(x, y)
	local p = s.plots[k]
	local c = GameData.CROPS[p.crop]
	local qty = c.yield
	if p.fertilized then
		qty *= GameData.FERTILIZER_MULTIPLIER
	end
	Rules.addItem(s, c.product, qty)
	if GameData.isPerennial(p.crop) then
		-- Alberi e arbusti restano piantati; il nuovo ciclo parte con l'acqua.
		p.planted_at = 0
		p.watered = false
		p.fertilized = false
		p.harvests = (p.harvests or 0) + 1
	else
		s.plots[k] = nil
		if GameData.RETILL_AFTER_HARVEST then
			s.tilled[k] = nil
		end
	end
	Rules.addXp(s, c.xp)
	Rules.emit("harvested", { x = x, y = y, product = c.product, qty = qty })
	return true
end

-- --- Magazzino --------------------------------------------------------------

function Rules.itemCount(s: any, product: string): number
	return s.inventory[product] or 0
end

function Rules.addItem(s: any, product: string, qty: number)
	s.inventory[product] = Rules.itemCount(s, product) + qty
end

function Rules.hasItems(s: any, items: { [string]: number }): boolean
	for product, qty in items do
		if Rules.itemCount(s, product) < qty then
			return false
		end
	end
	return true
end

function Rules.removeItems(s: any, items: { [string]: number })
	for product, qty in items do
		local left = Rules.itemCount(s, product) - qty
		s.inventory[product] = if left > 0 then left else nil
	end
end

-- --- Esperienza -------------------------------------------------------------

function Rules.addXp(s: any, amount: number)
	s.xp += amount
	while s.level < GameData.MAX_LEVEL and s.xp >= GameData.xpForLevel(s.level + 1) do
		s.level += 1
		s.nostalgie += 1
		local unlocked = {}
		for _, id in GameData.allPlants() do
			if GameData.CROPS[id].level == s.level then
				table.insert(unlocked, { k = "CROP_" .. string.upper(id) })
			end
		end
		local data: any = { key = "MSG_LEVEL_UP", args = { s.level } }
		if #unlocked > 0 then
			data.append = { key = "MSG_NEW_SEEDS", args = { { list = unlocked } } }
		end
		Rules.emit("toast", data)
		Rules.emit("levelUp", { level = s.level })
	end
end

function Rules.xpProgress(s: any): number
	local from = GameData.xpForLevel(s.level)
	local to = GameData.xpForLevel(s.level + 1)
	if to <= from then
		return 1
	end
	return math.clamp((s.xp - from) / (to - from), 0, 1)
end

-- --- Bacheca degli ordini ---------------------------------------------------

local function unitValue(product: string): number
	if GameData.SELL_PRICES[product] then
		return GameData.SELL_PRICES[product]
	end
	local id = GameData.cropForProduct(product)
	return if id then GameData.CROPS[id].sell_price else 1
end
Rules.unitValue = unitValue

-- Le piante lente si chiedono in quantità più piccole.
local function orderQty(product: string): number
	local id = GameData.cropForProduct(product)
	if not id then
		return randi(1, 2)
	end
	local t = GameData.CROPS[id].time
	if t <= 15 * GameData.MIN then
		return randi(2, 5)
	elseif t <= GameData.HOUR then
		return randi(2, 3)
	elseif t <= 4 * GameData.HOUR then
		return randi(1, 2)
	end
	return 1
end

local function shuffle(list: { any })
	for i = #list, 2, -1 do
		local j = randi(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function makeOrder(s: any): any
	local available = {}
	for _, id in GameData.plantableCrops(s.level) do
		table.insert(available, GameData.CROPS[id].product)
	end
	for _, id in s.restored do
		local prod = GameData.buildingProduct(id)
		if prod then
			table.insert(available, prod)
		end
	end
	local items = {}
	local value = 0
	local nProducts = if Rules.rng:NextNumber() < 0.6 or #available < 2 then 1 else 2
	shuffle(available)
	for i = 1, nProducts do
		local product = available[i]
		local qty = orderQty(product)
		items[product] = qty
		value += qty * unitValue(product)
	end
	return {
		giver = pick(GameData.ORDER_GIVERS),
		why = randi(0, GameData.ORDER_REASONS - 1),
		items = items,
		coins = math.floor(value * 1.3),
		xp = math.max(2, math.floor(value / 4)),
	}
end

function Rules.refillOrders(s: any)
	while #s.orders < GameData.ORDER_BOARD_SIZE do
		table.insert(s.orders, makeOrder(s))
	end
end

function Rules.canFulfill(s: any, index: number): boolean
	local o = s.orders[index]
	return o ~= nil and Rules.hasItems(s, o.items)
end

function Rules.anyOrderReady(s: any): boolean
	for i in s.orders do
		if Rules.canFulfill(s, i) then
			return true
		end
	end
	return false
end

local function randomAntique(): string
	return pick(GameData.ANTIQUE_ORDER)
end

function Rules.fulfillOrder(s: any, index: number): boolean
	if not Rules.canFulfill(s, index) then
		return false
	end
	local order = s.orders[index]
	Rules.removeItems(s, order.items)
	s.coins += order.coins
	Rules.addXp(s, order.xp)
	table.remove(s.orders, index)
	Rules.refillOrders(s)
	toast("MSG_ORDER_THANKS", order.giver, order.coins)
	if Rules.rng:NextNumber() < GameData.ANTIQUE_ORDER_CHANCE then
		local found = randomAntique()
		Rules.addAntique(s, found, 1)
		toast("MSG_ANTIQUE_FOUND", order.giver, { k = "ANT_" .. string.upper(found) })
	end
	return true
end

-- --- Oggetti antichi e forziere --------------------------------------------

function Rules.antiqueCount(s: any, id: string): number
	return s.antiques[id] or 0
end

function Rules.addAntique(s: any, id: string, qty: number)
	s.antiques[id] = Rules.antiqueCount(s, id) + qty
end

function Rules.isChestCell(s: any, x: number, y: number): boolean
	return s.chest.cell ~= nil and s.chest.cell == key(x, y)
end

-- Ogni giorno compare un forziere in un punto libero della fattoria.
function Rules.tickChest(s: any): boolean
	if s.last_chest_day == Rules.today() then
		return false
	end
	local free, fallback = {}, {}
	local w = GameData.worldSize()
	for y = 0, w - 1 do
		for x = 0, w - 1 do
			if not Rules.isInGrid(s, x, y) or Rules.getPlot(s, x, y) or Rules.isPlowQueued(s, x, y)
				or Rules.objectAt(s, x, y) then
				continue
			end
			table.insert(fallback, key(x, y))
			if not Rules.isTilled(s, x, y) then
				table.insert(free, key(x, y))
			end
		end
	end
	local pool = if #free > 0 then free else fallback
	s.last_chest_day = Rules.today()
	if #pool == 0 then
		return true
	end
	s.chest = { cell = pick(pool) }
	toast("MSG_CHEST_APPEARED")
	return true
end

function Rules.openChest(s: any, x: number, y: number): boolean
	if not Rules.isChestCell(s, x, y) then
		return false
	end
	local found = {}
	for _ = 1, randi(GameData.CHEST_ANTIQUES[1], GameData.CHEST_ANTIQUES[2]) do
		local id = randomAntique()
		found[id] = (found[id] or 0) + 1
		Rules.addAntique(s, id, 1)
	end
	local c = randi(GameData.CHEST_COINS[1], GameData.CHEST_COINS[2])
	s.coins += c
	s.chest = {}
	local names = {}
	for id, n in found do
		table.insert(names, { fmt = "%d %s", args = { n, { k = "ANT_" .. string.upper(id) } } })
	end
	toast("MSG_CHEST_OPENED", { list = names }, c)
	Rules.emit("chestOpened", { x = x, y = y })
	return true
end

-- --- Lotti di terra ---------------------------------------------------------

function Rules.sectorCost(sx: number, sy: number): any
	return GameData.SECTORS[key(sx, sy)]
end

-- Un lotto si compra se confina con uno già posseduto.
function Rules.isSectorBuyable(s: any, sx: number, sy: number): boolean
	if Rules.isSectorOwned(s, sx, sy) or Rules.sectorCost(sx, sy) == nil then
		return false
	end
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		if Rules.isSectorOwned(s, sx + d[1], sy + d[2]) then
			return true
		end
	end
	return false
end

function Rules.canBuySector(s: any, sx: number, sy: number): boolean
	if not Rules.isSectorBuyable(s, sx, sy) then
		return false
	end
	local cost = Rules.sectorCost(sx, sy)
	if s.level < cost.level or s.coins < cost.coins then
		return false
	end
	for id, n in cost.antiques do
		if Rules.antiqueCount(s, id) < n then
			return false
		end
	end
	return true
end

function Rules.buySector(s: any, sx: number, sy: number): boolean
	if not Rules.canBuySector(s, sx, sy) then
		return false
	end
	local cost = Rules.sectorCost(sx, sy)
	s.coins -= cost.coins
	for id, n in cost.antiques do
		s.antiques[id] = Rules.antiqueCount(s, id) - n
	end
	table.insert(s.owned_sectors, key(sx, sy))
	Rules.addXp(s, 15)
	toast("MSG_SECTOR_BOUGHT")
	Rules.emit("sectorBought", { sx = sx, sy = sy })
	return true
end

-- --- Borgo ------------------------------------------------------------------

function Rules.isRestored(s: any, id: string): boolean
	return table.find(s.restored, id) ~= nil
end

function Rules.canRestore(s: any, id: string): boolean
	local b = GameData.BUILDINGS[id]
	if not b or Rules.isRestored(s, id) then
		return false
	end
	return s.level >= b.level and s.coins >= b.restore.coins and Rules.hasItems(s, b.restore.items)
end

-- Edificio che si può già restaurare (per il pallino sul pulsante Borgo).
function Rules.anyRestorable(s: any): boolean
	for id in GameData.BUILDINGS do
		if Rules.canRestore(s, id) then
			return true
		end
	end
	return false
end

function Rules.restore(s: any, id: string): boolean
	if not Rules.canRestore(s, id) then
		return false
	end
	local b = GameData.BUILDINGS[id]
	s.coins -= b.restore.coins
	Rules.removeItems(s, b.restore.items)
	table.insert(s.restored, id)
	s.nostalgie += 2
	Rules.addXp(s, 10 + 5 * #s.restored)
	toast("MSG_RESTORED_POP", b.pop[1], b.pop[2], b.pop[3])
	if #s.restored == GameData.TOURISM_FROM then
		s.next_tourist_at = Rules.now() + 60
		toast("MSG_TOURISM_START")
	end
	Rules.emit("restored", { id = id })
	return true
end

-- Abitanti del borgo: quelli rimasti più quelli tornati con i restauri.
function Rules.population(s: any): number
	local n = GameData.START_POPULATION
	for _, id in s.restored do
		local b = GameData.BUILDINGS[id]
		if b then
			for _, v in b.pop do
				n += v
			end
		end
	end
	return n
end

function Rules.productionProgress(s: any, id: string): number
	local p = s.productions[id]
	if not p then
		return 0
	end
	local recipe = GameData.BUILDINGS[id].recipe
	return math.clamp((Rules.now() - p.started_at) / recipe.time, 0, 1)
end

function Rules.startProduction(s: any, id: string): boolean
	local b = GameData.BUILDINGS[id]
	if not b or not b.recipe or not Rules.isRestored(s, id) or s.productions[id] then
		return false
	end
	if not Rules.hasItems(s, b.recipe.input) then
		toast("MSG_MISSING_INGREDIENTS")
		return false
	end
	Rules.removeItems(s, b.recipe.input)
	s.productions[id] = { started_at = Rules.now() }
	return true
end

function Rules.collectProduction(s: any, id: string): boolean
	if not s.productions[id] or Rules.productionProgress(s, id) < 1 then
		return false
	end
	for product, qty in GameData.BUILDINGS[id].recipe.out do
		Rules.addItem(s, product, qty)
	end
	s.productions[id] = nil
	Rules.addXp(s, 2)
	return true
end

-- --- Turismo ----------------------------------------------------------------

function Rules.tourismActive(s: any): boolean
	return #s.restored >= GameData.TOURISM_FROM
end

function Rules.touristInterval(s: any): number
	local k = 1 + 0.15 * #s.restored
	if Rules.isRestored(s, "ufficio_postale") then
		k += 0.5
	end
	return GameData.TOURIST_INTERVAL / k
end

function Rules.maxTourists(s: any): number
	return math.min(GameData.TOURIST_MAX, 1 + #s.restored // 3)
end

-- Valutazione del borgo: media delle recensioni (3 se non ce ne sono), più
-- il campanile restaurato; da 1 a 5.
function Rules.rating(s: any): number
	local r = 3
	if #s.reviews > 0 then
		local sum = 0
		for _, v in s.reviews do
			sum += v
		end
		r = sum / #s.reviews
	end
	if Rules.isRestored(s, "campanile") then
		r += 0.5
	end
	return math.clamp(r, 1, 5)
end

local function addReview(s: any, stars: number)
	table.insert(s.reviews, stars)
	while #s.reviews > GameData.REVIEWS_KEPT do
		table.remove(s.reviews, 1)
	end
end

local function makeTourist(s: any, arrived: number): any
	local wanted = {}
	for _, id in s.restored do
		local prod = GameData.buildingProduct(id)
		if prod then
			table.insert(wanted, prod)
		end
	end
	for _, o in s.placed do
		if o.kind == "structure" and o.type == "cucina" then
			for _, rid in GameData.STRUCTURES.cucina.recipes do
				table.insert(wanted, GameData.RECIPES[rid].out)
			end
			break
		end
	end
	if #wanted == 0 then
		wanted = { "pomodori", "grano" }
	end
	local prod = pick(wanted)
	local qty = randi(1, 2)
	local size = randi(1, 4)
	s.visitors_today += size
	local pay = unitValue(prod) * qty * GameData.TOURIST_PAY
	if Rules.isRestored(s, "osteria") then
		pay *= 1.25
	end
	return {
		type = pick(GameData.TOURIST_TYPES),
		size = size,
		items = { [prod] = qty },
		coins = math.floor(pay),
		arrived = arrived,
		leaves = arrived + GameData.TOURIST_PATIENCE,
	}
end

-- Arrivi e partenze dei visitatori (anche per il tempo passato a gioco chiuso)
-- e il premio giornaliero delle bocce.
function Rules.tickTourism(s: any): boolean
	local t = Rules.now()
	local dirty = false
	local today = Rules.today()
	if s.visitors_day ~= today then
		s.visitors_day = today
		s.visitors_today = 0
		dirty = true
	end
	if Rules.isRestored(s, "bocce") and s.last_bocce_day ~= today then
		s.last_bocce_day = today
		s.coins += GameData.BOCCE_DAILY
		toast("MSG_BOCCE", GameData.BOCCE_DAILY)
		dirty = true
	end
	-- chi ha aspettato troppo se ne va, deluso
	for i = #s.tourists, 1, -1 do
		if s.tourists[i].leaves <= t then
			table.remove(s.tourists, i)
			addReview(s, 2)
			dirty = true
		end
	end
	if Rules.tourismActive(s) then
		if s.next_tourist_at <= 0 then
			s.next_tourist_at = t + 60
			dirty = true
		end
		local guard = 0
		while s.next_tourist_at <= t and guard < 20 do
			guard += 1
			if #s.tourists < Rules.maxTourists(s) then
				table.insert(s.tourists, makeTourist(s, s.next_tourist_at))
			end
			s.next_tourist_at += Rules.touristInterval(s)
			dirty = true
		end
	end
	return dirty
end

function Rules.canServeTourist(s: any, i: number): boolean
	local t = s.tourists[i]
	return t ~= nil and Rules.hasItems(s, t.items)
end

function Rules.serveTourist(s: any, i: number): boolean
	if not Rules.canServeTourist(s, i) then
		return false
	end
	local t = s.tourists[i]
	Rules.removeItems(s, t.items)
	s.coins += t.coins
	s.nostalgie += 1
	Rules.addXp(s, 5)
	table.remove(s.tourists, i)
	addReview(s, if Rules.rng:NextNumber() < 0.7 then 5 else 4)
	toast("MSG_TOURIST_THANKS", { k = "TOURIST_" .. string.upper(t.type) }, t.coins)
	return true
end

-- --- Oggetti sulla fattoria -------------------------------------------------
-- Ogni oggetto: {uid, kind = "animal"|"structure"|"decor", type, cell = "x,y"}
-- più, per gli animali, bottles, last_bottle, fed_at (0 = da nutrire) e,
-- per le strutture, recipe e started_at (ricetta in corso).

function Rules.objectAt(s: any, x: number, y: number): any
	for _, o in s.placed do
		local ox, oy = unkey(o.cell)
		local w, h = GameData.footprint(o.kind, o.type)
		if x >= ox and y >= oy and x < ox + w and y < oy + h then
			return o
		end
	end
	return nil
end

function Rules.getObject(s: any, uid: number): any
	for _, o in s.placed do
		if o.uid == uid then
			return o
		end
	end
	return nil
end

-- Quadrante libero per posare qualcosa: tuo, non zappato, senza piante, lavori,
-- forziere o altri oggetti.
function Rules.isCellFree(s: any, x: number, y: number): boolean
	return Rules.isInGrid(s, x, y) and not Rules.isTilled(s, x, y) and Rules.getPlot(s, x, y) == nil
		and not Rules.isPlowQueued(s, x, y) and Rules.objectAt(s, x, y) == nil and not Rules.isChestCell(s, x, y)
end

function Rules.canPlace(s: any, kind: string, typ: string, x: number, y: number): boolean
	local w, h = GameData.footprint(kind, typ)
	for dy = 0, h - 1 do
		for dx = 0, w - 1 do
			if not Rules.isCellFree(s, x + dx, y + dy) then
				return false
			end
		end
	end
	return true
end

local function catalog(kind: string): any
	return if kind == "animal" then GameData.ANIMALS else GameData.STRUCTURES
end

function Rules.buyPrice(kind: string, typ: string): number
	return catalog(kind)[typ].price
end

function Rules.unlockLevel(kind: string, typ: string): number
	return catalog(kind)[typ].level
end

function Rules.canBuy(s: any, kind: string, typ: string): boolean
	return s.level >= Rules.unlockLevel(kind, typ) and s.coins >= Rules.buyPrice(kind, typ)
end

-- Compra un animale o una struttura e lo mette nel quadrante scelto.
function Rules.buyAndPlace(s: any, kind: string, typ: string, x: number, y: number): boolean
	if (kind ~= "animal" and kind ~= "structure") or catalog(kind)[typ] == nil then
		return false
	end
	if not Rules.canBuy(s, kind, typ) then
		if s.level >= Rules.unlockLevel(kind, typ) then
			toast("MSG_NO_COINS")
		else
			toast("SHOP_UNLOCK", Rules.unlockLevel(kind, typ))
		end
		return false
	end
	if not Rules.canPlace(s, kind, typ, x, y) then
		toast("MSG_PLACE_BLOCKED")
		return false
	end
	s.coins -= Rules.buyPrice(kind, typ)
	local o: any = { uid = s.next_uid, kind = kind, type = typ, cell = key(x, y) }
	s.next_uid += 1
	if kind == "animal" then
		o.bottles = 0
		o.last_bottle = 0
		o.fed_at = 0
	end
	table.insert(s.placed, o)
	Rules.addXp(s, 3)
	return true
end

function Rules.placeDecor(s: any, typ: string, x: number, y: number): boolean
	if (s.decor_inv[typ] or 0) <= 0 then
		return false
	end
	if not Rules.canPlace(s, "decor", typ, x, y) then
		toast("MSG_PLACE_BLOCKED")
		return false
	end
	s.decor_inv[typ] -= 1
	if s.decor_inv[typ] <= 0 then
		s.decor_inv[typ] = nil
	end
	table.insert(s.placed, { uid = s.next_uid, kind = "decor", type = typ, cell = key(x, y) })
	s.next_uid += 1
	return true
end

-- Rimette in magazzino una decorazione posata (per spostarla).
function Rules.pickUpDecor(s: any, uid: number): boolean
	local o = Rules.getObject(s, uid)
	if not o or o.kind ~= "decor" then
		return false
	end
	table.remove(s.placed, table.find(s.placed, o))
	s.decor_inv[o.type] = (s.decor_inv[o.type] or 0) + 1
	return true
end

-- --- Animali ----------------------------------------------------------------

function Rules.buyBiberon(s: any, qty: number): boolean
	if qty <= 0 then
		return false
	end
	local cost = GameData.BIBERON_PRICE * qty
	if s.coins < cost then
		toast("MSG_NO_COINS")
		return false
	end
	s.coins -= cost
	s.biberon += qty
	return true
end

function Rules.isAdult(o: any): boolean
	return (o.bottles or 0) >= GameData.ANIMALS[o.type].bottles
end

-- Secondi che mancano prima del prossimo biberon (0 = si può dare ora).
function Rules.bottleWait(o: any): number
	local last = o.last_bottle or 0
	if last <= 0 then
		return 0
	end
	return math.max(0, math.ceil(last + GameData.BOTTLE_COOLDOWN - Rules.now()))
end

function Rules.animalProgress(o: any): number
	local fed = o.fed_at or 0
	if fed <= 0 then
		return 0
	end
	return math.clamp((Rules.now() - fed) / GameData.ANIMALS[o.type].time, 0, 1)
end

-- Stato di un animale, per gli indicatori e per decidere cosa fare al tocco:
-- "bottle" (cucciolo, pronto per il biberon), "bottle_wait", "hungry" (adulto
-- da nutrire), "producing", "ready" (prodotto da raccogliere).
function Rules.animalState(o: any): string
	if not Rules.isAdult(o) then
		return if Rules.bottleWait(o) == 0 then "bottle" else "bottle_wait"
	end
	if (o.fed_at or 0) <= 0 then
		return "hungry"
	end
	return if Rules.animalProgress(o) >= 1 then "ready" else "producing"
end

function Rules.giveBottle(s: any, uid: number): boolean
	local o = Rules.getObject(s, uid)
	if not o or o.kind ~= "animal" or Rules.isAdult(o) or Rules.bottleWait(o) > 0 then
		return false
	end
	if s.biberon <= 0 then
		toast("MSG_NO_BIBERON")
		return false
	end
	s.biberon -= 1
	o.bottles = (o.bottles or 0) + 1
	o.last_bottle = Rules.now()
	Rules.addXp(s, 1)
	if Rules.isAdult(o) then
		toast("MSG_ANIMAL_GROWN", { k = "ANIMAL_" .. string.upper(o.type) })
	end
	return true
end

function Rules.feedAnimal(s: any, uid: number): boolean
	local o = Rules.getObject(s, uid)
	if not o or o.kind ~= "animal" or Rules.animalState(o) ~= "hungry" then
		return false
	end
	local feed = GameData.ANIMALS[o.type].feed
	if not Rules.hasItems(s, feed) then
		toast("MSG_NO_FEED")
		return false
	end
	Rules.removeItems(s, feed)
	o.fed_at = Rules.now()
	return true
end

function Rules.collectAnimal(s: any, uid: number): boolean
	local o = Rules.getObject(s, uid)
	if not o or o.kind ~= "animal" or Rules.animalState(o) ~= "ready" then
		return false
	end
	local a = GameData.ANIMALS[o.type]
	Rules.addItem(s, a.product, a.yield)
	o.fed_at = 0
	Rules.addXp(s, a.xp)
	local x, y = unkey(o.cell)
	Rules.emit("harvested", { x = x, y = y, product = a.product, qty = a.yield })
	return true
end

-- --- Strutture e ricette ----------------------------------------------------

function Rules.recipeProgress(s: any, uid: number): number
	local o = Rules.getObject(s, uid)
	if not o or not o.recipe then
		return 0
	end
	return math.clamp((Rules.now() - o.started_at) / GameData.RECIPES[o.recipe].time, 0, 1)
end

function Rules.canStartRecipe(s: any, uid: number, recipe: string): boolean
	local o = Rules.getObject(s, uid)
	if not o or o.kind ~= "structure" or o.recipe then
		return false
	end
	if not table.find(GameData.STRUCTURES[o.type].recipes, recipe) then
		return false
	end
	local r = GameData.RECIPES[recipe]
	return Rules.hasItems(s, r.input) and s.coins >= r.coins and s.espresso >= r.espresso
end

function Rules.startRecipe(s: any, uid: number, recipe: string): boolean
	local r = GameData.RECIPES[recipe]
	if not Rules.canStartRecipe(s, uid, recipe) then
		if r and s.espresso < r.espresso then
			toast("MSG_NO_ESPRESSO")
		elseif r and not Rules.hasItems(s, r.input) then
			toast("MSG_MISSING_INGREDIENTS")
		elseif r and s.coins < r.coins then
			toast("MSG_NO_COINS")
		end
		return false
	end
	local o = Rules.getObject(s, uid)
	Rules.removeItems(s, r.input)
	s.coins -= r.coins
	if r.espresso > 0 then
		if s.espresso >= GameData.MOKA_MAX then
			s.moka_last_tick = Rules.now() -- da piena la moka riparte
		end
		s.espresso -= r.espresso
	end
	o.recipe = recipe
	o.started_at = Rules.now()
	return true
end

function Rules.collectRecipe(s: any, uid: number): boolean
	local o = Rules.getObject(s, uid)
	if not o or not o.recipe or Rules.recipeProgress(s, uid) < 1 then
		return false
	end
	local r = GameData.RECIPES[o.recipe]
	local out = r.out
	if table.find(GameData.DECOR, out) then
		s.decor_inv[out] = (s.decor_inv[out] or 0) + 1
	else
		Rules.addItem(s, out, 1)
	end
	o.recipe = nil
	o.started_at = nil
	Rules.addXp(s, r.xp)
	toast("MSG_RECIPE_DONE", { k = "RECIPE_" .. string.upper(out) })
	return true
end

-- Vende prodotti del magazzino (fatti in casa, latte, uova...).
function Rules.sell(s: any, product: string, qty: number): boolean
	if not GameData.SELL_PRICES[product] or qty <= 0 or Rules.itemCount(s, product) < qty then
		return false
	end
	Rules.removeItems(s, { [product] = qty })
	s.coins += GameData.SELL_PRICES[product] * qty
	return true
end

-- --- Tocco sulla fattoria ---------------------------------------------------
-- Porting di farm.gd (_tap, _apply_at, _use_tool, _object_tap). Nel gioco
-- Godot il contadino camminava fino al quadrante; qui il contadino è
-- l'avatar del giocatore e l'azione è immediata. "first" è il primo
-- quadrante di una passata col dito o col mouse: i messaggi d'aiuto escono
-- solo lì, per non riempire lo schermo trascinando.

local function objectTap(s: any, o: any): (boolean, string?)
	if o.kind == "structure" then
		return false, "structure"
	elseif o.kind == "animal" then
		local st = Rules.animalState(o)
		if st == "bottle" then
			return Rules.giveBottle(s, o.uid)
		elseif st == "bottle_wait" then
			toast("ANIMAL_WAIT", GameData.formatTime(Rules.bottleWait(o)))
		elseif st == "hungry" then
			return Rules.feedAnimal(s, o.uid)
		elseif st == "ready" then
			return Rules.collectAnimal(s, o.uid)
		end
	end
	return false
end

-- Restituisce (cambiato, pannello da aprire sul client o nil).
function Rules.useAt(s: any, x: number, y: number, tool: string, cropId: string?, first: boolean): (boolean, string?)
	if not Rules.isInWorld(x, y) then
		return false
	end
	local o = Rules.objectAt(s, x, y)
	if o then
		if first then
			return objectTap(s, o)
		end
		return false
	end
	if Rules.isChestCell(s, x, y) then
		return if first then Rules.openChest(s, x, y) else false
	end
	if not Rules.isInGrid(s, x, y) then
		return false, if first then "land" else nil
	end
	-- Le piante pronte si raccolgono sempre, qualunque strumento sia in mano.
	if Rules.isReady(s, x, y) then
		return Rules.harvest(s, x, y)
	end
	if tool == "hoe" then
		if Rules.isPlowQueued(s, x, y) then
			return if first then Rules.cancelPlow(s, x, y) else false
		elseif not Rules.isTilled(s, x, y) then
			return Rules.queuePlow(s, x, y)
		end
	elseif tool == "seed" then
		if Rules.getPlot(s, x, y) == nil and cropId and (Rules.isTilled(s, x, y) or first) then
			if Rules.seedCount(s, cropId) <= 0 and not first then
				return false
			end
			return Rules.plant(s, x, y, cropId)
		end
	elseif tool == "water" then
		if not Rules.needsWater(s, x, y) then
			if first then
				toast("MSG_WATER_HINT")
			end
		elseif s.water <= 0 then
			if first then
				toast("MSG_WELL_EMPTY")
			end
		else
			return Rules.waterPlot(s, x, y)
		end
	elseif tool == "fertilizer" then
		local p = Rules.getPlot(s, x, y)
		if not p then
			if first then
				toast("MSG_FERTILIZER_HINT")
			end
		elseif s.fertilizer <= 0 then
			if first then
				toast("MSG_NO_FERTILIZER")
			end
		elseif not p.fertilized then
			return Rules.fertilizePlot(s, x, y)
		end
	elseif tool == "hand" and first then
		if Rules.isGrowing(s, x, y) then
			toast("MSG_READY_IN", GameData.formatTime(Rules.plotSecondsLeft(s, x, y)))
		elseif Rules.needsWater(s, x, y) then
			toast("MSG_WATER_HINT")
		elseif not Rules.isTilled(s, x, y) and not Rules.isPlowQueued(s, x, y) then
			toast("MSG_TAKE_HOE")
		end
	end
	return false
end

-- In modalità sviluppatore riporta le monete al massimo e il livello all'ultimo.
function Rules.applyDevMode(s: any)
	s.coins = math.max(s.coins, GameData.DEV_COINS)
	if s.level < GameData.MAX_LEVEL then
		s.level = GameData.MAX_LEVEL
		s.xp = math.max(s.xp, GameData.xpForLevel(GameData.MAX_LEVEL))
	end
end

Rules.count = count

return Rules
