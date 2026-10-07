package alicorn

// Elastic_Item is the input contract for the standalone 1D allocator. All
// lengths are canonical Layout_Unit values; the allocator does not inspect
// retained nodes, layout styles, or renderer state.
Elastic_Item :: struct {
	minimum:        Layout_Unit,
	ideal:          Layout_Unit,
	maximum:        Layout_Unit,
	max_unbounded:  bool,
	expand_weight:  u32,
	compress_weight: u32,
}

Axis_Allocation_Result :: struct {
	unused:                 Layout_Unit,
	overflow:               Layout_Unit,
	invalid_items:          int,
	first_invalid_index:    int,
	invalid_available:      bool,
	output_too_small:       bool,
	redistribution_passes:  int,
}

LAYOUT_ALLOCATOR_UNIT_LIMIT :: Layout_Unit(1 << 50)

layout_allocator_canonical_item :: proc(item: Elastic_Item) -> (canonical: Elastic_Item, invalid: bool) {
	limit := i64(LAYOUT_ALLOCATOR_UNIT_LIMIT)
	minimum := i64(item.minimum)
	ideal := i64(item.ideal)
	maximum := i64(item.maximum)
	if minimum < 0 { minimum, invalid = 0, true }
	if minimum > limit { minimum, invalid = limit, true }
	if ideal < 0 { ideal, invalid = 0, true }
	if ideal > limit { ideal, invalid = limit, true }
	if !item.max_unbounded {
		if maximum < 0 { maximum, invalid = minimum, true }
		if maximum > limit { maximum, invalid = limit, true }
		if maximum < minimum { maximum, invalid = minimum, true }
	}
	if ideal < minimum { ideal = minimum }
	if !item.max_unbounded && ideal > maximum { ideal = maximum }
	canonical = item
	canonical.minimum = Layout_Unit(minimum)
	canonical.ideal = Layout_Unit(ideal)
	canonical.maximum = Layout_Unit(maximum)
	return
}

layout_allocator_clamp_total :: proc(value: u128) -> Layout_Unit {
	limit := (u128(1) << 63)-1
	clamped := value
	if clamped > limit { clamped = limit }
	return Layout_Unit(i64(clamped))
}

layout_allocator_share :: proc(amount, total_weight: u128, weight: u32) -> u128 {
	// Decomposition keeps the product bounded even when the axis contains
	// enough large ideal extents that their aggregate exceeds i64.
	whole := amount/total_weight
	remainder := amount%total_weight
	return whole*u128(weight) + (remainder*u128(weight))/total_weight
}

layout_allocator_capacity :: proc(item: Elastic_Item, current: Layout_Unit, expand: bool) -> i64 {
	if expand {
		if item.max_unbounded { return i64(LAYOUT_ALLOCATOR_UNIT_LIMIT)-i64(current) }
		return i64(item.maximum)-i64(current)
	}
	return i64(current)-i64(item.minimum)
}

layout_allocator_weight :: proc(item: Elastic_Item, expand: bool) -> u32 {
	return item.expand_weight if expand else item.compress_weight
}

// Allocates an integer delta by weighted saturating water-fill. Capped
// participants are removed and the remaining share is redistributed. Once
// no participant saturates, fractional remainder units go to eligible items
// in stable input order.
layout_allocator_distribute :: proc(
	items: []Elastic_Item,
	output: []Layout_Unit,
	amount: u128,
	expand: bool,
	result: ^Axis_Allocation_Result,
) -> u128 {
	remaining := amount
	if remaining == 0 { return 0 }
	for remaining > 0 {
		total_weight: u128 = 0
		for item, index in items {
			canonical, _ := layout_allocator_canonical_item(item)
			capacity := layout_allocator_capacity(canonical, output[index], expand)
			weight := layout_allocator_weight(canonical, expand)
			if capacity > 0 && weight > 0 { total_weight += u128(weight) }
		}
		if total_weight == 0 { return remaining }

		capped_any := false
		for item, index in items {
			canonical, _ := layout_allocator_canonical_item(item)
			capacity := layout_allocator_capacity(canonical, output[index], expand)
			weight := layout_allocator_weight(canonical, expand)
			if capacity <= 0 || weight == 0 { continue }
			// Compare the exact integer share without narrowing the aggregate
			// extent to i64. layout_allocator_share avoids an overflowing product.
			if layout_allocator_share(remaining, total_weight, weight) >= u128(capacity) { capped_any = true }
		}
		result.redistribution_passes += 1
		if capped_any {
			capped_total: u128 = 0
			for item, index in items {
				canonical, _ := layout_allocator_canonical_item(item)
				capacity := layout_allocator_capacity(canonical, output[index], expand)
				weight := layout_allocator_weight(canonical, expand)
				if capacity <= 0 || weight == 0 { continue }
				if layout_allocator_share(remaining, total_weight, weight) >= u128(capacity) {
					if expand { output[index] += Layout_Unit(capacity) } else { output[index] -= Layout_Unit(capacity) }
					capped_total += u128(capacity)
				}
			}
			remaining -= capped_total
			continue
		}

		assigned: u128 = 0
		for item, index in items {
			canonical, _ := layout_allocator_canonical_item(item)
			capacity := layout_allocator_capacity(canonical, output[index], expand)
			weight := layout_allocator_weight(canonical, expand)
			if capacity <= 0 || weight == 0 { continue }
			share := layout_allocator_share(remaining, total_weight, weight)
			if share > u128(capacity) { share = u128(capacity) }
			if expand { output[index] += Layout_Unit(i64(share)) } else { output[index] -= Layout_Unit(i64(share)) }
			assigned += share
		}
		remaining -= assigned
		// Largest-remainder tie breaking is intentionally stable: among the
		// remaining eligible participants, earlier siblings receive the first
		// indivisible unit.
		for remaining > 0 {
			progress := false
			for item, index in items {
				if remaining == 0 { break }
				canonical, _ := layout_allocator_canonical_item(item)
				if layout_allocator_capacity(canonical, output[index], expand) <= 0 || layout_allocator_weight(canonical, expand) == 0 { continue }
				if expand { output[index] += 1 } else { output[index] -= 1 }
				remaining -= 1
				progress = true
			}
			if !progress { return remaining }
		}
	}
	return 0
}

// layout_allocate_axis resolves ideal sizes against one available extent.
// Invalid constraints are reported and canonicalized conservatively; hard
// minima remain intact, even when their sum overflows the available extent.
layout_allocate_axis :: proc(
	available: Layout_Unit,
	items: []Elastic_Item,
	output: []Layout_Unit,
) -> Axis_Allocation_Result {
	result := Axis_Allocation_Result{first_invalid_index=-1}
	if len(output) < len(items) {
		result.output_too_small = true
		return result
	}
	available_value := i64(available)
	if available_value < 0 {
		result.invalid_available = true
		available_value = 0
	}
	if available_value > i64(LAYOUT_ALLOCATOR_UNIT_LIMIT) {
		result.invalid_available = true
		available_value = i64(LAYOUT_ALLOCATOR_UNIT_LIMIT)
	}
	available_value_u := u128(available_value)
	minimum_total: u128 = 0
	ideal_total: u128 = 0
	for item, index in items {
		canonical, invalid := layout_allocator_canonical_item(item)
		output[index] = canonical.ideal
		minimum_total += u128(i64(canonical.minimum))
		ideal_total += u128(i64(canonical.ideal))
		if invalid {
			result.invalid_items += 1
			if result.first_invalid_index < 0 { result.first_invalid_index = index }
		}
	}
	if minimum_total > available_value_u {
		for item, index in items {
			canonical, _ := layout_allocator_canonical_item(item)
			output[index] = canonical.minimum
		}
		result.overflow = layout_allocator_clamp_total(minimum_total-available_value_u)
		return result
	}
	if ideal_total > available_value_u {
		remaining := ideal_total-available_value_u
		remaining = layout_allocator_distribute(items, output, remaining, false, &result)
		if remaining > 0 { result.overflow = layout_allocator_clamp_total(remaining) }
	} else if ideal_total < available_value_u {
		remaining := available_value_u-ideal_total
		remaining = layout_allocator_distribute(items, output, remaining, true, &result)
		if remaining > 0 { result.unused = layout_allocator_clamp_total(remaining) }
	}
	return result
}
