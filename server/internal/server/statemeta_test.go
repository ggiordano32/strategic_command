package server

import "testing"

// A sea battle (N3a) has no armies: its humans come from "sf", the
// factions with a fleet in it.
func TestParseStateSeaBattle(t *testing.T) {
	text := []byte(`{"format":"strategic_command_campaign","version":7,"turn":3,"phase":"battles","winner":-1,
		"humans":[2],"factions":[{"alive":1},{"alive":1},{"alive":1}],"armies":[],
		"battles":[{"id":5,"r":4,"att":[],"def":[],"reinf":[],"att_f":2,"def_f":0,"sea":1,"sf":[0,2]},
			{"id":6,"r":4,"att":[],"def":[],"reinf":[],"att_f":1,"def_f":0}]}`)
	m, err := ParseState(text)
	if err != nil {
		t.Fatal(err)
	}
	if len(m.Battles) != 1 || m.Battles[0].ID != 5 || len(m.Battles[0].Humans) != 1 || m.Battles[0].Humans[0] != 2 {
		t.Fatalf("sea battle humans: %+v", m.Battles)
	}
	if len(m.AllBattleIDs) != 2 {
		t.Fatalf("all battle ids: %v", m.AllBattleIDs)
	}
}
