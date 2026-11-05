# App icon artwork

The owner confirmed on 2026-11-01 that the original reference artwork was
created by them with AI. This master and the variants below are derived from
that owner-provided reference.

`IconArtwork.png` is the full-bleed 1024 × 1024 square master, edited with
built-in imagegen on 2026-11-02 from the user's selected diagonal controller
artwork. The source is opaque and has no pre-rendered icon frame, transparent
padding, rounded corners, rim or external shadow.

Design brief / final generation prompt: preserve the diagonal outlined blue
upper-left and coral lower-right controller shapes, their large controls,
four small buttons each and delicate trailing ribbons. Make the neutral
charcoal background just slightly darker than the previous version (roughly
#232426); extend it to all four square edges. Center the complete symbol
with balanced padding. No text, monogram, extra objects or icon mockup.

Symmetry refinement (2026-11-02, built-in imagegen): align the four small
circles in each section into matching 2 × 2 grids, with equal row/column
spacing and matching diameters between blue and coral. Balance each group
and its large circle within its section, with corresponding placement
reversed between sections. Preserve the charcoal background, colored outlines
and trailing ribbons.

Regenerate the Finder icon and Dock appearance resources on macOS:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/make_icons.swift
```

The generator applies the macOS silhouette to the full-bleed source: an
824 × 824 rounded tile centered on a transparent 1024 × 1024 canvas, with a
restrained shadow. It downsamples this master into all ten standard iconset
representations (16–1024 pixels), packages `AppIcon.icns`, and writes the
1024-pixel Light, Dark and Monochrome Dock resources. Light and Dark share
the charcoal tile. Monochrome preserves the geometry and alpha with a
grayscale color-space conversion.

Inspect the installed app in Finder and the Dock after quitting and reopening
it; the running app can retain its previous icon until it restarts.
