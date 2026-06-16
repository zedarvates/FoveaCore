import urllib.request
import os

def main():
    dest_dir = "Videos test"
    os.makedirs(dest_dir, exist_ok=True)
    
    # 4 high-quality synthetic turntable videos from Voxel51 dataset
    urls = {
        "https://huggingface.co/datasets/Voxel51/sama_material_centric_video_dataset/resolve/main/data/video0.mp4": os.path.join(dest_dir, "synthetic_object_0.mp4"),
        "https://huggingface.co/datasets/Voxel51/sama_material_centric_video_dataset/resolve/main/data/video1.mp4": os.path.join(dest_dir, "synthetic_object_1.mp4"),
        "https://huggingface.co/datasets/Voxel51/sama_material_centric_video_dataset/resolve/main/data/video2.mp4": os.path.join(dest_dir, "synthetic_object_2.mp4"),
        "https://huggingface.co/datasets/Voxel51/sama_material_centric_video_dataset/resolve/main/data/video3.mp4": os.path.join(dest_dir, "synthetic_object_3.mp4"),
    }

    for url, dest in urls.items():
        if os.path.exists(dest) and os.path.getsize(dest) > 1000:
            print(f"{dest} already exists (size: {os.path.getsize(dest)} bytes). Skipping.")
            continue
        print(f"Downloading {url} to {dest}...")
        try:
            urllib.request.urlretrieve(url, dest)
            print(f"[SUCCESS] Successfully downloaded {dest} ({os.path.getsize(dest)} bytes)")
        except Exception as e:
            print(f"[ERROR] Failed to download {url}: {e}")

    # Remove the failed placeholder file if present
    bad_file = os.path.join(dest_dir, "car_turntable_360.mp4")
    if os.path.exists(bad_file):
        os.remove(bad_file)
        print(f"Removed temporary invalid file: {bad_file}")

if __name__ == "__main__":
    main()
