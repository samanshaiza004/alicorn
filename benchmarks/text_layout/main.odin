package main

import "core:fmt"
import "core:os"
import "core:time"
import alicorn "../../runtime"

FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
ITALIC_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleNext-Italic-Variable.ttf")

ROOT :: alicorn.Source_Site{"benchmarks/text_layout/main.odin", 1, 1, "root"}
ROW :: alicorn.Source_Site{"benchmarks/text_layout/main.odin", 20, 1, "wrapped_text_row"}

ROW_COUNT :: 20_000
VIEWPORT_HEIGHT :: f32(860)
INITIAL_WIDTH :: f32(1180)
ESTIMATED_ROW_HEIGHT :: f32(84)
SCROLL_FRAMES :: 120
RESIZE_FRAMES :: 40

TEXT_PREFIX :: "Alicorn keeps application state explicit while retained text shaping wraps a paragraph into visual rows. Search highlights semantic links, inline code identifiers, and emphasis decorate source-mapped text without changing UTF-8 offsets. Resize the pane to reflow this sentence; scroll to compare variable-height rows across the logical list. Reference row "
EXTRA_ONE :: "A selection can span visible fragments while its source range remains a single UTF-8 interval."
EXTRA_TWO :: "The runtime keeps layout, paint, and retained identity as separate stages."
EXTRA_THREE :: "Repeated resizing exercises width-keyed shaping and invalidation. Stable row keys preserve identity as the visible range changes. The height index stores only measurements that differ from its estimate, so long documents keep sparse geometry."

Text_Workload :: struct {
	rows: []string,
	row_nodes: []alicorn.Node_ID,
	style_spans: []alicorn.Text_Style_Span,
	paint_spans: []alicorn.Text_Paint_Span,
	index: alicorn.Virtual_List_Height_Index,
}

find_bytes :: proc(value, needle: string) -> int {
	if len(needle) == 0 || len(needle) > len(value) { return -1 }
	for start in 0..=len(value)-len(needle) {
		if value[start:start+len(needle)] == needle { return start }
	}
	return -1
}

make_workload :: proc(allocator := context.allocator) -> (workload: Text_Workload, ok: bool) {
	workload.rows = make([]string, ROW_COUNT, allocator=allocator)
	workload.row_nodes = make([]alicorn.Node_ID, ROW_COUNT, allocator=allocator)
	for i in 0..<ROW_COUNT {
		switch i%4 {
		case 0:
			workload.rows[i] = fmt.aprintf("%s%d.", TEXT_PREFIX, i, allocator=allocator)
		case 1:
			workload.rows[i] = fmt.aprintf("%s%d. %s", TEXT_PREFIX, i, EXTRA_ONE, allocator=allocator)
		case 2:
			workload.rows[i] = fmt.aprintf("%s%d. %s %s", TEXT_PREFIX, i, EXTRA_ONE, EXTRA_TWO, allocator=allocator)
		case 3:
			workload.rows[i] = fmt.aprintf("%s%d. %s %s %s", TEXT_PREFIX, i, EXTRA_ONE, EXTRA_TWO, EXTRA_THREE, allocator=allocator)
		}
	}

	text := workload.rows[0]
	explicit_start := find_bytes(text, "explicit")
	italic_start := find_bytes(text, "source-mapped")
	workload.style_spans = []alicorn.Text_Style_Span{
		{start=explicit_start, end=explicit_start+len("explicit"), font_weight=alicorn.FONT_WEIGHT_BOLD, font_weight_set=true},
		{start=italic_start, end=italic_start+len("source-mapped"), italic=true, italic_set=true},
	}
	link_start := find_bytes(text, "semantic links")
	code_start := find_bytes(text, "UTF-8")
	resize_start := find_bytes(text, "Resize")
	workload.paint_spans = []alicorn.Text_Paint_Span{
		{start=link_start, end=link_start+len("semantic links"), color=alicorn.Color{0.48, 0.76, 0.94, 1}, color_set=true, underline=true},
		{start=code_start, end=code_start+len("UTF-8"), background=alicorn.Color{0.16, 0.22, 0.31, 1}, background_set=true},
		{start=resize_start, end=resize_start+len("Resize"), color=alicorn.Color{0.87, 0.77, 0.52, 1}, color_set=true},
	}
	ok = explicit_start >= 0 && italic_start >= 0 && link_start >= 0 && code_start >= 0 && resize_start >= 0
	if !ok { return }
	ok = alicorn.virtual_list_height_index_init(&workload.index, ROW_COUNT, ESTIMATED_ROW_HEIGHT, allocator)
	return
}

destroy_workload :: proc(workload: ^Text_Workload, allocator := context.allocator) {
	for row in workload.rows { delete(row, allocator) }
	delete(workload.rows, allocator)
	delete(workload.row_nodes, allocator)
	alicorn.virtual_list_height_index_destroy(&workload.index)
}

describe_frame :: proc(rt: ^alicorn.Runtime, workload: ^Text_Workload, width, height, scroll_y: f32, previous_scroll_id: alicorn.Node_ID) -> (first, last: int, scroll_id: alicorn.Node_ID) {
	rt.viewport = alicorn.Rect{0, 0, width, height}
	if previous_scroll_id != 0 {
		_ = alicorn.scroll_region_set_offset(rt, previous_scroll_id, scroll_y, "benchmark variable-height scroll")
	}
	alicorn.invalidate_root(rt, "benchmark wrapped text frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, ROOT, label="text-layout-benchmark", style=alicorn.layout_style(.Column, width=width, height=height, clip=true))
	list := alicorn.virtual_list_begin_variable(
		&ui,
		&workload.index,
		key=alicorn.key_string("text-layout-variable-list"),
		style=alicorn.layout_style(.Column, width=width, height=height, clip=true),
		label="text-layout-variable-list",
	)
	first, last, scroll_id = list.first, list.last, list.scroll.id
	for row_index in first..<last {
		if !alicorn.key_scope_u64(&ui, u64(row_index), ROW) { continue }
		id := alicorn.text_ex(
			&ui,
			workload.rows[row_index],
			ROW,
			style=alicorn.layout_style(width=-1, height=-1),
			text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_REGULAR, overflow=.Wrap},
		)
		workload.row_nodes[row_index] = id
		_ = alicorn.text_style_spans(&ui, id, workload.style_spans)
		_ = alicorn.text_paint_spans(&ui, id, workload.paint_spans)
		alicorn.key_scope_end(&ui)
	}
	alicorn.virtual_list_end(&ui, list)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)

	for row_index in first..<last {
		id := workload.row_nodes[row_index]
		if node, exists := rt.nodes[id]; exists && node.bounds.h > 0 {
			_ = alicorn.virtual_list_height_index_set_height(&workload.index, row_index, node.bounds.h)
		}
	}
	return
}

direct_sparse_item_at :: proc(index: ^alicorn.Virtual_List_Height_Index, content_y: f32) -> int {
	if index == nil || index.item_count <= 0 { return -1 }
	alicorn.virtual_list_height_index_rebuild_prefix(index)
	target := max(content_y, f32(0))
	target = min(target, max(index.total_height-0.001, f32(0)))
	low, high := 0, len(index.entries)
	for low < high {
		mid := (low+high)/2
		entry := index.entries[mid]
		bottom := f32(entry.index+1)*index.estimated_height+entry.prefix_delta
		if bottom <= target { low = mid+1 } else { high = mid }
	}
	previous_delta: f32 = 0
	if low > 0 { previous_delta = index.entries[low-1].prefix_delta }
	gap_last := index.item_count-1
	if low < len(index.entries) {
		measured := index.entries[low]
		measured_top := f32(measured.index)*index.estimated_height+previous_delta
		if measured_top <= target { return measured.index }
		gap_last = measured.index-1
	}
	item := clamp(int((target-previous_delta)/index.estimated_height), 0, gap_last)
	if item < gap_last && f32(item+1)*index.estimated_height+previous_delta <= target { item += 1 }
	if item > 0 && f32(item)*index.estimated_height+previous_delta > target { item -= 1 }
	return item
}

direct_sparse_variable_metrics :: proc(index: ^alicorn.Virtual_List_Height_Index, scroll_y, viewport_height: f32) -> alicorn.Virtual_List_Metrics {
	result := alicorn.Virtual_List_Metrics{}
	if index == nil || index.item_count <= 0 || index.estimated_height <= 0 || viewport_height <= 0 { return result }
	alicorn.virtual_list_height_index_rebuild_prefix(index)
	result.content_height = index.total_height
	result.max_scroll_y = max(result.content_height-viewport_height, 0)
	result.offset_y = clamp(scroll_y, 0, result.max_scroll_y)
	result.first = direct_sparse_item_at(index, result.offset_y)
	viewport_end := result.offset_y+viewport_height
	trailing := direct_sparse_item_at(index, viewport_end)
	trailing_top := alicorn.virtual_list_height_index_item_top(index, trailing)
	result.last = trailing
	if trailing_top < viewport_end { result.last += 1 }
	result.last = min(max(result.first+1, result.last), index.item_count)
	result.leading_offset_y = result.offset_y-alicorn.virtual_list_height_index_item_top(index, result.first)
	return result
}

print_measurement :: proc(label: string, elapsed_ns: i64, frames: int, shape_before, cache_before, layout_before: u64, rt: ^alicorn.Runtime) {
	shape_calls := rt.text_engine.shape_calls-shape_before
	cache_hits := rt.text_engine.cache_hits-cache_before
	layout_visits := rt.stats.layout_nodes_visited-layout_before
	fmt.println(
		label,
		"frames", frames,
		"elapsed_ns", elapsed_ns,
		"ns_per_frame", elapsed_ns/i64(frames),
		"shape_calls", shape_calls,
		"shape_cache_hits", cache_hits,
		"layout_node_visits", layout_visits,
		"retained_nodes", len(rt.nodes),
	)
}

print_height_range :: proc(label: string, index: ^alicorn.Virtual_List_Height_Index) {
	if len(index.entries) == 0 {
		fmt.println(label, "measured_height_rows", 0)
		return
	}
	minimum := index.entries[0].height
	maximum := minimum
	for entry in index.entries {
		if entry.height < minimum { minimum = entry.height }
		if entry.height > maximum { maximum = entry.height }
	}
	fmt.println(label, "measured_height_rows", len(index.entries), "height_min", minimum, "height_max", maximum)
}

profile_variable_index :: proc(index: ^alicorn.Virtual_List_Height_Index) {
	// Measure the same sparse viewport geometry helper used by the variable
	// virtual-list path, separately from shaping, retained reconciliation, and
	// paint preparation. The surrounding full-frame benchmark remains the
	// end-to-end reference.
	alicorn.virtual_list_height_index_rebuild_prefix(index)
	current_samples := make([]i64, SCROLL_FRAMES)
	direct_samples := make([]i64, SCROLL_FRAMES)
	defer delete(current_samples)
	defer delete(direct_samples)
	current_checksum, direct_checksum, semantic_differences := 0, 0, 0
	for frame in 0..<SCROLL_FRAMES {
		scroll_y := f32(frame+1)*f32(160)
		start := time.now()
		current_metrics := alicorn.virtual_list_variable_metrics(index, scroll_y, VIEWPORT_HEIGHT)
		current_samples[frame] = time.duration_nanoseconds(time.since(start))
		start = time.now()
		direct_metrics := direct_sparse_variable_metrics(index, scroll_y, VIEWPORT_HEIGHT)
		direct_samples[frame] = time.duration_nanoseconds(time.since(start))
		current_checksum += current_metrics.first+current_metrics.last
		direct_checksum += direct_metrics.first+direct_metrics.last
		if current_metrics.first != direct_metrics.first || current_metrics.last != direct_metrics.last ||
		   abs(current_metrics.leading_offset_y-direct_metrics.leading_offset_y) > 0.001 {
			semantic_differences += 1
		}
	}
	for i in 1..<len(current_samples) {
		value := current_samples[i]
		j := i
		for j > 0 && current_samples[j-1] > value {
			current_samples[j] = current_samples[j-1]
			j -= 1
		}
		current_samples[j] = value
		value = direct_samples[i]
		j = i
		for j > 0 && direct_samples[j-1] > value {
			direct_samples[j] = direct_samples[j-1]
			j -= 1
		}
		direct_samples[j] = value
	}
	fmt.println("sparse_variable_metrics_only",
		"measured_overrides", len(index.entries),
		"calls", len(current_samples),
		"current_p50_ns", current_samples[len(current_samples)/2],
		"current_p95_ns", current_samples[(len(current_samples)*95)/100],
		"direct_y_p50_ns", direct_samples[len(direct_samples)/2],
		"direct_y_p95_ns", direct_samples[(len(direct_samples)*95)/100],
		"semantic_differences", semantic_differences,
		"checksums", current_checksum, direct_checksum,
	)
}

main :: proc() {
	workload, ok := make_workload()
	if !ok { fmt.println("benchmark setup failed: workload text spans could not be resolved"); os.exit(1) }
	defer destroy_workload(&workload)
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, INITIAL_WIDTH, VIEWPORT_HEIGHT})
	defer alicorn.destroy_runtime(&rt)
	if !alicorn.text_engine_load_font(&rt.text_engine, FONT_DATA) ||
	   !alicorn.text_engine_load_italic_font_role(&rt.text_engine, .UI, ITALIC_FONT_DATA) {
		fmt.println("benchmark setup failed: bundled text fonts could not be loaded")
		os.exit(1)
	}

	fmt.println("Alicorn focused text-layout benchmark (headless; raw wall-clock nanoseconds)")
	fmt.println("workload logical_rows", ROW_COUNT, "viewport", INITIAL_WIDTH, "x", VIEWPORT_HEIGHT, "estimated_row_height", ESTIMATED_ROW_HEIGHT, "text_bytes_first_row", len(workload.rows[0]), "typography_spans", len(workload.style_spans), "paint_spans", len(workload.paint_spans))

	// The first frame includes font-cache warmup and initial retained-node creation.
	first, last, scroll_id := describe_frame(&rt, &workload, INITIAL_WIDTH, VIEWPORT_HEIGHT, 0, 0)
	if rt.hard_error || first >= last { fmt.println("benchmark failed: initial visible rows were not realized"); os.exit(1) }
	fmt.println("initial_frame visible_rows", last-first, "measured_heights", len(workload.index.entries), "shape_calls_total", rt.text_engine.shape_calls, "retained_nodes", len(rt.nodes))

	// Let app-owned measured heights replace the initial estimate before timing.
	for _ in 0..<8 {
		first, last, scroll_id = describe_frame(&rt, &workload, INITIAL_WIDTH, VIEWPORT_HEIGHT, 0, scroll_id)
		if rt.hard_error { fmt.println("benchmark failed during height-index warmup:", rt.diagnostic); os.exit(1) }
	}
	print_height_range("warmup_geometry", &workload.index)

	shape_before := rt.text_engine.shape_calls
	cache_before := rt.text_engine.cache_hits
	layout_before := rt.stats.layout_nodes_visited
	start := time.now()
	for frame in 0..<SCROLL_FRAMES {
		offset := f32(frame+1)*f32(160)
		_, _, scroll_id = describe_frame(&rt, &workload, INITIAL_WIDTH, VIEWPORT_HEIGHT, offset, scroll_id)
		if rt.hard_error { fmt.println("benchmark failed during scroll:", rt.diagnostic); os.exit(1) }
	}
	scroll_ns := time.duration_nanoseconds(time.since(start))
	print_measurement("variable_height_scroll", scroll_ns, SCROLL_FRAMES, shape_before, cache_before, layout_before, &rt)

	shape_before = rt.text_engine.shape_calls
	cache_before = rt.text_engine.cache_hits
	layout_before = rt.stats.layout_nodes_visited
	start = time.now()
	for frame in 0..<RESIZE_FRAMES {
		width := f32(940) if frame%2 == 0 else f32(680)
		offset := f32(SCROLL_FRAMES+frame+1)*f32(160)
		_, _, scroll_id = describe_frame(&rt, &workload, width, VIEWPORT_HEIGHT, offset, scroll_id)
		if rt.hard_error { fmt.println("benchmark failed during resize:", rt.diagnostic); os.exit(1) }
	}
	resize_ns := time.duration_nanoseconds(time.since(start))
	print_measurement("wrapped_width_reflow", resize_ns, RESIZE_FRAMES, shape_before, cache_before, layout_before, &rt)
	print_height_range("final_geometry", &workload.index)
	profile_variable_index(&workload.index)
	fmt.println("text_cache_entries", alicorn.runa_cache_size(&rt.text_engine))
}
