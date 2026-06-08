using Godot;
using System;

namespace FoveaEngine
{
    [Tool]
    public partial class FoveaSplatManagerUI : Control
    {
        private Label _splatCountLabel;
        private Label _memoryLabel;
        private Label _activeLodLabel;

        private Button _importButton;
        private Button _convertButton;
        private Button _optimizeButton;
        private Button _bakeButton;
        private Button _exportButton;

        // Interactive Brush Controls
        private OptionButton _editModeDropdown;
        private HSlider _radiusSlider;
        private HSlider _strengthSlider;
        private ColorPickerButton _colorPicker;

        private FoveaSplatNode3D _activeNode;
        private FoveaSplatEditorPlugin _plugin;

        public void InitializePlugin(FoveaSplatEditorPlugin plugin)
        {
            _plugin = plugin;
            UpdateBrushToolValues();
        }

        public override void _Ready()
        {
            // Bind labels
            _splatCountLabel = GetNode<Label>("%SplatCountLabel");
            _memoryLabel = GetNode<Label>("%MemoryLabel");
            _activeLodLabel = GetNode<Label>("%ActiveLodLabel");

            // Bind buttons
            _importButton = GetNode<Button>("%ImportButton");
            _convertButton = GetNode<Button>("%ConvertButton");
            _optimizeButton = GetNode<Button>("%OptimizeButton");
            _bakeButton = GetNode<Button>("%BakeButton");
            _exportButton = GetNode<Button>("%ExportButton");

            // Bind brush controls
            _editModeDropdown = GetNodeOrNull<OptionButton>("%EditModeDropdown");
            _radiusSlider = GetNodeOrNull<HSlider>("%RadiusSlider");
            _strengthSlider = GetNodeOrNull<HSlider>("%StrengthSlider");
            _colorPicker = GetNodeOrNull<ColorPickerButton>("%ColorPicker");

            // Wire events
            _importButton.Pressed += OnImportPressed;
            _convertButton.Pressed += OnConvertPressed;
            _optimizeButton.Pressed += OnOptimizePressed;
            _bakeButton.Pressed += OnBakePressed;
            _exportButton.Pressed += OnExportPressed;

            if (_editModeDropdown != null)
            {
                _editModeDropdown.Clear();
                _editModeDropdown.AddItem("None (Navigate)", 0);
                _editModeDropdown.AddItem("Select Zone", 1);
                _editModeDropdown.AddItem("Paint Color", 2);
                _editModeDropdown.AddItem("Sculpt Add Splats", 3);
                _editModeDropdown.AddItem("Sculpt Erase Splats", 4);
                _editModeDropdown.AddItem("Recalibrate Covariance", 5);
                _editModeDropdown.AddItem("Merge Clusters", 6);
                
                _editModeDropdown.ItemSelected += OnEditModeSelected;
            }

            if (_radiusSlider != null) _radiusSlider.ValueChanged += OnRadiusChanged;
            if (_strengthSlider != null) _strengthSlider.ValueChanged += OnStrengthChanged;
            if (_colorPicker != null) _colorPicker.ColorChanged += OnColorChanged;

            // Start update polling timer
            var timer = new Timer();
            timer.WaitTime = 1.0f; 
            timer.Timeout += UpdateStats;
            AddChild(timer);
            timer.Start();
        }

        private void UpdateBrushToolValues()
        {
            if (_plugin == null) return;
            var brush = _plugin.GetBrushTool();
            if (brush == null) return;

            if (_radiusSlider != null) _radiusSlider.Value = brush.BrushRadius;
            if (_strengthSlider != null) _strengthSlider.Value = brush.BrushStrength;
            if (_colorPicker != null) _colorPicker.Color = brush.PaintColor;
        }

        private void UpdateStats()
        {
            _activeNode = FindActiveSplatNode(GetTree().Root);

            if (_activeNode != null && _activeNode.SplatResource != null)
            {
                var resource = _activeNode.SplatResource;
                int count = resource.SplatCount;
                _splatCountLabel.Text = $"Total Splats: {count:N0}";

                float memoryMb = (count * 16) / (1024f * 1024f);
                _memoryLabel.Text = $"VRAM Memory: {memoryMb:F2} MB";

                var renderer = _activeNode.GetRenderer();
                if (renderer != null && renderer.MaterialOverride is ShaderMaterial mat)
                {
                    float lod = (float)mat.GetShaderParameter("lod_ratio");
                    _activeLodLabel.Text = $"Active LOD: {(lod * 100f):F0}%";
                }
                else
                {
                    _activeLodLabel.Text = "Active LOD: 100%";
                }
            }
            else
            {
                _splatCountLabel.Text = "Total Splats: 0 (No active node)";
                _memoryLabel.Text = "VRAM Memory: 0.00 MB";
                _activeLodLabel.Text = "Active LOD: --";
            }
        }

        private FoveaSplatNode3D FindActiveSplatNode(Node parent)
        {
            if (parent is FoveaSplatNode3D node && node.IsInsideTree())
            {
                return node;
            }

            int childCount = parent.GetChildCount();
            for (int i = 0; i < childCount; i++)
            {
                var active = FindActiveSplatNode(parent.GetChild(i));
                if (active != null) return active;
            }

            return null;
        }

        private void OnEditModeSelected(long index)
        {
            if (_plugin != null)
            {
                _plugin.ActiveEditMode = (FoveaSplatEditorPlugin.EditMode)index;
                GD.Print($"FoveaSplatManagerUI: Active edit mode changed to {_plugin.ActiveEditMode}");
            }
        }

        private void OnRadiusChanged(double value)
        {
            if (_plugin != null && _plugin.GetBrushTool() != null)
            {
                _plugin.GetBrushTool().BrushRadius = (float)value;
            }
        }

        private void OnStrengthChanged(double value)
        {
            if (_plugin != null && _plugin.GetBrushTool() != null)
            {
                _plugin.GetBrushTool().BrushStrength = (float)value;
            }
        }

        private void OnColorChanged(Color color)
        {
            if (_plugin != null && _plugin.GetBrushTool() != null)
            {
                _plugin.GetBrushTool().PaintColor = color;
            }
        }

        private void OnImportPressed()
        {
            var dialog = new FileDialog
            {
                Title = "Import Gaussian Splat File",
                FileMode = FileDialog.FileModeEnum.OpenFile,
                Access = FileDialog.AccessEnum.Resources,
                Filters = new string[] { "*.ply ; PLY Clouds", "*.splat ; SPLAT Files", "*.gsplat ; GSPLAT Files" }
            };
            dialog.FileSelected += (path) =>
            {
                GD.Print($"FoveaSplatManagerUI: Importing file '{path}'...");
                if (_activeNode != null)
                {
                    _activeNode.LoadSplatFile(path);
                    UpdateStats();
                }
                else
                {
                    GD.PushWarning("FoveaSplatManagerUI: No active FoveaSplatNode3D in scene to assign imported resource.");
                }
                dialog.QueueFree();
            };
            AddChild(dialog);
            dialog.PopupCenteredRatio(0.7f);
        }

        private void OnConvertPressed()
        {
            if (_activeNode == null || string.IsNullOrEmpty(_activeNode.SplatFilePath))
            {
                GD.PushWarning("FoveaSplatManagerUI: Please select or load a splat file in an active node first.");
                return;
            }

            GD.Print($"FoveaSplatManagerUI: Converting '{_activeNode.SplatFilePath}' to Godot Resource...");
            _activeNode.LoadSplatFile(_activeNode.SplatFilePath);
            UpdateStats();
        }

        private void OnOptimizePressed()
        {
            if (_activeNode == null || _activeNode.SplatResource == null)
            {
                GD.PushWarning("FoveaSplatManagerUI: No active splat cloud loaded to optimize.");
                return;
            }

            GD.Print("FoveaSplatManagerUI: Optimizing splat cloud (50% Decimation + Morton sorting)...");
            var resource = _activeNode.SplatResource;
            FoveaSplatConverter.Decimate(resource, 0.5f);
            resource.SortByMorton();
            _activeNode.SplatResource = resource; 
            UpdateStats();
        }

        private void OnBakePressed()
        {
            if (_activeNode == null)
            {
                GD.PushWarning("FoveaSplatManagerUI: No active splat node found to bake collisions.");
                return;
            }

            GD.Print("FoveaSplatManagerUI: Baking voxel collisions...");
            _activeNode.Call("GenerateVoxelCollisions");
        }

        private void OnExportPressed()
        {
            if (_activeNode == null || _activeNode.SplatResource == null)
            {
                GD.PushWarning("FoveaSplatManagerUI: No active splat node loaded to export.");
                return;
            }

            var dialog = new FileDialog
            {
                Title = "Export Splat Modifications",
                FileMode = FileDialog.FileModeEnum.SaveFile,
                Access = FileDialog.AccessEnum.Resources,
                Filters = new string[] { "*.ply ; PLY Clouds", "*.splat ; SPLAT Files" }
            };
            dialog.FileSelected += (path) =>
            {
                GD.Print($"FoveaSplatManagerUI: Exporting changes to '{path}'...");
                FoveaSplatExporter.ExportToFile(_activeNode.SplatResource, path);
                dialog.QueueFree();
            };
            AddChild(dialog);
            dialog.PopupCenteredRatio(0.7f);
        }
    }
}
