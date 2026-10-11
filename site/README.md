# chaudron's website

The home page and the documentation, built with
[Haunt](https://dthompson.us/projects/haunt.html). Everything it needs,
fonts included, comes from Guix, at the revision pinned in `channels.scm`:

```sh
guix time-machine -C channels.scm -- shell -m manifest.scm -- haunt build
guix time-machine -C channels.scm -- shell -m manifest.scm -- haunt serve --watch
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
| `> [!NOTE]`, `> [!TIP]` | a callout |
| `> [!CAUTION]`, `> [!DANGER]` | a warning callout |
| a table with `\|` | a table |
| `[Stages](/docs/stages/)` | a link to another page |

Don't use `#`: the `title:` is the page's heading.
