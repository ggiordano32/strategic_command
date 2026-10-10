extends RefCounted
## Campaign map geometry (view only, floats allowed): hand-authored low-
## polygon coastlines of the western and central Mediterranean in [lon, lat]
## degrees, an equirectangular projection to map pixels, and each region's
## territory: the Voronoi cell of its settlement among the settlements on the
## same landmass, clipped to that landmass. Built once and cached.

const CData := preload("res://campaign/cdata.gd")

const LON0 := -10.5
const LAT0 := 47.0
const PX_LAT := 100.0          # map pixels per degree of latitude
const PX_LON := 76.6           # ... per degree of longitude (cos 40 deg)
const SIZE := Vector2(36.0 * PX_LON, 14.0 * PX_LAT)

## Landmasses that hold regions (index = CData region "land").
## 0 Europe (Iberia, Gaul, Italy, the Balkans; the north edge of the map
## closes it), 1 North Africa (the south edge closes it), 2 Sicily,
## 3 Sardinia, 4 Corsica.
const LANDS := [
	# 0 Europe: from the Bay of Biscay along the top edge, down the east
	# edge to the Aegean, round Greece, up the Adriatic, round Italy, along
	# the coasts of Gaul and Spain, round Iberia and back up to Biscay.
	[[-2.2, 47.0], [25.5, 47.0], [25.5, 40.9], [24.4, 40.95], [23.9, 40.7], [23.35, 40.2],
	[23.0, 40.5], [22.9, 40.62], [22.55, 40.3], [22.65, 39.95], [22.95, 39.55], [23.2, 39.15],
	[22.85, 38.85], [23.35, 38.45], [23.75, 38.3], [24.05, 38.0], [24.02, 37.65], [23.6, 37.94],
	[23.35, 38.0], [23.0, 37.88], [23.15, 37.55], [23.45, 37.4], [22.75, 37.5], [22.95, 36.95],
	[23.2, 36.44], [22.75, 36.75], [22.48, 36.38], [22.1, 36.95], [21.88, 36.72], [21.6, 37.2],
	[21.3, 37.65], [21.37, 38.15], [22.1, 38.05], [22.88, 37.93], [22.6, 38.22], [22.0, 38.35],
	[21.77, 38.33], [21.43, 38.37], [21.1, 38.5], [20.95, 38.75], [20.75, 38.96], [20.35, 39.3],
	[20.1, 39.65], [20.0, 39.85], [19.48, 40.45], [19.45, 41.3], [19.4, 41.85], [18.7, 42.4],
	[18.1, 42.65], [16.45, 43.5], [15.2, 44.1], [14.4, 45.33], [13.9, 44.8], [13.75, 45.65],
	[12.35, 45.45], [12.5, 44.95], [12.25, 44.4], [12.6, 44.05], [13.52, 43.62], [13.9, 42.9],
	[14.2, 42.46], [15.0, 42.0], [16.1, 41.9], [16.0, 41.65], [16.87, 41.12], [17.95, 40.64],
	[18.5, 40.15], [18.35, 39.8], [17.97, 40.05], [17.24, 40.47], [16.5, 39.75], [17.13, 39.08],
	[17.1, 38.9], [16.55, 38.7], [16.4, 38.3], [16.06, 37.92], [15.64, 38.1], [15.72, 38.25],
	[15.9, 38.7], [16.1, 39.1], [15.8, 39.6], [15.5, 40.05], [15.27, 40.0], [14.98, 40.35],
	[14.76, 40.68], [14.35, 40.6], [14.25, 40.85], [13.57, 41.2], [13.05, 41.22], [12.62, 41.45],
	[12.28, 41.73], [11.8, 42.1], [11.2, 42.45], [10.5, 42.93], [10.3, 43.55], [9.83, 44.1],
	[8.93, 44.4], [8.48, 44.3], [7.77, 43.8], [7.27, 43.7], [7.0, 43.55], [5.93, 43.1],
	[5.37, 43.3], [4.8, 43.35], [4.4, 43.45], [3.9, 43.5], [3.15, 43.15], [3.05, 42.7],
	[3.32, 42.32], [3.15, 42.1], [2.18, 41.38], [1.25, 41.1], [0.85, 40.7], [0.4, 40.35],
	[-0.32, 39.47], [0.23, 38.73], [-0.48, 38.34], [-0.7, 37.63], [-0.98, 37.6], [-2.19, 36.72],
	[-2.46, 36.83], [-4.42, 36.72], [-5.35, 36.13], [-5.6, 36.01], [-6.29, 36.53], [-7.0, 37.2],
	[-7.9, 37.0], [-8.99, 37.02], [-8.87, 37.95], [-9.45, 38.7], [-9.5, 38.78], [-9.4, 39.36],
	[-8.65, 41.15], [-8.85, 42.2], [-9.27, 42.9], [-8.4, 43.37], [-7.87, 43.77], [-5.65, 43.55],
	[-3.8, 43.46], [-2.9, 43.33], [-1.98, 43.32], [-1.56, 43.48], [-1.25, 44.65], [-1.1, 45.6],
	[-1.15, 46.15], [-2.0, 46.7]],
	# 1 North Africa: up the Atlantic coast of Morocco, east along the coast
	# to Tunisia, down to the south edge.
	[[-8.6, 33.0], [-8.5, 33.25], [-7.6, 33.6], [-6.85, 34.0], [-6.6, 34.26], [-6.15, 35.2],
	[-5.92, 35.79], [-5.8, 35.78], [-5.3, 35.9], [-5.2, 35.6], [-4.3, 35.2], [-3.93, 35.25],
	[-2.95, 35.3], [-1.9, 35.1], [-0.65, 35.7], [0.08, 35.93], [1.3, 36.5], [3.06, 36.77],
	[3.9, 36.92], [5.08, 36.75], [5.77, 36.82], [6.57, 37.0], [6.9, 36.88], [7.77, 36.9],
	[8.25, 36.95], [8.75, 36.95], [9.87, 37.27], [10.33, 36.86], [10.2, 36.8], [10.55, 36.95],
	[11.05, 37.08], [11.1, 36.85], [10.6, 36.4], [10.64, 35.83], [10.83, 35.77], [11.07, 35.5],
	[10.76, 34.74], [10.1, 33.88], [10.9, 33.8], [11.4, 33.0]],
	# 2 Sicily.
	[[15.65, 38.27], [15.29, 37.85], [15.09, 37.5], [15.22, 37.23], [15.29, 37.07], [15.13, 36.69],
	[14.85, 36.73], [14.25, 37.07], [13.94, 37.1], [13.58, 37.28], [13.08, 37.5], [12.59, 37.65],
	[12.43, 37.8], [12.51, 38.02], [12.73, 38.18], [13.36, 38.12], [14.02, 38.04], [15.24, 38.27]],
	# 3 Sardinia.
	[[9.15, 41.24], [9.55, 41.1], [9.5, 40.92], [9.73, 40.38], [9.71, 39.94], [9.52, 39.1],
	[9.1, 39.2], [8.85, 38.88], [8.4, 39.05], [8.45, 39.75], [8.52, 39.9], [8.48, 40.3],
	[8.31, 40.56], [8.14, 40.73], [8.22, 40.95], [8.4, 40.84], [8.71, 40.92]],
	# 4 Corsica.
	[[9.42, 43.0], [9.45, 42.7], [9.51, 42.1], [9.28, 41.6], [9.16, 41.39], [8.9, 41.67],
	[8.73, 41.92], [8.69, 42.27], [8.75, 42.57], [9.3, 42.68], [9.35, 42.95]],
]

## Islands without regions (drawn only).
const ISLANDS := [
	# Mallorca, Menorca, Ibiza.
	[[2.35, 39.55], [2.95, 39.95], [3.45, 39.75], [3.25, 39.35], [2.75, 39.4]],
	[[3.8, 39.95], [4.3, 40.05], [4.3, 39.85], [3.85, 39.9]],
	[[1.2, 38.95], [1.5, 39.1], [1.6, 38.95], [1.35, 38.85]],
	# Crete.
	[[23.5, 35.3], [24.3, 35.6], [25.4, 35.35], [25.5, 35.05], [24.6, 35.1], [23.6, 35.2]],
	# Euboea.
	[[22.9, 38.95], [23.35, 38.7], [24.1, 38.2], [24.55, 38.0], [24.1, 38.0], [23.5, 38.45], [22.85, 38.85]],
	# Corfu, Kefalonia, Zakynthos.
	[[19.65, 39.8], [19.95, 39.75], [20.1, 39.4], [19.9, 39.5]],
	[[20.35, 38.45], [20.65, 38.3], [20.55, 38.1], [20.35, 38.2]],
	[[20.65, 37.85], [20.95, 37.75], [20.85, 37.65], [20.65, 37.7]],
	# Elba, Malta.
	[[10.1, 42.82], [10.45, 42.85], [10.4, 42.72], [10.1, 42.75]],
	[[14.2, 36.05], [14.55, 35.9], [14.45, 35.8], [14.25, 35.9]],
]


## Unclaimed land: extra Voronoi sites that belong to no region, so the
## regions' territories do not spill over the Adriatic onto Dalmatia or across
## the whole Sahara. [lon, lat, landmass]. Their cells stay plain land.
const PHANTOMS := [
	[16.6, 43.6, 0], [15.0, 44.8, 0], [18.3, 44.1, 0], [17.5, 46.2, 0], [21.0, 45.5, 0],
	[22.5, 43.3, 0], [24.6, 42.2, 0], [20.6, 42.3, 0], [24.5, 44.5, 0],
	[0.2, 45.6, 0], [-0.8, 44.3, 0], [7.0, 46.6, 0], [10.5, 46.6, 0], [13.5, 46.6, 0],
	[2.0, 34.4, 1], [6.5, 34.2, 1], [-3.0, 34.0, 1], [-5.5, 33.6, 1], [9.0, 33.6, 1],
]

## Rivers (roads, rivers and hills, 2026-10-09; static, rules read the
## baked grid): {name, into (-1: the sea, else the index of the river it
## flows into), pts [lon, lat] from the source down to the mouth, cross
## [[name, kind (0 ford, 1 bridge), lon, lat], ...]}. The grid tool
## (tools/campaign_grid.gd) runs the mouth on until it is in a sea cell (or
## across the river it joins), makes every step between two cells whose
## centres the line separates a river edge and puts each crossing on the
## river's step nearest its point (a road's own step there first).
## Crossing ids: their order over the whole list (crossings()).
const RIVERS := [
	{"name": "Padus", "into": -1,
	"pts": [[7.1, 44.7], [7.65, 45.05], [8.2, 45.15], [8.7, 45.1], [9.2, 45.15], [9.69, 45.07],
	[10.05, 45.12], [10.6, 45.0], [11.2, 45.05], [11.8, 45.0], [12.45, 44.95]],
	"cross": [["Placentia", 1, 9.69, 45.07], ["Cremona", 0, 10.05, 45.12], ["Hostilia", 0, 11.2, 45.05]]},
	{"name": "Tiberis", "into": -1,
	"pts": [[12.05, 43.75], [12.25, 43.35], [12.4, 43.0], [12.45, 42.6], [12.5, 42.35], [12.55, 42.05],
	[12.48, 41.9], [12.35, 41.8], [12.22, 41.72]],
	"cross": [["Pons Sublicius", 1, 12.48, 41.9], ["Tuder", 0, 12.42, 42.78]]},
	{"name": "Arnus", "into": -1,
	"pts": [[11.7, 43.87], [11.8, 43.62], [11.8, 43.5], [11.55, 43.66], [11.25, 43.77], [10.8, 43.7],
	[10.4, 43.72], [10.28, 43.68]],
	"cross": [["Pisae", 1, 10.4, 43.72], ["Faesulae", 0, 11.25, 43.77]]},
	{"name": "Volturnus", "into": -1,
	"pts": [[14.2, 41.75], [14.3, 41.45], [14.4, 41.25], [14.25, 41.12], [14.05, 41.05], [13.93, 41.02]],
	"cross": [["Casilinum", 1, 14.2, 41.1]]},
	{"name": "Aufidus", "into": -1,
	"pts": [[15.1, 40.85], [15.45, 40.95], [15.8, 41.1], [16.05, 41.25], [16.18, 41.5]],
	"cross": [["Pons Aufidi", 1, 15.45, 40.95], ["Cannae", 0, 16.08, 41.32]]},
	{"name": "Rhodanus", "into": -1,
	"pts": [[6.15, 46.3], [5.8, 46.1], [5.5, 45.8], [4.83, 45.76], [4.8, 45.52], [4.82, 45.0],
	[4.75, 44.5], [4.75, 44.1], [4.8, 43.95], [4.63, 43.68], [4.6, 43.38]],
	"cross": [["Arelate", 1, 4.63, 43.68], ["Arausio", 0, 4.75, 44.1], ["Vienna", 0, 4.8, 45.52]]},
	{"name": "Garumna", "into": -1,
	"pts": [[1.5, 43.5], [1.3, 43.75], [1.0, 44.0], [0.5, 44.25], [-0.1, 44.5],
	[-0.57, 44.84], [-0.8, 45.1], [-1.1, 45.55]],
	"cross": [["Tolosa", 0, 1.3, 43.75]]},
	{"name": "Iberus", "into": -1,
	"pts": [[-4.05, 43.0], [-3.5, 42.75], [-2.9, 42.6], [-2.45, 42.45], [-1.9, 42.2], [-1.4, 41.85],
	[-0.88, 41.65], [-0.3, 41.4], [0.2, 41.15], [0.52, 40.81], [0.85, 40.72]],
	"cross": [["Dertosa", 1, 0.52, 40.81], ["Salduie", 0, -0.88, 41.65]]},
	{"name": "Baetis", "into": -1,
	"pts": [[-2.95, 37.9], [-3.5, 38.0], [-4.1, 37.95], [-4.78, 37.88], [-5.4, 37.6], [-5.98, 37.39],
	[-6.2, 37.05], [-6.38, 36.66]],
	"cross": [["Corduba", 1, -4.85, 37.85], ["Hispalis", 0, -5.98, 37.39]]},
	{"name": "Tagus", "into": -1,
	"pts": [[-1.8, 40.4], [-2.6, 40.5], [-3.4, 40.1], [-4.02, 39.8], [-4.8, 39.92], [-5.6, 39.75],
	[-6.5, 39.65], [-7.4, 39.5], [-8.2, 39.35], [-8.7, 39.1], [-9.05, 38.66], [-9.42, 38.66]],
	"cross": [["Toletum", 0, -4.02, 39.8], ["Norba", 1, -6.5, 39.65]]},
	{"name": "Bagradas", "into": -1,
	"pts": [[8.0, 36.3], [8.6, 36.45], [9.18, 36.73], [9.6, 36.75], [9.9, 36.88], [10.05, 37.0],
	[10.12, 37.06]],
	"cross": [["Utica road", 1, 10.0, 36.96], ["Vaga", 0, 9.18, 36.73]]},
	{"name": "Achelous", "into": -1,
	"pts": [[21.1, 39.8], [21.25, 39.4], [21.3, 39.0], [21.35, 38.7], [21.22, 38.47]],
	"cross": [["Stratos", 0, 21.33, 38.68]]},
	{"name": "Peneus", "into": -1,
	"pts": [[21.2, 39.75], [21.6, 39.6], [22.0, 39.55], [22.42, 39.7], [22.6, 39.85], [22.73, 39.86]],
	"cross": [["Larissa", 1, 22.47, 39.74], ["Trikka", 0, 21.77, 39.56]]},
]

## Roads: [name, [lon, lat] points]. The grid tool marks every cell the
## line runs through (4-connected: a diagonal run becomes a staircase) a
## road cell; where a road crosses a river it must do so at a crossing.
const ROADS := [
	["Via Appia", [[12.5, 41.9], [12.9, 41.6], [13.25, 41.29], [13.8, 41.25], [14.2, 41.1], [14.25, 41.08],
	[14.78, 41.3], [15.45, 40.95], [15.81, 40.96], [16.55, 40.65], [17.24, 40.47]]],
	["Via Latina", [[12.5, 41.9], [13.16, 41.73], [13.83, 41.49], [14.1, 41.3], [14.2, 41.1]]],
	["Via Aurelia", [[12.5, 41.9], [12.1, 42.0], [11.6, 42.35], [11.1, 42.6], [10.75, 43.1], [10.45, 43.6],
	[10.4, 43.72], [10.05, 44.05], [9.4, 44.45], [8.95, 44.5]]],
	["Via Cassia", [[12.1, 42.0], [11.99, 42.64], [11.95, 43.02], [11.88, 43.46]]],
	["Via Flaminia", [[12.5, 41.9], [12.62, 42.25], [12.65, 42.55], [12.75, 42.95], [12.85, 43.3],
	[12.95, 43.6], [12.7, 43.9], [12.45, 44.0]]],
	["Via Aemilia", [[12.45, 44.0], [11.9, 44.3], [11.34, 44.49], [10.93, 44.65], [10.3, 44.8], [9.69, 44.95],
	[9.69, 45.25], [9.19, 45.46]]],
	["Patavium road", [[11.34, 44.49], [11.2, 44.8], [11.2, 45.05], [11.5, 45.2], [11.88, 45.41]]],
	["Utica road", [[10.32, 36.85], [10.2, 36.9], [10.0, 36.96], [9.6, 37.05], [9.1, 36.85], [8.5, 36.75],
	[7.77, 36.7], [7.2, 36.55], [6.61, 36.36]]],
	["Hadrumetum road", [[10.32, 36.85], [10.3, 36.5], [10.5, 36.1], [10.6, 35.85]]],
	["Heraklean Way", [[5.37, 43.3], [5.0, 43.5], [4.63, 43.68], [4.36, 43.84], [3.7, 43.55], [3.0, 43.18],
	[2.9, 42.7], [3.0, 42.3], [3.05, 42.15]]],
	["Iberian coast road", [[3.05, 42.15], [2.4, 41.7], [1.2, 41.25], [0.52, 40.81], [0.1, 40.3],
	[-0.27, 39.68], [-0.45, 39.5], [-0.45, 39.1], [-0.9, 38.5], [-1.0, 37.7]]],
	["Baetis road", [[-1.0, 37.7], [-1.8, 37.9], [-3.0, 38.15], [-3.63, 38.15], [-4.3, 38.15], [-4.78, 38.1],
	[-4.9, 37.7], [-5.2, 37.4], [-5.8, 37.0], [-6.25, 36.6]]],
	["Rhone road", [[5.37, 43.3], [5.1, 43.6], [5.05, 44.0], [5.0, 44.5], [5.0, 45.0], [4.95, 45.35],
	[4.87, 45.52]]],
	["Isthmus road", [[23.73, 38.0], [23.4, 38.07], [23.1, 37.98], [22.93, 37.9], [22.85, 37.8],
	[22.72, 37.63], [22.5, 37.35], [22.43, 37.07]]],
	["Thessalian road", [[22.52, 40.76], [22.45, 40.3], [22.55, 40.0], [22.55, 39.85], [22.47, 39.74],
	[22.42, 39.64], [22.38, 39.3], [22.43, 38.95], [22.55, 38.8], [23.0, 38.5], [23.32, 38.32], [23.73, 38.0]]],
	["Sicilian coast road", [[12.6, 37.7], [12.83, 37.7], [13.58, 37.42], [14.25, 37.2], [14.75, 37.0],
	[15.2, 37.1]]],
	["Sicilian east road", [[15.2, 37.1], [15.0, 37.5], [15.1, 37.85], [15.45, 38.15]]],
]

## Hills: {kind (0 hill, 1 ridge), and either "w" (half width, degrees of
## latitude) with "pts" (a ribbon along a line) or "poly" (an area)}, all
## [lon, lat]. A cell whose centre is in one takes that kind where it is
## rougher than its region's own terrain (the region's kind stays the
## default for its other cells). The Alps are ridge, not impassable (their
## high ground is unclaimed land already).
const HILLS := [
	# The Alps' foot (the Maritime Alps round to the Julian).
	{"kind": 1, "poly": [[6.0, 44.2], [7.6, 44.0], [7.5, 44.6], [7.6, 45.3], [8.3, 45.75], [9.5, 45.85],
	[10.5, 45.75], [11.5, 45.8], [12.5, 46.0], [13.6, 46.1], [13.6, 47.0], [5.6, 47.0], [5.6, 45.6],
	[6.0, 45.0]]},
	# The Apennines: hills north and south, a ridge in the middle.
	{"kind": 0, "w": 0.25, "pts": [[8.6, 44.5], [9.5, 44.5], [10.3, 44.3], [11.2, 44.05], [11.9, 43.8], [12.4, 43.5]]},
	{"kind": 1, "w": 0.25, "pts": [[12.4, 43.5], [12.9, 43.0], [13.3, 42.6], [13.6, 42.2], [14.0, 41.85], [14.4, 41.55]]},
	{"kind": 0, "w": 0.25, "pts": [[14.4, 41.55], [15.0, 41.2], [15.5, 40.7], [15.8, 40.2], [16.1, 39.6], [16.2, 39.0],
	[16.1, 38.4]]},
	# Iberia: the Pyrenees, the Cantabrian range, the meseta's edges, the
	# Sierra Nevada.
	{"kind": 1, "w": 0.25, "pts": [[-1.9, 43.05], [-1.0, 42.95], [0.0, 42.75], [1.0, 42.6], [2.0, 42.45], [2.9, 42.45]]},
	{"kind": 1, "w": 0.2, "pts": [[-7.2, 42.9], [-6.0, 43.0], [-4.8, 43.05], [-3.6, 43.0]]},
	{"kind": 0, "w": 0.25, "pts": [[-7.0, 40.2], [-6.0, 40.3], [-5.0, 40.35], [-4.0, 40.75], [-3.3, 41.1]]},
	{"kind": 0, "w": 0.3, "pts": [[-3.0, 42.0], [-2.3, 41.4], [-1.6, 40.8], [-1.2, 40.2]]},
	{"kind": 0, "w": 0.18, "pts": [[-6.5, 38.15], [-5.5, 38.2], [-4.5, 38.35], [-3.5, 38.4], [-2.6, 38.45]]},
	{"kind": 1, "w": 0.2, "pts": [[-5.2, 36.75], [-4.3, 37.0], [-3.3, 37.05], [-2.4, 37.25]]},
	# Africa: the Rif, the Tell Atlas, the Aures.
	{"kind": 0, "w": 0.25, "pts": [[-5.4, 35.3], [-4.5, 35.0], [-3.6, 34.95]]},
	{"kind": 0, "w": 0.3, "pts": [[-1.5, 35.0], [0.5, 35.6], [2.5, 36.1], [4.5, 36.2], [6.0, 36.3], [7.5, 36.35],
	[8.5, 36.3]]},
	{"kind": 1, "w": 0.25, "pts": [[5.8, 35.3], [6.8, 35.2]]},
	# Greece: the Pindus, Olympus, Arcadia, Taygetus.
	{"kind": 1, "w": 0.25, "pts": [[20.3, 40.6], [20.8, 40.1], [21.15, 39.6], [21.45, 39.1], [21.7, 38.8]]},
	{"kind": 1, "w": 0.15, "pts": [[22.1, 40.2], [22.4, 40.05]]},
	{"kind": 0, "w": 0.3, "pts": [[21.9, 37.75], [22.3, 37.5], [22.25, 37.25]]},
	{"kind": 1, "w": 0.12, "pts": [[22.33, 37.2], [22.38, 36.75]]},
	# Sicily's interior and Etna.
	{"kind": 0, "w": 0.25, "pts": [[13.2, 37.75], [13.8, 37.65], [14.4, 37.6], [14.8, 37.55]]},
	{"kind": 1, "w": 0.15, "pts": [[14.9, 37.75], [15.0, 37.75]]},
]

static var _cells: Array = []
static var _anchors: Array = []
static var _lands: Array = []
static var _islands: Array = []


static func project(lon: float, lat: float) -> Vector2:
	return Vector2((lon - LON0) * PX_LON, (LAT0 - lat) * PX_LAT)


static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(project(float(p[0]), float(p[1])))
	return out


## Land polygons in map pixels.
static func lands() -> Array:
	if _lands.is_empty():
		for l in LANDS:
			_lands.append(_poly(l))
	return _lands


static func islands() -> Array:
	if _islands.is_empty():
		for l in ISLANDS:
			_islands.append(_poly(l))
	return _islands


## Settlement position of region r in map pixels.
static func site(r: int) -> Vector2:
	var rd: Dictionary = CData.REGIONS[r]
	return project(int(rd["lon"]) / 100.0, int(rd["lat"]) / 100.0)


## Territory of region r: Array of polygons (map pixels).
static func cell(r: int) -> Array:
	if _cells.is_empty():
		_build_cells()
	return _cells[r]


## Where a region's armies are drawn: inside its territory, a little
## away from the settlement towards the territory's centre.
static func anchor(r: int) -> Vector2:
	if _cells.is_empty():
		_build_cells()
	return _anchors[r]


static func _build_cells() -> void:
	var n := CData.region_count()
	var land_polys := lands()
	_cells.resize(n)
	_anchors.resize(n)
	var big := PackedVector2Array([Vector2(-200, -200), Vector2(SIZE.x + 200, -200),
		Vector2(SIZE.x + 200, SIZE.y + 200), Vector2(-200, SIZE.y + 200)])
	for r in n:
		var p := site(r)
		var land := int(CData.REGIONS[r]["land"])
		var poly := big
		for q in n:
			if q == r or int(CData.REGIONS[q]["land"]) != land:
				continue
			poly = _clip_half(poly, p, site(q))
			if poly.size() < 3:
				break
		for ph in PHANTOMS:
			if int(ph[2]) == land and poly.size() >= 3:
				poly = _clip_half(poly, p, project(float(ph[0]), float(ph[1])))
		var pieces: Array = []
		for piece in Geometry2D.intersect_polygons(poly, land_polys[land]):
			if not Geometry2D.is_polygon_clockwise(piece) and piece.size() >= 3:
				pieces.append(piece)
			elif piece.size() >= 3:
				pieces.append(piece)
		_cells[r] = pieces
		# Anchor: centroid of the piece holding the settlement, pulled half
		# way to the settlement, nudged below it if they nearly coincide.
		var best: PackedVector2Array = PackedVector2Array()
		for piece in pieces:
			if Geometry2D.is_point_in_polygon(p, piece):
				best = piece
		if best.is_empty() and not pieces.is_empty():
			best = pieces[0]
		var c := _centroid(best) if not best.is_empty() else p
		var a := p.lerp(c, 0.55)
		if a.distance_to(p) < 22.0:
			a = p + Vector2(0, 24)
		if not best.is_empty() and not Geometry2D.is_point_in_polygon(a, best):
			a = p + Vector2(0, 24)
		_anchors[r] = a


## Keep the half of polygon `poly` closer to a than to b (Sutherland-Hodgman
## against the perpendicular bisector).
static func _clip_half(poly: PackedVector2Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	var mid := (a + b) * 0.5
	var nrm := b - a
	var out := PackedVector2Array()
	var cnt := poly.size()
	for i in cnt:
		var s := poly[i]
		var e := poly[(i + 1) % cnt]
		var ds := (s - mid).dot(nrm)
		var de := (e - mid).dot(nrm)
		if ds <= 0.0:
			out.append(s)
		if (ds <= 0.0) != (de <= 0.0):
			var t := ds / (ds - de)
			out.append(s.lerp(e, t))
	return out


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var area := 0.0
	var c := Vector2.ZERO
	var cnt := poly.size()
	for i in cnt:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % cnt]
		var cr := p0.cross(p1)
		area += cr
		c += (p0 + p1) * cr
	if absf(area) < 1e-3:
		return poly[0]
	return c / (3.0 * area)


## Region whose territory contains map point p (-1 for the sea).
static func region_at(p: Vector2) -> int:
	for r in CData.region_count():
		for piece in cell(r):
			if Geometry2D.is_point_in_polygon(p, piece):
				return r
	return -1


## Every river crossing in id order: {id, name, kind (0 ford, 1 bridge),
## river (index in RIVERS), p (map pixels)}.
static func crossings() -> Array:
	var out: Array = []
	for i in RIVERS.size():
		for c in RIVERS[i]["cross"]:
			out.append({"id": out.size(), "name": str(c[0]), "kind": int(c[1]), "river": i,
				"p": project(float(c[2]), float(c[3]))})
	return out


## River i's line in map pixels (source to mouth, as authored).
static func river_line(i: int) -> PackedVector2Array:
	return _poly(RIVERS[i]["pts"])


## Road i's line in map pixels.
static func road_line(i: int) -> PackedVector2Array:
	return _poly(ROADS[i][1])


## The cells (index y * w + x of a grid of `cpx` px cells, w wide) a
## polyline runs through, in order and 4-connected (a diagonal move gets
## the orthogonal cell nearer the line in between). Shared by the grid tool
## (road cells) and the map view (the road drawn through them).
static func line_cells(line: PackedVector2Array, cpx: float, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var last := Vector2i(-1, -1)
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var n := maxi(int(ceil(a.distance_to(b) / (cpx * 0.1))), 1)
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var q := Vector2i(clampi(int(p.x / cpx), 0, w - 1), clampi(int(p.y / cpx), 0, h - 1))
			if q == last:
				continue
			if last.x >= 0 and q.x != last.x and q.y != last.y:
				# Diagonal: the orthogonal cell whose centre is nearer the line.
				var o1 := Vector2i(q.x, last.y)
				var o2 := Vector2i(last.x, q.y)
				var c1 := (Vector2(o1) + Vector2(0.5, 0.5)) * cpx
				var c2 := (Vector2(o2) + Vector2(0.5, 0.5)) * cpx
				var d1 := c1.distance_to(Geometry2D.get_closest_point_to_segment(c1, a, b))
				var d2 := c2.distance_to(Geometry2D.get_closest_point_to_segment(c2, a, b))
				var o := o1 if d1 <= d2 else o2
				out.append(o.y * w + o.x)
			out.append(q.y * w + q.x)
			last = q
	return out
