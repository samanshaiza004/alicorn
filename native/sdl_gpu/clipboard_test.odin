package alicorn_sdl_gpu

import "core:mem"
import "core:strings"
import "core:testing"

Clipboard_Test_Backend :: struct {
	allocator: mem.Allocator,
	text:      string,
	readable:  bool,
	writeable: bool,
	reads:     int,
	writes:    int,
}

clipboard_test_get_text :: proc(data: rawptr, allocator: mem.Allocator) -> (text: string, ok: bool) {
	backend := cast(^Clipboard_Test_Backend)data
	backend.reads += 1
	if !backend.readable { return "", false }
	cloned, err := strings.clone(backend.text, allocator)
	return cloned, err == nil
}

clipboard_test_set_text :: proc(data: rawptr, text: string) -> bool {
	backend := cast(^Clipboard_Test_Backend)data
	backend.writes += 1
	if !backend.writeable { return false }
	if len(backend.text) > 0 { delete(backend.text, backend.allocator) }
	cloned, err := strings.clone(text, backend.allocator)
	if err != nil { return false }
	backend.text = cloned
	return true
}

@(test)
test_clipboard_service_owns_read_copy_and_handles_large_utf8_text :: proc(t: ^testing.T) {
	backend := Clipboard_Test_Backend{allocator=context.allocator, readable=true, writeable=true}
	service := Clipboard_Service{data=rawptr(&backend), get_text=clipboard_test_get_text, set_text=clipboard_test_set_text}
	defer if len(backend.text) > 0 { delete(backend.text, backend.allocator) }

	bytes := make([]byte, 100*1024, allocator=context.temp_allocator)
	for i in 0..<len(bytes) { bytes[i] = 'x' }
	// Include multibyte UTF-8 at both ends to make sure this is copied as bytes,
	// not truncated or converted through a platform-native wide string.
	copy(bytes[:3], []byte{0xe3, 0x81, 0x82})
	copy(bytes[len(bytes)-4:], []byte{0xf0, 0x9f, 0x8c, 0x80})
	input := string(bytes)

	testing.expect(t, ClipboardSetText(service, input), "large UTF-8 clipboard write should succeed")
	testing.expect(t, backend.writes == 1, "clipboard set should call the host service exactly once")
	got, ok := ClipboardGetText(service, context.allocator)
	if len(got) > 0 { defer delete(got, context.allocator) }
	testing.expect(t, ok, "clipboard read should succeed")
	testing.expect(t, len(got) == len(input), "clipboard read should preserve a large payload length")
	testing.expect(t, got == input, "clipboard read should preserve the exact UTF-8 bytes")
	testing.expect(t, backend.reads == 1, "clipboard get should call the host service exactly once")
}

@(test)
test_clipboard_service_distinguishes_empty_clipboard_from_failure :: proc(t: ^testing.T) {
	backend := Clipboard_Test_Backend{allocator=context.allocator, readable=true, writeable=true}
	service := Clipboard_Service{data=rawptr(&backend), get_text=clipboard_test_get_text, set_text=clipboard_test_set_text}
	got, ok := ClipboardGetText(service, context.allocator)
	if len(got) > 0 { defer delete(got, context.allocator) }
	testing.expect(t, ok && got == "", "an empty clipboard is a successful empty read")

	backend.readable = false
	_, ok = ClipboardGetText(service, context.allocator)
	testing.expect(t, !ok, "an OS read failure should be distinct from empty clipboard text")
}

@(test)
test_clipboard_service_rejects_embedded_nul_and_missing_operations :: proc(t: ^testing.T) {
	backend := Clipboard_Test_Backend{allocator=context.allocator, writeable=true}
	service := Clipboard_Service{data=rawptr(&backend), set_text=clipboard_test_set_text}
	testing.expect(t, !ClipboardSetText(service, "before\x00after"), "embedded NUL must not silently truncate clipboard text")
	testing.expect(t, backend.writes == 0, "invalid input should be rejected before reaching the backend")
	testing.expect(t, !ClipboardSetText({}, "text"), "missing clipboard service should fail cleanly")
	_, ok := ClipboardGetText({}, context.allocator)
	testing.expect(t, !ok, "missing clipboard read operation should fail cleanly")
}
