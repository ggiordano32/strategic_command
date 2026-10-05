package server

import (
	"sync"
	"time"
)

// Limiter is a set of token buckets keyed by string (an IP, a token id...).
type Limiter struct {
	mu     sync.Mutex
	rate   float64 // tokens per second
	burst  float64
	bucket map[string]*bucket
	clock  Clock
}

type bucket struct {
	tokens float64
	last   time.Time
}

// NewLimiter allows `burst` events at once and `per` events per `every`.
func NewLimiter(clock Clock, per int, every time.Duration, burst int) *Limiter {
	return &Limiter{rate: float64(per) / every.Seconds(), burst: float64(burst),
		bucket: map[string]*bucket{}, clock: clock}
}

func (l *Limiter) refill(b *bucket, now time.Time) {
	if el := now.Sub(b.last).Seconds(); el > 0 {
		b.tokens += el * l.rate
		if b.tokens > l.burst {
			b.tokens = l.burst
		}
	}
	b.last = now
}

func (l *Limiter) get(key string, now time.Time) *bucket {
	b := l.bucket[key]
	if b == nil {
		b = &bucket{tokens: l.burst, last: now}
		l.bucket[key] = b
	}
	l.refill(b, now)
	return b
}

// Allow takes one token for key if there is one.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.get(key, l.clock.Now())
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// Has reports whether key has a token left, without taking it.
func (l *Limiter) Has(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.get(key, l.clock.Now()).tokens >= 1
}

// Take takes a token whether or not there is one (for counting failures).
func (l *Limiter) Take(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.get(key, l.clock.Now())
	b.tokens--
	if b.tokens < -l.burst {
		b.tokens = -l.burst
	}
}

// Sweep forgets full buckets (call now and then).
func (l *Limiter) Sweep() {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.clock.Now()
	for k, b := range l.bucket {
		l.refill(b, now)
		if b.tokens >= l.burst {
			delete(l.bucket, k)
		}
	}
}
