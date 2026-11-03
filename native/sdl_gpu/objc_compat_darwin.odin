#+build darwin

package alicorn_sdl_gpu

import Foundation "core:sys/darwin/Foundation"
import NS "vendor:darwin/AppKit"

// Odin's current Darwin bindings expose NSObject's release operation through
// its ObjectProtocol method rather than the former Foundation helper.
darwin_objc_release :: proc(value: ^NS.Object) {
	if value != nil {
		Foundation.ObjectProtocol_release(cast(^Foundation.ObjectProtocol)value)
	}
}

darwin_objc_retain :: proc(value: ^NS.Object) {
	if value != nil {
		_ = Foundation.ObjectProtocol_retain(cast(^Foundation.ObjectProtocol)value)
	}
}
