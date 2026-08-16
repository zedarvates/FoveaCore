using Godot;
using System;
using System.IO;

namespace FoveaEngine
{
    public partial class TestFoveaSplat : Node
    {
        public override void _Ready()
        {
            GD.Print("\n==============================================");
            GD.Print("=== Fovea Engine - Gaussian Splat Suite Tests ===");
            GD.Print("==============================================\n");

            bool success = true;

            try
            {
                // Test 1: Resource Creation and Morton Sorting
                success &= TestResourceAndSorting();

                // Test 2: Export and Import (Conversion)
                success &= TestExportAndImport();

                // Test 3: Node and Renderer Instantiation
                success &= TestNodeAndRenderer();

                // Test 4: Instancer Replication
                success &= TestInstancer();

                // Test 5: Animator Morphing and Path
                success &= TestAnimator();

                // Test 6: Selection and Brush Tools
                success &= TestSelectionAndBrush();
            }
            catch (Exception ex)
            {
                GD.PushError($"Test Run CRASHED: {ex.Message}\n{ex.StackTrace}");
                success = false;
            }

            GD.Print("\n==============================================");
            if (success)
            {
                GD.Print("=== ALL GAUSSIAN SPLAT SUITE TESTS PASSED ===");
                GD.Print("==============================================\n");
                ExitTest(0);
            }
            else
            {
                GD.PushError("=== GAUSSIAN SPLAT SUITE TESTS FAILED ===");
                GD.Print("==============================================\n");
                ExitTest(1);
            }
        }

        private void ExitTest(int exitCode)
        {
            GD.Print($"Exiting with code {exitCode}.");
            GetTree().Quit(exitCode);
        }

        private bool TestResourceAndSorting()
        {
            GD.Print("Testing: Splat Resource Creation & Morton-Code Sorting...");

            var resource = new FoveaSplatResource
            {
                Positions = new Vector3[]
                {
                    new Vector3(5, 2, 1),
                    new Vector3(1, 0, 3),
                    new Vector3(0, 4, 0)
                },
                Rotations = new Quaternion[]
                {
                    Quaternion.Identity,
                    Quaternion.Identity,
                    Quaternion.Identity
                },
                Scales = new Vector3[]
                {
                    Vector3.One,
                    Vector3.One,
                    Vector3.One
                },
                Colors = new Color[]
                {
                    Colors.Red,
                    Colors.Green,
                    Colors.Blue
                },
                Opacities = new float[] { 1f, 1f, 1f }
            };

            if (resource.SplatCount != 3)
            {
                GD.PushError("Failed: Resource SplatCount is not 3.");
                return false;
            }

            resource.RecalculateBounds();
            GD.Print($"Calculated Bounding Box Position: {resource.BBox.Position}, Size: {resource.BBox.Size}");

            if (resource.BBox.Size.Length() <= 0.1f)
            {
                GD.PushError("Failed: Bounds size calculation is incorrect.");
                return false;
            }

            // Test Morton code sorting
            resource.SortByMorton();
            GD.Print("Morton sort executed successfully.");

            GD.Print("Success: Resource and Sorting tests passed.\n");
            return true;
        }

        private bool TestExportAndImport()
        {
            GD.Print("Testing: Splat Exporter & Importer (Conversion)...");

            var resource = new FoveaSplatResource
            {
                Positions = new Vector3[] { new Vector3(0, 0, 0), new Vector3(1, 1, 1) },
                Rotations = new Quaternion[] { Quaternion.Identity, Quaternion.Identity },
                Scales = new Vector3[] { Vector3.One, Vector3.One },
                Colors = new Color[] { Colors.White, Colors.Red },
                Opacities = new float[] { 1f, 0.5f }
            };
            resource.RecalculateBounds();

            string tempSplatPath = "res://test_temp.splat";
            string tempPlyPath = "res://test_temp.ply";

            // Export to SPLAT
            bool splatExportOk = FoveaSplatExporter.ExportToFile(resource, tempSplatPath);
            GD.Print($"Exported to .splat: {splatExportOk}");

            // Export to PLY
            bool plyExportOk = FoveaSplatExporter.ExportToFile(resource, tempPlyPath);
            GD.Print($"Exported to .ply: {plyExportOk}");

            if (!splatExportOk || !plyExportOk)
            {
                GD.PushError("Failed: Exporting returned false.");
                return false;
            }

            // Load SPLAT
            var loadedSplat = FoveaSplatConverter.ConvertFileToResource(tempSplatPath);
            // Load PLY
            var loadedPly = FoveaSplatConverter.ConvertFileToResource(tempPlyPath);

            if (loadedSplat == null || loadedSplat.SplatCount != 2)
            {
                GD.PushError($"Failed: Loaded .splat has invalid count (expected 2, got {loadedSplat?.SplatCount ?? 0}).");
                return false;
            }

            if (loadedPly == null || loadedPly.SplatCount != 2)
            {
                GD.PushError($"Failed: Loaded .ply has invalid count (expected 2, got {loadedPly?.SplatCount ?? 0}).");
                return false;
            }

            GD.Print("Loaded splats count from both files verified.");

            // Cleanup temp files
            DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(tempSplatPath));
            DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(tempPlyPath));

            GD.Print("Success: Export and Import tests passed.\n");
            return true;
        }

        private bool TestNodeAndRenderer()
        {
            GD.Print("Testing: Node & Renderer Setup...");

            var node = new FoveaSplatNode3D();
            AddChild(node);

            var resource = new FoveaSplatResource
            {
                Positions = new Vector3[] { Vector3.Zero },
                Rotations = new Quaternion[] { Quaternion.Identity },
                Scales = new Vector3[] { Vector3.One },
                Colors = new Color[] { Colors.White },
                Opacities = new float[] { 1f }
            };
            resource.RecalculateBounds();

            node.SplatResource = resource;

            var renderer = node.GetRenderer();
            if (renderer == null)
            {
                GD.PushError("Failed: Dynamic FoveaSplatRenderer child node was not created.");
                return false;
            }

            if (renderer.Multimesh == null)
            {
                GD.PushError("Failed: Renderer Multimesh was not configured.");
                return false;
            }

            GD.Print("Renderer multimesh setup validated.");
            node.QueueFree();

            GD.Print("Success: Node and Renderer tests passed.\n");
            return true;
        }

        private bool TestInstancer()
        {
            GD.Print("Testing: Procedural Instancer...");

            var instancer = new FoveaSplatInstancer();
            AddChild(instancer);

            var resource = new FoveaSplatResource
            {
                Positions = new Vector3[] { Vector3.Zero, new Vector3(0.5f, 0.5f, 0.5f) },
                Rotations = new Quaternion[] { Quaternion.Identity, Quaternion.Identity },
                Scales = new Vector3[] { Vector3.One, Vector3.One },
                Colors = new Color[] { Colors.Red, Colors.Blue },
                Opacities = new float[] { 1f, 1f }
            };
            resource.RecalculateBounds();

            instancer.SourceResource = resource;
            instancer.InstanceCount = 10;
            instancer.PlacementAreaSize = new Vector3(5, 0, 5);

            instancer.GenerateInstances();

            var combined = instancer.GetCombinedResource();
            if (combined == null || combined.SplatCount != 20)
            {
                GD.PushError($"Failed: Instancer did not generate correct combined splat count (expected 20, got {combined?.SplatCount ?? 0}).");
                return false;
            }

            GD.Print($"Instancer generated {combined.SplatCount} splats successfully.");
            instancer.QueueFree();

            GD.Print("Success: Instancer tests passed.\n");
            return true;
        }

        private bool TestAnimator()
        {
            GD.Print("Testing: Splat Animator (Morphing)...");

            var node = new FoveaSplatNode3D();
            AddChild(node);

            var resA = new FoveaSplatResource
            {
                Positions = new Vector3[] { Vector3.Zero },
                Rotations = new Quaternion[] { Quaternion.Identity },
                Scales = new Vector3[] { Vector3.One },
                Colors = new Color[] { Colors.Red },
                Opacities = new float[] { 1f }
            };
            resA.RecalculateBounds();

            var resB = new FoveaSplatResource
            {
                Positions = new Vector3[] { new Vector3(5, 5, 5) },
                Rotations = new Quaternion[] { Quaternion.Identity },
                Scales = new Vector3[] { Vector3.One },
                Colors = new Color[] { Colors.Blue },
                Opacities = new float[] { 1f }
            };
            resB.RecalculateBounds();

            node.SplatResource = resA;

            var animator = new FoveaSplatAnimator();
            AddChild(animator);
            animator.TargetNode = node;
            animator.MorphTargetResource = resB;
            animator.SetBaseResource(resA);

            // Morph halfway
            animator.MorphProgress = 0.5f;

            var morphedPos = node.SplatResource.Positions[0];
            var morphedCol = node.SplatResource.Colors[0];

            GD.Print($"Morphed Position: {morphedPos}, Color: {morphedCol}");

            if (morphedPos.DistanceTo(new Vector3(2.5f, 2.5f, 2.5f)) > 0.01f)
            {
                GD.PushError("Failed: Morph position interpolation is incorrect.");
                return false;
            }

            node.QueueFree();
            animator.QueueFree();

            GD.Print("Success: Animator tests passed.\n");
            return true;
        }

        private bool TestSelectionAndBrush()
        {
            GD.Print("Testing: Selection & Brush Tools...");

            var node = new FoveaSplatNode3D();
            AddChild(node);

            var resource = new FoveaSplatResource
            {
                Positions = new Vector3[]
                {
                    new Vector3(0, 0, 0),
                    new Vector3(1, 0, 0),
                    new Vector3(10, 10, 10)
                },
                Rotations = new Quaternion[]
                {
                    Quaternion.Identity,
                    Quaternion.Identity,
                    Quaternion.Identity
                },
                Scales = new Vector3[]
                {
                    Vector3.One,
                    Vector3.One,
                    Vector3.One
                },
                Colors = new Color[]
                {
                    Colors.Black,
                    Colors.Black,
                    Colors.Black
                },
                Opacities = new float[] { 1f, 1f, 1f }
            };
            resource.RecalculateBounds();
            node.SplatResource = resource;

            // Selection Tool
            var selectionTool = new FoveaSplatSelectionTool();
            selectionTool.SelectZone(node, Vector3.Zero, 2.0f);
            
            GD.Print($"Selected splats within radius 2.0: {selectionTool.SelectedIndices.Count}");
            if (selectionTool.SelectedIndices.Count != 2)
            {
                GD.PushError($"Failed: Selection tool count mismatch (expected 2, got {selectionTool.SelectedIndices.Count}).");
                return false;
            }

            // Brush Tool (Paint)
            var brushTool = new FoveaSplatBrushTool
            {
                BrushRadius = 2.0f,
                BrushStrength = 1.0f,
                PaintColor = Colors.Green
            };
            brushTool.Paint(node, Vector3.Zero);

            var col0 = node.SplatResource.Colors[0];
            GD.Print($"Painted color at index 0: {col0}");
            if (col0.G < 0.5f)
            {
                GD.PushError("Failed: Brush paint did not apply correct color value.");
                return false;
            }

            node.QueueFree();

            GD.Print("Success: Selection and Brush tests passed.\n");
            return true;
        }
    }
}
