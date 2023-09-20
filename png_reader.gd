class_name PNGReader extends Node

const MAXBITS = 15              # maximum bits in a code
const MAXLCODES = 286           # maximum number of literal/length codes
const MAXDCODES = 30            # maximum number of distance codes
const FIXLCODES = 288           # number of fixed literal/length codes
const FIXDCODES = 32            # number of fixed distance codes
const CODELENGTHCODECOUNT = 19 # number of symbols used to CodeLength code (0 ~ 18)

# Order of CodeLength Code Length for Dynamic Huffman per Spec
const  CODELENGTH_CODELENGTH_ORDER = [
	16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
]

# length table maps length code to [length, offset bit count]
# Table is defined by specification.
const LENGTH_TABLE = {
	257: [3, 0],
	258: [4, 0],
	259: [5, 0],
	260: [6, 0],
	261: [7, 0],
	262: [8, 0],
	263: [9, 0],
	264: [10, 0],
	265: [11, 1],
	266: [13, 1],
	267: [15, 1],
	268: [17, 1],
	269: [19, 2],
	270: [23, 2],
	271: [27, 2],
	272: [31, 2],
	273: [35, 3],
	274: [43, 3],
	275: [51, 3],
	276: [59, 3],
	277: [67, 4],
	278: [83, 4],
	279: [99, 4],
	280: [115, 4],
	281: [131, 5],
	282: [163, 5],
	283: [195, 5],
	284: [227, 5],
	285: [285, 0]
}

# distance table maps backreference distance code to [distance, extra bits]
# the map is defined by the PNG deflate specification.
const DISTANCE_TABLE = {
	0: [1, 0],
	1: [2, 0],
	2: [3, 0],
	3: [4, 0],
	4: [5, 1],
	5: [7, 1],
	6: [9, 2],
	7: [13, 2],
	8: [17, 3],
	9: [25, 3],
	10: [33, 4],
	11: [49, 4],
	12: [65, 5],
	13: [97, 5],
	14: [129, 6],
	15: [193, 6],
	16: [257, 7],
	17: [385, 7],
	18: [513, 8],
	19: [769, 8],
	20: [1025, 9],
	21: [1537, 9],
	22: [2049, 10],
	23: [3073, 10],
	24: [4097, 11],
	25: [6145, 11],
	26: [8193, 12],
	27: [12289, 12],
	28: [16385, 13],
	29: [24577, 13]
}

var path: String

var palette: Array[Color]

# Image Metadata
var width: int
var height: int
var bit_depth: int
var color_type: int
var compression: int
var filter_method: int 
var interlace: int

var uncompressed_image_data: Array[int]

func _init(resource_path: String):
	path = resource_path
	palette = []
	_read_file()

# Load in PNG file at given [path] and parse the data.
# Referenced from specification: http://www.libpng.org/pub/png/spec/1.2/PNG-Structure.html
func _read_file():
	var file = FileAccess.open(path, FileAccess.READ)
	file.big_endian = true

	# First 8 bytes signiature for PNG:
	# 137 80 78 71 13 10 26 10
	var signature = file.get_buffer(8)

	while(!file.eof_reached()):
		# chunk 
		var chunk_size = file.get_32()
		var chunk_type = file.get_buffer(4).get_string_from_utf8()
		print(chunk_type)
		if chunk_type == "IHDR":
			width = file.get_32()
			height = file.get_32()
			bit_depth = file.get_8()
			color_type = file.get_8()
			compression = file.get_8()
			filter_method = file.get_8()
			interlace = file.get_8()
		elif chunk_type == "PLTE": 
			palette = []
			for n in chunk_size/3:
				# multiples of three RGB (1 byte, 1 byte, 1 byte)
				palette.push_back(Color(file.get_8(),file.get_8(),file.get_8()))
		elif chunk_type == "IDAT":
			var compressed_data = file.get_buffer(chunk_size)
			_decompress_zlib(compressed_data)
			pass
		else:
			# For the sake of this implementation rest of the chunk types are not handled.
			var chunk_data = file.get_buffer(chunk_size)

		var crc = file.get_buffer(4)

func _decompress_zlib(compressed_data: PackedByteArray):
	var bit_reader = BitReader.new(compressed_data)
	
	# zlib header
	var cmf = bit_reader.get_next_bits(8)
	var fcheck = bit_reader.get_next_bits(5)
	var fdict = bit_reader.get_next_bits(1)
	var flevel = bit_reader.get_next_bits(2)
	
	# Inflate
	uncompressed_image_data = []
	while(bit_reader.has_next()):
		# read-block til end
		var bfinal = bit_reader.get_next_bits(1)
		var btype = bit_reader.get_next_bits(2)

		if btype == 0:
			# no compression
			bit_reader.skip_to_next_byte()
			var len = bit_reader.get_next_bits(8) | (bit_reader.get_next_bits(8) << 8)
			var nlen = bit_reader.get_next_bits(8) | (bit_reader.get_next_bits(8) << 8)

			for i in len:
				var data = bit_reader.get_next_bits(8)
				uncompressed_image_data.push_back(data)
		elif btype == 1:
			# huffman
			var fixed_huffman_table = _generate_fixed_ll_huffman_map()
			var fixed_distance_table = _generate_fixed_distance_huffman_map()
			_inflate(fixed_huffman_table, fixed_distance_table, bit_reader, uncompressed_image_data)
		elif btype == 2:
			# dynamic huffman
			var hlit = bit_reader.get_next_bits(5) + 257  # Number of Literal/Length codes
			var hdist = bit_reader.get_next_bits(5) + 1 # Number of Distance codes
			var hclen = bit_reader.get_next_bits(4) + 4 # Number of Code Length codes
				
			if hlit > MAXLCODES || hdist > MAXDCODES:
				push_error("Bad code count for dynamic huffman.")
				return null
				
			var cl_code_to_length = {}
			# (hclen + 4) amount of 3-bit values of code length of  "Code Length Code"
			for n in hclen:
				var code_length_code = CODELENGTH_CODELENGTH_ORDER[n]
				cl_code_to_length[code_length_code] = bit_reader.get_next_bits(3)
				
			var cl_code_table = _generate_huffman_code_table(cl_code_to_length, CODELENGTHCODECOUNT)

			var symbol_to_code_length = {}
			var n = 0
			while n < hlit + hdist :
				var cl_code = 0
				var cl_code_length = 0
				while (!cl_code_table.has(cl_code) || cl_code_table[cl_code]["length"] != cl_code_length):
					cl_code = (cl_code << 1) | bit_reader.get_next_bit()
					cl_code_length += 1

				var code_length_symbol = cl_code_table[cl_code]["symbol"]
				var code_length = 0
				var repeat = 1
				if code_length_symbol <= 15:
					# literal
					code_length = code_length_symbol
				elif code_length_symbol == 16:
					# copy previous length 3 + (value of 2 bits) times.
					repeat = bit_reader.get_next_bits(2) + 3
					code_length = symbol_to_code_length[n - 1]
				elif code_length_symbol == 17:
					# repeat 0 for 3 + (value of 3 bits) times.
					repeat = bit_reader.get_next_bits(3) + 3
				elif code_length_symbol == 18:
					# repeat 0 for 11 + (value of 7 bits) times.
					repeat = bit_reader.get_next_bits(7) + 11

				for i in repeat:
					symbol_to_code_length[n] = code_length
					n += 1

			var ll_code_length = {}
			var distance_code_length = {}
			for symbol in symbol_to_code_length:
				if symbol < hlit:
					ll_code_length[symbol] = symbol_to_code_length[symbol]
				else:
					distance_code_length[symbol - hlit] = symbol_to_code_length[symbol]

			var dynamic_huffman_table = _generate_huffman_code_table(ll_code_length, MAXLCODES)
			var dynamic_distance_table = _generate_huffman_code_table(distance_code_length, MAXDCODES)
			_inflate(dynamic_huffman_table, dynamic_distance_table, bit_reader, uncompressed_image_data)
		elif btype == 3:
			# reserved (error)
			print ("error")
			pass
		
		var cleaned_image_data: Array[int] = []
		print(uncompressed_image_data)
		for h in height:
			for w in width + 1:
				if w != 0:
					print(w + (h * (width + 1)))
					cleaned_image_data.push_back(uncompressed_image_data[w + (h * (width + 1))])
					
		uncompressed_image_data = cleaned_image_data
		if bfinal == 1:
			break

# Inflate (uncompress Deflate) given the literal/length huffman table, distance code table, and bit_stream.
# Resulting data is written at the tail of provided "out" array as a byte per element in-order.
func _inflate(ll_table: Dictionary, d_table: Dictionary, bit_stream: BitReader, out: Array[int]):
	while(1):
		var code = 0
		for n in MAXBITS:
			code = (code << 1) | bit_stream.get_next_bit()
			if ll_table.has(code) && ll_table[code]["length"] == n + 1:
				break
		var symbol = ll_table[code]["symbol"]
		if symbol == 256:
			break
		elif symbol < 256:
			# literal
			out.push_back(symbol)
		else:
			# distance
			var length = LENGTH_TABLE[symbol][0]
			var extra_bits = LENGTH_TABLE[symbol][1]
			if extra_bits > 0:
				length += bit_stream.get_next_bits(extra_bits)

			var d_code = 0
			for n in MAXBITS:
				d_code = (d_code << 1) | bit_stream.get_next_bit()
				if d_table.has(d_code) && d_table[d_code]["length"] == n + 1:
					break
			var distance_symbol = d_table[d_code]["symbol"]
			
			var distance = DISTANCE_TABLE[distance_symbol][0]
			var distance_extra_bits = DISTANCE_TABLE[distance_symbol][1]
			if distance_extra_bits > 0:
				distance += bit_stream.get_next_bits(distance_extra_bits)
			
			_copy_bytes(length, distance, out)

# Copy bytes starting at [distance] away from the current position for [length] bytes.
func _copy_bytes(length: int, distance: int, data: Array[int]):
	# copy from position all the way to length
	var copy_byte_index = data.size() - distance
	
	var copy_byte = 0
	for n in length:
		var target_byte_value = data[n + copy_byte_index]
		data.push_back(target_byte_value)

# generates a huffman code to literal/length symbol map
func _generate_fixed_ll_huffman_map():
	var ll_to_code_length = {}
	for n in FIXLCODES:
		var code_length = _get_ll_code_length(n)
		ll_to_code_length[n] = code_length
	return _generate_huffman_code_table(ll_to_code_length, FIXLCODES)

func _generate_fixed_distance_huffman_map():
	var distance_to_code = {}
	for n in FIXDCODES:
		var code_length = _get_distance_code_length(n)
		distance_to_code[n] = code_length
	return _generate_huffman_code_table(distance_to_code, FIXDCODES)

# Compute huffman code table given a map of Symbol to their Code's length.
# max_symbol = maximum number of symbols for this particular code.
func _generate_huffman_code_table(symbol_to_length: Dictionary, max_symbol):
	var length_to_freq = []
	
	for n in MAXBITS:
		length_to_freq.push_back(0)
	for symbol in symbol_to_length:
		var code_length = symbol_to_length[symbol]
		if code_length != 0:
			length_to_freq[code_length] += 1
	
	var current_code_at_length = [0]
	for bits in MAXBITS:
		var next_code = (current_code_at_length[bits] + length_to_freq[bits]) << 1
		current_code_at_length.push_back(next_code)

	var code_to_symbol = {}
	for symbol in max_symbol:
		if symbol_to_length.has(symbol) && symbol_to_length[symbol] != 0:
			var code_length = symbol_to_length[symbol]
			var current_code = current_code_at_length[symbol_to_length[symbol]]

			code_to_symbol[current_code] = {
				"symbol": symbol,
				"length": symbol_to_length[symbol]
			}
			current_code_at_length[symbol_to_length[symbol]] += 1

	return code_to_symbol

# Retrieve huffman code length given the literal value/symbol
func _get_ll_code_length(symbol:int):
	if symbol >= 0 && symbol <= 143:
		return 8
	elif symbol >= 144 && symbol <= 255:
		return 9
	elif symbol >= 256 && symbol <= 279:
		return 7
	elif symbol >= 280 && symbol <= 287:
		return 8
	
# Retrieve the huffman code length for the distance code
func _get_distance_code_length(symbol: int):
	if symbol >= 0 && symbol <= 30:
		return 5
	
	return _get_ll_code_length(symbol)

# Get Pixels as array of int.
# If the image is in PALETTE mode, each pixel will contain the index of palette.
# Otherwise, each pixel will contain RGB values.
func get_pixels():
	return uncompressed_image_data

# Gets the palette as array of Color.
# Note: Returns empty array if the image is not saved in PALETTE mode.
func get_palette() -> Array[Color]:
	return palette
