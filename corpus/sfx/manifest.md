# SFX fixture provenance (2026-10-27)

Official [LZMA SDK 26.05 release asset](https://github.com/ip7z/7zip/releases/download/26.05/lzma2605.7z),
1,786,350 bytes; SHA-256:
`668fda469b7f584f246008cf28359c66ef98d65fafb3b22a52672eebe6970c28`.
SDK documentation and compiled SFX modules are Public Domain, Igor Pavlov;
see the retained [notice](../../licenses/7zip-SFX-Public-Domain.txt).

Exact unmodified stub SHA-256 values:

| Stub | Bytes | SHA-256 |
| --- | ---: | --- |
| 7zS2.sfx | 35328 | a47ba54a62b53595d556db5211dfaf252e2f28ec00574e594ed2d37b0dc9927b |
| 7zS2con.sfx | 34816 | 096faf069e0c8e9900de97f95ef458aff9b6c0193ee523dd427d0cfc34994943 |
| 7zSD.sfx | 129024 | 3a335e4338ebb8a8cff7b81aaa35decc148845e2ce144bfaf680b09cd647cb8c |

SHA-256 of each **decoded complete envelope**, not the Base64 transport:

| Fixture | SHA-256 |
| --- | --- |
| gui | a0bbb70b702dbaac6ba7768faa02887224ca20c8c852f14b0d07fdc44a849022 |
| console | 934218948dcb8220b68e556ef63bd2932ddc4508251b3fe30f1cf6570a71e41b |
| installer | 933e33f31f3dea0a07cacb2a3abf3f9597d9a76d2c422fd6bc504857e664040b |

The generator follows the SDK `DOC/installer.txt` concatenation workflow. It
uses official 7za 26.05 with LZMA2, solid mode, compressed header and timestamp
storage disabled. It independently tests/extracts every resulting envelope and
compares all files. It never executes a stub. The 58-byte config and generator
are project-authored Apache-2.0; payload source/license is recorded in
[SOURCES.md](../../SOURCES.md). No external tests were copied.
