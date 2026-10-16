package server

import (
	"bytes"
	"crypto/md5"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strconv"
)

// The server never runs game rules. It reads a few top-level facts from
// the state blobs the clients upload (turn, phase, winner, the humans and
// which of them are alive, and which humans have armies in each pending
// battle: by their armies, or for a sea battle its "sf" list of factions
// with a fleet in it) for bookkeeping, notifications and sanity checks.

const stateFormat = "strategic_command_campaign"

// num is a JSON number read as an int (accepts 5 and 5.0).
type num int

func (n *num) UnmarshalJSON(b []byte) error {
	var f float64
	if err := json.Unmarshal(b, &f); err != nil {
		return err
	}
	if math.IsNaN(f) || math.Abs(f) > 1<<53 {
		return fmt.Errorf("bad number")
	}
	*n = num(int(f))
	return nil
}

type stateDoc struct {
	Format   string `json:"format"`
	Version  num    `json:"version"`
	Name     string `json:"name"`
	Turn     num    `json:"turn"`
	Phase    string `json:"phase"`
	Winner   num    `json:"winner"`
	Humans   []num  `json:"humans"`
	Teams    []num  `json:"teams"`
	Settings struct {
		TurnTimeoutH num `json:"turn_timeout_h"`
	} `json:"settings"`
	Factions []struct {
		Alive num `json:"alive"`
	} `json:"factions"`
	Armies []struct {
		ID num `json:"id"`
		F  num `json:"f"`
	} `json:"armies"`
	Story *struct { // a story campaign (campaign/cstory.gd): the choices waiting for an answer
		Pending []struct {
			F num      `json:"f"`
			V *[][]num `json:"v"` // a crew vote (co-op): [captain, choice] given so far; absent: F answers alone
		} `json:"pending"`
	} `json:"story"`
	Battles []struct {
		ID    num   `json:"id"`
		R     num   `json:"r"`
		Att   []num `json:"att"`
		Def   []num `json:"def"`
		Reinf []num `json:"reinf"`
		AttF  num   `json:"att_f"`
		DefF  num   `json:"def_f"`
		Sf    []num `json:"sf"` // a sea battle (N3a): every faction with a fleet in it
	} `json:"battles"`
}

// Battle is a pending battle with at least one human faction in it.
// Humans: every human with an army in it (either side, or the defending
// city's owner). Guests: the alive humans without one there on the team of
// either side's lead faction (att_f / def_f), who may join it live and be
// given units (nil in rows stored before guests existed: any alive human).
type Battle struct {
	ID     int   `json:"id"`
	R      int   `json:"r"`
	Humans []int `json:"humans"`
	Guests []int `json:"guests"`
}

// mayJoin: seat f may be in battle b's live room (a human of the battle or
// one of its guests); alive lists the campaign's alive humans.
func (b *Battle) mayJoin(f int, alive []int) bool {
	if hasInt(b.Humans, f) {
		return true
	}
	if b.Guests == nil {
		return hasInt(alive, f)
	}
	return hasInt(b.Guests, f) && hasInt(alive, f)
}

// joiners: everyone who may be in battle b's live room but f.
func (b *Battle) joiners(f int, alive []int) []int {
	var out []int
	for _, x := range alive {
		if x != f && b.mayJoin(x, alive) {
			out = append(out, x)
		}
	}
	for _, x := range b.Humans {
		if x != f && !hasInt(out, x) && hasInt(alive, x) {
			out = append(out, x)
		}
	}
	sort.Ints(out)
	return out
}

// StateMeta is what the server keeps from a state.
type StateMeta struct {
	FormatVersion int
	Name          string
	Turn          int
	Phase         string
	Winner        int
	Humans        []int
	Alive         []int // humans still alive
	TimeoutH      int
	Battles       []Battle // pending, with a human
	AllBattleIDs  []int
	StoryOpen     bool  // a story choice is waiting (the turn cannot resolve)
	StoryWaiting  []int // the alive humans who still owe an answer to a waiting story choice
}

// StateHash is the game's CState.state_hash of a canonical state text: the
// first 4 bytes of its MD5 as a little-endian uint32, in hex. A version 7
// state whose teams are the default shape (and nobody is leaving) hashes as
// the format 6 state it equals, as the game does (CState.state_hash).
func StateHash(text []byte) string {
	sum := md5.Sum(hashView(text))
	return fmt.Sprintf("%08x", binary.LittleEndian.Uint32(sum[:4]))
}

// hashView is the text the game hashes: for a default-shaped version 7 state
// the same text without "teams" and with "version":6 (keys stay sorted, every
// value is kept byte for byte); any other text as it is.
func hashView(text []byte) []byte {
	if !bytes.Contains(text, []byte(`"teams"`)) {
		return text
	}
	var top map[string]json.RawMessage
	if json.Unmarshal(text, &top) != nil {
		return text
	}
	var version int
	var humans, teams []int
	if json.Unmarshal(top["version"], &version) != nil || version != 7 ||
		json.Unmarshal(top["humans"], &humans) != nil || json.Unmarshal(top["teams"], &teams) != nil {
		return text
	}
	if _, leaving := top["leaving"]; leaving {
		return text
	}
	isHuman := map[int]bool{}
	for _, h := range humans {
		isHuman[h] = true
	}
	next := 1
	for f, t := range teams {
		want := 0
		if !isHuman[f] {
			want = next
			next++
		}
		if t != want {
			return text
		}
	}
	delete(top, "teams")
	top["version"] = json.RawMessage("6")
	keys := make([]string, 0, len(top))
	for k := range top {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var out bytes.Buffer
	out.WriteByte('{')
	for i, k := range keys {
		if i > 0 {
			out.WriteByte(',')
		}
		kb, _ := json.Marshal(k)
		out.Write(kb)
		out.WriteByte(':')
		out.Write(top[k])
	}
	out.WriteByte('}')
	return out.Bytes()
}

// ParseState reads the facts above from a state JSON text.
func ParseState(text []byte) (*StateMeta, error) {
	var d stateDoc
	if err := json.Unmarshal(text, &d); err != nil {
		return nil, fmt.Errorf("state is not valid JSON: %v", err)
	}
	if d.Format != stateFormat {
		return nil, fmt.Errorf("not a campaign state (format %q)", d.Format)
	}
	switch d.Phase {
	case "plan", "battles", "over":
	default:
		return nil, fmt.Errorf("unknown phase %q", d.Phase)
	}
	m := &StateMeta{FormatVersion: int(d.Version), Name: d.Name, Turn: int(d.Turn), Phase: d.Phase,
		Winner: int(d.Winner), TimeoutH: int(d.Settings.TurnTimeoutH)}
	isHuman := map[int]bool{}
	for _, h := range d.Humans {
		m.Humans = append(m.Humans, int(h))
		isHuman[int(h)] = true
		if int(h) >= 0 && int(h) < len(d.Factions) && d.Factions[h].Alive != 0 {
			m.Alive = append(m.Alive, int(h))
		}
	}
	sort.Ints(m.Humans)
	sort.Ints(m.Alive)
	// Team of each faction (CState.team): the "teams" list, or the default
	// shape (humans team 0, every other faction alone) without it.
	team := func(f int) int {
		if f < 0 {
			return -1
		}
		if d.Teams != nil {
			if f < len(d.Teams) {
				return int(d.Teams[f])
			}
			return -1 - f
		}
		if isHuman[f] {
			return 0
		}
		return 1000 + f
	}
	armyF := map[int]int{}
	for _, a := range d.Armies {
		armyF[int(a.ID)] = int(a.F)
	}
	for _, b := range d.Battles {
		m.AllBattleIDs = append(m.AllBattleIDs, int(b.ID))
		set := map[int]bool{}
		for _, list := range [][]num{b.Att, b.Def, b.Reinf} {
			for _, id := range list {
				if f, ok := armyF[int(id)]; ok {
					set[f] = true
				}
			}
		}
		set[int(b.DefF)] = true
		for _, f := range b.Sf {
			set[int(f)] = true
		}
		var hs []int
		for f := range set {
			if isHuman[f] {
				hs = append(hs, f)
			}
		}
		if len(hs) == 0 {
			continue
		}
		sort.Ints(hs)
		gs := []int{}
		for _, f := range m.Alive {
			if set[f] {
				continue
			}
			t := team(f)
			if (int(b.AttF) >= 0 && t == team(int(b.AttF))) || (int(b.DefF) >= 0 && t == team(int(b.DefF))) {
				gs = append(gs, f)
			}
		}
		m.Battles = append(m.Battles, Battle{ID: int(b.ID), R: int(b.R), Humans: hs, Guests: gs})
	}
	if d.Story != nil {
		seen := map[int]bool{}
		for _, pe := range d.Story.Pending {
			m.StoryOpen = true
			if pe.V == nil {
				seen[int(pe.F)] = true
				continue
			}
			given := map[int]bool{}
			for _, v := range *pe.V {
				if len(v) > 0 {
					given[int(v[0])] = true
				}
			}
			for _, f := range m.Alive {
				if !given[f] {
					seen[f] = true
				}
			}
		}
		for _, f := range m.Alive {
			if seen[f] {
				m.StoryWaiting = append(m.StoryWaiting, f)
			}
		}
	}
	if m.Humans == nil {
		m.Humans = []int{}
	}
	if m.Alive == nil {
		m.Alive = []int{}
	}
	return m, nil
}

func (m *StateMeta) battle(id int) *Battle {
	for i := range m.Battles {
		if m.Battles[i].ID == id {
			return &m.Battles[i]
		}
	}
	return nil
}

func hasInt(list []int, v int) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func intsJSON(v []int) string {
	if v == nil {
		v = []int{}
	}
	b, _ := json.Marshal(v)
	return string(b)
}

func parseInts(s string) []int {
	var v []int
	json.Unmarshal([]byte(s), &v)
	if v == nil {
		v = []int{}
	}
	return v
}

func itoa(i int) string { return strconv.Itoa(i) }
