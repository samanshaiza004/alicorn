// Extracted unchanged parser/model routines from alicorn-history ce3276cf2fb425013df013bcb49e211ca234473a. See README.md for provenance.
package main

import "core:strconv"
import "core:strings"

git_patch_next_line :: proc(data: []byte, start: int) -> (line: string, next: int, ok: bool) {
	if start < 0 || start > len(data) { return }
	end := start
	for end < len(data) && data[end] != '\n' { end += 1 }
	line = string(data[start:end])
	if len(line) > 0 && line[len(line)-1] == '\r' { line = line[:len(line)-1] }
	next = end
	if next < len(data) { next += 1 }
	ok = true
	return
}

git_patch_parse_number :: proc(value: string, start: int) -> (number, next: int, ok: bool) {
	if start < 0 || start >= len(value) || value[start] < '0' || value[start] > '9' { return }
	end := start
	for end < len(value) && value[end] >= '0' && value[end] <= '9' { end += 1 }
	parsed, parsed_ok := strconv.parse_int(value[start:end])
	if !parsed_ok { return }
	return int(parsed), end, true
}

git_patch_parse_hunk_header :: proc(line: string) -> (old_start, old_count, new_start, new_count: int, ok: bool) {
	if len(line) < 4 || line[:2] != "@@" { return }
	position := 0
	minus := -1
	for i := 2; i < len(line); i += 1 {
		if line[i] == '-' { minus = i; break }
	}
	if minus < 0 { return }
	old_start, position, ok = git_patch_parse_number(line, minus+1)
	if !ok { return }
	old_count = 1
	if position < len(line) && line[position] == ',' {
		old_count, position, ok = git_patch_parse_number(line, position+1)
		if !ok { return }
	}
	plus := -1
	for i := position; i < len(line); i += 1 {
		if line[i] == '+' { plus = i; break }
	}
	if plus < 0 { return }
	new_start, position, ok = git_patch_parse_number(line, plus+1)
	if !ok { return }
	new_count = 1
	if position < len(line) && line[position] == ',' {
		new_count, position, ok = git_patch_parse_number(line, position+1)
		if !ok { return }
	}
	return old_start, old_count, new_start, new_count, true
}

git_patch_append_metadata :: proc(patch: ^File_Patch, line: string) -> bool {
	copy, err := strings.clone(line)
	if err != nil { return false }
	if patch.metadata == nil { patch.metadata = make([dynamic]string, 0, 4) }
	append(&patch.metadata, copy)
	return true
}

git_patch_append_line :: proc(hunk: ^Diff_Hunk, kind: Diff_Line_Kind, old_line, new_line: int, value: string) -> bool {
	copy, err := strings.clone(value)
	if err != nil { return false }
	if hunk.lines == nil { hunk.lines = make([dynamic]Diff_Line, 0, 32) }
	append(&hunk.lines, Diff_Line{kind=kind, old_line=old_line, new_line=new_line, text=copy})
	return true
}

git_parse_patch :: proc(data: []byte) -> (patch: File_Patch, error_text: string) {
	patch.hunks = make([dynamic]Diff_Hunk, 0, 8)
	patch.metadata = make([dynamic]string, 0, 4)
	position := 0
	current_hunk := -1
	old_line := 0
	new_line := 0
	for position < len(data) {
		line, next, line_ok := git_patch_next_line(data, position)
		if !line_ok { break }
		position = next
		if len(line) >= 2 && line[:2] == "@@" {
			old_start, old_count, new_start, new_count, header_ok := git_patch_parse_hunk_header(line)
			if !header_ok {
				file_patch_destroy(&patch)
				error_text = git_owned_error("git patch contained a malformed hunk header")
				return
			}
			header, clone_err := strings.clone(line)
			if clone_err != nil {
				file_patch_destroy(&patch)
				error_text = git_owned_error("out of memory copying patch hunk header")
				return
			}
			append(&patch.hunks, Diff_Hunk{
				old_start=old_start,
				old_count=old_count,
				new_start=new_start,
				new_count=new_count,
				header=header,
				lines=make([dynamic]Diff_Line, 0, 32),
			})
			current_hunk = len(patch.hunks)-1
			old_line = old_start
			new_line = new_start
			continue
		}
		if current_hunk < 0 {
			if strings.has_prefix(line, "Binary files ") || strings.has_prefix(line, "GIT binary patch") {
				patch.binary = true
				if !git_patch_append_metadata(&patch, line) {
					file_patch_destroy(&patch)
					error_text = git_owned_error("out of memory copying binary patch metadata")
					return
				}
			} else if strings.has_prefix(line, "old mode ") ||
				strings.has_prefix(line, "new mode ") ||
				strings.has_prefix(line, "new file mode ") ||
				strings.has_prefix(line, "deleted file mode ") ||
				strings.has_prefix(line, "rename from ") ||
				strings.has_prefix(line, "rename to ") {
				if !git_patch_append_metadata(&patch, line) {
					file_patch_destroy(&patch)
					error_text = git_owned_error("out of memory copying patch metadata")
					return
				}
			}
			continue
		}
		hunk := &patch.hunks[current_hunk]
		if len(line) == 0 {
			// A valid empty patch line still carries its leading kind byte. A
			// truly empty line is metadata from a malformed/foreign producer.
			continue
		}
		kind := Diff_Line_Kind.Meta
		text := line
		advance_old := false
		advance_new := false
		switch line[0] {
		case ' ':
			kind = .Context
			text = line[1:]
			advance_old = true
			advance_new = true
		case '+':
			kind = .Addition
			text = line[1:]
			advance_new = true
		case '-':
			kind = .Deletion
			text = line[1:]
			advance_old = true
		case '\\':
			kind = .Meta
		}
		if !git_patch_append_line(hunk, kind, old_line if advance_old else 0, new_line if advance_new else 0, text) {
			file_patch_destroy(&patch)
			error_text = git_owned_error("out of memory copying patch line")
			return
		}
		if advance_old { old_line += 1 }
		if advance_new { new_line += 1 }
	}
	history_patch_prepare_display(&patch)
	return
}


Diff_Line_Kind :: enum {
	Context,
	Addition,
	Deletion,
	Meta,
}

Diff_Line :: struct {
	kind:     Diff_Line_Kind,
	old_line: int,
	new_line: int,
	text:     string,
}

Diff_Hunk :: struct {
	old_start: int,
	old_count: int,
	new_start: int,
	new_count: int,
	header:    string,
	lines:     [dynamic]Diff_Line,
}

File_Patch :: struct {
	path:     string,
	binary:   bool,
	metadata: [dynamic]string,
	hunks:    [dynamic]Diff_Hunk,
	// Display rows are an owned index into the patch's existing strings. The
	// text fields borrow metadata/hunk storage; only the index array itself is
	// owned here. This keeps visible-row lookup O(1) without duplicating text.
	display_lines: [dynamic]Patch_Display_Line,
	content_width: f32,
}

Patch_Display_Line :: struct {
	kind:     Diff_Line_Kind,
	old_line: int,
	new_line: int,
	text:     string,
	hunk:     bool,
	hunk_index: int,
}

history_patch_prepare_display :: proc(patch: ^File_Patch) {
	if patch == nil || patch.display_lines != nil { return }
	capacity := len(patch.metadata) + 1
	for hunk in patch.hunks { capacity += 1 + len(hunk.lines) }
	patch.display_lines = make([dynamic]Patch_Display_Line, 0, capacity)
	width: f32 = 720
	for metadata in patch.metadata {
		append(&patch.display_lines, Patch_Display_Line{kind=.Meta, text=metadata})
		width = max(width, f32(len(metadata))*8 + 24)
	}
	for hunk, hunk_index in patch.hunks {
		append(&patch.display_lines, Patch_Display_Line{kind=.Meta, text=hunk.header, hunk=true, hunk_index=hunk_index})
		width = max(width, f32(len(hunk.header))*8 + 24)
		for line in hunk.lines {
			append(&patch.display_lines, Patch_Display_Line{kind=line.kind, old_line=line.old_line, new_line=line.new_line, text=line.text, hunk_index=hunk_index})
			width = max(width, f32(len(line.text))*8 + 160)
		}
	}
	if len(patch.display_lines) == 0 && patch.binary {
		append(&patch.display_lines, Patch_Display_Line{kind=.Meta, text="Binary file changed"})
	}
	patch.content_width = min(width, 4096)
}


diff_line_destroy :: proc(line: ^Diff_Line) {
	if len(line.text) > 0 { delete(line.text) }
	line^ = {}
}

diff_hunk_destroy :: proc(hunk: ^Diff_Hunk) {
	if len(hunk.header) > 0 { delete(hunk.header) }
	for &line in hunk.lines { diff_line_destroy(&line) }
	delete(hunk.lines)
	hunk^ = {}
}

file_patch_destroy :: proc(patch: ^File_Patch) {
	if len(patch.path) > 0 { delete(patch.path) }
	for metadata in patch.metadata { if len(metadata) > 0 { delete(metadata) } }
	delete(patch.metadata)
	for &hunk in patch.hunks { diff_hunk_destroy(&hunk) }
	delete(patch.hunks)
	delete(patch.display_lines)
	patch^ = {}
}


git_owned_error :: proc(value: string) -> string { copy, _ := strings.clone(value); return copy }

