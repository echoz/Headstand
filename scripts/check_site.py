"""Check the staged Headstand GitHub Pages artifact."""

import argparse
from html.parser import HTMLParser
from pathlib import Path
import posixpath
import stat
import sys
from urllib.parse import unquote, urljoin, urlsplit
from zipfile import BadZipFile, ZipFile


PROJECT = Path(__file__).resolve().parents[1]
PAGES_URL = "https://echoz.github.io/Headstand/"
PAGES_PATH = "/Headstand/"
ENTRY_PAGE = "index.html"
STL = "downloads/Storage-stand.stl"
OPENSCAD_ZIP = "downloads/Headstand-OpenSCAD.zip"
MODEL_FILES = ("Storage-stand.scad", "Folding-stand.scad")
IMAGE_TYPES = {".svg", ".png", ".webp", ".avif", ".jpg", ".jpeg", ".gif", ".ico"}
REFERENCE_ATTRIBUTES = {"a": "href", "img": "src", "link": "href"}


class PageReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []
        self.anchors = set()

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if attributes.get("id"):
            self.anchors.add(attributes["id"])
        if tag == "a" and attributes.get("name"):
            self.anchors.add(attributes["name"])
        attribute = REFERENCE_ATTRIBUTES.get(tag)
        if attribute in attributes:
            relations = (attributes.get("rel") or "").lower().split()
            is_stylesheet = tag == "link" and "stylesheet" in relations
            role = "stylesheet" if is_stylesheet else tag
            self.references.append((self.getpos()[0], role, attributes[attribute] or ""))


def artifact_files(output):
    if output.is_symlink() or not output.is_dir():
        raise ValueError(f"Expected a staged directory at {output}")
    files = {}
    for path in sorted(output.rglob("*")):
        name = path.relative_to(output).as_posix()
        is_pages_control = name == ".nojekyll"
        has_hidden_component = any(part.startswith(".") for part in Path(name).parts)
        if path.is_symlink() or (has_hidden_component and not is_pages_control):
            raise ValueError(f"Unexpected private or linked artifact entry: {name}")
        if path.is_dir() and not is_pages_control:
            continue
        is_public_file = (
            name in (ENTRY_PAGE, STL, OPENSCAD_ZIP)
            or path.suffix in IMAGE_TYPES | {".css"}
            or is_pages_control
        )
        if not path.is_file() or not is_public_file:
            raise ValueError(f"Unexpected artifact file: {name}")
        files[name] = path
    return files


def check_downloads(files):
    for name in (STL, OPENSCAD_ZIP):
        if name not in files:
            raise ValueError(f"Missing download: {name}")
    if files[STL].read_bytes() != (PROJECT / "exports" / "Storage-stand.stl").read_bytes():
        raise ValueError(f"{STL} differs from exports/Storage-stand.stl")
    with ZipFile(files[OPENSCAD_ZIP]) as archive:
        if sorted(archive.namelist()) != sorted(MODEL_FILES):
            raise ValueError(f"{OPENSCAD_ZIP} must contain exactly {', '.join(MODEL_FILES)}")
        for name in MODEL_FILES:
            entry = archive.getinfo(name)
            kind = stat.S_IFMT(entry.external_attr >> 16)
            if kind not in (0, stat.S_IFREG):
                raise ValueError(f"{OPENSCAD_ZIP} member {name} must be a regular file")
            source = (PROJECT / "model" / name).read_bytes()
            if entry.file_size != len(source) or archive.read(entry) != source:
                raise ValueError(f"{OPENSCAD_ZIP} member {name} differs from model/{name}")


def local_destination(reference):
    address = urlsplit(urljoin(PAGES_URL, reference))
    if (address.scheme, address.hostname) != ("https", "echoz.github.io"):
        return None
    if address.port not in (None, 443):
        return None
    path = unquote(address.path)
    if "\\" in path or "\0" in path:
        raise ValueError("contains an invalid path character")
    normalized = posixpath.normpath(path)
    if normalized == PAGES_PATH.rstrip("/"):
        target = ENTRY_PAGE
    else:
        if not normalized.startswith(PAGES_PATH):
            if urlsplit(reference).netloc:
                return None
            raise ValueError(f"leaves the Pages project path {PAGES_PATH}")
        if path.endswith("/"):
            raise ValueError("target must be a file")
        target = normalized[len(PAGES_PATH):]
    return target, unquote(address.fragment)


def check_page_references(files):
    if ENTRY_PAGE not in files:
        raise ValueError(f"Missing entry page: {ENTRY_PAGE}")
    page = PageReferences()
    page.feed(files[ENTRY_PAGE].read_text(encoding="utf-8"))
    page.close()

    linked_files = {ENTRY_PAGE, ".nojekyll"}
    download_links = set()
    for line, role, reference in page.references:
        try:
            destination = local_destination(reference)
            if destination is None:
                continue
            target, fragment = destination
            if target not in files:
                raise ValueError("target file is missing")
            suffix = Path(target).suffix
            if role == "img" and suffix not in IMAGE_TYPES:
                raise ValueError("does not point to an image")
            if role == "stylesheet" and suffix != ".css":
                raise ValueError("does not point to a stylesheet")
            if fragment and target == ENTRY_PAGE and fragment not in page.anchors:
                raise ValueError(f"anchor #{fragment} is missing")
        except ValueError as error:
            raise ValueError(f"{ENTRY_PAGE}:{line}: {reference!r} {error}") from error
        linked_files.add(target)
        if role == "a":
            download_links.add(target)

    for target in (STL, OPENSCAD_ZIP):
        if target not in download_links:
            raise ValueError(f"{ENTRY_PAGE} is missing a link to {target}")
    unlinked_files = sorted(files.keys() - linked_files)
    if unlinked_files:
        raise ValueError(f"Unreferenced artifact files: {', '.join(unlinked_files)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="directory staged by build_site.py")
    arguments = parser.parse_args()
    try:
        files = artifact_files(arguments.output)
        check_downloads(files)
        check_page_references(files)
    except (ValueError, OSError, BadZipFile, RuntimeError) as error:
        sys.exit(f"Headstand site check failed: {error}")
    print(f"Verified {len(files)} Headstand Pages files, both downloads and local references.")


if __name__ == "__main__":
    main()
