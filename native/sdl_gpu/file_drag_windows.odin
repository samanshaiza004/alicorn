#+build windows

package alicorn_sdl_gpu

import win "core:sys/windows"

foreign import Native_File_Drag_Ole32 "system:Ole32.lib"

@(default_calling_convention="system")
foreign Native_File_Drag_Ole32 {
	OleInitialize :: proc(reserved: rawptr) -> win.HRESULT ---
	OleUninitialize :: proc() ---
	DoDragDrop :: proc(data_object: rawptr, drop_source: rawptr, allowed_effects: win.DWORD, effect: ^win.DWORD) -> win.HRESULT ---
}

Win32_File_Drag_Interface :: struct {
	vtable: rawptr,
	owner:  ^Win32_File_Drag_Object,
}

Win32_File_Drag_Object :: struct {
	references:  u32,
	data_object: Win32_File_Drag_Interface,
	drop_source: Win32_File_Drag_Interface,
	path_wide:   []u16,
}

Win32_Format_Etc :: struct {
	cf_format: u16,
	ptd:       rawptr,
	dw_aspect: u32,
	lindex:    i32,
	tymed:     u32,
}

Win32_Stg_Medium_Contents :: struct #raw_union {
	h_global: win.HGLOBAL,
	stream:   rawptr,
	storage:  rawptr,
}

Win32_Stg_Medium :: struct {
	tymed:           u32,
	contents:        Win32_Stg_Medium_Contents,
	unk_for_release: rawptr,
}

Win32_Drop_Files :: struct {
	p_files: u32,
	point:   win.POINT,
	f_nc:    win.BOOL,
	f_wide:  win.BOOL,
}

Win32_IDataObject_VTable :: struct {
	query_interface:      proc "system" (this: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT,
	add_ref:              proc "system" (this: rawptr) -> win.ULONG,
	release:              proc "system" (this: rawptr) -> win.ULONG,
	get_data:             proc "system" (this: rawptr, format: ^Win32_Format_Etc, medium: ^Win32_Stg_Medium) -> win.HRESULT,
	get_data_here:        proc "system" (this: rawptr, format: ^Win32_Format_Etc, medium: ^Win32_Stg_Medium) -> win.HRESULT,
	query_get_data:       proc "system" (this: rawptr, format: ^Win32_Format_Etc) -> win.HRESULT,
	get_canonical_format: proc "system" (this: rawptr, input: ^Win32_Format_Etc, output: ^Win32_Format_Etc) -> win.HRESULT,
	set_data:             proc "system" (this: rawptr, format: ^Win32_Format_Etc, medium: ^Win32_Stg_Medium, release: win.BOOL) -> win.HRESULT,
	enum_format_etc:      proc "system" (this: rawptr, direction: u32, result: ^^Win32_IEnum_Format_Etc) -> win.HRESULT,
	d_advise:             proc "system" (this: rawptr, format: ^Win32_Format_Etc, flags: u32, sink: rawptr, connection: ^u32) -> win.HRESULT,
	d_unadvise:           proc "system" (this: rawptr, connection: u32) -> win.HRESULT,
	enum_d_advise:        proc "system" (this: rawptr, result: ^rawptr) -> win.HRESULT,
}

Win32_IEnum_Format_Etc :: struct {
	vtable: ^Win32_IEnum_Format_Etc_VTable,
	references: u32,
	cursor: u32,
}

Win32_IEnum_Format_Etc_VTable :: struct {
	query_interface: proc "system" (this: ^Win32_IEnum_Format_Etc, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT,
	add_ref:         proc "system" (this: ^Win32_IEnum_Format_Etc) -> win.ULONG,
	release:         proc "system" (this: ^Win32_IEnum_Format_Etc) -> win.ULONG,
	next:            proc "system" (this: ^Win32_IEnum_Format_Etc, count: u32, items: ^Win32_Format_Etc, fetched: ^u32) -> win.HRESULT,
	skip:            proc "system" (this: ^Win32_IEnum_Format_Etc, count: u32) -> win.HRESULT,
	reset:           proc "system" (this: ^Win32_IEnum_Format_Etc) -> win.HRESULT,
	clone:           proc "system" (this: ^Win32_IEnum_Format_Etc, result: ^^Win32_IEnum_Format_Etc) -> win.HRESULT,
}

WIN32_IID_I_DATA_OBJECT := win.GUID{0x0000010E, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
WIN32_IID_I_DROP_SOURCE := win.GUID{0x00000121, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
WIN32_IID_I_ENUM_FORMATETC := win.GUID{0x00000103, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}

WIN32_S_OK                    :: win.HRESULT(0)
WIN32_S_FALSE                 :: win.HRESULT(1)
WIN32_E_NOTIMPL               :: win.HRESULT(i32(-2147467263))
WIN32_E_NOINTERFACE           :: win.HRESULT(i32(-2147467262))
WIN32_E_POINTER               :: win.HRESULT(i32(-2147467261))
WIN32_E_OUTOFMEMORY           :: win.HRESULT(i32(-2147024882))
WIN32_E_INVALIDARG            :: win.HRESULT(i32(-2147024809))
WIN32_DV_E_FORMATETC           :: win.HRESULT(i32(-2147221404))
WIN32_DV_E_TYMED               :: win.HRESULT(i32(-2147221399))
WIN32_OLE_E_ADVISENOTSUPPORTED :: win.HRESULT(i32(-2147221501))
WIN32_DATA_S_SAMEFORMATETC     :: win.HRESULT(0x00040130)
WIN32_DRAGDROP_S_DROP          :: win.HRESULT(0x00040100)
WIN32_DRAGDROP_S_CANCEL        :: win.HRESULT(0x00040101)
WIN32_DRAGDROP_S_USEDEFAULTCURSORS :: win.HRESULT(0x00040102)

WIN32_DATADIR_GET      :: u32(1)
WIN32_DVASPECT_CONTENT :: u32(1)
WIN32_TYMED_HGLOBAL    :: u32(1)
WIN32_DROPEFFECT_COPY  :: win.DWORD(1)
WIN32_MK_LBUTTON       :: u32(1)

win32_iid_equal :: proc "contextless" (a, b: ^win.GUID) -> bool {
	return a != nil && b != nil && a.Data1 == b.Data1 && a.Data2 == b.Data2 &&
		a.Data3 == b.Data3 && a.Data4 == b.Data4
}

win32_file_drag_object_owner :: proc "contextless" (this: rawptr) -> ^Win32_File_Drag_Object {
	if this == nil { return nil }
	return (cast(^Win32_File_Drag_Interface)(this)).owner
}

win32_file_drag_query_interface :: proc "system" (this: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT {
	if result == nil { return WIN32_E_POINTER }
	result^ = nil
	owner := win32_file_drag_object_owner(this)
	if owner == nil || iid == nil { return WIN32_E_POINTER }
	if win32_iid_equal(iid, win.IUnknown_UUID) || win32_iid_equal(iid, &WIN32_IID_I_DATA_OBJECT) {
		result^ = rawptr(&owner.data_object)
	} else if win32_iid_equal(iid, &WIN32_IID_I_DROP_SOURCE) {
		result^ = rawptr(&owner.drop_source)
	} else {
		return WIN32_E_NOINTERFACE
	}
	owner.references += 1
	return WIN32_S_OK
}

win32_file_drag_add_ref :: proc "system" (this: rawptr) -> win.ULONG {
	owner := win32_file_drag_object_owner(this)
	if owner == nil { return 0 }
	owner.references += 1
	return win.ULONG(owner.references)
}

win32_file_drag_release :: proc "system" (this: rawptr) -> win.ULONG {
	owner := win32_file_drag_object_owner(this)
	if owner == nil { return 0 }
	if owner.references > 0 { owner.references -= 1 }
	remaining := owner.references
	if remaining == 0 {
		win.CoTaskMemFree(rawptr(raw_data(owner.path_wide)))
		win.CoTaskMemFree(rawptr(owner))
	}
	return win.ULONG(remaining)
}

win32_file_drag_format_supported :: proc "contextless" (format: ^Win32_Format_Etc) -> win.HRESULT {
	if format == nil { return WIN32_E_POINTER }
	if format.cf_format != u16(win.CF_HDROP) || format.dw_aspect != WIN32_DVASPECT_CONTENT || format.lindex != -1 {
		return WIN32_DV_E_FORMATETC
	}
	if (format.tymed & WIN32_TYMED_HGLOBAL) == 0 { return WIN32_DV_E_TYMED }
	return WIN32_S_OK
}

win32_file_drag_get_data :: proc "system" (this: rawptr, format: ^Win32_Format_Etc, medium: ^Win32_Stg_Medium) -> win.HRESULT {
	if medium == nil { return WIN32_E_POINTER }
	medium^ = {}
	if win32_file_drag_object_owner(this) == nil { return WIN32_E_POINTER }
	if result := win32_file_drag_format_supported(format); i32(result) < 0 { return result }
	wide := win32_file_drag_object_owner(this).path_wide
	if len(wide) == 0 { return WIN32_E_INVALIDARG }
	byte_count := size_of(Win32_Drop_Files) + (len(wide)+2)*size_of(u16)
	hglobal := cast(win.HGLOBAL)(win.GlobalAlloc(win.GMEM_MOVEABLE | win.GMEM_ZEROINIT, win.SIZE_T(byte_count)))
	if hglobal == win.HGLOBAL(nil) { return WIN32_E_OUTOFMEMORY }
	locked := win.GlobalLock(hglobal)
	if locked == nil {
		_ = win.GlobalFree(cast(win.LPVOID)hglobal)
		return WIN32_E_OUTOFMEMORY
	}
	header := cast(^Win32_Drop_Files)(locked)
	header^ = Win32_Drop_Files{p_files=u32(size_of(Win32_Drop_Files)), f_wide=win.BOOL(true)}
	destination := cast([^]u16)(cast(uintptr)(locked)+uintptr(size_of(Win32_Drop_Files)))
	copy(destination[:len(wide)], wide)
	_ = win.GlobalUnlock(hglobal)
	medium.tymed = WIN32_TYMED_HGLOBAL
	medium.contents.h_global = hglobal
	medium.unk_for_release = nil
	return WIN32_S_OK
}

win32_file_drag_get_data_here :: proc "system" (this: rawptr, _format: ^Win32_Format_Etc, _medium: ^Win32_Stg_Medium) -> win.HRESULT {
	if win32_file_drag_object_owner(this) == nil { return WIN32_E_POINTER }
	return WIN32_E_NOTIMPL
}

win32_file_drag_query_get_data :: proc "system" (_this: rawptr, format: ^Win32_Format_Etc) -> win.HRESULT {
	return win32_file_drag_format_supported(format)
}

win32_file_drag_get_canonical_format :: proc "system" (_this: rawptr, input: ^Win32_Format_Etc, output: ^Win32_Format_Etc) -> win.HRESULT {
	if input == nil || output == nil { return WIN32_E_POINTER }
	output^ = input^
	output.ptd = nil
	return WIN32_DATA_S_SAMEFORMATETC
}

win32_file_drag_set_data :: proc "system" (_this: rawptr, _format: ^Win32_Format_Etc, _medium: ^Win32_Stg_Medium, _release: win.BOOL) -> win.HRESULT {
	return WIN32_E_NOTIMPL
}

win32_file_drag_enum_next :: proc "system" (this: ^Win32_IEnum_Format_Etc, count: u32, items: ^Win32_Format_Etc, fetched: ^u32) -> win.HRESULT {
	if this == nil || items == nil { return WIN32_E_POINTER }
	if count == 0 { if fetched != nil { fetched^ = 0 }; return WIN32_S_OK }
	if count > 1 && fetched == nil { return WIN32_E_INVALIDARG }
	if this.cursor != 0 {
		if fetched != nil { fetched^ = 0 }
		return WIN32_S_FALSE
	}
	items^ = Win32_Format_Etc{cf_format=u16(win.CF_HDROP), dw_aspect=WIN32_DVASPECT_CONTENT, lindex=-1, tymed=WIN32_TYMED_HGLOBAL}
	this.cursor = 1
	if fetched != nil { fetched^ = 1 }
	return WIN32_S_OK if count == 1 else WIN32_S_FALSE
}

win32_file_drag_enum_skip :: proc "system" (this: ^Win32_IEnum_Format_Etc, count: u32) -> win.HRESULT {
	if this == nil { return WIN32_E_POINTER }
	if count == 0 { return WIN32_S_OK }
	if this.cursor != 0 { return WIN32_S_FALSE }
	this.cursor = 1
	return WIN32_S_OK if count == 1 else WIN32_S_FALSE
}

win32_file_drag_enum_reset :: proc "system" (this: ^Win32_IEnum_Format_Etc) -> win.HRESULT {
	if this == nil { return WIN32_E_POINTER }
	this.cursor = 0
	return WIN32_S_OK
}

win32_file_drag_enum_query_interface :: proc "system" (this: ^Win32_IEnum_Format_Etc, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT {
	if result == nil { return WIN32_E_POINTER }
	result^ = nil
	if this == nil || iid == nil { return WIN32_E_POINTER }
	if !win32_iid_equal(iid, win.IUnknown_UUID) && !win32_iid_equal(iid, &WIN32_IID_I_ENUM_FORMATETC) {
		return WIN32_E_NOINTERFACE
	}
	result^ = rawptr(this)
	_ = win32_file_drag_enum_add_ref(this)
	return WIN32_S_OK
}

win32_file_drag_enum_add_ref :: proc "system" (this: ^Win32_IEnum_Format_Etc) -> win.ULONG {
	if this == nil { return 0 }
	this.references += 1
	return win.ULONG(this.references)
}

win32_file_drag_enum_release :: proc "system" (this: ^Win32_IEnum_Format_Etc) -> win.ULONG {
	if this == nil { return 0 }
	if this.references > 0 { this.references -= 1 }
	remaining := this.references
	if remaining == 0 { win.CoTaskMemFree(rawptr(this)) }
	return win.ULONG(remaining)
}

win32_file_drag_enum_clone :: proc "system" (this: ^Win32_IEnum_Format_Etc, result: ^^Win32_IEnum_Format_Etc) -> win.HRESULT {
	if this == nil || result == nil { return WIN32_E_POINTER }
	clone := cast(^Win32_IEnum_Format_Etc)(win.CoTaskMemAlloc(win.SIZE_T(size_of(Win32_IEnum_Format_Etc))))
	if clone == nil { return WIN32_E_OUTOFMEMORY }
	clone^ = Win32_IEnum_Format_Etc{vtable=&WIN32_IENUM_FORMAT_ETC_VTABLE, references=1, cursor=this.cursor}
	result^ = clone
	return WIN32_S_OK
}

WIN32_IENUM_FORMAT_ETC_VTABLE: Win32_IEnum_Format_Etc_VTable = {
	query_interface=win32_file_drag_enum_query_interface,
	add_ref=win32_file_drag_enum_add_ref,
	release=win32_file_drag_enum_release,
	next=win32_file_drag_enum_next,
	skip=win32_file_drag_enum_skip,
	reset=win32_file_drag_enum_reset,
	clone=win32_file_drag_enum_clone,
}

win32_file_drag_enum_format_etc :: proc "system" (_this: rawptr, direction: u32, result: ^^Win32_IEnum_Format_Etc) -> win.HRESULT {
	if result == nil { return WIN32_E_POINTER }
	result^ = nil
	if direction != WIN32_DATADIR_GET { return WIN32_E_NOTIMPL }
	enumerator := cast(^Win32_IEnum_Format_Etc)(win.CoTaskMemAlloc(win.SIZE_T(size_of(Win32_IEnum_Format_Etc))))
	if enumerator == nil { return WIN32_E_OUTOFMEMORY }
	enumerator^ = Win32_IEnum_Format_Etc{vtable=&WIN32_IENUM_FORMAT_ETC_VTABLE, references=1}
	result^ = enumerator
	return WIN32_S_OK
}

win32_file_drag_advise :: proc "system" (_this: rawptr, _format: ^Win32_Format_Etc, _flags: u32, _sink: rawptr, _connection: ^u32) -> win.HRESULT {
	return WIN32_OLE_E_ADVISENOTSUPPORTED
}

win32_file_drag_unadvise :: proc "system" (_this: rawptr, _connection: u32) -> win.HRESULT {
	return WIN32_OLE_E_ADVISENOTSUPPORTED
}

win32_file_drag_enum_d_advise :: proc "system" (_this: rawptr, result: ^rawptr) -> win.HRESULT {
	if result != nil { result^ = nil }
	return WIN32_OLE_E_ADVISENOTSUPPORTED
}

WIN32_I_DATA_OBJECT_VTABLE: Win32_IDataObject_VTable = {
	query_interface=win32_file_drag_query_interface,
	add_ref=win32_file_drag_add_ref,
	release=win32_file_drag_release,
	get_data=win32_file_drag_get_data,
	get_data_here=win32_file_drag_get_data_here,
	query_get_data=win32_file_drag_query_get_data,
	get_canonical_format=win32_file_drag_get_canonical_format,
	set_data=win32_file_drag_set_data,
	enum_format_etc=win32_file_drag_enum_format_etc,
	d_advise=win32_file_drag_advise,
	d_unadvise=win32_file_drag_unadvise,
	enum_d_advise=win32_file_drag_enum_d_advise,
}

win32_drop_source_query_continue :: proc "system" (_this: rawptr, escape_pressed: win.BOOL, key_state: u32) -> win.HRESULT {
	if escape_pressed == win.BOOL(true) { return WIN32_DRAGDROP_S_CANCEL }
	if (key_state & WIN32_MK_LBUTTON) == 0 { return WIN32_DRAGDROP_S_DROP }
	return WIN32_S_OK
}

win32_drop_source_give_feedback :: proc "system" (_this: rawptr, _effect: win.DWORD) -> win.HRESULT {
	return WIN32_DRAGDROP_S_USEDEFAULTCURSORS
}

Win32_IDropSource_VTable :: struct {
	query_interface:      proc "system" (this: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT,
	add_ref:              proc "system" (this: rawptr) -> win.ULONG,
	release:              proc "system" (this: rawptr) -> win.ULONG,
	query_continue_drag:  proc "system" (this: rawptr, escape_pressed: win.BOOL, key_state: u32) -> win.HRESULT,
	give_feedback:        proc "system" (this: rawptr, effect: win.DWORD) -> win.HRESULT,

}

WIN32_I_DROP_SOURCE_VTABLE: Win32_IDropSource_VTable = {
	query_interface=win32_file_drag_query_interface,
	add_ref=win32_file_drag_add_ref,
	release=win32_file_drag_release,
	query_continue_drag=win32_drop_source_query_continue,
	give_feedback=win32_drop_source_give_feedback,
}

native_windows_file_drag_start :: proc(_data: rawptr, path: string) -> bool {
	wide := win.utf8_to_utf16(path, context.temp_allocator)
	if len(wide) == 0 { return false }
	if i32(OleInitialize(nil)) < 0 { return false }
	defer OleUninitialize()

	object := cast(^Win32_File_Drag_Object)(win.CoTaskMemAlloc(win.SIZE_T(size_of(Win32_File_Drag_Object))))
	if object == nil { return false }
	path_wide := cast([^]u16)(win.CoTaskMemAlloc(win.SIZE_T((len(wide)+1)*size_of(u16))))
	if path_wide == nil {
		win.CoTaskMemFree(rawptr(object))
		return false
	}
	copy(path_wide[:len(wide)], wide)
	path_wide[len(wide)] = 0
	object^ = Win32_File_Drag_Object{references=1, path_wide=path_wide[:len(wide)]}
	object.data_object = Win32_File_Drag_Interface{vtable=rawptr(&WIN32_I_DATA_OBJECT_VTABLE), owner=object}
	object.drop_source = Win32_File_Drag_Interface{vtable=rawptr(&WIN32_I_DROP_SOURCE_VTABLE), owner=object}
	effect: win.DWORD
	status := DoDragDrop(rawptr(&object.data_object), rawptr(&object.drop_source), WIN32_DROPEFFECT_COPY, &effect)
	_ = win32_file_drag_release(rawptr(&object.data_object))
	return status == WIN32_DRAGDROP_S_DROP || status == WIN32_DRAGDROP_S_CANCEL
}
