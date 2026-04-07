# FoveaCore GDExtension — Instructions de compilation

## Prérequis
- Python 3.8+
- SCons 4.0+
- Compilateur C++17 (MSVC sur Windows, GCC/Clang sur Linux/macOS)
- Godot 4.6.1

## Étape 1 : Cloner godot-cpp
```bash
cd addons/foveacore/gdextension
git clone --branch 4.6 https://github.com/godotengine/godot-cpp.git
cd godot-cpp
git submodule update --init
```

## Étape 2 : Compiler godot-cpp
```bash
cd godot-cpp
scons target=template_release platform=windows arch=x86_64
```

## Étape 3 : Compiler FoveaCore
```bash
cd ..
scons target=template_release platform=windows arch=x86_64
```

## Étape 4 : Placer la DLL
La DLL compilée sera dans `bin/foveacore.dll`. Elle est déjà référencée dans `foveacore.gdextension`.

## Commandes rapides

### Windows (Release)
```bash
scons target=template_release platform=windows arch=x86_64
```

### Windows (Debug)
```bash
scons target=template_debug platform=windows arch=x86_64
```

### Linux
```bash
scons target=template_release platform=linux arch=x86_64
```

### macOS
```bash
scons target=template_release platform=macos arch=universal
```

## Dépannage

### Erreur : godot-cpp non trouvé
Vérifier que le dossier `godot-cpp` existe dans `gdextension/`.

### Erreur : SCons non trouvé
```bash
pip install scons
```

### Erreur : Compilateur non trouvé
- Windows : Installer Visual Studio Build Tools 2022
- Linux : `sudo apt install build-essential`
- macOS : `xcode-select --install`

# FoveaCore — Compilation GDExtension

## ✅ Fichiers de build créés
- `addons/foveacore/gdextension/SConstruct` — Script SCons
- `addons/foveacore/gdextension/README_BUILD.md` — Instructions complètes

---

## 📋 Commandes à exécuter

Ouvrir un terminal et exécuter :

### Étape 1 : Cloner godot-cpp
```bash
cd f:/foveaengine/fovea-engine/addons/foveacore/gdextension
git clone --branch 4.6 https://github.com/godotengine/godot-cpp.git
cd godot-cpp
git submodule update --init
```

### Étape 2 : Installer SCons (si pas déjà fait)
```bash
pip install scons
```

### Étape 3 : Compiler godot-cpp
```bash
cd f:/foveaengine/fovea-engine/addons/foveacore/gdextension/godot-cpp
scons target=template_release platform=windows arch=x86_64
```

### Étape 4 : Compiler FoveaCore
```bash
cd f:/foveaengine/fovea-engine/addons/foveacore/gdextension
scons target=template_release platform=windows arch=x86_64
```

### Étape 5 : Vérifier
La DLL sera dans `addons/foveacore/gdextension/bin/foveacore.dll`.

Redémarrer Godot — le plugin chargera automatiquement le renderer natif.

---

## ⚠️ Prérequis
- **Python 3.8+**
- **SCons 4.0+** (`pip install scons`)
- **Compilateur C++17** : Visual Studio Build Tools 2022 (Windows)
- **Git** pour cloner godot-cpp
