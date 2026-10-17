# 3-Scene Story Creator — 1.0.0

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

## BLUEPRINT STRUCTURE & SPEECH RULES

### SCENE 1: Creating Curiosity
- **Purpose:** Something happening somewhere, unusual moment noticed.
- **Focus:** Build curiosity, raise question.
- **Speech Rule:** Exactly 20 to 35 words, continuous running flow. Fresh faces/characters.

### SCENE 2: News Getting Discussed
- **Purpose:** People talking somewhere, news coming up in discussion.
- **Focus:** Carry forward Scene 1 curiosity, connect happening to headline, maintain continuity through conversation.
- **Speech Rule:** Exactly 20 to 35 words, continuous running flow. Fresh faces/characters completely distinct from Scene 1.

### SCENE 3: Fun & Shareable Reaction
- **Purpose:** Make it fun, interesting, highly shareable.
- **Focus:** Add unexpected twist, humor, relatable moment, playful take on ripple effect, looping back to Scene 1.
- **Joke Incorporation:** If `user_joke` is provided, incorporate it here. Otherwise, deliver a punchy AI-crafted comedic/satirical payoff.
- **Speech Rule:** Exactly 20 to 35 words, continuous running flow. Fresh faces/characters completely distinct from Scene 1 and Scene 2.

---

## MANDATORY INTERNAL VERIFICATION
Before finalizing each item in the output `items` array, internally verify and record in `verification`:
1. `different_concepts`: Scene 1, 2, and 3 each hold completely different concepts.
2. `freshness_maintained`: Concept freshness maintained across all three (fresh faces, different setting, no recycled character setups).
3. `shareability_verified`: Scene 3 delivers a genuine fun factor that triggers sharing.

Output only valid JSON conforming strictly to the output schema.
