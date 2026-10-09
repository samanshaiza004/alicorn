package alicorn

// Control_Part_Transform composes visual state onto independent semantic
// parts of a control. It deliberately contains no geometry or layout values;
// those remain owned by the control and the layout system.
Control_Part_Transform :: struct {
	surface_role: Style_Color_Role,
	surface_mix: f32,
	text_role: Style_Color_Role,
	text_mix: f32,
	border_role: Style_Color_Role,
	border_mix: f32,
}

// Control_Part_Recipe resolves one semantic part independently. Each part
// receives the same selected → hovered → pressed → disabled state order, so
// controls compose transforms without a per-state color matrix.
Control_Part_Recipe :: struct {
	surface_role: Style_Color_Role,
	text_role: Style_Color_Role,
	border_role: Style_Color_Role,
	selected: Control_Part_Transform,
	hovered: Control_Part_Transform,
	pressed: Control_Part_Transform,
	disabled: Control_Part_Transform,
}

Control_Visual_State :: struct {
	selected: bool,
	hovered: bool,
	pressed: bool,
	disabled: bool,
}

Control_Part_Resolved_Style :: struct {
	surface: Color,
	text: Color,
	border: Color,
}

Checkbox_Recipe :: struct {
	defined: bool,
	box: Control_Part_Recipe,
	checkmark: Control_Part_Recipe,
	label: Control_Part_Recipe,
	focus_role: Style_Color_Role,
	focus_indicator_mode: Focus_Indicator_Mode,
}

Checkbox_Visual_State :: struct {
	checked: bool,
	hovered: bool,
	pressed: bool,
	disabled: bool,
	focused: bool,
}

Checkbox_Resolved_Style :: struct {
	box: Control_Part_Resolved_Style,
	checkmark: Control_Part_Resolved_Style,
	label: Control_Part_Resolved_Style,
	focus: Color,
	checked: bool,
	hovered: bool,
	pressed: bool,
	disabled: bool,
	focused: bool,
	focus_indicator_mode: Focus_Indicator_Mode,
	applied_transforms: Style_Control_States,
}

Slider_Recipe :: struct {
	defined: bool,
	track: Control_Part_Recipe,
	fill: Control_Part_Recipe,
	thumb: Control_Part_Recipe,
	label: Control_Part_Recipe,
	focus_role: Style_Color_Role,
	focus_indicator_mode: Focus_Indicator_Mode,
}

Slider_Visual_State :: struct {
	hovered: bool,
	pressed: bool,
	disabled: bool,
	focused: bool,
}

Slider_Resolved_Style :: struct {
	track: Control_Part_Resolved_Style,
	fill: Control_Part_Resolved_Style,
	thumb: Control_Part_Resolved_Style,
	label: Control_Part_Resolved_Style,
	focus: Color,
	hovered: bool,
	pressed: bool,
	disabled: bool,
	focused: bool,
	focus_indicator_mode: Focus_Indicator_Mode,
	applied_transforms: Style_Control_States,
}

Text_Field_Recipe :: struct {
	defined: bool,
	// horizontal_inset is a logical distance on each side of the text content.
	horizontal_inset: f32,
	surface_role: Style_Color_Role,
	text_role: Style_Color_Role,
	border_role: Style_Color_Role,
	focused_border_role: Style_Color_Role,
	focus_role: Style_Color_Role,
	selection_role: Style_Color_Role,
	caret_role: Style_Color_Role,
	hovered: Control_Part_Transform,
}

Text_Field_Visual_State :: struct {
	hovered: bool,
	focused: bool,
}

Text_Field_Resolved_Style :: struct {
	surface: Color,
	text: Color,
	border: Color,
	focus: Color,
	selection: Color,
	caret: Color,
	hovered: bool,
	focused: bool,
}

DEFAULT_TEXT_FIELD_RECIPE :: Text_Field_Recipe{
	defined=true,
	horizontal_inset=10,
	surface_role=.Surface,
	text_role=.Text,
	border_role=.Border,
	focused_border_role=.Focus,
	focus_role=.Focus,
	selection_role=.Selection,
	caret_role=.Accent,
	hovered=Control_Part_Transform{
		surface_role=.Subtle_Surface, surface_mix=0.12,
		border_role=.Muted_Text, border_mix=0.20,
	},
}

Style_Color_Transform :: struct {
	role: Style_Color_Role,
	mix: f32,
}

// Scrollbar_Recipe describes the track, moving thumb, and corner as separate
// semantic parts. It does not change track/thumb geometry, which is a layout
// and interaction contract owned by Scroll_Region.
Scrollbar_Recipe :: struct {
	defined: bool,
	track_role: Style_Color_Role,
	thumb_role: Style_Color_Role,
	corner_role: Style_Color_Role,
	hovered_thumb: Style_Color_Transform,
	pressed_thumb: Style_Color_Transform,
}

Scrollbar_Visual_State :: struct {
	hovered: bool,
	pressed: bool,
}

Scrollbar_Resolved_Style :: struct {
	track: Color,
	thumb: Color,
	corner: Color,
	hovered: bool,
	pressed: bool,
}

DEFAULT_SCROLLBAR_RECIPE :: Scrollbar_Recipe{
	defined=true,
	track_role=.Scrollbar_Track,
	thumb_role=.Scrollbar_Thumb,
	corner_role=.Surface,
	hovered_thumb=Style_Color_Transform{role=.Text, mix=0.14},
	pressed_thumb=Style_Color_Transform{role=.Accent, mix=0.22},
}

DEFAULT_CHECKBOX_RECIPE :: Checkbox_Recipe{
	defined=true,
	box=Control_Part_Recipe{
		surface_role=.Surface,
		text_role=.Text,
		border_role=.Accent,
		selected=Control_Part_Transform{
			surface_role=.Accent, surface_mix=0.82,
			border_role=.Accent_Hover, border_mix=0.42,
		},
		hovered=Control_Part_Transform{
			surface_role=.Subtle_Surface, surface_mix=0.16,
			border_role=.Accent_Hover, border_mix=0.28,
		},
		pressed=Control_Part_Transform{
			surface_role=.Accent_Pressed, surface_mix=0.24,
			border_role=.Accent_Pressed, border_mix=0.45,
		},
		disabled=Control_Part_Transform{
			surface_role=.Window_Background, surface_mix=0.58,
			border_role=.Muted_Text, border_mix=0.52,
		},
	},
	checkmark=Control_Part_Recipe{
		surface_role=.Accent_Text,
		text_role=.Text,
		border_role=.Accent_Text,
		selected=Control_Part_Transform{text_role=.Accent_Text, text_mix=1},
		disabled=Control_Part_Transform{text_role=.Muted_Text, text_mix=0.40},
	},
	label=Control_Part_Recipe{
		surface_role=.Surface,
		text_role=.Text,
		border_role=.Border,
		disabled=Control_Part_Transform{text_role=.Muted_Text, text_mix=1},
	},
	focus_role=.Focus,
	focus_indicator_mode=.Always,
}

DEFAULT_SLIDER_RECIPE :: Slider_Recipe{
	defined=true,
	track=Control_Part_Recipe{
		surface_role=.Border,
		text_role=.Muted_Text,
		border_role=.Border,
		disabled=Control_Part_Transform{surface_role=.Window_Background, surface_mix=0.45},
	},
	fill=Control_Part_Recipe{
		surface_role=.Accent,
		text_role=.Accent_Text,
		border_role=.Accent,
		hovered=Control_Part_Transform{surface_role=.Accent_Hover, surface_mix=0.18},
		pressed=Control_Part_Transform{surface_role=.Accent_Pressed, surface_mix=0.38},
		disabled=Control_Part_Transform{surface_role=.Muted_Text, surface_mix=0.54},
	},
	thumb=Control_Part_Recipe{
		surface_role=.Text,
		text_role=.Text,
		border_role=.Border,
		hovered=Control_Part_Transform{surface_role=.Accent_Hover, surface_mix=0.20},
		pressed=Control_Part_Transform{
			surface_role=.Accent_Pressed, surface_mix=0.40,
			border_role=.Accent_Pressed, border_mix=0.50,
		},
		disabled=Control_Part_Transform{
			surface_role=.Muted_Text, surface_mix=0.48,
			border_role=.Muted_Text, border_mix=0.68,
		},
	},
	label=Control_Part_Recipe{
		surface_role=.Surface,
		text_role=.Text,
		border_role=.Border,
		disabled=Control_Part_Transform{text_role=.Muted_Text, text_mix=1},
	},
	focus_role=.Focus,
	focus_indicator_mode=.Always,
}

style_checkbox_recipe :: proc(rt: ^Runtime, environment: Style_Environment) -> Checkbox_Recipe {
	if rt != nil {
		index := u64(u32(environment.theme))
		if index > 0 && index <= u64(len(rt.style_themes)) {
			recipe := rt.style_themes[index-1].checkbox_recipe
			if recipe.defined && style_checkbox_recipe_is_valid(recipe) { return recipe }
		}
	}
	return DEFAULT_CHECKBOX_RECIPE
}

style_slider_recipe :: proc(rt: ^Runtime, environment: Style_Environment) -> Slider_Recipe {
	if rt != nil {
		index := u64(u32(environment.theme))
		if index > 0 && index <= u64(len(rt.style_themes)) {
			recipe := rt.style_themes[index-1].slider_recipe
			if recipe.defined && style_slider_recipe_is_valid(recipe) { return recipe }
		}
	}
	return DEFAULT_SLIDER_RECIPE
}

style_text_field_recipe :: proc(rt: ^Runtime, environment: Style_Environment) -> Text_Field_Recipe {
	if rt != nil {
		index := u64(u32(environment.theme))
		if index > 0 && index <= u64(len(rt.style_themes)) {
			recipe := rt.style_themes[index-1].text_field_recipe
			if recipe.defined && style_text_field_recipe_is_valid(recipe) { return recipe }
		}
	}
	return DEFAULT_TEXT_FIELD_RECIPE
}

// style_text_field_horizontal_inset resolves the theme-provided logical inset
// and applies environment density once. Callers use this same value for text
// shaping, painting, pointer geometry, and native input positioning.
style_text_field_horizontal_inset :: proc(rt: ^Runtime, environment: Style_Environment) -> f32 {
	recipe := style_text_field_recipe(rt, environment)
	density := environment.density
	if !(density > 0) || !(density < 100) { density = 1 }
	return recipe.horizontal_inset * density
}

style_scrollbar_recipe :: proc(rt: ^Runtime, environment: Style_Environment) -> Scrollbar_Recipe {
	if rt != nil {
		index := u64(u32(environment.theme))
		if index > 0 && index <= u64(len(rt.style_themes)) {
			recipe := rt.style_themes[index-1].scrollbar_recipe
			if recipe.defined && style_scrollbar_recipe_is_valid(recipe) { return recipe }
		}
	}
	return DEFAULT_SCROLLBAR_RECIPE
}

style_control_part_recipe_is_valid :: proc(recipe: Control_Part_Recipe) -> bool {
	return style_color_role_is_valid(recipe.surface_role) &&
	       style_color_role_is_valid(recipe.text_role) &&
	       style_color_role_is_valid(recipe.border_role) &&
	       control_part_transform_is_valid(recipe.selected) &&
	       control_part_transform_is_valid(recipe.hovered) &&
	       control_part_transform_is_valid(recipe.pressed) &&
	       control_part_transform_is_valid(recipe.disabled)
}

style_checkbox_recipe_is_valid :: proc(recipe: Checkbox_Recipe) -> bool {
	if !recipe.defined { return true }
	return style_control_part_recipe_is_valid(recipe.box) &&
	       style_control_part_recipe_is_valid(recipe.checkmark) &&
	       style_control_part_recipe_is_valid(recipe.label) &&
	       style_color_role_is_valid(recipe.focus_role) &&
	       (recipe.focus_indicator_mode == .Always || recipe.focus_indicator_mode == .Keyboard_Only)
}

style_slider_recipe_is_valid :: proc(recipe: Slider_Recipe) -> bool {
	if !recipe.defined { return true }
	return style_control_part_recipe_is_valid(recipe.track) &&
	       style_control_part_recipe_is_valid(recipe.fill) &&
	       style_control_part_recipe_is_valid(recipe.thumb) &&
	       style_control_part_recipe_is_valid(recipe.label) &&
	       style_color_role_is_valid(recipe.focus_role) &&
	       (recipe.focus_indicator_mode == .Always || recipe.focus_indicator_mode == .Keyboard_Only)
}

control_part_transform_is_valid :: proc(transform: Control_Part_Transform) -> bool {
	return style_color_role_is_valid(transform.surface_role) &&
	       transform.surface_mix == transform.surface_mix && transform.surface_mix >= 0 && transform.surface_mix <= 1 &&
	       style_color_role_is_valid(transform.text_role) &&
	       transform.text_mix == transform.text_mix && transform.text_mix >= 0 && transform.text_mix <= 1 &&
	       style_color_role_is_valid(transform.border_role) &&
	       transform.border_mix == transform.border_mix && transform.border_mix >= 0 && transform.border_mix <= 1
}

style_text_field_recipe_is_valid :: proc(recipe: Text_Field_Recipe) -> bool {
	if !recipe.defined { return true }
	return recipe.horizontal_inset == recipe.horizontal_inset && recipe.horizontal_inset >= 0 && recipe.horizontal_inset <= 10000 &&
	       style_color_role_is_valid(recipe.surface_role) &&
	       style_color_role_is_valid(recipe.text_role) &&
	       style_color_role_is_valid(recipe.border_role) &&
	       style_color_role_is_valid(recipe.focused_border_role) &&
	       style_color_role_is_valid(recipe.focus_role) &&
	       style_color_role_is_valid(recipe.selection_role) &&
	       style_color_role_is_valid(recipe.caret_role) &&
	       control_part_transform_is_valid(recipe.hovered)
}

style_scrollbar_recipe_is_valid :: proc(recipe: Scrollbar_Recipe) -> bool {
	if !recipe.defined { return true }
	return style_color_role_is_valid(recipe.track_role) &&
	       style_color_role_is_valid(recipe.thumb_role) &&
	       style_color_role_is_valid(recipe.corner_role) &&
	       style_color_transform_is_valid(recipe.hovered_thumb) &&
	       style_color_transform_is_valid(recipe.pressed_thumb)
}

style_color_transform_is_valid :: proc(transform: Style_Color_Transform) -> bool {
	return style_color_role_is_valid(transform.role) &&
	       transform.mix == transform.mix && transform.mix >= 0 && transform.mix <= 1
}

control_part_transform_apply :: proc(
	transform: Control_Part_Transform,
	surface, text, border: ^Color,
	rt: ^Runtime,
	environment: Style_Environment,
) {
	if surface == nil || text == nil || border == nil { return }
	if transform.surface_mix > 0 {
		target := style_environment_color(rt, environment, transform.surface_role)
		surface^ = style_color_mix(surface^, target, transform.surface_mix)
	}
	if transform.text_mix > 0 {
		target := style_environment_color(rt, environment, transform.text_role)
		text^ = style_color_mix(text^, target, transform.text_mix)
	}
	if transform.border_mix > 0 {
		target := style_environment_color(rt, environment, transform.border_role)
		border^ = style_color_mix(border^, target, transform.border_mix)
	}
}

style_control_part_resolve :: proc(
	rt: ^Runtime,
	environment: Style_Environment,
	recipe: Control_Part_Recipe,
	state: Control_Visual_State,
) -> Control_Part_Resolved_Style {
	style := Control_Part_Resolved_Style{
		surface=style_environment_color(rt, environment, recipe.surface_role),
		text=style_environment_color(rt, environment, recipe.text_role),
		border=style_environment_color(rt, environment, recipe.border_role),
	}
	if state.selected { control_part_transform_apply(recipe.selected, &style.surface, &style.text, &style.border, rt, environment) }
	if state.hovered { control_part_transform_apply(recipe.hovered, &style.surface, &style.text, &style.border, rt, environment) }
	if state.pressed { control_part_transform_apply(recipe.pressed, &style.surface, &style.text, &style.border, rt, environment) }
	if state.disabled { control_part_transform_apply(recipe.disabled, &style.surface, &style.text, &style.border, rt, environment) }
	return style
}

style_checkbox_resolve :: proc(
	rt: ^Runtime,
	environment: Style_Environment,
	recipe: Checkbox_Recipe,
	state: Checkbox_Visual_State,
) -> Checkbox_Resolved_Style {
	resolved_recipe := recipe
	if !resolved_recipe.defined || !style_checkbox_recipe_is_valid(resolved_recipe) { resolved_recipe = DEFAULT_CHECKBOX_RECIPE }
	part_state := Control_Visual_State{
		selected=state.checked,
		hovered=state.hovered,
		pressed=state.pressed,
		disabled=state.disabled,
	}
	style := Checkbox_Resolved_Style{
		box=style_control_part_resolve(rt, environment, resolved_recipe.box, part_state),
		checkmark=style_control_part_resolve(rt, environment, resolved_recipe.checkmark, part_state),
		label=style_control_part_resolve(rt, environment, resolved_recipe.label, part_state),
		focus=style_environment_color(rt, environment, resolved_recipe.focus_role),
		checked=state.checked,
		hovered=state.hovered,
		pressed=state.pressed,
		disabled=state.disabled,
		focused=state.focused,
		focus_indicator_mode=resolved_recipe.focus_indicator_mode,
	}
	if environment.accessibility.increased_contrast {
		border_role := Style_Color_Role.Border
		if state.checked { border_role = .Focus }
		style.box.border = style_environment_color(rt, environment, border_role)
		style.box.border = style_contrast_fallback(style.box.border, style.box.surface, 3)
		style.checkmark.text = style_contrast_fallback(style.checkmark.text, style.box.surface, 4.5)
		style.label.text = style_contrast_fallback(style.label.text, style.label.surface, 4.5)
		style.focus = style_contrast_fallback(style.focus, style.box.surface, 3)
	}
	if state.checked { style.applied_transforms += {.Selected} }
	if state.hovered { style.applied_transforms += {.Hovered} }
	if state.pressed { style.applied_transforms += {.Pressed} }
	if state.disabled { style.applied_transforms += {.Disabled} }
	return style
}

style_slider_resolve :: proc(
	rt: ^Runtime,
	environment: Style_Environment,
	recipe: Slider_Recipe,
	state: Slider_Visual_State,
) -> Slider_Resolved_Style {
	resolved_recipe := recipe
	if !resolved_recipe.defined || !style_slider_recipe_is_valid(resolved_recipe) { resolved_recipe = DEFAULT_SLIDER_RECIPE }
	part_state := Control_Visual_State{hovered=state.hovered, pressed=state.pressed, disabled=state.disabled}
	style := Slider_Resolved_Style{
		track=style_control_part_resolve(rt, environment, resolved_recipe.track, part_state),
		fill=style_control_part_resolve(rt, environment, resolved_recipe.fill, part_state),
		thumb=style_control_part_resolve(rt, environment, resolved_recipe.thumb, part_state),
		label=style_control_part_resolve(rt, environment, resolved_recipe.label, part_state),
		focus=style_environment_color(rt, environment, resolved_recipe.focus_role),
		hovered=state.hovered,
		pressed=state.pressed,
		disabled=state.disabled,
		focused=state.focused,
		focus_indicator_mode=resolved_recipe.focus_indicator_mode,
	}
	if environment.accessibility.increased_contrast {
		// The thumb is the value's non-color position marker; a stronger outline
		// keeps it distinct from the filled track on low-contrast themes.
		style.thumb.border = style_environment_color(rt, environment, .Focus)
		style.thumb.border = style_contrast_fallback(style.thumb.border, style.thumb.surface, 3)
		style.label.text = style_contrast_fallback(style.label.text, style.label.surface, 4.5)
		style.focus = style_contrast_fallback(style.focus, style.thumb.surface, 3)
	}
	if state.hovered { style.applied_transforms += {.Hovered} }
	if state.pressed { style.applied_transforms += {.Pressed} }
	if state.disabled { style.applied_transforms += {.Disabled} }
	return style
}

style_text_field_resolve :: proc(
	rt: ^Runtime,
	environment: Style_Environment,
	recipe: Text_Field_Recipe,
	state: Text_Field_Visual_State,
) -> Text_Field_Resolved_Style {
	resolved_recipe := recipe
	if !style_text_field_recipe_is_valid(resolved_recipe) || !resolved_recipe.defined {
		resolved_recipe = DEFAULT_TEXT_FIELD_RECIPE
	}
	style := Text_Field_Resolved_Style{
		surface=style_environment_color(rt, environment, resolved_recipe.surface_role),
		text=style_environment_color(rt, environment, resolved_recipe.text_role),
		border=style_environment_color(rt, environment, resolved_recipe.border_role),
		focus=style_environment_color(rt, environment, resolved_recipe.focus_role),
		selection=style_environment_color(rt, environment, resolved_recipe.selection_role),
		caret=style_environment_color(rt, environment, resolved_recipe.caret_role),
		hovered=state.hovered,
		focused=state.focused,
	}
	if state.hovered { control_part_transform_apply(resolved_recipe.hovered, &style.surface, &style.text, &style.border, rt, environment) }
	if state.focused {
		style.border = style_environment_color(rt, environment, resolved_recipe.focused_border_role)
	}
	if environment.accessibility.increased_contrast {
		style.text = style_contrast_fallback(style.text, style.surface, 4.5)
		style.border = style_contrast_fallback(style.border, style.surface, 3)
		style.focus = style_contrast_fallback(style.focus, style.surface, 3)
	}
	return style
}

scrollbar_part_transform_apply :: proc(color: Color, transform: Style_Color_Transform, rt: ^Runtime, environment: Style_Environment) -> Color {
	if transform.mix <= 0 { return color }
	return style_color_mix(color, style_environment_color(rt, environment, transform.role), transform.mix)
}

style_scrollbar_resolve :: proc(
	rt: ^Runtime,
	environment: Style_Environment,
	recipe: Scrollbar_Recipe,
	state: Scrollbar_Visual_State,
) -> Scrollbar_Resolved_Style {
	resolved_recipe := recipe
	if !style_scrollbar_recipe_is_valid(resolved_recipe) || !resolved_recipe.defined {
		resolved_recipe = DEFAULT_SCROLLBAR_RECIPE
	}
	style := Scrollbar_Resolved_Style{
		track=style_environment_color(rt, environment, resolved_recipe.track_role),
		thumb=style_environment_color(rt, environment, resolved_recipe.thumb_role),
		corner=style_environment_color(rt, environment, resolved_recipe.corner_role),
		hovered=state.hovered,
		pressed=state.pressed,
	}
	if state.hovered { style.thumb = scrollbar_part_transform_apply(style.thumb, resolved_recipe.hovered_thumb, rt, environment) }
	if state.pressed { style.thumb = scrollbar_part_transform_apply(style.thumb, resolved_recipe.pressed_thumb, rt, environment) }
	return style
}
