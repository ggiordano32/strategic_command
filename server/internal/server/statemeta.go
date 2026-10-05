package server

import (
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
// battle) for bookkeeping, notifications and sanity checks.

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
	Battles []struct {
		ID    num   `json:"id"`
		R     num   `json:"r"`
		Att   []num `json:"att"`
		Def   []num `json:"def"`
		Reinf []num `json:"reinf"`
		AttF  num   `json:"att_f"`
		DefF  num   `json:"def_f"`
	} `json:"battles"`
}

// Battle is a pending battle with at least one human faction in it.
type Battle struct {
	ID     int   `json:"id"`
	R      int   `json:"r"`
	Humans []int `json:"humans"`
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
}

// StateHash is the game's CState.state_hash of a canonical state text: the
// first 4 bytes of its MD5 as a little-endian uint32, in hex.
func StateHash(text []byte) string {
	sum := md5.Sum(text)
	return fmt.Sprintf("%08x", binary.LittleEndian.Uint32(sum[:4]))
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
		m.Battles = append(m.Battles, Battle{ID: int(b.ID), R: int(b.R), Humans: hs})
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
