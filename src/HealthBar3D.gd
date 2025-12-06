extends Node3D
class_name HealthBar3D

@export var max_width: float = 0.2
@export var height: float = 0.1
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.8) # Dark gray with alpha 0.8
@export var health_color: Color = Color.GREEN
@export var low_health_color: Color = Color.RED

const BAR_WIDTH_PIXELS = 100
const BAR_HEIGHT_PIXELS = 10
const HEIGHT_ABOVE_UNIT_FACTOR: float = 1.5

var sprite: Sprite3D

func _init():
	"""
	Constructor. Initializes the Sprite3D node and sets up its basic properties like billboard mode and pixel size.
	"""
	# Create new Sprite3D node
	sprite = Sprite3D.new()
	
	# Set billboard_mode to BILLBOARD_ENABLED
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	
	# Set pixel_size to 0.01
	sprite.pixel_size = max_width / BAR_WIDTH_PIXELS
	
	
	# Add Sprite3D as child
	add_child(sprite)

# Adds a function called setup that takes unit_size as Vector3 parameter
func setup(unit_size: Vector3):
	"""
	Configures the health bar dimensions and vertical position relative to the unit size.

	Arguments:
	- unit_size (Vector3): The scaled AABB size of the associated unit mesh.
	"""
	# Calculate max_width based on unit_size.x, for example max_width = unit_size.x * 0.8
	max_width = unit_size.x
	
	# Set Node3D position in world coordinates
	position.y = unit_size.y * HEIGHT_ABOVE_UNIT_FACTOR
	
	# Calculate and set pixel size based on new max_width
	sprite.pixel_size = max_width / BAR_WIDTH_PIXELS
	
	# Initial update is now handled by the caller (Unit.gd) after setup()

# Create update_health function that takes current health and maximum health as parameters
func update_health(current_health: float, maximum_health: float):
	"""
	Generates a new ImageTexture to visually represent the current health percentage.
	The bar color interpolates from red (low health) to green (full health).

	Arguments:
	- current_health (float): The current health value of the unit.
	- maximum_health (float): The maximum possible health value.
	"""
	# Calculate health percentage as current divided by maximum
	var health_percentage: float = current_health / maximum_health
	health_percentage = clampf(health_percentage, 0.0, 1.0) # Ensure it's between 0 and 1
	
	# Create new Image with width 100 and height 10 pixels
	# Image.create takes width, height, use_mipmaps (false), format (FORMAT_RGBA8)
	var image = Image.create(BAR_WIDTH_PIXELS, BAR_HEIGHT_PIXELS, false, Image.FORMAT_RGBA8)
	
	# Fill entire image with background_color using fill method
	image.fill(background_color)
	
	# Calculate health bar pixel width as health percentage times 100
	var health_bar_pixel_width: int = int(health_percentage * BAR_WIDTH_PIXELS)
	
	if health_bar_pixel_width > 0:
		# Interpolate color between low_health_color (0%) and health_color (100%)
		var bar_color: Color = low_health_color.lerp(health_color, health_percentage)
		
		# Use fill_rect to draw health portion from x=0, y=0, width=calculated width, height=10
		var rect_to_fill = Rect2i(0, 0, health_bar_pixel_width, BAR_HEIGHT_PIXELS)
		image.fill_rect(rect_to_fill, bar_color)
		
	# Create ImageTexture from Image using create_from_image
	var texture = ImageTexture.create_from_image(image)
	
	# Assign ImageTexture to sprite.texture property
	sprite.texture = texture
