# ComfyUI image-to-splat bridge

`ComfyUISplatBridge` connects an API-format ComfyUI workflow to the stable
`FoveaSplat3D` node. It can upload an input image, inject its server-side name
into a selected `LoadImage` node, submit the workflow, poll its history, and
download the first supported Gaussian-splat artifact.

Supported output formats are `.fovea`, `.ply`, and `.splat`. The bridge checks
the format signature or structural stride before writing any response body.
Destinations must stay inside `res://` or `user://` and must not already exist.

## Example

Export a workflow using ComfyUI's API format, then load its JSON graph in Godot:

```gdscript
var bridge := ComfyUISplatBridge.new()
bridge.comfyui_url = "http://127.0.0.1:8188"

var workflow_text := FileAccess.get_file_as_string("res://workflows/image_to_3dgs.json")
var workflow: Dictionary = JSON.parse_string(workflow_text)
var target := FoveaSplat3D.new()
add_child(target)

bridge.generate_splat_from_image(
	source_image,
	workflow,
	"11", # LoadImage node ID in this workflow
	"user://generated/bonsai.ply",
	target,
	func(result: Dictionary) -> void:
		if result.get("ok", false):
			print("Imported: ", result["path"])
		else:
			push_error(result.get("error", "ComfyUI import failed"))
)
```

The destination extension must match the artifact returned by the workflow.
Use a unique destination for every generation; the bridge refuses to overwrite
an existing asset.

## Expected ComfyUI output

The completed history entry must expose a file descriptor somewhere under an
output node. Output node IDs and collection keys are not hard-coded:

```json
{
  "outputs": {
    "42": {
      "files": [
        {
          "filename": "bonsai.ply",
          "subfolder": "fovea/3dgs",
          "type": "output"
        }
      ]
    }
  }
}
```

## Validation boundary

The automated loopback test proves the Godot HTTP exchange, workflow image
injection, artifact discovery, file validation, persistence, and loading into
`FoveaSplat3D`. It does not prove compatibility with a particular ComfyUI
custom node, model checkpoint, 3DGS pipeline, Blender setup, or generated asset.
Those requirements must be recorded and validated with a reviewed reference
workflow before this integration can be promoted beyond experimental status.

Run the local contract checks with the CI-pinned Godot binary:

```bash
godot --headless --path . -s res://addons/foveacore/test/test_comfyui_splat_bridge.gd
python tools/test_comfyui_splat_http.py --godot /path/to/godot
```
