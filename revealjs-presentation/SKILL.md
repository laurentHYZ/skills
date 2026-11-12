---
name: revealjs-presentation
description: Build reveal.js HTML presentations with chalkboard (blackboard) annotation and custom control toolbar. Use this when the user asks to create a reveal.js presentation, a slide deck, HTML slides, or a teaching/presentation file. Covers the full workflow: generating slide HTML from user content, writing it to a .html file, and serving it via a local HTTP server. Uses reveal.js 4.6.1 with the chalkboard plugin (@latest CDN), custom controls with Font Awesome icons, and minScale/maxScale locked to 1.00 for sharp text rendering.
---

# Reveal.js Presentation Builder

Build self-contained, single-file reveal.js HTML presentations that include a chalkboard (blackboard) for freehand drawing and slide annotation.

## Quick start

1. Copy `assets/template.html` to a new `.html` file in the target directory
2. Replace `{{TITLE}}` and `{{SUBTITLE}}` with actual values
3. Add slides inside `<div class="slides">` using `<section>` elements
4. Add custom CSS in the `<style>` block if needed
5. Serve with `python3 -m http.server 8888` and open in browser

## Slide structure

Each slide is a `<section>` inside `<div class="slides">`. Nest `<section>` elements to create vertical slide stacks (navigated with up/down arrows).

```html
<!-- Regular horizontal slide -->
<section>
  <h2>Slide Title</h2>
  <p>Content here</p>
</section>

<!-- Vertical slide stack -->
<section>
  <section><h2>Main Topic</h2></section>
  <section><h3>Sub-point 1</h3></section>
  <section><h3>Sub-point 2</h3></section>
</section>
```

## Fragments (progressive reveal)

Use `class="fragment"` to reveal elements one at a time:

```html
<ul>
  <li class="fragment">Appears first</li>
  <li class="fragment">Appears second</li>
</ul>
```

## Features

- **B key** — toggle blackboard (blank canvas with grid, freehand draw)
- **C key** — toggle notes canvas (annotate directly on current slide)
- **DEL** — clear current surface
- **?** — show all keyboard shortcuts
- Toolbar buttons (bottom-left): chalkboard icon and pen icon
- Font Awesome 6.4.0 icons available: `<i class="fa fa-..."></i>`

## Configuration

The template uses these key settings (proven to work with the chalkboard plugin):

- `width: 1400, height: 900` — slide resolution
- `minScale: 1.00, maxScale: 1.00` — prevents blurry text scaling
- `keyboard: true` — no key override needed
- chalkboard plugin loaded from `reveal.js-plugins@latest` (not a pinned version)
- `toggleChalkboardButton` and `toggleNotesButton` positioned at bottom-left

## Serve and open

Always serve the HTML via a local HTTP server (file:// protocol may break CDN loading):

```bash
cd /path/to/slides && python3 -m http.server 8888
```

Then open `http://localhost:8888/presentation.html`.
If on WSL, use `wslview http://localhost:8888/presentation.html` to open in the Windows browser.
