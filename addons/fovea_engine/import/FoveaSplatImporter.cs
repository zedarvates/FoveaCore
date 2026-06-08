using Godot;
using Godot.Collections;

namespace FoveaEngine
{
    [GlobalClass]
    public partial class FoveaSplatImporter : EditorImportPlugin
    {
        public override string _GetImporterName() => "fovea.splat_importer";
        public override string _GetVisibleName() => "Fovea Gaussian Splat Importer";
        public override string[] _GetRecognizedExtensions() => new string[] { "ply", "splat", "gsplat", "pcd", "bin", "npy" };
        public override string _GetSaveExtension() => "res";
        public override string _GetResourceType() => "FoveaSplatResource";

        public override int _GetPresetCount() => 1;
        public override string _GetPresetName(int presetIndex) => "Default";

        public override Array<Dictionary> _GetImportOptions(string path, int presetIndex)
        {
            var options = new Array<Dictionary>();

            // Option 1: Decimation ratio
            var optDecimate = new Dictionary
            {
                { "name", "decimation_ratio" },
                { "default_value", 1.0f },
                { "property_hint", (int)PropertyHint.Range },
                { "hint_string", "0.01,1.0,0.01" }
            };
            options.Add(optDecimate);

            // Option 2: Recalculate Normals
            var optNormals = new Dictionary
            {
                { "name", "recalculate_normals" },
                { "default_value", true }
            };
            options.Add(optNormals);

            return options;
        }



        public override Error _Import(string sourceFile, string savePath, Dictionary options, Array<string> platformVariants, Array<string> genFiles)
        {
            GD.Print($"FoveaSplatImporter: Importing {sourceFile} -> {savePath}");

            var resource = FoveaSplatConverter.ConvertFileToResource(sourceFile);
            if (resource == null)
            {
                GD.PushError($"FoveaSplatImporter: Failed to parse {sourceFile}");
                return Error.Failed;
            }

            float decimateRatio = (float)options["decimation_ratio"];
            if (decimateRatio < 1.0f)
            {
                FoveaSplatConverter.Decimate(resource, decimateRatio);
                GD.Print($"FoveaSplatImporter: Decimated to {resource.SplatCount} splats.");
            }

            bool recalcNormals = (bool)options["recalculate_normals"];
            if (recalcNormals)
            {
                FoveaSplatConverter.RecalculateNormals(resource);
            }

            string destFile = $"{savePath}.{_GetSaveExtension()}";
            Error err = ResourceSaver.Save(resource, destFile);
            if (err != Error.Ok)
            {
                GD.PushError($"FoveaSplatImporter: Failed to save imported resource to {destFile}: {err}");
                return err;
            }

            return Error.Ok;
        }
    }
}
