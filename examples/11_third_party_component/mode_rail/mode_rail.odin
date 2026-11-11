package mode_rail

// Mode Rail is an example third-party compound control. It uses only public
// ui and runtime interfaces: no Runtime fields, private layout records, or
// native renderer access. The application owns state; this package owns its
// recipe, theme contract, adaptive presentation, and per-instance options.

import alicorn "alicorn:runtime"
import ui "alicorn:ui"

Mode :: enum { Calm, Balanced, Urgent }
Tone :: enum { Standard, Attention }

Mode_Rail_Semantic_Namespace :: u64(0x41434D454D4F4445)
MAX_SEMANTIC_INSTANCE_ID :: u64(0x3FFFFFFFFFFFFFFF)

mode_rail_max :: proc(a, b: f32) -> f32 { return a if a > b else b }
mode_rail_min :: proc(a, b: f32) -> f32 { return a if a < b else b }

State :: struct {
	selected: Mode,
	disabled: [3]bool,
}

// Recipe declares the extension roles this component consumes. Required roles
// are container, option, and signal. Attention is optional and falls back to
// signal when a consumer's theme omits it.
Recipe :: struct {
	container_role: alicorn.Style_Extension_Color_Role_ID,
	option_role:    alicorn.Style_Extension_Color_Role_ID,
	signal_role:    alicorn.Style_Extension_Color_Role_ID,
	attention_role: alicorn.Style_Extension_Color_Role_ID,
	wide_minimum:   f32,
}

// Instance_Overrides customizes one instance without cloning Recipe. Zero
// means inherit the component's default. indicator_role is an optional theme
// dependency and should be checked with theme_contract_check at setup time.
Instance_Overrides :: struct {
	indicator_role: alicorn.Style_Extension_Color_Role_ID,
	container_height: f32,
	container_padding: f32,
	container_corner_radius: f32,
	option_corner_radius: f32,
	option_button_height: f32,
	indicator_width: f32,
	indicator_height: f32,
	indicator_corner_radius: f32,
	label_size: f32,
	detail_size: f32,
}

Theme_Role_Requirement :: struct {
	role: alicorn.Style_Extension_Color_Role_ID,
	name: string,
}

Theme_Contract :: struct {
	required: [3]Theme_Role_Requirement,
	optional: [2]Theme_Role_Requirement,
}

Theme_Contract_Report :: struct {
	required_available: [3]bool,
	optional_available: [2]bool,
}

OPTION_LABELS: [3]string = {"Calm", "Balanced", "Urgent"}
OPTION_DETAILS: [3]string = {
	"Quiet, low-interruption updates.",
	"Steady updates with balanced attention.",
	"Prominent updates for time-sensitive work.",
}

recipe_default :: proc() -> Recipe {
	return Recipe{
		container_role=alicorn.style_extension_color_role_id("vendor.acme", "mode_rail.container"),
		option_role=alicorn.style_extension_color_role_id("vendor.acme", "mode_rail.option"),
		signal_role=alicorn.style_extension_color_role_id("vendor.acme", "mode_rail.signal"),
		attention_role=alicorn.style_extension_color_role_id("vendor.acme", "mode_rail.attention"),
		wide_minimum=520,
	}
}

theme_contract_default :: proc(recipe: Recipe, instance_indicator_role: alicorn.Style_Extension_Color_Role_ID = 0) -> Theme_Contract {
	return Theme_Contract{
		required={
			{role=recipe.container_role, name="vendor.acme.mode_rail.container"},
			{role=recipe.option_role, name="vendor.acme.mode_rail.option"},
			{role=recipe.signal_role, name="vendor.acme.mode_rail.signal"},
		},
		optional={
			{role=recipe.attention_role, name="vendor.acme.mode_rail.attention"},
			{role=instance_indicator_role, name="instance indicator override"},
		},
	}
}

// theme_contract_check is intended for setup/theme replacement, not a render
// loop. A missing required role prevents rendering. Missing optional roles
// leave their corresponding role unset so the component can use its fallback.
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

theme_contract_missing_required :: proc(contract: Theme_Contract, report: Theme_Contract_Report) -> (missing: [3]string, count: int) {
	for requirement, index in contract.required {
		if !report.required_available[index] {
			missing[count] = requirement.name
			count += 1
		}
	}
	return
}

semantic_id_for_instance :: proc(instance_id: u64, mode: Mode) -> alicorn.Semantic_ID {
	if instance_id == 0 || instance_id > MAX_SEMANTIC_INSTANCE_ID { return {} }
	index := int(mode)
	if index < 0 || index >= len(OPTION_LABELS) { return {} }
	return alicorn.Semantic_ID{
		namespace=Mode_Rail_Semantic_Namespace,
		value=(instance_id << 2) | u64(index+1),
	}
}

semantic_group_id_for_instance :: proc(instance_id: u64) -> alicorn.Semantic_ID {
	if instance_id == 0 || instance_id > MAX_SEMANTIC_INSTANCE_ID { return {} }
	return alicorn.Semantic_ID{namespace=Mode_Rail_Semantic_Namespace, value=instance_id << 2}
}

option_name :: proc(mode: Mode) -> string {
	index := int(mode)
	if index < 0 || index >= len(OPTION_LABELS) { return OPTION_LABELS[int(Mode.Balanced)] }
	return OPTION_LABELS[index]
}

option_indicator_role :: proc(recipe: Recipe, tone: Tone, selected: bool, overrides: Instance_Overrides) -> alicorn.Style_Extension_Color_Role_ID {
	if overrides.indicator_role != 0 { return overrides.indicator_role }
	if tone == .Attention && selected && recipe.attention_role != 0 { return recipe.attention_role }
	return recipe.signal_role
}

Resolved_Instance_Style :: struct {
	container_height: f32,
	container_padding: f32,
	container_corner_radius: f32,
	option_corner_radius: f32,
	option_button_height: f32,
	indicator_width: f32,
	indicator_height: f32,
	indicator_corner_radius: f32,
	label_size: f32,
	detail_size: f32,
}

instance_style_resolve :: proc(overrides: Instance_Overrides) -> Resolved_Instance_Style {
	result := Resolved_Instance_Style{
		container_height=260,
		container_padding=12,
		container_corner_radius=13,
		option_corner_radius=9,
		option_button_height=40,
		indicator_width=26,
		indicator_height=4,
		indicator_corner_radius=2,
		label_size=18,
		detail_size=14,
	}
	if overrides.container_height > 0 { result.container_height = overrides.container_height }
	if overrides.container_padding > 0 { result.container_padding = overrides.container_padding }
	if overrides.container_corner_radius > 0 { result.container_corner_radius = overrides.container_corner_radius }
	if overrides.option_corner_radius > 0 { result.option_corner_radius = overrides.option_corner_radius }
	if overrides.option_button_height > 0 { result.option_button_height = overrides.option_button_height }
	if overrides.indicator_width > 0 { result.indicator_width = overrides.indicator_width }
	if overrides.indicator_height > 0 { result.indicator_height = overrides.indicator_height }
	if overrides.indicator_corner_radius > 0 { result.indicator_corner_radius = overrides.indicator_corner_radius }
	if overrides.label_size > 0 { result.label_size = overrides.label_size }
	if overrides.detail_size > 0 { result.detail_size = overrides.detail_size }
	return result
}

render_option :: proc(
	ctx: ^ui.UI,
	state: ^State,
	recipe: Recipe,
	mode: Mode,
	tone: Tone,
	instance_id: u64,
	overrides: Instance_Overrides,
	metrics: Resolved_Instance_Style,
	compact: bool,
	instance_key: ui.UI_Key,
) -> bool {
	changed := false
	index := int(mode)
	if index < 0 || index >= len(OPTION_LABELS) { return false }
	// The key scope must lexically contain the complete component description.
	if ui.key_scope(ctx, instance_key) {
		card_height: f32 = 154
		card_direction := ui.Layout_Direction.Column
		card_gap: f32 = 7
		card_padding: f32 = 10
		button_width: f32 = -1
		button_height := metrics.option_button_height
		if compact {
			card_height = 46
			card_direction = .Row
			card_gap = 8
			card_padding = 5
			button_width = 148
			card_height = mode_rail_max(card_height, button_height+10)
		}
		card := alicorn.surface_begin(
			ctx,
			alicorn.surface_extension_color_role(recipe.option_role),
			key=ui.key_u64(1),
			style=ui.layout_style(card_direction, width=-1, height=card_height, grow=1,
				padding=card_padding, gap=card_gap, align=.Stretch),
			shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=metrics.option_corner_radius},
			label="mode-option-card",
		)
		if card == 0 { return false }

		clicked := ui.button(
			ctx,
			OPTION_LABELS[index],
			key=ui.key_u64(2),
			state=alicorn.Button_State{selected=state.selected == mode, disabled=state.disabled[index]},
			variant=.Quiet,
			width=button_width,
			height=button_height,
		)
		if clicked {
			state.selected = mode
			changed = true
		}
		_ = alicorn.semantic_augment(ctx, description=OPTION_DETAILS[index])
		_ = alicorn.semantic_bind(ctx, semantic_id_for_instance(instance_id, mode))

		if compact {
			ui.text(ctx, OPTION_DETAILS[index], key=ui.key_u64(3), size=metrics.detail_size,
				style=ui.layout_style(.Row, grow=1))
		} else {
			ui.text(ctx, OPTION_DETAILS[index], key=ui.key_u64(3), size=metrics.detail_size)
		}

		selected := state.selected == mode
		indicator_role := option_indicator_role(recipe, tone, selected, overrides)
		indicator_width := metrics.indicator_width*0.46
		indicator_height := metrics.indicator_height*0.7
		opacity := 0.22
		if selected {
			indicator_width = metrics.indicator_width
			indicator_height = metrics.indicator_height
			opacity = 1
		}
		marker := alicorn.surface_begin(
			ctx,
			alicorn.surface_extension_color_role(indicator_role),
			key=ui.key_u64(4),
			style=ui.layout_style(.Row, width=indicator_width, height=indicator_height),
			shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle,
				corner_radius=mode_rail_min(metrics.indicator_corner_radius, indicator_height*0.5)},
			label="mode-selection-indicator",
		)
		if marker != 0 {
			// Selection differs by both geometry and opacity, so color is never
			// the only cue. Retargeting samples the current value and stays
			// interruptible; reduced-motion preferences are handled by ui.motion.
			_ = ui.motion(ctx, marker, ui.Motion_Target{opacity=opacity, has_opacity=true})
			alicorn.surface_end(ctx)
		}

		alicorn.surface_end(ctx)
	}
	return changed
}

// mode_rail describes one independent selector. instance_id must be stable
// and unique among simultaneously mounted rails; it scopes logical semantic
// IDs so equivalent wide/compact options retain focus across resize. The
// returned bool reports an activation consumed during this description.
mode_rail :: proc(
	ctx: ^ui.UI,
	label: string,
	state: ^State,
	recipe: Recipe,
	key: ui.UI_Key,
	instance_id: u64,
	tone: Tone = .Standard,
	overrides: Instance_Overrides = {},
) -> bool {
	if ctx == nil || state == nil || instance_id == 0 || instance_id > MAX_SEMANTIC_INSTANCE_ID ||
		recipe.container_role == 0 || recipe.option_role == 0 || recipe.signal_role == 0 || recipe.wide_minimum <= 0 {
		return false
	}
	changed := false
	metrics := instance_style_resolve(overrides)
	if ui.key_scope(ctx, key) {
		container := alicorn.surface_begin(
			ctx,
			alicorn.surface_extension_color_role(recipe.container_role),
			key=ui.key_u64(1),
			style=ui.layout_style(.Column, width=-1, height=metrics.container_height,
				padding=metrics.container_padding, gap=8),
			shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle,
				corner_radius=metrics.container_corner_radius},
			label=label,
		)
		if container == 0 { return false }
		_ = alicorn.semantic_description(
			ctx,
			.Group,
			label,
			description="Choose one update mode. Layout adapts to the available width.",
			value=option_name(state.selected),
		)
		_ = alicorn.semantic_bind(ctx, semantic_group_id_for_instance(instance_id))
		ui.text(ctx, label, key=ui.key_u64(2), size=metrics.label_size)

		_ = alicorn.adaptive_begin(
			ctx,
			key=ui.key_u64(3),
			style=ui.layout_style(.Column, width=-1, height=190),
			label="mode-rail-responsive-layout",
		)

		wide := alicorn.adaptive_alternative_begin(
			ctx,
			key=ui.key_u64(4),
			name="wide mode layout",
			minimum_width=recipe.wide_minimum,
			style=ui.layout_style(.Row, width=-1, height=182),
		)
		if wide != 0 {
			_ = alicorn.semantic_description(ctx, .Group, "Horizontal mode choices",
				description="Three choices arranged side by side.")
			if ui.row(ctx, key=ui.key_u64(5), grow=1, gap=8, label="mode-rail-horizontal-options") {
				for mode in Mode {
					changed = render_option(ctx, state, recipe, mode, tone, instance_id, overrides, metrics, false,
						ui.key_pair(10, u64(mode)+1)) || changed
				}
			}
		}
		alicorn.adaptive_alternative_end(ctx)

		compact := alicorn.adaptive_alternative_begin(
			ctx,
			key=ui.key_u64(6),
			name="compact mode layout",
			style=ui.layout_style(.Column, width=-1, height=182),
		)
		if compact != 0 {
			_ = alicorn.semantic_description(ctx, .Group, "Stacked mode choices",
				description="Three choices arranged in a compact vertical list.")
			if ui.column(ctx, key=ui.key_u64(7), grow=1, gap=4, label="mode-rail-stacked-options") {
				for mode in Mode {
					changed = render_option(ctx, state, recipe, mode, tone, instance_id, overrides, metrics, true,
						ui.key_pair(20, u64(mode)+1)) || changed
				}
			}
		}
		alicorn.adaptive_alternative_end(ctx)
		alicorn.adaptive_end(ctx)
		alicorn.surface_end(ctx)
	}
	return changed
}
