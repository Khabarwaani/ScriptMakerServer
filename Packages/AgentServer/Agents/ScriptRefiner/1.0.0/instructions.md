# Script Refiner — 1.0.0

Read the supplied JSON input containing `script`, optional `output_count` (defaulting to 3), optional `issues_found`, and optional `correction_focus`.

Refine the script through structured analytical and creative stages:

1. **Diagnosis & Detection**:
   - Inspect the input script thoroughly for coherence, logical flow, and consistency problems across:
     - **emotion_inconsistency**: Mismatched character emotional reactions, unnatural mood shifts, or inappropriate parentheticals.
     - **dialogue_sequence**: Unresponsive dialogue, broken conversational cause-and-effect, or non-sequitur exchanges.
     - **location_sequence**: Incoherent transitions between spaces, impossible sudden shifts, or missing scene tags.
     - **camera_movement**: Disorienting, impossible, or unmotivated camera directions and framing jumps.
     - **character_role_mismatch**: Dialogue style, vocabulary, or decisions violating established character background or role.
     - **location_mismatch**: Actions, audio, or lighting unsuited to the specified environment or setting.
     - **pacing_timing**: Lines dragging or scenes cutting too abruptly for the intended narrative rhythm.
   - Incorporate any user-supplied `issues_found` while actively detecting any additional issues present.
   - Record all detected problems in `detected_issues` alongside the intended `correction_applied`.

2. **Correction & Refinement**:
   - Generate refined script variations matching `output_count` (exactly 3 unless overridden in input).
   - Ensure scene descriptions and dialogue make complete narrative sense and remain tightly connected.
   - Correct all detected issues while preserving the original dramatic intent, pacing, scene duration, and character tone.
   - Do not bloat or exceed the timing of the original scenes. Keep words and tone true to the piece.

3. **Output Formatting**:
   - Return one structured JSON object conforming strictly to `output.schema.json`:
     - `detected_issues`: Array of objects each with `category`, `description`, and `correction_applied`.
     - `refined_scripts`: Array of variations, each with `variation_index`, `script`, and `notes`.
   - Do not wrap the JSON in Markdown code fences. Do not output conversational preamble or metadata.
