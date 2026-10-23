#!/usr/bin/env python3
"""Generate game/sounds/*.wav (audio, docs/STATUS.md item 8b).

Procedural, deterministic (fixed seeds), 22,050 Hz mono 16-bit. Each clip is
built from filtered noise, decaying sines and short envelopes; nothing is a
raw square wave. Run: python3 tools/make_sounds.py
"""
import os
import wave
import zlib

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "sounds")


def rng(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def t_of(d):
    return np.arange(int(SR * d)) / SR


def noise(r, d):
    return r.standard_normal(int(SR * d))


def band(x, lo, hi):
    """FFT band-pass (lo/hi Hz; lo=0 low-pass, hi=0 high-pass)."""
    s = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    m = np.ones_like(f)
    if lo > 0:
        m *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** 4)
    if hi > 0:
        m *= 1.0 / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(s * m, len(x))


def env(n, a, d, shape=3.0):
    """Attack a s, then decay to zero over the rest (exp-ish)."""
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), np.exp(-(t - a) * shape / max(d, 1e-3)))
    e[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    return e


def tone(f, d, a=0.005, shape=5.0, harm=(1.0, 0.3, 0.1), det=0.0):
    t = t_of(d)
    y = sum(h * np.sin(2 * np.pi * f * (k + 1) * (1 + det) * t) for k, h in enumerate(harm))
    return y * env(len(t), a, d, shape)


def sweep(f0, f1, d, a=0.005, shape=4.0):
    t = t_of(d)
    f = f0 * (f1 / f0) ** (t / d)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.25 * np.sin(2 * ph)) * env(len(t), a, d, shape)


def place(y, x, at, g=1.0):
    i = int(at * SR)
    n = min(len(x), len(y) - i)
    if n > 0:
        y[i:i + n] += g * x[:n]


def finish(x, peak=0.8):
    x = x - np.mean(x)
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def clicks(r, d, times, f=(2500, 6000), g=1.0, ring=(900, 1700, 2600)):
    """Metallic ticks: a noise burst plus a few inharmonic decaying rings."""
    y = np.zeros(int(SR * d))
    for at in times:
        n = noise(r, 0.12)
        c = band(n, f[0], f[1]) * env(len(n), 0.0005, 0.012, 4)
        rf = r.choice(ring) * (0.9 + 0.2 * r.random())
        c = c + 0.6 * tone(rf, 0.12, 0.0005, 6, (1.0, 0.45, 0.2))
        place(y, c, at, g * (0.6 + 0.4 * r.random()))
    return y


# --------------------------------------------------------------- battle ----

def melee_clash():
    r = rng("melee")
    y = clicks(r, 0.5, [0.0, 0.07, 0.13, 0.22, 0.31], g=0.8)
    y += 0.3 * band(noise(r, 0.5), 200, 1500) * env(int(SR * 0.5), 0.01, 0.2, 3)
    return y


def charge_impact():
    r = rng("charge")
    y = np.zeros(int(SR * 0.9))
    place(y, sweep(130, 45, 0.5, 0.002, 5), 0, 1.0)
    place(y, band(noise(r, 0.3), 80, 600) * env(int(SR * 0.3), 0.001, 0.1, 4), 0, 0.9)
    place(y, clicks(r, 0.6, [0.05, 0.11, 0.17, 0.26, 0.38], g=0.6), 0.04)
    return y


def bow_volley():
    r = rng("volley")
    n = noise(r, 0.7)
    t = t_of(0.7)
    bp = band(n, 1800, 5000)
    sw = np.exp(-((t - 0.28) / 0.17) ** 2)  # rises then falls like arrows passing
    y = bp * sw
    place(y, band(noise(r, 0.08), 300, 1200) * env(int(SR * 0.08), 0.001, 0.03, 4), 0.0, 0.8)  # string thrum
    return y


def whoosh():
    r = rng("whoosh")
    t = t_of(0.45)
    y = band(noise(r, 0.45), 900, 3500) * np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 2
    return y


def bolt_release():
    r = rng("bolt")
    y = np.zeros(int(SR * 0.7))
    place(y, tone(180, 0.5, 0.001, 7, (1.0, 0.6, 0.3, 0.2)) * (1 + 0.3 * np.sin(2 * np.pi * 38 * t_of(0.5))), 0)
    place(y, sweep(110, 50, 0.3, 0.001, 6), 0.0, 0.9)
    place(y, band(noise(r, 0.12), 500, 3000) * env(int(SR * 0.12), 0.0005, 0.04, 4), 0, 0.5)
    return y


def bolt_impact():
    r = rng("boltimp")
    y = np.zeros(int(SR * 0.45))
    place(y, band(noise(r, 0.3), 100, 1400) * env(int(SR * 0.3), 0.001, 0.07, 4), 0)
    place(y, sweep(180, 70, 0.25, 0.001, 7), 0, 0.8)
    place(y, clicks(r, 0.2, [0.0, 0.03], g=0.4), 0)
    return y


def stone_release():
    r = rng("stonerel")
    y = np.zeros(int(SR * 1.1))
    t = t_of(0.7)
    creak = band(noise(r, 0.7), 150, 700) * (0.6 + 0.4 * np.sin(2 * np.pi * 14 * t * (1 + t))) * np.sin(np.pi * t / 0.7)
    place(y, creak, 0, 0.7)
    place(y, sweep(120, 38, 0.4, 0.002, 4), 0.62, 1.0)
    place(y, band(noise(r, 0.2), 80, 500) * env(int(SR * 0.2), 0.001, 0.07, 4), 0.62, 0.6)
    return y


def stone_impact():
    r = rng("stoneimp")
    y = np.zeros(int(SR * 1.3))
    place(y, sweep(95, 30, 1.0, 0.002, 3.2), 0, 1.0)
    place(y, band(noise(r, 0.6), 40, 400) * env(int(SR * 0.6), 0.002, 0.25, 3), 0, 0.9)
    place(y, band(noise(r, 0.5), 600, 3000) * env(int(SR * 0.5), 0.003, 0.1, 4), 0.02, 0.35)
    return y


def explosive_burst():
    r = rng("burst")
    y = np.zeros(int(SR * 1.5))
    place(y, sweep(110, 28, 1.3, 0.002, 3.0), 0, 1.0)
    place(y, band(noise(r, 1.0), 40, 700) * env(int(SR * 1.0), 0.002, 0.35, 3), 0, 1.0)
    cr = band(noise(r, 1.0), 2000, 7000)
    cr *= (r.random(len(cr)) < 0.12) * env(len(cr), 0.05, 0.4, 3)  # sparse crackle
    place(y, band(cr, 1500, 8000), 0.1, 1.2)
    return y


def musket_volley():
    """A ragged volley of matchlocks: sharp cracks spread over ~0.35 s on a
    low thump, then a rolling echo (West slice 2a)."""
    r = rng("musket")
    y = np.zeros(int(SR * 1.4))
    for k in range(26):
        at = 0.35 * (r.random() ** 1.6)
        n = noise(r, 0.09)
        c = band(n, 500, 6000) * env(len(n), 0.0004, 0.018, 5)
        c += 0.5 * band(noise(r, 0.09), 60, 400) * env(len(n), 0.001, 0.04, 4)
        place(y, c, at, 0.35 + 0.5 * r.random())
    place(y, sweep(90, 40, 0.5, 0.002, 4), 0.0, 0.5)
    roll = band(noise(r, 1.2), 80, 900) * env(int(SR * 1.2), 0.08, 0.9, 3)
    place(y, roll, 0.05, 0.45)
    return y


def cannon():
    """A gun's report: a deep boom with a sharp crack and a long rumble."""
    r = rng("cannon")
    y = np.zeros(int(SR * 1.5))
    place(y, sweep(70, 24, 1.3, 0.001, 2.6), 0, 1.0)
    place(y, band(noise(r, 1.4), 30, 300) * env(int(SR * 1.4), 0.002, 0.6, 2.8), 0, 1.0)
    place(y, band(noise(r, 0.15), 800, 6000) * env(int(SR * 0.15), 0.0003, 0.03, 5), 0, 0.7)
    return y


def fire_loop():
    """12 s of low roar with randomised crackle (about 15 pops a second, a few
    bigger snaps); circular, so the loop point is seamless."""
    r = rng("fire12")
    d = 12.0
    n = int(SR * d)
    base = band(noise(r, d), 100, 900) * 0.5 * (0.8 + 0.2 * wander(r, n, 2.5))
    pops = np.zeros(n)
    for _ in range(180):
        at = int(r.random() * n)
        w = band(noise(r, 0.03), 1500, 6000) * env(int(SR * 0.03), 0.0005, 0.008, 4)
        pops += np.roll(np.pad(w, (0, n - len(w))), at) * (0.3 + r.random() ** 2 * 1.4)
    return base + pops * 1.2


def gate_blow():
    r = rng("gateblow")
    y = np.zeros(int(SR * 0.7))
    place(y, sweep(210, 85, 0.35, 0.001, 6), 0)
    place(y, band(noise(r, 0.25), 150, 1200) * env(int(SR * 0.25), 0.001, 0.07, 4), 0, 0.8)
    place(y, tone(320, 0.4, 0.001, 8, (1.0, 0.3)), 0.01, 0.3)  # board resonance
    return y


def gate_break():
    r = rng("gatebreak")
    y = np.zeros(int(SR * 1.4))
    place(y, sweep(160, 50, 0.6, 0.001, 4), 0, 1.0)
    for i in range(14):
        at = 0.02 + i * 0.045 + 0.03 * r.random()
        p = band(noise(r, 0.12), 400 + 300 * r.random(), 3500) * env(int(SR * 0.12), 0.001, 0.03, 4)
        place(y, p, at, 0.7 * np.exp(-at * 1.5))
    place(y, band(noise(r, 1.0), 60, 900) * env(int(SR * 1.0), 0.05, 0.5, 3), 0.15, 0.5)
    return y


def creak():
    r = rng("creak")
    d = 0.9
    t = t_of(d)
    f = 95 + 35 * np.sin(2 * np.pi * 2.3 * t) + 20 * r.random()
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = (np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.4 * np.sin(3 * ph)) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 9 * t)))
    y = band(y + 0.3 * noise(r, d), 90, 1400)
    return y * np.sin(np.pi * t / d) ** 1.5


def unit_break():
    r = rng("break")
    d = 0.9
    t = t_of(d)
    f = 520 + 380 * np.sin(np.pi * t / d) + 18 * np.sin(2 * np.pi * 6 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    voice = band(noise(r, d), 400, 2500) * 0.9 + 0.5 * np.sin(ph)
    voice = band(voice, 350, 2200)
    return voice * np.sin(np.pi * t / d) ** 1.2


def horn_note(f, d, a=0.06, rel=0.25):
    t = t_of(d)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5 * t)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    y = sum(h * np.sin((k + 1) * ph) for k, h in enumerate((1.0, 0.7, 0.45, 0.25, 0.12)))
    e = np.minimum(t / a, 1.0) * np.minimum((d - t) / rel, 1.0)
    return band(y, 80, 2500) * np.clip(e, 0, 1)


def rally_horn():
    return horn_note(392, 0.5, 0.05, 0.2)


def horn_start():
    y = np.zeros(int(SR * 1.5))
    place(y, horn_note(220, 0.55), 0)
    place(y, horn_note(293.7, 0.85, 0.05, 0.4), 0.5)
    return y


def horn_victory():
    y = np.zeros(int(SR * 1.5))
    for i, (f, d) in enumerate(((261.6, 0.3), (329.6, 0.3), (392, 0.3), (523.3, 0.9))):
        place(y, horn_note(f, d, 0.04, 0.15 if i < 3 else 0.4), i * 0.28)
    return y


def horn_defeat():
    y = np.zeros(int(SR * 1.5))
    for i, (f, d) in enumerate(((246.9, 0.45), (207.7, 0.45), (164.8, 0.95))):
        place(y, horn_note(f, d, 0.08, 0.3), i * 0.45)
    return y


def elephant():
    r = rng("elephant")
    d = 1.1
    t = t_of(d)
    f = 280 + 260 * np.sin(np.pi * np.clip(t / 0.8, 0, 1)) ** 0.7
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = sum(h * np.sin((k + 1) * ph) for k, h in enumerate((1.0, 0.8, 0.5, 0.3, 0.2)))
    y = band(y * (1 + 0.5 * np.sin(2 * np.pi * 28 * t)) + 0.5 * noise(r, d), 150, 3000)
    return y * np.minimum(t / 0.08, 1) * np.clip((d - t) / 0.3, 0, 1)


def dogs():
    r = rng("dogs")
    y = np.zeros(int(SR * 1.2))
    for at, f0 in ((0.0, 520), (0.2, 480), (0.45, 560), (0.7, 500), (0.85, 450)):
        d = 0.14
        t = t_of(d)
        ph = 2 * np.pi * np.cumsum(f0 * (1 - 0.35 * t / d)) / SR
        b = band(np.sin(ph) + 0.7 * np.sin(2 * ph) + 0.4 * band(noise(r, d), 500, 3000), 300, 3000)
        place(y, b * env(len(t), 0.008, d, 4), at, 0.8)
    return y


BED_D = 48.0   # loop length of the two beds, s
BED_X = 2.0    # equal-power crossfade at the loop point, s
BED_RMS = 10 ** (-28 / 20)


def wander(r, n, period):
    """Smooth random curve in 0..1 (cosine-interpolated knots every ~period s)."""
    k = int(n / SR / period) + 3
    kn = r.random(k)
    pos = np.arange(n) / SR / period
    i = pos.astype(int)
    f = (1 - np.cos(np.pi * (pos - i))) / 2
    return kn[i] * (1 - f) + kn[i + 1] * f


def swell(r, n, period, jitter=0.25):
    """Surf-swell envelope: a phase that advances at 1/period Hz, the period
    on a random walk (+-jitter), so no swell repeats exactly. 0..1, peaky."""
    wk = band(r.standard_normal(n), 0, 0.15)
    wk = wk / np.max(np.abs(wk))
    f = (1.0 / period) / (1 + jitter * wk)
    ph = 2 * np.pi * np.cumsum(f) / SR + 2 * np.pi * r.random()
    return (0.5 + 0.5 * np.sin(ph)) ** 1.6


def seamless(g, x_s=BED_X):
    """g is BED_D + x_s long; crossfade its tail into its head (equal power) and
    return BED_D s whose last sample runs on into its first."""
    n = int(SR * BED_D)
    x = int(SR * x_s)
    out = g[:n].copy()
    u = np.linspace(0, 1, x, endpoint=False)
    out[:x] = g[:x] * np.sin(u * np.pi / 2) + g[n:n + x] * np.cos(u * np.pi / 2)
    out -= np.mean(out)
    return out * min(1.0, 10 ** (-12 / 20) / np.max(np.abs(out)))  # peak at most -12 dBFS


def gull(r):
    """One gull cry: 2-4 falling-rising 'kyow' syllables, a formant-ish buzz."""
    out = np.zeros(int(SR * 2.2))
    at = 0.0
    f0 = 1500 + 500 * r.random()
    for k in range(int(r.integers(2, 5))):
        d = 0.28 + 0.12 * r.random()
        t = t_of(d)
        u = t / d
        f = f0 * (1.25 - 0.55 * u + 0.25 * np.sin(np.pi * u) ** 2) * (1 - 0.06 * k)
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = np.sin(ph) + 0.55 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph)
        y *= 1 + 0.35 * np.sin(2 * np.pi * (45 + 15 * r.random()) * t)
        y = band(y + 0.15 * noise(r, d), 700, 5000) * np.sin(np.pi * u) ** 0.8
        place(out, y, at, 1.0 - 0.12 * k)
        at += d + 0.1 + 0.1 * r.random()
    return out


def crow(r):
    """A far crow: two or three rough low 'caw's."""
    out = np.zeros(int(SR * 2.0))
    at = 0.0
    for k in range(int(r.integers(2, 4))):
        d = 0.32
        t = t_of(d)
        f = 420 - 110 * t / d
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = sum(h * np.sin((i + 1) * ph) for i, h in enumerate((1.0, 0.7, 0.55, 0.4, 0.25)))
        y *= 0.55 + 0.45 * np.sin(2 * np.pi * 70 * t)
        y = band(y + 0.3 * noise(r, d), 300, 3200) * np.sin(np.pi * t / d) ** 0.7
        place(out, y, at, 1.0 - 0.15 * k)
        at += d + 0.15 + 0.1 * r.random()
    return out


def events(r, fns, counts, gains, total, lo=6.0, hi=6.0, gap=5.0):
    """Place event clips at random times, none within lo s of the start or hi s
    of the end of the loop and none closer than gap s to another."""
    y = np.zeros(total)
    d = total / SR
    taken = []
    for fn, c, g in zip(fns, counts, gains):
        for _ in range(c):
            for _try in range(200):
                at = lo + r.random() * (d - lo - hi - 2.5)
                if all(abs(at - o) > gap for o in taken):
                    break
            taken.append(at)
            e = fn(r)
            place(y, e / np.max(np.abs(e)), at, g * 0.25 * (0.7 + 0.3 * r.random()))  # g: share of the -12 dBFS peak
    return y


def rig_creak(r):
    """Far-off rigging: a slow low groan, band-limited and soft."""
    d = 1.8
    t = t_of(d)
    f = 130 + 25 * np.sin(2 * np.pi * 1.1 * t) + 10 * wander(r, len(t), 0.4)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.4 * np.sin(3 * ph)
    y *= 0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 5.5 * t))
    y = band(y + 0.3 * noise(r, d), 100, 900)
    return y * np.sin(np.pi * t / d) ** 2


def map_bed():
    """48 s sea bed: two surf layers on ~7 s and ~11 s swells (random-walk
    periods), a low wind with a 20-40 s drift, 2-3 gulls and one rigging creak."""
    r = rng("mapbed48")
    n = int(SR * (BED_D + BED_X))
    surf1 = band(noise(r, BED_D + BED_X), 120, 1100) * (0.12 + swell(r, n, 7.0))
    surf2 = band(noise(r, BED_D + BED_X), 500, 3500) * (0.05 + swell(r, n, 11.0)) * 0.45
    wind = band(noise(r, BED_D + BED_X), 90, 420) * (0.2 + wander(r, n, 30.0)) * 0.8
    base = surf1 + surf2 + wind
    base *= BED_RMS / np.sqrt(np.mean(base ** 2))
    ev = events(r, (gull, rig_creak), (int(r.integers(2, 4)), 1), (0.9, 0.45), n,
                hi=6.0 + BED_X)
    return seamless(base + ev)


def _battle_base(r, n, wind_lo=70, wind_hi=520, rum=2.2, gain=1.25):
    """The shared battlefield floor: low wind, a very slow distant rumble."""
    wind = band(noise(r, BED_D + BED_X), wind_lo, wind_hi) * (0.25 + wander(r, n, 25.0))
    wind += 0.35 * band(noise(r, BED_D + BED_X), 400, 1600) * (0.1 + wander(r, n, 9.0))
    rm = band(noise(r, BED_D + BED_X), 25, 110) * (0.15 + wander(r, n, 17.0)) * rum
    base = wind + rm
    return base * gain * BED_RMS / np.sqrt(np.mean(base ** 2))


def battle_bed():
    """Coast battlefield bed (file bed_battle): the old low wind and distant rumble
    plus a far, soft surf on a slow ~13 s swell and 1-2 gulls and a far crow."""
    r = rng("battlebed48")
    n = int(SR * (BED_D + BED_X))
    base = _battle_base(r, n)
    surf = band(noise(r, BED_D + BED_X), 150, 1400) * (0.1 + swell(r, n, 13.0, 0.3))
    surf *= 0.45 * BED_RMS / np.sqrt(np.mean(surf ** 2))  # far: well under the wind
    ev = events(r, (crow, gull), (1, int(r.integers(1, 3))), (0.4, 0.5), n, hi=6.0 + BED_X)
    return seamless(base + surf + ev)


def cicada(r):
    """One cicada's buzz: a 3.5-5 kHz carrier pulsed at 55-90 Hz, swelling in and out over 2-6 s."""
    d = 2.0 + 4.0 * r.random()
    t = t_of(d)
    f = 3600 + 1300 * r.random()
    y = np.sin(2 * np.pi * f * t + 3 * np.sin(2 * np.pi * 7 * t))
    y *= 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (55 + 35 * r.random()) * t)) * 0.8
    y = band(y + 0.25 * noise(r, d), 2500, 6500)
    return y * np.sin(np.pi * t / d) ** 1.5


def dog_bark(r):
    """A far dog: two low barks, soft and band-limited."""
    out = np.zeros(int(SR * 1.2))
    for at in (0.0, 0.4 + 0.1 * r.random()):
        d = 0.16
        t = t_of(d)
        ph = 2 * np.pi * np.cumsum(430 * (1 - 0.35 * t / d)) / SR
        y = band(np.sin(ph) + 0.7 * np.sin(2 * ph) + 0.4 * band(noise(r, d), 400, 2200), 250, 2200)
        place(out, y * env(len(t), 0.01, d, 4), at, 1.0)
    return out


def cricket(r):
    """A cricket's chirp: 3-4 pulses of a ~4.6 kHz tone."""
    out = np.zeros(int(SR * 0.4))
    f = 4300 + 600 * r.random()
    for k in range(int(r.integers(3, 5))):
        d = 0.03
        t = t_of(d)
        place(out, np.sin(2 * np.pi * f * t) * np.sin(np.pi * t / d), 0.07 * k, 1.0)
    return out


def tree_frog(r):
    """A tree frog: a short rising 'krik' trill around 2 kHz."""
    d = 0.22 + 0.1 * r.random()
    t = t_of(d)
    f = 1700 + 500 * r.random() + 500 * t / d
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 40 * t)))
    y = band(y + 0.1 * noise(r, d), 1200, 3500)
    return y * np.sin(np.pi * t / d)


def parrot(r):
    """A far parrot-like squawk: 2 harsh falling-rising notes, 1.1-2 kHz."""
    out = np.zeros(int(SR * 1.2))
    at = 0.0
    for k in range(int(r.integers(2, 4))):
        d = 0.22 + 0.08 * r.random()
        t = t_of(d)
        u = t / d
        f = (1300 + 300 * r.random()) * (1.3 - 0.6 * u)
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = sum(h * np.sin((i + 1) * ph) for i, h in enumerate((1.0, 0.8, 0.6, 0.4, 0.3)))
        y *= 0.6 + 0.4 * np.sin(2 * np.pi * 90 * t)
        y = band(y + 0.3 * noise(r, d), 700, 5000) * np.sin(np.pi * u) ** 0.6
        place(out, y, at, 1.0 - 0.1 * k)
        at += d + 0.08
    return out


def tropic_call(r):
    """A tropical bird: a clear whistled phrase, three rising-falling notes (~1.8-2.8 kHz)."""
    out = np.zeros(int(SR * 1.5))
    at = 0.0
    for f0 in (2000, 2500, 2200):
        d = 0.2
        t = t_of(d)
        f = f0 * (1 + 0.25 * np.sin(np.pi * t / d)) + 60 * np.sin(2 * np.pi * 14 * t)
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = np.sin(ph) + 0.25 * np.sin(2 * ph)
        place(out, y * np.sin(np.pi * t / d) ** 0.8, at, 1.0)
        at += d + 0.06
    return out


def chorus(r, n, fn, count, gain, lo=6.0, hi=6.0, burst=None):
    """count random-time instances of fn (peak-normalised, gain 0..1 of the -12 dBFS
    peak), none within lo / hi s of the loop's ends (hi counts the baked crossfade)."""
    y = np.zeros(n)
    d = n / SR
    for _ in range(count):
        at = lo + r.random() * (d - lo - hi - 6.5)
        e = fn(r)
        place(y, e / np.max(np.abs(e)), at, gain * 0.25 * (0.5 + 0.5 * r.random()))
    return y


def inland_rome_bed():
    """Inland Roman bed: wind in dry grass (higher, rustling, no rumble), a sparse
    random cicada chorus, 1-2 far crows and one distant dog bark. No gull, no surf."""
    r = rng("battlebed_rome48")
    n = int(SR * (BED_D + BED_X))
    base = _battle_base(r, n, 90, 650, rum=1.2, gain=1.1)
    grass = band(noise(r, BED_D + BED_X), 1800, 5500) * (0.1 + wander(r, n, 6.0)) ** 2
    base += grass * 0.5 * BED_RMS / np.sqrt(np.mean(grass ** 2))
    cic = chorus(r, n, cicada, int(r.integers(9, 13)), 0.22, hi=6.0)
    ev = events(r, (crow, dog_bark), (int(r.integers(1, 3)), 1), (0.45, 0.4), n, hi=6.0 + BED_X)
    return seamless(base + cic + ev)


def inland_west_bed():
    """Inland Caribbean bed: wind in leaves (a mid rustle over the wind), a soft cricket
    and tree-frog chorus, 2-3 far parrot squawks and one tropical bird call. No gull, no surf."""
    r = rng("battlebed_west48")
    n = int(SR * (BED_D + BED_X))
    base = _battle_base(r, n, 80, 600, rum=1.2, gain=1.1)
    leaves = band(noise(r, BED_D + BED_X), 1000, 4000) * (0.1 + wander(r, n, 8.0)) ** 2
    base += leaves * 0.6 * BED_RMS / np.sqrt(np.mean(leaves ** 2))
    chor = chorus(r, n, cricket, 150, 0.07) + chorus(r, n, tree_frog, 60, 0.09)
    ev = events(r, (parrot, tropic_call), (int(r.integers(2, 4)), 1), (0.5, 0.45), n, hi=6.0 + BED_X)
    return seamless(base + chor + ev)


# ------------------------------------------------------------- overworld ---

def tap():
    r = rng("tap")
    return band(noise(r, 0.05), 1500, 6000) * env(int(SR * 0.05), 0.0004, 0.01, 4) + 0.5 * tone(1400, 0.05, 0.0005, 8)


def order_ok():
    y = np.zeros(int(SR * 0.25))
    place(y, tone(520, 0.18, 0.004, 5, (1, 0.3)), 0, 0.8)
    place(y, tone(780, 0.14, 0.004, 5, (1, 0.2)), 0.06, 0.6)
    return y


def refused():
    r = rng("refused")
    d = 0.25
    y = band(tone(110, d, 0.003, 6, (1, 0.6, 0.4)) + 0.4 * noise(r, d), 60, 700)
    return y * env(len(y), 0.003, d, 5)


def end_turn():
    r = rng("endturn")
    y = np.zeros(int(SR * 0.6))
    place(y, sweep(150, 62, 0.4, 0.002, 4.5), 0)
    place(y, band(noise(r, 0.2), 100, 900) * env(int(SR * 0.2), 0.001, 0.06, 4), 0, 0.7)
    return y


def turn_resolved():
    y = np.zeros(int(SR * 0.9))
    place(y, tone(440, 0.4, 0.01, 4, (1, 0.35, 0.12)), 0)
    place(y, tone(659.3, 0.6, 0.01, 4, (1, 0.35, 0.12)), 0.2)
    return y


def battle_pending():
    y = np.zeros(int(SR * 0.9))
    place(y, horn_note(196, 0.25, 0.03, 0.08), 0)
    place(y, horn_note(293.7, 0.5, 0.03, 0.2), 0.27)
    return y


def chime():
    y = np.zeros(int(SR * 1.0))
    for i, f in enumerate((784, 988, 1175)):
        place(y, tone(f, 0.8 - i * 0.1, 0.003, 3.5, (1, 0.25, 0.1), det=0.001), i * 0.09, 0.7)
    return y


CLIPS = {
    "melee": (melee_clash, 0.7), "charge": (charge_impact, 0.9), "volley": (bow_volley, 0.55),
    "whoosh": (whoosh, 0.5), "bolt_release": (bolt_release, 0.75), "bolt_impact": (bolt_impact, 0.75),
    "stone_release": (stone_release, 0.8), "stone_impact": (stone_impact, 0.9), "burst": (explosive_burst, 0.9),
    "fire_loop": (fire_loop, 0.5), "gate_blow": (gate_blow, 0.8), "gate_break": (gate_break, 0.9),
    "creak": (creak, 0.5), "unit_break": (unit_break, 0.6), "unit_rally": (rally_horn, 0.6),
    "horn_start": (horn_start, 0.7), "horn_victory": (horn_victory, 0.75), "horn_defeat": (horn_defeat, 0.75),
    "elephant": (elephant, 0.75), "dogs": (dogs, 0.7),
    "tap": (tap, 0.4), "order_ok": (order_ok, 0.5), "refused": (refused, 0.6), "end_turn": (end_turn, 0.8),
    "turn_resolved": (turn_resolved, 0.6), "battle_pending": (battle_pending, 0.7), "chime": (chime, 0.6),
    "bed_battle": (battle_bed, 0.2512),
    "bed_battle_inland_rome": (inland_rome_bed, 0.2512), "bed_battle_inland_west": (inland_west_bed, 0.2512),
    "bed_map": (map_bed, 0.2512),
    "musket": (musket_volley, 0.8), "cannon": (cannon, 0.9),
}


def write(name, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    import sys
    only = sys.argv[1:]  # clip names: write just these (default: all)
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for name, (fn, peak) in CLIPS.items():
        if only and name not in only:
            continue
        x = fn()
        long = name.startswith("bed") or name == "fire_loop"
        x = x if long else x[:int(1.5 * SR)]
        if not long:
            x = np.concatenate([x, np.zeros(max(0, int(0.1 * SR) - len(x)))])
        write(name, x if name.startswith("bed") else finish(x, peak))
        total += len(x) * 2
    print("total bytes", total)


if __name__ == "__main__":
    main()
