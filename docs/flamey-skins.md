# Flamey skins (format 1)

Every Flamey wardrobe item is a JSON file in `backend/flamey-skins/<id>.json`.
The backend serves them at `GET /flamey/skins`; the app draws them. The 133
items that shipped as Swift drawing code were exported from that code
(`app/FlameyExport/`), so a migrated item is the same shapes the code drew.

A new skin is a new file and a PR. When it merges, the backend deploys it and
every phone on a build that understands its `format` draws it, with no app
update. A phone whose renderer is older than the skin's `format` skips it.

## Units

Body units: origin at the centre of Flamey's square, y down, 1 = u, where u is
the figure's size times its body scale. His base (`a.bottom`) is at +0.35, the
floor (`a.ground`) at +0.5, his face at -0.03, the top of his flame at -0.63
(plain look, standing on his legs; `meta.plain.anchors_u`). Art that sits on
his body moves with him when he hovers; see `attach` below.

## File

```jsonc
{
  "format": 1,                 // renderer version this skin needs
  "id": "crown",               // permanent: stored in users.flamey_look — never rename
  "order": 74,                 // Closet order (ties broken by id)
  "slot": "head",              // color head eyes chest back feet costume held trail companion aura bubble
  "name": "Crown",
  "family": "lifetimeMiles",   // Closet group (FlameyFamily raw value)
  "unlock": {"badge": "miles_1000"},   // "always" | "plus" | {"badge": id} | {"month": 1-12}
  "unlock_copy": "Walk 1,000 lifetime miles",
  "holidays": [],              // HolidayKey raw values: worn automatically on those days
  "mood_prop": false,          // automatic mood dressing, never in the Closet
  "compact": true,             // drawn on small surfaces (widgets, Live Activity)
  "tier": 1000,                // order within its slot; Closet "Best look" takes the highest owned
  "auto_eligible": true,       // may "Best look" pick it (false: holiday, costume, Plus, Monthly)
  "rules": { … },              // how it fits with the rest of him (below)
  "palette": { … },            // colour slot only
  "effects": ["aura:spotlight"],   // built-in effect pieces it uses (below)
  "art": { "<layer>": <recording>, … },
  "pivots": { "<layer>": [x, y] },
  "motion": { "<layer base>": { … } }
}
```

### rules

| Key | Meaning |
|---|---|
| `hides` | slots this item covers (a costume hides head, eyes…) |
| `clashes` | item ids it can't be worn with |
| `hover_lift` | feet: how far he floats, body units (full surfaces only) |
| `head_rise` | head/costume: how far above his tip it reaches (speech bubble, fitting) |
| `head_scale` | head: size factor |
| `is_cape` | back: tucks/squeezes like a cape on narrow surfaces |
| `floats` | companion: hovers by his shoulder instead of walking |
| `shows_face` / `shows_arms` | false = the item covers them (ghost sheet) |
| `figure_palette` | costume: recolours Flamey himself (skeleton suit) |
| `held` | held: hand, tight hand, grip, accent pivot, tight scale, wobble, period, accent, tile framing |
| `arm_hold` | held: where each hand goes, per reach |
| `draw` | `"last"`: drawn over chest, eyes and head (astronaut helmet) |
| `crown_unless`, `crown_rise` | colour: its `crown` layer shows only without these slots, and how far it rises |
| `glow` | `"wings"`: counts as his one halo-class effect (golden wings) |

### art: layers and recordings

A layer key is a part name, optionally followed by `@` and the conditions it
was drawn under. The renderer picks the layer whose conditions match the
surface (nearest `reach`).

| Part | Drawn | Conditions |
|---|---|---|
| `front` | in front of him | `jets=0/1` for feet |
| `behind` | behind him | `reach=0.9/0.8/0.62`, `low=0/1` (trail under a cape), `glow=0/1` (wings) |
| `crown` | in front, colour items | — |
| `held-body`, `held-accent` | in his hand | `reach` |
| `companion-body`, `companion-shadow` | beside him | `pose=rest/cheer/…` |
| `bopper-band`, `bopper-springs` | on his head | — |

`attach` follows from the part: feet art moves with his feet, companions stand
on the floor, everything else moves with his body.

A recording is `{"ops": [...], "clips"?: [...], "images"?: {...}}`:

```jsonc
{"op": "fill",   "d": "M-.2 -.5Q…Z", "paint": P, "eo"?: true}
{"op": "stroke", "d": "…", "paint": P, "w": 0.014, "cap"?: "round|square", "join"?: "round|bevel",
                 "miter"?: 4, "dash"?: [..], "phase"?: 0}
{"op": "image",  "src": "img0", "rect": [x, y, w, h], "m": M}
// any op may also carry:
//   "m":    [a,b,c,d,tx,ty] — d/paint/w are LOCAL and m maps them to body units
//   "a":    opacity 0–1
//   "fx":   [{"blur": r}] or [{"shadow": ["#RRGGBBAA", r, dx, dy]}], body units, in order
//   "clip": indices into "clips": [{"d", "eo"?, "inv"?}], intersected in order
```

`d` is SVG path data (M L Q C Z only). Paint `P` is `"#RRGGBBAA"`, a palette
token `{"tok": "outer.1", "a": 0.5, "fb": "#FFE047FF"}` (his current colour,
`fb` when he has none), or a gradient:
`{"lin": [x0,y0,x1,y1], "stops": [[t, colour], …]}`,
`{"rad": [cx,cy,r0,r1], "stops"}`, `{"conic": [cx,cy,degrees], "stops"}`.
Gradients pad past their ends. Blur and shadow radii match SwiftUI's
`GraphicsContext` filters.

### motion

Keyed by layer base name. All motion is one `repeatForever` ease-in-out
autoreverse per layer, off under Reduce Motion and on still surfaces.

| Kind | Fields | Used by |
|---|---|---|
| `drift` | `dx`, `dx_tight`, `alpha`, `period` | trails stream back and breathe |
| `bob` | `dy`, `period` | companions |
| `sway` | `deg`, `period` (about `pivots[layer]`) | heart-bopper springs |
| `wobble` | `deg`, `back`, `period` (about the grip) | held props |
| `pump` | `scale`, `dy`, `period` | pom-poms |
| `flutter` / `sweep` / `pulse` / `burst` | `period` (about the accent pivot) | held accents |

### effects

Built-in pieces the renderer draws from code, named so new skins can use
them: `aura:spectral_glow`, `aura:flicker`, `aura:spotlight`,
`aura:paparazzi`, `bubble:classic_bubble`, `bubble:comic`, `bubble:neon`,
`bubble:pixel`, `bubble:gold_bubble`. Colour effects (`stars`, `lava`,
`halo`, `embers`, …) are listed in `palette.effects`. A brand-new effect needs
an app update and a `format` bump.

## Making a new skin

1. Draw it in the Skin Builder (`/admin/skins` on the website), or export the
   ops another way.
2. Save the file as `backend/flamey-skins/<id>.json` with a new, permanent id.
3. `node backend/scripts/flamey-skins-check.mjs` (also runs in CI).
4. Open a PR. Merging deploys it.

## In the app

`FlameyItem` is an id backed by the skin catalog (`FlameyWardrobe.swift`):
every property (slot, unlock, tier, hides, copy, palette) reads the item's
skin, and `FlameyItem(rawValue:)` accepts any id the catalog has. The named
constants (`.partyHat`, `.classic`, …) are only the items the app's own logic
refers to. `FlameyOutfitLayer` draws every piece from skin layers;
`FlameyArt.swift` keeps only shared geometry (anchors, tight surfaces,
headroom, where held props and companions go). The catalog is the bundled
`FlameySkins.json` (regenerate with `node app/FlameyExport/convert/bundle.mjs`
before a release) or, when newer, the last download from `GET /flamey/skins`
(`FlameySkinSync`).

## Migrating the shipped items (done)

The 133 shipped items were exported from their Swift art code with
`app/FlameyExport/run.sh` on a Mac (it compiled a copy of FlameyArt.swift
drawing into a recording `GraphicsContext`), assembled with
`convert/assemble.mjs`, and checked with `match.sh`: 490/490 renders within 1%
of the code's own. The Swift art and those tools were then deleted; they live
at commit `82f9f07a` if a re-export is ever needed.
