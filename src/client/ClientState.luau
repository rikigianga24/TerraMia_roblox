-- Ultimo stato della partita arrivato dal server, più le scelte locali
-- dell'interfaccia (strumento in mano, seme scelto, modalità "posiziona").
-- I moduli dell'interfaccia ascoltano ClientState.changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ClientState = {}

ClientState.state = nil :: any -- nil finché il server non manda la partita
ClientState.meta = {} :: any -- {plot, canSave, dev}
ClientState.tool = "hand" -- hand, hoe, seed, water, fertilizer
ClientState.crop = "grano"
ClientState.placing = nil :: any -- {kind, type} mentre si posiziona un oggetto

local changedEvent = Instance.new("BindableEvent")
ClientState.changed = changedEvent.Event

function ClientState.notify()
	changedEvent:Fire()
end

-- Chiede un'azione al server (vedi ACTIONS in src/server/Main.server.luau).
function ClientState.act(name: string, ...)
	Remotes.Act:FireServer(name, ...)
end

function ClientState.setTool(tool: string, crop: string?)
	ClientState.tool = tool
	if crop then
		ClientState.crop = crop
	end
	ClientState.placing = nil
	ClientState.notify()
end

Remotes.State.OnClientEvent:Connect(function(state, meta)
	ClientState.state = state
	ClientState.meta = meta or {}
	ClientState.notify()
end)

return ClientState
