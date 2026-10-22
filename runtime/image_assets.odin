#+vet explicit-allocators
package alicorn

import "core:mem"
import odin_image "core:image"
import odin_png "core:image/png"
import odin_qoi "core:image/qoi"

// Importing the format packages registers their bounded built-in decoders.
_ :: odin_png
_ :: odin_qoi

IMAGE_MAX_ENCODED_BYTES :: 128 * 1024 * 1024
IMAGE_MAX_DECODED_BYTES :: 64 * 1024 * 1024
IMAGE_MAX_DIMENSION :: 16384

image_read_be_u32 :: proc(data: []u8, offset: int) -> (value: u32, ok: bool) {
	if offset < 0 || offset+4 > len(data) { return 0, false }
	value = u32(data[offset])<<24 | u32(data[offset+1])<<16 | u32(data[offset+2])<<8 | u32(data[offset+3])
	return value, true
}

image_header_dimensions :: proc(data: []u8) -> (width, height: u32, format_ok: bool, header_ok: bool) {
	if len(data) < 4 { return }
	#partial switch odin_image.which_bytes(data) {
	case .PNG:
		if len(data) < 24 { return 0, 0, true, false }
		width, _ = image_read_be_u32(data, 16)
		height, _ = image_read_be_u32(data, 20)
		return width, height, true, true
	case .QOI:
		if len(data) < 14 { return 0, 0, true, false }
		width, _ = image_read_be_u32(data, 4)
		height, _ = image_read_be_u32(data, 8)
		return width, height, true, true
	case:
		return 0, 0, false, false
	}
}

// image_decode_bytes is independent of Runtime state and may run on a worker.
// The scratch allocator must be worker-local; the pixel allocator must support
// cross-thread ownership transfer and remain alive after the worker exits.
image_decode_bytes :: proc(data: []u8, allocator := context.allocator, scratch_allocator := context.temp_allocator) -> (pixels: Image_Decoded, err: Image_Load_Error) {
	if len(data) == 0 { return {}, .Empty_Input }
	if len(data) > IMAGE_MAX_ENCODED_BYTES { return {}, .Input_Too_Large }
	width, height, recognized, header_ok := image_header_dimensions(data)
	if !recognized { return {}, .Unsupported_Format }
	if !header_ok || width == 0 || height == 0 { return {}, .Invalid_Header }
	if width > IMAGE_MAX_DIMENSION || height > IMAGE_MAX_DIMENSION || u64(width)*u64(height)*4 > IMAGE_MAX_DECODED_BYTES {
		return {}, .Dimensions_Too_Large
	}
	decoded, decode_error := odin_image.load_from_bytes(data, options={.alpha_add_if_missing}, allocator=scratch_allocator)
	if decode_error != nil || decoded == nil {
		if decoded != nil { odin_image.destroy(decoded, scratch_allocator) }
		return {}, .Decode_Failed
	}
	defer odin_image.destroy(decoded, scratch_allocator)
	if decoded.width != int(width) || decoded.height != int(height) || decoded.depth != 8 && decoded.depth != 16 || decoded.channels < 1 || decoded.channels > 4 {
		return {}, .Unsupported_Pixel_Format
	}
	pixel_count := decoded.width*decoded.height
	channel_bytes := decoded.depth/8
	expected_bytes := pixel_count*decoded.channels*channel_bytes
	if len(decoded.pixels.buf) != expected_bytes { return {}, .Decode_Failed }
	rgba := make([]u8, pixel_count*4, allocator)
	if rgba == nil && pixel_count > 0 { return {}, .Resource_Limit }
	if decoded.depth == 8 {
		for i := 0; i < pixel_count; i += 1 {
			pixel := decoded.pixels.buf[i*decoded.channels:]
		switch decoded.channels {
		case 1: rgba[i*4+0], rgba[i*4+1], rgba[i*4+2], rgba[i*4+3] = pixel[0], pixel[0], pixel[0], 255
		case 2: rgba[i*4+0], rgba[i*4+1], rgba[i*4+2], rgba[i*4+3] = pixel[0], pixel[0], pixel[0], pixel[1]
		case 3: rgba[i*4+0], rgba[i*4+1], rgba[i*4+2], rgba[i*4+3] = pixel[0], pixel[1], pixel[2], 255
		case 4: copy(rgba[i*4:i*4+4], pixel[:4])
		}
		}
	} else {
		pixels16 := mem.slice_data_cast([]u16, decoded.pixels.buf[:])
		for i := 0; i < pixel_count; i += 1 {
			pixel := pixels16[i*decoded.channels:]
		switch decoded.channels {
		case 1: rgba[i*4+0], rgba[i*4+1], rgba[i*4+2], rgba[i*4+3] = u8(pixel[0]>>8), u8(pixel[0]>>8), u8(pixel[0]>>8), 255
		case 2: rgba[i*4+0], rgba[i*4+1], rgba[i*4+2], rgba[i*4+3] = u8(pixel[0]>>8), u8(pixel[0]>>8), u8(pixel[0]>>8), u8(pixel[1]>>8)
		case 3: rgba[i*4+0], rgba[i*4+1], rgba[i*4+2], rgba[i*4+3] = u8(pixel[0]>>8), u8(pixel[1]>>8), u8(pixel[2]>>8), 255
		case 4: for channel := 0; channel < 4; channel += 1 { rgba[i*4+channel] = u8(pixel[channel]>>8) }
		}
		}
	}
    return Image_Decoded{decoded.width, decoded.height, rgba, allocator}, .None
}

image_decoded_destroy :: proc(pixels: ^Image_Decoded) {
    if pixels == nil { return }
    if pixels.rgba8 != nil { delete(pixels.rgba8, pixels.allocator) }
    pixels^ = {}
}

// image_adopt_decoded transfers the finished pixels without copying or
// decoding. Call only on the Runtime's owner thread. Failure retains ownership
// in pixels; success empties pixels and transfers it to the Runtime.
image_adopt_decoded :: proc(rt: ^Runtime, pixels: ^Image_Decoded) -> (Image_Handle, Image_Load_Error) {
    if rt == nil || pixels == nil { return {}, .Resource_Limit }
    if pixels.width <= 0 || pixels.height <= 0 { return {}, .Invalid_Header }
    if pixels.width > IMAGE_MAX_DIMENSION || pixels.height > IMAGE_MAX_DIMENSION || u64(pixels.width)*u64(pixels.height)*4 > IMAGE_MAX_DECODED_BYTES { return {}, .Dimensions_Too_Large }
    if len(pixels.rgba8) != pixels.width*pixels.height*4 || pixels.allocator.procedure == nil { return {}, .Unsupported_Pixel_Format }
    if rt.image_resource_sequence == max(u64) { return {}, .Resource_Limit }
    rt.image_resource_sequence += 1
    rt.images[rt.image_resource_sequence] = Image_Resource{pixels.width, pixels.height, pixels.rgba8, pixels.allocator}
    pixels^ = {}
    invalidate_root(rt, "application decoded image adopted")
    return Image_Handle(rt.image_resource_sequence), .None
}

// image_load_bytes is the synchronous convenience path for small built-in
// assets. Applications with large files should decode on a worker and adopt.
image_load_bytes :: proc(rt: ^Runtime, data: []u8) -> (Image_Handle, Image_Load_Error) {
    if rt == nil { return {}, .Resource_Limit }
    pixels, err := image_decode_bytes(data, rt.persistent_allocator, rt.scratch_allocator)
    if err != .None { return {}, err }
    defer image_decoded_destroy(&pixels)
    return image_adopt_decoded(rt, &pixels)
}

// image_release retires a Runtime-owned image handle. A stale retained widget
// then resolves as empty and is rebuilt on the next application description.
image_release :: proc(rt: ^Runtime, handle: Image_Handle) -> bool {
	if rt == nil || u64(handle) == 0 { return false }
	resource, ok := rt.images[u64(handle)]
	if !ok { return false }
	delete(resource.rgba8, resource.allocator)
	delete_key(&rt.images, u64(handle))
	invalidate_root(rt, "application image resource released")
	return true
}

image_resolve :: proc(rt: ^Runtime, handle: Image_Handle) -> (view: Image_Pixels_View, ok: bool) {
	if rt == nil || u64(handle) == 0 { return }
	resource, found := rt.images[u64(handle)]
	if !found { return }
	return Image_Pixels_View{resource.width, resource.height, resource.rgba8}, true
}

// font_load_bytes copies and installs bytes as the selected primary face.
// It may be called before host startup or from a UI-thread callback afterward.
font_load_bytes :: proc(rt: ^Runtime, role: Font_Role, data: []u8) -> bool {
	if rt == nil || !text_engine_load_font_role(&rt.text_engine, role, data) { return false }
	rt.text_engine.application_primary_font[role] = true
	invalidate_root(rt, "application font role changed")
	return true
}

font_load_italic_bytes :: proc(rt: ^Runtime, role: Font_Role, data: []u8) -> bool {
	if rt == nil || !text_engine_load_italic_font_role(&rt.text_engine, role, data) { return false }
	rt.text_engine.application_italic_font[role] = true
	invalidate_root(rt, "application italic font role changed")
	return true
}

font_load_fallback_bytes :: proc(rt: ^Runtime, role: Font_Role, data: []u8) -> bool {
	if rt == nil || !text_engine_load_fallback_font_role(&rt.text_engine, role, data) { return false }
	rt.text_engine.application_fallback_font[role] = true
	invalidate_root(rt, "application fallback font role changed")
	return true
}
