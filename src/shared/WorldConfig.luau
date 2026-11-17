-- Misure e posizioni del mondo 3D, condivise da server e client.
--
-- Su Roblox più giocatori stanno nello stesso server: ognuno ha la sua
-- fattoria (un appezzamento di 18×18 quadranti da 6 stud) attorno alla strada che sale
-- al borgo, in cima alla collina al centro della mappa. Il borgo è uno solo,
-- ma ognuno lo vede restaurato secondo la propria partita (vedi
-- src/client/BorgoLocal.luau).

local BorgoLayout = require(script.Parent.BorgoLayout)
local GameData = require(script.Parent.GameData)

local WorldConfig = {}

-- --- Fattorie -------------------------------------------------------------
WorldConfig.FARM_CELL = 6 -- lato di un quadrante, in stud: fattorie larghe 108 stud
WorldConfig.FARM_TILE_HEIGHT = 1
WorldConfig.MAX_PLOTS = 8 -- da tenere uguale ai giocatori massimi del server
WorldConfig.PLOTS_PER_ROW = 4 -- due a sinistra e due a destra della strada
WorldConfig.PLOT_ROWS = math.ceil(WorldConfig.MAX_PLOTS / WorldConfig.PLOTS_PER_ROW)
-- Scala dei modelli 3D delle piante (ReplicatedStorage.Modelli, fatti in
-- Blender in metri): una zolla di 2,2 m riempie quasi un quadrante.
WorldConfig.PLANT_SCALE = WorldConfig.FARM_CELL * 0.92 / 2.2

-- --- Borgo ------------------------------------------------------------------
WorldConfig.BORGO_CELL = 8 -- lato di una cella della pianta del borgo
WorldConfig.LEVEL_HEIGHT = 3 -- stud per "livello" di VHEIGHT (12 livelli = 36 stud)
WorldConfig.BORGO_SIZE_X = BorgoLayout.SIZE_X * WorldConfig.BORGO_CELL
WorldConfig.BORGO_SIZE_Z = BorgoLayout.SIZE_Y * WorldConfig.BORGO_CELL
-- Angolo nord-ovest del borgo (cella 0,0): il borgo è centrato nell'origine.
WorldConfig.BORGO_ORIGIN = Vector3.new(-WorldConfig.BORGO_SIZE_X / 2, 0, -WorldConfig.BORGO_SIZE_Z / 2)

-- Centro della cella (cx, cy) della pianta del borgo, a quota 0.
function WorldConfig.borgoCell(cx: number, cy: number): Vector3
	local c = WorldConfig.BORGO_CELL
	return WorldConfig.BORGO_ORIGIN + Vector3.new((cx + 0.5) * c, 0, (cy + 0.5) * c)
end

-- Altezza (in stud) del vertice (vx, vy) della pianta del borgo.
function WorldConfig.vertexHeight(vx: number, vy: number): number
	vx = math.clamp(vx, 0, BorgoLayout.SIZE_X)
	vy = math.clamp(vy, 0, BorgoLayout.SIZE_Y)
	local row = BorgoLayout.VHEIGHT[vy + 1]
	local fifths = string.byte(row, vx + 1) - 48
	return fifths / 5 * WorldConfig.LEVEL_HEIGHT
end

-- Altezza media della cella: la media dei suoi quattro vertici.
function WorldConfig.cellHeight(cx: number, cy: number): number
	return (WorldConfig.vertexHeight(cx, cy) + WorldConfig.vertexHeight(cx + 1, cy)
		+ WorldConfig.vertexHeight(cx, cy + 1) + WorldConfig.vertexHeight(cx + 1, cy + 1)) / 4
end

function WorldConfig.terrainAt(cx: number, cy: number): string
	local row = BorgoLayout.TERRAIN[cy + 1]
	if not row or cx < 0 or cx >= BorgoLayout.SIZE_X then
		return " "
	end
	return string.sub(row, cx + 1, cx + 1)
end

-- Appena dentro la porta del borgo, dove si arriva col pulsante "Borgo".
function WorldConfig.borgoSpawn(): Vector3
	local e = BorgoLayout.ENTRY
	local p = WorldConfig.borgoCell(e[1], e[2])
	return p + Vector3.new(0, WorldConfig.cellHeight(e[1], e[2]) + 5, 0)
end

-- Angolo "in fondo a sinistra" della fattoria numero i (1..MAX_PLOTS).
-- Le fattorie stanno a sud del borgo, in file da quattro (PLOTS_PER_ROW): due
-- a sinistra e due a destra della strada bianca che scende dalla porta. Il
-- quadrante (0,0) è in fondo; si cresce verso il borgo (y del quadrante verso
-- -Z) e verso destra (x verso +X).
local PLOT_SIDE = GameData.worldSize() * WorldConfig.FARM_CELL -- 108 stud
local PLOT_GAP = 40
WorldConfig.PLOT_SIDE = PLOT_SIDE
WorldConfig.PLOT_GAP = PLOT_GAP
-- La strada scende lungo x = ROAD_X (la porta del borgo).
WorldConfig.ROAD_X = WorldConfig.borgoCell(BorgoLayout.GATE[1], 0).X
WorldConfig.ROAD_WIDTH = 12
-- Bordo davanti della prima fila: poco sotto il borgo.
WorldConfig.FIRST_ROW_FRONT_Z = WorldConfig.BORGO_SIZE_Z / 2 + 32

function WorldConfig.plotOrigin(i: number): Vector3
	local col = (i - 1) % WorldConfig.PLOTS_PER_ROW -- 0..3
	local row = (i - 1) // WorldConfig.PLOTS_PER_ROW -- 0..PLOT_ROWS-1
	local side = if col < 2 then -1 else 1
	local k = if col < 2 then 1 - col else col - 2 -- 0 vicino alla strada, 1 lontano
	local nearEdge = WorldConfig.ROAD_X + side * (WorldConfig.ROAD_WIDTH / 2 + 10 + k * (PLOT_SIDE + PLOT_GAP))
	local x = if side < 0 then nearEdge - PLOT_SIDE else nearEdge
	local z = WorldConfig.FIRST_ROW_FRONT_Z + PLOT_SIDE + row * (PLOT_SIDE + PLOT_GAP)
	return Vector3.new(x, 0, z)
end

-- Centro del quadrante (x, y) della fattoria i, sopra la mattonella.
function WorldConfig.farmCell(i: number, x: number, y: number): Vector3
	local o = WorldConfig.plotOrigin(i)
	local c = WorldConfig.FARM_CELL
	return o + Vector3.new((x + 0.5) * c, WorldConfig.FARM_TILE_HEIGHT, -(y + 0.5) * c)
end

-- Dove compare il giocatore: davanti al primo lotto, verso la strada.
function WorldConfig.farmSpawn(i: number): Vector3
	local o = WorldConfig.plotOrigin(i)
	return o + Vector3.new(GameData.SECTOR_SIZE * WorldConfig.FARM_CELL / 2, 4, 6)
end

return WorldConfig
