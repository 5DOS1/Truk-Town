extends Controller
class_name Bot

const FOV : float = 120.0
const PERCEPTION_RANGE : float = 500.0
const FIRE_RANGE : float = 100.0
const TURN_RATE : float = 15.0

var brain : StackFSM
var target : Spatial
var thinking : bool = false
var navigation : Navigation
var point : Vector3

var random_dir : int = 0
var target_visible : bool = false

func _ready():
	# A delay for actions
	var _think_timeout = $think.connect("timeout", self, "_on_think_end")
	# Main state machine
	brain = StackFSM.new()
	add_child(brain)
	brain.push_state("roam")
	# Navigation
	navigation = Game.main.get_node("map/nav")

func _physics_process(delta):
	if character.state != character.DEAD:
		character.process_actions()
		character.process_movement(delta)
		character.process_rotations(delta)
	# Send state to server
	send_state()

func roam():
	# Stop unnecessary actions
	character.action = 0b00000000
	# Choosing random point from the interest points of the map
	if target:
		brain.push_state("chase")
	if point == Vector3.ZERO:
		point = Game.interest_points[randi() % Game.interest_points.size()].translation
		character.set_action(0, true)
	else:
		# Form the path
		var path = navigation.get_simple_path(character.translation, point, true)
		# If we get a path remove the first closest point and look at further one moving forward
		if path.size() > 1 and character.translation.distance_to(point) >= 1.0:
			path.remove(0)
			look_at_point(path[0])
			character.set_action(0, true)
		else:
			character.set_action(0, false)
			point = Vector3.ZERO
	
	if !thinking:
		thinking = true
		$think.start(rand_range(0.1, 1.0))
		target = get_closest()

func chase():
	if target == null or target.state == target.DEAD or target == self:
		brain.pop_state()
		return
	
	if !thinking:
		target_visible = target_is_visible(target, FOV, FIRE_RANGE)
	
	# Firing and random zig-zag movement
	if character.translation.distance_to(target.translation) <= FIRE_RANGE and target_visible and !thinking:
			character.set_action(5, true)
			random_dir = randi() % 3 - 1
			character.set_action(2, random_dir == -1)
			character.set_action(3, random_dir == 1)
			character.set_action(4, randi() % 100 == 0)
	else:
		character.set_action(2, false)
		character.set_action(3, false)
		character.set_action(4, false)
		character.set_action(5, false)
	
	var path = navigation.get_simple_path(character.translation, target.translation, true)
	if !path:
		look_at_target(target)
		character.set_action(0, true)
	else:
		path.remove(0)
		look_at_point(path[0])
		character.set_action(0, character.translation.distance_squared_to(target.translation) > 9.0)
#		look_at_target(target)
#		var distance_ok = character.translation.distance_squared_to(target.translation) > 9.0
#		var dir = ((path[0] - character.global_transform.origin) * character.global_transform.basis.z).normalized()
#		character.set_action(0, dir.z < -0.0 and distance_ok)
#		character.set_action(1, dir.z > 0.0 and distance_ok)
#		character.set_action(2, dir.x < -0.0 and distance_ok)
#		character.set_action(3, dir.x > 0.0 and distance_ok)

	if !thinking:
		thinking = true
		$think.start(rand_range(0.1, 0.5))

func target_is_visible(t, fov, distance):
	var facing = -character.head.global_transform.basis.z
	var to_target = t.translation - character.head.global_transform.origin
	var space_state = character.get_world().direct_space_state
	var result = space_state.intersect_ray(character.head.global_transform.origin, t.global_transform.origin, [self], 9)
	var result_target : Node
	if result:
		if result.collider is Character:
			result_target = result.collider
	return rad2deg(facing.angle_to(to_target)) < fov and character.head.global_transform.origin.distance_to(t.global_transform.origin) <= distance and result_target == t

func look_at_point(p):
	if p == character.global_transform.origin:
		return
	var new_transform = character.transform.looking_at(Vector3(p.x, character.transform.origin.y, p.z), Vector3.UP)
	character.transform = character.transform.interpolate_with(new_transform, get_physics_process_delta_time() * TURN_RATE)
	character.head.rotation = Vector3.ZERO
	#var new_head_transform = character.head.global_transform.looking_at(Vector3(p.x, p.y, p.z), Vector3.UP)
	#character.head.global_transform = character.head.global_transform.interpolate_with(new_head_transform, get_physics_process_delta_time() * TURN_RATE)

func look_at_target(t):
	if t == self:
		t = null
		return
	var new_char_transform = character.transform.looking_at(Vector3(t.translation.x, character.translation.y, t.translation.z), Vector3.UP)
	character.transform = character.transform.interpolate_with(new_char_transform, get_physics_process_delta_time() * TURN_RATE)
	# Aim for the head
	var new_head_transform = character.head.global_transform.looking_at(Vector3(t.head.global_transform.origin.x, t.head.global_transform.origin.y, t.head.global_transform.origin.z), Vector3.UP)
	character.head.global_transform = character.head.global_transform.interpolate_with(new_head_transform, get_physics_process_delta_time() * TURN_RATE)

func _on_think_end():
	thinking = false

# Get closeset character
func get_closest():
	var min_dist = INF
	var closest = null
	var characters = Game.main.get_node("characters").get_children()
	for c in characters:
		if c == self:
			continue
		# Aliens don't attack each other
		if character.get_node("mesh").has_method("is_alien") and c.get_node("mesh").has_method("is_alien"):
			continue
		var dist = character.translation.distance_to(c.translation)
		if dist < min_dist and target_is_visible(c, FOV, PERCEPTION_RANGE) and c.state != character.DEAD:
			min_dist = dist
			closest = c
	return closest

# For type checking
func is_bot():
	return true

# Networking
func send_state():
	var new_state = Game.State.new(character.translation, character.rotation.y, character.head.rotation.x, character.vel, character.state, character.action, character.health, character.score, OS.get_system_time_msecs())
	Game.main.update_bot_state(character.name, new_state)
