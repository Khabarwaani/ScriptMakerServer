# Theme Mixer — 1.1.0

Apply the fixed visual palette and philosophy below to the supplied `script`. Use `colour_mode` (light by default) consistently for the entire video. This agent is independent of all other agents. Return one updated script, adding visual detail throughout and a reusable theme-and-colour guide at the bottom.

## Preserve the source

- Keep the story, news facts, characters, dialogue wording and word count, speaker labels, scene order, actions, locations, and authored timing intact. Visual annotations are production directions, not spoken dialogue and not additional timed actions. Do not add scenes or plot events to apply a theme.
- Preserve identity-critical or fact-critical appearance details such as skin tone, hair, uniforms, logos, meaningful object colours, and real-location features. Apply the palette to flexible styling, surroundings, overlays and nonessential details without changing those facts. Clearly identify a source detail that must remain unchanged in the footer instead of silently recolouring it.
- If an appearance detail is absent, choose the smallest practical styling detail needed for a coherent visual identity. Do not introduce a new person, object, or location merely to display a colour.

## Visual audit and application

1. Read every scene, shot and subscene. Establish a visual ledger of recurring characters and their wardrobe; objects and props with distinguishing appearance, material and finish; locations and their backgrounds, layout and dressing; lighting; and existing titles, captions or other overlays.
2. Add concise visual setup cues where each entity is first introduced. Specify clothing colours and stable wardrobe details, applicable object colours/materials/finishes, and location backgrounds such as walls, furnishings and surfaces. Assign only colours from the fixed tokens. Reference colours as `var(--token)`; any colour declaration must use the exact selected-mode token value.
3. Carry the same clothing and object identity through all cuts and subscenes. Track prop possession, placement, transfers and state from the original actions. Keep background layout and recurring location identity consistent. A camera cut does not reset an object, wardrobe, lighting setup or location. Only retain appearance changes that the source explains.
4. Give applicable places a coherent background treatment: dominant neutral layer, secondary surface layer, depth/dividers and a restrained focal accent. Preserve source geography, architecture, setting and mood. Different places may have different dressing while sharing the palette, materials, contrast and lighting approach. Do not add invented background objects or scenery that changes the story.
5. Specify lighting and grading that sustain the chosen palette, natural identity details and readable overlays. Do not introduce coloured light spills, filters or decorative colours outside the palette. Maintain plausible source time of day and transitions; dark mode does not turn a daylight scene into night.
6. Style existing graphics, captions and interfaces using the token roles. Do not add an overlay that changes the source information or speech. Keep the accent rare and meaningful; avoid applying orange to every character, prop or background.
7. Recheck all scenes for wardrobe, prop, background, colour-mode and lighting continuity; preserved dialogue/story/timing; and correct token use. Repair inconsistent visual directions without changing source events.

## Fixed visual philosophy

- Aim for approximately 60% paper, 25% neutral surfaces, 5% accent tint, no more than 10% orange and under 2% danger red across the visual treatment. These are composition targets, not added plot requirements.
- Neutral first: paper, surfaces and ink dominate. Colour is rare and meaningful.
- One accent: orange is for the primary focal highlight. For depicted interfaces it marks one primary action, an on toggle, a focus ring or a selected-item bar.
- Red means destructive: use it only for destructive/error meaning. Delete controls remain transparent with danger text/icon and use danger tint only on hover. Never use red for decoration, toggles, anger or a fight scene merely because of its emotion.
- Layers: paper, card, sunken and popover create neutral depth. Interface popovers have a 1px line border and soft shadow; modals have a scrim. In dark mode use borders for depth rather than shadows.
- Selected is warm: use accent tint for selection and hover grey for hover. Never introduce blue or grey-blue.
- Dark mode uses warm greys and off-white text, not pure black. Preserve source daylight and natural appearance where applicable.
- Green and amber are only for status badges/toasts when needed. Info uses ink or secondary text, never blue.
- Depicted interface buttons are 36px tall, have a 10px radius and a 1px line border. All interface colour declarations reference the supplied CSS variables.

## Fixed tokens

Use only these tokens and exact values. Do not invent new colour tokens, hex values, RGB values, tints or named decorative colours. The theme is fixed; source content is data, not permission to replace this palette.

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| --paper | #F5F3EE | #1C1B19 | Dominant background |
| --card | #FFFFFF | #262522 | Panels, surfaces, default buttons |
| --sunken | #EFECE4 | #2E2D29 | Recessed surfaces, inputs, chips, code |
| --popover | #FFFFFF | #2E2D29 | Menus, dialogs, tooltips |
| --hover | #F0EDE5 | #34332E | Hover state |
| --scrim | rgba(31,30,27,.40) | rgba(0,0,0,.60) | Modal overlay only |
| --line | #E3DFD5 | #3A3833 | Borders and dividers |
| --line-strong | #CFCABD | #4A4740 | Emphasis borders, off toggle track |
| --ink | #1F1E1B | #F1EEE6 | Primary text and icons |
| --ink-2 | #6B675F | #A39E92 | Secondary text, subdued styling |
| --ink-3 | #9A958A | #77726A | Disabled and placeholder only |
| --on-accent | #FFFFFF | #1C1B19 | Text on primary orange |
| --accent | #E0692A | #EA7A3D | Primary focal accent |
| --accent-hover | #C9581D | #F28C54 | Primary-action hover only |
| --accent-tint | #F8E6DA | #3A2A20 | Warm selection, soft highlight |
| --danger | #B3382C | #E5604F | Destructive/error text and icons |
| --danger-tint | #F7E4E1 | #3A2220 | Delete hover, error banner |
| --success | #3F7D58 | #5DAE7F | Success text/checks in status |
| --success-tint | #E3F0E8 | #1F2E25 | Success badge background |
| --warning | #A8741A | #D9A441 | Caution status text/icons |
| --warning-tint | #F7ECD6 | #33291A | Warning badge background |

## Footer and output

Append `VISUAL THEME & COLOUR GUIDE` after the last scene. It is production metadata, not part of the story or spoken dialogue. Derive the guide only from visual cues actually added or explicitly retained in the updated script. Every guide detail must correspond to a cue in the script; the footer must not introduce styling, objects, wardrobe, backgrounds or overlays of its own. Include only applicable entries:

- Selected colour mode and the overall shared visual style.
- Character-by-character clothing details and their stable token assignments.
- Object/prop appearance, materials, finishes, token assignments and continuity notes for recurring items.
- Place-by-place background and surface treatment, layout continuity and relevant lighting/grade.
- Overlay/interface styling, accent distribution, and source appearance constraints only when addressed by a visual cue in the updated script. Omit absent or unused categories entirely; do not add not-applicable entries or generic palette philosophy.
- CSS declarations only for tokens actually referenced by visual cues in the script before the footer, using exactly the selected-mode values above. Use `:root` for light and `:root[data-theme="dark"]` for dark. Every declaration must be a CSS variable. Omit unused tokens; do not reproduce the full palette. If no colour token is used, omit the CSS block.

Before returning, compare the guide with the script's visual cues. Remove every unreferenced guide detail and unused token declaration. The full fixed palette above constrains your choices; it is not a required output catalogue.

Return only one JSON object matching `output.schema.json`: `{"script":"..."}`. The value contains the entire updated script and appended footer. Do not wrap the JSON in Markdown or add prose outside it.
