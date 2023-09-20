class_name BitReader extends Node

var data: PackedByteArray
var byte_offset: int
var bit_offset: int

const BITS_IN_BYTE = 8

# Bit-wise read helper for PackedByteArray, which
# decodes at the level of byte.
func _init(byteArray: PackedByteArray):
	data = byteArray
	byte_offset = 0
	bit_offset = 0
	
func has_next():
	return byte_offset < data.size() && bit_offset < BITS_IN_BYTE

# Skip to the beginning of next byte boundary
func skip_to_next_byte():
	byte_offset += 1
	bit_offset = 0

# Get the next bit in a byte.
func get_next_bit():
	if byte_offset >= data.size():
		push_error("Byte array out of bound")
		return null
		
	var current_byte = data.decode_u8(byte_offset)

	var current_bit = (current_byte >> bit_offset) & 0x1
	bit_offset += 1
	
	if bit_offset >= BITS_IN_BYTE:
		bit_offset = 0
		byte_offset += 1
	
	return current_bit

# Grab next [length] bits.
# If [reverse] is true, read the bit-stream as from most-significant to least-significant bit.
# Otherwise, read the bit-stream as from least-significant bit to most-significant bit.
func get_next_bits(length: int, reverse: bool= false):
	var result = 0
	for n in length:
		if reverse:
			result = (result << 1) | get_next_bit()
		else:
			result = result | (get_next_bit() << n)

	return result
