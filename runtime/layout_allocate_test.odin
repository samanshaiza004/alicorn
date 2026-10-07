package alicorn

import "core:testing"

layout_allocate_sum :: proc(values: []Layout_Unit) -> i64 {
	total: i64 = 0
	for value in values { total += i64(value) }
	return total
}

layout_allocate_next :: proc(state: ^u64) -> int {
	state^ = (state^*48271)%2147483647
	return int(state^%1001)
}

@(test)
test_layout_allocate_weighted_expansion_and_stable_remainder :: proc(t: ^testing.T) {
	items := [3]Elastic_Item{
		{minimum=0, ideal=0, max_unbounded=true, expand_weight=1},
		{minimum=0, ideal=0, max_unbounded=true, expand_weight=1},
		{minimum=0, ideal=0, max_unbounded=true, expand_weight=1},
	}
	output: [3]Layout_Unit
	result := layout_allocate_axis(2, items[:], output[:])
	testing.expect(t, output == [3]Layout_Unit{1, 1, 0}, "equal fractional remainders should go to earlier siblings deterministically")
	testing.expect(t, result.unused == 0 && result.overflow == 0, "a fully allocated axis should have no unused or overflow extent")

	weighted := [2]Elastic_Item{
		{minimum=0, ideal=0, max_unbounded=true, expand_weight=1},
		{minimum=0, ideal=0, max_unbounded=true, expand_weight=2},
	}
	weighted_output: [2]Layout_Unit
	_ = layout_allocate_axis(9, weighted[:], weighted_output[:])
	testing.expect(t, weighted_output == [2]Layout_Unit{3, 6}, "integer shares should track expand weights")
}

@(test)
test_layout_allocate_redistributes_around_maxima_and_reports_unused_space :: proc(t: ^testing.T) {
	items := [3]Elastic_Item{
		{minimum=0, ideal=0, maximum=2, expand_weight=1},
		{minimum=0, ideal=0, maximum=20, expand_weight=1},
		{minimum=0, ideal=0, maximum=20, expand_weight=1},
	}
	output: [3]Layout_Unit
	result := layout_allocate_axis(10, items[:], output[:])
	testing.expect(t, output == [3]Layout_Unit{2, 4, 4}, "a capped participant should release its share for redistribution")
	testing.expect(t, result.unused == 0 && result.overflow == 0, "redistribution should consume the available extent")

	bounded := [2]Elastic_Item{
		{minimum=0, ideal=0, maximum=2, expand_weight=1},
		{minimum=0, ideal=0, maximum=3, expand_weight=1},
	}
	bounded_output: [2]Layout_Unit
	bounded_result := layout_allocate_axis(10, bounded[:], bounded_output[:])
	testing.expect(t, bounded_output == [2]Layout_Unit{2, 3}, "bounded participants should stop at maximums")
	testing.expect(t, bounded_result.unused == 5, "unallocatable surplus should be reported as unused")
}

@(test)
test_layout_allocate_compresses_by_weight_and_preserves_hard_minima :: proc(t: ^testing.T) {
	weighted := [2]Elastic_Item{
		{minimum=0, ideal=10, max_unbounded=true, compress_weight=1},
		{minimum=0, ideal=10, max_unbounded=true, compress_weight=2},
	}
	output: [2]Layout_Unit
	result := layout_allocate_axis(10, weighted[:], output[:])
	testing.expect(t, output == [2]Layout_Unit{6, 4}, "compression weights should receive stable integer shrink shares")
	testing.expect(t, result.overflow == 0 && result.unused == 0, "weighted compression should fit the requested extent")

	minima := [2]Elastic_Item{
		{minimum=8, ideal=10, maximum=10, compress_weight=1},
		{minimum=5, ideal=10, maximum=10, compress_weight=1},
	}
	minimum_output: [2]Layout_Unit
	minimum_result := layout_allocate_axis(7, minima[:], minimum_output[:])
	testing.expect(t, minimum_output == [2]Layout_Unit{8, 5}, "hard minima must be preserved when their total exceeds available space")
	testing.expect(t, minimum_result.overflow == 6 && minimum_result.unused == 0, "minimum overflow should be explicit")
}

@(test)
test_layout_allocate_redistributes_compression_and_reports_weightless_overflow :: proc(t: ^testing.T) {
	items := [2]Elastic_Item{
		{minimum=8, ideal=10, maximum=10, compress_weight=1},
		{minimum=0, ideal=10, maximum=10, compress_weight=1},
	}
	output: [2]Layout_Unit
	_ = layout_allocate_axis(10, items[:], output[:])
	testing.expect(t, output == [2]Layout_Unit{8, 2}, "a participant that reaches its minimum should redistribute shrink to its sibling")

	no_weight := [2]Elastic_Item{
		{minimum=0, ideal=10, max_unbounded=true},
		{minimum=0, ideal=10, max_unbounded=true},
	}
	no_weight_output: [2]Layout_Unit
	no_weight_result := layout_allocate_axis(12, no_weight[:], no_weight_output[:])
	testing.expect(t, no_weight_output == [2]Layout_Unit{10, 10} && no_weight_result.overflow == 8,
		"unweighted items should retain their ideal size and report unresolvable compression")
}

@(test)
test_layout_allocate_invalid_constraints_are_reported_and_canonicalized :: proc(t: ^testing.T) {
	items := [3]Elastic_Item{
		{minimum=-4, ideal=5, maximum=3, expand_weight=1},
		{minimum=9, ideal=5, maximum=3, expand_weight=1},
		{minimum=4, ideal=1, max_unbounded=true, expand_weight=1},
	}
	output: [3]Layout_Unit
	result := layout_allocate_axis(20, items[:], output[:])
	testing.expect(t, result.invalid_items == 2 && result.first_invalid_index == 0,
		"negative minima and inverted bounds should be reported once per invalid item")
	testing.expect(t, output[0] >= 0 && output[1] >= 9 && output[2] >= 4,
		"invalid constraints and out-of-range ideal sizes should be normalized to valid bounds")

	negative_available := layout_allocate_axis(-1, items[:], output[:])
	testing.expect(t, negative_available.invalid_available && negative_available.overflow >= 0,
		"negative available extent should be reported and safely canonicalized")

	short: [1]Layout_Unit
	too_small := layout_allocate_axis(10, items[:], short[:])
	testing.expect(t, too_small.output_too_small, "the allocator should reject undersized caller output without writing past it")
}

@(test)
test_layout_allocate_aggregate_extent_can_exceed_i64 :: proc(t: ^testing.T) {
	items := make([]Elastic_Item, 8200)
	defer delete(items)
	output := make([]Layout_Unit, 8200)
	defer delete(output)
	for index in 0..<len(items) {
		items[index] = Elastic_Item{
			minimum=0,
			ideal=LAYOUT_ALLOCATOR_UNIT_LIMIT,
			max_unbounded=true,
			compress_weight=1,
		}
	}
	result := layout_allocate_axis(LAYOUT_ALLOCATOR_UNIT_LIMIT, items, output)
	testing.expect(t, layout_allocate_sum(output) == i64(LAYOUT_ALLOCATOR_UNIT_LIMIT),
		"large aggregate ideal extents should compress exactly to an i64-sized available axis")
	testing.expect(t, result.overflow == 0 && result.unused == 0,
		"large aggregate arithmetic should not wrap or report false overflow")
}

@(test)
test_layout_allocate_randomized_invariants_and_determinism :: proc(t: ^testing.T) {
	seed: u64 = 913571
	for _ in 0..<5000 {
		count := 1+layout_allocate_next(&seed)%12
		items: [12]Elastic_Item
		first: [12]Layout_Unit
		second: [12]Layout_Unit
		for index in 0..<count {
			minimum := layout_allocate_next(&seed)%80
			maximum := minimum+layout_allocate_next(&seed)%100
			ideal := minimum+layout_allocate_next(&seed)%(maximum-minimum+1)
			items[index] = Elastic_Item{
				minimum=Layout_Unit(minimum),
				ideal=Layout_Unit(ideal),
				maximum=Layout_Unit(maximum),
				expand_weight=u32(layout_allocate_next(&seed)%6),
				compress_weight=u32(layout_allocate_next(&seed)%6),
			}
		}
		available := Layout_Unit(layout_allocate_next(&seed)%1001)
		first_result := layout_allocate_axis(available, items[:count], first[:count])
		second_result := layout_allocate_axis(available, items[:count], second[:count])
		different_output := false
		for index in 0..<count {
			if first[index] != second[index] { different_output = true; break }
		}
		if different_output || first_result != second_result {
			testing.expect(t, false, "identical allocator inputs must produce identical output and diagnostics")
			return
		}
		for item, index in items[:count] {
			if first[index] < item.minimum || first[index] > item.maximum || first[index] < 0 {
				testing.expect(t, false, "every randomized allocation must stay within each item's hard bounds")
				return
			}
		}
		difference := layout_allocate_sum(first[:count])-i64(available)
		if difference > 0 {
			if i64(first_result.overflow) != difference || first_result.unused != 0 {
				testing.expect(t, false, "randomized overflows should exactly describe the excess output extent")
				return
			}
		} else if difference < 0 {
			if i64(first_result.unused) != -difference || first_result.overflow != 0 {
				testing.expect(t, false, "randomized unused extents should exactly describe unallocated space")
				return
			}
		} else if first_result.unused != 0 || first_result.overflow != 0 {
			testing.expect(t, false, "exact randomized allocations should report neither unused space nor overflow")
			return
		}
	}
}
