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

Text_Field_Recipe :: struct {
	defined: bool,
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
	return style_color_role_is_valid(recipe.surface_role) &&
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
	style: ^Text_Field_Resolved_Style,
	rt: ^Runtime,
	environment: Style_Environment,
) {
	if transform.surface_mix > 0 {
		target := style_environment_color(rt, environment, transform.surface_role)
		style.surface = style_color_mix(style.surface, target, transform.surface_mix)
	}
	if transform.text_mix > 0 {
		target := style_environment_color(rt, environment, transform.text_role)
		style.text = style_color_mix(style.text, target, transform.text_mix)
	}
	if transform.border_mix > 0 {
		target := style_environment_color(rt, environment, transform.border_role)
		style.border = style_color_mix(style.border, target, transform.border_mix)
	}
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
	if state.hovered { control_part_transform_apply(resolved_recipe.hovered, &style, rt, environment) }
	if state.focused {
		style.border = style_environment_color(rt, environment, resolved_recipe.focused_border_role)
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
