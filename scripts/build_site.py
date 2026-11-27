"""Stage the Headstand product page and its print files for GitHub Pages."""

import argparse
import shutil
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[1]
PAGE_FILES = (
    "index.html",
    "styles.css",
    "assets/case-interior.webp",
    "assets/case-closed.webp",
    "assets/case-packed.webp",
    "assets/case-open.webp",
    "assets/open-drains.webp",
)
MODEL_FILES = ("Storage-stand.scad", "Folding-stand.scad")


def build_site(output):
    if output.exists() or output.is_symlink():
        raise FileExistsError(f"Choose a new output directory: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as scratch:
        site = Path(scratch) / "site"
        for name in PAGE_FILES:
            target = site / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "site" / name, target)

        downloads = site / "downloads"
        downloads.mkdir()
        shutil.copyfile(ROOT / "exports/Storage-stand.stl", downloads / "Storage-stand.stl")
        with ZipFile(downloads / "Headstand-OpenSCAD.zip", "w") as archive:
            for name in MODEL_FILES:
                entry = ZipInfo(name)
                entry.external_attr = 0o100644 << 16
                archive.writestr(entry, (ROOT / "model" / name).read_bytes(), ZIP_DEFLATED)
        site.rename(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new directory for the staged website")
    try:
        build_site(parser.parse_args().output)
    except OSError as error:
        parser.exit(1, f"{error}\n")
