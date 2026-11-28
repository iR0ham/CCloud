import 'dart:convert';

/// Deterministic 128-bit identifier hash used for catalog identity.
///
/// The recipe is fixed by the Multi-Source specification and is shared verbatim by the Swift
/// (`stableKeyHash`) and webOS (`CC.identityHash`) ports: four independent 32-bit FNV-1a passes
/// over the exact UTF-8 bytes of the input, seeded with `0x811c9dc5`, `0x9e3779b9`, `0x85ebca6b`
/// and `0xc2b2ae35`, each rendered as eight lowercase hex digits and concatenated into thirty-two.
///
/// Four passes rather than one is not decoration. Every call site builds an identity by embedding
/// a separator-delimited string (`playlistId\nprovider\nnamespace\nchannelId`), so a single 32-bit
/// fold over a large catalog eventually collides at a rate a user would notice as two channels
/// silently merging; widening to 128 bits pushes that far past any realistic playlist. A detected
/// collision must raise `identityCollision` and refuse the merge rather than pick a winner.
///
/// This is deliberately **not** a cryptographic digest: it is used for channel, source and track
/// identity only, and never for passwords, signatures or integrity claims about downloaded bytes.
final List<int> _fnvSeeds = const [
  0x811c9dc5,
  0x9e3779b9,
  0x85ebca6b,
  0xc2b2ae35,
];

const int _fnvPrime = 0x01000193;
const int _mask32 = 0xFFFFFFFF;

/// Hashes [value] into a lowercase 32-hex-digit identifier.
///
/// The input is hashed exactly as it arrives — no case folding, no trimming, no
/// [liveNameKey]-style normalization. Callers that want a match key normalize first and then
/// hash, so that two ports disagreeing about normalization can never change an identity silently.
String stableKeyHash(String value) {
  final bytes = utf8.encode(value);
  final buffer = StringBuffer();
  for (final seed in _fnvSeeds) {
    var hash = seed;
    for (final byte in bytes) {
      // FNV-1a order: XOR the byte in first, then multiply. Swapping the two gives FNV-1 and a
      // completely different identifier space, which would orphan every persisted catalog row.
      hash = ((hash ^ byte) * _fnvPrime) & _mask32;
    }
    buffer.write(hash.toRadixString(16).padLeft(8, '0'));
  }
  return buffer.toString();
}
