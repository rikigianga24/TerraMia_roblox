-- Salvataggio delle partite nel DataStore di Roblox (equivalente di
-- scripts/autoload/save_manager.gd, che scriveva user://terramia_save.json).
--
-- Una chiave per giocatore ("p_<UserId>") con lo stato di Rules così com'è.
-- Si salva ogni AUTOSAVE secondi se qualcosa è cambiato, all'uscita e alla
-- chiusura del server. Se il DataStore non risponde (per esempio in Studio
-- senza "Enable Studio Access to API Services") si gioca lo stesso, ma la
-- partita non viene salvata e il giocatore lo sa.
--
-- Un campo nuovo dello stato va aggiunto in Rules.newGame: Rules.migrate lo
-- aggiunge da solo ai salvataggi vecchi.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage:WaitForChild("Shared").Rules)

local PlayerData = {}

PlayerData.STORE_NAME = "TerraMia_v1"
PlayerData.AUTOSAVE = 60
local RETRIES = 3

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(PlayerData.STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[TerraMia] DataStore non disponibile:", result)
	end
end

local function keyFor(player: Player): string
	return "p_" .. player.UserId
end

local function retry<T>(fn: () -> T): (boolean, any)
	local ok, result
	for attempt = 1, RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[TerraMia] DataStore, tentativo %d: %s", attempt, tostring(result)))
		task.wait(attempt * 2)
	end
	return false, result
end

-- Carica la partita (o ne crea una nuova). Restituisce lo stato e se si può
-- salvare: false se il caricamento è fallito, per non sovrascrivere con una
-- partita vuota quella vera del giocatore.
function PlayerData.load(player: Player): (any, boolean)
	if not store then
		return Rules.newGame(), false
	end
	local ok, data = retry(function()
		return (store :: DataStore):GetAsync(keyFor(player))
	end)
	if not ok then
		return Rules.newGame(), false
	end
	if data == nil then
		return Rules.newGame(), true
	end
	return Rules.migrate(data), true
end

function PlayerData.save(player: Player, state: any): boolean
	if not store then
		return false
	end
	state.saved_at = Rules.now()
	local ok = retry(function()
		return (store :: DataStore):UpdateAsync(keyFor(player), function()
			return state
		end)
	end)
	return ok
end

return PlayerData
