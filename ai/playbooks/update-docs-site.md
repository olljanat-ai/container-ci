# Playbook: edit the guidance site

`docs/index.html` is **generated**. Edit `docs/index.template.html` and re-render:

```bash
python3 tools/build_docs.py
```

CI fails the build if the committed `index.html` does not match. Editing `index.html`
directly always ends in that failure.

## How the page is put together

Three static files, no framework, no build step beyond the include substitution:

| | |
| --- | --- |
| `docs/index.template.html` | Content. `{{include:<path>}}` embeds a real repository file, HTML-escaped |
| `docs/assets/style.css` | Design tokens and layout |
| `docs/assets/app.js` | Tool chooser, theme toggle, syntax colouriser, copy buttons, scroll-spy |

Currently included: the three caller pipeline files, `pipelines/common/trivy.yaml` and
`pipelines/common/Dockerfile`. Those five never need copying by hand — change the file,
re-render, done.

## Adding content

**A new section:** add a `<section id="…">` in the template and a matching entry in the
rail `<nav>`. The scroll-spy picks it up automatically from the nav links.

**Platform-specific content:** wrap it in `data-tool="<slug>"`. The attribute takes a
space-separated list, so `data-tool="github gitlab"` shows for both. Slugs are
`azure-devops`, `github`, `gitlab`.

**A code block:**

```html
<div class="code">
  <div class="code__bar">
    <span class="code__path">path/or/label</span>
    <button class="code__copy" type="button">Copy</button>
  </div>
  <pre><code data-lang="yaml">{{include:path/to/file.yml}}</code></pre>
</div>
```

`data-lang` is one of `yaml`, `hcl`, `dockerfile` or `shell`. Hand-written code needs
`&lt;` and `&amp;` escaped; `{{include:}}` content is escaped for you.

## Design constraints

- **Both themes are defined at token level.** Every colour is a `--var` declared in the
  bare `:root` block, then redefined in `@media (prefers-color-scheme: dark)` (guarded as
  `:root:not([data-theme="light"])`) and in `:root[data-theme="dark"]`. A colour whose
  only definition lives inside one of those blocks does not apply in the default,
  un-stamped state — that is the classic unreadable-page bug.
- **Numbering means sequence.** The `.steps` list is numbered because the build contract
  really is ordered. Do not number things that are not.
- **Wide content scrolls in its own container.** Tables go in `.table-wrap`, code in
  `.code`. The page body must never scroll sideways.
- **Callouts are rationed.** `.note` and `.note--watch` earn their border by being rare.

## Publishing

`.github/workflows/pages.yml` deploys `docs/` to GitHub Pages on every push to `main`
that touches it. It runs `tools/build_docs.py --check` first, so an un-regenerated
`index.html` fails the deploy rather than reaching the site. Nothing to do by hand; the
one-time setup is *Settings → Pages → Source → **GitHub Actions***.

## Verify

```bash
python3 tools/build_docs.py
python3 tools/build_docs.py --check
```

Then open `docs/index.html` and click all three chooser options. Each must show its own
setup block and nothing else, and the choice must survive a reload — it is kept in the
URL hash and `localStorage`.
