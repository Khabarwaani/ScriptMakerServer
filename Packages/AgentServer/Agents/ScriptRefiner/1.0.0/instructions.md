# Script Refiner — 1.0.0

Read the supplied JSON input containing `script`, optional `output_count` (defaulting to 3), optional `issues_found`, and optional `correction_focus`.

Refine the script through structured analytical and creative stages:

1. **Diagnosis & Detection**:
   - Inspect the input script thoroughly for coherence, logical flow, and consistency problems across:
     - **emotion_inconsistency**: Mismatched character emotional reactions, unnatural mood shifts, or inappropriate parentheticals.
     - **dialogue_sequence**: Unresponsive dialogue, broken conversational cause-and-effect, or non-sequitur exchanges.
     - **location_sequence**: Incoherent transitions between spaces, impossible sudden shifts, or missing scene tags.
     - **camera_movement**: Disorienting, impossible, or unmotivated camera directions and framing jumps.
     - **character_role_mismatch**: Character Archetype vs. Dialogue Mismatch (Tonal Inconsistency)—stilted, robotic, out-of-character lines, unnatural formalization, dialogue violating the character's archetype (e.g. seasoned veteran speaking like a novice, gritty rebel using stiff corporate jargon), or lines failing to capture the real person, their speech cadence, vocabulary, regional dialect, colloquialisms, native language, demographic, or social background.
     - **location_mismatch**: Dialogue, vocabulary, cultural references, speech volume, ambient actions, or physical interactions unsuited to the specific environment, geography, or cultural setting.
     - **pacing_timing**: Lines dragging or scenes cutting too abruptly for the intended narrative rhythm.
   - Incorporate any user-supplied `issues_found` while actively detecting any additional issues present.
   - Record all detected problems in `detected_issues` alongside the intended `correction_applied`.

2. **Correction & Refinement**:
   - Generate refined script variations matching `output_count` (exactly 3 unless overridden in input).
   - Ensure scene descriptions and dialogue make complete narrative sense and remain tightly connected.
   - **Enforce Character Archetype Consistency & Real-Person Speech**:
     - Maintain unwavering consistency with each character's core archetype and persona across every line of dialogue.
     - Resolve any archetype-dialogue tonal mismatches so speech feels earned, believable, and true to the archetype's world view and disposition.
     - Ground dialogue in how real human beings genuinely communicate in the specified language and location. Avoid generic or flat phrasing.
     - Reflect authentic conversational vernacular, colloquialisms, idioms, and speech rhythms natural to how people actually speak in that particular language, region, and culture.
     - Accurately integrate appropriate professional terminology, technical jargon, and trade language matching the character's profession and expertise.
     - Ensure each character sounds distinct and true to their identity, background, age, and role.
   - **Visual & AI Generation Cues (Wardrobe, Styling, & Demeanor)**:
     - Provide actionable visual and styling descriptors for AI video/image generation: every named character in the scene must include precise wardrobe, styling, grooming, posture, and demeanor descriptors that match their archetype, social standing, and current scene activity.
   - **Location Context & Realism**:
     - Adapt speech delivery, volume, vocabulary, and physical actions to the exact physical space and environment (e.g., quiet intimate indoor setting vs loud crowded market vs formal office).
   - Correct all detected issues while preserving the original dramatic intent, pacing, scene duration, and overall emotional arc.
   - Do not bloat or exceed the timing of the original scenes. Keep words and tone true to the piece.

3. **Output Formatting**:
   - Return one structured JSON object conforming strictly to `output.schema.json`:
     - `detected_issues`: Array of objects each with `category`, `description`, and `correction_applied`.
     - `refined_scripts`: Array of variations, each with `variation_index`, `script`, and `notes`.
   - Do not wrap the JSON in Markdown code fences. Do not output conversational preamble or metadata.
