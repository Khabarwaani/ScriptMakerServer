# ScriptRefiner

Independent Swift package with provider-independent agent definitions.

Generated from the versioned resources. From the repository root, refresh with `swift run --package-path Packages/AgentServer AgentTools docs`; verify with `AgentTools docs --check`. Put authored notes in a version's `notes.md` rather than editing this generated file.

## Server integration

The server must link this Swift package, adapt it to `AgentPackageContract`, and explicitly register it in `AgentRegistry.registeredPackages`. Version resources are compiled and validated at build time. Rebuild the server after adding or changing declared versions; adding Markdown directories alone does not make an agent available.

Test this package from the repository root:

```sh
swift test --package-path Packages/AgentServer/Agents/ScriptRefiner
```

## HTTP execution

`GET /agents` returns only agent IDs, display names and available versions. `POST /execute` returns one schema-validated JSON value or a structured error by default; `status=false` can be omitted. Use `POST /execute?status=true` for lifecycle/progress SSE and one validated final result. Raw provider text stays internal. Select this agent on `/help` or `/try`; those pages include the status checkbox and Copy controls. Full contracts are available from `/openapi.json`.

## Responsibility

You are a script refiner responsible for diagnosing and correcting narrative, dialogue, character, spatial, action and full prop lifecycle continuity so scripts describe believable people and can be generated consistently as video. Automatically audit every script point, shot and subscene, preserve established people and props until an explained change occurs, maintain physically coherent possession, locations and actions, and refine authentic speech and visual descriptors without extending the original scene duration.

## Available Versions

### Version 1.0.0

**Role:** You are a script refiner responsible for analyzing, diagnosing, and refining scripts so characters speak and behave like real, believable people, fully primed for visual and AI generation. Your mission is to enforce character archetype consistency and eliminate archetype vs. dialogue mismatches (tonal inconsistency), ensure every named character includes precise wardrobe, styling, and demeanor descriptors matching their role in the scene, and ground all dialogue in realistic, location-specific conversational vernacular, authentic linguistic idioms of how people talk in the generated language and location, and accurate professional terminology.

**Constraints:**
- Required fields: detected_issues, refined_scripts
- Strict schema: additional properties are not permitted.
- Required fields: script
- Strict schema: additional properties are not permitted.

#### Instructions

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


#### Input JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "examples" : [
    {
      "correction_focus" : [
        "text_correction",
        "emotion_detection",
        "location_continuity"
      ],
      "issues_found" : [
        {
          "category" : "emotion_inconsistency",
          "description" : "John is laughing while stating he lost everything."
        }
      ],
      "output_count" : 3,
      "script" : "INT. OFFICE - DAY\nJOHN (laughing happily)\nI just lost everything.\nEXT. BEACH - NIGHT\nMARY (whispering)\nWhy did we move here so suddenly?"
    }
  ],
  "properties" : {
    "correction_focus" : {
      "description" : "Optional subset of issue types to prioritize during refinement.",
      "items" : {
        "enum" : [
          "text_correction",
          "emotion_detection",
          "speech_sequence",
          "location_continuity",
          "camera_continuity",
          "character_voice",
          "timing_preservation"
        ],
        "type" : "string"
      },
      "type" : "array"
    },
    "issues_found" : {
      "description" : "Optional list of user-specified issues already known or identified in the script.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "category" : {
            "enum" : [
              "emotion_inconsistency",
              "dialogue_sequence",
              "location_sequence",
              "camera_movement",
              "character_role_mismatch",
              "location_mismatch",
              "pacing_timing"
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
      "description" : "Number of refined script variations to generate. Defaults to 3.",
      "maximum" : 5,
      "minimum" : 1,
      "type" : "integer"
    },
    "script" : {
      "description" : "The original script text to analyze and refine.",
      "type" : "string"
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
          "category" : "emotion_inconsistency",
          "correction_applied" : "Replaced laughing with somber pacing.",
          "description" : "John laughs unnaturally during grave news."
        }
      ],
      "refined_scripts" : [
        {
          "notes" : "Direct emotional correction maintaining original word count.",
          "script" : "INT. OFFICE - DAY\nJOHN (devastated)\nI just lost everything.",
          "variation_index" : 1
        },
        {
          "notes" : "Nuanced reaction emphasizing shock.",
          "script" : "INT. OFFICE - DAY\nJOHN (stunned silence, then quiet disbelief)\nI... I just lost everything.",
          "variation_index" : 2
        },
        {
          "notes" : "Visceral physical beat preserving exact scene duration.",
          "script" : "INT. OFFICE - DAY\nJOHN (hands shaking, voice breaking)\nIt's all gone. Everything.",
          "variation_index" : 3
        }
      ]
    }
  ],
  "properties" : {
    "detected_issues" : {
      "description" : "Comprehensive list of issues detected and diagnosed in the script.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "category" : {
            "enum" : [
              "emotion_inconsistency",
              "dialogue_sequence",
              "location_sequence",
              "camera_movement",
              "character_role_mismatch",
              "location_mismatch",
              "pacing_timing"
            ],
            "type" : "string"
          },
          "correction_applied" : {
            "description" : "Summary of how this issue was resolved across the refined scripts.",
            "type" : "string"
          },
          "description" : {
            "description" : "Explanation of the issue found in the source script.",
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
      "description" : "Array of refined script variations correcting identified issues.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "notes" : {
            "description" : "Specific focus or subtle tonal direction of this variation.",
            "type" : "string"
          },
          "script" : {
            "description" : "The refined script text.",
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
          "notes"
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
  "correction_focus" : [
    "text_correction",
    "emotion_detection",
    "location_continuity"
  ],
  "issues_found" : [
    {
      "category" : "emotion_inconsistency",
      "description" : "John is laughing while stating he lost everything."
    }
  ],
  "output_count" : 3,
  "script" : "INT. OFFICE - DAY\nJOHN (laughing happily)\nI just lost everything.\nEXT. BEACH - NIGHT\nMARY (whispering)\nWhy did we move here so suddenly?"
}
```

#### Example Output (Illustrative Only)

```json
{
  "detected_issues" : [
    {
      "category" : "emotion_inconsistency",
      "correction_applied" : "Replaced laughing with somber pacing.",
      "description" : "John laughs unnaturally during grave news."
    }
  ],
  "refined_scripts" : [
    {
      "notes" : "Direct emotional correction maintaining original word count.",
      "script" : "INT. OFFICE - DAY\nJOHN (devastated)\nI just lost everything.",
      "variation_index" : 1
    },
    {
      "notes" : "Nuanced reaction emphasizing shock.",
      "script" : "INT. OFFICE - DAY\nJOHN (stunned silence, then quiet disbelief)\nI... I just lost everything.",
      "variation_index" : 2
    },
    {
      "notes" : "Visceral physical beat preserving exact scene duration.",
      "script" : "INT. OFFICE - DAY\nJOHN (hands shaking, voice breaking)\nIt's all gone. Everything.",
      "variation_index" : 3
    }
  ]
}
```

### Version 1.1.0

**Role:** You are a script refiner responsible for diagnosing and correcting narrative, dialogue, character, spatial, action and full prop lifecycle continuity so scripts describe believable people and can be generated consistently as video. Automatically audit every script point, shot and subscene, preserve established people and props until an explained change occurs, maintain physically coherent possession, locations and actions, and refine authentic speech and visual descriptors without extending the original scene duration.

**Constraints:**
- Required fields: detected_issues, refined_scripts
- Strict schema: additional properties are not permitted.
- Required fields: script
- Strict schema: additional properties are not permitted.

#### Instructions

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


#### Input JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "examples" : [
    {
      "correction_focus" : [
        "text_correction",
        "emotion_detection",
        "location_continuity"
      ],
      "issues_found" : [
        {
          "category" : "emotion_inconsistency",
          "description" : "John is laughing while stating he lost everything."
        }
      ],
      "output_count" : 3,
      "script" : "INT. OFFICE - DAY\nJOHN (laughing happily)\nI just lost everything.\nEXT. BEACH - NIGHT\nMARY (whispering)\nWhy did we move here so suddenly?"
    },
    {
      "correction_focus" : [
        "prop_continuity",
        "character_continuity",
        "spatial_continuity",
        "action_continuity"
      ],
      "output_count" : 1,
      "script" : "INT. WORKSHOP - DAY\n1. MAYA, in a blue jacket, holds a brass key in her left hand beside the desk.\n2. Close-up: Maya now wears a red jacket and holds a silver key in her right hand by the door.\n3. The key vanishes; she opens the desk lock using it without returning to the desk."
    }
  ],
  "properties" : {
    "correction_focus" : {
      "description" : "Optional subset of issue types to prioritize during refinement.",
      "items" : {
        "enum" : [
          "text_correction",
          "emotion_detection",
          "speech_sequence",
          "location_continuity",
          "camera_continuity",
          "character_voice",
          "timing_preservation",
          "character_continuity",
          "prop_continuity",
          "spatial_continuity",
          "action_continuity"
        ],
        "type" : "string"
      },
      "type" : "array"
    },
    "issues_found" : {
      "description" : "Optional list of user-specified issues already known or identified in the script.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "category" : {
            "enum" : [
              "emotion_inconsistency",
              "dialogue_sequence",
              "location_sequence",
              "camera_movement",
              "character_role_mismatch",
              "location_mismatch",
              "pacing_timing",
              "character_continuity",
              "prop_continuity",
              "spatial_continuity",
              "action_continuity"
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
      "description" : "Number of refined script variations to generate. Defaults to 3.",
      "maximum" : 5,
      "minimum" : 1,
      "type" : "integer"
    },
    "script" : {
      "description" : "Original script with scenes, script points and subscenes. All continuity checks run automatically, even without supplied issues or correction_focus.",
      "type" : "string"
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
          "category" : "emotion_inconsistency",
          "correction_applied" : "Replaced laughing with somber pacing.",
          "description" : "John laughs unnaturally during grave news."
        }
      ],
      "refined_scripts" : [
        {
          "notes" : "Direct emotional correction maintaining original word count.",
          "script" : "INT. OFFICE - DAY\nJOHN (devastated)\nI just lost everything.",
          "variation_index" : 1
        },
        {
          "notes" : "Nuanced reaction emphasizing shock.",
          "script" : "INT. OFFICE - DAY\nJOHN (stunned silence, then quiet disbelief)\nI... I just lost everything.",
          "variation_index" : 2
        },
        {
          "notes" : "Visceral physical beat preserving exact scene duration.",
          "script" : "INT. OFFICE - DAY\nJOHN (hands shaking, voice breaking)\nIt's all gone. Everything.",
          "variation_index" : 3
        }
      ]
    },
    {
      "detected_issues" : [
        {
          "category" : "prop_continuity",
          "correction_applied" : "Keep the same brass key in her left hand throughout all three points, and explicitly bring it to the desk lock when used.",
          "description" : "Point 1 establishes a brass key in Maya’s left hand; point 2 replaces it with a silver key in her right hand without a transfer, and point 3 makes it disappear before reuse."
        },
        {
          "category" : "character_continuity",
          "correction_applied" : "Keep Maya’s blue jacket and identity unchanged across every point.",
          "description" : "Maya’s blue jacket becomes red between points 1 and 2 with no wardrobe change."
        },
        {
          "category" : "spatial_continuity",
          "correction_applied" : "Keep her beside the desk in all three points.",
          "description" : "Maya shifts from the desk to the door without movement, then opens the desk lock without returning."
        },
        {
          "category" : "action_continuity",
          "correction_applied" : "Maintain possession and show her inserting the held key into the reachable desk lock.",
          "description" : "Point 3 uses the key after it disappears, skipping the possession and reachable-lock prerequisites."
        }
      ],
      "refined_scripts" : [
        {
          "notes" : "Preserves cast, wardrobe, prop identity, possession and blocking while making the key’s introduction, use and resulting location explicit.",
          "script" : "INT. WORKSHOP - DAY\nContinuity: MAYA wears the same blue jacket throughout; one brass key, held in her left hand; she remains beside the desk.\n1. Maya holds the brass key in her left hand beside the locked desk.\n2. Close-up: the same brass key stays in her left hand; her blue jacket is unchanged.\n3. Still beside the desk, Maya inserts that key with her left hand into the desk lock and turns it. The key remains in the lock.",
          "variation_index" : 1
        }
      ]
    }
  ],
  "properties" : {
    "detected_issues" : {
      "description" : "Comprehensive list of issues detected and diagnosed in the script.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "category" : {
            "enum" : [
              "emotion_inconsistency",
              "dialogue_sequence",
              "location_sequence",
              "camera_movement",
              "character_role_mismatch",
              "location_mismatch",
              "pacing_timing",
              "character_continuity",
              "prop_continuity",
              "spatial_continuity",
              "action_continuity"
            ],
            "type" : "string"
          },
          "correction_applied" : {
            "description" : "Summary of how this issue was resolved across the refined scripts.",
            "type" : "string"
          },
          "description" : {
            "description" : "Concrete conflicting or missing source script points/subscenes, including lifecycle and continuity contradictions.",
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
      "description" : "Array of refined script variations correcting identified issues.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "notes" : {
            "description" : "Specific focus or subtle tonal direction of this variation.",
            "type" : "string"
          },
          "script" : {
            "description" : "Refined script with stable scene-level cast/prop setup and consistent lifecycle, position and action cues at every script point/subscene.",
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
          "notes"
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
  "correction_focus" : [
    "text_correction",
    "emotion_detection",
    "location_continuity"
  ],
  "issues_found" : [
    {
      "category" : "emotion_inconsistency",
      "description" : "John is laughing while stating he lost everything."
    }
  ],
  "output_count" : 3,
  "script" : "INT. OFFICE - DAY\nJOHN (laughing happily)\nI just lost everything.\nEXT. BEACH - NIGHT\nMARY (whispering)\nWhy did we move here so suddenly?"
}
```

#### Example Output (Illustrative Only)

```json
{
  "detected_issues" : [
    {
      "category" : "emotion_inconsistency",
      "correction_applied" : "Replaced laughing with somber pacing.",
      "description" : "John laughs unnaturally during grave news."
    }
  ],
  "refined_scripts" : [
    {
      "notes" : "Direct emotional correction maintaining original word count.",
      "script" : "INT. OFFICE - DAY\nJOHN (devastated)\nI just lost everything.",
      "variation_index" : 1
    },
    {
      "notes" : "Nuanced reaction emphasizing shock.",
      "script" : "INT. OFFICE - DAY\nJOHN (stunned silence, then quiet disbelief)\nI... I just lost everything.",
      "variation_index" : 2
    },
    {
      "notes" : "Visceral physical beat preserving exact scene duration.",
      "script" : "INT. OFFICE - DAY\nJOHN (hands shaking, voice breaking)\nIt's all gone. Everything.",
      "variation_index" : 3
    }
  ]
}
```
