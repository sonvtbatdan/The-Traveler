tool
extends MeshInstance

# This toolscript is used for setting up sea material parameters
# critical for its functionality such as : 
# - ground influences
# - adaptive noise
# - mesh offset positioning
# - various parameters
# Despite not attached to the parent MeshInstance, this sea material
# will still work just fine, except for some features that needs special parameters
# ---------------------------
# Author : Michael Herman
# Last Updated : 18/02/2022
# Version : 1.0

export (Array, NodePath) var points_of_influence
export (bool) var override_center_offset = true
export (bool) var show_debug_output = true
export (bool) var generate_noise = false
export (bool) var default_on_load = false

enum PRINT {WARNING, ERROR}
const RADIUS = 10.0

onready var material;

func _ready():
	if not self.mesh :
		printdebug("Object : (" + String(self.name)
			+ ") contain no mesh object or not of MeshInstance type", PRINT.ERROR)
		return
	if self.get_surface_material(0) :
		material = self.get_surface_material(0)
		update_shader_parameters()
	else :
		printdebug("Material not found, please assign it to index-0", PRINT.WARNING)
	
func log10(var a):
	return log(a) / log(10)
	
func log2(var a):
	return log(a) / log(2)
	
func printdebug(var data, var type = ""):
	if not show_debug_output : 
		return
	match type: 
		PRINT.WARNING :
			push_warning(data)
			pass
		PRINT.ERROR : 
			push_error(data)
			pass
		_ : print(data)

func default_noise(var w, var h):
	var simplex_noise = OpenSimplexNoise.new()
	var noise_texture = NoiseTexture.new()
	simplex_noise.seed = randi() % 10
	simplex_noise.octaves = 3
	simplex_noise.period = 30.0
	simplex_noise.persistence = 0.8
	noise_texture.width = pow(2.0, ceil(log2(w)))
	noise_texture.height = pow(2.0, ceil(log2(h)))
	noise_texture.noise = simplex_noise
	noise_texture.seamless = true
	return noise_texture
	
func image_to_texture(var img : Image) :
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex
	
func update_shader_parameters():
	# Scripts for options processing
	# and some parameters intialization
	var mesh_size = self.mesh.get_aabb().size
	var mesh_sub_z = self.mesh.subdivide_depth
	var mesh_sub_x = self.mesh.subdivide_width
	material.set_shader_param("mesh_size", Vector2(mesh_size.x, mesh_size.z).floor())
	if default_on_load:
		default_on_load = false
		self.translation = Vector3(0.0, 0.0 ,0.0)
		self.mesh.center_offset = Vector3(0.0, 0.0, 0.0)
		material.set_shader_param("roughness", 0.1)
		material.set_shader_param("wave_speed", 0.3)
		material.set_shader_param("wave_direction", Vector2(1.0,0.0))
		material.set_shader_param("reflectiveness", 0.5)
		material.set_shader_param("ground_influence", 0.7)
		material.set_shader_param("wave_length", mesh_size.x / 10.0)
		printdebug("parameter reset to default", PRINT.WARNING)
	if generate_noise:
		material.set_shader_param("noise", default_noise(mesh_sub_x, mesh_sub_z))
		printdebug("custom noise generated ", PRINT.WARNING)
	if override_center_offset:
		override_center_offset = false;
		var w = mesh_size.x / 2.0
		var h = mesh_size.z / 2.0
		self.mesh.center_offset = Vector3(w, 0.0, h)
		self.translation += Vector3(-w, 0.0, -h)
		printdebug("offseting mesh")
	
	# Now, Iterate through points of influence,
	# store the translation and radius in to image pixels
	# send image as texture to shader parameters
	var img = Image.new()
	if points_of_influence.empty():
		printdebug("Empty points of influence")
		img.create(1, 1, false, Image.FORMAT_RGBAF)
		img.lock()
		img.set_pixel(0, 0, Color(0.0, 0.0, 0.0, RADIUS))
		material.set_shader_param("grounds_arr", image_to_texture(img))
		material.set_shader_param("grounds_arr_length", 0)
		printdebug("shader's parameters updated", PRINT.WARNING)
		return # If empty quit procedure

	img.create(points_of_influence.size(), 1, false, Image.FORMAT_RGBAF)
	img.lock()
	img.set_pixel(0, 0, Color(0.0, 0.0, 0.0))
	var col = 0; # Keep record of valid point influence
	for path in points_of_influence:
		if not get_node(path) :
			# If any element of array is empty, skip
			printdebug("Node Not found or Path is Empty", PRINT.ERROR) 
			continue
		if not (get_node(path) is Spatial):
			# Register only spatial node position, otherwise skip
			printdebug("Point of Influence object does not inherit spatial type, path: " + path, PRINT.ERROR)
			continue
			
		var node = get_node(path)
		var pos = to_global(node.translation)
		var radius = RADIUS
		printdebug("Object : " + node.get_name() + ", Add Locations : " + String(pos))
		
		if node is MeshInstance:
			if node.mesh and node.mesh.has_method("get_radius"):
				radius = node.mesh.radius * node.scale.x
			elif node.mesh:
				var box = node.mesh.get_aabb();
				radius = sqrt((box.size.x * box.size.x) + (box.size.z * box.size.z)) / 2.0
		
		if node is CollisionShape:
			if node.shape and node.shape.has_method("get_radius"):
				radius = node.shape.radius * node.scale.x
		printdebug("Object : " + node.get_name() + ", set radius : " + String(radius))
		img.set_pixel(col, 0, Color(pos.x, pos.y, pos.z, radius))
		col += 1
	material.set_shader_param("grounds_arr", image_to_texture(img))
	material.set_shader_param("grounds_arr_length", col)
	img.unlock()
	printdebug("shader's parameters updated", PRINT.WARNING)



