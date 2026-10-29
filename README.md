# Systemic Antifungal Pharmacology — Quarto presentation

A reveal.js lecture (59 content slides + 4 section dividers) covering the established antifungal
classes and the agents in late-phase development.

## Layout

```
_quarto.yml          project config (bibliography, CSL)
index.qmd            title slide, YAML format options, section includes
sections/            one .qmd per lecture section (edit these)
  00-burden.qmd            disease burden, WHO priority pathogens, why development is hard
  01-targets.qmd           molecular targets and the PK/PD framework
  02-polyenes.qmd          amphotericin B formulations
  03-flucytosine.qmd       flucytosine
  04-triazoles.qmd         azole class, five triazoles + oteseconazole
  05-echinocandins.qmd     caspofungin, anidulafungin, micafungin
  06-unmet-need.qmd        gaps in the established classes
  07-rezafungin.qmd        .. 11-inhaled-and-other.qmd   newer agents
  12-comparisons.qmd       cross-class summary tables
  13-tdm.qmd               consolidated TDM targets
  14-closing.qmd           take-home points
references.bib       67 references, every entry verified against PubMed (PMID + DOI included)
vancouver.csl        numeric citation style
custom.scss          theme (colours, table sizing, callout boxes)
figures/             generated PNGs
```

## Rendering

```bash
quarto render                 # -> _output/index.html (self-contained)
quarto preview                # live reload while editing
```

`embed-resources: true` in `index.qmd` makes the output a single portable HTML file.

## Exporting a PDF handout

Open the rendered deck in Chrome with `?print-pdf` appended to the URL, then print to PDF:

```
_output/index.html?print-pdf
```

## Callout classes (defined in custom.scss)

- `::: {.keypoint}` — blue, the teaching point of the slide
- `::: {.pearl}` — amber, a clinical pearl or nuance
- `::: {.caution}` — red, a pitfall or contraindication
- `::: {.source}` — small grey text for data provenance
- `::: {.smaller-table}` — wraps the widest comparison tables

## Figures

Regenerate from the analysis session, or replace the PNGs in `figures/` keeping the same filenames:
`fig_timeline.png`, `fig_spectrum.png`, `fig_penetration.png`.
