extends Node
## File I/O, integrity and versioning for saved games. Nothing else.
##
## What goes *into* a save is decided by the systems that own the data --
## main.gd assembles the run dictionary from the level, the clock and (later)
## the director and economy. This autoload only stores it safely and hands it
## back, so it never needs to know what a level or a worker is.
##
## Two files, two policies:
##   run.save      one run. Deleted on death. A version mismatch is REFUSED.
##   profile.save  permanent. A version mismatch is MIGRATED, never discarded.
##
## Runs are ephemeral, so carrying migration code for every intermediate shape
## of an in-development format costs more than the occasional lost run. Meta
## progression is the one thing a player would genuinely mourn, so it migrates.

const RUN_PATH := "user://run.save"
const PROFILE_PATH := "user://profile.save"

const MAGIC := "NSPL"
## Layout of the header itself. Changing this invalidates every existing file,
## so it should almost never change.
const CONTAINER_VERSION := 1
## 2: runs hold units, houses and construction sites (Stage 2a). A version-1
## run is refused, per the run policy above, and the player starts fresh.
const RUN_VERSION := 2
const PROFILE_VERSION := 1

## Longest plausible header string. Bounds the read so a corrupt length field
## cannot make us allocate wildly before we have verified anything.
const _MAX_HEADER_STRING := 128
const _MIN_FILE_SIZE := 24

## Always a valid dictionary, loaded at startup. Mutate it and call
## save_profile(); it is small enough that there is no reason to batch writes.
var profile := {}


func _ready() -> void:
	_load_profile()


# --- Runs ---------------------------------------------------------------------

## Writes the run atomically. Returns false if nothing was written, in which
## case any previous save is still intact.
func save_run(data: Dictionary) -> bool:
	return _write(RUN_PATH, RUN_VERSION, data)


## The saved run, or {} if there is none or none that this build can read.
func load_run() -> Dictionary:
	return _find_run()


## True only if a run exists that would actually load. This verifies the payload
## rather than peeking at the header: a header can be intact while the payload
## behind it is corrupt, and a Continue button that starts a brand new world is
## worse than the few milliseconds a full check costs on a title screen.
func has_run() -> bool:
	return not _find_run().is_empty()


## Walks the candidates and returns the first payload that verifies and matches
## the version this build reads.
func _find_run() -> Dictionary:
	for candidate in _candidates(RUN_PATH):
		var result := _read(candidate)
		if not result["ok"]:
			continue
		if result["version"] != RUN_VERSION:
			push_warning("SaveManager: '%s' is version %d, this build reads %d. Ignoring it."
				% [candidate, result["version"], RUN_VERSION])
			continue
		if candidate != RUN_PATH:
			push_warning("SaveManager: '%s' unusable, recovered from '%s'."
				% [RUN_PATH, candidate])
		return result["payload"]
	return {}


## Removes the run and its temp/backup companions. Called when a run ends.
func delete_run() -> void:
	for candidate in _candidates(RUN_PATH):
		if FileAccess.file_exists(candidate):
			var err := DirAccess.remove_absolute(candidate)
			if err != OK:
				push_error("SaveManager: couldn't delete '%s': %s"
					% [candidate, error_string(err)])


# --- Profile ------------------------------------------------------------------

func save_profile() -> bool:
	return _write(PROFILE_PATH, PROFILE_VERSION, profile)


func _default_profile() -> Dictionary:
	return {
		"runs_started": 0,
		"runs_ended": 0,
		"best_day": 0,
		"total_ticks": 0,
		# Meta-currency and unlocks join this in Stage 8. New keys are filled in
		# from these defaults on load, so adding one needs no migration step.
	}


func _load_profile() -> void:
	for candidate in _candidates(PROFILE_PATH):
		var result := _read(candidate)
		if not result["ok"]:
			continue
		if candidate != PROFILE_PATH:
			push_warning("SaveManager: profile recovered from '%s'." % candidate)
		profile = _migrate_profile(result["payload"], result["version"])
		return
	profile = _default_profile()


## Brings an older profile up to the current version. A profile is never thrown
## away: an unreadable *field* is replaced, but the file is kept.
func _migrate_profile(data: Dictionary, from_version: int) -> Dictionary:
	var out := data.duplicate(true)
	var version := from_version

	# Migration steps go here, one per version step, in order:
	#   if version == 1:
	#       out = _profile_1_to_2(out)
	#       version = 2

	if version > PROFILE_VERSION:
		push_warning("SaveManager: profile is version %d, newer than this build (%d). "
			% [version, PROFILE_VERSION] + "Keeping the fields we understand.")
	elif version != PROFILE_VERSION:
		push_warning("SaveManager: profile version %d has no migration path to %d."
			% [version, PROFILE_VERSION])

	# Additive changes need no explicit step: any key added since the file was
	# written simply takes its default.
	var defaults := _default_profile()
	for key in defaults:
		if not out.has(key):
			out[key] = defaults[key]
	return out


# --- File format --------------------------------------------------------------
#
# Header, then payload:
#   u32 + bytes   magic "NSPL"
#   u32           container version
#   u32           payload schema version
#   u32 + bytes   sha256 of the payload, hex
#   u64           payload length
#   bytes         payload, var_to_bytes of a Dictionary (no object support)
#
# The digest is written before the payload so a truncated file is detected
# rather than deserialised into nonsense, and so has_run() can read a version
# without touching the payload at all.

func _candidates(path: String) -> Array[String]:
	# Order matters. A leftover .tmp is a COMPLETE newer save from a write that
	# was interrupted after the old file was rotated away, so it beats .bak.
	return [path, path + ".tmp", path + ".bak"]


func _write(path: String, data_version: int, payload: Dictionary) -> bool:
	var bytes := var_to_bytes(payload)
	var digest := _sha256(bytes)
	var tmp := path + ".tmp"
	var bak := path + ".bak"

	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: couldn't open '%s': %s"
			% [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_32(MAGIC.length())
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_32(CONTAINER_VERSION)
	file.store_32(data_version)
	file.store_32(digest.length())
	file.store_buffer(digest.to_ascii_buffer())
	file.store_64(bytes.size())
	file.store_buffer(bytes)
	file.close()

	# Read back what actually reached the disk before touching the existing
	# save. A bad write must never be allowed to destroy a good file.
	if not _read(tmp)["ok"]:
		push_error("SaveManager: wrote '%s' but it failed verification. Keeping the old save." % tmp)
		return false

	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var err := DirAccess.rename_absolute(path, bak)
		if err != OK:
			push_error("SaveManager: couldn't rotate '%s' to backup: %s"
				% [path, error_string(err)])
			return false
	var err2 := DirAccess.rename_absolute(tmp, path)
	if err2 != OK:
		# The new save is complete and still on disk as .tmp, and _candidates()
		# looks there, so nothing is lost even though the rename failed.
		push_error("SaveManager: couldn't move '%s' into place: %s"
			% [tmp, error_string(err2)])
		return false
	return true


## Returns {"ok": bool, "version": int, "payload": Dictionary}.
## Never throws and never trusts the file: every length is bounded before use.
func _read(path: String) -> Dictionary:
	var fail := {"ok": false, "version": 0, "payload": {}}
	if not FileAccess.file_exists(path):
		return fail
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < _MIN_FILE_SIZE:
		return fail

	if _read_string(file) != MAGIC:
		return fail
	if file.get_32() != CONTAINER_VERSION:
		return fail
	var version := file.get_32()
	var digest := _read_string(file)
	if digest.is_empty():
		return fail

	var length := file.get_64()
	var remaining := file.get_length() - file.get_position()
	if length <= 0 or length > remaining:
		return fail    # truncated: the payload claimed is longer than the file
	var bytes := file.get_buffer(length)
	if bytes.size() != length:
		return fail
	if _sha256(bytes) != digest:
		return fail    # corrupted: the bytes are not the bytes we wrote

	var payload = bytes_to_var(bytes)
	if not payload is Dictionary:
		return fail
	return {"ok": true, "version": version, "payload": payload}


## Length-prefixed ASCII, with the length bounded before it is trusted.
func _read_string(file: FileAccess) -> String:
	var length := file.get_32()
	if length <= 0 or length > _MAX_HEADER_STRING:
		return ""
	if length > file.get_length() - file.get_position():
		return ""
	return file.get_buffer(length).get_string_from_ascii()


func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
