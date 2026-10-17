# Print files

Production prints for the Mile A Day pieces, made by `npm run prints` from `components/designs.tsx`.
Transparent PNGs at **300 DPI**, trimmed to the artwork. Sizes assume a size M (about 20 in wide flat).

In Tapstitch: **Add new design** → pick the blank → upload each file to its print area → set the width and
position below → **Save Design**. Save the design's front and back mockups (flat on white) to a folder as
`<product-id>-front.png` / `-back.png`, then `npm run cutouts -- <folder>` writes the rack photos to
`shop/public/garments/` and prints each piece's aspect for `lib/catalog.ts`.

## One Mile Every Day Tee — White (`daily-mile-tee`)

Blank: Everyday cotton tee, white.

| File | Print area | Width | Height | Placement |
|---|---|---|---|---|
| `daily-mile-tee/front.png` | Front | 2.2 in | 2.2 in | 3.1 in to the wearer's left of centre (left chest), top 3.9 in below the collar |
| `daily-mile-tee/back.png` | Back | 10.2 in | 12.7 in | centred, top 3.8 in below the collar |

## Extra Mile Long Sleeve — Navy (`extra-mile-long-sleeve`)

Blank: Sun-faded boxy long sleeve, navy.

| File | Print area | Width | Height | Placement |
|---|---|---|---|---|
| `extra-mile-long-sleeve/front.png` | Front | 3.6 in | 1.1 in | 3.1 in to the wearer's left of centre (left chest), top 4.2 in below the collar |
| `extra-mile-long-sleeve/back.png` | Back | 10.8 in | 13.6 in | centred, top 3.0 in below the collar |
| `extra-mile-long-sleeve/sleeve.png` | Right sleeve (reads top to bottom, shoulder to cuff) | 0.7 in | 9.5 in | centred on the sleeve, starting 2.0 in below the shoulder seam |

## Don't Break The Streak Tee — Black (`streak-tee`)

Blank: Everyday cotton tee, black.

| File | Print area | Width | Height | Placement |
|---|---|---|---|---|
| `streak-tee/front.png` | Front | 8.4 in | 5.2 in | centred, top 3.4 in below the collar |
| `streak-tee/back.png` | Back | 10.2 in | 11.6 in | centred, top 5.3 in below the collar |

## Run Club Tank — Heather Gray (`run-club-tank`)

Blank: Crewneck tank, heather gray.

| File | Print area | Width | Height | Placement |
|---|---|---|---|---|
| `run-club-tank/front.png` | Front | 9.3 in | 8.1 in | centred, top 3.6 in below the collar |
| `run-club-tank/back.png` | Back | 5.2 in | 3.3 in | centred, top 4.5 in below the collar |

## Keep It Lit Flamey Tee — Cream (`flamey-tee`)

Blank: Everyday cotton tee, cream.

| File | Print area | Width | Height | Placement |
|---|---|---|---|---|
| `flamey-tee/front.png` | Front | 8.8 in | 10.9 in | centred, top 2.5 in below the collar |
| `flamey-tee/back.png` | Back | 9.5 in | 6.4 in | centred, top 2.3 in below the collar |

## Flamey Run Crew Long Sleeve — Black (`flamey-run-crew`)

Blank: Cotton long sleeve, black.

| File | Print area | Width | Height | Placement |
|---|---|---|---|---|
| `flamey-run-crew/front.png` | Front | 1.8 in | 2.5 in | 3.5 in to the wearer's left of centre (left chest), top 3.6 in below the collar |
| `flamey-run-crew/back.png` | Back | 10.0 in | 12.2 in | 0.7 in left of centre, top 4.1 in below the collar |
| `flamey-run-crew/sleeve.png` | Right sleeve (reads top to bottom, shoulder to cuff) | 0.7 in | 8.8 in | centred on the sleeve, starting 2.0 in below the shoulder seam |
