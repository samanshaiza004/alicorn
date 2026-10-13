package alicorn

Icon_Atlas_Page_Data :: struct {
	width, height: int,
	pixels: []u8,
}

Icon_Atlas_Entry :: struct {
	page, x, y, size: int,
}

// Integer physical sizes in the supported range have their own rasterization.
// Sizes outside the range resample its nearest endpoint; no runtime SVG work.
icon_atlas_lookup :: proc(id: Icon_ID, physical_size: int) -> (Icon_Atlas_Entry, bool) {
	if !icon_id_is_valid(id) || physical_size <= 0 { return {}, false }
	size := clamp(physical_size, ICON_ATLAS_MIN_SIZE, ICON_ATLAS_MAX_SIZE)
	index := (int(id)-1)*(ICON_ATLAS_MAX_SIZE-ICON_ATLAS_MIN_SIZE+1)+size-ICON_ATLAS_MIN_SIZE
	if index < 0 || index >= len(ICON_ATLAS_ENTRIES) { return {}, false }
	return ICON_ATLAS_ENTRIES[index], true
}

icon_atlas_validate :: proc() -> bool {
	if len(ICON_ATLAS_ENTRIES) != (int(Icon_ID.Count)-1)*(ICON_ATLAS_MAX_SIZE-ICON_ATLAS_MIN_SIZE+1) { return false }
	for page in ICON_ATLAS_PAGES {
		if page.width <= 0 || page.height <= 0 || page.width%256 != 0 || len(page.pixels) != page.width*page.height { return false }
	}
	for entry, index in ICON_ATLAS_ENTRIES {
		if entry.page < 0 || entry.page >= len(ICON_ATLAS_PAGES) { return false }
		page := ICON_ATLAS_PAGES[entry.page]
		if entry.size != ICON_ATLAS_MIN_SIZE+index%(ICON_ATLAS_MAX_SIZE-ICON_ATLAS_MIN_SIZE+1) ||
		   entry.x < ICON_ATLAS_GUTTER || entry.y < ICON_ATLAS_GUTTER ||
		   entry.x+entry.size+ICON_ATLAS_GUTTER > page.width || entry.y+entry.size+ICON_ATLAS_GUTTER > page.height { return false }
	}
	return true
}
