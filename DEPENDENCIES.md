# 📦 Dépendances FoveaEngine (StudioTo3D)

Pour que le pipeline de reconstruction fonctionne, vous devez installer **FFmpeg** et **COLMAP** sur votre système.

---

## 📹 1. FFmpeg
Utilisé pour extraire les images de vos vidéos.

### Installation (Windows) :
1. Téléchargez la dernière version sur **[GitHub ShareX/FFmpeg Releases](https://github.com/ShareX/FFmpeg/releases)**.
2. Décompressez l'archive (ex: `C:\ffmpeg`).
3. Le fichier important est `bin\ffmpeg.exe`.

---

## 🏛️ 2. COLMAP
Utilisé pour la photogrammétrie (Structure from Motion).

### Installation (Windows) :
1. Téléchargez la version Windows (avec CUDA si vous avez une carte NVIDIA) sur **[GitHub COLMAP/COLMAP Releases](https://github.com/colmap/colmap/releases)**.
2. Décompressez l'archive (ex: `C:\colmap`).
3. Le fichier important est `colmap.exe`.

---

## 🧬 3. 3D Gaussian Splatting (Python)
Utilisé pour l'entraînement du nuage de points.

### Pré-requis :
- Python 3.10+
- CUDA Toolkit 11.8+
- Un GPU NVIDIA performant (8GB+ VRAM recommandé).

---

## ⚙️ Configuration dans Godot

Une fois installé, vous pouvez configurer les chemins dans le panel **StudioTo3D** de FoveaEngine :

1. Ouvrez le panel **StudioTo3D** dans l'éditeur Godot.
2. Allez dans la section **Settings** (en bas).
3. Renseignez les chemins complets vers vos exécutables :
   - FFmpeg Path : `C:\ffmpeg\bin\ffmpeg.exe`
   - COLMAP Path : `C:\colmap\colmap.exe`

4. Cliquez sur **Check Tools** pour valider que Godot arrive à les lancer.

### Astuce : Ajout au PATH
Si vous ajoutez ces dossiers à votre variable d'environnement `PATH` de Windows, vous n'aurez pas besoin de renseigner les chemins complets dans Godot. Le moteur détectera automatiquement `ffmpeg` et `colmap`.
