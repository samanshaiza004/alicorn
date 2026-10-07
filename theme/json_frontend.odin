package theme

import "core:encoding/json"
import "core:math"
import "core:mem"
import "core:strconv"
import "core:strings"

// This frontend accepts a deliberately small, strict-JSON DTCG-inspired
// format. It is an authoring/import format only; the returned source model is
// format-neutral and runtime code never parses files.
//
// {
//   "schema": 1,
//   "contract": "0.2",
//   "extends": "alicorn.base", // optional
//   "tokens": {
//     "color.ink": {"$type":"color", "$value":{
//       "colorSpace":"srgb", "components":[0.08,0.1,0.14], "alpha":1
//     }},
//     "space.small": {"$type":"dimension", "$value":{"value":8,"unit":"px"}},
//     "text.primary": {"$type":"color", "$value":"{color.ink}"}
//   },
//   "roles": {
//     "core": {"text":"{text.primary}"},
//     "extensions": {"app.editor.gutter":{
//       "$type":"dimension", "$value":"{space.small}"
//     }}
//   },
//   "materials": {"app.editor.paper":{"kind":"analytic_relief","bevel_width":1}},
//   "recipes": {"button":{"tab":{"selected_indicator_role":"accent"}}}
// }
//
// Schema must match the current schema exactly; the compiler accepts the
// current major contract and earlier compatible minors (currently 0.2).
// Contract values use `major.minor` spelling. Colors are DTCG
// encoded sRGB components in [0,1], decoded with the standard piecewise sRGB
// EOTF into linear-sRGB Theme_Color channels. The runtime adapter copies these
// channels unchanged; Alicorn's GPU solid path forwards them unchanged, while
// output transfer remains the renderer/swapchain contract. No P3/OKLCH input
// or conversion is implemented here.
// Dimensions accept only unit `px`, mapped one-to-one to Alicorn logical
// units (no DPI conversion). Token values are literals or `{token.name}`
// aliases. Core role keys are lowercase snake_case Core_Color_Role names.
// Extension role declarations require app.* or vendor.* names and an explicit
// `$type`; their `$value` must be a token alias. Unknown fields, color spaces,
// units, coercions, JSON5 syntax, and other DTCG value forms are rejected.

Theme_JSON_Diagnostic_Code :: enum u8 {
	Syntax,
	Duplicate_Key,
	Duplicate_Token_Declaration,
	Duplicate_Role_Declaration,
	Missing_Field,
	Unsupported_Field,
	Unsupported_Value,
	Invalid_Schema,
	Invalid_Contract,
	Invalid_Core_Role,
	Invalid_Extension_Role,
	Invalid_Token_Type,
	Invalid_Alias,
	Invalid_Color,
	Invalid_Length,
	Invalid_Material,
	Invalid_Recipe,
}

Theme_JSON_Diagnostic :: struct {
	code:    Theme_JSON_Diagnostic_Code,
	span:    Source_Span,
	message: string,
	field:   string,
}

Theme_JSON_Output :: struct {
	source:          Theme_Source_Model,
	schema_version:  u32,
	contract:        Theme_Contract_Version,
	extends:         string,
	// The output owns this slice. Diagnostic messages and field names are
	// references to static literals; every span.path borrows source_path.
	diagnostics:     []Theme_JSON_Diagnostic,
	source_path:     string,
	has_source:      bool,
	ok:              bool,
}

JSON_Node_Kind :: enum u8 {
	Invalid,
	Null,
	Boolean,
	Number,
	String,
	Object,
	Array,
}

JSON_Node :: struct {
	kind:          JSON_Node_Kind,
	span:          Source_Span,
	text:          string,
	number:        f64,
	integer:       bool,
	boolean:       bool,
	members:       []JSON_Member,
	elements:      []JSON_Node,
}

JSON_Member :: struct {
	key:      string,
	key_span: Source_Span,
	value:    JSON_Node,
}

JSON_Object_Context :: enum u8 {
	Generic,
	Root,
	Tokens,
	Roles,
	Core_Roles,
	Extension_Roles,
}

JSON_Parser :: struct {
	tokenizer:   json.Tokenizer,
	token:       json.Token,
	token_error: json.Error,
	input:       string,
	path:        string,
	allocator:   mem.Allocator,
	diagnostics: [dynamic]Theme_JSON_Diagnostic,
	depth:       u32,
	fatal:       bool,
}

THEME_JSON_MAX_NESTING :: u32(128)

theme_json_parse :: proc(
	input: string,
	path := "<theme>",
	allocator := context.allocator,
) -> Theme_JSON_Output {
	parser := JSON_Parser{
		tokenizer=json.make_tokenizer(input, .JSON, parse_integers=true),
		input=input,
		path=theme_json_clone(path, allocator),
		allocator=allocator,
		diagnostics=make([dynamic]Theme_JSON_Diagnostic, 0, allocator=allocator),
	}
	theme_json_advance(&parser)

	root := theme_json_parse_value(&parser, .Root)
	if !parser.fatal && parser.token.kind != .EOF {
		theme_json_syntax(&parser, parser.token, "unexpected trailing data after the root value")
	}

	output := Theme_JSON_Output{source_path=parser.path}
	if root.kind == .Object && !parser.fatal {
		theme_json_map_root(&parser, root, &output)
	} else if !parser.fatal {
		theme_json_diagnostic(&parser, .Unsupported_Value, root.span, "theme document root must be an object")
	}

	output.diagnostics = parser.diagnostics[:]
	theme_json_sort_diagnostics(&output.diagnostics)
	output.ok = !parser.fatal && output.has_source && len(output.diagnostics) == 0 && len(output.source.tokens) > 0
	theme_json_node_destroy(root, allocator)
	return output
}

theme_json_output_destroy :: proc(output: ^Theme_JSON_Output, allocator := context.allocator) {
	if output == nil { return }
	for definition in output.source.tokens {
		delete(definition.name, allocator)
		if alias, ok := definition.value.(Theme_Alias); ok {
			delete(alias.target, allocator)
		}
	}
	for binding in output.source.core_roles {
		delete(binding.token, allocator)
	}
	for declaration in output.source.extension_roles {
		delete(declaration.name, allocator)
		delete(declaration.token, allocator)
	}
	for material in output.source.materials { delete(material.name, allocator) }
	delete(output.source.tokens, allocator)
	delete(output.source.core_roles, allocator)
	delete(output.source.extension_roles, allocator)
	delete(output.source.materials, allocator)
	delete(output.source.button_recipes, allocator)
	delete(output.extends, allocator)
	delete(output.source_path, allocator)
	delete(output.diagnostics, allocator)
	output^ = Theme_JSON_Output{}
}

theme_json_advance :: proc(parser: ^JSON_Parser) {
	parser.token, parser.token_error = json.get_token(&parser.tokenizer)
	if parser.token_error != nil && parser.token_error != .EOF {
		theme_json_syntax(parser, parser.token, "invalid strict JSON token")
	} else if parser.token.kind == .EOF && parser.token.offset < len(parser.input) {
		// Odin's tokenizer treats NUL as EOF. Reject it and any ignored suffix
		// rather than silently truncating a supposedly strict JSON document.
		theme_json_syntax(parser, parser.token, "NUL is not valid strict JSON data")
	}
}

theme_json_parse_value :: proc(parser: ^JSON_Parser, object_context: JSON_Object_Context) -> JSON_Node {
	token := parser.token
	if parser.fatal { return JSON_Node{} }
	#partial switch token.kind {
	case .Null:
		parser.token = token
		theme_json_advance(parser)
		return JSON_Node{kind=.Null, span=theme_json_token_span(token)}
	case .True, .False:
		value := token.kind == .True
		theme_json_advance(parser)
		return JSON_Node{kind=.Boolean, boolean=value, span=theme_json_token_span(token)}
	case .Integer, .Float:
		integer := token.kind == .Integer
		value, valid := strconv.parse_f64(token.text)
		theme_json_advance(parser)
		if !valid {
			theme_json_diagnostic(parser, .Syntax, theme_json_token_span(token), "invalid JSON number")
			return JSON_Node{kind=.Invalid, span=theme_json_token_span(token)}
		}
		return JSON_Node{kind=.Number, number=value, integer=integer, span=theme_json_token_span(token)}
	case .String:
		value, err := json.unquote_string(token, .JSON, parser.allocator)
		theme_json_advance(parser)
		if err != nil {
			theme_json_diagnostic(parser, .Syntax, theme_json_token_span(token), "invalid JSON string")
			return JSON_Node{kind=.Invalid, span=theme_json_token_span(token)}
		}
		return JSON_Node{kind=.String, text=value, span=theme_json_token_span(token)}
	case .Open_Brace:
		if parser.depth >= THEME_JSON_MAX_NESTING {
			theme_json_syntax(parser, token, "JSON nesting exceeds the supported limit")
			return JSON_Node{kind=.Invalid, span=theme_json_token_span(token)}
		}
		parser.depth += 1
		node := theme_json_parse_object(parser, object_context)
		parser.depth -= 1
		return node
	case .Open_Bracket:
		if parser.depth >= THEME_JSON_MAX_NESTING {
			theme_json_syntax(parser, token, "JSON nesting exceeds the supported limit")
			return JSON_Node{kind=.Invalid, span=theme_json_token_span(token)}
		}
		parser.depth += 1
		node := theme_json_parse_array(parser)
		parser.depth -= 1
		return node
	case:
		theme_json_syntax(parser, token, "expected a JSON value")
		return JSON_Node{kind=.Invalid, span=theme_json_token_span(token)}
	}
}

theme_json_parse_object :: proc(parser: ^JSON_Parser, object_context: JSON_Object_Context) -> JSON_Node {
	open := parser.token
	node := JSON_Node{kind=.Object, span=theme_json_token_span(open)}
	parser.token = open
	theme_json_advance(parser)
	members := make([dynamic]JSON_Member, 0, allocator=parser.allocator)
	transferred := false
	defer if !transferred { theme_json_members_destroy(members[:], parser.allocator) }

	if parser.token.kind == .Close_Brace {
		close := parser.token
		node.span.end_offset = theme_json_token_span(close).end_offset
		theme_json_advance(parser)
		node.members = members[:]
		transferred = true
		return node
	}

	for !parser.fatal {
		if parser.token.kind != .String {
			theme_json_syntax(parser, parser.token, "object member names must be quoted strings")
			break
		}
		key_token := parser.token
		key, key_error := json.unquote_string(key_token, .JSON, parser.allocator)
		key_span := theme_json_token_span(key_token)
		theme_json_advance(parser)
		if key_error != nil {
			delete(key, parser.allocator)
			theme_json_diagnostic(parser, .Syntax, key_span, "invalid object member name")
			break
		}
		if parser.token.kind != .Colon {
			delete(key, parser.allocator)
			theme_json_syntax(parser, parser.token, "expected ':' after object member name")
			break
		}
		theme_json_advance(parser)

		child_context := theme_json_child_context(object_context, key)
		value := theme_json_parse_value(parser, child_context)
		duplicate := false
		for member in members {
			if member.key == key {
				duplicate = true
				break
			}
		}
		if duplicate {
			code := theme_json_duplicate_code(object_context)
			message := "duplicate JSON object key"
			if code == .Duplicate_Token_Declaration { message = "duplicate token declaration" }
			if code == .Duplicate_Role_Declaration { message = "duplicate role declaration" }
			theme_json_diagnostic(parser, code, key_span, message)
			delete(key, parser.allocator)
			theme_json_node_destroy(value, parser.allocator)
		} else {
			append(&members, JSON_Member{key=key, key_span=key_span, value=value})
		}

		if parser.fatal { break }
		if parser.token.kind == .Close_Brace {
			close := parser.token
			node.span.end_offset = theme_json_token_span(close).end_offset
			theme_json_advance(parser)
			node.members = members[:]
			transferred = true
			return node
		}
		if parser.token.kind != .Comma {
			theme_json_syntax(parser, parser.token, "expected ',' or '}' after object member")
			break
		}
		comma := parser.token
		theme_json_advance(parser)
		if parser.token.kind == .Close_Brace {
			theme_json_syntax(parser, parser.token, "trailing commas are not allowed in strict JSON")
			break
		}
		_ = comma
	}

	return node
}

theme_json_parse_array :: proc(parser: ^JSON_Parser) -> JSON_Node {
	open := parser.token
	node := JSON_Node{kind=.Array, span=theme_json_token_span(open)}
	theme_json_advance(parser)
	elements := make([dynamic]JSON_Node, 0, allocator=parser.allocator)
	transferred := false
	defer if !transferred { theme_json_elements_destroy(elements[:], parser.allocator) }

	if parser.token.kind == .Close_Bracket {
		node.span.end_offset = theme_json_token_span(parser.token).end_offset
		theme_json_advance(parser)
		node.elements = elements[:]
		transferred = true
		return node
	}
	for !parser.fatal {
		append(&elements, theme_json_parse_value(parser, .Generic))
		if parser.fatal { break }
		if parser.token.kind == .Close_Bracket {
			node.span.end_offset = theme_json_token_span(parser.token).end_offset
			theme_json_advance(parser)
			node.elements = elements[:]
			transferred = true
			return node
		}
		if parser.token.kind != .Comma {
			theme_json_syntax(parser, parser.token, "expected ',' or ']' after array element")
			break
		}
		theme_json_advance(parser)
		if parser.token.kind == .Close_Bracket {
			theme_json_syntax(parser, parser.token, "trailing commas are not allowed in strict JSON")
			break
		}
	}
	return node
}

theme_json_child_context :: proc(parent: JSON_Object_Context, key: string) -> JSON_Object_Context {
	#partial switch parent {
	case .Root:
		if key == "tokens" { return .Tokens }
		if key == "roles" { return .Roles }
	case .Roles:
		if key == "core" { return .Core_Roles }
		if key == "extensions" { return .Extension_Roles }
	}
	return .Generic
}

theme_json_duplicate_code :: proc(object_context: JSON_Object_Context) -> Theme_JSON_Diagnostic_Code {
	#partial switch object_context {
	case .Tokens: return .Duplicate_Token_Declaration
	case .Core_Roles, .Extension_Roles: return .Duplicate_Role_Declaration
	case: return .Duplicate_Key
	}
}

theme_json_map_root :: proc(parser: ^JSON_Parser, root: JSON_Node, output: ^Theme_JSON_Output) {
	schema, has_schema := theme_json_member(root, "schema")
	contract, has_contract := theme_json_member(root, "contract")
	tokens, has_tokens := theme_json_member(root, "tokens")
	roles, has_roles := theme_json_member(root, "roles")
	materials, has_materials := theme_json_member(root, "materials")
	recipes, has_recipes := theme_json_member(root, "recipes")
	extends, has_extends := theme_json_member(root, "extends")

	version_valid := true
	if !has_schema { theme_json_missing(parser, root.span, "schema"); version_valid = false }
	else if schema.kind != .Number || !schema.integer || schema.number != f64(THEME_SOURCE_SCHEMA_VERSION) {
		theme_json_diagnostic(parser, .Invalid_Schema, schema.span, "schema must be the integer 1")
		version_valid = false
	} else { output.schema_version = THEME_SOURCE_SCHEMA_VERSION }

	if !has_contract { theme_json_missing(parser, root.span, "contract"); version_valid = false }
	else if contract.kind != .String || !theme_json_parse_contract(contract.text, &output.contract) {
		theme_json_diagnostic(parser, .Invalid_Contract, contract.span, "contract must use major.minor form, such as 0.2")
		version_valid = false
	} else if output.contract.major != THEME_CONTRACT_VERSION.major || output.contract.minor > THEME_CONTRACT_VERSION.minor {
		theme_json_diagnostic(parser, .Invalid_Contract, contract.span, "theme contract version is newer than this compiler supports")
		version_valid = false
	}

	if !version_valid { return }
	output.has_source = true
	output.source.metadata = Theme_Source_Metadata{
		schema_version=output.schema_version,
		contract=output.contract,
		span=theme_json_source_span(parser, root.span),
	}

	if has_extends {
		if extends.kind != .String || extends.text == "" {
			theme_json_diagnostic(parser, .Unsupported_Value, extends.span, "extends must be a non-empty theme identifier string")
		} else { output.extends = theme_json_clone(extends.text, parser.allocator) }
	}

	for member in root.members {
		if member.key != "schema" && member.key != "contract" && member.key != "extends" &&
		   member.key != "tokens" && member.key != "roles" && member.key != "materials" &&
		   member.key != "recipes" {
			theme_json_diagnostic(parser, .Unsupported_Field, member.key_span, "unsupported top-level field")
		}
	}

	if !has_tokens { theme_json_missing(parser, root.span, "tokens") }
	else if tokens.kind != .Object {
		theme_json_diagnostic(parser, .Unsupported_Value, tokens.span, "tokens must be an object keyed by token name")
	} else { theme_json_map_tokens(parser, tokens^, output) }

	if has_roles {
		if roles.kind != .Object {
			theme_json_diagnostic(parser, .Unsupported_Value, roles.span, "roles must be an object")
		} else { theme_json_map_roles(parser, roles^, output) }
	}
	if has_materials {
		if materials.kind != .Object {
			theme_json_diagnostic(parser, .Unsupported_Value, materials.span, "materials must be an object keyed by app/vendor material name")
		} else { theme_json_map_materials(parser, materials^, output) }
	}
	if has_recipes {
		if recipes.kind != .Object {
			theme_json_diagnostic(parser, .Unsupported_Value, recipes.span, "recipes must be an object")
		} else { theme_json_map_recipes(parser, recipes^, output) }
	}
}

theme_json_map_materials :: proc(parser: ^JSON_Parser, node: JSON_Node, output: ^Theme_JSON_Output) {
	definitions := make([dynamic]Theme_Material_Definition, 0, allocator=parser.allocator)
	for member in node.members {
		if !theme_extension_role_name_is_valid(member.key) {
			theme_json_diagnostic(parser, .Invalid_Material, member.key_span, "material names must use app.* or vendor.* namespaces")
			continue
		}
		if member.value.kind != .Object {
			theme_json_diagnostic(parser, .Invalid_Material, member.value.span, "material definition must be an object")
			continue
		}
		kind_node, has_kind := theme_json_member(member.value, "kind")
		if !has_kind { theme_json_missing(parser, member.value.span, "kind") }
		value := Theme_Material{}
		if has_kind {
			if kind_node.kind != .String {
				theme_json_diagnostic(parser, .Invalid_Material, kind_node.span, "material kind must be 'flat' or 'analytic_relief'")
			} else {
				switch kind_node.text {
				case "flat": value.kind = .Flat
				case "analytic_relief": value.kind = .Analytic_Relief
				case: theme_json_diagnostic(parser, .Invalid_Material, kind_node.span, "supported material kinds are 'flat' and 'analytic_relief'")
				}
			}
		}
		for property in member.value.members {
			if property.key != "kind" && property.key != "bevel_width" && property.key != "bevel_strength" &&
			   property.key != "inner_shadow_strength" && property.key != "outer_shadow_strength" &&
			   property.key != "outer_shadow_radius" {
				theme_json_diagnostic(parser, .Unsupported_Field, property.key_span, "unsupported material property")
			}
		}
		bevel_width, bw_ok := theme_json_optional_f32(parser, member.value, "bevel_width")
		bevel_strength, bs_ok := theme_json_optional_f32(parser, member.value, "bevel_strength")
		inner_shadow_strength, is_ok := theme_json_optional_f32(parser, member.value, "inner_shadow_strength")
		outer_shadow_strength, os_ok := theme_json_optional_f32(parser, member.value, "outer_shadow_strength")
		outer_shadow_radius, or_ok := theme_json_optional_f32(parser, member.value, "outer_shadow_radius")
		value.bevel_width = bevel_width
		value.bevel_strength = bevel_strength
		value.inner_shadow_strength = inner_shadow_strength
		value.outer_shadow_strength = outer_shadow_strength
		value.outer_shadow_radius = outer_shadow_radius
		if has_kind && bw_ok && bs_ok && is_ok && os_ok && or_ok {
			append(&definitions, Theme_Material_Definition{
				name=theme_json_clone(member.key, parser.allocator),
				value=value,
				span=theme_json_source_span(parser, member.key_span),
			})
		}
	}
	output.source.materials = definitions[:]
}

theme_json_map_recipes :: proc(parser: ^JSON_Parser, node: JSON_Node, output: ^Theme_JSON_Output) {
	definitions := make([dynamic]Theme_Button_Recipe_Override, 0, allocator=parser.allocator)
	for component in node.members {
		if component.key != "button" {
			theme_json_diagnostic(parser, .Invalid_Recipe, component.key_span, "only the built-in 'button' recipe family is supported")
			continue
		}
		if component.value.kind != .Object {
			theme_json_diagnostic(parser, .Invalid_Recipe, component.value.span, "button recipes must be an object keyed by variant")
			continue
		}
		for variant_member in component.value.members {
			variant, variant_ok := theme_json_button_variant(variant_member.key)
			if !variant_ok {
				theme_json_diagnostic(parser, .Invalid_Recipe, variant_member.key_span, "unknown button variant")
				continue
			}
			if variant_member.value.kind != .Object {
				theme_json_diagnostic(parser, .Invalid_Recipe, variant_member.value.span, "button recipe override must be an object")
				continue
			}
			override := Theme_Button_Recipe_Override{
				variant=variant,
				span=theme_json_source_span(parser, variant_member.key_span),
			}
			for property in variant_member.value.members {
				switch property.key {
				case "surface_role":
					role, ok := theme_json_recipe_role(parser, property.value)
					if ok { override.surface_role, override.has_surface_role = role, true }
				case "text_role":
					role, ok := theme_json_recipe_role(parser, property.value)
					if ok { override.text_role, override.has_text_role = role, true }
				case "surface_visible":
					if property.value.kind == .Boolean { override.surface_visible, override.has_surface_visible = property.value.boolean, true }
					else { theme_json_diagnostic(parser, .Invalid_Recipe, property.value.span, "surface_visible must be a boolean") }
				case "selected_indicator":
					if property.value.kind != .String { theme_json_diagnostic(parser, .Invalid_Recipe, property.value.span, "selected_indicator must be 'none' or 'underline'") }
					else {
						switch property.value.text {
						case "none": override.selected_indicator, override.has_selected_indicator = false, true
						case "underline": override.selected_indicator, override.has_selected_indicator = true, true
						case: theme_json_diagnostic(parser, .Invalid_Recipe, property.value.span, "selected_indicator must be 'none' or 'underline'")
						}
					}
				case "selected_indicator_role":
					role, ok := theme_json_recipe_role(parser, property.value)
					if ok { override.selected_indicator_role, override.has_selected_indicator_role = role, true }
				case "focus_indicator_mode":
					if property.value.kind != .String { theme_json_diagnostic(parser, .Invalid_Recipe, property.value.span, "focus_indicator_mode must be 'always' or 'keyboard_only'") }
					else {
						switch property.value.text {
						case "always": override.focus_indicator_keyboard_only, override.has_focus_indicator_keyboard = false, true
						case "keyboard_only": override.focus_indicator_keyboard_only, override.has_focus_indicator_keyboard = true, true
						case: theme_json_diagnostic(parser, .Invalid_Recipe, property.value.span, "focus_indicator_mode must be 'always' or 'keyboard_only'")
						}
					}
				case "focus_role":
					role, ok := theme_json_recipe_role(parser, property.value)
					if ok { override.focus_role, override.has_focus_role = role, true }
				case "semantic_active_role":
					role, ok := theme_json_recipe_role(parser, property.value)
					if ok { override.semantic_active_role, override.has_semantic_active_role = role, true }
				case "states":
					theme_json_map_button_states(parser, property.value, &override)
				case:
					theme_json_diagnostic(parser, .Unsupported_Field, property.key_span, "unsupported button recipe property")
				}
			}
			append(&definitions, override)
		}
	}
	output.source.button_recipes = definitions[:]
}

theme_json_map_button_states :: proc(parser: ^JSON_Parser, node: JSON_Node, override: ^Theme_Button_Recipe_Override) {
	if node.kind != .Object {
		theme_json_diagnostic(parser, .Invalid_Recipe, node.span, "states must be an object keyed by selected, hovered, pressed, or disabled")
		return
	}
	for state_member in node.members {
		state, state_ok := theme_json_button_state(state_member.key)
		if !state_ok {
			theme_json_diagnostic(parser, .Invalid_Recipe, state_member.key_span, "unknown button state")
			continue
		}
		if state_member.value.kind != .Object {
			theme_json_diagnostic(parser, .Invalid_Recipe, state_member.value.span, "button state transform must be an object")
			continue
		}
		transform := &override.states[int(state)]
		for property in state_member.value.members {
			switch property.key {
			case "surface_role":
				role, ok := theme_json_recipe_role(parser, property.value)
				if ok { transform.surface_role, transform.has_surface_role = role, true }
			case "surface_mix":
				value, ok := theme_json_required_f32(parser, property.value, "surface_mix")
				if ok { transform.surface_mix, transform.has_surface_mix = value, true }
			case "text_role":
				role, ok := theme_json_recipe_role(parser, property.value)
				if ok { transform.text_role, transform.has_text_role = role, true }
			case "text_mix":
				value, ok := theme_json_required_f32(parser, property.value, "text_mix")
				if ok { transform.text_mix, transform.has_text_mix = value, true }
			case:
				theme_json_diagnostic(parser, .Unsupported_Field, property.key_span, "unsupported button transform property")
			}
		}
	}
}

theme_json_recipe_role :: proc(parser: ^JSON_Parser, node: JSON_Node) -> (Core_Color_Role, bool) {
	if node.kind != .String {
		theme_json_diagnostic(parser, .Invalid_Recipe, node.span, "recipe role must be a core color role name")
		return .Count, false
	}
	role, ok := theme_json_core_role(node.text)
	if !ok { theme_json_diagnostic(parser, .Invalid_Recipe, node.span, "unknown core color role in recipe") }
	return role, ok
}

theme_json_button_variant :: proc(value: string) -> (Theme_Button_Variant, bool) {
	switch value {
	case "default": return .Default, true
	case "primary": return .Primary, true
	case "toolbar": return .Toolbar, true
	case "quiet": return .Quiet, true
	case "tab": return .Tab, true
	case "danger": return .Danger, true
	}
	return .Default, false
}

theme_json_button_state :: proc(value: string) -> (Theme_Button_State, bool) {
	switch value {
	case "selected": return .Selected, true
	case "hovered": return .Hovered, true
	case "pressed": return .Pressed, true
	case "disabled": return .Disabled, true
	}
	return .Selected, false
}

theme_json_optional_f32 :: proc(parser: ^JSON_Parser, object: JSON_Node, name: string) -> (f32, bool) {
	node, found := theme_json_member(object, name)
	if !found { return 0, true }
	return theme_json_required_f32(parser, node^, name)
}

theme_json_required_f32 :: proc(parser: ^JSON_Parser, node: JSON_Node, name: string) -> (f32, bool) {
	if node.kind != .Number {
		theme_json_diagnostic(parser, .Unsupported_Value, node.span, "numeric value required for theme property")
		return 0, false
	}
	return f32(node.number), true
}

theme_json_map_tokens :: proc(parser: ^JSON_Parser, node: JSON_Node, output: ^Theme_JSON_Output) {
	definitions := make([dynamic]Token_Definition, 0, allocator=parser.allocator)
	for member in node.members {
		if member.value.kind != .Object {
			theme_json_diagnostic(parser, .Unsupported_Value, member.value.span, "token declaration must be an object")
			continue
		}
		type_node, has_type := theme_json_member(member.value, "$type")
		value_node, has_value := theme_json_member(member.value, "$value")
		if !has_type { theme_json_missing(parser, member.value.span, "$type") }
		if !has_value { theme_json_missing(parser, member.value.span, "$value") }
		for property in member.value.members {
			if property.key != "$type" && property.key != "$value" {
				theme_json_diagnostic(parser, .Unsupported_Field, property.key_span, "unsupported token property")
			}
		}
		if !has_type || !has_value { continue }
		if type_node.kind != .String {
			theme_json_diagnostic(parser, .Invalid_Token_Type, type_node.span, "$type must be 'color' or 'dimension'")
			continue
		}
		kind: Token_Kind
		switch type_node.text {
		case "color": kind = .Color
		case "dimension": kind = .Length
		case:
			theme_json_diagnostic(parser, .Invalid_Token_Type, type_node.span, "supported token types are 'color' and 'dimension'")
			continue
		}
		value, valid := theme_json_token_value(parser, kind, value_node^)
		if valid {
			append(&definitions, Token_Definition{
				name=theme_json_clone(member.key, parser.allocator),
				kind=kind,
				value=value,
				span=theme_json_source_span(parser, member.key_span),
			})
		}
	}
	output.source.tokens = definitions[:]
}

theme_json_token_value :: proc(parser: ^JSON_Parser, kind: Token_Kind, node: JSON_Node) -> (value: Theme_Token_Value, valid: bool) {
	if node.kind == .String {
		target, ok := theme_json_alias_target(node.text)
		if !ok {
			theme_json_diagnostic(parser, .Unsupported_Value, node.span, "string token values must be a {token.name} alias")
			return
		}
		return Theme_Alias{theme_json_clone(target, parser.allocator)}, true
	}
	if kind == .Color {
		color, ok := theme_json_parse_color(parser, node)
		if ok { return color, true }
	} else {
		length, ok := theme_json_parse_length(parser, node)
		if ok { return length, true }
	}
	return
}

theme_json_parse_color :: proc(parser: ^JSON_Parser, node: JSON_Node) -> (Theme_Color, bool) {
	if node.kind != .Object {
		theme_json_diagnostic(parser, .Invalid_Color, node.span, "color value must be an sRGB object or token alias")
		return {}, false
	}
	space, has_space := theme_json_member(node, "colorSpace")
	components, has_components := theme_json_member(node, "components")
	alpha, has_alpha := theme_json_member(node, "alpha")
	if !has_space { theme_json_missing(parser, node.span, "colorSpace") }
	if !has_components { theme_json_missing(parser, node.span, "components") }
	for member in node.members {
		if member.key != "colorSpace" && member.key != "components" && member.key != "alpha" {
			theme_json_diagnostic(parser, .Unsupported_Field, member.key_span, "unsupported color value field")
		}
	}
	if !has_space || !has_components { return {}, false }
	if space.kind != .String || space.text != "srgb" {
		theme_json_diagnostic(parser, .Unsupported_Value, space.span, "only the explicit 'srgb' color space is supported")
		return {}, false
	}
	if components.kind != .Array || len(components.elements) != 3 {
		theme_json_diagnostic(parser, .Invalid_Color, components.span, "sRGB components must be an array of exactly three numbers")
		return {}, false
	}
	values: [3]f32
	for element, index in components.elements {
		if element.kind != .Number || !theme_json_unit_component(element.number) {
			theme_json_diagnostic(parser, .Invalid_Color, element.span, "sRGB components must be finite numbers in [0,1]")
			return {}, false
		}
		values[index] = theme_json_srgb_to_linear(element.number)
	}
	a: f32 = 1
	if has_alpha {
		if alpha.kind != .Number || !theme_json_unit_component(alpha.number) || alpha.number == 0 {
			theme_json_diagnostic(parser, .Invalid_Color, alpha.span, "alpha must be a finite number in (0,1]")
			return {}, false
		}
		a = f32(alpha.number)
	}
	return Theme_Color{values[0], values[1], values[2], a}, true
}

theme_json_parse_length :: proc(parser: ^JSON_Parser, node: JSON_Node) -> (Theme_Length, bool) {
	if node.kind != .Object {
		theme_json_diagnostic(parser, .Invalid_Length, node.span, "dimension value must be an object or token alias")
		return 0, false
	}
	amount, has_amount := theme_json_member(node, "value")
	unit, has_unit := theme_json_member(node, "unit")
	if !has_amount { theme_json_missing(parser, node.span, "value") }
	if !has_unit { theme_json_missing(parser, node.span, "unit") }
	for member in node.members {
		if member.key != "value" && member.key != "unit" {
			theme_json_diagnostic(parser, .Unsupported_Field, member.key_span, "unsupported dimension value field")
		}
	}
	if !has_amount || !has_unit { return 0, false }
	if unit.kind != .String || unit.text != "px" {
		theme_json_diagnostic(parser, .Unsupported_Value, unit.span, "only dimension unit 'px' is supported and maps to logical units")
		return 0, false
	}
	if amount.kind != .Number || amount.number != amount.number || amount.number < 0 || amount.number > 1_000_000 {
		theme_json_diagnostic(parser, .Invalid_Length, amount.span, "dimension must be a finite number in [0,1000000]")
		return 0, false
	}
	return Theme_Length(f32(amount.number)), true
}

theme_json_map_roles :: proc(parser: ^JSON_Parser, roles: JSON_Node, output: ^Theme_JSON_Output) {
	core, has_core := theme_json_member(roles, "core")
	extensions, has_extensions := theme_json_member(roles, "extensions")
	for member in roles.members {
		if member.key != "core" && member.key != "extensions" {
			theme_json_diagnostic(parser, .Unsupported_Field, member.key_span, "roles supports only 'core' and 'extensions'")
		}
	}
	if has_core {
		if core.kind != .Object { theme_json_diagnostic(parser, .Unsupported_Value, core.span, "core roles must be an object") }
		else { theme_json_map_core_roles(parser, core^, output) }
	}
	if has_extensions {
		if extensions.kind != .Object { theme_json_diagnostic(parser, .Unsupported_Value, extensions.span, "extension roles must be an object") }
		else { theme_json_map_extension_roles(parser, extensions^, output) }
	}
}

theme_json_map_core_roles :: proc(parser: ^JSON_Parser, node: JSON_Node, output: ^Theme_JSON_Output) {
	bindings := make([dynamic]Core_Role_Binding, 0, allocator=parser.allocator)
	for member in node.members {
		role, role_valid := theme_json_core_role(member.key)
		if !role_valid {
			theme_json_diagnostic(parser, .Invalid_Core_Role, member.key_span, "unknown core color role")
			continue
		}
		target, target_valid := theme_json_node_alias(parser, member.value)
		if !target_valid { continue }
		append(&bindings, Core_Role_Binding{
			role=role,
			token=theme_json_clone(target, parser.allocator),
			span=theme_json_source_span(parser, member.key_span),
		})
	}
	output.source.core_roles = bindings[:]
}

theme_json_map_extension_roles :: proc(parser: ^JSON_Parser, node: JSON_Node, output: ^Theme_JSON_Output) {
	declarations := make([dynamic]Extension_Role_Declaration, 0, allocator=parser.allocator)
	for member in node.members {
		if !theme_extension_role_name_is_valid(member.key) {
			theme_json_diagnostic(parser, .Invalid_Extension_Role, member.key_span, "extension roles must use app.* or vendor.* names")
			continue
		}
		if member.value.kind != .Object {
			theme_json_diagnostic(parser, .Unsupported_Value, member.value.span, "extension role must declare $type and a token-alias $value")
			continue
		}
		type_node, has_type := theme_json_member(member.value, "$type")
		value_node, has_value := theme_json_member(member.value, "$value")
		if !has_type { theme_json_missing(parser, member.value.span, "$type") }
		if !has_value { theme_json_missing(parser, member.value.span, "$value") }
		for property in member.value.members {
			if property.key != "$type" && property.key != "$value" {
				theme_json_diagnostic(parser, .Unsupported_Field, property.key_span, "unsupported extension role property")
			}
		}
		if !has_type || !has_value { continue }
		if type_node.kind != .String {
			theme_json_diagnostic(parser, .Invalid_Token_Type, type_node.span, "$type must be 'color' or 'dimension'")
			continue
		}
		kind: Token_Kind
		switch type_node.text {
		case "color": kind = .Color
		case "dimension": kind = .Length
		case:
			theme_json_diagnostic(parser, .Invalid_Token_Type, type_node.span, "supported extension role types are 'color' and 'dimension'")
			continue
		}
		target, target_valid := theme_json_node_alias(parser, value_node^)
		if !target_valid { continue }
		append(&declarations, Extension_Role_Declaration{
			name=theme_json_clone(member.key, parser.allocator),
			kind=kind,
			token=theme_json_clone(target, parser.allocator),
			span=theme_json_source_span(parser, member.key_span),
		})
	}
	output.source.extension_roles = declarations[:]
}

theme_json_node_alias :: proc(parser: ^JSON_Parser, node: JSON_Node) -> (string, bool) {
	if node.kind != .String {
		theme_json_diagnostic(parser, .Unsupported_Value, node.span, "role binding must be a {token.name} reference")
		return "", false
	}
	target, ok := theme_json_alias_target(node.text)
	if !ok {
		theme_json_diagnostic(parser, .Invalid_Alias, node.span, "reference must have the form {token.name}")
	}
	return target, ok
}

theme_json_alias_target :: proc(value: string) -> (string, bool) {
	if len(value) < 3 || value[0] != '{' || value[len(value)-1] != '}' { return "", false }
	target := value[1:len(value)-1]
	if target == "" { return "", false }
	for character in target {
		if character <= ' ' || character == '{' || character == '}' { return "", false }
	}
	return target, true
}

theme_json_core_role :: proc(name: string) -> (Core_Color_Role, bool) {
	switch name {
	case "window_background": return .Window_Background, true
	case "surface": return .Surface, true
	case "subtle_surface": return .Subtle_Surface, true
	case "editor_background": return .Editor_Background, true
	case "text": return .Text, true
	case "muted_text": return .Muted_Text, true
	case "accent": return .Accent, true
	case "accent_hover": return .Accent_Hover, true
	case "accent_pressed": return .Accent_Pressed, true
	case "accent_text": return .Accent_Text, true
	case "selection": return .Selection, true
	case "focus": return .Focus, true
	case "semantic_focus": return .Semantic_Focus, true
	case "border": return .Border, true
	case "danger": return .Danger, true
	case "success": return .Success, true
	case "scrollbar_track": return .Scrollbar_Track, true
	case "scrollbar_thumb": return .Scrollbar_Thumb, true
	}
	return .Count, false
}

theme_json_parse_contract :: proc(value: string, version: ^Theme_Contract_Version) -> bool {
	dot := -1
	for character, index in value {
		if character == '.' {
			if dot >= 0 { return false }
			dot = index
		}
	}
	if dot <= 0 || dot >= len(value)-1 { return false }
	major, major_ok := theme_json_parse_u32(value[:dot])
	minor, minor_ok := theme_json_parse_u32(value[dot+1:])
	if !major_ok || !minor_ok { return false }
	if major > 0xFFFF || minor > 0xFFFF { return false }
	version^ = Theme_Contract_Version{major=u16(major), minor=u16(minor)}
	return true
}

theme_json_parse_u32 :: proc(value: string) -> (u32, bool) {
	result: u64
	for character in value {
		if character < '0' || character > '9' { return 0, false }
		digit := u64(character - '0')
		if result > (u64(0xFFFF_FFFF)-digit)/10 { return 0, false }
		result = result*10 + digit
	}
	return u32(result), len(value) > 0
}

theme_json_member :: proc(node: JSON_Node, key: string) -> (^JSON_Node, bool) {
	for index in 0..<len(node.members) {
		if node.members[index].key == key { return &node.members[index].value, true }
	}
	return nil, false
}

theme_json_missing :: proc(parser: ^JSON_Parser, span: Source_Span, name: string) {
	located_span := span
	if located_span.path == "" { located_span.path = parser.path }
	append(&parser.diagnostics, Theme_JSON_Diagnostic{
		code=.Missing_Field,
		span=located_span,
		message="required field is missing",
		field=name,
	})
}

theme_json_diagnostic :: proc(
	parser: ^JSON_Parser,
	code: Theme_JSON_Diagnostic_Code,
	span: Source_Span,
	message: string,
) {
	located_span := span
	if located_span.path == "" { located_span.path = parser.path }
	append(&parser.diagnostics, Theme_JSON_Diagnostic{code=code, span=located_span, message=message})
}

theme_json_syntax :: proc(parser: ^JSON_Parser, token: json.Token, message: string) {
	span := theme_json_token_span(token)
	theme_json_diagnostic(parser, .Syntax, span, message)
	parser.fatal = true
}

theme_json_token_span :: proc(token: json.Token) -> Source_Span {
	start := max(token.offset, 0)
	return Source_Span{
		start_offset=u64(start),
		end_offset=u64(start+len(token.text)),
		line=u32(max(token.line, 1)),
		column=u32(max(token.column, 1)),
	}
}

theme_json_source_span :: proc(parser: ^JSON_Parser, span: Source_Span) -> Source_Span {
	result := span
	result.path = parser.path
	return result
}

theme_json_unit_component :: proc(value: f64) -> bool {
	return value == value && value >= 0 && value <= 1
}

theme_json_srgb_to_linear :: proc(encoded: f64) -> f32 {
	if encoded <= 0.04045 { return f32(encoded / 12.92) }
	return f32(math.pow((encoded + 0.055) / 1.055, 2.4))
}

theme_json_clone :: proc(value: string, allocator: mem.Allocator) -> string {
	copy, _ := strings.clone(value, allocator)
	return copy
}

theme_json_node_destroy :: proc(node: JSON_Node, allocator: mem.Allocator) {
	if node.kind == .Object { theme_json_members_destroy(node.members, allocator) }
	if node.kind == .Array { theme_json_elements_destroy(node.elements, allocator) }
	if node.kind == .String { delete(node.text, allocator) }
}

theme_json_members_destroy :: proc(members: []JSON_Member, allocator: mem.Allocator) {
	for member in members {
		delete(member.key, allocator)
		theme_json_node_destroy(member.value, allocator)
	}
	delete(members, allocator)
}

theme_json_elements_destroy :: proc(elements: []JSON_Node, allocator: mem.Allocator) {
	for element in elements { theme_json_node_destroy(element, allocator) }
	delete(elements, allocator)
}

theme_json_sort_diagnostics :: proc(diagnostics: ^[]Theme_JSON_Diagnostic) {
	for index in 1..<len(diagnostics^) {
		cursor := index
		for cursor > 0 && theme_json_diagnostic_less(diagnostics^[cursor], diagnostics^[cursor-1]) {
			diagnostics^[cursor], diagnostics^[cursor-1] = diagnostics^[cursor-1], diagnostics^[cursor]
			cursor -= 1
		}
	}
}

theme_json_diagnostic_less :: proc(a, b: Theme_JSON_Diagnostic) -> bool {
	if a.span.start_offset != b.span.start_offset { return a.span.start_offset < b.span.start_offset }
	if a.code != b.code { return a.code < b.code }
	if a.message != b.message { return a.message < b.message }
	return a.field < b.field
}
