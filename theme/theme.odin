package theme

import "core:mem"
import "core:strings"

// Theme source values are deliberately limited to context-free values. A
// Length is expressed in Alicorn logical units; it does not depend on layout,
// density, or typography context.
Token_Kind :: enum u8 {
	Color,
	Length,
}

// Theme_Color stores linear-sRGB RGB channels and straight (untransformed)
// alpha. Authoring frontends decode encoded sRGB before constructing this
// value. The runtime adapter and Alicorn solid GPU path pass these floats
// through unchanged; output transfer is defined by the renderer/swapchain.
Theme_Color :: struct {
	r, g, b, a: f32,
}

Theme_Length :: distinct f32

Theme_Alias :: struct {
	target: string,
}

Theme_Token_Value :: union #no_nil {
	Theme_Color,
	Theme_Length,
	Theme_Alias,
}

Source_Span :: struct {
	path:         string,
	start_offset: u64,
	end_offset:   u64,
	line:         u32,
	column:       u32,
}

Token_Definition :: struct {
	name:  string,
	kind:  Token_Kind,
	value: Theme_Token_Value,
	span:  Source_Span,
}

Theme_Contract_Version :: struct {
	major: u16,
	minor: u16,
}

Theme_Source_Metadata :: struct {
	// The schema version is an exact source-format contract, independent from
	// the style contract version consumed by a runtime.
	schema_version: u32,
	contract:       Theme_Contract_Version,
	span:           Source_Span,
}

Theme_Compiler_Support :: struct {
	schema_version: u32,
	contract_major: u16,
	contract_minor: u16,
}

THEME_SOURCE_SCHEMA_VERSION :: u32(1)
THEME_CONTRACT_VERSION :: Theme_Contract_Version{major=0, minor=2}
THEME_LENGTH_MAX_LOGICAL_UNITS :: f32(1_000_000)
THEME_COMPILER_SUPPORT :: Theme_Compiler_Support{
	schema_version=THEME_SOURCE_SCHEMA_VERSION,
	contract_major=THEME_CONTRACT_VERSION.major,
	contract_minor=THEME_CONTRACT_VERSION.minor,
}

// These IDs are the stable core role vocabulary. Keep app/vendor roles out of
// this enum; extension roles are declared by namespaced strings below.
Core_Color_Role :: enum u8 {
	Window_Background,
	Surface,
	Subtle_Surface,
	Editor_Background,
	Text,
	Muted_Text,
	Accent,
	Accent_Hover,
	Accent_Pressed,
	Accent_Text,
	Selection,
	Focus,
	Semantic_Focus,
	Border,
	Danger,
	Success,
	Scrollbar_Track,
	Scrollbar_Thumb,
	Count,
}

CORE_COLOR_ROLE_COUNT :: int(Core_Color_Role.Count)

Core_Role_Binding :: struct {
	role:  Core_Color_Role,
	token: string,
	span:  Source_Span,
}

// Extension roles are intentionally separate from core roles. Accepted names
// start with app.<component>. or vendor.<vendor>.<component>.
Extension_Role_Declaration :: struct {
	name:  string,
	kind:  Token_Kind,
	token: string,
	span:  Source_Span,
}

// Layers are supplied base-to-derived. Definitions replace same-named
// definitions from earlier layers; aliases are resolved only after every
// layer has been merged.
Theme_Source_Model :: struct {
	metadata:        Theme_Source_Metadata,
	tokens:          []Token_Definition,
	core_roles:      []Core_Role_Binding,
	extension_roles: []Extension_Role_Declaration,
}

Color_Token_ID :: distinct u32
Length_Token_ID :: distinct u32
Extension_Color_Role_ID :: distinct u64
Extension_Length_Role_ID :: distinct u64

// Compiled_Theme contains only values and compact IDs needed to resolve style
// references. Names and source locations live in Theme_Debug_Metadata.
Compiled_Theme :: struct {
	contract:                Theme_Contract_Version,
	colors:                  []Theme_Color,
	lengths:                 []Theme_Length,
	core_color_roles:        [CORE_COLOR_ROLE_COUNT]Color_Token_ID,
	extension_color_roles:   []Compiled_Extension_Color_Role,
	extension_length_roles:  []Compiled_Extension_Length_Role,
	content_signature:       u64,
}

Compiled_Extension_Color_Role :: struct {
	id:    Extension_Color_Role_ID,
	token: Color_Token_ID,
}

Compiled_Extension_Length_Role :: struct {
	id:    Extension_Length_Role_ID,
	token: Length_Token_ID,
}

Token_Provenance :: struct {
	id:          u32,
	name:        string,
	kind:        Token_Kind,
	span:        Source_Span,
	alias_target: string,
}

Extension_Role_Provenance :: struct {
	color_id:  Extension_Color_Role_ID,
	length_id: Extension_Length_Role_ID,
	name:      string,
	kind:      Token_Kind,
	span:      Source_Span,
}

// Debug/provenance data is separately owned so a release runtime can retain
// Compiled_Theme without also retaining authored names or source locations.
Theme_Debug_Metadata :: struct {
	tokens:          []Token_Provenance,
	extension_roles: []Extension_Role_Provenance,
}

Diagnostic_Severity :: enum u8 {
	Error,
	Warning,
}

Diagnostic_Code :: enum u16 {
	Duplicate_Token,
	Token_Type_Changed,
	Invalid_Token_Name,
	Invalid_Token_Kind,
	Unsupported_Schema_Version,
	Unsupported_Contract_Version,
	Unknown_Alias,
	Alias_Type_Mismatch,
	Alias_Cycle,
	Invalid_Color,
	Invalid_Length,
	Token_Value_Type_Mismatch,
	Invalid_Core_Role,
	Duplicate_Core_Role,
	Core_Role_Token_Not_Found,
	Core_Role_Token_Type_Mismatch,
	Invalid_Extension_Role_Namespace,
	Duplicate_Extension_Role,
	Extension_Role_Type_Changed,
	Extension_Role_Hash_Collision,
	Extension_Role_Token_Not_Found,
	Extension_Role_Token_Type_Mismatch,
}

// symbol_path is populated for alias cycles (repeats the first symbol at the
// end) and extension-role hash collisions (the colliding authored names).
// Returned diagnostic paths and symbol strings are owned by the output.
Theme_Diagnostic :: struct {
	code:                      Diagnostic_Code,
	severity:                  Diagnostic_Severity,
	path:                       string,
	span:                       Source_Span,
	symbol_path:                []string,
	related_name:               string,
	expected_kind:              Token_Kind,
	actual_kind:                Token_Kind,
	expected_schema_version:    u32,
	actual_schema_version:      u32,
	supported_contract_major:   u16,
	supported_contract_minor:   u16,
	actual_contract:            Theme_Contract_Version,
}

Theme_Compile_Output :: struct {
	theme:       Compiled_Theme,
	debug:       Theme_Debug_Metadata,
	diagnostics: []Theme_Diagnostic,
	ok:          bool,
}

Resolve_State :: enum u8 {
	Unvisited,
	Visiting,
	Resolved,
	Failed,
}

Effective_Token :: struct {
	definition: Token_Definition,
	layer:      int,
	state:      Resolve_State,
	color:      Theme_Color,
	length:     Theme_Length,
	color_id:   Color_Token_ID,
	length_id:  Length_Token_ID,
}

Effective_Core_Role :: struct {
	binding: Core_Role_Binding,
	layer:   int,
}

Effective_Extension_Role :: struct {
	declaration: Extension_Role_Declaration,
	layer:       int,
	color_id:    Extension_Color_Role_ID,
	length_id:   Extension_Length_Role_ID,
}

theme_compile :: proc(
	sources: []Theme_Source_Model,
	support := THEME_COMPILER_SUPPORT,
	allocator := context.allocator,
) -> Theme_Compile_Output {
	tokens := make([dynamic]Effective_Token, 0, allocator=allocator)
	core_roles := make([dynamic]Effective_Core_Role, 0, allocator=allocator)
	extension_roles := make([dynamic]Effective_Extension_Role, 0, allocator=allocator)
	diagnostics := make([dynamic]Theme_Diagnostic, 0, allocator=allocator)
	defer delete(tokens)
	defer delete(core_roles)
	defer delete(extension_roles)
	defer delete(diagnostics)
	defer theme_discard_diagnostic_payloads(&diagnostics, allocator)
	effective_contract := Theme_Contract_Version{major=support.contract_major}

	for source, layer in sources {
		if source.metadata.schema_version != support.schema_version {
			diagnostic := theme_diagnostic(.Unsupported_Schema_Version, source.metadata.span)
			diagnostic.expected_schema_version = support.schema_version
			diagnostic.actual_schema_version = source.metadata.schema_version
			append(&diagnostics, diagnostic)
		}
		if source.metadata.contract.major != support.contract_major || source.metadata.contract.minor > support.contract_minor {
			diagnostic := theme_diagnostic(.Unsupported_Contract_Version, source.metadata.span)
			diagnostic.supported_contract_major = support.contract_major
			diagnostic.supported_contract_minor = support.contract_minor
			diagnostic.actual_contract = source.metadata.contract
			append(&diagnostics, diagnostic)
		} else if source.metadata.contract.minor > effective_contract.minor {
			effective_contract.minor = source.metadata.contract.minor
		}
		for definition in source.tokens {
			if definition.name == "" {
				append(&diagnostics, theme_diagnostic(.Invalid_Token_Name, definition.span))
				continue
			}
			if definition.kind != .Color && definition.kind != .Length {
				append(&diagnostics, theme_diagnostic(.Invalid_Token_Kind, definition.span))
				continue
			}
			index := effective_token_index_linear(tokens[:], definition.name)
			if index >= 0 {
				if tokens[index].layer == layer {
					append(&diagnostics, theme_diagnostic(.Duplicate_Token, definition.span))
					continue
				}
				if tokens[index].definition.kind != definition.kind {
					diagnostic := theme_diagnostic(.Token_Type_Changed, definition.span)
					diagnostic.expected_kind = tokens[index].definition.kind
					diagnostic.actual_kind = definition.kind
					append(&diagnostics, diagnostic)
					continue
				}
				tokens[index] = Effective_Token{definition=definition, layer=layer}
			} else {
				append(&tokens, Effective_Token{definition=definition, layer=layer})
			}
		}

		for binding in source.core_roles {
			if binding.role >= .Count {
				append(&diagnostics, theme_diagnostic(.Invalid_Core_Role, binding.span))
				continue
			}
			index := effective_core_role_index(core_roles[:], binding.role)
			if index >= 0 {
				if core_roles[index].layer == layer {
					append(&diagnostics, theme_diagnostic(.Duplicate_Core_Role, binding.span))
					continue
				}
				core_roles[index] = Effective_Core_Role{binding=binding, layer=layer}
			} else {
				append(&core_roles, Effective_Core_Role{binding=binding, layer=layer})
			}
		}

		for declaration in source.extension_roles {
			if !theme_extension_role_name_is_valid(declaration.name) {
				append(&diagnostics, theme_diagnostic(.Invalid_Extension_Role_Namespace, declaration.span))
				continue
			}
			if declaration.kind != .Color && declaration.kind != .Length {
				append(&diagnostics, theme_diagnostic(.Invalid_Token_Kind, declaration.span))
				continue
			}
			index := effective_extension_role_index(extension_roles[:], declaration.name)
			if index >= 0 {
				if extension_roles[index].layer == layer {
					append(&diagnostics, theme_diagnostic(.Duplicate_Extension_Role, declaration.span))
					continue
				}
				if extension_roles[index].declaration.kind != declaration.kind {
					diagnostic := theme_diagnostic(.Extension_Role_Type_Changed, declaration.span)
					diagnostic.expected_kind = extension_roles[index].declaration.kind
					diagnostic.actual_kind = declaration.kind
					append(&diagnostics, diagnostic)
					continue
				}
				extension_roles[index] = Effective_Extension_Role{declaration=declaration, layer=layer}
			} else {
				append(&extension_roles, Effective_Extension_Role{declaration=declaration, layer=layer})
			}
		}
	}

	theme_sort_effective_tokens(&tokens)
	stack := make([dynamic]int, 0, len(tokens), allocator=allocator)
		defer delete(stack)
	for index in 0..<len(tokens) {
		if !theme_resolve_token(index, tokens[:], &stack, &diagnostics, allocator) {
			continue
		}
	}

	// Role binding is intentionally a second pass over the final merged graph.
	// It can therefore refer to tokens overridden by a derived theme.
	for entry in core_roles {
		token_index := effective_token_index(tokens[:], entry.binding.token)
		if token_index < 0 {
			append(&diagnostics, theme_diagnostic(.Core_Role_Token_Not_Found, entry.binding.span))
			continue
		}
		if tokens[token_index].definition.kind != .Color {
			diagnostic := theme_diagnostic(.Core_Role_Token_Type_Mismatch, entry.binding.span)
			diagnostic.expected_kind = .Color
			diagnostic.actual_kind = tokens[token_index].definition.kind
			append(&diagnostics, diagnostic)
		}
	}
	for entry in extension_roles {
		token_index := effective_token_index(tokens[:], entry.declaration.token)
		if token_index < 0 {
			append(&diagnostics, theme_diagnostic(.Extension_Role_Token_Not_Found, entry.declaration.span))
			continue
		}
		if tokens[token_index].definition.kind != entry.declaration.kind {
			diagnostic := theme_diagnostic(.Extension_Role_Token_Type_Mismatch, entry.declaration.span)
			diagnostic.expected_kind = entry.declaration.kind
			diagnostic.actual_kind = tokens[token_index].definition.kind
			append(&diagnostics, diagnostic)
		}
	}
	theme_sort_effective_extension_roles(&extension_roles)
	theme_assign_extension_role_ids(&extension_roles, &diagnostics)

	if len(diagnostics) > 0 {
		theme_sort_diagnostics(&diagnostics)
		output_diagnostics := make([]Theme_Diagnostic, len(diagnostics), allocator)
		for diagnostic, index in diagnostics {
			output_diagnostics[index] = theme_copy_diagnostic(diagnostic, allocator)
		}
		return Theme_Compile_Output{diagnostics=output_diagnostics}
	}

	color_count, length_count := 0, 0
	for token in tokens {
		if token.definition.kind == .Color { color_count += 1 } else { length_count += 1 }
	}
	compiled := Compiled_Theme{
		contract=effective_contract,
		colors=make([]Theme_Color, color_count, allocator),
		lengths=make([]Theme_Length, length_count, allocator),
	}
	color_token_next, length_token_next := 0, 0
	for index in 0..<len(tokens) {
		token := &tokens[index]
		if token.definition.kind == .Color {
			color_token_next += 1
			token.color_id = Color_Token_ID(u32(color_token_next))
			compiled.colors[int(u32(token.color_id))-1] = token.color
		} else {
			length_token_next += 1
			token.length_id = Length_Token_ID(u32(length_token_next))
			compiled.lengths[int(u32(token.length_id))-1] = token.length
		}
	}
	for entry in core_roles {
		token_index := effective_token_index(tokens[:], entry.binding.token)
		compiled.core_color_roles[int(entry.binding.role)] = tokens[token_index].color_id
	}

	color_roles_count, length_roles_count := 0, 0
	for entry in extension_roles {
		if entry.declaration.kind == .Color { color_roles_count += 1 } else { length_roles_count += 1 }
	}
	compiled.extension_color_roles = make([]Compiled_Extension_Color_Role, color_roles_count, allocator)
	compiled.extension_length_roles = make([]Compiled_Extension_Length_Role, length_roles_count, allocator)
	color_role_slot, length_role_slot := 0, 0
	for index in 0..<len(extension_roles) {
		entry := &extension_roles[index]
		token_index := effective_token_index(tokens[:], entry.declaration.token)
		if entry.declaration.kind == .Color {
			color_role_slot += 1
			compiled.extension_color_roles[color_role_slot-1] = Compiled_Extension_Color_Role{
				id=entry.color_id,
				token=tokens[token_index].color_id,
			}
		} else {
			length_role_slot += 1
			compiled.extension_length_roles[length_role_slot-1] = Compiled_Extension_Length_Role{
				id=entry.length_id,
				token=tokens[token_index].length_id,
			}
		}
	}

	debug := theme_build_debug_metadata(tokens[:], extension_roles[:], allocator)
	compiled.content_signature = theme_content_signature(compiled, debug)
	return Theme_Compile_Output{theme=compiled, debug=debug, ok=true}
}

theme_resolve_token :: proc(
	index: int,
	tokens: []Effective_Token,
	stack: ^[dynamic]int,
	diagnostics: ^[dynamic]Theme_Diagnostic,
	allocator: mem.Allocator,
) -> bool {
	token := &tokens[index]
	switch token.state {
	case .Resolved:
		return true
	case .Failed:
		return false
	case .Visiting:
		cycle_start := 0
		for token_index, stack_index in stack {
			if token_index == index { cycle_start = stack_index; break }
		}
		cycle := make([]string, len(stack)-cycle_start+1, allocator)
		for stack_index in cycle_start..<len(stack) {
			cycle[stack_index-cycle_start] = tokens[stack[stack_index]].definition.name
		}
		cycle[len(cycle)-1] = token.definition.name
		diagnostic := theme_diagnostic(.Alias_Cycle, token.definition.span)
		diagnostic.symbol_path = cycle
		append(diagnostics, diagnostic)
		return false
	case .Unvisited:
	}

	token.state = .Visiting
	append(stack, index)
	defer pop(stack)

	switch value in token.definition.value {
	case Theme_Color:
		if token.definition.kind != .Color {
			append(diagnostics, theme_diagnostic(.Token_Value_Type_Mismatch, token.definition.span))
			token.state = .Failed
			return false
		}
		if !theme_color_is_valid(value) {
			append(diagnostics, theme_diagnostic(.Invalid_Color, token.definition.span))
			token.state = .Failed
			return false
		}
		token.color = value
	case Theme_Length:
		if token.definition.kind != .Length {
			append(diagnostics, theme_diagnostic(.Token_Value_Type_Mismatch, token.definition.span))
			token.state = .Failed
			return false
		}
		if !theme_length_is_valid(value) {
			append(diagnostics, theme_diagnostic(.Invalid_Length, token.definition.span))
			token.state = .Failed
			return false
		}
		token.length = value
	case Theme_Alias:
		target_index := effective_token_index(tokens, value.target)
		if target_index < 0 {
			append(diagnostics, theme_diagnostic(.Unknown_Alias, token.definition.span))
			token.state = .Failed
			return false
		}
		if tokens[target_index].definition.kind != token.definition.kind {
			diagnostic := theme_diagnostic(.Alias_Type_Mismatch, token.definition.span)
			diagnostic.expected_kind = token.definition.kind
			diagnostic.actual_kind = tokens[target_index].definition.kind
			append(diagnostics, diagnostic)
			token.state = .Failed
			return false
		}
		if !theme_resolve_token(target_index, tokens, stack, diagnostics, allocator) {
			token.state = .Failed
			return false
		}
		token.color = tokens[target_index].color
		token.length = tokens[target_index].length
	}

	token.state = .Resolved
	return true
}

theme_build_debug_metadata :: proc(
	tokens: []Effective_Token,
	extension_roles: []Effective_Extension_Role,
	allocator: mem.Allocator,
) -> Theme_Debug_Metadata {
	debug := Theme_Debug_Metadata{
		tokens=make([]Token_Provenance, len(tokens), allocator),
		extension_roles=make([]Extension_Role_Provenance, len(extension_roles), allocator),
	}
	for token, index in tokens {
		name := theme_clone_string(token.definition.name, allocator)
		span := token.definition.span
		span.path = theme_clone_string(span.path, allocator)
		alias_target := ""
		if alias, ok := token.definition.value.(Theme_Alias); ok {
			alias_target = theme_clone_string(alias.target, allocator)
		}
		id: u32
		if token.definition.kind == .Color { id = u32(token.color_id) } else { id = u32(token.length_id) }
		debug.tokens[index] = Token_Provenance{
			id=id,
			name=name,
			kind=token.definition.kind,
			span=span,
			alias_target=alias_target,
		}
	}
	for entry, index in extension_roles {
		name := theme_clone_string(entry.declaration.name, allocator)
		span := entry.declaration.span
		span.path = theme_clone_string(span.path, allocator)
		debug.extension_roles[index] = Extension_Role_Provenance{
			color_id=entry.color_id,
			length_id=entry.length_id,
			name=name,
			kind=entry.declaration.kind,
			span=span,
		}
	}
	return debug
}

theme_content_signature :: proc(theme: Compiled_Theme, debug: Theme_Debug_Metadata) -> u64 {
	h: u64 = 14695981039346656037
	h = theme_hash_u64(h, u64(theme.contract.major))
	h = theme_hash_u64(h, u64(theme.contract.minor))
	for color, index in theme.colors {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_hash_u64(h, u64(transmute(u32)color.r))
		h = theme_hash_u64(h, u64(transmute(u32)color.g))
		h = theme_hash_u64(h, u64(transmute(u32)color.b))
		h = theme_hash_u64(h, u64(transmute(u32)color.a))
	}
	for length, index in theme.lengths {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_hash_u64(h, u64(transmute(u32)f32(length)))
	}
	for token, role in theme.core_color_roles {
		h = theme_hash_u64(h, u64(role))
		h = theme_hash_u64(h, u64(token))
	}
	for role in debug.extension_roles {
		h = theme_hash_string(h, role.name)
		h = theme_hash_u64(h, u64(role.color_id))
		h = theme_hash_u64(h, u64(role.length_id))
		h = theme_hash_u64(h, u64(role.kind))
	}
	for token in debug.tokens {
		h = theme_hash_string(h, token.name)
		h = theme_hash_u64(h, u64(token.id))
		h = theme_hash_u64(h, u64(token.kind))
	}
	for binding in theme.extension_color_roles {
		h = theme_hash_u64(h, u64(binding.id))
		h = theme_hash_u64(h, u64(binding.token))
	}
	for binding in theme.extension_length_roles {
		h = theme_hash_u64(h, u64(binding.id))
		h = theme_hash_u64(h, u64(binding.token))
	}
	return h
}

theme_hash_u64 :: proc(h: u64, value: u64) -> u64 {
	hash := h
	hash = (hash ~ (value & 0xFF)) * 1099511628211
	hash = (hash ~ ((value >> 8) & 0xFF)) * 1099511628211
	hash = (hash ~ ((value >> 16) & 0xFF)) * 1099511628211
	hash = (hash ~ ((value >> 24) & 0xFF)) * 1099511628211
	hash = (hash ~ ((value >> 32) & 0xFF)) * 1099511628211
	hash = (hash ~ ((value >> 40) & 0xFF)) * 1099511628211
	hash = (hash ~ ((value >> 48) & 0xFF)) * 1099511628211
	hash = (hash ~ ((value >> 56) & 0xFF)) * 1099511628211
	return hash
}

theme_hash_string :: proc(h: u64, value: string) -> u64 {
	hash := h
	for character in value { hash = (hash ~ u64(character)) * 1099511628211 }
	return (hash ~ u64(0xFF)) * 1099511628211
}

theme_output_destroy :: proc(output: ^Theme_Compile_Output, allocator := context.allocator) {
	if output == nil { return }
	delete(output.theme.colors, allocator)
	delete(output.theme.lengths, allocator)
	delete(output.theme.extension_color_roles, allocator)
	delete(output.theme.extension_length_roles, allocator)
	for token in output.debug.tokens {
		delete(token.name, allocator)
		delete(token.span.path, allocator)
		delete(token.alias_target, allocator)
	}
	for role in output.debug.extension_roles {
		delete(role.name, allocator)
		delete(role.span.path, allocator)
	}
	delete(output.debug.tokens, allocator)
	delete(output.debug.extension_roles, allocator)
	for diagnostic in output.diagnostics {
		delete(diagnostic.path, allocator)
		delete(diagnostic.related_name, allocator)
		for symbol in diagnostic.symbol_path { delete(symbol, allocator) }
		delete(diagnostic.symbol_path, allocator)
	}
	delete(output.diagnostics, allocator)
	output^ = Theme_Compile_Output{}
}

theme_discard_diagnostic_payloads :: proc(diagnostics: ^[dynamic]Theme_Diagnostic, allocator: mem.Allocator) {
	for diagnostic in diagnostics {
		delete(diagnostic.symbol_path, allocator)
	}
}

theme_diagnostic :: proc(code: Diagnostic_Code, span: Source_Span) -> Theme_Diagnostic {
	return Theme_Diagnostic{code=code, severity=.Error, path=span.path, span=span}
}

theme_copy_diagnostic :: proc(diagnostic: Theme_Diagnostic, allocator: mem.Allocator) -> Theme_Diagnostic {
	copy := diagnostic
	copy.path = theme_clone_string(diagnostic.path, allocator)
	copy.span.path = copy.path
	copy.related_name = theme_clone_string(diagnostic.related_name, allocator)
	if len(diagnostic.symbol_path) > 0 {
		copy.symbol_path = make([]string, len(diagnostic.symbol_path), allocator)
		for symbol, index in diagnostic.symbol_path {
			copy.symbol_path[index] = theme_clone_string(symbol, allocator)
		}
	}
	return copy
}

theme_clone_string :: proc(value: string, allocator: mem.Allocator) -> string {
	owned := make([]byte, len(value), allocator)
	copy(owned, value)
	return string(owned)
}

theme_color_is_valid :: proc(color: Theme_Color) -> bool {
	return theme_unit_float_is_valid(color.r) && theme_unit_float_is_valid(color.g) &&
	       theme_unit_float_is_valid(color.b) && color.a == color.a && color.a > 0 && color.a <= 1
}

theme_unit_float_is_valid :: proc(value: f32) -> bool {
	return value == value && value >= 0 && value <= 1
}

theme_length_is_valid :: proc(value: Theme_Length) -> bool {
	f := f32(value)
	return f == f && f >= 0 && f <= THEME_LENGTH_MAX_LOGICAL_UNITS
}

theme_extension_role_name_is_valid :: proc(name: string) -> bool {
	if len(name) < 7 { return false }
	segments := 0
	segment_length := 0
	for character in name {
		if character == '.' {
			if segment_length == 0 { return false }
			segments += 1
			segment_length = 0
			continue
		}
		if !((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '_' || character == '-') {
			return false
		}
		segment_length += 1
	}
	if segment_length == 0 { return false }
	segments += 1
	if strings.has_prefix(name, "app.") { return segments >= 3 }
	if strings.has_prefix(name, "vendor.") { return segments >= 4 }
	return false
}

theme_extension_role_parts :: proc(name: string) -> (namespace, short_name: string, ok: bool) {
	first_dot, second_dot := -1, -1
	for index := 0; index < len(name); index += 1 {
		if name[index] != '.' { continue }
		if first_dot < 0 { first_dot = index } else { second_dot = index; break }
	}
	if first_dot <= 0 || second_dot <= first_dot+1 || second_dot >= len(name)-1 { return }
	return name[:second_dot], name[second_dot+1:], true
}

theme_extension_role_hash :: proc(namespace, name: string, type_tag: u64) -> u64 {
	// Mirrors runtime/style_tokens.odin's style_extension_role_hash exactly.
	h: u64 = 1469598103934665603
	h = theme_hash_mix(h, type_tag)
	for index := 0; index < len(namespace); index += 1 { h = theme_hash_mix(h, u64(namespace[index])) }
	h = theme_hash_mix(h, u64('.'))
	for index := 0; index < len(name); index += 1 { h = theme_hash_mix(h, u64(name[index])) }
	if h == 0 { return 1 }
	return h
}

theme_assign_extension_role_ids :: proc(
	roles: ^[dynamic]Effective_Extension_Role,
	diagnostics: ^[dynamic]Theme_Diagnostic,
) {
	for index in 0..<len(roles) {
		entry := &roles[index]
		namespace, short_name, ok := theme_extension_role_parts(entry.declaration.name)
		if !ok { continue }
		if entry.declaration.kind == .Color {
			entry.color_id = Extension_Color_Role_ID(theme_extension_role_hash(namespace, short_name, 1))
		} else {
			entry.length_id = Extension_Length_Role_ID(theme_extension_role_hash(namespace, short_name, 2))
		}
		for previous_index in 0..<index {
			previous := roles[previous_index]
			if previous.declaration.kind != entry.declaration.kind || previous.declaration.name == entry.declaration.name { continue }
			collides := entry.declaration.kind == .Color && previous.color_id == entry.color_id ||
				entry.declaration.kind == .Length && previous.length_id == entry.length_id
			if collides {
				diagnostic := theme_diagnostic(.Extension_Role_Hash_Collision, entry.declaration.span)
				diagnostic.related_name = previous.declaration.name
				append(diagnostics, diagnostic)
			}
		}
	}
}

theme_hash_mix :: proc(h, value: u64) -> u64 {
	return (h ~ value) * 1099511628211
}

effective_token_index :: proc(tokens: []Effective_Token, name: string) -> int {
	low, high := 0, len(tokens)
	for low < high {
		middle := low + (high-low)/2
		candidate := tokens[middle].definition.name
		if candidate == name { return middle }
		if candidate < name { low = middle+1 } else { high = middle }
	}
	return -1
}

effective_token_index_linear :: proc(tokens: []Effective_Token, name: string) -> int {
	for token, index in tokens { if token.definition.name == name { return index } }
	return -1
}

effective_core_role_index :: proc(roles: []Effective_Core_Role, role: Core_Color_Role) -> int {
	for entry, index in roles { if entry.binding.role == role { return index } }
	return -1
}

effective_extension_role_index :: proc(roles: []Effective_Extension_Role, name: string) -> int {
	for entry, index in roles { if entry.declaration.name == name { return index } }
	return -1
}

theme_sort_effective_tokens :: proc(tokens: ^[dynamic]Effective_Token) {
	for index in 1..<len(tokens) {
		cursor := index
		for cursor > 0 && tokens[cursor].definition.name < tokens[cursor-1].definition.name {
			tokens[cursor], tokens[cursor-1] = tokens[cursor-1], tokens[cursor]
			cursor -= 1
		}
	}
}

theme_sort_effective_extension_roles :: proc(roles: ^[dynamic]Effective_Extension_Role) {
	for index in 1..<len(roles) {
		cursor := index
		for cursor > 0 && roles[cursor].declaration.name < roles[cursor-1].declaration.name {
			roles[cursor], roles[cursor-1] = roles[cursor-1], roles[cursor]
			cursor -= 1
		}
	}
}

theme_sort_diagnostics :: proc(diagnostics: ^[dynamic]Theme_Diagnostic) {
	for index in 1..<len(diagnostics) {
		cursor := index
		for cursor > 0 && theme_diagnostic_less(diagnostics[cursor], diagnostics[cursor-1]) {
			diagnostics[cursor], diagnostics[cursor-1] = diagnostics[cursor-1], diagnostics[cursor]
			cursor -= 1
		}
	}
}

theme_diagnostic_less :: proc(a, b: Theme_Diagnostic) -> bool {
	if a.path != b.path { return a.path < b.path }
	if a.span.start_offset != b.span.start_offset { return a.span.start_offset < b.span.start_offset }
	if a.span.end_offset != b.span.end_offset { return a.span.end_offset < b.span.end_offset }
	if a.span.line != b.span.line { return a.span.line < b.span.line }
	if a.span.column != b.span.column { return a.span.column < b.span.column }
	if a.code != b.code { return a.code < b.code }
	if a.severity != b.severity { return a.severity < b.severity }
	if a.expected_kind != b.expected_kind { return a.expected_kind < b.expected_kind }
	if a.actual_kind != b.actual_kind { return a.actual_kind < b.actual_kind }
	if a.expected_schema_version != b.expected_schema_version { return a.expected_schema_version < b.expected_schema_version }
	if a.actual_schema_version != b.actual_schema_version { return a.actual_schema_version < b.actual_schema_version }
	if a.supported_contract_major != b.supported_contract_major { return a.supported_contract_major < b.supported_contract_major }
	if a.supported_contract_minor != b.supported_contract_minor { return a.supported_contract_minor < b.supported_contract_minor }
	if a.actual_contract.major != b.actual_contract.major { return a.actual_contract.major < b.actual_contract.major }
	if a.actual_contract.minor != b.actual_contract.minor { return a.actual_contract.minor < b.actual_contract.minor }
	if a.related_name != b.related_name { return a.related_name < b.related_name }
	if len(a.symbol_path) != len(b.symbol_path) { return len(a.symbol_path) < len(b.symbol_path) }
	for index in 0..<len(a.symbol_path) {
		if a.symbol_path[index] != b.symbol_path[index] { return a.symbol_path[index] < b.symbol_path[index] }
	}
	return false
}
