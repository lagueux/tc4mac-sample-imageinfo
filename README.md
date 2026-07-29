# tc4mac image properties plugin (content sample)

A [tc4mac](https://tc4mac.com) content plugin: image dimensions, orientation,
megapixels, resolution, colour model and depth, as **columns** you can sort
and search on — and as `[=field]` placeholders in Multi-Rename.

A content plugin never displays anything. It answers with *values*; the host
decides where they appear. (The plugin that *shows* a file is a viewer
plugin — see the Markdown sample.)

## Build and install

```
./make-plugin.sh
```

Then **Configuration ▸ Plugins ▸ Install…** in tc4mac, and switch it on.

## What to look at

- `ImagePropertiesProvider.swift` — the fields and how each is read.
- `main.swift` — the plugin process: the field list once, then one value at
  a time.

Three decisions worth copying:

**Read the file, don't ask the index.** Spotlight answers only for indexed
local volumes, so its columns go blank on a network share or a freshly
attached disk. This reads each file's header with ImageIO, and only the
header — a hundred-megapixel RAW costs the same as a thumbnail.

**Sort by the number, show the text.** Megapixels come back as a decimal
carrying its own display string, so the column reads "12.2 MP" while sorting
uses 12.192768. Formatting a number into text loses the ordering.

**Orientation is the rendered shape, not the EXIF tag.** The tag says how the
camera was held; a rotated photo would claim Landscape while displaying
portrait.

A file with no value for a field gets a blank cell, never an error — most
files are not images.

## Licence

MIT. See `LICENSE`.
