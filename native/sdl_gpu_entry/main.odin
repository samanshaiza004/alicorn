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
	host.RunFoundation()
}
