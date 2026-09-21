class_name Art
extends RefCounted
## Loads sprites by path, falling back to a neutral placeholder when the file is
## missing or not yet imported, so the game never breaks while art is in
## progress. Nothing is ever written into assets/.
##
## Note: a PNG added to assets/ is only loadable after the Godot editor has
## imported it. Until you open the editor once, new art shows the fallback.

const FALLBACK_SIZE := 32

static var _cache := {}
static var _fallback: Texture2D


static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = fallback()
	_cache[path] = tex
	return tex


static func exists(path: String) -> bool:
	return path != "" and ResourceLoader.exists(path)


## A grey checker tile with a darker border: obviously a placeholder, never
## mistaken for real art.
static func fallback() -> Texture2D:
	if _fallback != null:
		return _fallback
	var img := Image.create(FALLBACK_SIZE, FALLBACK_SIZE, false, Image.FORMAT_RGBA8)
	var light := Color(0.55, 0.55, 0.55)
	var dark := Color(0.40, 0.40, 0.40)
	var edge := Color(0.22, 0.22, 0.22)
	for y in FALLBACK_SIZE:
		for x in FALLBACK_SIZE:
			@warning_ignore("integer_division")
			var c := light if ((x / 8) + (y / 8)) % 2 == 0 else dark
			if x == 0 or y == 0 or x == FALLBACK_SIZE - 1 or y == FALLBACK_SIZE - 1:
				c = edge
			img.set_pixel(x, y, c)
	_fallback = ImageTexture.create_from_image(img)
	return _fallback


## Paths from `paths` that do not exist yet.
static func missing(paths: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p in paths:
		if not exists(p) and not out.has(p):
			out.append(p)
	return out


## Debug builds only: prints the art still to draw, so the game itself tells
## the artist what is left.
static func report_missing(paths: Array) -> void:
	if not OS.is_debug_build():
		return
	var gone := missing(paths)
	if gone.is_empty():
		print("Art: all %d referenced sprites present." % paths.size())
		return
	print("Art: %d sprite(s) missing or not yet imported (showing placeholder):" % gone.size())
	for p in gone:
		print("   - ", p)
