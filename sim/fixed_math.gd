class_name FixedMath
extends RefCounted
## Integer-only maths for the deterministic battle sim. No floats anywhere.
##
## Distances: 1 metre = 1024 units (UNITS_PER_M).
## Angles: 0..1023 for a full turn (ANGLE_FULL). Angle 0 points along +x and
## angles increase toward +y (clockwise on screen, y down), like Godot's
## rotation, so the view converts with angle * TAU / 1024.
## Trig values are Q12 fixed point (4096 = 1.0).
##
## The tables below are hardcoded constants (generated once offline). They are
## data, not computed at runtime, so every platform sees identical values.

const UNITS_PER_M := 1024
const ANGLE_FULL := 1024
const ANGLE_MASK := 1023
const ANGLE_HALF := 512
const ANGLE_QUARTER := 256
const TRIG_ONE := 4096
const TRIG_SHIFT := 12

## sin for angles 0..256 (a quarter turn), Q12.
const SIN_QUARTER: Array[int] = [
	0, 25, 50, 75, 101, 126, 151, 176, 201, 226, 251, 276, 301, 326, 351, 376, 401, 426,
	451, 476, 501, 526, 551, 576, 601, 626, 651, 675, 700, 725, 750, 774, 799, 824, 848,
	873, 897, 922, 946, 971, 995, 1020, 1044, 1068, 1092, 1117, 1141, 1165, 1189, 1213,
	1237, 1261, 1285, 1309, 1332, 1356, 1380, 1404, 1427, 1451, 1474, 1498, 1521, 1544,
	1567, 1591, 1614, 1637, 1660, 1683, 1706, 1729, 1751, 1774, 1797, 1819, 1842, 1864,
	1886, 1909, 1931, 1953, 1975, 1997, 2019, 2041, 2062, 2084, 2106, 2127, 2149, 2170,
	2191, 2213, 2234, 2255, 2276, 2296, 2317, 2338, 2359, 2379, 2399, 2420, 2440, 2460,
	2480, 2500, 2520, 2540, 2559, 2579, 2598, 2618, 2637, 2656, 2675, 2694, 2713, 2732,
	2751, 2769, 2788, 2806, 2824, 2843, 2861, 2878, 2896, 2914, 2932, 2949, 2967, 2984,
	3001, 3018, 3035, 3052, 3068, 3085, 3102, 3118, 3134, 3150, 3166, 3182, 3198, 3214,
	3229, 3244, 3260, 3275, 3290, 3305, 3320, 3334, 3349, 3363, 3378, 3392, 3406, 3420,
	3433, 3447, 3461, 3474, 3487, 3500, 3513, 3526, 3539, 3551, 3564, 3576, 3588, 3600,
	3612, 3624, 3636, 3647, 3659, 3670, 3681, 3692, 3703, 3713, 3724, 3734, 3745, 3755,
	3765, 3775, 3784, 3794, 3803, 3812, 3822, 3831, 3839, 3848, 3857, 3865, 3873, 3881,
	3889, 3897, 3905, 3912, 3920, 3927, 3934, 3941, 3948, 3954, 3961, 3967, 3973, 3979,
	3985, 3991, 3996, 4002, 4007, 4012, 4017, 4022, 4027, 4031, 4036, 4040, 4044, 4048,
	4052, 4055, 4059, 4062, 4065, 4068, 4071, 4074, 4076, 4079, 4081, 4083, 4085, 4087,
	4088, 4090, 4091, 4092, 4093, 4094, 4095, 4095, 4096, 4096, 4096
]

## atan(i / 256) for i in 0..256, in angle units (0..128 = one eighth turn).
const ATAN_TABLE: Array[int] = [
	0, 1, 1, 2, 3, 3, 4, 4, 5, 6, 6, 7, 8, 8, 9, 10, 10, 11, 11, 12, 13, 13, 14, 15, 15, 16,
	16, 17, 18, 18, 19, 20, 20, 21, 22, 22, 23, 23, 24, 25, 25, 26, 27, 27, 28, 28, 29, 30,
	30, 31, 31, 32, 33, 33, 34, 34, 35, 36, 36, 37, 38, 38, 39, 39, 40, 41, 41, 42, 42, 43,
	44, 44, 45, 45, 46, 46, 47, 48, 48, 49, 49, 50, 51, 51, 52, 52, 53, 53, 54, 55, 55, 56,
	56, 57, 57, 58, 58, 59, 60, 60, 61, 61, 62, 62, 63, 63, 64, 65, 65, 66, 66, 67, 67, 68,
	68, 69, 69, 70, 70, 71, 71, 72, 72, 73, 74, 74, 75, 75, 76, 76, 77, 77, 78, 78, 79, 79,
	80, 80, 81, 81, 82, 82, 83, 83, 84, 84, 84, 85, 85, 86, 86, 87, 87, 88, 88, 89, 89, 90,
	90, 91, 91, 91, 92, 92, 93, 93, 94, 94, 95, 95, 96, 96, 96, 97, 97, 98, 98, 99, 99, 99,
	100, 100, 101, 101, 102, 102, 102, 103, 103, 104, 104, 104, 105, 105, 106, 106, 106,
	107, 107, 108, 108, 108, 109, 109, 110, 110, 110, 111, 111, 112, 112, 112, 113, 113,
	113, 114, 114, 115, 115, 115, 116, 116, 116, 117, 117, 118, 118, 118, 119, 119, 119,
	120, 120, 120, 121, 121, 121, 122, 122, 122, 123, 123, 123, 124, 124, 124, 125, 125,
	125, 126, 126, 126, 127, 127, 127, 128, 128
]


static func sin_a(a: int) -> int:
	a = a & ANGLE_MASK
	if a < 256:
		return SIN_QUARTER[a]
	elif a < 512:
		return SIN_QUARTER[512 - a]
	elif a < 768:
		return -SIN_QUARTER[a - 512]
	return -SIN_QUARTER[1024 - a]


static func cos_a(a: int) -> int:
	return sin_a(a + 256)


## Angle (0..1023) of the vector (x, y). Returns 0 for the zero vector.
static func atan2_a(y: int, x: int) -> int:
	if x == 0 and y == 0:
		return 0
	var ax := absi(x)
	var ay := absi(y)
	var oct: int
	if ax >= ay:
		oct = ATAN_TABLE[(ay * 256) / ax]
	else:
		oct = 256 - ATAN_TABLE[(ax * 256) / ay]
	# oct is the angle in the first quadrant, 0..256.
	if x >= 0:
		if y >= 0:
			return oct & ANGLE_MASK
		return (1024 - oct) & ANGLE_MASK
	if y >= 0:
		return 512 - oct
	return (512 + oct) & ANGLE_MASK


## Signed shortest difference b - a, in -512..511.
static func angle_diff(a: int, b: int) -> int:
	return ((b - a + 512) & ANGLE_MASK) - 512


## Integer square root (floor) of a non-negative int.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := n
	var y := (x + 1) >> 1
	while y < x:
		x = y
		y = (x + n / x) >> 1
	return x


## Cheap distance approximation (alpha max plus beta min, error < 4%).
static func approx_len(dx: int, dy: int) -> int:
	var ax := absi(dx)
	var ay := absi(dy)
	if ax > ay:
		return ax - (ax >> 5) + ((ay * 3) >> 3) + (ay >> 6)
	return ay - (ay >> 5) + ((ax * 3) >> 3) + (ax >> 6)
