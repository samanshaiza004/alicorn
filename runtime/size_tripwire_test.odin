package alicorn

import "core:fmt"
import "core:testing"

// These constants make retained-state growth visible in both code review and
// test output before style/material data is added to every node.
NODE_SIZE_BYTES :: size_of(Node)
DESCRIPTION_SIZE_BYTES :: size_of(Description)
PAINT_COMMAND_SIZE_BYTES :: size_of(Paint_Command)

NODE_SIZE_TRIPWIRE_BYTES :: 2048
DESCRIPTION_SIZE_TRIPWIRE_BYTES :: 768
PAINT_COMMAND_SIZE_TRIPWIRE_BYTES :: 128

@(test)
test_retained_record_sizes_stay_within_budget :: proc(t: ^testing.T) {
	fmt.println("Alicorn retained record sizes: Node=", NODE_SIZE_BYTES,
		" bytes, Description=", DESCRIPTION_SIZE_BYTES, " bytes, Paint_Command=", PAINT_COMMAND_SIZE_BYTES, " bytes")
	testing.expect(t, NODE_SIZE_BYTES <= NODE_SIZE_TRIPWIRE_BYTES,
		"Node exceeded the retained-state size budget; keep per-node styling data compact")
	testing.expect(t, DESCRIPTION_SIZE_BYTES <= DESCRIPTION_SIZE_TRIPWIRE_BYTES,
		"Description exceeded the description-time size budget")
	testing.expect(t, PAINT_COMMAND_SIZE_BYTES <= PAINT_COMMAND_SIZE_TRIPWIRE_BYTES,
		"Paint_Command exceeded the renderer-boundary size budget")
}
