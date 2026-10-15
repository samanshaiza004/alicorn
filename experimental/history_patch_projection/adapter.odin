package main

// Application policy lives here. The indexes store copied span references;
// strings, parsed hunk lines and fold identities remain owned by the adapter.
Span_Kind :: enum u32 { Metadata, Header, Line, Gap, Fold, Binary }
Span_Ref :: struct { kind: Span_Kind, source, first, count: u32 }
Measure :: struct { old_rows, new_rows, display_rows, headers: i64 }
Dimension :: enum { Old, New, Display, Hunk }

Fold_Plan :: struct {
	id: u64,
	block: int,
	original: []Span_Ref,
	measure: Measure,
}
Patch_Store :: struct {
	patch: ^File_Patch,
	folds: []Fold_Plan,
	epoch: u64,
}
Visible_Row :: struct {
	line: Patch_Display_Line,
	fold_id: u64,
	hidden_rows: i64,
	patch_line: int,
}
Source_Kind :: enum { Missing, Visible, Gap, Folded }
Source_Result :: struct {
	kind: Source_Kind,
	display_row: i64,
	hunk, patch_line: int,
	fold_id: u64,
}
// A logical selection/scroll anchor survives projection changes. It is scoped
// to an immutable patch epoch, not a transient display row or tree revision.
Anchor :: struct { epoch: u64, hunk, line, byte_column: int, intra_row: f32 }
Anchor_Result :: struct { row: i64, folded: bool, ok: bool }

combine :: proc(a, b: Measure) -> Measure {
	return {a.old_rows+b.old_rows, a.new_rows+b.new_rows, a.display_rows+b.display_rows, a.headers+b.headers}
}
extent :: proc(m: Measure, dimension: Dimension) -> i64 {
	switch dimension {
	case .Old: return m.old_rows
	case .New: return m.new_rows
	case .Display: return m.display_rows
	case .Hunk: return m.headers
	}
	return 0
}
hunk_origin :: proc(start, count: int) -> i64 {
	// Unified diff's zero-count start names the line BEFORE the insertion.
	return i64(start)+1 if count == 0 else i64(start)
}
gap_measure :: proc(patch: ^File_Patch, hunk_index: int) -> Measure {
	h := patch.hunks[hunk_index]
	old_end, new_end: i64 = 1, 1
	if hunk_index > 0 {
		previous := patch.hunks[hunk_index-1]
		old_end = hunk_origin(previous.old_start, previous.old_count)+i64(previous.old_count)
		new_end = hunk_origin(previous.new_start, previous.new_count)+i64(previous.new_count)
	}
	return {hunk_origin(h.old_start, h.old_count)-old_end, hunk_origin(h.new_start, h.new_count)-new_end, 0, 0}
}
span_measure :: proc(store: ^Patch_Store, span: Span_Ref) -> Measure {
	switch span.kind {
	case .Metadata, .Binary: return {display_rows=1}
	case .Header: return {display_rows=1, headers=1}
	case .Gap: return gap_measure(store.patch, int(span.source))
	case .Fold: return store.folds[span.source].measure
	case .Line:
		kind := store.patch.hunks[span.source].lines[span.first].kind
		count := i64(span.count)
		return {
			old_rows=count if kind == .Context || kind == .Deletion else 0,
			new_rows=count if kind == .Context || kind == .Addition else 0,
			display_rows=count,
		}
	}
	return {}
}
span_valid :: proc(store: ^Patch_Store, span: Span_Ref) -> bool {
	if store == nil || store.patch == nil { return false }
	switch span.kind {
	case .Metadata: return int(span.source) < len(store.patch.metadata) && span.count == 1
	case .Binary: return store.patch.binary && span.count == 1
	case .Header, .Gap: return int(span.source) < len(store.patch.hunks) && span.count == 1
	case .Fold: return int(span.source) < len(store.folds) && span.count == 1
	case .Line:
		if int(span.source) >= len(store.patch.hunks) || span.count == 0 { return false }
		lines := store.patch.hunks[span.source].lines[:]
		if u64(span.first)+u64(span.count) > u64(len(lines)) { return false }
		kind := lines[span.first].kind
		for line in lines[int(span.first):int(span.first)+int(span.count)] { if line.kind != kind { return false } }
		return true
	}
	return false
}
make_spans :: proc(store: ^Patch_Store) -> (spans: [dynamic]Span_Ref, ok: bool) {
	spans = make([dynamic]Span_Ref)
	for _, i in store.patch.metadata { append(&spans, Span_Ref{kind=.Metadata, source=u32(i), count=1}) }
	for h, hi in store.patch.hunks {
		gap := gap_measure(store.patch, hi)
		if gap.old_rows < 0 || gap.new_rows < 0 { return spans, false }
		if gap.old_rows > 0 || gap.new_rows > 0 { append(&spans, Span_Ref{kind=.Gap, source=u32(hi), count=1}) }
		append(&spans, Span_Ref{kind=.Header, source=u32(hi), count=1})
		old_line := hunk_origin(h.old_start, h.old_count)
		new_line := hunk_origin(h.new_start, h.new_count)
		for line in h.lines {
			if line.kind == .Context || line.kind == .Deletion {
				if i64(line.old_line) != old_line { return spans, false }
				old_line += 1
			}
			if line.kind == .Context || line.kind == .Addition {
				if i64(line.new_line) != new_line { return spans, false }
				new_line += 1
			}
		}
		if old_line != hunk_origin(h.old_start, h.old_count)+i64(h.old_count) ||
		   new_line != hunk_origin(h.new_start, h.new_count)+i64(h.new_count) { return spans, false }
		for first := 0; first < len(h.lines); {
			end := first+1
			for end < len(h.lines) && h.lines[end].kind == h.lines[first].kind { end += 1 }
			append(&spans, Span_Ref{kind=.Line, source=u32(hi), first=u32(first), count=u32(end-first)})
			first = end
		}
	}
	if len(spans) == 0 && store.patch.binary { append(&spans, Span_Ref{kind=.Binary, count=1}) }
	return spans, true
}
make_fold_plans :: proc(store: ^Patch_Store, seed: []Span_Ref, limit: int) -> []Fold_Plan {
	plans := make([dynamic]Fold_Plan)
	next_candidate := 0
	stride := max(len(seed)/max(limit, 1), 1)
	for first := 0; first < len(seed) && len(plans) < limit; {
		if seed[first].kind != .Line { first += 1; continue }
		end := first+1
		block_end := min((first/LEAF_CAPACITY+1)*LEAF_CAPACITY, len(seed))
		for end < block_end && end-first < 4 && seed[end].kind == .Line && seed[end].source == seed[first].source { end += 1 }
		hidden := Measure{}
		for span in seed[first:end] { hidden = combine(hidden, span_measure(store, span)) }
		if hidden.display_rows > 1 && first >= next_candidate {
			plan := Fold_Plan{id=u64(len(plans))+1, block=first/LEAF_CAPACITY, original=make([]Span_Ref, end-first), measure=hidden}
			copy(plan.original, seed[first:end])
			plan.measure.display_rows = 1
			append(&plans, plan)
			next_candidate = first+stride
		}
		first = end
	}
	// Freeze the application-owned catalog before any index borrows it.
	result := make([]Fold_Plan, len(plans))
	copy(result, plans[:])
	delete(plans)
	return result
}
destroy_fold_plans :: proc(plans: []Fold_Plan) {
	for plan in plans { delete(plan.original) }
	delete(plans)
}
materialize_row :: proc(store: ^Patch_Store, span: Span_Ref, within: int) -> Visible_Row {
	switch span.kind {
	case .Metadata: return {line={kind=.Meta, text=store.patch.metadata[span.source]}, patch_line=-1}
	case .Binary: return {line={kind=.Meta, text="Binary file changed"}, patch_line=-1}
	case .Header: return {line={kind=.Meta, text=store.patch.hunks[span.source].header, hunk=true, hunk_index=int(span.source)}, patch_line=-1}
	case .Line:
		line := store.patch.hunks[span.source].lines[int(span.first)+within]
		return {line={kind=line.kind, old_line=line.old_line, new_line=line.new_line, text=line.text, hunk_index=int(span.source)}, patch_line=int(span.first)+within}
	case .Fold:
		plan := store.folds[span.source]
		hidden_rows: i64 = 0
		for original in plan.original { hidden_rows += span_measure(store, original).display_rows }
		return {line={kind=.Meta, text="Collapsed region", hunk_index=int(plan.original[0].source)}, fold_id=plan.id, hidden_rows=hidden_rows, patch_line=-1}
	case .Gap: return {}
	}
	return {}
}

// Independent expanded oracle starts from History's actual display index.
// Folding is implemented once here and used to verify every index backend.
oracle_rows :: proc(store: ^Patch_Store, active: []bool) -> [dynamic]Visible_Row {
	rows := make([dynamic]Visible_Row)
	position := 0
	for _ in store.patch.metadata { append(&rows, Visible_Row{line=store.patch.display_lines[position], patch_line=-1}); position += 1 }
	for h in store.patch.hunks {
		append(&rows, Visible_Row{line=store.patch.display_lines[position], patch_line=-1}); position += 1
		for _, li in h.lines { append(&rows, Visible_Row{line=store.patch.display_lines[position], patch_line=li}); position += 1 }
	}
	if position == 0 && len(store.patch.display_lines) == 1 { append(&rows, Visible_Row{line=store.patch.display_lines[0], patch_line=-1}) }
	for plan, fi in store.folds {
		if !active[fi] { continue }
		first_span := plan.original[0]
		last_span := plan.original[len(plan.original)-1]
		first_line := int(first_span.first)
		end_line := int(last_span.first+last_span.count)
		first := -1
		end := -1
		for row, ri in rows {
			if row.fold_id != 0 || row.line.hunk || row.line.hunk_index != int(first_span.source) { continue }
			if row.patch_line == first_line { first = ri }
			if row.patch_line == end_line-1 { end = ri+1 }
		}
		assert(first >= 0 && end > first)
		folded := materialize_row(store, Span_Ref{kind=.Fold, source=u32(fi), count=1}, 0)
		rows[first] = folded
		copy(rows[first+1:], rows[end:])
		resize(&rows, len(rows)-(end-first)+1)
	}
	return rows
}
oracle_source :: proc(store: ^Patch_Store, rows: []Visible_Row, old_side: bool, coordinate: i64) -> Source_Result {
	if coordinate < 1 { return {} }
	max_source: i64 = 0
	for h in store.patch.hunks {
		start, count := h.new_start, h.new_count
		if old_side { start, count = h.old_start, h.old_count }
		max_source = max(max_source, hunk_origin(start, count)+i64(count)-1)
	}
	if coordinate > max_source { return {} }
	for row, ri in rows {
		if row.fold_id != 0 {
			plan := store.folds[row.fold_id-1]
			for span in plan.original {
				for line in store.patch.hunks[span.source].lines[int(span.first):int(span.first+span.count)] {
					number := line.new_line
					if old_side { number = line.old_line }
					if i64(number) == coordinate { return {kind=.Folded, display_row=i64(ri), hunk=int(span.source), fold_id=plan.id} }
				}
			}
		} else {
			number := row.line.new_line
			if old_side { number = row.line.old_line }
			if i64(number) == coordinate {
				return {kind=.Visible, display_row=i64(ri), hunk=row.line.hunk_index, patch_line=row.patch_line}
			}
		}
	}
	return {kind=.Gap}
}
