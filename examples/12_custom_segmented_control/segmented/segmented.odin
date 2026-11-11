package segmented

// Segmented is a third-party control built only from Alicorn's public
// interaction, layout, semantic-surface, visual-part, semantic, theme-role,
// and motion interfaces. The Button owns hit testing, keyboard focus and
// activation, while Button_Presentation.Custom leaves all visible pixels to
// this package.

import alicorn "alicorn:runtime"
import ui "alicorn:ui"

Choice :: enum { Preview, Edit, Compare }

Segmented_State :: struct {
	selected: Choice,
	disabled: [3]bool,
}

Recipe :: struct {
	track_role:    alicorn.Style_Extension_Color_Role_ID,
	idle_role:     alicorn.Style_Extension_Color_Role_ID,
	selected_role: alicorn.Style_Extension_Color_Role_ID,
	accent_role:   alicorn.Style_Extension_Color_Role_ID,
	focus_role:    alicorn.Style_Extension_Color_Role_ID,
	hover_role:    alicorn.Style_Extension_Color_Role_ID,
	disabled_role: alicorn.Style_Extension_Color_Role_ID,
	wide_minimum:  f32,
}

// Style is deliberately component-owned: an application can give one
// instance a distinct accent and geometry without cloning the recipe.
Style :: struct {
	instance_accent_role: alicorn.Style_Extension_Color_Role_ID,
	track_height:         f32,
	track_radius:         f32,
	segment_radius:       f32,
	segment_padding:      f32,
	focus_inset:          f32,
	segment_height:       f32,
	compact_height:       f32,
	marker_width:         f32,
	marker_height:        f32,
	label_size:           f32,
}

Theme_Role_Requirement :: struct {
	role: alicorn.Style_Extension_Color_Role_ID,
	name: string,
}

Theme_Contract :: struct {
	required: [7]Theme_Role_Requirement,
	optional: [1]Theme_Role_Requirement,
}

Theme_Contract_Report :: struct {
	required_available: [7]bool,
	optional_available: [1]bool,
}

Choice_Labels :: [3]string{"Preview", "Edit", "Compare"}

Semantic_Namespace :: u64(0x4F52424954534547)
MAX_SEMANTIC_INSTANCE_ID :: u64(0x3FFFFFFFFFFFFFFF)

recipe_default :: proc() -> Recipe {
	return Recipe{
		track_role=alicorn.style_extension_color_role_id("vendor.orbit", "segmented.track"),
		idle_role=alicorn.style_extension_color_role_id("vendor.orbit", "segmented.idle"),
		selected_role=alicorn.style_extension_color_role_id("vendor.orbit", "segmented.selected"),
		accent_role=alicorn.style_extension_color_role_id("vendor.orbit", "segmented.accent"),
		focus_role=alicorn.style_extension_color_role_id("vendor.orbit", "segmented.focus"),
		hover_role=alicorn.style_extension_color_role_id("vendor.orbit", "segmented.hover"),
		disabled_role=alicorn.style_extension_color_role_id("vendor.orbit", "segmented.disabled"),
		wide_minimum=470,
	}
}

style_default :: proc() -> Style {
	return Style{
		track_height=208,
		track_radius=20,
		segment_radius=12,
		segment_padding=4,
		focus_inset=2,
		segment_height=58,
		compact_height=46,
		marker_width=24,
		marker_height=4,
		label_size=16,
	}
}

theme_contract_default :: proc(recipe: Recipe, instance_accent_role: alicorn.Style_Extension_Color_Role_ID = 0) -> Theme_Contract {
	return Theme_Contract{
		required={
			{recipe.track_role, "vendor.orbit.segmented.track"},
			{recipe.idle_role, "vendor.orbit.segmented.idle"},
			{recipe.selected_role, "vendor.orbit.segmented.selected"},
			{recipe.accent_role, "vendor.orbit.segmented.accent"},
			{recipe.focus_role, "vendor.orbit.segmented.focus"},
			{recipe.hover_role, "vendor.orbit.segmented.hover"},
			{recipe.disabled_role, "vendor.orbit.segmented.disabled"},
		},
		optional={{instance_accent_role, "per-instance accent override"}},
	}
}

theme_contract_check :: proc(
	rt: ^alicorn.Runtime,
	theme: alicorn.Style_Theme_ID,
	contract: Theme_Contract,
) -> Theme_Contract_Report {
	report := Theme_Contract_Report{}
	for requirement, index in contract.required {
		_, report.required_available[index] = alicorn.style_extension_color(rt, theme, requirement.role)
	}
	for requirement, index in contract.optional {
		if requirement.role == 0 {
			report.optional_available[index] = true
		} else {
			_, report.optional_available[index] = alicorn.style_extension_color(rt, theme, requirement.role)
		}
	}
	return report
}

theme_contract_satisfied :: proc(report: Theme_Contract_Report) -> bool {
	for available in report.required_available { if !available { return false } }
	return true
}

theme_contract_missing_required :: proc(contract: Theme_Contract, report: Theme_Contract_Report) -> (missing: [7]string, count: int) {
	for requirement, index in contract.required {
		if !report.required_available[index] {
			missing[count] = requirement.name
			count += 1
		}
	}
	return
}

semantic_id :: proc(instance_id: u64, choice: Choice) -> alicorn.Semantic_ID {
	index := int(choice)
	if instance_id == 0 || instance_id > MAX_SEMANTIC_INSTANCE_ID || index < 0 || index >= len(Choice_Labels) {
		return {}
	}
	return alicorn.Semantic_ID{namespace=Semantic_Namespace, value=(instance_id << 2) | u64(index+1)}
}

semantic_group_id :: proc(instance_id: u64) -> alicorn.Semantic_ID {
	if instance_id == 0 || instance_id > MAX_SEMANTIC_INSTANCE_ID { return {} }
	return alicorn.Semantic_ID{namespace=Semantic_Namespace, value=instance_id << 2}
}

choice_label :: proc(choice: Choice) -> string {
	switch choice {
	case .Preview: return "Preview"
	case .Edit: return "Edit"
	case .Compare: return "Compare"
	}
	return "Unknown"
}

choice_description :: proc(choice: Choice) -> string {
	switch choice {
	case .Preview: return "Inspect the result without changing source."
	case .Edit: return "Make changes in the active document."
	case .Compare: return "Show the original and edited result together."
	}
	return ""
}

render_option :: proc(
	ctx: ^ui.UI,
	state: ^Segmented_State,
	recipe: Recipe,
	style: Style,
	choice: Choice,
	instance_id: u64,
	compact: bool,
	key: ui.UI_Key,
) -> bool {
	activated := false
	index := int(choice)
	if index < 0 || index >= len(Choice_Labels) { return false }
	if ui.key_scope(ctx, key) {

		selected := state.selected == choice
		disabled := state.disabled[index]
		label := choice_label(choice)
		button_height := style.segment_height if !compact else style.compact_height
		button_grow: f32 = 1 if !compact else 0
		owner, clicked := alicorn.button_begin(
			ctx,
			label,
			key=ui.key_u64(1),
			style=ui.layout_style(.Column, width=-1, height=button_height, grow=button_grow),
			state=alicorn.Button_State{selected=selected, disabled=disabled},
			content_style=alicorn.button_content_style(padding_x=0, padding_y=0),
			presentation=.Custom,
		)
		if owner == 0 {
			return false
		}
		activated = clicked
		_ = alicorn.semantic_augment(ctx, description=choice_description(choice))
		_ = alicorn.semantic_bind(ctx, semantic_id(instance_id, choice))
		if clicked {
			state.selected = choice
			selected = true
		}

		// This retained frame appears only for keyboard-visible focus. Its inset
		// remains in layout in every state, so focus never moves the label.
		frame := alicorn.surface_begin(
			ctx,
			alicorn.surface_extension_color_role(recipe.focus_role),
			key=ui.key_u64(2),
			style=ui.layout_style(.Column, width=-1, height=button_height, padding=style.focus_inset),
			shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=style.segment_radius+style.focus_inset},
			label="segmented-focus-frame",
		)
		if frame != 0 {
			_ = alicorn.visual_part_attach(ctx, frame, owner, alicorn.visual_part_core(.Focus_Indicator), .Owner_Focus_Visible)

			face_role := recipe.idle_role
			if selected && !disabled { face_role = recipe.selected_role }
			if disabled { face_role = recipe.disabled_role }
			face_height := button_height-2*style.focus_inset
			if face_height < 1 { face_height = 1 }
			face := alicorn.surface_begin(
				ctx,
				alicorn.surface_extension_color_role(face_role),
				key=ui.key_u64(3),
				style=ui.layout_style(.Column, width=-1, height=face_height, padding=style.segment_padding, gap=1,
					align=.Center, justify=.Center),
				shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=style.segment_radius},
				label="segmented-option-face",
			)
			if face != 0 {
				_ = alicorn.visual_part_attach(ctx, face, owner, alicorn.visual_part_core(.Surface))

				text_style := alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_MEDIUM, font_size=style.label_size}
				if selected { text_style.font_weight = alicorn.FONT_WEIGHT_SEMIBOLD }
				label_color := alicorn.style_color(ctx, .Text)
				if disabled { label_color = alicorn.style_color(ctx, .Muted_Text) }
				label_line_height := style.label_size*1.5
				if label_line_height < 24 { label_line_height = 24 }
				if ui.row(ctx, key=ui.key_u64(7), width=-1, height=label_line_height,
					align=.Center, justify=.Center, label="segmented-option-label-line") {
					// Equal fixed gutters keep the label centered on the segment
					// whether the leading hover accent is visible or not.
					if ui.column(ctx, key=ui.key_u64(8), width=16, height=label_line_height,
						align=.Center, justify=.Center, label="segmented-leading-gutter") {
						if !disabled {
							hover := alicorn.surface_begin(
								ctx,
								alicorn.surface_extension_color_role(recipe.hover_role),
								key=ui.key_u64(4),
								style=ui.layout_style(.Row, width=3, height=16),
								shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=1.5},
								label="segmented-hover-cue",
							)
							if hover != 0 {
								_ = alicorn.visual_part_attach(ctx, hover, owner, alicorn.visual_part_core(.Overlay), .Owner_Hovered)
								alicorn.surface_end(ctx)
							}
						}
					}
					label_id := ui.text(ctx, label, key=ui.key_u64(5),
						size=style.label_size, color=label_color,
						style=ui.layout_style(.Row, height=label_line_height),
						text_style=text_style, decorative=true)
					if label_id != 0 {
						_ = alicorn.visual_part_attach(ctx, label_id, owner, alicorn.visual_part_core(.Label))
					}
					if ui.column(ctx, key=ui.key_u64(9), width=16, height=label_line_height,
						label="segmented-trailing-gutter") {}
				}
				if disabled {
					ui.text(ctx, "Unavailable", key=ui.key_u64(10), size=11,
						color=alicorn.style_color(ctx, .Muted_Text),
						style=ui.layout_style(.Row, height=14),
						text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_MEDIUM}, decorative=true)
				}

				marker_role := recipe.accent_role
				if style.instance_accent_role != 0 { marker_role = style.instance_accent_role }
				marker_width := style.marker_width
				marker_height := style.marker_height
				opacity: f64 = 0.18
				offset_y: f64 = 1
				if selected && !disabled {
					opacity = 1
					offset_y = 0
				}
				if disabled { opacity = 0.08 }
				marker := alicorn.surface_begin(
					ctx,
					alicorn.surface_extension_color_role(marker_role),
					key=ui.key_u64(6),
					style=ui.layout_style(.Row, width=marker_width, height=marker_height),
					shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=marker_height*0.5},
					label="segmented-selection-marker",
				)
				if marker != 0 {
					_ = alicorn.visual_part_attach(ctx, marker, owner, alicorn.visual_part_core(.Selected_Indicator))
					_ = ui.motion(ctx, marker, ui.Motion_Target{
						opacity=opacity,
						translation=ui.Motion_Vector2{0, offset_y},
						has_opacity=true,
						has_translation=true,
					})
					alicorn.surface_end(ctx)
				}
				alicorn.surface_end(ctx)
			}
			alicorn.surface_end(ctx)
		}
		alicorn.button_end(ctx)
		return activated
	}
	return false
}

// segmented_control returns whether an option was activated. Selection remains
// application-owned, while the same semantic IDs survive its responsive
// horizontal and compact presentations.
segmented_control :: proc(
	ctx: ^ui.UI,
	label: string,
	state: ^Segmented_State,
	recipe: Recipe,
	style: Style,
	key: ui.UI_Key,
	instance_id: u64,
) -> bool {
	if ctx == nil || state == nil || instance_id == 0 || instance_id > MAX_SEMANTIC_INSTANCE_ID ||
		recipe.track_role == 0 || recipe.idle_role == 0 || recipe.selected_role == 0 ||
		recipe.accent_role == 0 || recipe.focus_role == 0 || recipe.hover_role == 0 ||
		recipe.disabled_role == 0 || recipe.wide_minimum <= 0 {
		return false
	}
	changed := false
	adaptive_height := style.segment_height
	if compact_height := style.compact_height*3+10; compact_height > adaptive_height { adaptive_height = compact_height }
	if ui.key_scope(ctx, key) {
		track := alicorn.surface_begin(
			ctx,
			alicorn.surface_extension_color_role(recipe.track_role),
			key=ui.key_u64(1),
			style=ui.layout_style(.Column, width=-1, height=style.track_height, grow=1, padding=12, gap=8),
			shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=style.track_radius},
			label=label,
		)
		if track == 0 { return false }
		_ = alicorn.semantic_description(ctx, .Group, label,
			description="Three-way segmented choice. Keyboard focus and activation use Alicorn Button behavior.",
			value=choice_label(state.selected))
		_ = alicorn.semantic_bind(ctx, semantic_group_id(instance_id))
		ui.text(ctx, label, key=ui.key_u64(2), size=14, decorative=true,
			text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_SEMIBOLD})

		adaptive := alicorn.adaptive_begin(
			ctx,
			key=ui.key_u64(3),
			style=ui.layout_style(.Column, width=-1, height=adaptive_height),
			label="segmented-responsive-presentation",
		)
		if adaptive != 0 {
			wide := alicorn.adaptive_alternative_begin(
				ctx,
				key=ui.key_u64(4),
				name="horizontal segmented choices",
				minimum_width=recipe.wide_minimum,
				style=ui.layout_style(.Row, width=-1, height=adaptive_height, align=.Center, justify=.Center, gap=8),
			)
			if wide != 0 {
				for choice in Choice {
					changed = render_option(ctx, state, recipe, style, choice, instance_id, false,
						ui.key_pair(10, u64(choice)+1)) || changed
				}
			}
			alicorn.adaptive_alternative_end(ctx)

			compact := alicorn.adaptive_alternative_begin(
				ctx,
				key=ui.key_u64(5),
				name="vertical segmented choices",
				style=ui.layout_style(.Column, width=-1, height=adaptive_height, gap=5),
			)
			if compact != 0 {
				for choice in Choice {
					changed = render_option(ctx, state, recipe, style, choice, instance_id, true,
						ui.key_pair(20, u64(choice)+1)) || changed
				}
			}
			alicorn.adaptive_alternative_end(ctx)
			alicorn.adaptive_end(ctx)
		}
		alicorn.surface_end(ctx)
		return changed
	}
	return false
}
