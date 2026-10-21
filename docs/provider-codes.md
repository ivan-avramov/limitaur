# Provider codes

Two-letter codes shown above the window code in the status item. The table is `providerCodes` in `Sources/LimitaurCore/WindowCode.swift`; the test `providerCodesAreDistinguishable` enforces the rule for every pair, so a new entry that collides fails the build's tests.

Rule: letters that look alike in a small bold sans face form a class: {C G O Q D 0 6}, {I L J T 1}, {E F}, {M N W}, {B R P 8 3 9}, {U V Y}, {K X}, {S 5}, {Z 2}, {A 4}, {H}. Two codes are distinguishable when at least one position holds letters from different classes; a character outside every class is its own class. Table entries must use classified letters. Only Claude and Codex have adapters today; the rest reserve codes so that future providers never collide with existing ones.

| Provider | Code | Note |
|---|---|---|
| Claude (Anthropic) | CL | |
| Codex / ChatGPT (OpenAI) | CX | |
| Gemini (Google) | GM | G and C share a class; M versus L separates it from CL |
| Cursor | CU | |
| GitHub Copilot | GH | |
| Grok (xAI) | XA | GK would collide with CX |
| Mistral | MS | |
| Perplexity | PX | |
| DeepSeek | DS | |
| Meta AI | MA | |
| Microsoft Copilot | MC | |
| Cohere | CE | CH would collide with GH |
| Windsurf | WI | WD would collide with MC, WS with MS |
| Replit | RP | |
| Amazon Q / Bedrock | AQ | |
| Hugging Face | HF | |
| Together | TG | |
| Groq | GQ | |
| OpenRouter | OR | |
| Kimi (Moonshot) | KM | |
| Qwen (Alibaba) | AL | QW would collide with GM |
| Fireworks | FW | |

Unknown provider IDs fall back to their first two uppercase letters. A fallback that is not distinguishable from a reserved code degrades to its first letter plus `?` (for example `chatgpt` → `C?`, since CH collides with GH).
