-- Test delle regole di gioco, senza grafica (porting di tests/test_game_state.gd).
--
-- Avvio in Roblox Studio, dalla barra dei comandi (View > Command Bar), anche
-- senza premere Play:
--   require(game.ServerStorage.Tests.RulesTests)()
-- Stampa "TUTTI I TEST OK" oppure i controlli falliti.
--
-- Il tempo si fa avanzare con Rules.timeOffset invece di aspettare.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = require(Shared.GameData)
local Locale = require(Shared.Locale)
local Rules = require(Shared.Rules)
local Strings = require(Shared.Strings)

local failures = 0

local function check(cond: any, what: string)
	if not cond then
		failures += 1
		print("  FALLITO: " .. what)
	end
end

local function advance(seconds: number)
	Rules.timeOffset += seconds
end

local function grow(s: any, x: number, y: number)
	s.water = math.max(s.water, 1)
	Rules.waterPlot(s, x, y)
	Rules.getPlot(s, x, y).planted_at -= 999999
end

local function testNewGame()
	print("partita nuova")
	local s = Rules.newGame()
	check(Rules.count(s.tilled) == 4, "4 quadranti lavorati all'inizio")
	check(Rules.seedCount(s, "grano") == 4, "4 semi di grano all'inizio")
	check(s.water == GameData.WATER_START, "gocce iniziali")
	check(#s.orders == GameData.ORDER_BOARD_SIZE, "bacheca piena")
end

local function testPlowQueue()
	print("zappa")
	local s = Rules.newGame()
	check(Rules.queuePlow(s, 0, 0), "metto in coda il primo quadrante")
	check(not Rules.queuePlow(s, 0, 0), "niente doppioni in coda")
	check(not Rules.queuePlow(s, 2, 2), "non si zappa la terra già lavorata")
	check(Rules.queuePlow(s, 1, 0), "secondo quadrante in coda")
	local j0, j1 = s.plow_queue[1], s.plow_queue[2]
	check(math.abs(j0["end"] - j0.start - GameData.PLOW_TIME) < 0.01, "15 secondi a quadrante")
	check(math.abs(j1.start - j0["end"]) < 0.01, "il secondo parte quando finisce il primo")
	advance(10)
	Rules.updatePlowing(s)
	check(not Rules.isTilled(s, 0, 0), "dopo 10 s non è ancora pronto")
	advance(6)
	Rules.updatePlowing(s)
	check(Rules.isTilled(s, 0, 0) and not Rules.isTilled(s, 1, 0), "dopo 16 s il primo è lavorato, il secondo no")
	advance(15)
	Rules.updatePlowing(s)
	check(Rules.isTilled(s, 1, 0), "dopo altri 15 s anche il secondo")
	Rules.queuePlow(s, 0, 1)
	Rules.queuePlow(s, 0, 2)
	Rules.cancelPlow(s, 0, 1)
	check(#s.plow_queue == 1, "cancellato un lavoro")
	check(s.plow_queue[1]["end"] - Rules.now() <= GameData.PLOW_TIME + 0.5, "il lavoro dopo slitta avanti")
end

local function testSeedsAndPlanting()
	print("semi e semina")
	local s = Rules.newGame()
	check(not Rules.plant(s, 0, 0, "grano"), "non si pianta sull'erba")
	check(Rules.plant(s, 2, 2, "grano"), "si pianta sulla terra lavorata")
	check(Rules.seedCount(s, "grano") == 3, "un seme consumato")
	check(not Rules.plant(s, 2, 2, "grano"), "quadrante occupato")
	check(not Rules.buySeeds(s, "carota", 1), "la carota è bloccata al livello 1")
	local coins = s.coins
	check(Rules.buySeeds(s, "pomodoro", 2), "compro 2 semi di pomodoro")
	check(s.coins == coins - 10 and Rules.seedCount(s, "pomodoro") == 2, "pagati 10 monete")
	s.coins = 0
	check(not Rules.buySeeds(s, "pomodoro", 1), "senza monete non si compra")
	check(not Rules.buySeeds(s, "gallina", 1), "gli animali non sono semi")
end

local function testWater()
	print("acqua")
	local s = Rules.newGame()
	s.seeds.pomodoro = 1
	Rules.plant(s, 2, 2, "pomodoro")
	check(Rules.needsWater(s, 2, 2), "appena seminato aspetta l'acqua")
	Rules.getPlot(s, 2, 2).planted_at -= 99999
	check(Rules.plotProgress(s, 2, 2) == 0 and not Rules.isReady(s, 2, 2), "senz'acqua non cresce")
	check(Rules.plotSecondsLeft(s, 2, 2) == GameData.CROPS.pomodoro.time, "il tempo resta tutto da fare")
	local w = s.water
	check(Rules.waterPlot(s, 2, 2), "annaffio")
	check(s.water == w - 1, "una goccia usata")
	check(Rules.isGrowing(s, 2, 2) and not Rules.needsWater(s, 2, 2), "ora cresce")
	check(math.abs(Rules.plotSecondsLeft(s, 2, 2) - GameData.CROPS.pomodoro.time) <= 1, "la crescita parte adesso")
	check(not Rules.waterPlot(s, 2, 2), "una volta per ciclo")
	s.water = 0
	Rules.plant(s, 3, 2, "grano")
	check(not Rules.waterPlot(s, 3, 2), "senza gocce non si annaffia")
	s.water_last_tick = Rules.now() - GameData.WATER_INTERVAL * 3.5
	Rules.tickWater(s)
	check(s.water == 3, "il pozzo ricarica 3 gocce in 3,5 intervalli")
	s.water_last_tick = Rules.now() - 99999
	Rules.tickWater(s)
	check(s.water == GameData.WATER_MAX, "non supera il massimo")
end

local function testFertilizerAndHarvest()
	print("concime e raccolto")
	local s = Rules.newGame()
	Rules.plant(s, 2, 2, "grano")
	Rules.plant(s, 3, 2, "grano")
	check(not Rules.buyFertilizer(s, 1), "concime bloccato al livello 1")
	s.level = GameData.FERTILIZER_LEVEL
	s.coins = 100
	check(Rules.buyFertilizer(s, 2), "compro concime")
	check(Rules.fertilizePlot(s, 2, 2), "concimo il primo (anche prima dell'acqua)")
	check(not Rules.fertilizePlot(s, 2, 2), "una volta per ciclo")
	check(not Rules.harvest(s, 2, 2), "non si raccoglie prima del tempo")
	grow(s, 2, 2)
	grow(s, 3, 2)
	check(Rules.harvest(s, 2, 2) and Rules.itemCount(s, "grano") == 4, "raccolto concimato: 4 grano")
	check(Rules.harvest(s, 3, 2) and Rules.itemCount(s, "grano") == 6, "raccolto normale: 2 grano")
	check(Rules.getPlot(s, 2, 2) == nil and Rules.isTilled(s, 2, 2), "la terra resta lavorata e libera")
end

local function testTrees()
	print("alberi")
	local s = Rules.newGame()
	s.level = 4
	s.seeds.ulivo = 1
	check(Rules.plant(s, 2, 2, "ulivo"), "pianto un ulivo")
	grow(s, 2, 2)
	check(Rules.harvest(s, 2, 2), "raccolgo le olive")
	check(Rules.itemCount(s, "olive") == 3, "3 olive")
	check(Rules.getPlot(s, 2, 2) ~= nil, "l'ulivo resta piantato")
	check(Rules.needsWater(s, 2, 2), "e per rifare i frutti va annaffiato di nuovo")
end

local function testSectorsAndAntiques()
	print("lotti, oggetti antichi e forziere")
	local s = Rules.newGame()
	check(Rules.isInGrid(s, 5, 5) and not Rules.isInGrid(s, 6, 0), "si parte con il lotto 6x6")
	check(Rules.isInWorld(17, 17) and not Rules.isInWorld(18, 0), "mappa 18x18")
	check(not Rules.queuePlow(s, 7, 1), "non si zappa fuori dai propri lotti")
	check(Rules.isSectorBuyable(s, 1, 0) and not Rules.isSectorBuyable(s, 1, 1), "si compra solo un lotto confinante")
	check(not Rules.canBuySector(s, 1, 0), "servono monete, livello e oggetti antichi")
	s.level = 3
	s.coins = 1000
	check(not Rules.canBuySector(s, 1, 0), "mancano ancora gli oggetti antichi")
	for id, n in GameData.SECTORS["1,0"].antiques do
		Rules.addAntique(s, id, n)
	end
	check(Rules.buySector(s, 1, 0), "compro il lotto")
	check(Rules.isInGrid(s, 7, 1), "il lotto ora è mio")
	check(s.coins == 1000 - GameData.SECTORS["1,0"].coins, "pagate le monete")
	check(Rules.antiqueCount(s, "anfora") == 0, "consumati gli oggetti antichi")
	check(Rules.isSectorBuyable(s, 1, 1), "ora confina anche il lotto centrale")
	s.last_chest_day = ""
	Rules.tickChest(s)
	check(s.chest.cell ~= nil, "compare il forziere del giorno")
	local x, y = GameData.unkey(s.chest.cell)
	check(Rules.isInGrid(s, x, y) and Rules.getPlot(s, x, y) == nil, "su un quadrante libero della fattoria")
	Rules.tickChest(s)
	check(Rules.isChestCell(s, x, y), "non ne compare un altro lo stesso giorno")
	local total = 0
	for _, id in GameData.ANTIQUE_ORDER do
		total += Rules.antiqueCount(s, id)
	end
	local coins = s.coins
	check(Rules.openChest(s, x, y), "apro il forziere")
	local after = 0
	for _, id in GameData.ANTIQUE_ORDER do
		after += Rules.antiqueCount(s, id)
	end
	check(after - total >= 1 and after - total <= 2, "dentro 1 o 2 oggetti antichi")
	check(s.coins > coins, "e qualche moneta")
	check(s.chest.cell == nil and not Rules.openChest(s, x, y), "si apre una volta sola")
end

local function testAnimals()
	print("animali")
	local s = Rules.newGame()
	check(not Rules.buyAndPlace(s, "animal", "gallina", 0, 0), "gallina bloccata al livello 1")
	s.level = 3
	s.coins = 500
	check(not Rules.buyAndPlace(s, "animal", "gallina", 2, 2), "non sulla terra zappata")
	check(Rules.buyAndPlace(s, "animal", "gallina", 0, 0), "compro un pulcino")
	check(s.coins == 500 - GameData.ANIMALS.gallina.price, "pagato")
	check(not Rules.queuePlow(s, 0, 0), "non si zappa sotto un animale")
	local o = Rules.objectAt(s, 0, 0)
	check(Rules.animalState(o) == "bottle", "il cucciolo aspetta il biberon")
	check(not Rules.giveBottle(s, o.uid), "senza biberon non si nutre")
	check(Rules.buyBiberon(s, 5) and s.biberon == 5, "compro 5 biberon")
	check(Rules.giveBottle(s, o.uid), "primo biberon")
	check(not Rules.giveBottle(s, o.uid), "il secondo deve aspettare")
	check(Rules.animalState(o) == "bottle_wait", "in attesa")
	for _ = 1, GameData.ANIMALS.gallina.bottles - 1 do
		o.last_bottle = Rules.now() - GameData.BOTTLE_COOLDOWN - 1
		Rules.giveBottle(s, o.uid)
	end
	check(Rules.isAdult(o), "dopo 3 biberon è adulta")
	check(Rules.animalState(o) == "hungry", "e ha fame")
	check(not Rules.feedAnimal(s, o.uid), "senza grano non mangia")
	Rules.addItem(s, "grano", 1)
	check(Rules.feedAnimal(s, o.uid), "mangia il grano")
	o.fed_at -= GameData.ANIMALS.gallina.time + 1
	check(Rules.collectAnimal(s, o.uid) and Rules.itemCount(s, "uova") == 2, "2 uova")
end

local function testStructures()
	print("strutture e ricette")
	local s = Rules.newGame()
	s.level = 3
	s.coins = 1000
	check(Rules.buyAndPlace(s, "structure", "falegnameria", 0, 0), "compro la falegnameria")
	check(not Rules.canPlace(s, "animal", "gallina", 1, 1), "occupa 2x2 quadranti")
	local o = Rules.objectAt(s, 1, 1)
	check(Rules.startRecipe(s, o.uid, "staccionata"), "preparo una staccionata")
	check(not Rules.collectRecipe(s, o.uid), "non è ancora pronta")
	o.started_at -= 999
	check(Rules.collectRecipe(s, o.uid) and s.decor_inv.staccionata == 1, "staccionata in magazzino")
	check(Rules.placeDecor(s, "staccionata", 4, 0), "la posiziono")
	check(Rules.pickUpDecor(s, Rules.objectAt(s, 4, 0).uid) and s.decor_inv.staccionata == 1, "e la riprendo")
	Rules.addItem(s, "uova", 3)
	check(Rules.sell(s, "uova", 2) and Rules.itemCount(s, "uova") == 1, "vendo 2 uova")
end

local function testBorgoAndTourism()
	print("borgo e turismo")
	local s = Rules.newGame()
	check(not Rules.canRestore(s, "mulino"), "il mulino si sblocca al livello 2")
	s.level = 5
	s.coins = 5000
	Rules.addItem(s, "grano", 50)
	Rules.addItem(s, "pomodori", 30)
	local pop = Rules.population(s)
	check(Rules.restore(s, "mulino"), "restauro il mulino")
	check(Rules.population(s) == pop + 4, "tornano 4 persone")
	check(not Rules.tourismActive(s), "un restauro non basta per i turisti")
	check(Rules.startProduction(s, "mulino"), "macino")
	s.productions.mulino.started_at -= 999
	check(Rules.collectProduction(s, "mulino") and Rules.itemCount(s, "farina") == 1, "una farina")
	check(Rules.restore(s, "conserve"), "restauro le conserve")
	check(Rules.tourismActive(s), "con due restauri arrivano i visitatori")
	advance(120)
	Rules.tickTourism(s)
	check(#s.tourists >= 1, "arriva il primo visitatore")
	local t = s.tourists[1]
	for product, qty in t.items do
		Rules.addItem(s, product, qty)
	end
	local coins = s.coins
	check(Rules.serveTourist(s, 1), "lo servo")
	check(s.coins == coins + t.coins and #s.reviews == 1 and s.reviews[1] >= 4, "paga e lascia una bella recensione")
end

local function testOrdersAndLevels()
	print("ordini e livelli")
	local s = Rules.newGame()
	local function fill()
		for _, id in GameData.allPlants() do
			s.inventory[GameData.CROPS[id].product] = 100
		end
	end
	fill()
	local n = 0
	while n < 200 and s.level < GameData.MAX_LEVEL do
		local done = false
		for i in s.orders do
			if Rules.canFulfill(s, i) then
				Rules.fulfillOrder(s, i)
				done = true
				n += 1
				break
			end
		end
		if not done then
			fill()
		end
	end
	check(s.level == GameData.MAX_LEVEL, string.format("con gli ordini si arriva al livello %d (%d ordini)", GameData.MAX_LEVEL, n))
	check(#GameData.plantableCrops(s.level) == #GameData.allPlants(), "tutte le piante sbloccate")
end

local function testMigration()
	print("salvataggi")
	local old = { coins = 50, level = 2, inventory = { grano = 3 } }
	local s = Rules.migrate(old)
	check(s.coins == 50 and s.level == 2, "i valori salvati restano")
	check(s.water == GameData.WATER_START and #s.orders == GameData.ORDER_BOARD_SIZE, "i campi nuovi prendono il default")
	check(Rules.isInGrid(s, 0, 0), "si possiede il lotto iniziale")
end

local function testUseAt()
	print("tocco sulla fattoria")
	local s = Rules.newGame()
	check(Rules.useAt(s, 2, 2, "seed", "grano", true), "semino toccando la terra")
	check(Rules.useAt(s, 2, 2, "water", nil, true), "annaffio")
	check(Rules.useAt(s, 0, 0, "hoe", nil, true) and Rules.isPlowQueued(s, 0, 0), "zappo l'erba")
	check(Rules.useAt(s, 0, 0, "hoe", nil, true) and not Rules.isPlowQueued(s, 0, 0), "ritocco e annullo")
	Rules.getPlot(s, 2, 2).planted_at -= 9999
	check(Rules.useAt(s, 2, 2, "hoe", nil, false), "il raccolto si fa con qualsiasi strumento")
	local _, panel = Rules.useAt(s, 10, 10, "hand", nil, true)
	check(panel == "land", "fuori dai propri lotti si apre il terreno in vendita")
end

local function testTranslations()
	print("traduzioni")
	for key, row in Strings.T do
		check(#row == #Strings.LANGS, "lingue mancanti in " .. key)
	end
	for _, id in GameData.CROP_ORDER do
		check(Locale.has("CROP_" .. string.upper(id)), "nome tradotto per " .. id)
		check(Locale.has("PROD_" .. string.upper(GameData.CROPS[id].product)), "prodotto tradotto: " .. id)
	end
	for id in GameData.BUILDINGS do
		check(Locale.has("BLD_" .. string.upper(id)), "nome dell'edificio " .. id)
		check(Locale.has("STORY_" .. string.upper(id)), "storia dell'edificio " .. id)
	end
	Locale.setLang("en")
	check(Locale.crop("grano") == "Wheat", "grano in inglese è Wheat")
	Locale.setLang("fr")
	check(Locale.product("farina") == "farine", "farina in francese è farine")
	check(Locale.message({ key = "MSG_NO_SEEDS_OF", args = { { k = "CROP_GRANO", lower = true } } }) ~= "MSG_NO_SEEDS_OF", "messaggi con argomenti da tradurre")
	Locale.setLang("it")
end

return function()
	failures = 0
	Rules.timeOffset = 0
	local emit = Rules.emit
	Rules.emit = function() end
	testNewGame()
	testPlowQueue()
	testSeedsAndPlanting()
	testWater()
	testFertilizerAndHarvest()
	testTrees()
	testSectorsAndAntiques()
	testAnimals()
	testStructures()
	testBorgoAndTourism()
	testOrdersAndLevels()
	testMigration()
	testUseAt()
	testTranslations()
	Rules.emit = emit
	Rules.timeOffset = 0
	if failures == 0 then
		print("TUTTI I TEST OK")
	else
		print(string.format("TEST FALLITI: %d", failures))
	end
	return failures
end
