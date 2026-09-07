# Bug MP3 encoder

Bug dynamically loads LAME 3.100, copyright © the LAME project and its contributors.
LAME is licensed under the GNU Library General Public License, version 2 or later.
The library is provided WITHOUT ANY WARRANTY, including merchantability or fitness
for a particular purpose. The complete license is in `Resources/Encoder/COPYING.LAME`
after preparation; individual copyright notices are preserved in the source archive.

Upstream release: https://sourceforge.net/projects/lame/files/lame/3.100/
Source archive: https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
Fallback mirror: https://download.videolan.org/pub/contrib/lame/lame-3.100.tar.gz
Pinned SHA-256: `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`.
Both downloads must match this digest before extraction or compilation. The build script patches only the Darwin export list, removing obsolete
`lame_init_old` and disabled decoder (`lame_decode*`, `hip_*`) entries. The
archive remains unmodified; the shipped script reproduces the complete patch. `scripts/prepare-encoder.sh` contains the complete build recipe.
No global installation, Package.swift dependency, or network access at runtime is needed.

## Packaging handoff

1. Run `scripts/prepare-encoder.sh` for the host architecture, or
   `ARCHS="arm64 x86_64" scripts/prepare-encoder.sh` for a universal dylib.
   Apple Command Line Tools, curl, make, and an SDK are required. The script builds
   in a temporary directory and writes only `Resources/Encoder/` in the repository.
2. Copy `Resources/Encoder/libmp3lame.dylib` to
   `Bug.app/Contents/Frameworks/libmp3lame.dylib` before signing the app.
   Architectures must include every architecture of the app executable.
   The library install ID is `@rpath/libmp3lame.dylib`; Bug loads the absolute bundle
   path with dlopen, so no additional linker or rpath setting is required.
3. Copy this notice, `Resources/Encoder/COPYING.LAME`, the unmodified corresponding
   source `Resources/Encoder/lame-3.100.tar.gz`, and `scripts/prepare-encoder.sh`
   into `Bug.app/Contents/Resources/Encoder/`. Include these with every distribution.
   The source archive permits recipients to rebuild and replace the dynamic library.
   Do not impose restrictions on LGPL-permitted replacement/debugging of the library.
4. Sign the nested dylib, then the app, using the same identity (ad hoc for local use).
   Distributors who change signing/runtime policies must preserve LGPL replacement rights.
5. Validate `swift build`, `swift test`, and `scripts/package-app.sh`, then confirm
   the resulting app contains the library and notices. Packaging integration belongs
   to the lead; the exporter does not modify the packaging script or package manifest.

For unbundled development/tests construct `AudioExporter(encoderURL: URL(...))` with
an absolute path to the prepared dylib. The default initializer loads only the app's
bundled encoder; missing or incompatible libraries produce a recoverable export error.

## Audio behavior and limits

Capture's common-epoch leading silence is retained. Mono is duplicated to stereo;
stereo channels are preserved. Each input is resampled independently to 48 kHz,
then summed with zero padding through the longest track. Supported inputs are mono
or stereo at 8–192 kHz; multichannel input fails explicitly.

Two passes use bounded 4096-frame buffers. The first measures the mixed sample peak;
the second applies constant `gain = min(1, 0.95 / peak)` (silence uses 1). This never
boosts quiet material, retains dynamics, and reserves approximately 0.45 dB headroom.
24-bit integer quantization rounds without dither. MP3 uses normalized floating-point
input, CBR 320 kbps, 48 kHz joint stereo, LAME quality 2. Lossy reconstruction may
overshoot sample peaks: this is not a true-peak limiter. CBR output has encoder delay
and end padding, without a gapless Xing/LAME header.

Classic RIFF WAV is limited to just under 4 GiB (about 4.14 hours); larger WAV exports
fail before replacing the destination. MP3 has no corresponding WAV size limit.
Inputs must be completed, immutable recordings during both passes. Sources are never
written or removed. Output is staged beside the destination and renamed atomically
only after successful finalization, synchronization, and a cancellation check. Failure
or cancellation before that commit preserves an existing destination and cleans the
staging file. Cancellation arriving after the atomic commit cannot undo a completed
export. A process crash can leave a hidden `.bug-export-*` staging file.
