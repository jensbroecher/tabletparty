extends CanvasLayer

var color_rect: ColorRect
var material: ShaderMaterial
var is_transitioning := false

func _ready():
	process_mode = PROCESS_MODE_ALWAYS
	layer = 128
	
	color_rect = ColorRect.new()
	color_rect.anchors_preset = Control.PRESET_FULL_RECT
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.visible = false
	add_child(color_rect)
	
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform bool invert = false;

void fragment() {
    float alpha = 0.0;
    if (!invert) {
        float border = 1.0 - progress;
        alpha = smoothstep(border + 0.05, border - 0.05, UV.x);
    } else {
        float border = progress;
        alpha = smoothstep(border + 0.05, border - 0.05, UV.x);
    }
    COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""
	material = ShaderMaterial.new()
	material.shader = shader
	color_rect.material = material

func change_scene(target_scene_path: String):
	if is_transitioning:
		return
	is_transitioning = true
	
	color_rect.visible = true
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Transition in: Progress 0 to 1
	material.set_shader_parameter("invert", false)
	material.set_shader_parameter("progress", 0.0)
	
	var tween = create_tween()
	tween.tween_property(material, "shader_parameter/progress", 1.0, 0.45)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	# Change scene
	get_tree().change_scene_to_file(target_scene_path)
	
	# Small delay to let scene load
	await get_tree().create_timer(0.05).timeout
	
	# Transition out: Progress 0 to 1
	material.set_shader_parameter("invert", true)
	material.set_shader_parameter("progress", 0.0)
	
	var tween_out = create_tween()
	tween_out.tween_property(material, "shader_parameter/progress", 1.0, 0.45)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween_out.finished
	
	color_rect.visible = false
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false

func reload_scene():
	if is_transitioning:
		return
	change_scene(get_tree().current_scene.scene_file_path)
