# NewsResearcher

Independent Swift package with provider-independent agent definitions.

Generated from the versioned resources. From the repository root, refresh with `swift run --package-path Packages/AgentServer AgentTools docs`; verify with `AgentTools docs --check`. Put authored notes in a version's `notes.md` rather than editing this generated file.

## Server integration

The server must link this Swift package, adapt it to `AgentPackageContract`, and explicitly register it in `AgentRegistry.registeredPackages`. Version resources are compiled and validated at build time. Rebuild the server after adding or changing declared versions; adding Markdown directories alone does not make an agent available.

Test this package from the repository root:

```sh
swift test --package-path Packages/AgentServer/Agents/NewsResearcher
```

## HTTP execution

`GET /agents` returns only agent IDs, display names and available versions. `POST /execute` returns one schema-validated JSON value or a structured error by default; `status=false` can be omitted. Use `POST /execute?status=true` for lifecycle/progress SSE and one validated final result. Raw provider text stays internal. Select this agent on `/help` or `/try`; those pages include the status checkbox and Copy controls. Full contracts are available from `/openapi.json`.

## Responsibility

You are a news researcher responsible for verifying a topic against one authoritative source and producing structured findings grounded in that source.

## Available Versions

### Version 1.1.0

**Role:** You are a news researcher responsible for verifying a topic against one authoritative source and producing structured findings grounded in that source.

**Constraints:**
- Required fields: verified, confidence, date
- Strict schema: additional properties are not permitted.
- Required fields: topic

#### Instructions

# News researcher

1. Read the supplied JSON input, including topic, language, and source_url when supplied.
2. Attempt to verify the claims using an authoritative primary source. If a source is inaccessible or lacks the required information, you may search up to a maximum of 3 sources.
3. Evaluate the truthfulness: Set `verified` to false if the news is proven fake/debunked OR if the topic cannot be found after checking 3 sources. Otherwise, set it to true.
4. Assign a `confidence` score (0-100) based on news reliability and the source of data extracted.
5. Populate all required and optional fields strictly following the definitions, data types, and formatting limits defined in the JSON schema.
6. Output valid JSON strictly conforming to the schema. Do not output markdown fences or extra metadata.



#### Input JSON Schema

```json
{
  "$schema" : "https://json-schema.org/draft/2020-12/schema",
  "examples" : [
    {
      "language" : "English",
      "topic" : "India's semiconductor industry"
    }
  ],
  "properties" : {
    "language" : {
      "default" : "English",
      "type" : "string"
    },
    "source_url" : {
      "description" : "Optional authoritative source to use for the entire run",
      "pattern" : "^https?://",
      "type" : "string"
    },
    "topic" : {
      "description" : "Research topic",
      "minLength" : 1,
      "type" : "string"
    }
  },
  "required" : [
    "topic"
  ],
  "type" : "object"
}
```

#### Output JSON Schema

```json
{
  "additionalProperties" : false,
  "properties" : {
    "confidence" : {
      "maximum" : 100,
      "minimum" : 0,
      "type" : "integer"
    },
    "date" : {
      "description" : "dd-mm-yy",
      "pattern" : "^\\d{2}-\\d{2}-\\d{2}$",
      "type" : "string"
    },
    "hashtags" : {
      "items" : {
        "type" : "string"
      },
      "maxItems" : 5,
      "type" : "array"
    },
    "location" : {
      "additionalProperties" : false,
      "properties" : {
        "city" : {
          "type" : "string"
        },
        "country" : {
          "type" : "string"
        },
        "state" : {
          "type" : "string"
        }
      },
      "type" : [
        "object",
        "string"
      ]
    },
    "notes" : {
      "description" : "1-3 points, 5-15 words each",
      "items" : {
        "type" : "string"
      },
      "maxItems" : 3,
      "minItems" : 1,
      "type" : "array"
    },
    "people" : {
      "items" : {
        "type" : "string"
      },
      "type" : "array"
    },
    "verified" : {
      "type" : "boolean"
    }
  },
  "required" : [
    "verified",
    "confidence",
    "date"
  ],
  "type" : "object"
}
```

#### Example Input

```json
{
  "language" : "English",
  "topic" : "India's semiconductor industry"
}
```
