class_name ObjDefs
extends RefCounted
## Catalog of object types and their checkable properties, plus the reference dimensions shared by
## the mesh factory, the pile layout and the generator. Meshes are built in mm at REF_DIAMETER.

enum Type { SCREW, BOLT, NUT, WASHER }
enum Head { NONE, PAN, FLAT, DOME, HEX, SQUARE, PLAIN, WIDE }
enum Drive { NONE, PHILLIPS, SLOTTED, TORX, HEX_SOCKET }
enum Mat { STEEL, BRASS, BLACK, COPPER, ZINC }
enum LenClass { NONE, SHORT, MEDIUM, LONG }
enum Prop { TYPE, HEAD, DRIVE, MATERIAL, LENGTH_CLASS, LENGTH_MM, DIAMETER, PITCH }

const TYPES: Array[int] = [Type.SCREW, Type.BOLT, Type.NUT, Type.WASHER]
const PROP_COUNT: int = 8
## Properties readable by eye. The others need the inspect view's ruler and thread gauge.
const VISIBLE_PROPS: Array[int] = [Prop.TYPE, Prop.HEAD, Prop.DRIVE, Prop.MATERIAL, Prop.LENGTH_CLASS]

const DEFAULT_LENGTH_MM: int = 40
const DEFAULT_DIAMETER_MM: int = 8
const DEFAULT_PITCH: int = 125 ## mm x 100

const LENGTHS_MM: Array[int] = [16, 20, 25, 30, 35, 40, 50, 60, 70, 80]
const DIAMETERS_MM: Array[int] = [4, 6, 8, 10, 12]
const PITCHES: Array[int] = [100, 125, 150]
## Length class bands used for Easy/Medium. The gaps between bands keep classes unambiguous by eye.
const CLASS_BAND_MM: Dictionary = {
	LenClass.SHORT: Vector2i(16, 22),
	LenClass.MEDIUM: Vector2i(34, 44),
	LenClass.LONG: Vector2i(60, 76),
}
const CLASS_SPLIT_SHORT_MEDIUM: int = 28
const CLASS_SPLIT_MEDIUM_LONG: int = 52

const MATERIAL_COLORS: Dictionary = {
	Mat.STEEL: Color(0.62, 0.64, 0.68),
	Mat.BRASS: Color(0.85, 0.65, 0.2),
	Mat.BLACK: Color(0.15, 0.15, 0.17),
	Mat.COPPER: Color(0.75, 0.36, 0.18),
	Mat.ZINC: Color(0.4, 0.58, 0.85),
}

# Reference geometry (mm at diameter 8).
const REF_DIAMETER: float = 8.0
const SHAFT_R: float = 4.0
const TIP_H: float = 3.0
const BODY_LEN: float = 17.0 ## stretchable part of the shaft in the reference mesh


static func length_class(length_mm: int) -> int:
	if length_mm <= 0:
		return LenClass.NONE
	if length_mm < CLASS_SPLIT_SHORT_MEDIUM:
		return LenClass.SHORT
	return LenClass.MEDIUM if length_mm < CLASS_SPLIT_MEDIUM_LONG else LenClass.LONG


static func has_length(type: int) -> bool:
	return type == Type.SCREW or type == Type.BOLT


static func has_thread(type: int) -> bool:
	return type != Type.WASHER


## Allowed values of a property for a type. A single-entry result means the property does not vary.
static func values(type: int, prop: int) -> Array[int]:
	match prop:
		Prop.TYPE:
			return TYPES
		Prop.HEAD:
			match type:
				Type.SCREW: return [Head.PAN, Head.FLAT, Head.DOME]
				Type.BOLT, Type.NUT: return [Head.HEX, Head.SQUARE]
				_: return [Head.PLAIN, Head.WIDE]
		Prop.DRIVE:
			if type == Type.SCREW:
				return [Drive.PHILLIPS, Drive.SLOTTED, Drive.TORX, Drive.HEX_SOCKET]
			return [Drive.NONE]
		Prop.MATERIAL:
			return [Mat.STEEL, Mat.BRASS, Mat.BLACK, Mat.COPPER, Mat.ZINC]
		Prop.LENGTH_CLASS:
			if has_length(type):
				return [LenClass.SHORT, LenClass.MEDIUM, LenClass.LONG]
			return [LenClass.NONE]
		Prop.LENGTH_MM:
			if has_length(type):
				return LENGTHS_MM
			return [0]
		Prop.DIAMETER:
			return DIAMETERS_MM
		_:
			if has_thread(type):
				return PITCHES
			return [0]


static func default_value(type: int, prop: int) -> int:
	match prop:
		Prop.LENGTH_CLASS:
			return LenClass.MEDIUM if has_length(type) else LenClass.NONE
		Prop.LENGTH_MM:
			return DEFAULT_LENGTH_MM if has_length(type) else 0
		Prop.DIAMETER:
			return DEFAULT_DIAMETER_MM
		Prop.PITCH:
			return DEFAULT_PITCH if has_thread(type) else 0
		_:
			return values(type, prop)[0]


static func prop_name(prop: int) -> String:
	return ["type", "head", "drive", "material", "length", "length", "diameter", "thread pitch"][prop]


static func value_name(prop: int, value: int) -> String:
	match prop:
		Prop.TYPE: return ["Screw", "Bolt", "Nut", "Washer"][value]
		Prop.HEAD: return ["-", "Pan head", "Flat head", "Dome head", "Hex", "Square", "Plain", "Wide"][value]
		Prop.DRIVE: return ["-", "Phillips", "Slotted", "Torx", "Hex socket"][value]
		Prop.MATERIAL: return ["Steel", "Brass", "Black oxide", "Copper", "Blue zinc"][value]
		Prop.LENGTH_CLASS: return ["-", "Short", "Medium", "Long"][value]
		Prop.LENGTH_MM: return "%d mm" % value
		Prop.DIAMETER: return "M%d" % value
		_: return "%.2f mm" % (value / 100.0)


# --- Geometry (mm, nominal; multiply by units_per_mm for meters) ---

static func head_radius(type: int, head: int) -> float:
	match head:
		Head.PAN: return 7.0
		Head.FLAT: return 8.0
		Head.DOME: return 6.5
		Head.HEX: return 7.5 if type == Type.BOLT else 8.0
		Head.SQUARE: return 8.0 if type == Type.BOLT else 9.0
		Head.PLAIN: return 9.0
		_: return 13.0


static func head_height(type: int, head: int) -> float:
	match head:
		Head.PAN: return 4.5
		Head.FLAT: return 3.5
		Head.DOME: return 5.0
		Head.HEX: return 5.5 if type == Type.BOLT else 7.0
		Head.SQUARE: return 5.5 if type == Type.BOLT else 6.5
		_: return 1.6


## (max radius, half axial extent, axial center offset) in nominal mm, for the object's local +Y axis.
static func bounds_mm(type: int, head: int, length_mm: int, diameter_mm: int) -> Vector3:
	var s: float = diameter_mm / REF_DIAMETER
	var hh: float = head_height(type, head) * s
	var r: float = maxf(head_radius(type, head), SHAFT_R if has_length(type) else 0.0) * s
	if has_length(type):
		return Vector3(r, (hh + length_mm) / 2.0, (hh - length_mm) / 2.0)
	return Vector3(r, hh / 2.0, hh / 2.0)
