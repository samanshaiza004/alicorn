#+build linux

package alicorn_sdl_gpu

import "core:dynlib"
import "core:os"
import "core:strings"

Fontconfig_Symbols :: struct {
	init:                  proc "c" () -> int `dynlib:"FcInit"`,
	charset_create:        proc "c" () -> rawptr `dynlib:"FcCharSetCreate"`,
	charset_destroy:       proc "c" (charset: rawptr) `dynlib:"FcCharSetDestroy"`,
	charset_add_char:      proc "c" (charset: rawptr, codepoint: u32) -> int `dynlib:"FcCharSetAddChar"`,
	pattern_create:        proc "c" () -> rawptr `dynlib:"FcPatternCreate"`,
	pattern_destroy:       proc "c" (pattern: rawptr) `dynlib:"FcPatternDestroy"`,
	pattern_add_string:    proc "c" (pattern: rawptr, object, value: cstring) -> int `dynlib:"FcPatternAddString"`,
	pattern_add_charset:   proc "c" (pattern: rawptr, object: cstring, charset: rawptr) -> int `dynlib:"FcPatternAddCharSet"`,
	config_substitute:     proc "c" (config, pattern: rawptr, kind: int) -> int `dynlib:"FcConfigSubstitute"`,
	default_substitute:    proc "c" (pattern: rawptr) `dynlib:"FcDefaultSubstitute"`,
	font_match:            proc "c" (config, pattern: rawptr, result: ^int) -> rawptr `dynlib:"FcFontMatch"`,
	pattern_get_string:    proc "c" (pattern: rawptr, object: cstring, index: int, value: ^cstring) -> int `dynlib:"FcPatternGetString"`,
	_handle:               dynlib.Library,
}

fontconfig_symbols: Fontconfig_Symbols
fontconfig_initialized: bool

native_fontconfig_initialize :: proc() -> bool {
	if fontconfig_initialized {
		return fontconfig_symbols._handle != nil && fontconfig_symbols.init != nil &&
			fontconfig_symbols.charset_create != nil && fontconfig_symbols.charset_destroy != nil &&
			fontconfig_symbols.charset_add_char != nil && fontconfig_symbols.pattern_create != nil &&
			fontconfig_symbols.pattern_destroy != nil && fontconfig_symbols.pattern_add_string != nil &&
			fontconfig_symbols.pattern_add_charset != nil && fontconfig_symbols.config_substitute != nil &&
			fontconfig_symbols.default_substitute != nil && fontconfig_symbols.font_match != nil &&
			fontconfig_symbols.pattern_get_string != nil
	}
	fontconfig_initialized = true

	for library_path in ([?]string{"libfontconfig.so.1", "libfontconfig.so"}) {
		count, loaded := dynlib.initialize_symbols(&fontconfig_symbols, library_path, "", "_handle")
		if !loaded || count < 12 {
			if fontconfig_symbols._handle != nil {
				_ = dynlib.unload_library(fontconfig_symbols._handle)
				fontconfig_symbols = {}
			}
			continue
		}
		if fontconfig_symbols.init() == 0 { return false }
		return true
	}
	return false
}

native_fontconfig_find_font_with_library :: proc(family: cstring, codepoints: []rune) -> string {
	pattern := fontconfig_symbols.pattern_create()
	if pattern == nil { return "" }
	defer fontconfig_symbols.pattern_destroy(pattern)
	charset := fontconfig_symbols.charset_create()
	if charset == nil { return "" }
	defer fontconfig_symbols.charset_destroy(charset)

	if fontconfig_symbols.pattern_add_string(pattern, "family", family) == 0 { return "" }
	for codepoint in codepoints {
		if fontconfig_symbols.charset_add_char(charset, u32(codepoint)) == 0 { return "" }
	}
	if fontconfig_symbols.pattern_add_charset(pattern, "charset", charset) == 0 { return "" }
	if fontconfig_symbols.config_substitute(nil, pattern, 0) == 0 { return "" }
	fontconfig_symbols.default_substitute(pattern)

	result: int
	match := fontconfig_symbols.font_match(nil, pattern, &result)
	if match == nil || result != 0 {
		if match != nil { fontconfig_symbols.pattern_destroy(match) }
		return ""
	}
	defer fontconfig_symbols.pattern_destroy(match)
	path: cstring
	if fontconfig_symbols.pattern_get_string(match, "file", 0, &path) != 0 || path == nil { return "" }
	resolved, err := strings.clone(string(path), context.temp_allocator)
	if err != nil || resolved == "" || !os.exists(resolved) { return "" }
	return resolved
}

native_fontconfig_find_font_with_command :: proc(family: cstring, codepoints: []rune) -> string {
	// NixOS may expose Fontconfig through fc-match's own store RPATH without
	// putting libfontconfig.so on the host executable's loader path.
	query_builder, builder_err := strings.builder_make(allocator=context.temp_allocator)
	if builder_err != nil { return "" }
	defer strings.builder_destroy(&query_builder)
	strings.write_string(&query_builder, string(family))
	strings.write_string(&query_builder, ":charset=")
	for codepoint, index in codepoints {
		if index > 0 { strings.write_byte(&query_builder, ',') }
		strings.write_uint(&query_builder, uint(codepoint), 16)
	}
	query := strings.to_string(query_builder)
	command := [?]string{"fc-match", "-f", "%{file}", query}
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command=command[:]},
		context.temp_allocator,
	)
	defer delete(stdout, context.temp_allocator)
	defer delete(stderr, context.temp_allocator)
	if err != nil || !state.success { return "" }
	path := strings.trim_space(string(stdout))
	if path == "" || !os.exists(path) { return "" }
	resolved, clone_err := strings.clone(path, context.temp_allocator)
	if clone_err != nil { return "" }
	return resolved
}

native_fontconfig_find_font :: proc(family: cstring, codepoints: []rune) -> string {
	if len(codepoints) == 0 { return "" }
	if native_fontconfig_initialize() {
		if path := native_fontconfig_find_font_with_library(family, codepoints); path != "" {
			return path
		}
	}
	return native_fontconfig_find_font_with_command(family, codepoints)
}
