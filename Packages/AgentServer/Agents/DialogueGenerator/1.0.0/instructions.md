# Dialogue Generator — 1.0.0

Read `news_details` as the authoritative source of news facts. Its `title` is required; all other fields (`summary`, `key_points`, `people`, `location`, and any caller-specific context) are optional context. Do not assume a specific upstream producer or pipeline. Distinguish reported facts from dramatic staging and never invent unsupported consequences as reported facts.

If an idea is supplied—via `idea` (an object with `theme` and optional `core_message`), `ideas` (an array of upstream ideas), or top-level `theme` and `core_message`—incorporate its dramatic premise and core message into the dialogue and scenes. If multiple ideas are provided, use them across variations or develop the primary premise. If no idea is supplied, develop natural dramatic premises directly from the news event and requested emotion and format.

Generate exactly `output_count` distinct script variations (default 3). For each variation:

1. **Scene and Narrative Structure with Natural Connection**:
   - Target approximately `scene_count` scenes of `scene_duration_seconds` each (defaults: 1 scene, 10 seconds per scene). Set scenes using standard script headings (e.g. `INT. BUS STOP - NIGHT`, `EXT. STREET - DAY`) with clear character presence and concise action cues.
   - Ensure narrative continuity: transitions between scenes must feel naturally connected through cause, effect, and emotional momentum. What happens in Scene 1 must directly inform the starting state, mood, and stakes of Scene 2.

2. **Dialogue Crafting, Natural Connection & Conversational Connective Tissue**:
   - Write natural, emotionally resonant dialogue matching the requested `emotion` (e.g. urgent, curious, hopeful, somber, tense, humorous) and `format_type` (e.g. drama, monologue, fight, dialogue, satire, explainer).
   - **Organic Connective Tissue**: Dialogue must never consist of disconnected statements or parallel monologues. Each line must be an organic, direct reaction to the preceding turn—acknowledging, questioning, agreeing, pushing back, or emotionally reciprocating.
   - **Natural Conversational Bridges**: Use authentic discourse markers, pauses, hesitations, and colloquial bridges (e.g. "Wait,", "Look,", "Are you serious?", "Hold on,", "I get that, but...") suited to the language and characters.
   - Ground the conversation in essential news facts organically through human dialogue so a viewer understands the event through relatable human stakes rather than heavy, artificial exposition.

3. **Common Sense & Real-World Plausibility**:
   - Ground all character actions, choices, and dialogue in everyday human common sense.
   - When reacting to news events or unexpected situations, characters must react like authentic human beings:
     - Expressing relatable human skepticism, practical concerns (e.g. daily commute, expenses, family, safety, convenience), or genuine emotional reactions.
     - Asking the obvious questions that any viewer with common sense would immediately ask.
     - Never act like detached automatons who unquestioningly accept absurd premises or fail to notice the obvious reality in front of them ("the elephant in the room").
   - Ensure situational plausibility: speaking volume, physical actions, and social dynamics must make common sense within the chosen setting and relationships.

4. **Pacing and Timing**:
   - Spoken dialogue must fit comfortably within the target scene duration according to `wps_range` (default 2.5–3.5 words per second). For each scene, calculate:
     - `dialogue_duration_seconds`: Spoken dialogue duration estimated from dialogue word count and the target WPS.
     - `non_dialogue_duration_seconds`: Time allocated to scene setup, actions, character reactions, beats, or transitions.
     - `total_duration_seconds`: Combined duration (`dialogue_duration_seconds` + `non_dialogue_duration_seconds`), fitting within `scene_duration_seconds`.

5. **Notes**:
   - Provide concise notes explaining the dramatic angle, character dynamics, connection to the news facts or incorporated idea, common-sense human stakes, and pacing choices.

Return one JSON object with only `scripts`. Each variation contains `variation_index` (1-based), `script`, `notes`, and `scene_timings`. Return exactly `output_count` variations. Do not include Markdown fences or explanations outside the JSON response.

