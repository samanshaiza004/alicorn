package main

import "core:fmt"
import "core:os"
import theme "../../theme"

main :: proc() {
	args := os.args
	if len(args) == 1 {
		theme_cli_usage(os.stdout)
		return
	}

	status := 0
	switch args[1] {
	case "help", "--help", "-h":
		theme_cli_usage(os.stdout)
	case "check":
		if len(args) != 3 {
			fmt.eprintln("theme check expects exactly one file path")
			theme_cli_usage(os.stderr)
			status = 2
		} else {
			status = theme_cli_run(args[2], "")
		}
	case "explain":
		if len(args) != 4 {
			fmt.eprintln("theme explain expects a file path and token name")
			theme_cli_usage(os.stderr)
			status = 2
		} else {
			status = theme_cli_run(args[2], args[3])
		}
	case:
		fmt.eprintfln("unknown theme command: {}", args[1])
		theme_cli_usage(os.stderr)
		status = 2
	}

	if status != 0 {
		os.exit(status)
	}
}

theme_cli_usage :: proc(output: ^os.File) {
	fmt.fprintln(output, "Alicorn theme source checker")
	fmt.fprintln(output, "")
	fmt.fprintln(output, "Usage:")
	fmt.fprintln(output, "  theme check <file>                 Validate strict theme JSON")
	fmt.fprintln(output, "  theme explain <file> <token-name>  Show a token value and provenance")
	fmt.fprintln(output, "  theme help                         Show this help")
	fmt.fprintln(output, "")
	fmt.fprintln(output, "Only schema/contract versions supported by this build are accepted.")
	fmt.fprintln(output, "JSON color components are sRGB; explain reports converted linear-sRGB channels (alpha unchanged).")
	fmt.fprintln(output, "Only extends = alicorn.base is supported; it uses typed built-in defaults and never loads a path.")
}

// All file/parser/compiler/adapter allocations are released before returning.
// The process argument storage is owned by core:os and lives for process life.
theme_cli_run :: proc(path, token_name: string) -> int {
	data, read_error := os.read_entire_file(path, context.allocator)
	if read_error != nil {
		fmt.eprintln("could not read theme file:", path, "error:", read_error)
		return 1
	}
	defer delete(data)

	parsed := theme.theme_json_parse(string(data), path)
	defer theme.theme_json_output_destroy(&parsed)
	for diagnostic in parsed.diagnostics {
		if diagnostic.field != "" {
			fmt.eprintfln("{:s}:{:d}:{:d}: error: {:s} (field: {:s})", diagnostic.span.path,
				diagnostic.span.line, diagnostic.span.column, diagnostic.message, diagnostic.field)
		} else {
			fmt.eprintfln("{:s}:{:d}:{:d}: error: {:s}", diagnostic.span.path,
				diagnostic.span.line, diagnostic.span.column, diagnostic.message)
		}
	}
	if !parsed.ok {
		return 1
	}

	if parsed.extends != "" && parsed.extends != "alicorn.base" {
		span := parsed.source.metadata.span
		fmt.eprintfln("{:s}:{:d}:{:d}: error: unsupported extends '{:s}'; only the built-in 'alicorn.base' source is supported (arbitrary paths are never loaded)",
			span.path, span.line, span.column, parsed.extends)
		return 1
	}

	compiled, source_layers_ok := theme_cli_compile_source(parsed.source, parsed.extends == "alicorn.base")
	if !source_layers_ok {
		span := parsed.source.metadata.span
		fmt.eprintfln("{:s}:{:d}:{:d}: error: Alicorn's built-in base source could not be constructed",
			span.path, span.line, span.column)
		return 1
	}
	defer theme.theme_output_destroy(&compiled)
	for diagnostic in compiled.diagnostics {
		fmt.eprintf("{:s}:{:d}:{:d}: error: {:s}", diagnostic.path, diagnostic.span.line,
			diagnostic.span.column, theme_cli_compile_diagnostic_message(diagnostic))
		if len(diagnostic.symbol_path) > 0 {
			fmt.eprint(" [")
			for symbol, index in diagnostic.symbol_path {
				if index > 0 { fmt.eprint(" -> ") }
				fmt.eprint(symbol)
			}
			fmt.eprint("]")
		}
		fmt.eprintln("")
	}
	if !compiled.ok {
		return 1
	}

	// Validate that the compiled source can be applied over Alicorn's typed
	// built-in runtime defaults. The adapter performs no file lookup.
	runtime_theme, adapter_ok := theme.theme_runtime_style_theme(compiled)
	if !adapter_ok {
		span := parsed.source.metadata.span
		fmt.eprintln("{:s}:{:d}:{:d}: error: compiled theme cannot be represented by the current Alicorn runtime style contract",
			span.path, span.line, span.column)
		return 1
	}
	defer theme.theme_runtime_style_theme_destroy(&runtime_theme)

	if token_name == "" {
		fmt.printfln("valid theme: {}", path)
		fmt.printfln("schema {}, contract {}.{}; {} color tokens, {} length tokens",
			parsed.schema_version, compiled.theme.contract.major, compiled.theme.contract.minor,
			len(compiled.theme.colors), len(compiled.theme.lengths))
		if parsed.extends == "alicorn.base" {
			fmt.println("base: alicorn.base (typed built-in layer; no filesystem lookup)")
		}
		return 0
	}

	return theme_cli_explain(compiled, path, token_name)
}

theme_cli_compile_source :: proc(source: theme.Theme_Source_Model, include_base: bool) -> (theme.Theme_Compile_Output, bool) {
	if include_base {
		base := theme.theme_builtin_base_source_create()
		defer theme.theme_builtin_base_source_destroy(&base)
		if len(base.tokens) == 0 || len(base.core_roles) == 0 {
			return {}, false
		}
		return theme.theme_compile({base.model, source}, support=theme.THEME_COMPILER_SUPPORT), true
	}
	return theme.theme_compile({source}, support=theme.THEME_COMPILER_SUPPORT), true
}

theme_cli_explain :: proc(output: theme.Theme_Compile_Output, input_path, token_name: string) -> int {
	provenance_index := -1
	for token, index in output.debug.tokens {
		if token.name == token_name {
			provenance_index = index
			break
		}
	}
	if provenance_index < 0 {
		fmt.eprintfln("{:s}: error: token not found: {:s}", input_path, token_name)
		return 1
	}

	token := output.debug.tokens[provenance_index]
	kind_name := "color"
	if token.kind == .Length { kind_name = "length" }
	fmt.printfln("token: {}", token.name)
	fmt.printfln("kind: {}", kind_name)
	if token.kind == .Color {
		id := int(token.id)
		if id <= 0 || id > len(output.theme.colors) {
			fmt.eprintfln("{:s}: error: compiler returned an invalid color token id for {:s}", input_path, token_name)
			return 1
		}
		color := output.theme.colors[id-1]
		fmt.printfln("value: linear-srgb({:.7g}, {:.7g}, {:.7g}, alpha={:.7g})", color.r, color.g, color.b, color.a)
	} else {
		id := int(token.id)
		if id <= 0 || id > len(output.theme.lengths) {
			fmt.eprintfln("{:s}: error: compiler returned an invalid length token id for {:s}", input_path, token_name)
			return 1
		}
		fmt.printfln("value: {:.7g} logical units", f32(output.theme.lengths[id-1]))
	}
	fmt.println("provenance:")

	current := token
	for hop in 0..<len(output.debug.tokens) {
		fmt.printfln("  {:s} defined at {:s}:{:d}:{:d}", current.name, current.span.path,
			current.span.line, current.span.column)
		if current.alias_target == "" {
			break
		}
		fmt.printfln("    aliases to {}", current.alias_target)
		next_index := -1
		for candidate, index in output.debug.tokens {
			if candidate.name == current.alias_target {
				next_index = index
				break
			}
		}
		if next_index < 0 {
			fmt.eprintfln("{:s}: error: compiler returned missing alias provenance for {:s}", input_path, current.alias_target)
			return 1
		}
		current = output.debug.tokens[next_index]
	}
	if token.kind == .Color {
		if current.span.path == "alicorn.base" {
			fmt.println("representation: typed built-in value is already linear-sRGB; no authoring conversion applied")
		} else {
			fmt.println("representation: JSON source sRGB channels use the sRGB EOTF; alpha is unchanged")
		}
	}
	return 0
}

theme_cli_compile_diagnostic_message :: proc(diagnostic: theme.Theme_Diagnostic) -> string {
	switch diagnostic.code {
	case .Duplicate_Token: return "duplicate token definition"
	case .Token_Type_Changed: return "an overlay cannot change a token's type"
	case .Invalid_Token_Name: return "invalid or empty token name"
	case .Invalid_Token_Kind: return "unsupported token kind"
	case .Unsupported_Schema_Version: return "unsupported theme schema version"
	case .Unsupported_Contract_Version: return "unsupported Alicorn style contract version"
	case .Unknown_Alias: return "alias refers to an unknown token"
	case .Alias_Type_Mismatch: return "alias target has a different token kind"
	case .Alias_Cycle: return "token alias cycle"
	case .Invalid_Color: return "color is outside the supported channel range"
	case .Invalid_Length: return "length is outside the supported logical-unit range"
	case .Token_Value_Type_Mismatch: return "literal value does not match the declared token kind"
	case .Invalid_Core_Role: return "invalid core semantic role"
	case .Duplicate_Core_Role: return "core semantic role is declared more than once in one layer"
	case .Core_Role_Token_Not_Found: return "core role refers to an unknown token"
	case .Core_Role_Token_Type_Mismatch: return "core color role must reference a color token"
	case .Invalid_Extension_Role_Namespace: return "extension roles must use app.* or vendor.* namespace"
	case .Duplicate_Extension_Role: return "extension role is declared more than once in one layer"
	case .Extension_Role_Type_Changed: return "an overlay cannot change an extension role's type"
	case .Extension_Role_Hash_Collision: return "extension role ID collides with another role"
	case .Extension_Role_Token_Not_Found: return "extension role refers to an unknown token"
	case .Extension_Role_Token_Type_Mismatch: return "extension role and token kinds differ"
	}
	return "theme compilation failed"
}
