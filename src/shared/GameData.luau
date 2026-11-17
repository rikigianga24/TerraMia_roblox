-- Dati statici del gioco, presi dal documento di design (docs/design.md).
-- Porting 1:1 di scripts/autoload/game_data.gd del progetto Godot.
--
-- Tempi e livelli sono una proposta da bilanciare con i test.
-- I valori economici di grano e pomodoro sono fissati a mano; gli altri
-- vengono dalla stessa formula, da rifinire con i test:
--   seme = 1,5·√minuti (×4 per alberi e arbusti, che restano piantati)
--   valore del raccolto ≈ seme + 3·minuti^0,6, diviso per la resa
--   esperienza = 0,9·√minuti
--
-- Le tabelle Luau non hanno ordine: dove l'ordine conta (negozio, sblocchi)
-- c'è una lista a parte (CROP_ORDER, BUILDING_ORDER).

local GameData = {}

-- Crediti mostrati nelle impostazioni.
GameData.CREATOR = "Riccardo"
GameData.VERSION = "0.1.0"

local MIN = 60
local HOUR = 3600
local DAY = 86400
GameData.MIN = MIN
GameData.HOUR = HOUR
GameData.DAY = DAY

-- kind: "crop" (si ripianta a ogni raccolto), "tree"/"bush" (resta piantato
-- e rifà i frutti), "animal" (vedi ANIMALS). yield = pezzi per raccolto,
-- color = colore della grafica provvisoria.
local CROP_LIST = {
	{ "grano", "crop", 2 * MIN, "grano", 1, 2, 3, 1, 2, "e8c547" },
	{ "lattuga", "crop", 5 * MIN, "lattuga", 1, 3, 5, 2, 2, "9ccf4f" },
	{ "pomodoro", "crop", 10 * MIN, "pomodori", 1, 5, 9, 3, 2, "d9412b" },
	{ "carota", "crop", 15 * MIN, "carote", 2, 6, 11, 3, 2, "ee8a2a" },
	{ "basilico", "crop", 30 * MIN, "basilico", 2, 8, 16, 5, 2, "3f9b3a" },
	{ "gallina", "animal", 20 * MIN, "uova", 3, 0, 0, 0, 0, "f4f0e6" },
	{ "fragola", "crop", 40 * MIN, "fragole", 3, 9, 18, 6, 2, "e0314f" },
	{ "zucchina", "crop", 45 * MIN, "zucchine", 3, 10, 20, 6, 2, "4e8a32" },
	{ "cipolla", "crop", 25 * MIN, "cipolle", 4, 8, 14, 4, 2, "c9a0c8" },
	{ "carciofo", "crop", 1 * HOUR, "carciofi", 4, 12, 23, 7, 2, "6f8f5a" },
	{ "ulivo", "tree", 4 * HOUR, "olive", 4, 92, 47, 14, 3, "58683a" },
	{ "mucca", "animal", 1 * HOUR, "latte", 5, 0, 0, 0, 0, "ffffff" },
	{ "patata", "crop", 1 * HOUR, "patate", 5, 12, 23, 7, 2, "c49a5a" },
	{ "melanzana", "crop", 90 * MIN, "melanzane", 5, 14, 29, 9, 2, "5b2a6e" },
	{ "rovo_more", "bush", 2 * HOUR, "more", 5, 64, 31, 10, 3, "2c1d3f" },
	{ "aglio", "crop", 1 * HOUR, "aglio", 6, 12, 23, 7, 2, "efe8dc" },
	{ "peperoncino", "crop", 2 * HOUR, "peperoncini", 6, 16, 35, 10, 2, "c41e1e" },
	{ "vite", "tree", 8 * HOUR, "uva", 6, 132, 70, 20, 3, "6a2c5e" },
	{ "rucola", "crop", 20 * MIN, "rucola", 7, 7, 13, 4, 2, "4a7d2e" },
	{ "fagioli", "crop", 90 * MIN, "fagioli", 7, 14, 29, 9, 2, "b5653a" },
	{ "fico", "tree", 6 * HOUR, "fichi", 7, 112, 59, 17, 3, "7a4a6a" },
	{ "finocchio", "crop", 2 * HOUR, "finocchi", 8, 16, 35, 10, 2, "dfe8c0" },
	{ "rosmarino", "bush", 3 * HOUR, "rosmarino", 8, 80, 40, 12, 3, "5d7f6a" },
	{ "nocciolo", "tree", 10 * HOUR, "nocciole", 8, 148, 80, 22, 3, "9a6b3c" },
	{ "origano", "crop", 1 * HOUR, "origano", 9, 12, 23, 7, 2, "6d8c3c" },
	{ "zucca", "crop", 3 * HOUR, "zucche", 9, 20, 44, 12, 2, "e27a1f" },
	{ "castagno", "tree", 12 * HOUR, "castagne", 9, 160, 89, 24, 3, "7b4a26" },
	{ "ciliegio", "tree", 8 * HOUR, "ciliegie", 10, 132, 70, 20, 3, "b0142c" },
	{ "mandorlo", "tree", 12 * HOUR, "mandorle", 10, 160, 89, 24, 3, "d8c09a" },
	{ "anguria", "crop", 4 * HOUR, "angurie", 11, 23, 52, 14, 2, "3d8c3a" },
	{ "pesco", "tree", 8 * HOUR, "pesche", 11, 132, 70, 20, 3, "f2a46b" },
	{ "limone", "tree", 8 * HOUR, "limoni", 8, 130, 60, 18, 3, "f2d64b" },
	{ "arancio", "tree", 10 * HOUR, "arance", 12, 148, 80, 22, 3, "f08a12" },
	{ "zafferano", "crop", 1 * DAY, "zafferano", 12, 57, 219, 34, 2, "8a4fc0", true },
	{ "pistacchio", "tree", 1 * DAY, "pistacchi", 13, 228, 200, 34, 3, "93b04a", true },
}

export type Crop = {
	id: string,
	kind: string,
	time: number,
	product: string,
	level: number,
	seed_cost: number,
	sell_price: number,
	xp: number,
	yield: number,
	color: string,
	rare: boolean,
}

GameData.CROPS = {} :: { [string]: Crop }
GameData.CROP_ORDER = {} :: { string }
for _, r in CROP_LIST do
	local c: Crop = {
		id = r[1],
		kind = r[2],
		time = r[3],
		product = r[4],
		level = r[5],
		seed_cost = r[6],
		sell_price = r[7],
		xp = r[8],
		yield = r[9],
		color = r[10],
		rare = r[11] == true,
	}
	GameData.CROPS[c.id] = c
	table.insert(GameData.CROP_ORDER, c.id)
end

-- Edifici del borgo: il cuore del gioco. Ognuno ha un abitante che chiede
-- aiuto per riaprirlo (STORY_<id> nelle traduzioni), un costo di restauro,
-- gli abitanti che riporta in paese (pop: abitanti, commercianti, famiglie) e,
-- una volta restaurato, una produzione ("recipe") o un effetto ("effect").
GameData.BUILDINGS = {
	mulino = { level = 2, restore = { coins = 60, items = { grano = 10 } }, pop = { 2, 1, 1 },
		recipe = { input = { grano = 3 }, out = { farina = 1 }, time = 2 * MIN } },
	forno = { level = 3, restore = { coins = 120, items = { farina = 4, grano = 10 } }, pop = { 2, 1, 1 },
		recipe = { input = { farina = 2, uova = 1 }, out = { pane = 1 }, time = 10 * MIN } },
	ufficio_postale = { level = 4, restore = { coins = 150, items = { grano = 15, pomodori = 6 } }, pop = { 2, 1, 1 },
		effect = "tourism" },
	conserve = { level = 4, restore = { coins = 160, items = { pomodori = 15 } }, pop = { 2, 1, 1 },
		recipe = { input = { pomodori = 4 }, out = { passata = 1 }, time = 5 * MIN } },
	frantoio = { level = 5, restore = { coins = 220, items = { olive = 10 } }, pop = { 3, 1, 1 },
		recipe = { input = { olive = 5 }, out = { olio = 1 }, time = 15 * MIN } },
	caseificio = { level = 6, restore = { coins = 250, items = { latte = 4, grano = 20 } }, pop = { 2, 1, 1 },
		recipe = { input = { latte_pecora = 3 }, out = { pecorino = 1 }, time = 20 * MIN } },
	cantina = { level = 7, restore = { coins = 300, items = { uva = 10 } }, pop = { 3, 1, 1 },
		recipe = { input = { uva = 5 }, out = { chianti = 1 }, time = 30 * MIN } },
	gelateria = { level = 7, restore = { coins = 220, items = { latte = 4, fragole = 6 } }, pop = { 2, 1, 1 },
		recipe = { input = { latte = 2, fragole = 3 }, out = { gelato = 1 }, time = 8 * MIN } },
	pastificio = { level = 8, restore = { coins = 280, items = { farina = 8, uova = 6 } }, pop = { 2, 1, 1 },
		recipe = { input = { farina = 2, uova = 2 }, out = { pasta_fresca = 1 }, time = 10 * MIN } },
	campanile = { level = 8, restore = { coins = 400, items = { grano = 20, olio = 2 } }, pop = { 1, 0, 1 },
		effect = "rating" },
	bar = { level = 9, restore = { coins = 300, items = { limoni = 8, latte = 6 } }, pop = { 2, 1, 1 },
		recipe = { input = { limoni = 5 }, out = { limoncello = 1 }, time = 20 * MIN } },
	osteria = { level = 10, restore = { coins = 450, items = { passata = 3, pasta_fresca = 3, basilico = 5 } }, pop = { 2, 1, 1 },
		effect = "tips" },
	pasticceria = { level = 11, restore = { coins = 400, items = { mandorle = 8, farina = 6 } }, pop = { 2, 1, 1 },
		recipe = { input = { mandorle = 3, farina = 2, uova = 2 }, out = { cantucci = 1 }, time = 15 * MIN } },
	caldarroste = { level = 11, restore = { coins = 120, items = { castagne = 10 } }, pop = { 1, 1, 0 },
		recipe = { input = { castagne = 4 }, out = { caldarroste = 1 }, time = 5 * MIN } },
	bocce = { level = 12, restore = { coins = 200, items = { grano = 30 } }, pop = { 4, 0, 1 },
		effect = "daily" },
} :: { [string]: any }
GameData.BUILDING_ORDER = {
	"mulino", "forno", "ufficio_postale", "conserve", "frantoio", "caseificio", "cantina",
	"gelateria", "pastificio", "campanile", "bar", "osteria", "pasticceria", "caldarroste", "bocce",
}
-- Battute degli abitanti (LINE_<id>_<n> nelle traduzioni).
GameData.BUILDING_LINES = { mulino = 2 }

-- Abitanti rimasti nel borgo abbandonato all'inizio.
GameData.START_POPULATION = 3

-- --- Turismo ---------------------------------------------------------------
-- Dopo TOURISM_FROM restauri arrivano i visitatori: chiedono prodotti tipici,
-- pagano e lasciano una recensione (5 stelle se serviti, 2 se se ne vanno).
GameData.TOURISM_FROM = 2
GameData.TOURIST_TYPES = { "ciclisti", "turisti", "camperisti", "stranieri" }
GameData.TOURIST_INTERVAL = 15 * MIN -- uno ogni tanto, più spesso con più edifici
GameData.TOURIST_PATIENCE = 3 * HOUR
GameData.TOURIST_MAX = 4
GameData.TOURIST_PAY = 1.5 -- rispetto al prezzo di vendita
GameData.REVIEWS_KEPT = 20
GameData.BOCCE_DAILY = 40

-- Esperienza totale necessaria per raggiungere ogni livello.
-- XP_FOR_LEVEL[livello + 1], perché le liste Luau partono da 1.
GameData.XP_FOR_LEVEL = { 0, 0, 12, 40, 90, 160, 250, 370, 520, 700, 920, 1180, 1480, 1830 }
GameData.MAX_LEVEL = 13

-- Modalità sviluppatore, per le prove: monete infinite e livello massimo
-- (tutto sbloccato). Vale solo dentro Roblox Studio, mai nel gioco pubblicato.
GameData.DEV_MODE = false
GameData.DEV_COINS = 999999

-- Espresso: la moka di casa ne fa 1 ogni 2 ore, fino a 3.
GameData.MOKA_INTERVAL = 2 * HOUR
GameData.MOKA_MAX = 3

-- Zappa: un quadrante d'erba si lavora in 15 secondi.
-- I lavori si mettono in coda e vanno avanti anche a gioco chiuso.
GameData.PLOW_TIME = 15
GameData.PLOW_QUEUE_MAX = 12
-- Se true, dopo il raccolto di una coltura la terra torna erba e va rizappata.
GameData.RETILL_AFTER_HARVEST = false
-- Quadranti già lavorati a inizio partita (il tutorial ne usa 4).
GameData.START_TILLED = { { 2, 2 }, { 3, 2 }, { 2, 3 }, { 3, 3 } }
GameData.START_SEEDS = { grano = 4 }
GameData.START_COINS = 30

-- Gocce d'acqua: il pozzo ne riempie una ogni 90 secondi, fino a 20.
-- Una pianta seminata resta un sacchetto di semi finché non la annaffi:
-- l'acqua (una goccia) fa partire la crescita. Alberi e arbusti, dopo il
-- raccolto, vanno annaffiati di nuovo per rifare i frutti.
GameData.WATER_INTERVAL = 90
GameData.WATER_MAX = 20
GameData.WATER_START = 10

-- Concime: raddoppia il raccolto della pianta su cui lo spargi (una volta per ciclo).
GameData.FERTILIZER_PRICE = 10
GameData.FERTILIZER_MULTIPLIER = 2
GameData.FERTILIZER_LEVEL = 2

GameData.ORDER_BOARD_SIZE = 3
GameData.ORDER_GIVERS = { "Gino", "Rosa", "Beppe", "Zia Carmela", "Nonna Pina" }
-- Quante ragioni diverse ha un ordine (ORDER_WHY_0.. nelle traduzioni).
GameData.ORDER_REASONS = 6

-- Mappa della fattoria: lotti di 6×6 quadranti, 3×3 lotti in tutto.
-- Si parte dal lotto (0,0); ci si allarga comprando i lotti confinanti.
GameData.SECTOR_SIZE = 6
GameData.WORLD_SECTORS = 3
GameData.START_SECTOR = "0,0"
-- Prezzo dei lotti: monete, livello minimo e oggetti antichi.
GameData.SECTORS = {
	["1,0"] = { coins = 150, level = 3, antiques = { moneta_romana = 1, anfora = 1 } },
	["0,1"] = { coins = 150, level = 3, antiques = { moneta_romana = 1, lucerna = 1 } },
	["1,1"] = { coins = 400, level = 5, antiques = { anfora = 1, mosaico = 2 } },
	["2,0"] = { coins = 400, level = 5, antiques = { lucerna = 2, fibula = 1 } },
	["0,2"] = { coins = 400, level = 5, antiques = { moneta_romana = 2, fibula = 1 } },
	["2,1"] = { coins = 900, level = 7, antiques = { mosaico = 2, chiave_antica = 1 } },
	["1,2"] = { coins = 900, level = 7, antiques = { anfora = 2, chiave_antica = 1 } },
	["2,2"] = { coins = 1600, level = 9, antiques = { chiave_antica = 2, mosaico = 2, fibula = 2 } },
} :: { [string]: any }

-- Oggetti antichi: servono a sbloccare i lotti. Si trovano a caso
-- consegnando ordini, o nel forziere che compare ogni giorno sulla fattoria.
GameData.ANTIQUES = {
	moneta_romana = { color = "d9a441" },
	anfora = { color = "c0603e" },
	lucerna = { color = "b98a5a" },
	mosaico = { color = "4f8fb0" },
	fibula = { color = "9aa6ad" },
	chiave_antica = { color = "7a5a2a" },
}
GameData.ANTIQUE_ORDER = { "moneta_romana", "anfora", "lucerna", "mosaico", "fibula", "chiave_antica" }
GameData.ANTIQUE_ORDER_CHANCE = 0.3
-- Forziere: uno al giorno, in un punto libero della fattoria.
GameData.CHEST_ANTIQUES = { 1, 2 } -- da 1 a 2 oggetti
GameData.CHEST_COINS = { 20, 60 }

-- --- Animali ----------------------------------------------------------------
-- Si comprano da cuccioli e crescono con i biberon (uno ogni BOTTLE_COOLDOWN);
-- da adulti si nutrono ("feed") e dopo "time" danno il loro prodotto.
GameData.BIBERON_PRICE = 12
GameData.BOTTLE_COOLDOWN = 5 * MIN
GameData.ANIMALS = {
	gallina = { level = 3, price = 40, bottles = 3, feed = { grano = 1 }, product = "uova", yield = 2, time = 20 * MIN, xp = 4 },
	mucca = { level = 5, price = 160, bottles = 5, feed = { grano = 3 }, product = "latte", yield = 1, time = 1 * HOUR, xp = 10 },
	pecora = { level = 6, price = 120, bottles = 4, feed = { grano = 2 }, product = "latte_pecora", yield = 1, time = 90 * MIN, xp = 8 },
} :: { [string]: any }
GameData.ANIMAL_ORDER = { "gallina", "mucca", "pecora" }

-- --- Strutture, ricette e decorazioni -----------------------------------------
-- Le strutture si comprano, si posizionano sulla fattoria (su quadranti liberi,
-- non zappati) e fanno una ricetta alla volta.
GameData.STRUCTURES = {
	falegnameria = { level = 3, price = 150, size = { 2, 2 }, recipes = { "staccionata", "secchio", "barile", "panchina" } },
	cucina = { level = 4, price = 250, size = { 2, 2 }, recipes = { "bruschetta", "pesto", "pizza" } },
} :: { [string]: any }
GameData.STRUCTURE_ORDER = { "falegnameria", "cucina" }
-- input: prodotti consumati; coins: costo in monete; espresso: tazzine consumate;
-- out: cosa esce (decorazione per la falegnameria, prodotto per la cucina).
GameData.RECIPES = {
	staccionata = { input = {}, coins = 5, espresso = 0, time = 1 * MIN, out = "staccionata", xp = 1 },
	secchio = { input = {}, coins = 10, espresso = 0, time = 2 * MIN, out = "secchio", xp = 1 },
	barile = { input = {}, coins = 25, espresso = 0, time = 5 * MIN, out = "barile", xp = 2 },
	panchina = { input = {}, coins = 40, espresso = 0, time = 10 * MIN, out = "panchina", xp = 3 },
	bruschetta = { input = { pane = 1, pomodori = 2, olio = 1 }, coins = 0, espresso = 1, time = 5 * MIN, out = "bruschetta", xp = 8 },
	pesto = { input = { basilico = 3, aglio = 1, olio = 1 }, coins = 0, espresso = 1, time = 8 * MIN, out = "pesto", xp = 10 },
	pizza = { input = { farina = 2, pomodori = 2, basilico = 1 }, coins = 0, espresso = 1, time = 12 * MIN, out = "pizza", xp = 12 },
} :: { [string]: any }
GameData.DECOR = { "staccionata", "secchio", "barile", "panchina" }
-- Prodotti tipici, fatti in casa e degli animali: si vendono e piacciono ai turisti.
GameData.SELL_PRICES = {
	farina = 12, pane = 45, passata = 50, olio = 90, pecorino = 110, chianti = 160,
	gelato = 60, pasta_fresca = 70, limoncello = 120, cantucci = 130, caldarroste = 55,
	bruschetta = 140, pesto = 150, pizza = 170,
	uova = 6, latte = 14, latte_pecora = 16,
} :: { [string]: number }
GameData.SELL_ORDER = {
	"uova", "latte", "latte_pecora", "farina", "pane", "passata", "olio", "pecorino", "chianti",
	"gelato", "pasta_fresca", "limoncello", "cantucci", "caldarroste", "bruschetta", "pesto", "pizza",
}

-- --- Funzioni di comodo ------------------------------------------------------

function GameData.crop(id: string): Crop?
	return GameData.CROPS[id]
end

function GameData.building(id: string): any
	return GameData.BUILDINGS[id]
end

-- Le piante si seminano nei campi; gli animali stanno in ANIMALS.
function GameData.isPlant(id: string): boolean
	local c = GameData.CROPS[id]
	return c ~= nil and c.kind ~= "animal"
end

-- Resta piantata dopo il raccolto e rifà i frutti (alberi e arbusti).
function GameData.isPerennial(id: string): boolean
	local c = GameData.CROPS[id]
	return c ~= nil and (c.kind == "tree" or c.kind == "bush")
end

-- Tutte le piante in ordine di sblocco.
function GameData.allPlants(): { string }
	local result = {}
	for _, id in GameData.CROP_ORDER do
		if GameData.isPlant(id) then
			table.insert(result, id)
		end
	end
	return result
end

-- Piante già sbloccate al livello dato.
function GameData.plantableCrops(level: number): { string }
	local result = {}
	for _, id in GameData.allPlants() do
		if GameData.CROPS[id].level <= level then
			table.insert(result, id)
		end
	end
	return result
end

function GameData.cropForProduct(product: string): string?
	for _, id in GameData.CROP_ORDER do
		if GameData.CROPS[id].product == product then
			return id
		end
	end
	return nil
end

function GameData.xpForLevel(level: number): number
	local t = GameData.XP_FOR_LEVEL
	return t[math.clamp(level + 1, 1, #t)]
end

function GameData.isDecorRecipe(id: string): boolean
	return table.find(GameData.DECOR, GameData.RECIPES[id].out) ~= nil
end

function GameData.footprint(kind: string, typ: string): (number, number)
	if kind == "structure" then
		local s = GameData.STRUCTURES[typ].size
		return s[1], s[2]
	end
	return 1, 1
end

-- Prodotto che esce da un edificio del borgo, o nil se ha un effetto.
function GameData.buildingProduct(id: string): string?
	local b = GameData.BUILDINGS[id]
	if b == nil or b.recipe == nil then
		return nil
	end
	for product in b.recipe.out do
		return product
	end
	return nil
end

function GameData.maxPopulation(): number
	local n = GameData.START_POPULATION
	for _, b in GameData.BUILDINGS do
		for _, v in b.pop do
			n += v
		end
	end
	return n
end

-- Lato della mappa in quadranti (18).
function GameData.worldSize(): number
	return GameData.WORLD_SECTORS * GameData.SECTOR_SIZE
end

function GameData.sectorOf(x: number, y: number): (number, number)
	return x // GameData.SECTOR_SIZE, y // GameData.SECTOR_SIZE
end

function GameData.key(x: number, y: number): string
	return string.format("%d,%d", x, y)
end

function GameData.unkey(key: string): (number, number)
	local a, b = string.match(key, "^(-?%d+),(-?%d+)$")
	return tonumber(a) or 0, tonumber(b) or 0
end

function GameData.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= HOUR then
		return string.format("%dh %02dm", seconds // HOUR, (seconds % HOUR) // MIN)
	end
	return string.format("%d:%02d", seconds // MIN, seconds % MIN)
end

function GameData.color(hex: string): Color3
	return Color3.fromHex(hex)
end

return GameData
