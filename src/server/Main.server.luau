-- Server di Terra Mia: costruisce il mondo, dà una fattoria a ogni giocatore,
-- carica e salva le partite e applica le azioni chieste dai client.
--
-- Il server è l'unico che cambia lo stato (Rules). Il client chiede le
-- azioni con il RemoteEvent "Act" e riceve lo stato intero con "State" e i
-- messaggi da tradurre con "Message". Ogni argomento arrivato dal client
-- viene controllato: un client modificato non deve poter barare.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = require(Shared.GameData)
local Rules = require(Shared.Rules)
local WorldConfig = require(Shared.WorldConfig)

local FarmView = require(script.Parent.FarmView)
local PlayerData = require(script.Parent.PlayerData)
local WorldBuilder = require(script.Parent.WorldBuilder)

local DEV_MODE = GameData.DEV_MODE and RunService:IsStudio()

-- --- Remote ---------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local Act = remote("Act")
local StateEvent = remote("State")
local MessageEvent = remote("Message")
remotes.Parent = ReplicatedStorage

WorldBuilder.build()

-- --- Sessioni -------------------------------------------------------------------

type Session = {
	player: Player,
	state: any,
	canSave: boolean,
	dirty: boolean,
	lastSave: number,
	plot: number?,
	view: any,
	tokens: number,
	loaded: boolean,
}

local sessions: { [Player]: Session } = {}
local plotsTaken: { [number]: Player } = {}

local function freePlot(): number?
	for i = 1, WorldConfig.MAX_PLOTS do
		if not plotsTaken[i] then
			return i
		end
	end
	return nil
end

local function pushState(sess: Session)
	StateEvent:FireClient(sess.player, sess.state, {
		plot = sess.plot,
		canSave = sess.canSave,
		dev = DEV_MODE,
	})
end

-- Esegue fn raccogliendo i messaggi di Rules e li manda al giocatore.
local function withMessages(sess: Session, fn: () -> boolean): boolean
	local buffer = {}
	Rules.emit = function(kind, data)
		table.insert(buffer, { kind = kind, data = data })
	end
	local ok, changed = pcall(fn)
	Rules.emit = function() end
	if not ok then
		warn("[TerraMia] errore in un'azione:", changed)
		changed = false
	end
	if #buffer > 0 then
		MessageEvent:FireClient(sess.player, buffer)
	end
	if changed then
		if DEV_MODE then
			Rules.applyDevMode(sess.state)
		end
		sess.dirty = true
	end
	return changed == true
end

local function teleport(player: Player, where: string)
	local sess = sessions[player]
	local character = player.Character
	if not character or not sess then
		return
	end
	local pos, look
	if where == "farm" and sess.plot then
		pos = WorldConfig.farmSpawn(sess.plot)
		look = pos + Vector3.new(0, 0, -1)
	else
		pos = WorldConfig.borgoSpawn()
		look = pos + Vector3.new(0, 0, -1)
	end
	character:PivotTo(CFrame.lookAt(pos, look))
end

-- --- Controllo degli argomenti --------------------------------------------------

local function isInt(v: any, lo: number?, hi: number?): boolean
	return type(v) == "number" and v == v and math.floor(v) == v and v >= (lo or -10000) and v <= (hi or 10000)
end

local function isId(v: any, catalog: { [string]: any }?): boolean
	if type(v) ~= "string" or #v > 40 then
		return false
	end
	return catalog == nil or catalog[v] ~= nil
end

local TOOLS = { hand = true, hoe = true, seed = true, water = true, fertilizer = true }

-- Ogni azione: (stato, argomenti...) -> cambiato?
local ACTIONS: { [string]: (any, ...any) -> boolean } = {
	use = function(s, x, y, tool, crop, first)
		if not (isInt(x, 0, 100) and isInt(y, 0, 100) and TOOLS[tool] and type(first) == "boolean") then
			return false
		end
		if crop ~= nil and not isId(crop, GameData.CROPS) then
			return false
		end
		local changed = Rules.useAt(s, x, y, tool, crop, first)
		return changed
	end,
	buySeeds = function(s, crop, qty)
		return isId(crop, GameData.CROPS) and isInt(qty, 1, 100) and Rules.buySeeds(s, crop, qty)
	end,
	buyFertilizer = function(s, qty)
		return isInt(qty, 1, 100) and Rules.buyFertilizer(s, qty)
	end,
	buyBiberon = function(s, qty)
		return isInt(qty, 1, 100) and Rules.buyBiberon(s, qty)
	end,
	buyAndPlace = function(s, kind, typ, x, y)
		return (kind == "animal" or kind == "structure") and isId(typ) and isInt(x, 0, 100) and isInt(y, 0, 100)
			and Rules.buyAndPlace(s, kind, typ, x, y)
	end,
	placeDecor = function(s, typ, x, y)
		return isId(typ) and isInt(x, 0, 100) and isInt(y, 0, 100) and Rules.placeDecor(s, typ, x, y)
	end,
	pickUpDecor = function(s, uid)
		return isInt(uid, 1, 1e7) and Rules.pickUpDecor(s, uid)
	end,
	fulfillOrder = function(s, i)
		return isInt(i, 1, 20) and Rules.fulfillOrder(s, i)
	end,
	serveTourist = function(s, i)
		return isInt(i, 1, 20) and Rules.serveTourist(s, i)
	end,
	restore = function(s, id)
		return isId(id, GameData.BUILDINGS) and Rules.restore(s, id)
	end,
	startProduction = function(s, id)
		return isId(id, GameData.BUILDINGS) and Rules.startProduction(s, id)
	end,
	collectProduction = function(s, id)
		return isId(id, GameData.BUILDINGS) and Rules.collectProduction(s, id)
	end,
	buySector = function(s, sx, sy)
		return isInt(sx, 0, 10) and isInt(sy, 0, 10) and Rules.buySector(s, sx, sy)
	end,
	startRecipe = function(s, uid, recipe)
		return isInt(uid, 1, 1e7) and isId(recipe, GameData.RECIPES) and Rules.startRecipe(s, uid, recipe)
	end,
	collectRecipe = function(s, uid)
		return isInt(uid, 1, 1e7) and Rules.collectRecipe(s, uid)
	end,
	sell = function(s, product, qty)
		return isId(product, GameData.SELL_PRICES) and isInt(qty, 1, 999) and Rules.sell(s, product, qty)
	end,
}

Act.OnServerEvent:Connect(function(player: Player, name: any, ...)
	local sess = sessions[player]
	if not sess or not sess.loaded or type(name) ~= "string" then
		return
	end
	-- limite di richieste: le passate col dito ne mandano tante, ma non infinite
	if sess.tokens < 1 then
		return
	end
	sess.tokens -= 1
	if name == "hello" then
		-- il client è pronto: gli si rimanda lo stato, nel caso l'avesse perso
		pushState(sess)
		return
	end
	if name == "goto" then
		local where = ...
		if where == "farm" or where == "borgo" then
			teleport(player, where)
		end
		return
	end
	local action = ACTIONS[name]
	if not action then
		return
	end
	local args = table.pack(...)
	local changed = withMessages(sess, function()
		return action(sess.state, table.unpack(args, 1, args.n)) == true
	end)
	if changed then
		pushState(sess)
		if sess.view then
			sess.view:refresh(sess.state)
		end
	end
end)

-- --- Entrata e uscita -----------------------------------------------------------

local function save(sess: Session)
	if not sess.canSave or not sess.loaded then
		return
	end
	if PlayerData.save(sess.player, sess.state) then
		sess.dirty = false
		sess.lastSave = os.clock()
	end
end

local function onCharacter(player: Player)
	task.defer(function()
		local character = player.Character
		if character then
			character:WaitForChild("HumanoidRootPart", 10)
			teleport(player, "farm")
		end
	end)
end

local function onPlayerAdded(player: Player)
	local index = freePlot()
	local sess: Session = {
		player = player,
		state = Rules.newGame(),
		canSave = false,
		dirty = false,
		lastSave = os.clock(),
		plot = index,
		view = nil,
		tokens = 60,
		loaded = false,
	}
	sessions[player] = sess
	if index then
		plotsTaken[index] = player
	else
		MessageEvent:FireClient(player, { { kind = "toast", data = { key = "UI_NO_PLOT", args = {} } } })
	end
	local state, canSave = PlayerData.load(player)
	if sessions[player] ~= sess then
		return -- è uscito durante il caricamento
	end
	sess.state = state
	sess.canSave = canSave
	sess.loaded = true
	-- tempo passato a gioco chiuso
	withMessages(sess, function()
		Rules.tick(sess.state)
		return true
	end)
	if DEV_MODE then
		Rules.applyDevMode(sess.state)
	end
	if index then
		sess.view = FarmView.new(index, player)
		sess.view:refresh(sess.state)
	end
	pushState(sess)
	if not canSave then
		MessageEvent:FireClient(player, { { kind = "toast", data = { key = "UI_NO_SAVE", args = {} } } })
	end
	player.CharacterAdded:Connect(function()
		onCharacter(player)
	end)
	if player.Character then
		onCharacter(player)
	end
end

local function onPlayerRemoving(player: Player)
	local sess = sessions[player]
	if not sess then
		return
	end
	sessions[player] = nil
	if sess.plot and plotsTaken[sess.plot] == player then
		plotsTaken[sess.plot] = nil
	end
	if sess.view then
		sess.view:destroy()
	end
	save(sess)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

game:BindToClose(function()
	local pending = 0
	for _, sess in sessions do
		pending += 1
		task.spawn(function()
			save(sess)
			pending -= 1
		end)
	end
	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)

-- --- Il tempo che passa -----------------------------------------------------------
-- Ogni secondo: moka, pozzo, zappa, forziere, turisti; la fattoria 3D segue
-- la crescita delle piante; ogni tanto si salva.

task.spawn(function()
	while true do
		task.wait(1)
		for _, sess in sessions do
			if not sess.loaded then
				continue
			end
			sess.tokens = math.min(60, sess.tokens + 30)
			local changed = withMessages(sess, function()
				return Rules.tick(sess.state)
			end)
			if changed then
				pushState(sess)
			end
			if sess.view then
				sess.view:refresh(sess.state)
			end
			if sess.dirty and os.clock() - sess.lastSave >= PlayerData.AUTOSAVE then
				sess.lastSave = os.clock()
				task.spawn(save, sess)
			end
		end
	end
end)
