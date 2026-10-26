# Password-protected 7z imports

`Archive::open(bytes, password="...")` and
`host.open_file(path, password="...")` accept 7z AES-256-CBC/SHA-256 encrypted
data and headers. `archive.is_encrypted()` reports whether either uses AES;
it does not certify a password or authenticate the archive. The normal verified
read, audit, comparison and staged export APIs retain their behavior.

The checked-in fixtures use the **public test password** `moon7z-密码-🔑`.
For a manual PowerShell example, set `MOON7Z_PASSWORD` to that value, then run:

```console
moon run app -- --password-env MOON7Z_PASSWORD test corpus/encrypted/v2605-header.7z
moon run app -- --password-env MOON7Z_PASSWORD extract --contents-only corpus/encrypted/v2605-header.7z out protected-import
moon run checks/encrypted.mbtx -- wasm
moon run checks/encrypted.mbtx -- native
```

Create `out` first and use a new destination name. The executable receives only
the environment-variable name in its arguments. It reports a missing variable
without its value. Diff commands use the same supplied password for both inputs;
the library can open each side independently with different passwords.
The standalone checker supplies its public fixture password itself and compares
every exported byte with `corpus/x86/part-{a,b}.bin`. It also checks missing/wrong
passwords, empty stdout, absence of a published destination and no password value
in diagnostics. Native verification executes the native CLI.

Plain-header encrypted archives may be listed without a password; reading their
encrypted folders raises `PasswordRequired`. Encrypted headers require the
password during opening. An explicitly supplied empty string is different from
omitting the password. Text is encoded as UTF-16LE without BOM or normalization,
including supplementary Unicode characters. Salt and IV lengths are validated;
omitted IV bytes are zero. Empty properties use the official default parameters.
Cycles value 63 uses direct salt/password key material; other values use the
7z SHA-256 counter derivation. Ciphertext must match the declared zero-padded
size, padding is checked, and all available CRCs remain enforced.

`DecryptionFailed` means encrypted decoding, padding or integrity failed. It
cannot reliably distinguish a wrong password from damaged ciphertext. No failed
folder enters the reader cache or escapes as a member. Reopen with the correct
password to retry. Missing CRCs are still reported as missing; this format uses
CBC and CRCs, not authenticated encryption. No guaranteed memory erasure or
constant-time behavior is claimed for the managed runtime/primitive dependency.

## Bounded derivation

Defaults are `password_bytes=8192` UTF-16 bytes, `kdf_rounds=4194304` SHA rounds
and `kdf_bytes=134217728` hashed input bytes. The latter two are **cumulative per
Archive instance**, covering header and payload derivations. Work is checked
before hashing and large exponents return a typed `Limit`. No giant repeated
input string is allocated. Value 63 performs no SHA rounds. The existing input,
dictionary and graph/final-output budgets continue to apply.

Up to 64 derived keys are retained privately, indexed by cycle count and salt;
IV changes do not require a different key. Cache hits consume no new derivation
budget; eviction may require derivation again. Reopening starts a fresh budget.
Passwords/keys have no public getter, Debug or JSON implementation. This is a
work bound, not a wall-clock deadline or peak-memory guarantee.

## Independent evidence

Official 7-Zip Extra packed, tested and unpacked four cases with the public
Unicode password; every extracted member matched the attributed originals.
Random IVs make regeneration bytes differ, so hashes identify these exact
checked-in fixtures, not a promise of deterministic encryption.

| Fixture | Producer and layout | SHA-256 |
| --- | --- | --- |
| v1900-data.7z | 19.00, LZMA, visible header, solid | `a7be042637af2ce03fe3ce8b263b38021138e2c58fca130dff4450177811c5a5` |
| v2605-header.7z | 26.05, LZMA2, encrypted header, solid | `b3357d72e421a63d846e4a40aed389dd6226e1ee127183b98432164e3869e48f` |
| v2605-copy.7z | 26.05, Copy, visible header, solid | `1056116a05c0e5adef75ccfb111c61f0eaad9959ae3eb0d1abd5943b714924bb` |
| v2605-separate.7z | 26.05, BZip2, encrypted header, separate | `a83a844919ddbda9749b825c4793268bfec88f051f77abe69c0095b6c8872357` |

```console
moon run corpus/encrypted/generate.mbtx -- PATH_TO_7ZA19 PATH_TO_7ZA26 NEW_DIRECTORY
```

The generator deliberately passes this public fixture password to the independent
packer; application credentials must use the library API or CLI environment
option instead. AES and SHA are reused from `moonbitlang/x@0.5.5/crypto`
(Apache-2.0); 7z properties, bounded derivation and workflow integration are
described in [SOURCES.md](../SOURCES.md). The wider [compatibility target](compatibility.md)
is still incomplete, including PPMd and split/seekable inputs.
