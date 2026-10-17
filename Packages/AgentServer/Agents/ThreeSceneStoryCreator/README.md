# ThreeSceneStoryCreator

Independent Swift package with provider-independent agent definitions.

Generated from the versioned resources. From the repository root, refresh with `swift run --package-path Packages/AgentServer AgentTools docs`; verify with `AgentTools docs --check`. Put authored notes in a version's `notes.md` rather than editing this generated file.

## Server integration

The server must link this Swift package, adapt it to `AgentPackageContract`, and explicitly register it in `AgentRegistry.registeredPackages`. Version resources are compiled and validated at build time. Rebuild the server after adding or changing declared versions; adding Markdown directories alone does not make an agent available.

Test this package from the repository root:

```sh
swift test --package-path Packages/AgentServer/Agents/ThreeSceneStoryCreator
```

## HTTP execution

`GET /agents` returns only agent IDs, display names and available versions. `POST /execute` returns one schema-validated JSON value or a structured error by default; `status=false` can be omitted. Use `POST /execute?status=true` for lifecycle/progress SSE and one validated final result. Raw provider text stays internal. Select this agent on `/help` or `/try`; those pages include the status checkbox and Copy controls. Full contracts are available from `/openapi.json`.

## Responsibility

You are ThreeSceneStoryCreator, an expert viral news screenwriter and creative director specializing in high-retention 3-scene short-form video scripts following the Khabarwaani Blueprint: Curiosity -> Continuity Discussion -> Shareable Reaction.

## Available Versions

### Version 2.0.0

**Role:** You are ThreeSceneStoryCreator, an expert viral news screenwriter and creative director specializing in high-retention 3-scene short-form video scripts following the Khabarwaani Blueprint: Curiosity -> Continuity Discussion -> Shareable Reaction.

**Constraints:**
- Required fields: items
- Strict schema: additional properties are not permitted.
- Required fields: news
- Strict schema: additional properties are not permitted.

#### Instructions

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


#### Input JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "examples" : [
    {
      "news" : "Traffic department issues flying car fines"
    },
    {
      "news" : "Traffic department issues flying car fines",
      "output_count" : 1,
      "user_joke" : "Ab to chalan hawa me katega"
    }
  ],
  "properties" : {
    "news" : {
      "description" : "Verified news details, headline, or article facts.",
      "type" : "string"
    },
    "output_count" : {
      "default" : 1,
      "description" : "Number of 3-scene story packages to generate. Defaults to 1.",
      "maximum" : 5,
      "minimum" : 1,
      "type" : "integer"
    },
    "user_joke" : {
      "description" : "Optional user-provided joke or humorous angle to incorporate into Scene 3.",
      "type" : "string"
    }
  },
  "required" : [
    "news"
  ],
  "title" : "ThreeSceneStoryCreatorInput",
  "type" : "object"
}
```

#### Output JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties" : false,
  "properties" : {
    "items" : {
      "description" : "Array of generated 3-scene story packages matching requested output_count.",
      "items" : {
        "additionalProperties" : false,
        "properties" : {
          "scenes" : {
            "description" : "Array of 3 Scene objects (Curiosity, News Discussion, Shareable Reaction).",
            "items" : {
              "additionalProperties" : false,
              "properties" : {
                "dialogues" : {
                  "description" : "List of natural reply-response dialogue turns between characters.",
                  "items" : {
                    "additionalProperties" : false,
                    "properties" : {
                      "dialogue" : {
                        "description" : "Spoken line in natural reply-response flow.",
                        "type" : "string"
                      },
                      "speaker" : {
                        "description" : "Name or persona of speaking character.",
                        "type" : "string"
                      }
                    },
                    "required" : [
                      "speaker",
                      "dialogue"
                    ],
                    "title" : "ThreeSceneDialogue",
                    "type" : "object"
                  },
                  "type" : "array"
                },
                "goal" : {
                  "description" : "Goal/Purpose of the scene (Curiosity / News Discussion / Shareable Reaction).",
                  "type" : "string"
                },
                "location" : {
                  "description" : "Setting or environment where this scene occurs.",
                  "type" : "string"
                },
                "title" : {
                  "description" : "Scene title.",
                  "type" : "string"
                },
                "verification" : {
                  "additionalProperties" : false,
                  "properties" : {
                    "dialogue_sensible" : {
                      "description" : "True if dialogue makes complete sense, is meaningful, and has natural reply-response flow.",
                      "type" : "boolean"
                    },
                    "different_concepts" : {
                      "description" : "True if this scene holds a distinct concept.",
                      "type" : "boolean"
                    },
                    "freshness_maintained" : {
                      "description" : "True if fresh faces, fresh setting, and no recycled setups are maintained.",
                      "type" : "boolean"
                    },
                    "notes" : {
                      "description" : "Short summary of verification check.",
                      "type" : "string"
                    },
                    "passed" : {
                      "description" : "True if all verification checks passed.",
                      "type" : "boolean"
                    }
                  },
                  "required" : [
                    "passed",
                    "dialogue_sensible",
                    "different_concepts",
                    "freshness_maintained",
                    "notes"
                  ],
                  "title" : "ThreeSceneVerification",
                  "type" : "object"
                },
                "words_count" : {
                  "description" : "Total count of spoken words across all dialogues, calculated last (strictly 20 to 35 words).",
                  "maximum" : 35,
                  "minimum" : 20,
                  "type" : "integer"
                }
              },
              "required" : [
                "title",
                "goal",
                "location",
                "verification",
                "dialogues",
                "words_count"
              ],
              "title" : "ThreeSceneItem",
              "type" : "object"
            },
            "maxItems" : 3,
            "minItems" : 3,
            "type" : "array"
          },
          "title" : {
            "description" : "Catchy story title/headline.",
            "type" : "string"
          }
        },
        "required" : [
          "title",
          "scenes"
        ],
        "title" : "ThreeSceneStoryPackage",
        "type" : "object"
      },
      "maxItems" : 5,
      "minItems" : 1,
      "type" : "array"
    }
  },
  "required" : [
    "items"
  ],
  "title" : "ThreeSceneStoryCreatorOutput",
  "type" : "object"
}
```

#### Example Input

```json
{
  "news" : "Traffic department issues flying car fines"
}
```
