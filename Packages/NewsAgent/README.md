# NewsAgent

A lightweight, focused Swift package containing news agents conforming to `AgentAtom` specifications.

## Dependencies

- `AgentAtom` (local Swift Package)
- Apple libraries (`Foundation`)
- **No other dependencies**

## Features

### ShekharJokeGenerator

A Hindi comedy news satirist and joke curator inspired by Shekhar Suman's iconic delivery, sharp observations, and relatable everyday humor.

- Evaluates verified fresh Indian news based on configurable parameters:
  - `output_count`: number of winning story joke packages in output array (default: 1).
  - `news_count`: number of stories to research/input (default: 3).
  - `jokes_per_category`: number of joke variations evaluated per category (default: 2).
- Generates dual joke versions for each story:
  - Short joke: maximum 30 words in Devanagari Hindi.
  - Long joke: maximum 60 words in Devanagari Hindi.
- Formats structured outputs ready for display or broadcast.

### Models & Specifications

- `ShekharJokeGeneratorInput`: Input payload with `output_count`, `news_count`, and `jokes_per_category`.
- `ShekharJokeItem`: Individual winning joke package (headline, date, link, category, joke1, joke2, script).
- `ShekharJokeGeneratorOutput`: Structured output payload containing an `items` array of `ShekharJokeItem`.
- `ShekharJokeGeneratorSpec`: Conforms to `AgentAtom.ModelledSpec`, providing typed input and schema-derived output.

## Usage

```swift
import AgentAtom
import NewsAgent

let spec = ShekharJokeGeneratorSpec(
    input: ShekharJokeGeneratorInput(outputCount: 1, newsCount: 3, jokesPerCategory: 2)
)

// Run with any AgentAtom session (e.g. AppleIntelligenceSession)
if #available(macOS 26, iOS 26, *) {
    guard let session = AppleIntelligenceSession() else { return }
    let operation = FailableAgenticOperation(spec: spec, session: session)
    let result = await operation.execute()
    switch result {
    case .success(let json):
        let output = try JSONDecoder().decode(ShekharJokeGeneratorOutput.self, from: Data(json.utf8))
        if let first = output.items.first {
            print(first.joke1)
        }
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

## Testing

```bash
swift test --package-path Packages/NewsAgent
```
