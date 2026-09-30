FACE HUGGER — THIRD-PARTY NOTICE MATERIALS

This directory preserves upstream license texts and attribution metadata for the
staged upload runtime: CPython 3.12.14, python-build-standalone build 20260901,
and the locked Hugging Face Python packages inspected on September 30, 2026.
The individual upstream texts control; this index does not replace them.

python-build-standalone-20260901/
  licenses/ contains all 19 texts shipped in the matching arm64 and x86_64
  full-build archives, plus a zlib-ng text referenced by upstream metadata but
  absent from those archives. The latter was recovered from the exact source
  dependency archive named by the upstream build recipe.
  The supplied license set is a superset: a notice's presence does not mean that
  its component is linked into this macOS runtime. license-coverage.json maps
  extension modules, license paths, and reported system/static links.
  provenance.json records upstream URLs and verified hashes. The full upstream
  PYTHON.json files are retained for each architecture. OpenSSL 3.5.8 AUTHORS.md
  is retained; its upstream LICENSE.txt matches LICENSE.openssl-3.txt exactly.

python-packages/
  Each package directory preserves the license files supplied by that locked
  wheel. inventory.json records names, versions, file hashes, and runtime paths.
  Both architecture copies were compared and matched. hf-xet-1.6.0 also retains
  its wheel-supplied CycloneDX software bills of materials for both architectures.

hf-xet-dependencies/
  Source-supplied notices for all 237 identities in the union of both wheel
  SBOMs (231 registry crates and six Xet workspace identities). provenance.json
  records exact source URLs, registry/SBOM checksums, supplemental source
  revisions, and hashes of every retained notice. Sources were read only;
  no crate or build scripts were executed. The collection includes upstream
  notice supersets and does not imply every named component ships in the app.

libyaml-0.2.5/
  The separate upstream libyaml License used by PyYAML's native extension.
  provenance.json records exact release commits, build-recipe evidence, and
  the bundled arm64 runtime's libyaml version report. Intel binary inspection
  agrees; Intel execution was not performed.

AUDIT LIMIT
All license paths referenced by the two inspected Python full-build metadata
files resolve to retained text. This does NOT establish a complete notice set
for all code in the product. HF Xet's component source-notice collection is
retained, but source-embedded attributions and license-specific obligations
still warrant review. Other compiled/vendored wheel dependencies require
further review before claiming a complete distribution notice audit.

CPython's standard-library LICENSE.txt and the original dist-info license files
are also retained in the staged runtime. Keep this directory structure when
packaging; flattening it loses identically named notices from different packages.
