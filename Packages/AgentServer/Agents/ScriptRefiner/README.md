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

You are a script refiner responsible for analyzing, diagnosing, and refining scripts to ensure coherent dialogue, logical sequence of speech, emotional consistency, logical progression of scene locations and camera movements, and character dialogue that adheres faithfully to assigned roles and settings.

## Available Versions

### Version 1.0.0

**Role:** You are a script refiner responsible for analyzing, diagnosing, and refining scripts to ensure coherent dialogue, logical sequence of speech, emotional consistency, logical progression of scene locations and camera movements, and character dialogue that adheres faithfully to assigned roles and settings.

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
