package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
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
	case "compile":
		if len(args) < 7 {
			fmt.eprintln("theme compile expects a source, --output path, and --symbol name")
			theme_cli_usage(os.stderr)
			status = 2
		} else {
			output_path, symbol := "", ""
			package_name, runtime_import := "main", "alicorn:runtime"
			output_seen, symbol_seen, package_seen, runtime_import_seen := false, false, false, false
			option_error := false
			index := 3
			for index < len(args) {
				option := args[index]
				if index+1 >= len(args) {
					fmt.eprintfln("missing value for {:s}", option)
					option_error = true
					break
				}
				value := args[index+1]
				switch option {
				case "--output":
					if output_seen { fmt.eprintln("--output may only be specified once"); option_error = true; break }
					output_path, output_seen = value, true
				case "--symbol":
					if symbol_seen { fmt.eprintln("--symbol may only be specified once"); option_error = true; break }
					symbol, symbol_seen = value, true
				case "--package":
					if package_seen { fmt.eprintln("--package may only be specified once"); option_error = true; break }
					package_name = value
					package_seen = true
				case "--runtime-import":
					if runtime_import_seen { fmt.eprintln("--runtime-import may only be specified once"); option_error = true; break }
					runtime_import = value
					runtime_import_seen = true
				case:
					fmt.eprintfln("unknown theme compile option: {:s}", option)
					option_error = true
				}
				if option_error { break }
				index += 2
			}
			if !output_seen || !symbol_seen {
				fmt.eprintln("theme compile requires --output and --symbol")
				option_error = true
			}
			if option_error {
				theme_cli_usage(os.stderr)
				status = 2
			} else {
				status = theme_cli_compile(args[2], output_path, symbol, package_name, runtime_import)
			}
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
	fmt.fprintln(output, "Alicorn theme compiler and source tools")
	fmt.fprintln(output, "")
	fmt.fprintln(output, "Usage:")
	fmt.fprintln(output, "  theme check <file>                 Validate strict theme JSON")
	fmt.fprintln(output, "  theme explain <file> <token-name>  Show a token value and provenance")
	fmt.fprintln(output, "  theme compile <file> --output <file> --symbol <name> [--package <name>] [--runtime-import <path>]")
	fmt.fprintln(output, "  theme help                         Show this help")
	fmt.fprintln(output, "")
	fmt.fprintln(output, "Only schema/contract versions supported by this build are accepted.")
	fmt.fprintln(output, "JSON color components are sRGB; explain reports converted linear-sRGB channels (alpha unchanged).")
	fmt.fprintln(output, "Only extends = alicorn.base is supported; it uses typed built-in defaults and never loads a path.")
	fmt.fprintln(output, "compile emits an Odin factory and matching destroy procedure; generated sources default to package main and import alicorn:runtime.")
}

// All file/parser/compiler/adapter allocations are released before returning.
// The process argument storage is owned by core:os and lives for process life.
theme_cli_run :: proc(path, token_name: string) -> int {
	compiled, schema_version, includes_base, compiled_ok := theme_cli_compile_file(path)
	if !compiled_ok { return 1 }
	defer theme.theme_output_destroy(&compiled)

	// Validate that the compiled source can be applied over Alicorn's typed
	// built-in runtime defaults. The adapter performs no file lookup.
	runtime_theme, adapter_ok := theme.theme_runtime_style_theme(compiled)
	if !adapter_ok {
		fmt.eprintfln("{:s}: error: compiled theme cannot be represented by the current Alicorn runtime style contract", path)
		return 1
	}
	defer theme.theme_runtime_style_theme_destroy(&runtime_theme)

	if token_name == "" {
		fmt.printfln("valid theme: {}", path)
		fmt.printfln("schema {}, contract {}.{}; {} color tokens, {} length tokens",
			schema_version, compiled.theme.contract.major, compiled.theme.contract.minor,
			len(compiled.theme.colors), len(compiled.theme.lengths))
		if includes_base {
			fmt.println("base: alicorn.base (typed built-in layer; no filesystem lookup)")
		}
		return 0
	}

	return theme_cli_explain(compiled, path, token_name)
}

theme_cli_compile_file :: proc(path: string) -> (output: theme.Theme_Compile_Output, schema_version: u32, includes_base, ok: bool) {
	data, read_error := os.read_entire_file(path, context.allocator)
	if read_error != nil {
		fmt.eprintln("could not read theme file:", path, "error:", read_error)
		return {}, 0, false, false
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
	if !parsed.ok { return {}, 0, false, false }

	if parsed.extends != "" && parsed.extends != "alicorn.base" {
		span := parsed.source.metadata.span
		fmt.eprintfln("{:s}:{:d}:{:d}: error: unsupported extends '{:s}'; only the built-in 'alicorn.base' source is supported (arbitrary paths are never loaded)",
			span.path, span.line, span.column, parsed.extends)
		return {}, 0, false, false
	}

	compiled, source_layers_ok := theme_cli_compile_source(parsed.source, parsed.extends == "alicorn.base")
	if !source_layers_ok {
		span := parsed.source.metadata.span
		fmt.eprintfln("{:s}:{:d}:{:d}: error: Alicorn's built-in base source could not be constructed",
			span.path, span.line, span.column)
		return {}, 0, false, false
	}
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
		theme.theme_output_destroy(&compiled)
		return {}, 0, false, false
	}
	return compiled, parsed.schema_version, parsed.extends == "alicorn.base", true
}

theme_cli_compile :: proc(input_path, output_path, symbol, package_name, runtime_import: string) -> int {
	if !theme_cli_codegen_identifier_is_valid(symbol) {
		fmt.eprintln("invalid Odin symbol name:", symbol)
		return 2
	}
	if !theme_cli_codegen_identifier_is_valid(package_name) {
		fmt.eprintln("invalid Odin package name:", package_name)
		return 2
	}
	if !theme_cli_codegen_import_is_valid(runtime_import) {
		fmt.eprintln("invalid Odin runtime import path:", runtime_import)
		return 2
	}

	input_absolute, input_path_error := os.get_absolute_path(input_path, context.allocator)
	if input_path_error != nil {
		fmt.eprintln("could not resolve theme source path:", input_path, "error:", input_path_error)
		return 1
	}
	defer delete(input_absolute)
	output_directory, output_name := filepath.split(output_path)
	if output_directory == "" { output_directory = "." }
	output_directory_absolute, output_directory_error := filepath.abs(output_directory, context.allocator)
	if output_directory_error != nil {
		fmt.eprintln("could not resolve output directory:", output_directory, "error:", output_directory_error)
		return 1
	}
	defer delete(output_directory_absolute)
	output_absolute, output_join_error := filepath.join({output_directory_absolute, output_name}, context.allocator)
	if output_join_error != nil {
		fmt.eprintln("could not resolve output path:", output_path, "error:", output_join_error)
		return 1
	}
	defer delete(output_absolute)
	if strings.equal_fold(input_absolute, output_absolute) {
		fmt.eprintln("theme source and generated output must be different files")
		return 2
	}
	input_info, input_stat_error := os.stat(input_path, context.allocator)
	if input_stat_error == nil { defer os.file_info_delete(input_info, context.allocator) }
	output_info, output_stat_error := os.stat(output_path, context.allocator)
	if output_stat_error == nil {
		defer os.file_info_delete(output_info, context.allocator)
		if input_stat_error == nil && os.same_file(input_info, output_info) {
			fmt.eprintln("theme source and generated output must be different files")
			return 2
		}
	}

	compiled, _, _, compiled_ok := theme_cli_compile_file(input_path)
	if !compiled_ok { return 1 }
	defer theme.theme_output_destroy(&compiled)
	runtime_theme, adapted := theme.theme_runtime_style_theme(compiled)
	if !adapted {
		fmt.eprintln("compiled theme cannot be represented by the current Alicorn runtime style contract")
		return 1
	}
	defer theme.theme_runtime_style_theme_destroy(&runtime_theme)

	generated, generated_ok := theme_cli_codegen_odin(runtime_theme, symbol, package_name, runtime_import)
	if !generated_ok {
		fmt.eprintln("could not generate valid Odin theme source")
		return 1
	}
	defer delete(generated)
	if write_error := os.write_entire_file_from_string(output_path, generated); write_error != nil {
		fmt.eprintln("could not write generated theme source:", output_path, "error:", write_error)
		return 1
	}
	fmt.printfln("compiled theme source {} -> {} ({})", input_path, output_path, symbol)
	return 0
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
