-- Il borgo visto da questo giocatore. Il server costruisce ogni edificio
-- due volte (Ruin e Restored); qui si mostra la versione della propria
-- partita. Le modifiche fatte dal client restano solo sul suo schermo,
-- quindi ognuno vede il proprio borgo rinascere.
--
-- Al restauro: polvere, il rudere sparisce, l'edificio torna com'era, si
-- accendono le luci e fuma il camino (docs/design.md, "Restauro come evento").
--
-- Qui si traducono anche le etichette nel mondo (attributo L10nKey) e i
-- ProximityPrompt (attributi PromptKind e PromptId), che aprono i pannelli.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = require(Shared.GameData)
local Locale = require(Shared.Locale)
local Rules = require(Shared.Rules)

local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Panels)

local BorgoLocal = {}

local shown: { [string]: boolean } = {} -- edificio -> restaurato sullo schermo
local initialized = false

local function setVisible(folder: Instance, visible: boolean, fade: boolean)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local base = d:GetAttribute("BaseTransparency")
			if base == nil then
				d:SetAttribute("BaseTransparency", d.Transparency)
				d:SetAttribute("BaseCanCollide", d.CanCollide)
				base = d.Transparency
			end
			local target = if visible then base else 1
			if fade then
				TweenService:Create(d, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Transparency = target }):Play()
			else
				d.Transparency = target
			end
			d.CanCollide = visible and d:GetAttribute("BaseCanCollide") == true
			d.CastShadow = visible
		elseif d:IsA("Light") or d:IsA("Smoke") or d:IsA("ParticleEmitter") then
			d.Enabled = visible
		end
	end
end

local function dust(model: Model)
	local cf, size = model:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(size.X, 1, size.Z)
	anchor.CFrame = cf - Vector3.new(0, size.Y / 2 - 1, 0)
	anchor.Parent = workspace
	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(Color3.fromRGB(226, 210, 180))
	p.Size = NumberSequence.new(3, 7)
	p.Transparency = NumberSequence.new(0.3, 1)
	p.Lifetime = NumberRange.new(1.5, 2.5)
	p.Speed = NumberRange.new(4, 9)
	p.SpreadAngle = Vector2.new(60, 60)
	p.Rate = 0
	p.Parent = anchor
	p:Emit(80)
	task.delay(4, function()
		anchor:Destroy()
	end)
end

local function updateBuildings(s: any)
	local edifici = workspace:FindFirstChild("Mondo") and workspace.Mondo:FindFirstChild("Borgo")
		and workspace.Mondo.Borgo:FindFirstChild("Edifici")
	if not edifici then
		return
	end
	for _, model in edifici:GetChildren() do
		local id = model:GetAttribute("BuildingId")
		if not id then
			continue
		end
		local restored = Rules.isRestored(s, id)
		if shown[id] == restored then
			continue
		end
		local animate = initialized and restored
		shown[id] = restored
		local ruin = model:FindFirstChild("Ruin")
		local rest = model:FindFirstChild("Restored")
		if animate then
			dust(model)
			task.delay(0.6, function()
				if ruin then
					setVisible(ruin, false, true)
				end
				if rest then
					setVisible(rest, true, true)
				end
			end)
		else
			if ruin then
				setVisible(ruin, not restored, false)
			end
			if rest then
				setVisible(rest, restored, false)
			end
		end
	end
	initialized = true
end

-- --- Testi nel mondo ------------------------------------------------------------

local function localizeLabel(t: TextLabel)
	local key = t:GetAttribute("L10nKey")
	if not key then
		return
	end
	local arg = t:GetAttribute("L10nArg")
	local text = if arg then Locale.tr(key, arg) else Locale.tr(key)
	-- un edificio che si può già restaurare ha un segno in più
	local s = ClientState.state
	if s and string.sub(key, 1, 4) == "BLD_" then
		local id = string.lower(string.sub(key, 5))
		if GameData.BUILDINGS[id] and Rules.canRestore(s, id) then
			text ..= " !"
		end
	end
	t.Text = text
end

local function localizePrompt(p: ProximityPrompt)
	local kind = p:GetAttribute("PromptKind")
	if not kind then
		return
	end
	local id = p:GetAttribute("PromptId")
	p.ActionText = Locale.tr(if kind == "board" then "PROMPT_OPEN" else "PROMPT_TALK")
	p.ObjectText = Locale.building(id)
end

-- Etichette e prompt già visti, per non scorrere tutto il workspace a ogni cambio.
local labels: { [TextLabel]: boolean } = {}
local prompts: { [ProximityPrompt]: boolean } = {}

local function register(d: Instance)
	if d:IsA("TextLabel") and d:GetAttribute("L10nKey") then
		labels[d] = true
		d.Destroying:Connect(function()
			labels[d] = nil
		end)
		localizeLabel(d)
	elseif d:IsA("ProximityPrompt") and d:GetAttribute("PromptKind") then
		prompts[d] = true
		d.Destroying:Connect(function()
			prompts[d] = nil
		end)
		localizePrompt(d)
	end
end

local function localizeAll()
	for t in labels do
		localizeLabel(t)
	end
	for p in prompts do
		localizePrompt(p)
	end
end

function BorgoLocal.init()
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("TextLabel") or d:IsA("ProximityPrompt") then
			task.defer(register, d)
		elseif d:IsA("Model") and d:GetAttribute("BuildingId") and ClientState.state then
			-- edificio arrivato dopo lo stato (streaming): va sistemato
			shown[d:GetAttribute("BuildingId")] = nil
			task.defer(updateBuildings, ClientState.state)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local kind = prompt:GetAttribute("PromptKind")
		if kind == "board" then
			Panels.open("orders")
		elseif kind == "building" then
			Panels.open("building", prompt:GetAttribute("PromptId"))
		end
	end)
	ClientState.changed:Connect(function()
		local s = ClientState.state
		if s then
			updateBuildings(s)
		end
		localizeAll()
	end)
	for _, d in workspace:GetDescendants() do
		register(d)
	end
end

return BorgoLocal
