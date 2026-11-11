package runa

import "core:testing"
import parse "parse"
import "itemize"

@(test)
test_emoji_font_preference_uses_emoji_presentation_property :: proc(t: ^testing.T) {
	testing.expect(t, itemize.has_emoji_presentation('🎉') && itemize.has_emoji_presentation('⌚'),
		"default emoji-presentation scalars should prefer an available color face")
	testing.expect(t, !itemize.has_emoji_presentation('⚠') && !itemize.has_emoji_presentation('©'),
		"text-default pictographs should not be forced into emoji presentation without VS16")
}

@(test)
test_color_face_preference_respects_vs15_and_vs16 :: proc(t: ^testing.T) {
	codepoints := []rune{'🎉', '⚠'}
	monochrome := fallback_test_font(codepoints)
	color := fallback_test_font(codepoints)
	defer { delete(monochrome._cmap.groups); delete(color._cmap.groups) }
	color._has_colr = true
	color._colr = parse.Colr{version=1, base_glyph_list_off=1}
	fonts := [2]^Font{&monochrome, &color}
	stack := Font_Stack(fonts[:])

	picked, covered := pick_font_for_grapheme(stack, "🎉")
	default_emoji_prefers_color := covered && picked == &color
	picked, covered = pick_font_for_grapheme(stack, "⚠️")
	vs16_prefers_color := covered && picked == &color
	picked, covered = pick_font_for_grapheme(stack, "⚠︎")
	vs15_prefers_text := covered && picked == &monochrome
	testing.expect(t, default_emoji_prefers_color && vs16_prefers_color && vs15_prefers_text,
		"face preference should follow default emoji presentation and explicit text/emoji selectors")
}

fallback_test_font :: proc(codepoints: []rune) -> Font {
	unique := make([dynamic]rune, 0, len(codepoints), context.temp_allocator)
	for codepoint in codepoints {
		found := false
		for prior in unique { if prior == codepoint { found = true; break } }
		if !found { append(&unique, codepoint) }
	}
	for i in 1..<len(unique) {
		for j := i; j > 0 && unique[j] < unique[j-1]; j -= 1 {
			unique[j], unique[j-1] = unique[j-1], unique[j]
		}
	}
	groups := make([]parse.Cmap_Group, len(unique))
	for codepoint, index in unique {
		groups[index] = parse.Cmap_Group{
			start_char=u32(codepoint),
			end_char=u32(codepoint),
			start_glyph=u32(index+1),
		}
	}
	delete(unique)
	return Font{
		units_per_em=1000,
		num_glyphs=u16(len(groups)+1),
		ascent=800,
		descent=-200,
		_cmap=parse.Cmap{format=.Format_12, groups=groups},
	}
}

@(test)
test_grapheme_fallback_covers_cjk_emoji_variants_and_combining_marks :: proc(t: ^testing.T) {
	clusters := [?]string{
		"日本語", "简体中文", "繁體中文", "한국어", "🎉", "❤️", "♥︎", "👍🏽",
		"👩‍💻", "1️⃣", "🇯🇵", "é", "سلام",
	}
	for cluster in clusters {
		codepoints := make([dynamic]rune, 0, len(cluster), context.temp_allocator)
		for codepoint in cluster { append(&codepoints, codepoint) }
		font := fallback_test_font(codepoints[:])
		delete(codepoints)
		fonts := [1]^Font{&font}
		stack := Font_Stack(fonts[:])
		picked, covered := pick_font_for_grapheme(stack, cluster)
		testing.expect(t, covered && picked == &font,
			"a face that covers every significant scalar in a grapheme should be selected")
		delete(font._cmap.groups)
	}
}

@(test)
test_cluster_fallback_preserves_utf8_source_byte_ranges :: proc(t: ^testing.T) {
	latin := fallback_test_font([]rune{'a'})
	cjk := fallback_test_font([]rune{'中', '日', '本', '語'})
	defer { delete(latin._cmap.groups); delete(cjk._cmap.groups) }
	fonts := [2]^Font{&latin, &cjk}
	text := "a日本語"
	runs := paragraph_font_runs_make(text, Paragraph_Opts{fonts=Font_Stack(fonts[:]), size=16})
	testing.expect(t, len(runs) == 2 && runs[0].text_start == 0 && runs[0].text_end == 1 &&
		runs[1].text_start == 1 && runs[1].text_end == len(text),
		"fallback run boundaries must remain UTF-8 source byte offsets")
}

@(test)
test_cluster_fallback_keeps_zwj_sequence_in_one_face :: proc(t: ^testing.T) {
	woman := rune(0x1F469)
	laptop := rune(0x1F4BB)
	primary := fallback_test_font([]rune{woman})
	secondary := fallback_test_font([]rune{woman, laptop})
	defer { delete(primary._cmap.groups); delete(secondary._cmap.groups) }
	fonts := [2]^Font{&primary, &secondary}
	stack := Font_Stack(fonts[:])
	font, covered := pick_font_for_grapheme(stack, "👩‍💻")
	testing.expect(t, covered && font == &secondary,
		"the complete ZWJ grapheme must select one face covering both emoji bases")

	partial := fallback_test_font([]rune{laptop})
	defer { delete(partial._cmap.groups) }
	partial_fonts := [2]^Font{&primary, &partial}
	partial_stack := Font_Stack(partial_fonts[:])
	font, covered = pick_font_for_grapheme(partial_stack, "👩‍💻")
	testing.expect(t, !covered && font == &primary,
		"when no face covers the full ZWJ grapheme, keep it in the primary face instead of splitting it")
	options := Paragraph_Opts{fonts=partial_stack, size=16}
	runs := paragraph_font_runs_make("👩‍💻", options)
	testing.expect(t, len(runs) == 1 && runs[0].unresolved_fallback,
		"an unsupported cluster should stay one run and expose unresolved fallback coverage")
}

@(test)
test_adjacent_arabic_clusters_keep_one_script_run :: proc(t: ^testing.T) {
	font := fallback_test_font([]rune{'س', 'ل', 'ا', 'م'})
	defer { delete(font._cmap.groups) }
	fonts := [1]^Font{&font}
	options := Paragraph_Opts{fonts=Font_Stack(fonts[:]), size=16}
	runs := paragraph_font_runs_make("سلام", options)
	testing.expect(t, len(runs) == 1 && runs[0].script == itemize.ARABIC,
		"grapheme-aware fallback must still join compatible Arabic clusters for contextual shaping")
}

fallback_test_write_be_u16 :: proc(data: []u8, offset: int, value: u16) {
	data[offset] = u8(value >> 8)
	data[offset+1] = u8(value)
}

fallback_test_write_be_u32 :: proc(data: []u8, offset: int, value: u32) {
	data[offset] = u8(value >> 24)
	data[offset+1] = u8(value >> 16)
	data[offset+2] = u8(value >> 8)
	data[offset+3] = u8(value)
}

@(test)
test_color_table_inventory_detects_unsupported_bitmap_tables :: proc(t: ^testing.T) {
	tags := [?][4]u8{
		{'C','O','L','R'}, {'C','P','A','L'}, {'s','b','i','x'}, {'C','B','D','T'}, {'C','B','L','C'},
	}
	header_size := 12 + len(tags)*16
	data := make([]u8, header_size+len(tags)*2)
	defer delete(data)
	fallback_test_write_be_u32(data, 0, 0x00010000)
	fallback_test_write_be_u16(data, 4, u16(len(tags)))
	for tag, index in tags {
		record := 12 + index*16
		for byte, byte_index in tag { data[record+byte_index] = byte }
		fallback_test_write_be_u32(data, record+8, u32(header_size+index*2))
		fallback_test_write_be_u32(data, record+12, 2)
	}
	fallback_test_write_be_u16(data, header_size, 1)
	inventory, err := font_color_table_inventory(data)
	support := font_color_rendering_support(nil)
	testing.expect(t, err == .None && inventory.colr_version == 1 && inventory.has_colr && inventory.has_cpal &&
		inventory.has_sbix && inventory.has_cbdt && inventory.has_cblc,
		"raw font inspection should identify COLR, sbix, and CBDT/CBLC table presence")
	testing.expect(t, !support.colrv0 && !support.colrv1_subset && !support.sbix && !support.cbdt_cblc,
		"table discovery must not be confused with successful parsing or bitmap raster support")
}
