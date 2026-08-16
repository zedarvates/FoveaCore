using Godot;
using System;

namespace FoveaEngine
{
    [Tool]
    public partial class FoveaSplatEditorPlugin : EditorPlugin
    {
        private FoveaSplatImporter _importer;
        private EditorDock _dock;

        private FoveaSplatSelectionTool _selectionTool = new FoveaSplatSelectionTool();
        private FoveaSplatBrushTool _brushTool = new FoveaSplatBrushTool();

        public enum EditMode { None, Select, Paint, SculptAdd, SculptRemove, Recalibrate, Merge }
        public EditMode ActiveEditMode { get; set; } = EditMode.None;

        public FoveaSplatBrushTool GetBrushTool() => _brushTool;
        public FoveaSplatSelectionTool GetSelectionTool() => _selectionTool;

        public override void _EnterTree()
        {
            GD.Print("FoveaSplatEditorPlugin: Activating Gaussian Splat Suite...");

            // 1. Register File Importer
            _importer = new FoveaSplatImporter();
            AddImportPlugin(_importer);

            // 2. Register Node Types
            var icon = GD.Load<Texture2D>("res://icon.svg");

            var scriptNode = GD.Load<Script>("res://addons/fovea_engine/core/FoveaSplatNode3D.cs");
            AddCustomType("FoveaSplatNode3D", "Node3D", scriptNode, icon);

            var scriptInstancer = GD.Load<Script>("res://addons/fovea_engine/core/FoveaSplatInstancer.cs");
            AddCustomType("FoveaSplatInstancer", "Node3D", scriptInstancer, icon);

            var scriptAnimator = GD.Load<Script>("res://addons/fovea_engine/core/FoveaSplatAnimator.cs");
            AddCustomType("FoveaSplatAnimator", "Node", scriptAnimator, icon);

            var scriptRenderer = GD.Load<Script>("res://addons/fovea_engine/render/FoveaSplatRenderer.cs");
            AddCustomType("FoveaSplatRenderer", "MultiMeshInstance3D", scriptRenderer, icon);

            // 3. Add Splat Manager UI Dock
            try
            {
                var dockScene = GD.Load<PackedScene>("res://addons/fovea_engine/ui/FoveaSplatManagerUI.tscn");
                if (dockScene != null)
                {
                    var dockContent = (Control)dockScene.Instantiate();
                    if (dockContent is FoveaSplatManagerUI managerUI)
                    {
                        managerUI.InitializePlugin(this);
                    }

                    _dock = new EditorDock
                    {
                        Title = "Fovea Splats",
                        DefaultSlot = EditorDock.DockSlot.LeftUr,
                        AvailableLayouts = EditorDock.DockLayout.All,
                    };
                    _dock.AddChild(dockContent);
                    AddDock(_dock);
                    GD.Print("FoveaSplatEditorPlugin: Splat Manager UI Dock registered.");
                }
            }
            catch (Exception ex)
            {
                GD.PushError($"FoveaSplatEditorPlugin: Failed to load UI dock: {ex.Message}");
            }
        }

        public override void _ExitTree()
        {
            GD.Print("FoveaSplatEditorPlugin: Deactivating Gaussian Splat Suite...");

            // Remove Node Types
            RemoveCustomType("FoveaSplatNode3D");
            RemoveCustomType("FoveaSplatInstancer");
            RemoveCustomType("FoveaSplatAnimator");
            RemoveCustomType("FoveaSplatRenderer");

            // Remove Importer
            if (_importer != null)
            {
                RemoveImportPlugin(_importer);
                _importer = null;
            }

            // Remove UI Dock
            if (_dock != null)
            {
                RemoveDock(_dock);
                _dock.QueueFree();
                _dock = null;
            }
        }

        public override string _GetPluginName() => "Fovea Gaussian Splat Suite";

        public override int _Forward3DGuiInput(Camera3D viewportCamera, InputEvent @event)
        {
            if (ActiveEditMode == EditMode.None) return (int)AfterGuiInput.Pass;

            // Get selected node in editor
            var selection = EditorInterface.Singleton.GetSelection();
            var selectedNodes = selection.GetSelectedNodes();
            if (selectedNodes.Count == 0 || !(selectedNodes[0] is FoveaSplatNode3D splatNode))
            {
                return (int)AfterGuiInput.Pass;
            }

            if (@event is InputEventMouseButton mouseBtn)
            {
                if (mouseBtn.ButtonIndex == MouseButton.Left)
                {
                    if (mouseBtn.Pressed)
                    {
                        ApplyTool(viewportCamera, mouseBtn.Position, splatNode);
                        return (int)AfterGuiInput.Stop;
                    }
                }
            }
            else if (@event is InputEventMouseMotion mouseMotion)
            {
                if ((mouseMotion.ButtonMask & MouseButtonMask.Left) != 0)
                {
                    ApplyTool(viewportCamera, mouseMotion.Position, splatNode);
                    return (int)AfterGuiInput.Stop;
                }
            }

            return (int)AfterGuiInput.Pass;
        }

        private void ApplyTool(Camera3D camera, Vector2 mousePos, FoveaSplatNode3D node)
        {
            if (node == null || node.SplatResource == null || node.SplatCount == 0) return;

            Vector3 rayOrigin = camera.ProjectRayOrigin(mousePos);
            Vector3 rayDir = camera.ProjectRayNormal(mousePos);

            // Raycast into splats to define brush focus point
            int hitIdx = _selectionTool.SelectIndividual(node, rayOrigin, rayDir);
            if (hitIdx == -1) return;

            Vector3 hitPosWorld = node.GlobalTransform * node.SplatResource.Positions[hitIdx];

            switch (ActiveEditMode)
            {
                case EditMode.Select:
                    _selectionTool.SelectZone(node, hitPosWorld, _brushTool.BrushRadius);
                    break;
                case EditMode.Paint:
                    _brushTool.Paint(node, hitPosWorld);
                    break;
                case EditMode.SculptAdd:
                    _brushTool.SculptDensity(node, hitPosWorld, add: true);
                    break;
                case EditMode.SculptRemove:
                    _brushTool.SculptDensity(node, hitPosWorld, add: false);
                    break;
                case EditMode.Recalibrate:
                    _brushTool.RecalibrateCovariance(node, hitPosWorld);
                    break;
                case EditMode.Merge:
                    _brushTool.MergeClusters(node, hitPosWorld);
                    break;
            }
        }
    }
}
