# chaudron's website

The home page and the documentation, built with
[Haunt](https://dthompson.us/projects/haunt.html), and deployed to
[chaudron.dev](https://chaudron.dev) with chaudron itself. Everything it
needs, fonts and chaudron included, comes from the channels pinned in
`channels.lock.scm`:

```sh
guix time-machine -C channels.lock.scm -- shell -m manifest.scm -- haunt serve --watch
guix time-machine -C channels.lock.scm -- shell -m manifest.scm -- guile deploy.scm
```

The first serves the site on <http://localhost:8080>; the second builds it
and deploys it, with the Cloudflare token of `.env`. To move to newer
versions of Guix and chaudron:

```sh
guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm
```

The site is written to `public/`. The search needs a server: it does not
work when opening the files directly.

## Where things are

| File | |
| --- | --- |
| `haunt.scm` | the site: which pages and files it is made of |
| `chaudron-site/home.scm` | the home page |
| `chaudron-site/docs.scm` | the documentation pages, their sidebar and search |
| `chaudron-site/markdown.scm` | what the Markdown of the documentation turns into |
| `chaudron-site/common.scm` | what every page shares: head, header, footer, code panels |
| `chaudron-site/frames.scm` | the pixel frames, drawn one character per pixel |
| `chaudron-site/fonts.scm` | the fonts, subset when building |
| `assets/` | style sheets, scripts and the logo, copied as they are |
| `docs/` | the documentation, in Markdown |

## Writing documentation

One Markdown file per page, in `docs/<section>/<page>.md`. The page is
served at `/docs/<page>/`, so page names must be unique.

| Directory | Section in the sidebar |
| --- | --- |
| `docs/start/` | Start here |
| `docs/concepts/` | Concepts |
| `docs/providers/` | Providers |
| `docs/recipes/` | Recipes |
| `docs/extending/` | Extending |

Sections and their order are in `%sections`, in `chaudron-site/docs.scm`.

Each file starts with a header, then `---`:

```text
title: Stages
order: 1
description: One environment, deployed by running one program.
---

The text starts here.
```

| Field | |
| --- | --- |
| `title:` | the title of the page, required |
| `order:` | its position in its section |
| `description:` | shown under the title, and to search engines |

### Markdown

| You write | You get |
| --- | --- |
| `## Setup`, `### Details` | sections, listed in "On this page" |
| ```` ```scheme ```` | highlighted Scheme, in a frame titled "scheme" |
| ```` ```scheme deploy.scm ```` | the same, titled "deploy.scm" |
| ```` ```output ```` | what chaudron prints, its `chaudron:` lines in green |
| ```` ```sh ```` | commands; a leading `$ ` is shown as a prompt |
| ```` ```project ```` | the tree of a project: one `@ file \| kind` line per file, a description, and an example between `~~~` lines; kind is `commit`, `generated`, `secret` or `optional` |
| `> [!NOTE]`, `> [!TIP]` | a callout |
| `> [!CAUTION]`, `> [!DANGER]` | a warning callout |
| a table with `\|` | a table |
| `[Stages](/docs/stages/)` | a link to another page |

Don't use `#`: the `title:` is the page's heading.
