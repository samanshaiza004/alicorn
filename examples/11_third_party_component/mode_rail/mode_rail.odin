package mode_rail

// Mode Rail is an example third-party compound control. It uses only the
// public ui and runtime APIs: no Runtime fields, private layout records, or
// native renderer access. The application owns state; this package owns its
// recipe and presentation policy.

import alicorn "alicorn:runtime"
import ui "alicorn:ui"

Mode :: enum { Calm, Balanced, Urgent }
Tone :: enum { Standard, Attention }

State :: struct {
	selected: Mode,
}

// Recipe is intentionally an application-level typed value rather than a new
// Alicorn runtime recipe family. Theme role IDs resolve through the active
// compiled theme, and instance tone can choose a different token without
// copying or forking the recipe.
Recipe :: struct {
	container_role: alicorn.Style_Extension_Color_Role_ID,
	option_role:    alicorn.Style_Extension_Color_Role_ID,
	signal_role:    alicorn.Style_Extension_Color_Role_ID,
	attention_role: alicorn.Style_Extension_Color_Role_ID,
	wide_minimum:   f32,
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

option_name :: proc(mode: Mode) -> string {
	index := int(mode)
	if index < 0 || index >= len(OPTION_LABELS) { return OPTION_LABELS[int(Mode.Balanced)] }
	return OPTION_LABELS[index]
}

render_option :: proc(
	ctx: ^ui.UI,
	state: ^State,
	recipe: Recipe,
	mode: Mode,
	tone: Tone,
	compact: bool,
	instance_key: ui.UI_Key,
) -> bool {
	changed := false
	index := int(mode)
	if index < 0 || index >= len(OPTION_LABELS) { return false }
	// The key scope must lexically contain the complete component description.
	// Keeping it as a standalone call would defer closing all repeated option
	// scopes until this helper returns, accidentally nesting sibling identities.
	if ui.key_scope(ctx, instance_key) {

	card_height: f32 = 142
	card_direction := ui.Layout_Direction.Column
	card_gap: f32 = 7
	card_padding: f32 = 10
	button_width: f32 = -1
	button_height: f32 = 40
	if compact {
		card_height = 46
		card_direction = .Row
		card_gap = 8
		card_padding = 5
		button_width = 142
		button_height = 36
	}
	card := alicorn.surface_begin(
		ctx,
		alicorn.surface_extension_color_role(recipe.option_role),
		key=ui.key_u64(1),
		style=ui.layout_style(card_direction, width=-1, height=card_height, grow=1,
			padding=card_padding, gap=card_gap, align=.Stretch),
		shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=9},
		label="mode-option-card",
	)
	if card == 0 { return false }

	clicked := ui.button(
		ctx,
		OPTION_LABELS[index],
		key=ui.key_u64(2),
		state=ui.Button_State{selected=state.selected == mode},
		variant=.Quiet,
		width=button_width,
		height=button_height,
	)
	if clicked {
		state.selected = mode
		changed = true
	}
	selected := state.selected == mode
	states := alicorn.Semantic_States{}
	if selected { states = alicorn.semantic_states_add(states, .Selected) }
	actions := alicorn.semantic_actions_add({}, .Press)
	_ = alicorn.semantic_description(
		ctx,
		.Button,
		OPTION_LABELS[index],
		description=OPTION_DETAILS[index],
		states=states,
		actions=actions,
	)

	if compact {
		ui.text(ctx, OPTION_DETAILS[index], key=ui.key_u64(3), size=13,
			style=ui.layout_style(.Row, grow=1))
	} else {
		ui.text(ctx, OPTION_DETAILS[index], key=ui.key_u64(3), size=14)
	}

	indicator_role := recipe.signal_role
	if tone == .Attention && selected { indicator_role = recipe.attention_role }
	indicator_width: f32 = 26
	if compact { indicator_width = 20 }
	marker := alicorn.surface_begin(
		ctx,
		alicorn.surface_extension_color_role(indicator_role),
		key=ui.key_u64(4),
		style=ui.layout_style(.Row, width=indicator_width, height=4),
		shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=2},
		label="mode-selection-indicator",
	)
	if marker != 0 {
		opacity := 0.16
		if selected { opacity = 1 }
		// Repeated selection changes retarget this retained property from its
		// current presentation, so rapid changes interrupt smoothly. Selection,
		// hit testing, and semantics update immediately at target layout.
		_ = ui.motion(ctx, marker, ui.Motion_Target{opacity=opacity, has_opacity=true})
		alicorn.surface_end(ctx)
	}

	alicorn.surface_end(ctx)
}
	return changed
}

// mode_rail describes one independent selector instance. The returned bool
// reports whether this description consumed a user activation. A compact
// stacked alternative is selected by the assigned width; source state and
// semantic selection are shared across both presentations.
mode_rail :: proc(
	ctx: ^ui.UI,
	label: string,
	state: ^State,
	recipe: Recipe,
	key: ui.UI_Key,
	tone: Tone = .Standard,
) -> bool {
	if ctx == nil || state == nil || recipe.container_role == 0 || recipe.option_role == 0 ||
		recipe.signal_role == 0 || recipe.attention_role == 0 || recipe.wide_minimum <= 0 {
		return false
	}

	changed := false
	if ui.key_scope(ctx, key) {
	container := alicorn.surface_begin(
		ctx,
		alicorn.surface_extension_color_role(recipe.container_role),
		key=ui.key_u64(1),
		style=ui.layout_style(.Column, width=-1, height=240, padding=12, gap=8),
		shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=13},
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
	ui.text(ctx, label, key=ui.key_u64(2), size=18)

	owner := alicorn.adaptive_begin(
		ctx,
		key=ui.key_u64(3),
		style=ui.layout_style(.Column, width=-1, height=168),
		label="mode-rail-responsive-layout",
	)
	_ = owner

	wide := alicorn.adaptive_alternative_begin(
		ctx,
		key=ui.key_u64(4),
		name="wide mode layout",
		minimum_width=recipe.wide_minimum,
		style=ui.layout_style(.Row, width=-1, height=160),
	)
	if wide != 0 {
		_ = alicorn.semantic_description(ctx, .Group, "Horizontal mode choices",
			description="Three choices arranged side by side.")
		if ui.row(ctx, key=ui.key_u64(5), grow=1, gap=8, label="mode-rail-horizontal-options") {
			for mode in Mode {
				changed = render_option(ctx, state, recipe, mode, tone, false, ui.key_pair(10, u64(mode)+1)) || changed
			}
		}
	}
	alicorn.adaptive_alternative_end(ctx)

	compact := alicorn.adaptive_alternative_begin(
		ctx,
		key=ui.key_u64(6),
		name="compact mode layout",
		style=ui.layout_style(.Column, width=-1, height=160),
	)
	if compact != 0 {
		_ = alicorn.semantic_description(ctx, .Group, "Stacked mode choices",
			description="Three choices arranged in a compact vertical list.")
		if ui.column(ctx, key=ui.key_u64(7), grow=1, gap=4, label="mode-rail-stacked-options") {
			for mode in Mode {
				changed = render_option(ctx, state, recipe, mode, tone, true, ui.key_pair(20, u64(mode)+1)) || changed
			}
		}
	}
	alicorn.adaptive_alternative_end(ctx)
	alicorn.adaptive_end(ctx)
	alicorn.surface_end(ctx)
	}
	return changed
}
