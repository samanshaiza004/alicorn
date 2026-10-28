package main

import "core:testing"
import alicorn "alicorn:runtime"

@(test)
test_voiceover_gallery_adopts_slider_input :: proc(t: ^testing.T) {
	app := App{level=0.65}
	voiceover_slider_adopt(&app, alicorn.Control_Change_F32{value=0.8, changed=true})
	testing.expect(t, app.level == 0.8,
		"the gallery should retain a changed slider value in application state")

	voiceover_slider_adopt(&app, alicorn.Control_Change_F32{value=0.2, changed=false})
	testing.expect(t, app.level == 0.8,
		"an unchanged slider description should not overwrite application state")
}
