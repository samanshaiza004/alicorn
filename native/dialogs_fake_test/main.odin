package main

import "core:fmt"
import "core:os"
import alicorn "../../runtime"
import host "../sdl_gpu"

Dialog_Test_State :: struct {
	callbacks: int,
	last_status: host.Dialog_Status,
	had_path: bool,
}

on_dialog :: proc(state: rawptr, rt: ^alicorn.Runtime, result: ^host.File_Dialog_Result) {
	_ = rt
	test := cast(^Dialog_Test_State)state
	test.callbacks += 1
	test.last_status = result.status
	test.had_path = len(result.paths) == 1
}

fail :: proc(message: string) -> ! {
	fmt.println("dialog fake test FAILED:", message)
	os.exit(1)
}

main :: proc() {
	test: Dialog_Test_State
	fake: host.Dialog_Fake_Backend
	service := host.Dialog_Fake_Service(&fake, on_dialog, rawptr(&test), nil)
	request := host.File_Dialog_Request{id=host.Dialog_ID(7), kind=.Open_Folder}
	if !host.ShowFileDialog(service, request) { fail("first fake dialog request was rejected") }
	if host.ShowFileDialog(service, request) { fail("second active fake dialog was accepted") }
	if fake.busy_rejections != 1 { fail("fake busy policy was not observable") }
	if !host.Dialog_Fake_Complete(&fake, .Accepted, "/tmp/example-repository") { fail("accepted fake dialog did not complete") }
	if test.callbacks != 1 || test.last_status != .Accepted || !test.had_path { fail("accepted callback was malformed") }
	if !host.ShowFileDialog(service, request) { fail("fake dialog did not reopen after completion") }
	if !host.Dialog_Fake_Complete(&fake, .Cancelled) { fail("cancelled fake dialog did not complete") }
	if test.callbacks != 2 || test.last_status != .Cancelled { fail("cancelled callback was malformed") }
	fmt.println("Alicorn native dialog fake test: PASS")
}
