# Headstand product page

This static page introduces the [folding stand with storage for two heads](../README.md#folding-stand-with-storage-for-two-heads) and publishes its print files on [Headstand's GitHub Pages site](https://echoz.github.io/Headstand/). The checked-in OpenSCAD files and STL are the design authority.

- `index.html` contains the product views, instructions, and links.
- `styles.css` owns the responsive layout and the gallery. The gallery uses native radio controls and CSS. Browsers without CSS `:has()` display the views in sequence.
- `assets/` contains the sculpted interior, closed case, packed heads, upright heads and drainage views. The interior views use the [current STL](../exports/Storage-stand.stl). The closed view shows the same rectangular exterior. The brush heads are illustrative.

To preview locally, run these commands from the repository root with Python 3. Choose a new output directory for each build.

```sh
python3 scripts/build_site.py _site
python3 scripts/check_site.py _site
python3 -m http.server 8000 --bind 127.0.0.1 --directory _site
```

Open [the local preview](http://127.0.0.1:8000/). Staging copies the page and its images and supplies both downloads.

- `downloads/Storage-stand.stl` from the current checked-in export
- `downloads/Headstand-OpenSCAD.zip` with `Storage-stand.scad` and its `Folding-stand.scad` dependency

Check the four gallery options with pointer and keyboard, the two local navigation targets, both downloads, and the layout on mobile and desktop. Changing the printable candidate also requires checking the renders, dimensions, print settings, and physical-trial status against the new candidate.
