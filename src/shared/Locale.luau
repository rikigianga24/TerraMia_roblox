-- Traduzioni: Locale.tr("CHIAVE", ...) restituisce il testo nella lingua scelta.
-- I testi stanno in src/shared/Strings.luau, generato da tools/translations_source.py.
--
-- La lingua è quella scelta dal giocatore nelle impostazioni, altrimenti
-- quella del dispositivo, altrimenti l'inglese (come nel gioco Godot).

local Strings = require(script.Parent.Strings)

local Locale = {}

local langIndex = 2 -- inglese

function Locale.langs(): { string }
	return Strings.LANGS
end

function Locale.current(): string
	return Strings.LANGS[langIndex]
end

function Locale.setLang(code: string)
	local short = string.lower(string.sub(code or "", 1, 2))
	local i = table.find(Strings.LANGS, short)
	if i then
		langIndex = i
	end
end

function Locale.has(key: string): boolean
	return Strings.T[key] ~= nil
end

-- Testo grezzo della chiave, senza argomenti. Una chiave che manca si vede
-- così com'è, per accorgersene subito.
function Locale.raw(key: string): string
	local row = Strings.T[key]
	if not row then
		return key
	end
	return row[langIndex] or row[1]
end

-- Risolve un argomento di un messaggio di Rules: numero, stringa,
-- {k = "CHIAVE", lower = true}, {list = {...}} o {fmt = "...", args = {...}}.
local function resolve(arg: any): any
	if type(arg) ~= "table" then
		return arg
	end
	if arg.k then
		local text = Locale.raw(arg.k)
		return if arg.lower then string.lower(text) else text
	end
	if arg.list then
		local parts = {}
		for _, a in arg.list do
			table.insert(parts, tostring(resolve(a)))
		end
		return table.concat(parts, ", ")
	end
	if arg.fmt then
		local args = {}
		for i, a in arg.args do
			args[i] = resolve(a)
		end
		return string.format(arg.fmt, table.unpack(args))
	end
	return ""
end

function Locale.tr(key: string, ...): string
	local text = Locale.raw(key)
	if select("#", ...) == 0 then
		return text
	end
	local args = { ... }
	for i, a in args do
		args[i] = resolve(a)
	end
	local ok, result = pcall(string.format, text, table.unpack(args))
	return if ok then result else text
end

-- Testo di un messaggio arrivato dal server: {key, args, append}.
function Locale.message(m: any): string
	local text = Locale.tr(m.key, table.unpack(m.args or {}))
	if m.append then
		text ..= Locale.message(m.append)
	end
	return text
end

-- Nomi di piante, prodotti, edifici, abitanti...
function Locale.crop(id: string): string
	return Locale.raw("CROP_" .. string.upper(id))
end

function Locale.product(id: string): string
	return Locale.raw("PROD_" .. string.upper(id))
end

function Locale.building(id: string): string
	return Locale.raw("BLD_" .. string.upper(id))
end

function Locale.resident(id: string): string
	return Locale.raw("RES_" .. string.upper(id))
end

function Locale.story(id: string): string
	return Locale.raw("STORY_" .. string.upper(id))
end

function Locale.effect(effect: string): string
	return Locale.raw("EFFECT_" .. string.upper(effect))
end

function Locale.animal(id: string, baby: boolean?): string
	return Locale.raw((if baby then "BABY_" else "ANIMAL_") .. string.upper(id))
end

function Locale.structure(id: string): string
	return Locale.raw("STRUCT_" .. string.upper(id))
end

function Locale.recipe(id: string): string
	return Locale.raw("RECIPE_" .. string.upper(id))
end

function Locale.antique(id: string): string
	return Locale.raw("ANT_" .. string.upper(id))
end

-- Nome di qualsiasi cosa stia in magazzino (prodotto della terra o ricetta).
function Locale.item(id: string): string
	if Locale.has("PROD_" .. string.upper(id)) then
		return Locale.product(id)
	end
	return Locale.recipe(id)
end

return Locale
