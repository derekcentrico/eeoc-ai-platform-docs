---
name: human-tone
description: >
  AI-language detection and removal patterns for EEOC platform prose. Covers
  comments, docstrings, markdown docs, HTML templates. Read before any docs
  audit or tone review. Referenced by post-impl-verifier Pass 2.
---

# Human Tone — AI-Language Audit

All prose in this platform must read as if written by a senior federal
developer, not by a language model. This skill defines what to detect, what
to replace, and what to leave alone.

---

## Banned Terms (always replace)

| AI tell | Replacement |
|---|---|
| leverage / leveraging | use |
| utilize / utilizing | use |
| streamline / streamlined | simplify |
| robust | reliable / solid |
| comprehensive | full / complete |
| cutting-edge | (drop or name the tech) |
| seamless / seamlessly | (drop or describe what happens) |
| empower / empowering | enable |
| innovative / innovation | (drop or describe the feature) |
| revolutionize | (drop) |
| purpose-built | built for |
| best-in-class | (drop) |
| state-of-the-art | (drop or name the tech) |
| world-class | (drop) |
| delve / delving | (drop) |
| tapestry | (drop) |
| paradigm | pattern / approach |
| synergy | (drop or describe the interaction) |
| holistic | full / end-to-end |
| pivotal | key / critical |
| multifaceted | (drop or list the facets) |
| nuanced | (drop or describe the nuance) |
| realm | area / domain |
| cornerstone | foundation / core |
| foster / fostering | support / encourage |
| harness / harnessing | use |
| spearhead | lead |
| testament | shows / proves |
| encompasses | includes / covers |
| embark | start / begin |
| unravel | debug / investigate |
| landscape (metaphorical) | area / space |

### Medium-priority (flag in prose, leave in code identifiers)

`designed to`, `crafted to`, `built to`, `aimed at`, `tailored for`,
`ensure/ensures/ensuring` (in docs — leave `_ensure_init`-style names),
`facilitate` (unless describing mediation), `enhance/enhanced`,
`optimal/optimize`, `scalable/scalability`, `production-ready` (in prose)

---

## Structural Tells (rewrite)

### Sentence starters to eliminate
- `It is important to note` → drop or rephrase
- `It's worth noting` → drop or rephrase
- `Notably` → drop or integrate
- `Furthermore,` / `Moreover,` / `Additionally,` as sentence openers → restructure
- `In order to` → `to`

### Indirect voice patterns
- `At its core` → be specific
- `This allows for` → `allows` or specify the action
- `plays a crucial role` → describe what it does
- `a wide range of` / `a variety of` → `various` or list them
- `with respect to` → `for`
- `in the context of` → `in` or `when`
- `in terms of` → state it directly

### The "Noun provides/implements/handles" pattern
Bad: "The configuration system implements key settings..."
Good: "Settings are configured via..." or "Configure settings like..."

### The "Noun is designed to" pattern
Bad: "This module is designed to capture metrics..."
Good: "Captures metrics..." or "This module captures metrics."

---

## Markdown Tells

- **Kill conclusion sections.** Remove `Conclusion`, `Summary`, `Next Steps`
  headers at the bottom of docs. Developers don't write concluding paragraphs.
- **Reduce bolding.** Bold is for headings and inline code terms, not emphasis.
- **Flatten short lists.** Two-item bullet lists → comma-separated sentence.
- **Remove preamble/postamble.** Drop `This section outlines...`,
  `As mentioned above...`, `The following describes...`.

---

## Docstring Rules

- Start with an **imperative verb**, not "This function/class..."
- Keep it to one line if the purpose is obvious from the name + type hints
- Do not explain parameters whose names are self-documenting
- Bad: `"""This function validates that the provided email is valid."""`
- Good: `"""Validate email format."""`

---

## Comment Rules

- **Delete obvious comments** that just translate code to English
- **Focus on "why"**, not "what": `# cap at 500 to avoid memory spikes on large dockets`
- **Allow developer shorthand**: params, config, repo, util, auth, perf
- **Don't force punctuation** on brief inline fragments
- **Vary phrasing** in repetitive sections — humans don't copy-paste the same comment structure

---

## What to Leave Alone

- Function/variable names (`_ensure_datetime`, `utilization_rate`)
- API parameters (`json.dumps(..., ensure_ascii=False)`)
- Domain terms used correctly (`facilitate` in mediation context)
- Legally required labels (`AI-Generated Document`)
- `example_data/`, vendor code, third-party code
- Code logic — only touch prose

---

## Grep Commands

```bash
# high-priority AI terms in changed files
git diff --name-only main...HEAD | xargs grep -inE \
  'leverage|utilize|streamline|\brobust\b|comprehensive|cutting.edge|seamless|empower|innovative|purpose.built|best.in.class|state.of.the.art|delve|tapestry|paradigm|synergy|holistic|pivotal|multifaceted|nuanced|\brealm\b|cornerstone|foster|harness|spearhead|testament|encompasses|embark|unravel' \
  2>/dev/null || true

# structural tells
git diff --name-only main...HEAD | xargs grep -inE \
  'it is important to note|it.s worth noting|in order to|at its core|plays a crucial role|a wide range of|designed to|crafted to|this function|this class|this module is' \
  2>/dev/null || true

# conclusion sections in markdown
git diff --name-only main...HEAD | grep '\.md$' | xargs grep -in '^## \(Conclusion\|Summary\|Next Steps\)' 2>/dev/null || true
```
