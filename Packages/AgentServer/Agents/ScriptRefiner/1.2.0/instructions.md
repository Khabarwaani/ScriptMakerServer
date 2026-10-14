# Script Refiner — 1.2.0

Read the supplied JSON input containing `script`, optional `output_count` (defaulting to 3), optional `scene_duration_seconds` (defaulting to 10.0), optional `scene_count` (defaulting to 1), optional `wps_range` (defaulting to min: 2.5, max: 3.5), optional `issues_found`, and optional `correction_focus`.

Refine the script through structured analytical and creative stages:

1. **Diagnosis & Detection**:
   - Inspect the entire script, every scene, script point, shot, and subscene for coherence, logical flow, narrative pacing, and consistency problems. Detection is mandatory even when `issues_found` and `correction_focus` are omitted; a focus changes priority, never disables other checks.
   - Detect these categories:
     - **emotion_inconsistency**: Mismatched character emotional reactions, unnatural mood shifts, inappropriate parentheticals, or emotional responses defying everyday human common sense.
     - **dialogue_sequence**: Unresponsive dialogue, broken conversational cause-and-effect, missing conversational bridges or connective tissue, unnatural topic shifts, failure to acknowledge prior turns, or non-sequitur exchanges where characters broadcast disconnected statements rather than engaging in authentic, responsive dialogue.
     - **location_sequence**: Incoherent transitions between spaces, impossible location shifts, or missing scene tags.
     - **camera_movement**: Impossible, disorienting, or unmotivated camera directions and framing jumps.
     - **character_role_mismatch**: Character archetype vs. dialogue mismatch, out-of-character speech, speech inconsistent with identity, profession, regional dialect, demographic, or social background, or characters acting contrary to everyday situational common sense.
     - **location_mismatch**: Dialogue, speech volume, cultural references, or physical interactions unsuited to the environment.
     - **pacing_timing**: Dialogue or actions that cannot fit the intended duration or narrative rhythm.
     - **character_continuity**: Unexplained changes in cast, identity, appearance, wardrobe, or physical condition; substitutions or disappearances across shots/subscenes without an entrance, exit, or justified scene transition.
     - **prop_continuity**: Broken prop lifecycle: objects introduced without setup, randomly appearing/disappearing, changing identity or appearance, duplicating, changing holder/hand/location/state without an action, or being reused after leaving possession without a supported transition.
     - **spatial_continuity**: Inconsistent character/prop positions, relative distances, orientation, blocking, or location within a scene; unmotivated teleportation across script points/subscenes.
     - **action_continuity**: Actions that reset, conflict with prior actions, skip necessary intermediate states, require occupied hands, or contradict current character state, real-world physics, or common-sense plausibility.
     - **dialogue_overflow**: Spoken dialogue whose word count and pacing cannot fit within the allocated `scene_duration_seconds` alongside necessary non-dialogue timings under the target `wps_range`, requiring sentence tightening, trimming, or distribution across scenes up to `scene_count`.
   - Incorporate supplied `issues_found` and independently detect additional issues. Do not label an explained change as an error.
   - For each detected issue, identify the concrete conflicting or missing script points/subscenes in `description`. Describe the actual repair in `correction_applied`, and apply that repair in every refined variation.

2. **Full Prop Lifecycle, Natural Connection & Scene Continuity Audit**:
   - Before rewriting, build a working continuity ledger for the entire script. For each scene establish its location and layout, cast identities and visual descriptors, each person's position/orientation and ongoing action, and every prop's stable identity and distinguishing appearance.
   - **Natural Connection & Conversational Connective Tissue**:
     - Ensure spoken dialogue is never a series of disjointed one-liners or parallel monologues. Each line must be an organic reaction to what came before, utilizing natural conversational bridges, callbacks, questions, agreements, or pushback.
     - Ensure transitions between scenes and subscenes have tight cause-and-effect continuity: consequences and emotional momentum from Scene 1 must carry naturally into Scene 2.
   - **Everyday Common Sense & Plausibility**:
     - Verify that characters react with relatable human common sense. If presented with shocking, bizarre, or official news, characters must react with plausible human emotions, skepticism, or practical everyday concerns (finances, commute, safety, family) rather than passive, robotic exposition.
     - Check that characters do not ignore obvious reality in front of them ("the elephant in the room") and that their decisions reflect believable human motivation.
   - Track each prop from its first supported introduction through every script point, shot, and subscene: origin/setup, existence, current holder and hand or physical location, condition/state, interactions and transformations, transfers, and eventual exit/disposition. Carry forward unchanged state explicitly in generation cues where needed. Reuse the same established prop; do not substitute a visually different item or invent duplicate copies.
   - A prop persists until an explicit, plausible action or narrative transition changes its state. Being outside the camera frame does not make it disappear. A close-up, reaction shot, camera cut, new script point, or subscene is not permission to reset the inventory, cast, wardrobe, blocking, or action.
   - Track all lifecycle changes: taking an item out, setting it down, pocketing/storing it, passing it between people or hands, consuming it, using it, opening/closing it, transforming/damaging it, retrieving it, carrying it offscreen, and leaving it behind. Every change needs a supported cause and a consistent resulting state. An item no longer held cannot be used from that hand until an explicit retrieval/transfer supplies it; a stored item remains stored until taken out.
   - Trace dependencies between people, props, and actions: hands already holding items, reachable positions, movement paths, contact with objects, and the completion/continuation of prior actions. Preserve cause-and-effect and physical feasibility at every beat.
   - Keep the same people and their established appearance throughout a scene and its subscenes. Introduce/remove people only through a supported entrance/exit or explicit scene transition. Across genuine scene changes, preserve recurring identities and carried props unless story context explains a change.
   - Detect missing introductions, unexplained possession changes, and unresolved/disappearing props automatically. If a state is ambiguous, use the smallest coherent repair consistent with source intent, and disclose the inferred setup/action in `correction_applied` or variation `notes`.

3. **Scene Timing Constraints & WPS Pacing**:
   - Enforce scene timing fitting strictly within `scene_duration_seconds` (default: 10.0 seconds) and total scenes up to `scene_count` (default: 1).
   - Divide scene timing into:
     - **Dialogue timing**: Governed by the input `wps_range` (default min: 2.5, max: 3.5 words per second). For spoken lines, calculate dialogue duration based on word count and target WPS pacing: `dialogue_duration_seconds = dialogue_words / target_wps`.
     - **Non-dialogue timing**: Managed based on script requirements and realism (physical actions, pauses, beats, establishing shots, reactions, transitions).
   - Ensure the sum of dialogue and non-dialogue timings for each scene does not exceed `scene_duration_seconds`.
   - If dialogue exceeds allowed bounds:
     - Tighten/modify sentences, eliminate verbose phrasing, or compress dialogue into concise, punchy lines.
     - If dialogue still cannot fit within a single scene without compromising realistic pacing or required non-dialogue actions, shift excess dialogue into subsequent scenes up to `scene_count`.
     - When multiple scenes are used, ensure each scene maintains coherent blocking, continuity, and self-contained timing adhering to `scene_duration_seconds`.

4. **Correction, Refinement & Recheck Verification**:
   - Generate exactly `output_count` refined script variations (default 3).
   - Preserve dramatic intent, emotional arc, character voice, and authentic vernacular while correcting all detected issues.
   - In each variation's `script`, include concise scene-level continuity setup and clear per-point/subscene cues for people, props, positions, and actions. Lock wardrobe, grooming, and demeanor descriptors across shots unless a justified change occurs.
   - **Comprehensive Recheck Verification**:
     - Before producing output, recheck and verify generated output across all issue categories (continuity, props, cast, space, action, emotion, dialogue, and timing) to ensure zero regressions.
     - Specifically verify that no new `dialogue_overflow` issues exist, word counts stay within the `wps_range`, and total durations for all scenes fit within `scene_duration_seconds`.
     - Compute the exact `scene_timings` breakdown for every scene in each variation, detailing `scene_number`, `dialogue_duration_seconds`, `non_dialogue_duration_seconds`, and `total_duration_seconds`.

5. **Output Formatting**:
   - Return one JSON object strictly matching `output.schema.json`:
     - `detected_issues`: Array of objects each with `category`, concrete `description`, and `correction_applied`. Include `dialogue_overflow` if detected and corrected.
     - `refined_scripts`: Array of variations, each with `variation_index`, complete `script`, `notes`, and `scene_timings`.
     - `scene_timings`: Array of objects for each scene specifying `scene_number`, `dialogue_duration_seconds`, `non_dialogue_duration_seconds`, and `total_duration_seconds`.
   - Do not wrap JSON in Markdown code fences. Do not output conversational preamble, explanations, or metadata outside the JSON structure.
