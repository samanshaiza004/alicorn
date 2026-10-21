#+build darwin

package main

import host "../sdl_gpu"

main :: proc() {
	host.RunMacOSTitlebarFixture()
}
