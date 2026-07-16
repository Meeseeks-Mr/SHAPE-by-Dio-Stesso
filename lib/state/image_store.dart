import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Raw RGBA pixels produced by the pure-Dart decoder in a background isolate,
/// ready for [ui.decodeImageFromPixels]. Plain data so it is sendable across the
/// isolate boundary.
class _DecodedRgba {
  _DecodedRgba(this.width, this.height, this.pixels);
  final int width, height;
  final Uint8List pixels; // length width*height*4, RGBA straight alpha
}

/// Decodes [bytes] with the pure-Dart [img] decoder and downsamples to
/// [ImageStore.maxSide], returning straight-alpha RGBA bytes. Runs in a
/// [compute] isolate. Returns null for formats package:image can't decode (the
/// caller then falls back to the platform codec).
///
/// We decode in pure Dart rather than via `ui.instantiateImageCodec` because the
/// Android platform codec was observed to strip the alpha channel from some
/// PNGs on-device (transparent pixels came back opaque → rendered black). The
/// pure-Dart path preserves alpha deterministically.
_DecodedRgba? _decodeRgbaIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final srcW = decoded.width, srcH = decoded.height;
  var out = decoded;
  final longest = math.max(srcW, srcH);
  if (longest > ImageStore.maxSide) {
    final scale = ImageStore.maxSide / longest;
    out = img.copyResize(decoded,
        width: math.max(1, (srcW * scale).round()),
        interpolation: img.Interpolation.average);
  }
  final rgba = out.getBytes(order: img.ChannelOrder.rgba);
  return _DecodedRgba(out.width, out.height, rgba);
}

/// Caches decoded [ui.Image]s keyed by object id so the synchronous painter can
/// draw them. Decoding is async; callers pass an [onReady] to trigger a repaint.
class ImageStore {
  ImageStore._();
  static final ImageStore instance = ImageStore._();

  /// Largest dimension we keep for a display texture. Huge imports (e.g. a
  /// 15 MP photo) are downsampled to this — it slashes GPU memory (a 4045²
  /// RGBA image is ~62 MB) and keeps the canvas responsive.
  static const int maxSide = 2048;

  final Map<String, ui.Image> _images = {};
  final Set<String> _decoding = {};

  ui.Image? get(String id) => _images[id];

  bool has(String id) => _images.containsKey(id);

  void put(String id, ui.Image image) => _images[id] = image;

  /// Decodes [bytes] into a display-ready [ui.Image]: pure-Dart decode (preserves
  /// alpha) + downsample on a background isolate, then uploaded via
  /// [ui.decodeImageFromPixels]. Falls back to the platform codec for formats
  /// package:image can't handle.
  static Future<ui.Image> decodeDisplay(Uint8List bytes) async {
    final raw = await compute(_decodeRgbaIsolate, bytes);
    if (raw == null) {
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      raw.pixels,
      raw.width,
      raw.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<ui.Image> decode(String id, Uint8List bytes,
      {void Function()? onReady}) async {
    final image = await decodeDisplay(bytes);
    _images[id] = image;
    onReady?.call();
    return image;
  }

  /// Ensure an id's bytes are decoded (no-op if already cached/decoding).
  void ensure(String id, Uint8List? bytes, void Function() onReady) {
    if (bytes == null || _images.containsKey(id) || _decoding.contains(id)) {
      return;
    }
    _decoding.add(id);
    decode(id, bytes, onReady: () {
      _decoding.remove(id);
      onReady();
    });
  }

  void evict(String id) => _images.remove(id);
}
