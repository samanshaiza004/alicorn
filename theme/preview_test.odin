package theme

import "core:testing"

@(test)
test_theme_json_compile_and_preview_compatibility :: proc(t: ^testing.T) {
	first := theme_compile_json(`{
	  "schema": 1, "contract": "0.2", "extends": "alicorn.base",
	  "tokens": {"app.accent": {"$type":"color", "$value":{"colorSpace":"srgb", "components":[0.7,0.2,0.1], "alpha":1}}},
	  "roles": {"core":{"accent":"{app.accent}"}}
	}`, "first.json")
	defer theme_json_compile_output_destroy(&first)
	second := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"alicorn.base","tokens":{"app.accent":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.1,0.6,0.2],"alpha":1}}},"roles":{"core":{"accent":"{app.accent}"}}}`, "second.json")
	defer theme_json_compile_output_destroy(&second)
	testing.expect(t, first.ok && second.ok, "valid JSON should compile with the typed built-in base layer")
	testing.expect(t, theme_preview_structure_compatible(first, second),
		"formatting, source paths, and color values may change while token identity and role bindings stay fixed")
	if first.ok && second.ok {
		accent := int(u32(first.compiled.theme.core_color_roles[int(Core_Color_Role.Accent)]))-1
		testing.expect(t, accent >= 0 && accent < len(first.compiled.theme.colors) &&
			first.compiled.theme.colors[accent] != second.compiled.theme.colors[accent],
			"the compatible candidates should change the color bound to the Accent role")
	}

	changed_binding := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"alicorn.base","tokens":{"app.accent":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.1,0.6,0.2],"alpha":1}}},"roles":{"core":{"accent":"{alicorn.color.accent}"}}}`, "binding.json")
	defer theme_json_compile_output_destroy(&changed_binding)
	testing.expect(t, !theme_preview_structure_compatible(first, changed_binding),
		"changing a core role binding must reject a color-only preview candidate")

	changed_tokens := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"alicorn.base","tokens":{"app.other":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.1,0.6,0.2],"alpha":1}}},"roles":{"core":{"accent":"{app.other}"}}}`, "identity.json")
	defer theme_json_compile_output_destroy(&changed_tokens)
	testing.expect(t, !theme_preview_structure_compatible(first, changed_tokens),
		"renaming a token must reject a color-only preview candidate even when array lengths match")

	changed_structure := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"alicorn.base","tokens":{"app.accent":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.1,0.6,0.2],"alpha":1}},"space.extra":{"$type":"dimension","$value":{"value":4,"unit":"px"}}},"roles":{"core":{"accent":"{app.accent}"}}}`, "structure.json")
	defer theme_json_compile_output_destroy(&changed_structure)
	testing.expect(t, !theme_preview_structure_compatible(first, changed_structure),
		"adding a length token must be rejected by the initial color-only preview contract")

	material_before := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"alicorn.base","tokens":{"app.accent":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.7,0.2,0.1],"alpha":1}}},"roles":{"core":{"accent":"{app.accent}"}},"materials":{"app.gallery.panel":{"kind":"analytic_relief","bevel_width":1,"bevel_strength":0.2}}}`, "material-before.json")
	defer theme_json_compile_output_destroy(&material_before)
	material_color_only := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"alicorn.base","tokens":{"app.accent":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.1,0.6,0.2],"alpha":1}}},"roles":{"core":{"accent":"{app.accent}"}},"materials":{"app.gallery.panel":{"kind":"analytic_relief","bevel_width":1,"bevel_strength":0.2}}}`, "material-color-only.json")
	defer theme_json_compile_output_destroy(&material_color_only)
	material_changed := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"alicorn.base","tokens":{"app.accent":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.1,0.6,0.2],"alpha":1}}},"roles":{"core":{"accent":"{app.accent}"}},"materials":{"app.gallery.panel":{"kind":"analytic_relief","bevel_width":1,"bevel_strength":0.8}}}`, "material-changed.json")
	defer theme_json_compile_output_destroy(&material_changed)
	testing.expect(t, theme_preview_structure_compatible(material_before, material_color_only),
		"changing colors while a material remains identical should be compatible")
	testing.expect(t, !theme_preview_structure_compatible(material_before, material_changed),
		"changing a material value must be rejected by a color-only preview")

	bad := theme_compile_json(`{`, "invalid.json")
	defer theme_json_compile_output_destroy(&bad)
	testing.expect(t, !bad.ok && len(bad.parsed.diagnostics) > 0,
		"invalid JSON must remain a structured failed candidate for last-good handling")

	unknown_base := theme_compile_json(`{"schema":1,"contract":"0.2","extends":"../theme.json","tokens":{"a":{"$type":"color","$value":{"colorSpace":"srgb","components":[0.1,0.2,0.3],"alpha":1}}}}`, "untrusted.json")
	defer theme_json_compile_output_destroy(&unknown_base)
	testing.expect(t, !unknown_base.ok && unknown_base.unsupported_extends,
		"preview compilation must not load arbitrary paths from extends")
}
