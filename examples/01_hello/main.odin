package main

// The first application needs only typed state, a render procedure, and
// ordinary Odin control flow. ui.run owns routine native host and frame setup.

import "core:fmt"
import "core:os"
import "core:strings"
import ui "alicorn:ui"

App :: struct {
	count: int,
	desktop_validation: bool,
	pointer_activations: int,
	keyboard_activations: int,
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	if ui.column(ctx, padding=24, gap=12) {
		if app.desktop_validation {
			ui.text(ctx, "macOS desktop launch validation", size=24)
			ui.text(ctx, "Physically click Pointer test, then Tab until Keyboard test is focused; press Space.")
			if ui.button(ctx, "Pointer test") {
				app.pointer_activations += 1
			}
			if ui.button(ctx, "Keyboard test") {
				app.keyboard_activations += 1
			}
			ui.text(ctx, fmt.tprintf(
				"Pointer: %d · Keyboard: %d",
				app.pointer_activations,
				app.keyboard_activations,
			))
		} else {
			ui.text(ctx, "Hello, Alicorn", size=24)
			ui.text(ctx, fmt.tprintf("Count: %d", app.count))
			if ui.button(ctx, "Increment") {
				app.count += 1
			}
		}
	}
}

main :: proc() {
	result_path := ""
	run_id := ""
	for argument in os.args {
		result_prefix := "--desktop-validation-result="
		run_prefix := "--desktop-validation-run-id="
		if strings.has_prefix(argument, result_prefix) {
			result_path = argument[len(result_prefix):]
		}
		if strings.has_prefix(argument, run_prefix) {
			run_id = argument[len(run_prefix):]
		}
	}
	app := App{desktop_validation=result_path != ""}
	ui.run(&app, render, title="Alicorn starter", width=720, height=480)
	if result_path != "" {
		if run_id == "" {
			fmt.eprintln("desktop validation requires a run ID")
			os.exit(1)
		}
		result := desktop_validation_result_json(
			run_id,
			app.pointer_activations,
			app.keyboard_activations,
		)
		if err := os.write_entire_file_from_string(result_path, result); err != nil {
			fmt.eprintln("desktop validation result write failed:", err)
			os.exit(1)
		}
	}
}

desktop_validation_result_json :: proc(
	run_id: string,
	pointer_activations, keyboard_activations: int,
) -> string {
	// fmt treats single braces as format syntax; doubled braces emit JSON delimiters.
	return fmt.tprintf(
		"{{\"runId\":\"%s\",\"pointerActivations\":%d,\"keyboardActivations\":%d}}\n",
		run_id,
		pointer_activations,
		keyboard_activations,
	)
}
