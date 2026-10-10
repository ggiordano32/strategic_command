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


def fire_loop():
    r = rng("fire")
    d = 1.5
    n = int(SR * d)
    base = band(noise(r, d), 100, 900) * 0.5
    pops = np.zeros(n)
    for _ in range(22):
        at = int(r.random() * n)
        w = band(noise(r, 0.03), 1500, 6000) * env(int(SR * 0.03), 0.0005, 0.008, 4)
        k = min(len(w), n - at)
        pops[at:at + k] += w[:k] * (0.4 + r.random())
        if k < len(w):  # wrap for a seamless loop
            pops[:len(w) - k] += w[k:] * 0.5
    y = base + pops * 1.2
    x = max(1, int(0.05 * SR))  # crossfade ends
    y[:x] = y[:x] * np.linspace(0, 1, x) + y[-x:] * np.linspace(1, 0, x)
    return y[:-x]


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


def battle_bed():
    r = rng("battlebed")
    d = 3.0
    n = int(SR * d)
    t = np.arange(n) / SR
    wind = band(noise(r, d), 60, 500) * (0.6 + 0.4 * np.sin(2 * np.pi * (1 / d) * 1 * t + 1))
    wind += 0.3 * band(noise(r, d), 400, 1500) * (0.5 + 0.5 * np.sin(2 * np.pi * (1 / d) * 3 * t))
    drums = np.zeros(n)
    beat = d / 4
    for i in range(4):  # distant march: a thud each beat, accented on 1 and 5
        at = int(i * beat * SR)
        w = np.sin(2 * np.pi * 70 * t_of(0.3) * (1 - 0.4 * t_of(0.3))) * env(int(SR * 0.3), 0.005, 0.1, 4)
        w = w * (1.0 if i % 4 == 0 else 0.6)
        k = min(len(w), n - at)
        drums[at:at + k] += w[:k]
    y = wind / np.max(np.abs(wind)) * 0.5 + band(drums, 40, 250) * 0.55
    return y


def map_bed():
    r = rng("mapbed")
    d = 3.0
    n = int(SR * d)
    t = np.arange(n) / SR
    w = band(noise(r, d), 80, 900)
    w = w * (0.55 + 0.45 * np.sin(2 * np.pi * (1 / d) * t)) + 0.4 * band(noise(r, d), 500, 2200) * (
        0.5 + 0.5 * np.sin(2 * np.pi * (3 / d) * t + 2))
    return w


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
    "bed_battle": (battle_bed, 0.6), "bed_map": (map_bed, 0.5),
}


def write(name, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for name, (fn, peak) in CLIPS.items():
        x = fn()
        x = x[:int(1.5 * SR)] if not name.startswith("bed") else x
        if not name.startswith("bed") and name != "fire_loop":
            x = np.concatenate([x, np.zeros(max(0, int(0.1 * SR) - len(x)))])
        write(name, finish(x, peak))
        total += len(x) * 2
    print("total bytes", total)


if __name__ == "__main__":
    main()
