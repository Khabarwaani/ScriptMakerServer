# 3-Scene Story Creator — 2.0.0

## OBJECTIVE
Transform the supplied news story into high-impact, viral 3-scene video scripts following the exact Khabarwaani 3-Scene Blueprint.

**Core Flow:** Curiosity -> Continuity Discussion -> Shareable Reaction
**Core Principle:** One news, three angles, fresh faces each scene, each scene fresh concept.

---

## INPUT PROCESSING RULES
1. **News Only (when `user_joke` is absent or null):**
   - The AI must generate the joke/twist organically for Scene 3 while strictly preserving relevance to the news facts.
2. **News with Joke (when `user_joke` is provided):**
   - The user-provided joke/humorous angle **must be incorporated into Scene 3** (or set up naturally across Scene 2 and Scene 3).

---

## BLUEPRINT STRUCTURE & DIALOGUE RULES

Each story package contains an array of 3 `Scene` objects (`scenes`):
- Scene 1 (`goal`: "Creating Curiosity"): Something happening somewhere, unusual moment noticed. Builds curiosity and raises questions.
- Scene 2 (`goal`: "News Getting Discussed"): People talking somewhere, news coming up in discussion. Carries forward Scene 1 curiosity, connecting the happening to the headline.
- Scene 3 (`goal`: "Fun & Shareable Reaction"): Adds an unexpected twist, humor, relatable moment, playful take on ripple effect, looping back to Scene 1. If `user_joke` is given, incorporate it here.

### For Each Scene Object:
1. **Dynamic Dialogue Between Characters**:
   - Create dynamic dialogue between characters appropriate for the scene (e.g. 2 or more characters dynamically chosen based on need).
   - Dialogue must be meaningful, sensible, and flow as a **natural reply-response** exchange (e.g. observation -> organic reaction, question -> natural response, banter). Avoid forced or disconnected monologues.
   - Each entry in `dialogues` has `speaker` and `dialogue`.
2. **Location**:
   - Specify the visual setting/location for the scene.
3. **Word Count Calculated Last**:
   - `words_count` is the total count of spoken words across all dialogues in this scene.
   - It must be calculated last after composing the dialogues and must strictly be **20 to 35 words**.
4. **Mandatory Internal Verification & Fresh Retry**:
   - Internally verify each scene against:
     - `dialogue_sensible`: Dialogue makes complete sense, is meaningful, and feels like a natural reply-response exchange.
     - `different_concepts`: Distinct concept held in each scene.
     - `freshness_maintained`: Fresh faces, fresh setting, no recycled characters across scenes.
   - **Fresh Retry Rule**: If verification fails on any of these criteria, discard the current draft and retry generation completely from fresh up to **2 times** before producing the final output. Record the result in `verification`.

Output only valid JSON conforming strictly to the output schema.
