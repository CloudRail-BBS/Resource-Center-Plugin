#!/usr/bin/env node
// Syntax-checks .gjs / .js files with content-tag — the exact parser Discourse
// itself uses (frontend/asset-processor/content-tag.js).
//
// This matters more than it looks. lib/plugin/js_compiler.rb catches a
// TranspileError and emits `throw new Error(...)` as the ENTIRE plugin bundle,
// so one bad character in one file stops every component in the plugin from
// working, and the browser console points at the wrong file.
//
// Do NOT hand-roll this. The obvious approaches all let through the one shape
// that actually breaks a plugin (a `<template>` block followed by a separate
// `<script>` block):
//   - stripping `<template>`/`<script>` tags before parsing removes exactly the
//     structure you need to validate, so the broken shape passes;
//   - @glimmer/syntax's `preprocess` parses template-only strings, not whole
//     .gjs files, and also accepts the broken shape.
//
// Usage: node scripts/check-gjs.mjs <files…>

import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

const require = createRequire(import.meta.url);

let Preprocessor;
try {
  ({ Preprocessor } = require("content-tag"));
} catch {
  // A check that cannot run must not look like a check that passed.
  console.error(
    "SKIP  content-tag is not installed. Run `npm i content-tag` before validating.",
  );
  process.exit(2);
}

const processor = new Preprocessor();
const files = process.argv.slice(2);

if (files.length === 0) {
  console.error("SKIP  no files passed to check-gjs.mjs");
  process.exit(2);
}

let failed = 0;

for (const file of files) {
  const source = readFileSync(file, "utf8");

  try {
    processor.process(source, { filename: file });
    console.log(`OK    ${file}`);
  } catch (error) {
    console.error(`FAIL  ${file}\n      ${error.message}`);
    failed += 1;
  }
}

process.exit(failed === 0 ? 0 : 1);
