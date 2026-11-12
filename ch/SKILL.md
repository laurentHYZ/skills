---
name: ch
description: Answer the user's question or message in Chinese. Use when the user wants a Chinese-language response, explanation, or translation.
disable-model-invocation: true
argument-hint: [your question]
---

Answer the following in **Simplified Chinese**.

Rules:
- Write the full response in Chinese.
- For every technical term, domain-specific word, or proper noun, append its tonal pinyin (with tone marks, e.g. ā á ǎ à) and English translation in parentheses immediately after, like this:
  `钩子（gōu zi, hook）`
- Use natural, fluent Chinese — not word-for-word translation.
- Keep code blocks in the original language (do not translate code).
- If the question is in English, answer in Chinese. If already in Chinese, still apply the technical-term annotation rule.

$ARGUMENTS
