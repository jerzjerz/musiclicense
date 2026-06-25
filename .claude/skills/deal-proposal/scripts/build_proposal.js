#!/usr/bin/env node
/*
 * deal-proposal renderer.
 * Renders a deal proposal .docx from a JSON deal spec, applying the
 * design tokens defined in docs/deal-proposal-design-system.md.
 *
 * Usage:  node build_proposal.js <input.json> [--out path.docx]
 *
 * The design tokens below ARE the implementation of the design system.
 * Do not restyle ad hoc — change the design-system doc first, then here.
 */
const fs = require("fs");
const path = require("path");

let docx;
try { docx = require("docx"); }
catch (e) {
  console.error("Missing dependency 'docx'. Run:  npm install --prefix " + __dirname + " docx");
  process.exit(2);
}
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Footer, AlignmentType, WidthType, BorderStyle, ShadingType,
  VerticalAlign, PageNumber, TabStopType,
} = docx;

// ---------- Design tokens (deal-proposal-design-system.md §2,§3,§1) ----------
const INK = "1A1A1A", SOFT = "6B6B6B", PANEL = "F7F4EF", HAIR = "DAD6CE", ACCENT = "6E2A33";
const SERIF = "Georgia", SANS = "Arial";
const CONTENT_W = 9180;

const noBorder = { style: BorderStyle.NONE, size: 0, color: "FFFFFF" };
const hair = { style: BorderStyle.SINGLE, size: 4, color: HAIR };
const cellMargins = { top: 90, bottom: 90, left: 150, right: 150 };

// ---------- primitives ----------
const spacer = (h = 120) => new Paragraph({ spacing: { after: h }, children: [new TextRun({ text: "", size: 2 })] });

const eyebrow = (text, after = 60) => new Paragraph({
  spacing: { after },
  children: [new TextRun({ text, font: SANS, size: 18, bold: true, allCaps: true, color: SOFT, characterSpacing: 24 })],
});

const h1 = (num, text) => new Paragraph({
  spacing: { before: 360, after: 80 },
  children: [
    new TextRun({ text: (num ? num + "  " : ""), font: SANS, size: 20, bold: true, color: ACCENT }),
    new TextRun({ text, font: SERIF, size: 36, bold: true, color: INK }),
  ],
});
const ruleAfter = () => new Paragraph({
  spacing: { after: 140 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: HAIR, space: 1 } },
  children: [new TextRun({ text: "", size: 2 })],
});
const h2 = (text) => new Paragraph({
  spacing: { before: 200, after: 60 },
  children: [new TextRun({ text, font: SANS, size: 24, bold: true, color: INK })],
});
const para = (text) => new Paragraph({
  spacing: { after: 120, line: 330, lineRule: "auto" },
  children: [new TextRun({ text, font: SERIF, size: 22, color: INK })],
});
const note = (text) => new Paragraph({
  children: [new TextRun({ text, font: SERIF, size: 20, italics: true, color: SOFT })],
});
const lead = (text) => new Paragraph({
  spacing: { after: 140, line: 330, lineRule: "auto" },
  children: [new TextRun({ text, font: SERIF, size: 22, italics: true, color: SOFT })],
});
const check = (text) => new Paragraph({
  spacing: { after: 70, line: 300, lineRule: "auto" },
  indent: { left: 360, hanging: 360 },
  children: [
    new TextRun({ text: "✓  ", font: SANS, size: 22, bold: true, color: ACCENT }),
    new TextRun({ text, font: SERIF, size: 22, color: INK }),
  ],
});

const callout = (lines) => new Table({
  width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: [CONTENT_W],
  borders: { top: noBorder, bottom: noBorder, right: noBorder, insideHorizontal: noBorder, insideVertical: noBorder,
    left: { style: BorderStyle.SINGLE, size: 24, color: ACCENT } },
  rows: [new TableRow({ children: [new TableCell({
    width: { size: CONTENT_W, type: WidthType.DXA },
    shading: { fill: PANEL, type: ShadingType.CLEAR, color: "auto" },
    margins: { top: 130, bottom: 130, left: 200, right: 200 },
    children: lines.map((l, i) => new Paragraph({
      spacing: { after: i === lines.length - 1 ? 0 : 70, line: 300, lineRule: "auto" },
      children: [new TextRun({ text: l, font: SERIF, size: 22, color: INK })],
    })),
  })] })],
});

function infoTable(rows, labelW = 2700) {
  const valW = CONTENT_W - labelW;
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: [labelW, valW],
    borders: { top: hair, bottom: hair, left: noBorder, right: noBorder, insideHorizontal: hair, insideVertical: noBorder },
    rows: rows.map(([k, v]) => new TableRow({ children: [
      new TableCell({ width: { size: labelW, type: WidthType.DXA }, margins: cellMargins, verticalAlign: VerticalAlign.CENTER,
        children: [new Paragraph({ children: [new TextRun({ text: k, font: SANS, size: 20, bold: true, color: INK })] })] }),
      new TableCell({ width: { size: valW, type: WidthType.DXA }, margins: cellMargins, verticalAlign: VerticalAlign.CENTER,
        children: [new Paragraph({ spacing: { line: 280, lineRule: "auto" }, children: [new TextRun({ text: v, font: SANS, size: 20, color: INK })] })] }),
    ] })),
  });
}

function dataTable(headers, colW, rows) {
  const headerRow = new TableRow({ tableHeader: true, children: headers.map((h, i) => new TableCell({
    width: { size: colW[i], type: WidthType.DXA }, margins: cellMargins,
    shading: { fill: PANEL, type: ShadingType.CLEAR, color: "auto" },
    children: [new Paragraph({ alignment: i === 0 ? AlignmentType.LEFT : AlignmentType.RIGHT,
      children: [new TextRun({ text: h, font: SANS, size: 20, bold: true, color: INK })] })],
  })) });
  const bodyRows = rows.map((r) => {
    if (r.band) return new TableRow({ children: [new TableCell({ columnSpan: headers.length,
      width: { size: CONTENT_W, type: WidthType.DXA }, margins: { top: 70, bottom: 70, left: 150, right: 150 },
      shading: { fill: "FBFAF7", type: ShadingType.CLEAR, color: "auto" },
      children: [new Paragraph({ children: [new TextRun({ text: r.band, font: SANS, size: 18, bold: true, allCaps: true, color: ACCENT, characterSpacing: 16 })] })] })] });
    return new TableRow({ children: r.cells.map((c, i) => new TableCell({
      width: { size: colW[i], type: WidthType.DXA }, margins: cellMargins, verticalAlign: VerticalAlign.CENTER,
      children: [new Paragraph({ alignment: i === 0 ? AlignmentType.LEFT : AlignmentType.RIGHT,
        children: [new TextRun({ text: String(c), font: SANS, size: 20, color: INK })] })] })) });
  });
  return new Table({ width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: colW,
    borders: { top: hair, bottom: hair, left: noBorder, right: noBorder, insideHorizontal: hair, insideVertical: noBorder },
    rows: [headerRow, ...bodyRows] });
}

function optionCards(left, right) {
  const W = CONTENT_W / 2;
  const head = (label) => new TableCell({ width: { size: W, type: WidthType.DXA }, margins: { top: 120, bottom: 100, left: 170, right: 170 },
    shading: { fill: PANEL, type: ShadingType.CLEAR, color: "auto" },
    borders: { top: { style: BorderStyle.SINGLE, size: 24, color: ACCENT }, bottom: noBorder, left: noBorder, right: noBorder },
    children: [new Paragraph({ children: [new TextRun({ text: label, font: SANS, size: 18, bold: true, allCaps: true, color: INK, characterSpacing: 18 })] })] });
  const fig = (figure, sub) => new TableCell({ width: { size: W, type: WidthType.DXA }, margins: { top: 100, bottom: 40, left: 170, right: 170 },
    borders: { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder },
    children: [
      new Paragraph({ spacing: { after: 20 }, children: [new TextRun({ text: figure, font: SERIF, size: 40, bold: true, color: ACCENT })] }),
      new Paragraph({ children: [new TextRun({ text: sub || "", font: SANS, size: 18, color: SOFT })] }),
    ] });
  const bullets = (items) => new TableCell({ width: { size: W, type: WidthType.DXA }, margins: { top: 60, bottom: 130, left: 170, right: 170 },
    borders: { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder },
    children: items.map((it) => new Paragraph({ spacing: { after: 60, line: 290, lineRule: "auto" }, indent: { left: 220, hanging: 220 },
      children: [new TextRun({ text: "—  ", font: SANS, size: 20, color: ACCENT }), new TextRun({ text: it, font: SERIF, size: 21, color: INK })] })) });
  return new Table({ width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: [W, W],
    borders: { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder, insideHorizontal: noBorder, insideVertical: { style: BorderStyle.SINGLE, size: 4, color: "FFFFFF" } },
    rows: [
      new TableRow({ children: [head(left.label), head(right.label)] }),
      new TableRow({ children: [fig(left.figure, left.figureSub), fig(right.figure, right.figureSub)] }),
      new TableRow({ children: [bullets(left.bullets || []), bullets(right.bullets || [])] }),
    ] });
}

// ---------- block dispatcher ----------
function renderBlock(b) {
  switch (b.kind) {
    case "h2": return [h2(b.text)];
    case "para": return [para(b.text)];
    case "lead": return [lead(b.text)];
    case "note": return [note(b.text)];
    case "callout": return [callout(b.lines), spacer(140)];
    case "infoTable": return [infoTable(b.rows, b.labelW)];
    case "dataTable": return [dataTable(b.headers, b.colW, b.rows)];
    case "checklist": return b.items.map(check);
    case "optionCards": return [optionCards(b.left, b.right)];
    case "spacer": return [spacer(b.h || 120)];
    default: throw new Error("unknown block kind: " + b.kind);
  }
}

// ---------- assemble ----------
function build(spec) {
  const ch = [];
  const m = spec.meta || {};

  // Cover
  ch.push(spacer(2600));
  if (m.confidentialLabel) ch.push(eyebrow(m.confidentialLabel));
  if (m.brandLabel) ch.push(eyebrow(m.brandLabel, 240));
  (m.titleLines || []).forEach((t, i, arr) =>
    ch.push(new Paragraph({ spacing: { after: i === arr.length - 1 ? 160 : 120 },
      children: [new TextRun({ text: t, font: SERIF, size: 60, color: INK })] })));
  ch.push(new Paragraph({ spacing: { after: 420 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 18, color: ACCENT, space: 1 } },
    children: [new TextRun({ text: "", size: 2 })] }));
  ch.push(spacer(160));
  if (m.info) ch.push(infoTable(m.info, m.infoLabelW || 2400));

  // Sections
  (spec.sections || []).forEach((s) => {
    if (s.pageBreakBefore) ch.push(new Paragraph({ pageBreakBefore: true, children: [new TextRun({ text: "", size: 2 })] }));
    ch.push(h1(s.num, s.title));
    ch.push(ruleAfter());
    if (s.lead) ch.push(lead(s.lead));
    (s.blocks || []).forEach((b) => renderBlock(b).forEach((p) => ch.push(p)));
  });

  if (spec.footerNote) { ch.push(spacer(220)); ch.push(note(spec.footerNote)); }

  return new Document({
    styles: { default: { document: { run: { font: SERIF, size: 22, color: INK } } } },
    sections: [{
      properties: { page: { size: { width: 11906, height: 16838 },
        margin: { top: 1588, bottom: 1440, left: 1361, right: 1361 } } },
      footers: { default: new Footer({ children: [new Paragraph({
        tabStops: [{ type: TabStopType.RIGHT, position: 9180 }],
        border: { top: { style: BorderStyle.SINGLE, size: 4, color: HAIR, space: 6 } },
        children: [
          new TextRun({ text: m.footer || "Strictly Private & Confidential", font: SANS, size: 16, color: SOFT }),
          new TextRun({ text: "\t", font: SANS, size: 16 }),
          new TextRun({ children: [PageNumber.CURRENT], font: SANS, size: 16, color: SOFT }),
        ],
      })] }) },
      children: ch,
    }],
  });
}

// ---------- CLI ----------
const args = process.argv.slice(2);
const inPath = args.find((a) => !a.startsWith("--"));
if (!inPath) { console.error("Usage: node build_proposal.js <input.json> [--out path.docx]"); process.exit(1); }
const outIdx = args.indexOf("--out");
const spec = JSON.parse(fs.readFileSync(inPath, "utf-8"));
const out = outIdx >= 0 ? args[outIdx + 1] : (spec.out || "deal-proposal.docx");
fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
Packer.toBuffer(build(spec)).then((buf) => {
  fs.writeFileSync(out, buf);
  console.log("written:", out, buf.length, "bytes");
});
