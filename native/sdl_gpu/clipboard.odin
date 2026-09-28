package alicorn_sdl_gpu

import "core:mem"
import "core:strings"
import "vendor:sdl3"

// Clipboard_Get_Text_Proc reads UTF-8 text into memory owned by allocator.
// The returned string remains valid until that allocator releases it. A
// successful read of an empty clipboard returns "", true; failures return
// "", false.
Clipboard_Get_Text_Proc :: proc(data: rawptr, allocator: mem.Allocator) -> (text: string, ok: bool)

// Clipboard_Set_Text_Proc synchronously copies the supplied UTF-8 text before
// returning. The input is borrowed only for the duration of this call.
Clipboard_Set_Text_Proc :: proc(data: rawptr, text: string) -> bool

// Clipboard_Service is a UI-thread-only host service. It contains only opaque
// state and platform-neutral callbacks; SDL clipboard allocations and handles
// remain private to the native host.
Clipboard_Service :: struct {
	data:     rawptr,
	get_text: Clipboard_Get_Text_Proc,
	set_text: Clipboard_Set_Text_Proc,
}

// ClipboardGetText returns an owned copy allocated with allocator. The caller
// must release it with that same allocator. An unavailable service or OS
// clipboard error returns "", false; an empty clipboard is "", true.
ClipboardGetText :: proc(service: Clipboard_Service, allocator := context.allocator) -> (text: string, ok: bool) {
	if service.get_text == nil { return "", false }
	return service.get_text(service.data, allocator)
}

// ClipboardSetText places UTF-8 text on the OS clipboard. The host copies it
// before returning. Embedded NUL bytes are rejected because SDL's clipboard
// interface accepts a NUL-terminated string.
ClipboardSetText :: proc(service: Clipboard_Service, text: string) -> bool {
	if !clipboard_text_is_supported(text) { return false }
	if service.set_text == nil { return false }
	return service.set_text(service.data, text)
}

clipboard_text_is_supported :: proc(text: string) -> bool {
	return !strings.contains_rune(text, 0)
}

native_clipboard_get_text :: proc(data: rawptr, allocator: mem.Allocator) -> (text: string, ok: bool) {
	_ = data
	native_text := sdl3.GetClipboardText()
	if native_text == nil { return "", false }
	defer sdl3.free(rawptr(native_text))

	cloned, err := strings.clone_from_cstring(cstring(native_text), allocator)
	return cloned, err == nil
}

native_clipboard_set_text :: proc(data: rawptr, text: string) -> bool {
	_ = data
	if !clipboard_text_is_supported(text) { return false }

	// SDL copies clipboard input during the call. Use and release a normal
	// allocator-owned temporary rather than retaining an app buffer or SDL
	// object beyond the call.
	native_text, err := strings.clone_to_cstring(text, context.allocator)
	if err != nil { return false }
	defer delete(native_text, context.allocator)
	return sdl3.SetClipboardText(native_text)
}

native_clipboard_service :: proc() -> Clipboard_Service {
	return Clipboard_Service{
		get_text=native_clipboard_get_text,
		set_text=native_clipboard_set_text,
	}
}
