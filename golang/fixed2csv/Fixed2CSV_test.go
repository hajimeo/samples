package main

import (
	"testing"
)

var LINE = "  Block                                                                                                                                                                                                                                                                                                                                          Invocations  SelfTime.Total  SelfTime.Avg  SelfTime.Min  SelfTime.Max  WallTime.Total  WallTime.Avg  WallTime.Min  WallTime.Max"

func TestNonSpacePos(t *testing.T) {
	//words := strings.Fields(LINE)
	//t.Logf("%v", words)
	//i := strings.Index(LINE, "Block")
	//t.Logf("%v", LINE[0:i])

	positions := nonSpacePos(LINE)
	if positions == nil || len(positions) == 0 {
		t.Errorf("positions from nonSpacePos is empty")
	}
	t.Logf("%v", positions)
}

func TestLine2CSV(t *testing.T) {
	positions := nonSpacePos(LINE)
	csvStr := line2CSV(LINE, positions)
	if len(csvStr) == 0 {
		t.Errorf("csvStr from line2CSV is empty")
	}
	t.Logf("%v", csvStr)
}