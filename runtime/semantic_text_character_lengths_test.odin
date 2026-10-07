package alicorn

import "core:mem"
import "core:testing"

@(test)
test_semantic_text_character_lengths_uses_extended_graphemes :: proc(t: ^testing.T) {
	allocator := context.allocator

	lengths, ok := semantic_text_character_lengths("Hello", allocator)
	ascii_expected := [5]u8{1, 1, 1, 1, 1}
	testing.expect(t, ok && semantic_byte_lengths_equal(lengths, ascii_expected[:]),
		"ASCII text should produce one byte length per grapheme")
	if len(lengths) > 0 { delete(lengths, allocator) }

	lengths, ok = semantic_text_character_lengths("A日本🙂", allocator)
	unicode_expected := [4]u8{1, 3, 3, 4}
	testing.expect(t, ok && semantic_byte_lengths_equal(lengths, unicode_expected[:]),
		"multibyte CJK and emoji should preserve their UTF-8 byte lengths")
	if len(lengths) > 0 { delete(lengths, allocator) }

	lengths, ok = semantic_text_character_lengths("é👨‍👩‍👧‍👦", allocator)
	grapheme_expected := [2]u8{3, 25}
	testing.expect(t, ok && semantic_byte_lengths_equal(lengths, grapheme_expected[:]),
		"combining and ZWJ sequences should each remain one extended grapheme")
	if len(lengths) > 0 { delete(lengths, allocator) }

	lengths, ok = semantic_text_character_lengths("a\r\nb", allocator)
	crlf_expected := [3]u8{1, 2, 1}
	testing.expect(t, ok && semantic_byte_lengths_equal(lengths, crlf_expected[:]),
		"CRLF should remain one selectable grapheme with a two-byte length")
	if len(lengths) > 0 { delete(lengths, allocator) }

	lengths, ok = semantic_text_character_lengths("", allocator)
	testing.expect(t, ok && len(lengths) == 0,
		"empty text should be valid and return no selectable-unit lengths")
}

@(test)
test_semantic_text_character_lengths_enforces_u8_limit_without_leaking :: proc(t: ^testing.T) {
	allocator := context.allocator

	// 'a' plus 127 two-byte combining marks forms one 255-byte grapheme.
	bytes_255 := make([]u8, 255, allocator=allocator)
	bytes_255[0] = 'a'
	for i in 0..<127 {
		bytes_255[1+i*2] = 0xCC
		bytes_255[2+i*2] = 0x81
	}
	lengths, ok := semantic_text_character_lengths(string(bytes_255), allocator)
	testing.expect(t, ok && len(lengths) == 1 && lengths[0] == 255,
		"an exactly 255-byte grapheme should fit the selectable-unit representation")
	if len(lengths) > 0 { delete(lengths, allocator) }
	delete(bytes_255, allocator)

	// 'a' + 126 U+0301 marks is 253 bytes; U+1AB0 contributes three more,
	// making one constructible 256-byte extended grapheme.
	bytes_256 := make([]u8, 256, allocator=allocator)
	bytes_256[0] = 'a'
	for i in 0..<126 {
		bytes_256[1+i*2] = 0xCC
		bytes_256[2+i*2] = 0x81
	}
	bytes_256[253] = 0xE1
	bytes_256[254] = 0xAA
	bytes_256[255] = 0xB0

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, allocator)
	tracked_allocator := mem.tracking_allocator(&tracking)
	rejected_lengths, accepted := semantic_text_character_lengths(string(bytes_256), tracked_allocator)
	testing.expect(t, !accepted && len(rejected_lengths) == 0,
		"a 256-byte grapheme should fail without returning partial lengths")
	testing.expect(t, len(tracking.allocation_map) == 0,
		"rejecting an oversized grapheme should release the allocated result")
	mem.tracking_allocator_destroy(&tracking)
	delete(bytes_256, allocator)
}
