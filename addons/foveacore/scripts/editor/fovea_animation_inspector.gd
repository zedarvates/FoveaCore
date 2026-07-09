@tool
extends EditorPlugin
func _handles(object: Object) -> bool:
	return object is FoveaMaterialOscillation or object is FoveaFlowFieldAnimator or object is FoveaMorphCovarianceAnimator
func _edit(object: Object) -> void: pass
func _make_visible(visible: bool) -> void: pass
