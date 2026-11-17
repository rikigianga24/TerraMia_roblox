-- Lancia i test delle regole (src/tests/RulesTests.luau) fuori da Roblox
-- Studio, con Lune (https://lune-org.github.io/docs), installato da rokit:
--
--   lune run tools/run_tests
--
-- Simula le poche API Roblox che servono a src/shared: game:GetService,
-- workspace:GetServerTimeNow, Random, DateTime, Color3 e script/require.
-- Esce con codice 1 se un controllo fallisce.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local cache = {}

local function folder(name: string, dir: string, modules: { string })
	local f = { Name = name, _children = {} }
	for _, n in modules do
		f._children[n] = { Name = n, Parent = f, _file = dir .. "/" .. n .. ".luau" }
	end
	function f.WaitForChild(self, n)
		return self._children[n] or error("manca " .. n)
	end
	return setmetatable(f, {
		__index = function(t, k)
			return rawget(t, "_children")[k]
		end,
	})
end

local Shared = folder("Shared", "src/shared", { "GameData", "Rules", "Locale", "Strings", "BorgoLayout", "WorldConfig" })
local Tests = folder("Tests", "src/tests", { "RulesTests" })

local clock = os.time()
local services = {
	RunService = {
		IsRunning = function()
			return true
		end,
		IsStudio = function()
			return true
		end,
	},
	ReplicatedStorage = {
		WaitForChild = function(_, n)
			assert(n == "Shared")
			return Shared
		end,
	},
}

local RandomClass = {}
RandomClass.__index = RandomClass
function RandomClass.NextInteger(_, a: number, b: number): number
	return math.random(a, b)
end
function RandomClass.NextNumber(_, a: number?, b: number?): number
	local lo, hi = a or 0, b or 1
	return lo + math.random() * (hi - lo)
end

local env = {}
env.game = {
	GetService = function(_, n)
		return services[n] or error("servizio non simulato: " .. n)
	end,
}
env.workspace = {
	GetServerTimeNow = function()
		return clock
	end,
}
env.DateTime = {
	now = function()
		return { UnixTimestampMillis = clock * 1000 }
	end,
}
env.Color3 = {
	fromHex = function(h)
		return { hex = h }
	end,
	fromRGB = function(r, g, b)
		return { r, g, b }
	end,
}
env.Random = {
	new = function(seed)
		if seed then
			math.randomseed(seed)
		end
		return setmetatable({}, RandomClass)
	end,
}
-- le librerie standard di Luau, viste dai moduli
env.print, env.math, env.string, env.table, env.os = print, math, string, table, os
env.pairs, env.ipairs, env.next, env.select, env.type, env.typeof = pairs, ipairs, next, select, type, typeof
env.tostring, env.tonumber, env.error, env.assert, env.pcall = tostring, tonumber, error, assert, pcall
env.setmetatable, env.getmetatable, env.rawget, env.rawset = setmetatable, getmetatable, rawget, rawset

function env.require(m)
	if cache[m] then
		return cache[m]
	end
	local fn = luau.load(fs.readFile(m._file), {
		debugName = m.Name,
		environment = setmetatable({ script = m }, { __index = env }),
	})
	cache[m] = fn()
	return cache[m]
end

local failures = env.require(Tests._children.RulesTests)()
process.exit(if failures > 0 then 1 else 0)
