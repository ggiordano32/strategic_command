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

// A story campaign (campaign/cstory.gd): who still owes an answer to a
// waiting choice (a crew vote waits for each living captain who has not
// voted; a single choice for its captain).
func TestParseStateStoryWaiting(t *testing.T) {
	text := []byte(`{"format":"strategic_command_campaign","version":7,"turn":3,"phase":"plan","winner":-1,
		"humans":[5,7],"factions":[{"alive":1},{"alive":1},{"alive":1},{"alive":1},{"alive":1},{"alive":1},{"alive":1},{"alive":1}],
		"armies":[],"battles":[],"story":{"pending":[{"id":4,"e":"chase","t":3,"f":5,"v":[[5,1]]}]}}`)
	m, err := ParseState(text)
	if err != nil {
		t.Fatal(err)
	}
	if !m.StoryOpen || len(m.StoryWaiting) != 1 || m.StoryWaiting[0] != 7 {
		t.Fatalf("vote waiting for the second captain: open %v waiting %v", m.StoryOpen, m.StoryWaiting)
	}
	solo := []byte(`{"format":"strategic_command_campaign","version":7,"turn":3,"phase":"plan","winner":-1,
		"humans":[5],"factions":[{"alive":1},{"alive":1},{"alive":1},{"alive":1},{"alive":1},{"alive":1}],
		"armies":[],"battles":[],"story":{"pending":[{"id":4,"e":"chase","t":3,"f":5}]}}`)
	m, err = ParseState(solo)
	if err != nil {
		t.Fatal(err)
	}
	if !m.StoryOpen || len(m.StoryWaiting) != 1 || m.StoryWaiting[0] != 5 {
		t.Fatalf("single choice: %v", m.StoryWaiting)
	}
	none := []byte(`{"format":"strategic_command_campaign","version":7,"turn":3,"phase":"plan","winner":-1,
		"humans":[0],"factions":[{"alive":1}],"armies":[],"battles":[],"story":{"pending":[]}}`)
	m, _ = ParseState(none)
	if m.StoryOpen || len(m.StoryWaiting) != 0 {
		t.Fatalf("nothing waits: %v", m)
	}
}
