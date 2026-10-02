package alicorn
import "core:mem"
import "core:strings"

hash_mix :: proc(h, value: u64) -> u64 {
	result := h ~ value
	result *= 1099511628211
	return result
}

hash_string :: proc(value: string) -> u64 {
	h: u64 = 1469598103934665603
	for i := 0; i < len(value); i += 1 {
		h = hash_mix(h, u64(value[i]))
	}
	return h
}

identity_hash :: proc(parent: Node_ID, source: Source_Site, key: string, explicit_key: bool) -> Node_ID {
	h := u64(1469598103934665603)
	h = hash_mix(h, u64(parent))
	h = hash_mix(h, hash_string(source.file))
	h = hash_mix(h, u64(source.line))
	h = hash_mix(h, u64(source.column))
	h = hash_mix(h, hash_string(source.component))
	if explicit_key {
		h = hash_mix(h, hash_string(key))
	}
	if h == 0 {
		h = 1
	}
	return Node_ID(h)
}

identity_hash_u64 :: proc(parent: Node_ID, source: Source_Site, key: u64) -> Node_ID {
	h := u64(1469598103934665603)
	h = hash_mix(h, u64(parent))
	h = hash_mix(h, hash_string(source.file))
	h = hash_mix(h, u64(source.line))
	h = hash_mix(h, u64(source.column))
	h = hash_mix(h, hash_string(source.component))
	h = hash_mix(h, key)
	if h == 0 { h = 1 }
	return Node_ID(h)
}

identity_hash_key :: proc(parent: Node_ID, source: Source_Site, key: UI_Key) -> Node_ID {
	h := u64(1469598103934665603)
	h = hash_mix(h, u64(parent))
	h = hash_mix(h, hash_string(source.file))
	h = hash_mix(h, u64(source.line))
	h = hash_mix(h, u64(source.column))
	h = hash_mix(h, hash_string(source.component))
	switch value in key {
	case UI_Unkeyed:
		h = hash_mix(h, 0)
	case string:
		h = hash_mix(h, 1)
		h = hash_mix(h, hash_string(value))
	case u64:
		h = hash_mix(h, 2)
		h = hash_mix(h, value)
	case UI_Key_Pair:
		h = hash_mix(h, 3)
		h = hash_mix(h, value.first)
		h = hash_mix(h, value.second)
	}
	if h == 0 { h = 1 }
	return Node_ID(h)
}

owned :: proc(value: string, allocator := context.allocator) -> string {
	if value == "" {
		return ""
	}
	copy, _ := strings.clone(value, allocator)
	return copy
}

owned_with_allocator :: proc(value: string, allocator: mem.Allocator) -> string {
	if value == "" { return "" }
	copy, err := strings.clone(value, allocator)
	if err != nil { return "" }
	return copy
}

