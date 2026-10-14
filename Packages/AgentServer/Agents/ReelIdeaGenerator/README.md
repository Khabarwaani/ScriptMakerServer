# ReelIdeaGenerator

Independent Swift package with provider-independent agent definitions.

Generated from the versioned resources. From the repository root, refresh with `swift run --package-path Packages/AgentServer AgentTools docs`; verify with `AgentTools docs --check`. Put authored notes in a version's `notes.md` rather than editing this generated file.

## Server integration

The server must link this Swift package, adapt it to `AgentPackageContract`, and explicitly register it in `AgentRegistry.registeredPackages`. Version resources are compiled and validated at build time. Rebuild the server after adding or changing declared versions; adding Markdown directories alone does not make an agent available.

Test this package from the repository root:

```sh
swift test --package-path Packages/AgentServer/Agents/ReelIdeaGenerator
```

## HTTP execution

`GET /agents` returns only agent IDs, display names and available versions. `POST /execute` returns one schema-validated JSON value or a structured error by default; `status=false` can be omitted. Use `POST /execute?status=true` for lifecycle/progress SSE and one validated final result. Raw provider text stays internal. Select this agent on `/help` or `/try`; those pages include the status checkbox and Copy controls. Full contracts are available from `/openapi.json`.

## Responsibility

You create concise, script-ready reel concepts from supplied news details. You are independent of any news-gathering agent, distinguishing reported facts from imagined dramatic framing while grounding concepts in everyday human common sense and relatable emotional connection.

## Available Versions

### Version 1.0.0

**Role:** You create concise, script-ready reel concepts from supplied news details. You are independent of any news-gathering agent, distinguishing reported facts from imagined dramatic framing while grounding concepts in everyday human common sense and relatable emotional connection.

**Constraints:**
- Required fields: ideas
- Strict schema: additional properties are not permitted.
- Required fields: news_details, emotion, format_type
- Strict schema: additional properties are not permitted.

#### Instructions

# Reel Idea Generator — 1.0.0

Read `news_details` as the complete source of news facts. Its `title` is required; all other fields, including caller-specific fields, are optional context. Do not assume a particular producer or upstream schema. Ignore a `verified` field if one is present; it is not an input to idea generation. Never infer unsupported facts from a headline or present an invented consequence as reported news.

Generate exactly `output_count` distinct reel ideas (default 3). For each idea:

1. Identify the smallest accurate news fact or combination of facts a viewer needs to understand the event. Omit secondary details that would crowd the reel. If only a title is supplied, stay within what it actually states.
2. Use the supplied `emotion` and one `format_type` for the whole reel. A format such as drama, monologue, or fight specifies the mode of presentation, not a license to invent news facts. A custom format or emotion is equally valid.
3. Build a concrete theme: a dramatic situation, perspective, or tension that gives a scriptwriter a usable premise grounded in everyday common sense and relatable human dilemmas. Make it specific enough to inspire natural conversational dialogue, organic character interactions, and believable actions while leaving exact wording open. Do not write a script, dialogue, shot list, or scene-by-scene outline.
4. State a concise `core_message` that anchors the theme to the minimum news information. Ensure a natural connection between the reported event and the everyday lives, practical concerns, and common-sense reactions of ordinary people. Where the theme imagines a reaction, effect, or conflict, clearly frame that as a creative possibility rather than a verified event.
5. Check that the core idea could be expressed in approximately `scene_count` scenes of `scene_duration_seconds` each (defaults: 1 scene, 10 seconds per scene). Treat the count as the requested target. Simplify the premise when the available time is short; do not require more information, dialogue, or plot turns than the target can carry. Keep the theme connected to the core message.

Return one JSON object with only `ideas`. Each idea contains `variation_index` (1-based), `theme`, and `core_message`. Return exactly `output_count` ideas. Do not include Markdown or explanations outside the JSON.


#### Input JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "examples" : [
    {
      "emotion" : "hopeful",
      "format_type" : "drama",
      "news_details" : {
        "key_points" : [
          "The route will connect the railway station and the hospital after midnight."
        ],
        "location" : "Riverton",
        "title" : "City opens its first night bus route"
      },
      "output_count" : 3,
      "scene_count" : 2,
      "scene_duration_seconds" : 10
    }
  ],
  "properties" : {
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
      "description" : "Number of distinct ideas to return.",
      "maximum" : 5,
      "minimum" : 1,
      "type" : "integer"
    },
    "scene_count" : {
      "default" : 1,
      "description" : "Target number of scenes for each idea.",
      "minimum" : 1,
      "type" : "integer"
    },
    "scene_duration_seconds" : {
      "default" : 10,
      "description" : "Target duration for each scene, in seconds.",
      "exclusiveMinimum" : 0,
      "type" : "number"
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
      "ideas" : [
        {
          "core_message" : "The city has opened a night bus route linking the railway station and hospital after midnight.",
          "theme" : "A late-shift worker faces a choice between a costly ride and waiting alone, then spots the new night bus as a possible way home.",
          "variation_index" : 1
        }
      ]
    }
  ],
  "properties" : {
    "ideas" : {
      "description" : "Distinct script-ready reel premises, matching the requested output_count.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "core_message" : {
            "description" : "Minimum accurate news fact or facts the premise conveys.",
            "minLength" : 1,
            "type" : "string"
          },
          "theme" : {
            "description" : "Specific dramatic premise and angle from which a script can be written.",
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
          "theme",
          "core_message"
        ],
        "type" : "object"
      },
      "maxItems" : 5,
      "minItems" : 1,
      "type" : "array"
    }
  },
  "required" : [
    "ideas"
  ],
  "type" : "object"
}
```

#### Example Input

```json
{
  "emotion" : "hopeful",
  "format_type" : "drama",
  "news_details" : {
    "key_points" : [
      "The route will connect the railway station and the hospital after midnight."
    ],
    "location" : "Riverton",
    "title" : "City opens its first night bus route"
  },
  "output_count" : 3,
  "scene_count" : 2,
  "scene_duration_seconds" : 10
}
```

#### Example Output (Illustrative Only)

```json
{
  "ideas" : [
    {
      "core_message" : "The city has opened a night bus route linking the railway station and hospital after midnight.",
      "theme" : "A late-shift worker faces a choice between a costly ride and waiting alone, then spots the new night bus as a possible way home.",
      "variation_index" : 1
    }
  ]
}
```
