#+build windows

package main
import host "../sdl_gpu"
main :: proc() { host.RunCaptionValidation() }
