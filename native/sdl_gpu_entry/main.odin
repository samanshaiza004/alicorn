package main

import host "../sdl_gpu"
import "core:os"

main :: proc() {
	for argument in os.args {
		if argument == "--menu-fixture" {
			host.RunMenuFixture()
			return
		}
	}
	for argument in os.args {
		if argument == "--inspector" || argument == "--inspector-open" || argument == "--inspector-fixture" {
			host.RunInspectorFixture()
			return
		}
	}
	host.RunFoundation()
}
