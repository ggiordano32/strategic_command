extends RefCounted
## The nav grid of tests/data/dummy_pack.gd: 4 x 2 cells, region A on the
## left, B on the right, no rivers.

const CELL_PX := 20
const W := 4
const H := 2
const SITE: Array[int] = [0, 3]
const PORT: Array[int] = [-1, -1]
const CAMP: Array[int] = [4, 7]
const OVERRIDES: Array[int] = []
const RIVER: Array[int] = []
const CROSS: Array[int] = []
const TERRAIN: Array[String] = ["....", "...."]
const ROWS: Array[String] = ["AABB", "AABB"]
