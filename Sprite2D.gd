@tool
extends Sprite2D

var palette: Array[Color]
@onready var PNGReader = preload("res://png_reader.gd")

func _ready():
	pass

func _process(delta):
	if get_material().get_shader_parameter("index_as_r") == null :
		var png_reader = PNGReader.new(texture.resource_path)
		var pixelBytes = PackedByteArray(png_reader.get_pixels())
		var image = Image.create_from_data(
				png_reader.width, png_reader.height, false, Image.FORMAT_R8, pixelBytes)
		var index_texture = ImageTexture.create_from_image(image)
		
		get_material().set_shader_parameter("index_as_r", index_texture)
