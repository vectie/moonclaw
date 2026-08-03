# PDF OCR Markdown

This internal package converts a PDF into Markdown by running a simple OCR
pipeline:

1. rasterize PDF pages with `pdftoppm`
2. OCR each page image with `tesseract`
3. normalize OCR text into page-structured Markdown

It is intended as a reusable seam for job preprocessing and attachment
ingestion, not as a full document-layout engine.

## Runtime dependencies

The current implementation expects these binaries on `PATH`:

- `pdftoppm`
- `tesseract`

## Current behavior

- OCR is page-by-page
- output is Markdown with one `## Page N` section per page
- simple paragraph and list normalization is applied
- no table reconstruction or visual layout preservation yet

## Example

```moonbit
let document = @pdf_ocr_markdown.convert_pdf_to_markdown("/tmp/report.pdf")
println(document.markdown)
```
