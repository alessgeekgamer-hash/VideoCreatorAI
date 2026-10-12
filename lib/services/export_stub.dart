import 'dart:typed_data';
import '../models/project.dart';

// Implementación elegida según plataforma vía import condicional.
Future<String> exportarVideoMp4({
  required VideoProject proyecto,
  required Future<String> Function(String nombre) tempFilePath,
  required Future<void> Function(Uint8List bytes, String nombre) writeTemp,
  required Future<String> Function(String cmd) runFFmpeg,
}) {
  throw UnimplementedError('Usa export_io o export_web');
}
