extends SceneTree
## Tool: cuts a UI sheet drawn on a magenta background into separate transparent
## PNGs (one per element), sorted in reading order: <out>/<prefix>_00.png, _01, ...
## Run headless:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path game -s res://tests/slice_ui_sheet.gd -- <sheet.png> <out dir> <prefix>  [merge gap]

## Magenta-ness = min(r, b) - g. At or above KEY_HIGH a pixel is background,
## at or below KEY_LOW it is fully kept; in between it fades (soft edges).
const KEY_LOW := 0.22
const KEY_HIGH := 0.5
## Pieces closer than this (pixels) belong to one element (e.g. a pair of boots).
const MERGE_GAP := 14  # override with a 4th argument
const MIN_SIZE := 24
const PAD := 4


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGBA8)
	_key(img)
	var gap := int(args[3]) if args.size() > 3 else MERGE_GAP
	var boxes := _merge(_components(img), gap)
	boxes.sort_custom(_reading_order.bind(boxes))
	DirAccess.make_dir_recursive_absolute(args[1])
	for i in boxes.size():
		var r: Rect2i = boxes[i].grow(PAD).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png("%s/%s_%02d.png" % [args[1], args[2], i])
		print("%s_%02d  %s" % [args[2], i, r])
	quit()


## Removes the magenta background and the pink fringe it leaves on edges.
func _key(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var m := minf(c.r, c.b) - c.g
			if m <= KEY_LOW * 0.5:
				continue
			var alpha := clampf((KEY_HIGH - m) / (KEY_HIGH - KEY_LOW), 0.0, 1.0)
			var spill := maxf(0.0, minf(c.r, c.b) - c.g)
			c.r -= spill
			c.b -= spill
			c.a = alpha
			img.set_pixel(x, y, c)


## Bounding boxes of the opaque islands (8-connected flood fill).
func _components(img: Image) -> Array[Rect2i]:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var boxes: Array[Rect2i] = []
	for y in h:
		for x in w:
			if seen[y * w + x] or img.get_pixel(x, y).a < 0.5:
				continue
			var lo := Vector2i(x, y)
			var hi := Vector2i(x, y)
			var stack := PackedInt32Array([y * w + x])
			seen[y * w + x] = 1
			while not stack.is_empty():
				var i := stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				var px := i % w
				var py := i / w
				lo = Vector2i(mini(lo.x, px), mini(lo.y, py))
				hi = Vector2i(maxi(hi.x, px), maxi(hi.y, py))
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var nx: int = px + dx
						var ny: int = py + dy
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							continue
						var j := ny * w + nx
						if not seen[j] and img.get_pixel(nx, ny).a >= 0.5:
							seen[j] = 1
							stack.append(j)
			boxes.append(Rect2i(lo, hi - lo + Vector2i.ONE))
	return boxes


func _merge(boxes: Array[Rect2i], gap: int) -> Array[Rect2i]:
	var merged := true
	while merged:
		merged = false
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				if boxes[i].grow(gap).intersects(boxes[j]):
					boxes[i] = boxes[i].merge(boxes[j])
					boxes.remove_at(j)
					merged = true
					break
			if merged:
				break
	return boxes.filter(func(b: Rect2i) -> bool: return b.size.x >= MIN_SIZE and b.size.y >= MIN_SIZE)


## Rows first (boxes whose centres are within half a box height share a row), then left to right.
func _reading_order(a: Rect2i, b: Rect2i, _all: Array) -> bool:
	var ay := a.get_center().y
	var by := b.get_center().y
	if absi(ay - by) > mini(a.size.y, b.size.y) / 2:
		return ay < by
	return a.position.x < b.position.x
