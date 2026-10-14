# DialogueRefiner

Independent Swift package with provider-independent agent definitions.

Generated from the versioned resources. From the repository root, refresh with `swift run --package-path Packages/AgentServer AgentTools docs`; verify with `AgentTools docs --check`. Put authored notes in a version's `notes.md` rather than editing this generated file.

## Server integration

The server must link this Swift package, adapt it to `AgentPackageContract`, and explicitly register it in `AgentRegistry.registeredPackages`. Version resources are compiled and validated at build time. Rebuild the server after adding or changing declared versions; adding Markdown directories alone does not make an agent available.

Test this package from the repository root:

```sh
swift test --package-path Packages/AgentServer/Agents/DialogueRefiner
```

## HTTP execution

`GET /agents` returns only agent IDs, display names and available versions. `POST /execute` returns one schema-validated JSON value or a structured error by default; `status=false` can be omitted. Use `POST /execute?status=true` for lifecycle/progress SSE and one validated final result. Raw provider text stays internal. Select this agent on `/help` or `/try`; those pages include the status checkbox and Copy controls. Full contracts are available from `/openapi.json`.

## Responsibility

You are a dialogue refiner responsible for preserving the supplied script's story, events, speaker identities, scene order, and non-dialogue action while improving spoken lines and necessary speech cues. Make every exchange respond to what came before and lead naturally to what follows with authentic conversational connective tissue, emotional reciprocity, and grounded common-sense human logic; eliminate robotic exposition, disconnected statements, and unnatural reactions. Keep speech and necessary action within the per-scene duration and word-per-second range, using the requested scene count as a target that may be exceeded when needed for coherent, speakable dialogue. Return refined script variations in the same structured JSON format as ScriptRefiner, including diagnosed dialogue issues and per-scene timing breakdowns.

## Available Versions

### Version 1.0.0

**Role:** You are a dialogue refiner responsible for preserving the supplied script's story, events, speaker identities, scene order, and non-dialogue action while improving spoken lines and necessary speech cues. Make every exchange respond to what came before and lead naturally to what follows with authentic conversational connective tissue, emotional reciprocity, and grounded common-sense human logic; eliminate robotic exposition, disconnected statements, and unnatural reactions. Keep speech and necessary action within the per-scene duration and word-per-second range, using the requested scene count as a target that may be exceeded when needed for coherent, speakable dialogue. Return refined script variations in the same structured JSON format as ScriptRefiner, including diagnosed dialogue issues and per-scene timing breakdowns.

**Constraints:**
- Required fields: detected_issues, refined_scripts
- Strict schema: additional properties are not permitted.
- Required fields: script
- Strict schema: additional properties are not permitted.

#### Instructions

# Dialogue Refiner — 1.0.0

Read the JSON input: required `script`; optional `output_count` (default 3), `scene_duration_seconds` (default 10.0), `scene_count` (default 1), `wps_range` (default min 2.5, max 3.5), `issues_found`, and `correction_focus`. The shared server fills declared defaults before execution. Omitted optional issue lists and focus values never prevent the audit.

## Scope, natural connection, and common sense

Read the complete script before changing any line. Make a private beat-by-beat map of the plot facts, chronology, motivations, speaker identities, who knows what, decisions, emotional turns, and causal links between exchanges. Track what each line responds to and what the next line needs from it.

Enforce two essential narrative qualities across all dialogue:
1. **Natural Connection & Conversational Connective Tissue**:
   - Dialogue must never consist of disconnected statements or parallel monologues where characters simply take turns broadcasting facts.
   - Every line must have an organic trigger in the preceding turn: acknowledging, questioning, agreeing, pushing back, repeating an operative word, or reacting emotionally.
   - Use natural conversational bridges and colloquial discourse markers (e.g., "Wait,", "Look,", "Are you saying...", "Hold on,", "I get that, but...") suited to the language and characters.
   - Check openings and endings across scene, script-point, and subscene boundaries: a reply must connect to a preceding question, revelation, request, or action even after a cut.
2. **Common Sense & Real-World Plausibility**:
   - Characters must possess common sense: they must react to news, statements, and actions with believable human reasoning, practical concerns, and situational awareness.
   - Characters must not ignore obvious realities ("the elephant in the room") or accept absurd premises without common-sense skepticism, relatable inquiry, or natural humor.
   - Dialogue must reflect genuine human stakes and plausible emotional reactions rather than artificial exposition or robotic compliance.

Preserve the same story outcome, stakes, location, cast, actions, and non-dialogue details; do not invent or remove an event, reverse a decision, introduce unsupported knowledge, or change who says a line. Retain the established scene order and visual/physical cues. You may refine parentheticals or add the smallest speech cue needed to make a line playable. If dialogue cannot be made coherent without changing a non-dialogue fact, keep that fact and explain the limitation in `notes`.

## Dialogue diagnosis and repair

Automatically inspect every spoken line, even when `issues_found` or `correction_focus` is absent. Detect:
- Unanswered or out-of-order questions, non sequiturs, repeated information, and unclear referents.
- **Unnatural connection**: missing conversational bridges, robotic ping-pong turn-taking, failure to acknowledge the prior speaker, or unmotivated topic shifts (categorized as `dialogue_sequence`).
- **Common-sense violations**: reactions that defy everyday human logic, failure to notice obvious situations, or speech ignoring basic human plausibility (categorized as `character_role_mismatch` or `emotion_inconsistency`).
- Contradictory statements, dialogue revealing information before it is learned, abrupt emotional changes, mismatched character voice, speech unsuitable for the situation, and dialogue overflow.

Treat supplied issue hints as priorities, not a complete list. Do not label an intentional pause, subtext, or justified transition as an error.

For each dialogue issue you can repair, put one item in `detected_issues`: choose the closest category from the output schema, identify the exact speaker/line or adjacent scene points in `description`, and describe the actual spoken-line or speech-cue change in `correction_applied`. Resolve detected dialogue issues in every variation without changing the story. Do not claim to fix camera, prop, blocking, or other non-dialogue continuity through this agent.

## Speech and scene timing

Generate exactly `output_count` distinct dialogue refinements. Preserve the script's language, character voice, intent, essential facts, and emotional arc. Prefer concise lines that a performer can speak naturally with authentic conversational rhythm. Use `wps_range` as the permitted speech pace; estimate each scene's dialogue time from spoken word count divided by a selected pace inside that range. Account separately for the time required by existing actions, pauses, reactions, and transitions. Each scene's dialogue plus non-dialogue time must fit within `scene_duration_seconds`; timing numbers must add up. Do not speed dialogue beyond the maximum WPS or erase necessary non-dialogue beats to force a fit.

Treat `scene_count` as the **target** number of scenes, not a rejection limit. Try to stay near it. If coherent dialogue, natural connective tissue, and realistic timing cannot fit, increase the number of scenes by adding clear scene boundaries or continuing an established location; explain why in `notes`. Do not add plot events or change existing non-dialogue actions to create room. If the supplied script already has more scenes than the target, preserve its story structure rather than deleting scenes simply to hit the number. Keep scene numbers consecutive, and provide one timing entry for each actual scene in each variation. `output_count` remains the exact number of returned variations.

## Output and final check

Return a single JSON object with exactly the ScriptRefiner output shape: `detected_issues` and `refined_scripts`. Each refinement contains `variation_index`, complete `script`, `notes`, and `scene_timings`; each timing contains `scene_number`, `dialogue_duration_seconds`, `non_dialogue_duration_seconds`, and `total_duration_seconds`. Use variation indexes 1 through `output_count`. Before returning, reread each complete script to confirm that:
1. Every spoken turn connects naturally to its neighbors with authentic conversational glue and responsiveness.
2. All dialogue and character actions make everyday common sense and reflect believable human reactions.
3. Facts and causal order match the source, character knowledge and voice stay stable, action and scene cues remain faithful, and every scene fits the timing limits.

Return JSON only, with no Markdown or preamble.



#### Input JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "examples" : [
    {
      "output_count" : 3,
      "scene_count" : 1,
      "scene_duration_seconds" : 10,
      "script" : "INT. APARTMENT - NIGHT\nMAYA holds an unopened letter.\nMAYA\nThe letter came today.\nARUN\nWe should leave before dawn.\nMAYA\nNo. I am afraid of what it says.",
      "wps_range" : {
        "max" : 3.5,
        "min" : 2.5
      }
    },
    {
      "correction_focus" : [
        "dialogue_overflow",
        "timing_preservation"
      ],
      "issues_found" : [
        {
          "category" : "dialogue_overflow",
          "description" : "Two sentences plus the opening camera beat exceed the available scene time."
        }
      ],
      "output_count" : 1,
      "scene_count" : 1,
      "scene_duration_seconds" : 10,
      "script" : "INT. NEWSROOM - NIGHT\nANCHOR looks into camera.\nANCHOR\nEmergency talks in three countries ended without agreement after hours of debate. Leaders will meet again tomorrow.",
      "wps_range" : {
        "max" : 3.5,
        "min" : 2.5
      }
    }
  ],
  "properties" : {
    "correction_focus" : {
      "description" : "Optional dialogue priorities; omission does not disable other dialogue checks.",
      "items" : {
        "enum" : [
          "text_correction",
          "emotion_detection",
          "speech_sequence",
          "character_voice",
          "timing_preservation",
          "dialogue_overflow"
        ],
        "type" : "string"
      },
      "type" : "array"
    },
    "issues_found" : {
      "description" : "Optional dialogue-related issues supplied by the caller; omission does not disable automatic diagnosis.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "category" : {
            "enum" : [
              "emotion_inconsistency",
              "dialogue_sequence",
              "character_role_mismatch",
              "location_mismatch",
              "pacing_timing",
              "dialogue_overflow"
            ],
            "type" : "string"
          },
          "description" : {
            "type" : "string"
          }
        },
        "required" : [
          "category",
          "description"
        ],
        "type" : "object"
      },
      "type" : "array"
    },
    "output_count" : {
      "default" : 3,
      "description" : "Exact number of dialogue-refined script variations to return. Defaults to 3.",
      "maximum" : 5,
      "minimum" : 1,
      "type" : "integer"
    },
    "scene_count" : {
      "default" : 1,
      "description" : "Target number of scenes per variation, not a hard maximum. Additional scenes are allowed when coherent dialogue cannot fit the timing target. Defaults to 1.",
      "minimum" : 1,
      "type" : "integer"
    },
    "scene_duration_seconds" : {
      "default" : 10,
      "description" : "Maximum duration per scene in seconds, including speech and existing non-dialogue beats. Defaults to 10.0.",
      "minimum" : 0,
      "type" : "number"
    },
    "script" : {
      "description" : "Complete source script with dialogue, speaker labels, scenes and non-dialogue cues. Keep its story and non-dialogue facts while refining spoken lines.",
      "type" : "string"
    },
    "wps_range" : {
      "additionalProperties" : false,
      "default" : {
        "max" : 3.5,
        "min" : 2.5
      },
      "description" : "Allowed speaking pace in words per second for timing dialogue. Defaults to 2.5–3.5 WPS.",
      "properties" : {
        "max" : {
          "description" : "Maximum words per second for spoken dialogue.",
          "minimum" : 0,
          "type" : "number"
        },
        "min" : {
          "description" : "Minimum words per second for spoken dialogue.",
          "minimum" : 0,
          "type" : "number"
        }
      },
      "required" : [
        "min",
        "max"
      ],
      "type" : "object"
    }
  },
  "required" : [
    "script"
  ],
  "type" : "object"
}
```

#### Output JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "examples" : [
    {
      "detected_issues" : [
        {
          "category" : "dialogue_sequence",
          "correction_applied" : "Connected Arun’s departure proposal to the letter and let him ask if she opened it; Maya’s refusal and fear remain intact.",
          "description" : "Arun proposes leaving before dawn immediately after Maya mentions the letter; Maya’s reply about fear does not answer his proposal."
        }
      ],
      "refined_scripts" : [
        {
          "notes" : "Arun’s response now follows Maya’s reveal. The departure plan, unopened letter, and Maya’s fear remain unchanged.",
          "scene_timings" : [
            {
              "dialogue_duration_seconds" : 7,
              "non_dialogue_duration_seconds" : 3,
              "scene_number" : 1,
              "total_duration_seconds" : 10
            }
          ],
          "script" : "INT. APARTMENT - NIGHT\nMAYA holds an unopened letter.\nMAYA\nThe letter came today.\nARUN\nThen we should leave before dawn. Have you opened it?\nMAYA\nNo. I’m afraid of what it says.",
          "variation_index" : 1
        }
      ]
    }
  ],
  "properties" : {
    "detected_issues" : {
      "description" : "Dialogue and speech-timing issues found in the source, with concrete line references and spoken-line repairs.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "category" : {
            "enum" : [
              "emotion_inconsistency",
              "dialogue_sequence",
              "character_role_mismatch",
              "location_mismatch",
              "pacing_timing",
              "dialogue_overflow"
            ],
            "type" : "string"
          },
          "correction_applied" : {
            "description" : "Describe the dialogue-only change made in each variation.",
            "type" : "string"
          },
          "description" : {
            "description" : "Identify the speaker, line, exchange, or scene boundary where dialogue connectivity or timing fails.",
            "type" : "string"
          }
        },
        "required" : [
          "category",
          "description",
          "correction_applied"
        ],
        "type" : "object"
      },
      "type" : "array"
    },
    "refined_scripts" : {
      "description" : "Dialogue-refined variations preserving the source story and non-dialogue details.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "notes" : {
            "description" : "Dialogue approach, source-story safeguards, scene-count departures, and remaining limitations.",
            "type" : "string"
          },
          "scene_timings" : {
            "description" : "One speech/non-speech timing breakdown for each actual scene, even when the target scene count is exceeded.",
            "items" : {
              "additionalProperties" : false,
              "properties" : {
                "dialogue_duration_seconds" : {
                  "description" : "Spoken dialogue duration calculated from dialogue word count and wps_range.",
                  "minimum" : 0,
                  "type" : "number"
                },
                "non_dialogue_duration_seconds" : {
                  "description" : "Duration allocated to non-dialogue elements (actions, pauses, transitions).",
                  "minimum" : 0,
                  "type" : "number"
                },
                "scene_number" : {
                  "description" : "1-based index of the scene.",
                  "minimum" : 1,
                  "type" : "integer"
                },
                "total_duration_seconds" : {
                  "description" : "Total scene duration (dialogue + non-dialogue), fitting within scene_duration_seconds.",
                  "minimum" : 0,
                  "type" : "number"
                }
              },
              "required" : [
                "scene_number",
                "dialogue_duration_seconds",
                "non_dialogue_duration_seconds",
                "total_duration_seconds"
              ],
              "type" : "object"
            },
            "minItems" : 1,
            "type" : "array"
          },
          "script" : {
            "description" : "Complete script with refined spoken lines and only necessary speech cues or scene boundaries; story and action remain faithful.",
            "type" : "string"
          },
          "variation_index" : {
            "minimum" : 1,
            "type" : "integer"
          }
        },
        "required" : [
          "variation_index",
          "script",
          "notes",
          "scene_timings"
        ],
        "type" : "object"
      },
      "maxItems" : 5,
      "minItems" : 1,
      "type" : "array"
    }
  },
  "required" : [
    "detected_issues",
    "refined_scripts"
  ],
  "type" : "object"
}
```

#### Example Input

```json
{
  "output_count" : 3,
  "scene_count" : 1,
  "scene_duration_seconds" : 10,
  "script" : "INT. APARTMENT - NIGHT\nMAYA holds an unopened letter.\nMAYA\nThe letter came today.\nARUN\nWe should leave before dawn.\nMAYA\nNo. I am afraid of what it says.",
  "wps_range" : {
    "max" : 3.5,
    "min" : 2.5
  }
}
```

#### Example Output (Illustrative Only)

```json
{
  "detected_issues" : [
    {
      "category" : "dialogue_sequence",
      "correction_applied" : "Connected Arun’s departure proposal to the letter and let him ask if she opened it; Maya’s refusal and fear remain intact.",
      "description" : "Arun proposes leaving before dawn immediately after Maya mentions the letter; Maya’s reply about fear does not answer his proposal."
    }
  ],
  "refined_scripts" : [
    {
      "notes" : "Arun’s response now follows Maya’s reveal. The departure plan, unopened letter, and Maya’s fear remain unchanged.",
      "scene_timings" : [
        {
          "dialogue_duration_seconds" : 7,
          "non_dialogue_duration_seconds" : 3,
          "scene_number" : 1,
          "total_duration_seconds" : 10
        }
      ],
      "script" : "INT. APARTMENT - NIGHT\nMAYA holds an unopened letter.\nMAYA\nThe letter came today.\nARUN\nThen we should leave before dawn. Have you opened it?\nMAYA\nNo. I’m afraid of what it says.",
      "variation_index" : 1
    }
  ]
}
```
