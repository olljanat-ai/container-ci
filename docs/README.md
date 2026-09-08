# The guidance site

`index.html` is the page teams land on: they pick their CI system and get the setup for
it, with the shared parts underneath.

**`index.html` is generated. Edit `index.template.html` instead.**

```bash
python3 tools/build_docs.py           # regenerate index.html
python3 tools/build_docs.py --check   # what CI runs
```

The template embeds real files with `{{include:<path>}}`, so the YAML shown on the page
is the YAML in the repository — change a pipeline and the page changes with it. CI fails
the build if `index.html` is out of date.

| File | |
| --- | --- |
| `index.template.html` | Page source. Edit this. |
| `index.html` | Generated output. Committed so GitHub Pages can serve it. |
| `assets/style.css` | Design tokens and layout. Both themes are defined token-level. |
| `assets/app.js` | Tool chooser, theme toggle, a small syntax colouriser, copy buttons, scroll-spy nav. |

No build tooling, no dependencies, no framework — the page is three static files plus a
Google Fonts stylesheet.

## Publishing

GitHub Pages, deployed by [`.github/workflows/pages.yml`](../.github/workflows/pages.yml)
on every push to `main` that touches `docs/`. The workflow re-runs
`tools/build_docs.py --check` before it uploads, so a stale `index.html` fails the deploy
instead of being served.

Enable it once, in *Settings → Pages → Source → **GitHub Actions***. The `.nojekyll` file
is kept for the older *Deploy from a branch → `main` / `/docs`* mode; the Actions
deployment serves the artifact as-is and never runs Jekyll.

## Adding a CI platform

The chooser is driven by one `data-tool` attribute. See
[`ai/playbooks/add-pipeline-platform.md`](../ai/playbooks/add-pipeline-platform.md) for
every place a new platform has to be registered.
