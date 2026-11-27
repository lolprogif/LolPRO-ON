extends Node3D

var limbs: Array[Node3D] = []
var phase := 0.0
var motion := "Idle"
var armor := Color("20232c")
var gold := Color("c69a46")
var skin := Color("cda18a")

func part(parent: Node3D, pos: Vector3, dims: Vector3, tint: Color, rounded: bool = false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if rounded:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		m.mesh = sphere
		m.scale = dims
	else:
		var box := BoxMesh.new()
		box.size = dims
		m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = 0.65 if tint == gold or tint == armor else 0.0
	m.material_override = mat
	parent.add_child(m)
	m.position = pos
	return m

func _ready():
	part(self,Vector3(0,1.16,0),Vector3(0.52,0.58,0.32),armor,true)
	part(self,Vector3(0,0.91,0),Vector3(0.46,0.13,0.34),gold)
	part(self,Vector3(0,1.65,0),Vector3(0.29,0.35,0.28),skin,true)
	part(self,Vector3(0,1.79,0),Vector3(0.33,0.20,0.31),Color("e4e6ef"),true)
	for i in range(5):
		var tuft := part(self,Vector3(-0.12+i*0.06,1.88,-0.02),Vector3(0.08,0.19,0.11),Color("e4e6ef"),true)
		tuft.rotation.z = -0.3
	for side in [-1,1]:
		var arm := Node3D.new()
		add_child(arm)
		arm.position = Vector3(side*0.34,1.39,0)
		part(arm,Vector3(0,-0.04,0),Vector3(0.27,0.23,0.33),gold,true)
		part(arm,Vector3(0,-0.28,0),Vector3(0.16,0.43,0.19),armor,true)
		part(arm,Vector3(0,-0.48,0),Vector3(0.14,0.17,0.15),skin,true)
		limbs.append(arm)
		var leg := Node3D.new()
		add_child(leg)
		leg.position = Vector3(side*0.14,0.86,0)
		part(leg,Vector3(0,-0.32,0),Vector3(0.21,0.68,0.23),armor,true)
		part(leg,Vector3(0,-0.39,0.10),Vector3(0.19,0.19,0.08),gold,true)
		part(leg,Vector3(0,-0.77,0.05),Vector3(0.23,0.18,0.33),armor)
		limbs.append(leg)
	part(self,Vector3(0,0.68,0.18),Vector3(0.20,0.48,0.05),Color("791e29"))
	var sword := part(self,Vector3(0,1.03,-0.25),Vector3(0.10,1.20,0.06),gold)
	sword.rotation.z = 0.48

func set_motion(state: String):
	motion = state

func _process(delta):
	phase += delta * (11.0 if motion == "Running" else 6.0)
	var amplitude := 0.65 if motion == "Running" else (0.40 if motion == "Walking" else 0.025)
	if motion == "Jumping":
		amplitude = 0.0
	for i in range(limbs.size()):
		var sign_value := 1.0 if i == 0 or i == 3 else -1.0
		limbs[i].rotation.x = lerpf(limbs[i].rotation.x,sin(phase)*amplitude*sign_value,minf(delta*15.0,1.0))
