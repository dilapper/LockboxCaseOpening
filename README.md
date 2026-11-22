# LockboxCaseOpening

A World of Warcraft addon that turns opening a lockbox into a CS-style case opening.

When you open a lockbox, a chest drops onto the screen, then a strip of items spins past a marker and settles on the best item inside. The rest of the screen dims, leaving a circular window around the spinner.

Works for: Ornate Bronze, Heavy Bronze, Iron, Strong Iron, Steel, Reinforced Steel, Mithril, Thorium and Eternium Lockboxes (English client). The chest's metal is tinted to match the box.

- The spinner is filled with white and green items only, so a blue or better drop stands out.
- A blue or better find is announced in guild chat, once the spin lands: "<your character> just found [item] in a lock box!" (skipping the animation still announces it).
- Click the overlay to skip the animation.

## Install

Copy the `LockboxCaseOpening` folder into your `Interface/AddOns` directory.

## Options

Open Esc > Options > AddOns > LockboxCaseOpening, or use `/lockcase options`. You can turn the animation off, turn the guild announcement off, and play a full test animation.

## Commands

| Command | Effect |
| --- | --- |
| `/lockcase options` | Open the options panel |
| `/lockcase test` | Play the full animation (never announces to guild) |
| `/lockcase spin` | Play just the spinner, skipping the chest intro |
| `/lockcase on` / `off` | Turn the animation on or off |
| `/lockcase findsound <text>` | List game sound names containing the text |
| `/lockcase sound <NAME or id>` | Play a sound |
| `/lockcase debug` | Print what the addon sees (for bug reports) |

## Art

The chest and the spinner cut-out are generated, not hand-drawn. To regenerate them (PowerShell 7):

```
pwsh tools/make_case_art.ps1 LockboxCaseOpening
pwsh tools/make_circle_hole.ps1 LockboxCaseOpening
```

`make_case_art.ps1` ray-casts a small 3D chest into `case_wood.tga` (full colour) and `case_metal.tga` (greyscale, tinted per box in-game).
