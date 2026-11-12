---
name: youtube-transcript
description: Extract a YouTube transcript, remove timestamps, and save as a clean markdown file with section headings from the video's chapter markers
tools: [YouTube, Write, Read]
---

# YouTube Transcript to Markdown Skill

Use this skill to extract a transcript from any YouTube video, strip the timestamps, add section headings from the video's chapter markers (found in the description), and save the result as a clean, readable markdown file.

## Process

### Step 1: Extract transcript and description

Call the `YouTube` tool with the video URL. This returns both the video description (with chapter markers) and the full transcript with timestamps.

```
YouTube url: "https://www.youtube.com/watch?v=VIDEO_ID"
```

### Step 2: Identify chapter markers

In the returned description, look for a block of chapters in this format:

```
00:00 OpenCode overview
00:38 Terminal catch
01:14 Claude Co-Work
...
```

Each line is a timestamp and a title. These become your section headings.

### Step 3: Assign sections to transcript paragraphs

Map each chapter title to the corresponding section of the transcript. The transcript comes with timestamps like `[0:00]`, `[0:31]`, `[1:01]`, etc. Use the chapter timestamps as boundaries to determine where each section begins.

- The first section starts at the beginning of the transcript.
- Each subsequent section starts at the paragraph whose timestamp falls on or after that chapter's timestamp.
- If the transcript has more content after the last chapter, it continues under the last heading.

### Step 4: Write the markdown file

Use the `Write` tool to save the result. The file should include:

- A level-1 heading with the video title
- The video URL
- Any relevant links from the description
- The transcript body, broken into sections with level-2 headings matching the chapter titles, with all timestamps removed from the body text

### Naming convention

Name the file after the video title, lowercased, with hyphens replacing spaces, followed by `-transcript.md`. For example: `opencode-aionui-transcript.md`.

## Example

**Input:** `https://www.youtube.com/watch?v=xOOUEx8XBDE`

**Output file structure:**

```markdown
# OpenCode + AionUi: The Free Alternative to Claude Cowork

**Video:** https://www.youtube.com/watch?v=xOOUEx8XBDE

**Links:**
- AionUi: https://github.com/iOfficeAI/AionUi
- OpenCode: https://github.com/sst/opencode
- Official site: https://www.aionui.com

---

## OpenCode overview

Open code is one of the better open source coding agents out right now...

## Terminal catch

The catch with Open Code, if you want to call it that, is that it lives in the command line...

## Claude Co-Work

Before I show you that, Anthropic released a tool called Claude Co-work...

...
```

## Notes

- Remove ALL timestamp markers like `[0:00]`, `[0:31]`, `[1:01]` from the final output.
- If the description has no chapter markers, still produce a clean transcript without timestamps, using a single body of text.
- Keep the description's useful links (GitHub repos, official sites) in a links section at the top.
- The transcript paragraphs may need minor editing for flow after timestamps are removed — merge sentences that were split by timestamps back into coherent paragraphs.
