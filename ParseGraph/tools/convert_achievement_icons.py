"""Re-export the five achievement icons from their full-resolution originals."""
from pathlib import Path
import hashlib
import json
import shutil

from PIL import Image, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parent.parent
SOURCES = Path(r"C:\Users\hello\Desktop\ParseGraph Achievement Icons\Special")
DESTINATION = ROOT / "Images" / "Achievements"
BACKUP = ROOT / "backups" / "achievement-icons-before-smooth-resize-2026-09-13"
ICONS = {
    "Late Bloomer": "late_bloomer",
    "The Comeback Arc": "the_comeback_arc",
    "We Go Again": "we_go_again",
    "We Don’t Talk About Those": "we_dont_talk_about_those",
    "Mathematically Suspicious": "mathematically_suspicious",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    # Validate every source before touching any installed artwork.
    prepared = []
    for title, stem in ICONS.items():
        source = SOURCES / (title + ".tga")
        with Image.open(source) as image:
            assert image.mode == "RGB" and min(image.size) > 48, source
            original = image.copy()
        color = original.resize((48, 48), Image.Resampling.LANCZOS)
        locked = ImageEnhance.Brightness(ImageOps.grayscale(color)).enhance(0.68).convert("RGB")
        installed = DESTINATION / (stem + ".tga")
        with Image.open(installed) as image:
            nearest_match = image.convert("RGB").tobytes() == original.resize((48, 48), Image.Resampling.NEAREST).tobytes()
        prepared.append((title, stem, source, original.size, color, locked, nearest_match))

    # Never overwrite the originals from an earlier run.
    BACKUP.mkdir(parents=True, exist_ok=False)
    for _, stem, *_ in prepared:
        for suffix in ("", "_locked"):
            name = stem + suffix + ".tga"
            shutil.copy2(DESTINATION / name, BACKUP / name)

    manifest = []
    for title, stem, source, size, color, locked, nearest_match in prepared:
        source_hash = digest(source)
        for suffix, image in (("", color), ("_locked", locked)):
            path = DESTINATION / (stem + suffix + ".tga")
            image.save(path, format="TGA", compression=None, orientation=1)
            header = path.read_bytes()[:18]
            assert header[2] == 2 and header[16] == 24 and header[17] == 32, path
            with Image.open(path) as saved:
                assert saved.mode == "RGB" and saved.size == (48, 48)
                assert saved.tobytes() == image.tobytes()
        assert digest(source) == source_hash
        manifest.append({
            "achievement": title,
            "source": str(source),
            "source_size": size,
            "source_sha256": source_hash,
            "previous_icon_matches_nearest_neighbor": nearest_match,
            "output": stem + ".tga",
            "locked_output": stem + "_locked.tga",
            "resampling": "Lanczos",
            "format": "48x48 RGB, 24-bit uncompressed TGA, top-left origin",
            "locked_brightness": 0.68,
        })
        print(title + ": converted; old file matches nearest-neighbor = " + str(nearest_match))
    (BACKUP / "conversion.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print("Verified all 10 output files; full-resolution originals unchanged.")


if __name__ == "__main__":
    main()
