package alicorn

import "core:testing"

Semantic_Augment_Selected_ID :: Semantic_ID{namespace=0x53454D414E544943, value=1}
Semantic_Augment_Disabled_ID :: Semantic_ID{namespace=0x53454D414E544943, value=2}

@(test)
test_semantic_augment_preserves_control_contract_and_only_adds_metadata :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 260, 120})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "semantic augmentation fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("semantic-augment-root"), style=layout_style(.Column, width=260, height=120))
	_, _ = button_begin(&ui, "Selected action", key_string("selected"),
		style=layout_style(width=160, height=32), state=Button_State{selected=true})
	augment_selected := semantic_augment(&ui,
		description="An extra explanation supplied by a reusable component.",
	actions_add=semantic_actions_add({}, .Expand))
	bind_selected := semantic_bind(&ui, Semantic_Augment_Selected_ID)
	button_end(&ui)

	_, _ = button_begin(&ui, "Disabled action", key_string("disabled"),
		style=layout_style(width=160, height=32), state=Button_State{disabled=true})
	augment_disabled := semantic_augment(&ui, description="Unavailable until setup completes.")
	bind_disabled := semantic_bind(&ui, Semantic_Augment_Disabled_ID)
	button_end(&ui)
	container_end(&ui)
	end_frame(&ui)

	selected, selected_found := semantic_node_lookup(&rt, Semantic_Augment_Selected_ID)
	disabled, disabled_found := semantic_node_lookup(&rt, Semantic_Augment_Disabled_ID)
	testing.expect(t, augment_selected && augment_disabled && bind_selected && bind_disabled,
		"augmentation and logical identity binding should accept the current described controls")
	testing.expect(t, selected_found && selected.role == .Button && selected.label == "Selected action" &&
		selected.description == "An extra explanation supplied by a reusable component." &&
		semantic_states_has(selected.states, .Selected) && semantic_actions_has(selected.actions, .Press) &&
		semantic_actions_has(selected.actions, .Expand),
		"a reusable component should add a description/action without replacing built-in role, label, selected state, or Press")
	testing.expect(t, disabled_found && disabled.role == .Button && disabled.label == "Disabled action" &&
		disabled.description == "Unavailable until setup completes." &&
		semantic_states_has(disabled.states, .Disabled) && !semantic_actions_has(disabled.actions, .Press),
		"augmentation must preserve a disabled Button's state and prevent it from regaining Press")
}
