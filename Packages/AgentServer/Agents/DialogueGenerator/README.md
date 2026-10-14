# DialogueGenerator

Independent Swift package with provider-independent agent definitions.

Generated from the versioned resources. From the repository root, refresh with `swift run --package-path Packages/AgentServer AgentTools docs`; verify with `AgentTools docs --check`. Put authored notes in a version's `notes.md` rather than editing this generated file.

## Server integration

The server must link this Swift package, adapt it to `AgentPackageContract`, and explicitly register it in `AgentRegistry.registeredPackages`. Version resources are compiled and validated at build time. Rebuild the server after adding or changing declared versions; adding Markdown directories alone does not make an agent available.

Test this package from the repository root:

```sh
swift test --package-path Packages/AgentServer/Agents/DialogueGenerator
```

## HTTP execution

`GET /agents` returns only agent IDs, display names and available versions. `POST /execute` returns one schema-validated JSON value or a structured error by default; `status=false` can be omitted. Use `POST /execute?status=true` for lifecycle/progress SSE and one validated final result. Raw provider text stays internal. Select this agent on `/help` or `/try`; those pages include the status checkbox and Copy controls. Full contracts are available from `/openapi.json`.

## Responsibility

You generate script variations with spoken dialogue and scene timings from supplied news details and optional upstream ideas. You are independent of any idea generator or news-gathering agent, anchoring dramatic scenes in verified news facts while ensuring authentic conversational flow, natural connective tissue between speakers, and grounded common-sense human reactions.

## Available Versions

### Version 1.0.0

**Role:** You generate script variations with spoken dialogue and scene timings from supplied news details and optional upstream ideas. You are independent of any idea generator or news-gathering agent, anchoring dramatic scenes in verified news facts while ensuring authentic conversational flow, natural connective tissue between speakers, and grounded common-sense human reactions.

**Constraints:**
- Required fields: scripts
- Strict schema: additional properties are not permitted.
- Required fields: news_details, emotion, format_type
- Strict schema: additional properties are not permitted.

#### Instructions

# Dialogue Generator — 1.0.0

Read `news_details` as the authoritative source of news facts. Its `title` is required; all other fields (`summary`, `key_points`, `people`, `location`, and any caller-specific context) are optional context. Do not assume a specific upstream producer or pipeline. Distinguish reported facts from dramatic staging and never invent unsupported consequences as reported facts.

If an idea is supplied—via `idea` (an object with `theme` and optional `core_message`), `ideas` (an array of upstream ideas), or top-level `theme` and `core_message`—incorporate its dramatic premise and core message into the dialogue and scenes. If multiple ideas are provided, use them across variations or develop the primary premise. If no idea is supplied, develop natural dramatic premises directly from the news event and requested emotion and format.

Generate exactly `output_count` distinct script variations (default 3). For each variation:

1. **Scene and Narrative Structure with Natural Connection**:
   - Target approximately `scene_count` scenes of `scene_duration_seconds` each (defaults: 1 scene, 10 seconds per scene). Set scenes using standard script headings (e.g. `INT. BUS STOP - NIGHT`, `EXT. STREET - DAY`) with clear character presence and concise action cues.
   - Ensure narrative continuity: transitions between scenes must feel naturally connected through cause, effect, and emotional momentum. What happens in Scene 1 must directly inform the starting state, mood, and stakes of Scene 2.

2. **Dialogue Crafting, Natural Connection & Conversational Connective Tissue**:
   - Write natural, emotionally resonant dialogue matching the requested `emotion` (e.g. urgent, curious, hopeful, somber, tense, humorous) and `format_type` (e.g. drama, monologue, fight, dialogue, satire, explainer).
   - **Organic Connective Tissue**: Dialogue must never consist of disconnected statements or parallel monologues. Each line must be an organic, direct reaction to the preceding turn—acknowledging, questioning, agreeing, pushing back, or emotionally reciprocating.
   - **Natural Conversational Bridges**: Use authentic discourse markers, pauses, hesitations, and colloquial bridges (e.g. "Wait,", "Look,", "Are you serious?", "Hold on,", "I get that, but...") suited to the language and characters.
   - Ground the conversation in essential news facts organically through human dialogue so a viewer understands the event through relatable human stakes rather than heavy, artificial exposition.

3. **Common Sense & Real-World Plausibility**:
   - Ground all character actions, choices, and dialogue in everyday human common sense.
   - When reacting to news events or unexpected situations, characters must react like authentic human beings:
     - Expressing relatable human skepticism, practical concerns (e.g. daily commute, expenses, family, safety, convenience), or genuine emotional reactions.
     - Asking the obvious questions that any viewer with common sense would immediately ask.
     - Never act like detached automatons who unquestioningly accept absurd premises or fail to notice the obvious reality in front of them ("the elephant in the room").
   - Ensure situational plausibility: speaking volume, physical actions, and social dynamics must make common sense within the chosen setting and relationships.

4. **Pacing and Timing**:
   - Spoken dialogue must fit comfortably within the target scene duration according to `wps_range` (default 2.5–3.5 words per second). For each scene, calculate:
     - `dialogue_duration_seconds`: Spoken dialogue duration estimated from dialogue word count and the target WPS.
     - `non_dialogue_duration_seconds`: Time allocated to scene setup, actions, character reactions, beats, or transitions.
     - `total_duration_seconds`: Combined duration (`dialogue_duration_seconds` + `non_dialogue_duration_seconds`), fitting within `scene_duration_seconds`.

5. **Notes**:
   - Provide concise notes explaining the dramatic angle, character dynamics, connection to the news facts or incorporated idea, common-sense human stakes, and pacing choices.

Return one JSON object with only `scripts`. Each variation contains `variation_index` (1-based), `script`, `notes`, and `scene_timings`. Return exactly `output_count` variations. Do not include Markdown fences or explanations outside the JSON response.



#### Input JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "examples" : [
    {
      "emotion" : "hopeful",
      "format_type" : "drama",
      "idea" : {
        "core_message" : "The city has opened a night bus route linking the railway station and hospital after midnight.",
        "theme" : "A late-shift worker faces a choice between a costly ride and waiting alone, then spots the new night bus as a possible way home."
      },
      "news_details" : {
        "key_points" : [
          "The route will connect the railway station and the hospital after midnight."
        ],
        "location" : "Riverton",
        "title" : "City opens its first night bus route"
      },
      "output_count" : 3,
      "scene_count" : 1,
      "scene_duration_seconds" : 10,
      "wps_range" : {
        "max" : 3.5,
        "min" : 2.5
      }
    },
    {
      "emotion" : "curious",
      "format_type" : "dialogue",
      "news_details" : {
        "summary" : "Telescope data shows spectral signatures of water vapor in the atmosphere of habitable-zone planet K2-18b.",
        "title" : "Astronomers discover water vapor on distant exoplanet"
      },
      "output_count" : 1,
      "scene_count" : 1,
      "scene_duration_seconds" : 10
    }
  ],
  "properties" : {
    "core_message" : {
      "description" : "Optional top-level minimum news message to convey.",
      "type" : "string"
    },
    "emotion" : {
      "description" : "Desired emotional tone. Choose a suggestion or enter a custom value.",
      "examples" : [
        "urgent",
        "curious",
        "hopeful",
        "somber",
        "tense",
        "humorous"
      ],
      "minLength" : 1,
      "type" : "string"
    },
    "format_type" : {
      "description" : "One presentation format for the entire reel. Choose a suggestion or enter a custom value.",
      "examples" : [
        "drama",
        "monologue",
        "fight",
        "dialogue",
        "satire",
        "explainer"
      ],
      "minLength" : 1,
      "type" : "string"
    },
    "idea" : {
      "additionalProperties" : true,
      "description" : "Optional upstream reel idea or premise to incorporate into the dialogue.",
      "properties" : {
        "core_message" : {
          "description" : "Minimum accurate news fact or core message conveyed.",
          "type" : "string"
        },
        "theme" : {
          "description" : "Dramatic premise and angle for the script.",
          "type" : "string"
        }
      },
      "type" : "object"
    },
    "ideas" : {
      "description" : "Optional array of upstream reel ideas from which premises can be drawn.",
      "items" : {
        "additionalProperties" : true,
        "properties" : {
          "core_message" : {
            "type" : "string"
          },
          "theme" : {
            "type" : "string"
          },
          "variation_index" : {
            "type" : "integer"
          }
        },
        "type" : "object"
      },
      "type" : "array"
    },
    "news_details" : {
      "additionalProperties" : true,
      "description" : "News JSON from any caller. Only title is required; other fields and additional context are welcome.",
      "properties" : {
        "key_points" : {
          "description" : "Optional supporting facts.",
          "items" : {
            "type" : "string"
          },
          "type" : "array"
        },
        "location" : {
          "description" : "Optional place or structured location.",
          "type" : [
            "string",
            "object"
          ]
        },
        "people" : {
          "description" : "Optional people relevant to the news.",
          "items" : {
            "type" : "string"
          },
          "type" : "array"
        },
        "summary" : {
          "description" : "Optional account of the event.",
          "type" : "string"
        },
        "title" : {
          "description" : "News title or headline.",
          "minLength" : 1,
          "type" : "string"
        }
      },
      "required" : [
        "title"
      ],
      "type" : "object"
    },
    "output_count" : {
      "default" : 3,
      "description" : "Number of distinct script variations to return.",
      "maximum" : 5,
      "minimum" : 1,
      "type" : "integer"
    },
    "scene_count" : {
      "default" : 1,
      "description" : "Target number of scenes for each script variation.",
      "minimum" : 1,
      "type" : "integer"
    },
    "scene_duration_seconds" : {
      "default" : 10,
      "description" : "Target duration for each scene, in seconds.",
      "exclusiveMinimum" : 0,
      "type" : "number"
    },
    "theme" : {
      "description" : "Optional top-level dramatic premise and angle for the script.",
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
    "news_details",
    "emotion",
    "format_type"
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
      "scripts" : [
        {
          "notes" : "Drama format conveying the new night bus route connecting the station and hospital, with personal stakes.",
          "scene_timings" : [
            {
              "dialogue_duration_seconds" : 6.5,
              "non_dialogue_duration_seconds" : 3.5,
              "scene_number" : 1,
              "total_duration_seconds" : 10
            }
          ],
          "script" : "INT. BUS STOP - NIGHT\nPRIYA shivers under the street lamp, checking her watch.\nPRIYA\nLast cab cancelled. It's past midnight.\nA clean night bus pulls up and the doors hiss open.\nBUS DRIVER\nStation and hospital route running all night now. Step on in.\nPRIYA (relieved)\nFirst night route? You saved my shift.",
          "variation_index" : 1
        }
      ]
    }
  ],
  "properties" : {
    "scripts" : {
      "description" : "Distinct generated script variations matching the requested output_count.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "notes" : {
            "description" : "Creative approach, premise framing, character dynamics, and pacing rationale.",
            "minLength" : 1,
            "type" : "string"
          },
          "scene_timings" : {
            "description" : "Scene timing breakdowns divided into dialogue and non-dialogue timings fitting within scene_duration_seconds.",
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
            "description" : "Complete script formatted with scene headings, character names, spoken dialogue lines, and action/speech cues.",
            "minLength" : 1,
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
    "scripts"
  ],
  "type" : "object"
}
```

#### Example Input

```json
{
  "emotion" : "hopeful",
  "format_type" : "drama",
  "idea" : {
    "core_message" : "The city has opened a night bus route linking the railway station and hospital after midnight.",
    "theme" : "A late-shift worker faces a choice between a costly ride and waiting alone, then spots the new night bus as a possible way home."
  },
  "news_details" : {
    "key_points" : [
      "The route will connect the railway station and the hospital after midnight."
    ],
    "location" : "Riverton",
    "title" : "City opens its first night bus route"
  },
  "output_count" : 3,
  "scene_count" : 1,
  "scene_duration_seconds" : 10,
  "wps_range" : {
    "max" : 3.5,
    "min" : 2.5
  }
}
```

#### Example Output (Illustrative Only)

```json
{
  "scripts" : [
    {
      "notes" : "Drama format conveying the new night bus route connecting the station and hospital, with personal stakes.",
      "scene_timings" : [
        {
          "dialogue_duration_seconds" : 6.5,
          "non_dialogue_duration_seconds" : 3.5,
          "scene_number" : 1,
          "total_duration_seconds" : 10
        }
      ],
      "script" : "INT. BUS STOP - NIGHT\nPRIYA shivers under the street lamp, checking her watch.\nPRIYA\nLast cab cancelled. It's past midnight.\nA clean night bus pulls up and the doors hiss open.\nBUS DRIVER\nStation and hospital route running all night now. Step on in.\nPRIYA (relieved)\nFirst night route? You saved my shift.",
      "variation_index" : 1
    }
  ]
}
```
