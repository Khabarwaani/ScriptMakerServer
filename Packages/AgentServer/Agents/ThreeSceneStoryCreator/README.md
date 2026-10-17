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

### Version 1.0.0

**Role:** You are ThreeSceneStoryCreator, an expert viral news screenwriter and creative director specializing in high-retention 3-scene short-form video scripts following the Khabarwaani Blueprint: Curiosity -> Continuity Discussion -> Shareable Reaction.

**Constraints:**
- Required fields: items
- Strict schema: additional properties are not permitted.
- Required fields: news
- Strict schema: additional properties are not permitted.

#### Instructions

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
          "scene_1" : {
            "additionalProperties" : false,
            "properties" : {
              "characters" : {
                "description" : "Character name(s) or persona(s) appearing in this scene.",
                "type" : "string"
              },
              "joke_applied" : {
                "description" : "Optional field showing the joke applied.",
                "type" : "string"
              },
              "purpose" : {
                "description" : "Purpose/Focus of the scene.",
                "type" : "string"
              },
              "setting" : {
                "description" : "Setting/Environment where this scene occurs.",
                "type" : "string"
              },
              "speech" : {
                "description" : "Spoken dialogue in natural running spoken flow (strictly 20 to 35 words).",
                "type" : "string"
              },
              "speech_word_count" : {
                "description" : "Exact word count of speech.",
                "type" : "integer"
              }
            },
            "required" : [
              "purpose",
              "characters",
              "setting",
              "speech",
              "speech_word_count"
            ],
            "title" : "ThreeSceneItem",
            "type" : "object"
          },
          "scene_2" : {
            "additionalProperties" : false,
            "properties" : {
              "characters" : {
                "description" : "Character name(s) or persona(s) appearing in this scene.",
                "type" : "string"
              },
              "joke_applied" : {
                "description" : "Optional field showing the joke applied.",
                "type" : "string"
              },
              "purpose" : {
                "description" : "Purpose/Focus of the scene.",
                "type" : "string"
              },
              "setting" : {
                "description" : "Setting/Environment where this scene occurs.",
                "type" : "string"
              },
              "speech" : {
                "description" : "Spoken dialogue in natural running spoken flow (strictly 20 to 35 words).",
                "type" : "string"
              },
              "speech_word_count" : {
                "description" : "Exact word count of speech.",
                "type" : "integer"
              }
            },
            "required" : [
              "purpose",
              "characters",
              "setting",
              "speech",
              "speech_word_count"
            ],
            "title" : "ThreeSceneItem",
            "type" : "object"
          },
          "scene_3" : {
            "additionalProperties" : false,
            "properties" : {
              "characters" : {
                "description" : "Character name(s) or persona(s) appearing in this scene.",
                "type" : "string"
              },
              "joke_applied" : {
                "description" : "Optional field showing the joke applied (relevant for Scene 3).",
                "type" : "string"
              },
              "purpose" : {
                "description" : "Purpose/Focus of the scene.",
                "type" : "string"
              },
              "setting" : {
                "description" : "Setting/Environment where this scene occurs.",
                "type" : "string"
              },
              "speech" : {
                "description" : "Spoken dialogue in natural running spoken flow (strictly 20 to 35 words).",
                "type" : "string"
              },
              "speech_word_count" : {
                "description" : "Exact word count of speech.",
                "type" : "integer"
              }
            },
            "required" : [
              "purpose",
              "characters",
              "setting",
              "speech",
              "speech_word_count"
            ],
            "title" : "ThreeSceneItem",
            "type" : "object"
          },
          "title" : {
            "description" : "Catchy story title/headline.",
            "type" : "string"
          },
          "verification" : {
            "additionalProperties" : false,
            "properties" : {
              "different_concepts" : {
                "description" : "True if Scene 1, 2, and 3 each hold completely different concepts.",
                "type" : "boolean"
              },
              "freshness_maintained" : {
                "description" : "True if concept freshness and fresh faces are maintained across all three.",
                "type" : "boolean"
              },
              "notes" : {
                "description" : "Short summary of verification check.",
                "type" : "string"
              },
              "shareability_verified" : {
                "description" : "True if Scene 3 delivers strong fun/shareability.",
                "type" : "boolean"
              }
            },
            "required" : [
              "different_concepts",
              "freshness_maintained",
              "shareability_verified",
              "notes"
            ],
            "title" : "ThreeSceneVerification",
            "type" : "object"
          }
        },
        "required" : [
          "title",
          "scene_1",
          "scene_2",
          "scene_3",
          "verification"
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
