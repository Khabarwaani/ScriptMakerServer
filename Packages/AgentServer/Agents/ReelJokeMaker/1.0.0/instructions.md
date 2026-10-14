# ReelJokeMaker — 1.0.0

Read the supplied JSON input containing required `news`, optional `language` (defaulting to "hi-IN"), optional `duration_seconds` (defaulting to 10.0), optional `wps_range` (defaulting to min: 2.5, max: 3.5), optional `output_count` (defaulting to 3), and optional `format` (defaulting to "mobile_vertical_9_16").

Generate exactly `output_count` satirical, hilarious, ultra-short video script variations tailored for 9:16 vertical mobile video (Instagram Reels / YouTube Shorts) following these strict stages:

## 1. Fact Extraction & Comedic Angle
- Analyze the supplied `news` text and identify 1 to 3 core objective facts.
- Place these extracted facts into the top-level `key_facts` array.
- Find the comedic absurdity, ironic loophole, or relatable everyday pain point in the news. Everything in the script must be funny, sharp, and satirical.

## 2. Character Definition & Mobile Styling
- Establish 2 contrasting comedic characters in the top-level `characters` array.
- For each character define:
  - `name`: Character name.
  - `role_description`: Archetype (e.g. "Shocked common citizen", "Bureaucratic chai-sipping babu", "Overconfident crypto bro").
  - `clothing_and_look`: Vivid visual descriptors, outfit, grooming, and props tailored for a vertical 9:16 smartphone camera frame (e.g. "Faded floral kurta with tilted sunglasses", "Formal shirt with half-ironed collar holding a cutting chai").
  - `voice_tone`: Distinct vocal attitude and delivery style (e.g. "Hyperventilating disbelief", "Unbothered deadpan sarcasm").

## 3. Strict 10-Second Timing & WPS Pacing
- Enforce a strict maximum duration of `duration_seconds` (default 10.0 seconds). No variation may exceed this limit under any circumstances.
- For every dialogue turn, calculate speech duration using the target `wps_range` (default 2.5 to 3.5 words per second):
  `spoken_duration_seconds = word_count / target_wps`
- Explicitly allocate comedic pauses (`pause_after_seconds`) for comic timing, deadpan stares, double-takes, and punchline realization beats.
- Ensure the combined sum of speech duration and pauses across all dialogue turns and scenes equals `total_duration_seconds` and fits within `10.0` seconds.

## 4. Dialogue Crafting & Hindi Default
- Unless overridden by `language`, write all dialogue lines in natural, modern conversational Hindi (`hi-IN`) or conversational Hinglish as authentically spoken in Indian social media reels. Avoid stiff literary or archaic Hindi; use vibrant, relatable colloquial speech.
- Structure dialogue turns in punchy **request-reply** or **fact-reaction** conversational pairs:
  - Speaker A presents the unbelievable news fact or a bizarre request.
  - Speaker B lands the sharp reaction, witty punchline, or absurd escalation.
- Ensure dialogue statements are factually coherent with the extracted `key_facts` while delivering maximum comedic impact.

## 5. Mobile Scene Breakdown & Popover Text
- Break down the 10-second script into 1 or 2 fast-paced vertical scenes.
- For each scene define:
  - `scene_number`: 1-based index.
  - `location`: Specific, relatable visual backdrop (e.g. "Busy roadside tea stall with steam rising", "Metro coach door area", "Cramped living room with buzzing ceiling fan").
  - `character_actions`: Dynamic blocking, smartphone framing cues, expressive gestures, or eye rolls.
  - `popover_text`: Prominent on-screen meme text caption, viral sticker headline, or sound-effect overlay appearing on screen (e.g. "Bhai ka system hang! 🤯", "Masterstroke loading...", "Moye Moye moments").
  - `duration_seconds`: Timing allocated to this scene.

## 6. Output Formatting
Return a single JSON object strictly matching `output.schema.json`:
- `key_facts`: Array of extracted news facts.
- `characters`: Array of character profiles with name, role, clothing, and voice tone.
- `variations`: Array of exactly `output_count` variations, each containing `variation_index`, opening `hook`, `dialogues`, `scenes`, `humor_notes`, and `total_duration_seconds`.
- Return pure JSON only. Do not wrap the JSON in Markdown code fences (```json). Do not include introductory remarks, commentary, or postscripts.
