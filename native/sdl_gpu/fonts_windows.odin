#+build windows

package alicorn_sdl_gpu

import "core:mem"
import "core:strings"
import win "core:sys/windows"
import "core:unicode/utf8"
import alicorn "../../runtime"

foreign import alicorn_dwrite "system:Dwrite.lib"
foreign alicorn_dwrite {
	DWriteCreateFactory :: proc "system" (factory_type: u32, iid: ^win.GUID, factory: ^rawptr) -> win.HRESULT ---
}

foreign import alicorn_kernel32 "system:Kernel32.lib"
foreign alicorn_kernel32 {
	GetUserDefaultUILanguage :: proc "system" () -> u16 ---
}

WIN32_DWRITE_FACTORY2_IID :: win.GUID{
	Data1=0x0439FC60, Data2=0xCA44, Data3=0x4994,
	Data4=[8]win.BYTE{0x8D,0xEE,0x3A,0x9A,0xF7,0xB7,0x32,0xEC},
}
WIN32_DWRITE_TEXT_ANALYSIS_SOURCE_IID :: win.GUID{
	Data1=0x688E1A58, Data2=0x5094, Data3=0x47C8,
	Data4=[8]win.BYTE{0xAD,0xC8,0xFB,0xCE,0xA6,0x0A,0xE9,0x2B},
}
WIN32_DWRITE_LOCAL_FONT_FILE_LOADER_IID :: win.GUID{
	Data1=0xB2D9F3EC, Data2=0xC9FE, Data3=0x4A11,
	Data4=[8]win.BYTE{0xA2,0xEC,0xD8,0x62,0x08,0xF7,0xC0,0xA2},
}
WIN32_IUNKNOWN_IID :: win.GUID{
	Data1=0, Data2=0, Data3=0,
	Data4=[8]win.BYTE{0xC0,0,0,0,0,0,0,0x46},
}

Win32_DWrite_Object :: struct { vtable: ^rawptr }
Win32_DWrite_Text_Source :: struct {
	vtable: ^rawptr,
	text: []u16,
	locale: []u16,
	reading_direction: i32,
}

Win32_DWrite_Sample :: struct {
	text: string,
	locale: string,
}

Win32_DWrite_Query_Interface :: proc "system" (self: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT
Win32_DWrite_Add_Ref :: proc "system" (self: rawptr) -> u32
Win32_DWrite_Release :: proc "system" (self: rawptr) -> u32
Win32_DWrite_Get_Text_At_Position :: proc "system" (self: rawptr, position: u32, text: ^^u16, length: ^u32) -> win.HRESULT
Win32_DWrite_Get_Text_Before_Position :: proc "system" (self: rawptr, position: u32, text: ^^u16, length: ^u32) -> win.HRESULT
Win32_DWrite_Get_Reading_Direction :: proc "system" (self: rawptr) -> i32
Win32_DWrite_Get_Locale_Name :: proc "system" (self: rawptr, position: u32, length: ^u32, locale: ^^u16) -> win.HRESULT
Win32_DWrite_Get_Number_Substitution :: proc "system" (self: rawptr, position: u32, length: ^u32, substitution: ^rawptr) -> win.HRESULT

Win32_DWrite_Get_System_Font_Fallback :: proc "system" (self: rawptr, fallback: ^rawptr) -> win.HRESULT
Win32_DWrite_Map_Characters :: proc "system" (
	self: rawptr,
	source: rawptr,
	text_position, text_length: u32,
	base_font_collection: rawptr,
	base_family_name: ^u16,
	weight, style, stretch: u32,
	mapped_length: ^u32,
	mapped_font: ^rawptr,
	scale: ^f32,
) -> win.HRESULT
Win32_DWrite_Font_Create_Face :: proc "system" (self: rawptr, face: ^rawptr) -> win.HRESULT
Win32_DWrite_Face_Get_Files :: proc "system" (self: rawptr, count: ^u32, files: ^rawptr) -> win.HRESULT
Win32_DWrite_Face_Get_Index :: proc "system" (self: rawptr) -> u32
Win32_DWrite_File_Get_Reference_Key :: proc "system" (self: rawptr, key: ^rawptr, key_size: ^u32) -> win.HRESULT
Win32_DWrite_File_Get_Loader :: proc "system" (self: rawptr, loader: ^rawptr) -> win.HRESULT
Win32_DWrite_Loader_Create_Stream :: proc "system" (self: rawptr, key: rawptr, key_size: u32, stream: ^rawptr) -> win.HRESULT
Win32_DWrite_Stream_Get_Size :: proc "system" (self: rawptr, size: ^u64) -> win.HRESULT
Win32_DWrite_Stream_Read_Fragment :: proc "system" (self: rawptr, data: ^^u8, offset, size: u64, fragment_context: ^rawptr) -> win.HRESULT
Win32_DWrite_Stream_Release_Fragment :: proc "system" (self: rawptr, fragment_context: rawptr)

win32_dwrite_succeeded :: proc(result: win.HRESULT) -> bool { return i32(result) >= 0 }

win32_dwrite_method :: proc(object: rawptr, index: int) -> rawptr {
	if object == nil { return nil }
	com := (^Win32_DWrite_Object)(object)
	return (cast([^]rawptr)com.vtable)[index]
}

win32_dwrite_release :: proc(object: rawptr) {
	if object == nil { return }
	release := transmute(Win32_DWrite_Release)(win32_dwrite_method(object, 2))
	_ = release(object)
}

win32_dwrite_source_add_ref :: proc "system" (self: rawptr) -> u32 { _ = self; return 1 }
win32_dwrite_source_release :: proc "system" (self: rawptr) -> u32 { _ = self; return 1 }

win32_dwrite_source_query_interface :: proc "system" (self: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT {
	if result == nil { return win.HRESULT(-2147467261) }
	result^ = nil
	if iid == nil { return win.HRESULT(-2147467261) }
	is_unknown := iid.Data1 == WIN32_IUNKNOWN_IID.Data1 && iid.Data2 == WIN32_IUNKNOWN_IID.Data2 &&
		iid.Data3 == WIN32_IUNKNOWN_IID.Data3 && iid.Data4 == WIN32_IUNKNOWN_IID.Data4
	is_source := iid.Data1 == WIN32_DWRITE_TEXT_ANALYSIS_SOURCE_IID.Data1 &&
		iid.Data2 == WIN32_DWRITE_TEXT_ANALYSIS_SOURCE_IID.Data2 &&
		iid.Data3 == WIN32_DWRITE_TEXT_ANALYSIS_SOURCE_IID.Data3 &&
		iid.Data4 == WIN32_DWRITE_TEXT_ANALYSIS_SOURCE_IID.Data4
	if !is_unknown && !is_source {
		return win.HRESULT(-2147467262)
	}
	result^ = self
	_ = win32_dwrite_source_add_ref(self)
	return win.HRESULT(0)
}

win32_dwrite_source_get_text_at :: proc "system" (self: rawptr, position: u32, text: ^^u16, length: ^u32) -> win.HRESULT {
	if text == nil || length == nil { return win.HRESULT(-2147467261) }
	source := (^Win32_DWrite_Text_Source)(self)
	if position >= u32(len(source.text)) {
		text^, length^ = nil, 0
		return win.HRESULT(0)
	}
	text^ = &source.text[int(position)]
	length^ = u32(len(source.text)-int(position))
	return win.HRESULT(0)
}

win32_dwrite_source_get_text_before :: proc "system" (self: rawptr, position: u32, text: ^^u16, length: ^u32) -> win.HRESULT {
	if text == nil || length == nil { return win.HRESULT(-2147467261) }
	source := (^Win32_DWrite_Text_Source)(self)
	if position == 0 || position > u32(len(source.text)) {
		text^, length^ = nil, 0
		return win.HRESULT(0)
	}
	text^ = &source.text[0]
	length^ = position
	return win.HRESULT(0)
}

win32_dwrite_source_get_direction :: proc "system" (self: rawptr) -> i32 {
	return (^Win32_DWrite_Text_Source)(self).reading_direction
}

win32_dwrite_source_get_locale :: proc "system" (self: rawptr, position: u32, length: ^u32, locale: ^^u16) -> win.HRESULT {
	if length == nil || locale == nil { return win.HRESULT(-2147467261) }
	source := (^Win32_DWrite_Text_Source)(self)
	if position >= u32(len(source.text)) {
		length^, locale^ = 0, nil
		return win.HRESULT(0)
	}
	length^ = u32(len(source.text)-int(position))
	locale^ = &source.locale[0]
	return win.HRESULT(0)
}

win32_dwrite_source_get_number_substitution :: proc "system" (self: rawptr, position: u32, length: ^u32, substitution: ^rawptr) -> win.HRESULT {
	if length == nil || substitution == nil { return win.HRESULT(-2147467261) }
	source := (^Win32_DWrite_Text_Source)(self)
	length^ = u32(max(int(len(source.text))-int(position), 0))
	substitution^ = nil
	return win.HRESULT(0)
}

win32_dwrite_utf16 :: proc(value: string, allocator := context.temp_allocator) -> []u16 {
	result := make([dynamic]u16, 0, max(len(value), 2), allocator)
	for offset := 0; offset < len(value); {
		codepoint, byte_count := utf8.decode_rune_in_string(value[offset:])
		if byte_count <= 0 { byte_count = 1 }
		offset += byte_count
		if codepoint <= 0xFFFF {
			append(&result, u16(codepoint))
		} else {
			value32 := u32(codepoint)-0x10000
			append(&result, u16(0xD800+(value32>>10)), u16(0xDC00+(value32&0x3FF)))
		}
	}
	return result[:]
}

win32_dwrite_utf16_locale :: proc(value: string, allocator := context.temp_allocator) -> []u16 {
	result := make([dynamic]u16, 0, len(value)+1, allocator)
	for byte in value { append(&result, u16(byte)) }
	append(&result, 0)
	return result[:]
}

win32_dwrite_localized_samples :: proc() -> [12]Win32_DWrite_Sample {
	language := GetUserDefaultUILanguage()
	preferred_han := "en-US"
	switch language {
	case 0x0411: preferred_han = "ja-JP"
	case 0x0412: preferred_han = "ko-KR"
	case 0x0404, 0x0C04, 0x1404, 0x7C04: preferred_han = "zh-TW"
	case 0x0804, 0x1004, 0x7804: preferred_han = "zh-CN"
	}
	return [12]Win32_DWrite_Sample{
		{"語", preferred_han},
		{"日本語", "ja-JP"},
		{"简体中文", "zh-CN"},
		{"繁體中文", "zh-TW"},
		{"한국어", "ko-KR"},
		{"سلام", "ar-SA"},
		{"🎉", "en-US"},
		{"❤️", "en-US"},
		{"👍🏽", "en-US"},
		{"👩‍💻", "en-US"},
		{"1️⃣", "en-US"},
		{"🇯🇵", "en-US"},
	}
}

win32_dwrite_locale_reading_direction :: proc(locale: string) -> i32 {
	// DWRITE_READING_DIRECTION_RIGHT_TO_LEFT. The small startup sample list
	// currently contains Arabic as its only RTL language.
	if strings.has_prefix(locale, "ar") { return 1 }
	return 0 // DWRITE_READING_DIRECTION_LEFT_TO_RIGHT
}

win32_dwrite_load_face_bytes :: proc(fallback: rawptr, sample: string, locale_name: string) -> (data: []u8, face_index: int, ok: bool) {
	text := win32_dwrite_utf16(sample)
	locale := win32_dwrite_utf16_locale(locale_name)
	if len(text) == 0 { return }
	source_vtable := [?]rawptr{
		transmute(rawptr)win32_dwrite_source_query_interface,
		transmute(rawptr)win32_dwrite_source_add_ref,
		transmute(rawptr)win32_dwrite_source_release,
		transmute(rawptr)win32_dwrite_source_get_text_at,
		transmute(rawptr)win32_dwrite_source_get_text_before,
		transmute(rawptr)win32_dwrite_source_get_direction,
		transmute(rawptr)win32_dwrite_source_get_locale,
		transmute(rawptr)win32_dwrite_source_get_number_substitution,
	}
	source := Win32_DWrite_Text_Source{
		&source_vtable[0], text, locale, win32_dwrite_locale_reading_direction(locale_name),
	}
	map_characters := transmute(Win32_DWrite_Map_Characters)(win32_dwrite_method(fallback, 3))
	mapped_length: u32
	mapped_font: rawptr
	scale: f32
	map_result := map_characters(fallback, rawptr(&source), 0, u32(len(text)), nil, nil, 400, 0, 5, &mapped_length, &mapped_font, &scale)
	if !win32_dwrite_succeeded(map_result) || mapped_font == nil || mapped_length != u32(len(text)) {
		if mapped_font != nil { win32_dwrite_release(mapped_font) }
		return
	}
	// The retained face stack has no per-face em-scale field yet. Refuse
	// non-unit DirectWrite mappings rather than silently producing incorrect
	// glyph size and line metrics.
	if scale < 0.999 || scale > 1.001 {
		win32_dwrite_release(mapped_font)
		return
	}
	defer { win32_dwrite_release(mapped_font) }
	// IDWriteFont has 11 methods after IUnknown; CreateFontFace is slot 13.
	create_face := transmute(Win32_DWrite_Font_Create_Face)(win32_dwrite_method(mapped_font, 13))
	font_face: rawptr
	if !win32_dwrite_succeeded(create_face(mapped_font, &font_face)) || font_face == nil {
		win32_dwrite_release(font_face)
		return
	}
	defer { win32_dwrite_release(font_face) }
	get_index := transmute(Win32_DWrite_Face_Get_Index)(win32_dwrite_method(font_face, 5))
	face_index = int(get_index(font_face))
	get_files := transmute(Win32_DWrite_Face_Get_Files)(win32_dwrite_method(font_face, 4))
	// A face backed by multiple files is not a single SFNT/TTC byte blob and
	// cannot be registered by Runa's current face loader. Query the count first
	// as required by IDWriteFontFace::GetFiles, then accept exactly one file.
	file_count: u32
	if !win32_dwrite_succeeded(get_files(font_face, &file_count, nil)) || file_count != 1 { return }
	file: rawptr
	requested_file_count := u32(1)
	if !win32_dwrite_succeeded(get_files(font_face, &requested_file_count, &file)) || file == nil {
		win32_dwrite_release(file)
		return
	}
	defer { win32_dwrite_release(file) }
	get_reference_key := transmute(Win32_DWrite_File_Get_Reference_Key)(win32_dwrite_method(file, 3))
	get_loader := transmute(Win32_DWrite_File_Get_Loader)(win32_dwrite_method(file, 4))
	reference_key: rawptr
	reference_key_size: u32
	loader: rawptr
	if !win32_dwrite_succeeded(get_reference_key(file, &reference_key, &reference_key_size)) || reference_key == nil || reference_key_size == 0 { return }
	if !win32_dwrite_succeeded(get_loader(file, &loader)) || loader == nil {
		win32_dwrite_release(loader)
		return
	}
	defer { win32_dwrite_release(loader) }
	// Only consume the documented local-file loader. Calling GetFileSize on
	// DirectWrite's remote-font stream may require downloading the whole file;
	// system fallback discovery must not turn startup into network I/O.
	query_interface := transmute(Win32_DWrite_Query_Interface)(win32_dwrite_method(loader, 0))
	local_loader_iid := WIN32_DWRITE_LOCAL_FONT_FILE_LOADER_IID
	local_loader: rawptr
	if !win32_dwrite_succeeded(query_interface(loader, &local_loader_iid, &local_loader)) || local_loader == nil {
		win32_dwrite_release(local_loader)
		return
	}
	defer { win32_dwrite_release(local_loader) }
	create_stream := transmute(Win32_DWrite_Loader_Create_Stream)(win32_dwrite_method(local_loader, 3))
	stream: rawptr
	if !win32_dwrite_succeeded(create_stream(local_loader, reference_key, reference_key_size, &stream)) || stream == nil {
		win32_dwrite_release(stream)
		return
	}
	defer { win32_dwrite_release(stream) }
	get_size := transmute(Win32_DWrite_Stream_Get_Size)(win32_dwrite_method(stream, 5))
	file_size: u64
	if !win32_dwrite_succeeded(get_size(stream, &file_size)) || file_size == 0 || file_size > u64(alicorn.FONT_FACE_FILE_BYTE_LIMIT) { return }
	read_fragment := transmute(Win32_DWrite_Stream_Read_Fragment)(win32_dwrite_method(stream, 3))
	fragment: ^u8
	fragment_context: rawptr
	release_fragment := transmute(Win32_DWrite_Stream_Release_Fragment)(win32_dwrite_method(stream, 4))
	if !win32_dwrite_succeeded(read_fragment(stream, &fragment, 0, file_size, &fragment_context)) || fragment == nil {
		if fragment_context != nil { release_fragment(stream, fragment_context) }
		return
	}
	defer {
		release_fragment(stream, fragment_context)
	}
	data = make([]u8, int(file_size), context.temp_allocator)
	if data == nil { return {}, face_index, false }
	fragment_bytes := cast([^]u8)fragment
	for index in 0..<len(data) { data[index] = fragment_bytes[index] }
	ok = true
	return
}

// Resolve a small locale-aware set during startup. This avoids loading fonts or
// synchronously querying DirectWrite from typing, scrolling, or composition.
// Each mapping is for a complete UTF-16 sample; Runa still performs cluster-
// atomic cmap selection over the resulting immutable face stack.
native_load_directwrite_fallback_faces :: proc(rt: ^alicorn.Runtime) -> int {
	factory: rawptr
	factory_iid := WIN32_DWRITE_FACTORY2_IID
	if !win32_dwrite_succeeded(DWriteCreateFactory(0, &factory_iid, &factory)) || factory == nil { return 0 }
	defer { win32_dwrite_release(factory) }
	get_fallback := transmute(Win32_DWrite_Get_System_Font_Fallback)(win32_dwrite_method(factory, 26))
	fallback: rawptr
	if !win32_dwrite_succeeded(get_fallback(factory, &fallback)) || fallback == nil { return 0 }
	defer { win32_dwrite_release(fallback) }
	loaded_faces := 0
	for sample in win32_dwrite_localized_samples() {
	font_bytes, face_index, ok := win32_dwrite_load_face_bytes(fallback, sample.text, sample.locale)
		if !ok { continue }
		file := alicorn.font_file_load_bytes(rt, font_bytes)
		delete(font_bytes, context.temp_allocator)
		if file == 0 { continue }
		face := alicorn.font_face_load(rt, file, face_index)
		if face == 0 { continue }
		added_ui := alicorn.font_face_add_fallback(rt, .UI, face)
		added_monospace := alicorn.font_face_add_fallback(rt, .Monospace, face)
		if added_ui || added_monospace { loaded_faces += 1 }
	}
	return loaded_faces
}
