# Script Refiner — 1.1.0

Read the supplied JSON input containing `script`, optional `output_count` (defaulting to 3), optional `issues_found`, and optional `correction_focus`.

Refine the script through structured analytical and creative stages:

1. **Diagnosis & Detection**:
   - Inspect the entire script, every scene, script point, shot and subscene for coherence, logical flow and consistency problems. Detection is mandatory even when `issues_found` and `correction_focus` are omitted; a focus changes priority, never disables other checks.
   - Detect these categories:
     - **emotion_inconsistency**: Mismatched reactions, unnatural mood shifts or inappropriate parentheticals.
     - **dialogue_sequence**: Broken conversational cause-and-effect or non-sequitur exchanges.
     - **location_sequence**: Incoherent transitions, impossible location shifts or missing scene tags.
     - **camera_movement**: Impossible, disorienting or unmotivated camera directions and framing jumps.
     - **character_role_mismatch**: Character archetype vs. dialogue mismatch, out-of-character speech or speech inconsistent with identity, profession, regional dialect, demographic or social background.
     - **location_mismatch**: Dialogue, speech volume, cultural references or physical interactions unsuited to the environment.
     - **pacing_timing**: Dialogue or actions that cannot fit the intended duration or narrative rhythm.
     - **character_continuity**: Unexplained changes in cast, identity, appearance, wardrobe or physical condition; substitutions or disappearances across shots/subscenes without an entrance, exit or justified scene transition.
     - **prop_continuity**: Broken prop lifecycle: objects introduced without setup, randomly appearing/disappearing, changing identity or appearance, duplicating, changing holder/hand/location/state without an action, or being reused after leaving possession without a supported transition.
     - **spatial_continuity**: Inconsistent character/prop positions, relative distances, orientation, blocking or location within a scene; unmotivated teleportation across script points/subscenes.
     - **action_continuity**: Actions that reset, conflict with prior actions, skip necessary intermediate states, require occupied hands, or contradict the current character/prop state.
   - Incorporate supplied `issues_found` and independently detect additional issues. Do not label an explained change as an error.
   - For each detected issue, identify the concrete conflicting or missing script points/subscenes in `description`. Describe the actual repair in `correction_applied`, and apply that repair in every refined variation.

2. **Full Prop Lifecycle & Scene Continuity Audit**:
   - Before rewriting, build a working continuity ledger for the entire script. For each scene establish its location and layout, cast identities and visual descriptors, each person's position/orientation and ongoing action, and every prop's stable identity and distinguishing appearance.
   - Track each prop from its first supported introduction through every script point, shot and subscene: origin/setup, existence, current holder and hand or physical location, condition/state, interactions and transformations, transfers and eventual exit/disposition. Carry forward unchanged state explicitly in generation cues where needed. Reuse the same established prop; do not substitute a visually different item or invent duplicate copies.
   - A prop persists until an explicit, plausible action or narrative transition changes its state. Being outside the camera frame does not make it disappear. A close-up, reaction shot, camera cut, new script point or subscene is not permission to reset the inventory, cast, wardrobe, blocking or action.
   - Track all lifecycle changes, not just dropping or throwing: taking an item out, setting it down, pocketing/storing it, passing it between people or hands, consuming it, using it, opening/closing it, transforming/damaging it, retrieving it, carrying it offscreen, and leaving it behind. Every change needs a supported cause and a consistent resulting state. An item no longer held cannot be used from that hand until an explicit retrieval/transfer supplies it; a stored item remains stored until taken out.
   - Trace dependencies between people, props and actions: hands already holding items, reachable positions, movement paths, contact with objects and the completion/continuation of prior actions. Preserve cause-and-effect and physical feasibility at every beat.
   - Keep the same people and their established appearance throughout a scene and its subscenes. Introduce/remove people only through a supported entrance/exit or explicit scene transition. Across genuine scene changes, preserve recurring identities and carried props unless story context explains a change; a new scene is not an automatic identity or inventory reset.
   - Detect missing introductions, unexplained possession changes and unresolved/disappearing props automatically. If a state is ambiguous, use the smallest coherent repair consistent with source intent, and disclose the inferred setup/action in `correction_applied` or variation `notes`. Do not invent unnecessary objects, characters or story events merely to fill a ledger.

3. **Correction & Refinement**:
   - Generate exactly `output_count` refined script variations (default 3).
   - Preserve dramatic intent, emotional arc, original scene duration and pacing. Correct all detected issues in every variation. Prefer removing a contradictory/unnecessary reference or a short non-spoken continuity cue over adding an extra scene or lengthening spoken dialogue.
   - In each variation's `script`, include concise scene-level continuity setup and clear per-point/subscene cues for people, props, positions and actions. Reassert stable identifiers/appearance when a shot could otherwise generate a different person or prop. Record necessary state changes at the beat where they happen, and maintain their resulting state in every later beat. These visual annotations do not add spoken lines or extend runtime.
   - Enforce consistent character archetypes and distinct, believable speech. Use authentic language, regional vernacular, conversational idioms and professional terminology matching the character and location.
   - Every named character needs precise wardrobe, styling, grooming, posture and demeanor matching their role. Lock those descriptors across shots unless a visible, justified change occurs.
   - Adapt speech volume, delivery and actions to the physical environment. Keep scenes and dialogue narratively connected and physically plausible.
   - After drafting each variation, re-run the full ledger forward, point by point and subscene by subscene. Verify that all props have supported introductions and persistent identities, possession/location/state evolves only through explained transitions, people remain consistent, blocking and actions connect, and every reported correction is present. Repair any newly introduced discontinuity before returning output.

4. **Output Formatting**:
   - Return one JSON object strictly matching `output.schema.json`:
     - `detected_issues`: Objects with `category`, concrete `description` and `correction_applied`.
     - `refined_scripts`: Variations with `variation_index`, complete `script` and `notes`.
   - Keep continuity setup and lifecycle cues inside each `script`; summarize inferred repairs in `notes`. Do not add undeclared top-level fields or expose a separate private reasoning ledger.
   - Do not wrap JSON in Markdown or return preamble, provider metadata or tool annotations.
