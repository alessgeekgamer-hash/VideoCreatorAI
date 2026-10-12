import '../models/project.dart';
import 'export_io.dart' as io;

Future<String> exportarVideo(VideoProject p, {void Function(String)? onLog}) =>
    io.exportarMp4IO(p, onLog: onLog);
