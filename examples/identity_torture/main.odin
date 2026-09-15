package main

import "core:fmt"
import "core:os"
import alicorn "../../runtime"

render :: proc(rt: ^alicorn.Runtime, keys: []string) -> map[string]alicorn.Node_ID {
	ids := make(map[string]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "identity torture operation")
	ui, build := alicorn.begin_frame(rt)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, label="torture")
	for key in keys {
		if alicorn.key_scope_begin(&ui, alicorn.key_string(key)) {
			id := alicorn.text(&ui, fmt.aprintf("stateful %s", key), style=alicorn.Layout_Style{.Column, -1, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
			ids[key] = id
			alicorn.key_scope_end(&ui)
		}
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return ids
}

main :: proc() {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 480})
	keys := make([dynamic]string, 0)
	for i := 0; i < 12; i += 1 { append(&keys, fmt.aprintf("track-%d", i)) }
	ids := render(&rt, keys[:])
	expected := make(map[string]int)
	for key, id in ids {
		rt.nodes[id].local_counter = len(key)
		expected[key] = len(key)
	}
	seed: u64 = 0x51D3
	for step := 0; step < 5000; step += 1 {
		seed = seed*2862933555777941757 + 3037000493
		if len(keys) > 1 {
			a := int(seed % u64(len(keys)))
			b := int((seed >> 12) % u64(len(keys)))
			keys[a], keys[b] = keys[b], keys[a]
		}
		if step%17 == 0 && len(keys) > 2 {
			at := int(seed % u64(len(keys)))
			for i := at; i < len(keys)-1; i += 1 { keys[i] = keys[i+1] }
			pop(&keys)
		}
		if step%31 == 0 {
			append(&keys, fmt.aprintf("new-%d", step))
		}
		ids = render(&rt, keys[:])
		for key, id in ids {
			if _, exists := expected[key]; !exists { expected[key] = rt.nodes[id].local_counter }
			if rt.nodes[id].local_counter != expected[key] {
				fmt.println("IDENTITY FAILURE", step, key, id, rt.nodes[id].local_counter)
				os.exit(1)
			}
		}
	}
	fmt.println("identity torture: PASS; operations=5000 live_nodes=", len(rt.nodes))
	fmt.println("duplicate/missing keys are intentionally hard diagnostics; see tests for the negative case")
}
