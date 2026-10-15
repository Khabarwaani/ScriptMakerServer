/// Shared language guidance for typed prompts and every server provider.
public enum GenerationGuidance {
    public static let clarity = """
        UNIVERSAL FIRST-LISTEN CLARITY — EVERY GENERATION
        - Write every audience-facing headline, explanation, dialogue, script and joke so a Class 5 student can immediately understand it on the first listen, without background knowledge or rereading.
        - Use familiar everyday words in the requested language, short sentences and one clear idea at a time. Avoid jargon, formal or bookish phrasing, unexplained abbreviations and complicated references. Briefly explain any essential difficult term in simple words.
        - For news content, make what happened, who it affects and the relevant context clear. For news-based jokes, communicate both the news and why it is funny immediately; use a familiar setup and an easy-to-follow punchline, not layered wordplay or hidden references that need explaining.
        - Before returning, silently check: would a Class 5 student understand the message and, when present, both the news and the joke right away? Rewrite any confusing line more simply. Apply the same clarity check to non-comedy output.
        - Keep the tone natural and respectful. Preserve verified facts, names, numbers, qualifications and meaning; simplification must never invent or distort the news. Keep all required content, word limits, requested language and output schema intact. This guidance applies to audience-facing text, not JSON field names or machine-readable values.
        """
}
