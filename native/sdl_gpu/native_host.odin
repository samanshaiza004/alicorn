package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "vendor:sdl3"

fail :: proc(message: string) -> ! {
	fmt.println("SDL validation FAILED:", message, "SDL error:", sdl3.GetError())
	os.exit(1)
}
