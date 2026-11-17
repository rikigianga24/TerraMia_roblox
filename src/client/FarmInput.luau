-- Tocchi e clic sulla propria fattoria (equivalente di _unhandled_input e
-- _apply_at in scenes/farm/farm.gd). Si tocca un quadrante e si può
-- trascinare per zappare, seminare o annaffiare tanti quadranti di fila.
--
-- Il client decide solo cosa aprire (pannello del terreno o della
-- struttura); l'azione vera la fa il server con Rules.useAt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameData = require(Shared.GameData)
local Rules = require(Shared.Rules)

local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Panels)

local player = Players.LocalPlayer
local FarmInput = {}

local stroke: { [string]: boolean }? = nil
local hover: SelectionBox

-- Il quadrante sotto il punto dello schermo, se è nella propria fattoria.
local function cellAt(screenPos: Vector2): (number?, number?, Instance?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not hit then
		return nil
	end
	local inst: Instance? = hit.Instance
	local tagged: Instance? = nil
	while inst and inst ~= workspace do
		if tagged == nil and inst:GetAttribute("CellX") ~= nil then
			tagged = inst
		end
		local owner = inst:GetAttribute("OwnerUserId")
		if owner ~= nil then
			if owner ~= player.UserId or not tagged then
				return nil
			end
			return tagged:GetAttribute("CellX"), tagged:GetAttribute("CellY"), hit.Instance
		end
		inst = inst.Parent
	end
	return nil
end

-- Primo tocco di una passata: può aprire un pannello invece di agire.
local function firstTap(x: number, y: number)
	local s = ClientState.state
	local placing = ClientState.placing
	if placing then
		if placing.kind == "decor" then
			ClientState.act("placeDecor", placing.type, x, y)
		else
			ClientState.act("buyAndPlace", placing.kind, placing.type, x, y)
		end
		ClientState.placing = nil
		ClientState.notify()
		return
	end
	local o = Rules.objectAt(s, x, y)
	if o and o.kind == "structure" then
		Panels.open("structure", o.uid)
		return
	end
	if not o and Rules.isInWorld(x, y) and not Rules.isInGrid(s, x, y) and not Rules.isChestCell(s, x, y) then
		local sx, sy = GameData.sectorOf(x, y)
		Panels.open("land", { sx = sx, sy = sy })
		return
	end
	ClientState.act("use", x, y, ClientState.tool, if ClientState.tool == "seed" then ClientState.crop else nil, true)
end

local function apply(screenPos: Vector2, first: boolean)
	if not ClientState.state then
		return
	end
	local x, y = cellAt(screenPos)
	if x == nil or y == nil then
		return
	end
	local k = GameData.key(x, y)
	if stroke == nil or stroke[k] then
		return
	end
	stroke[k] = true
	if first then
		firstTap(x, y)
	elseif not ClientState.placing and ClientState.tool ~= "hand" then
		ClientState.act("use", x, y, ClientState.tool, if ClientState.tool == "seed" then ClientState.crop else nil, false)
	end
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function FarmInput.init()
	hover = Instance.new("SelectionBox")
	hover.Name = "TerraMiaHover"
	hover.Color3 = Color3.fromRGB(255, 240, 190)
	hover.LineThickness = 0.06
	hover.SurfaceTransparency = 1
	hover.Parent = player:WaitForChild("PlayerGui")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not isPointer(input) then
			return
		end
		stroke = {}
		apply(Vector2.new(input.Position.X, input.Position.Y), true)
	end)
	UserInputService.InputChanged:Connect(function(input)
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local x, _, inst = cellAt(pos)
			hover.Adornee = if x ~= nil and inst and inst:IsA("BasePart") then inst else nil
			if stroke then
				apply(pos, false)
			end
		elseif input.UserInputType == Enum.UserInputType.Touch and stroke then
			apply(pos, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then
			stroke = nil
		end
	end)
end

return FarmInput
