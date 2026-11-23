// Packs build/icon/icon_<size>.png into windows/runner/resources/app_icon.ico.
// ICO entries may hold PNG data directly (supported since Windows Vista).
// Run: dart tool/icon/make_ico.dart
import 'dart:io';
import 'dart:typed_data';

void main() {
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  final images = [for (final s in sizes) File('build/icon/icon_$s.png').readAsBytesSync()];
  final header = ByteData(6)
    ..setUint16(0, 0, Endian.little) // reserved
    ..setUint16(2, 1, Endian.little) // type: icon
    ..setUint16(4, sizes.length, Endian.little);
  final dir = BytesBuilder();
  var offset = 6 + 16 * sizes.length;
  for (var i = 0; i < sizes.length; i++) {
    final s = sizes[i];
    final e = ByteData(16)
      ..setUint8(0, s == 256 ? 0 : s) // width (0 = 256)
      ..setUint8(1, s == 256 ? 0 : s) // height
      ..setUint8(2, 0) // palette
      ..setUint8(3, 0) // reserved
      ..setUint16(4, 1, Endian.little) // colour planes
      ..setUint16(6, 32, Endian.little) // bits per pixel
      ..setUint32(8, images[i].length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    dir.add(e.buffer.asUint8List());
    offset += images[i].length;
  }
  final out = BytesBuilder()
    ..add(header.buffer.asUint8List())
    ..add(dir.takeBytes());
  for (final img in images) {
    out.add(img);
  }
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(out.takeBytes());
  stdout.writeln('Wrote windows/runner/resources/app_icon.ico (${sizes.length} sizes)');
}
