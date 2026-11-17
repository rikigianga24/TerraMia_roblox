-- Client di Terra Mia: lingua, interfaccia, input sulla fattoria e borgo locale.
-- Lo stato arriva dal server (src/server/Main.server.luau) e sta in ClientState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared.Locale)

local player = Players.LocalPlayer

-- Lingua del dispositivo; se non è tra le quattro del gioco resta l'inglese.
Locale.setLang(player.LocaleId)

local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Panels)
local Hud = require(script.Parent.Hud)
local FarmInput = require(script.Parent.FarmInput)
local BorgoLocal = require(script.Parent.BorgoLocal)
local FarmFx = require(script.Parent.FarmFx)

local screen = Instance.new("ScreenGui")
screen.Name = "TerraMia"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

Panels.init(screen)
Hud.init(screen)
FarmInput.init()
BorgoLocal.init()
task.spawn(FarmFx.init) -- aspetta che il server abbia costruito il mondo

ReplicatedStorage:WaitForChild("Remotes").Message.OnClientEvent:Connect(function(list)
	Hud.onMessages(list)
end)

-- ClientState ascolta già "State": si chiede lo stato, nel caso il server
-- l'avesse mandato prima che questo script partisse.
ClientState.act("hello")
ClientState.notify()
