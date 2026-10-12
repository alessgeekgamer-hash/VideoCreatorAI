import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';

Future<String> _run(String cmd) async {
  final s = await FFmpegKit.execute(cmd);
  final code = await s.getReturnCode();
  if (!ReturnCode.isSuccess(code)) {
    final logs = await s.getAllLogsAsString();
    throw Exception('FFmpeg fallo: $logs');
  }
  return '';
}

String _tipoSfx(String keyword) {
  final k = keyword.toLowerCase();
  if (k.contains('whoosh') || k.contains('intro') || k.contains('transi') || k.contains('sweep')) return 'whoosh';
  if (k.contains('pop') || k.contains('click') || k.contains('success') || k.contains('ding')) return 'pop';
  if (k.contains('riser') || k.contains('tension') || k.contains('suspense')) return 'riser';
  return 'pad';
}

/// Genera un SFX procedural sin internet (para que la app siempre agregue sonidos).
Future<void> _genSfx(String keyword, double dur, String out) async {
  final t = _tipoSfx(keyword);
  final d = dur.clamp(1, 15).toStringAsFixed(1);
  String cmd;
  if (t == 'whoosh') {
    cmd = '-y -f lavfi -i "anoisesrc=d=$d:c=white:r=44100" -af "highpass=f=500,lowpass=f=6000,volume=0.15,afade=t=in:st=0:d=0.3,afade=t=out:st=0:d=$d" -c:a aac "$out"';
  } else if (t == 'pop') {
    cmd = '-y -f lavfi -i "sine=frequency=880:duration=$d" -af "volume=0.25,afade=t=out:st=0:d=$d" -c:a aac "$out"';
  } else if (t == 'riser') {
    cmd = '-y -f lavfi -i "sine=frequency=200:duration=$d" -af "vibrato=f=6:d=0.8,volume=0.18,afade=t=in:st=0:d=1,afade=t=out:st=0:d=$d" -c:a aac "$out"';
  } else {
    cmd = '-y -f lavfi -i "sine=frequency=110:duration=$d" -f lavfi -i "sine=frequency=165:duration=$d" -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest,volume=0.10,afade=t=in:st=0:d=0.5,afade=t=out:st=0:d=$d[a]" -map "[a]" -c:a aac "$out"';
  }
  await _run(cmd);
}

/// Exporta MP4 real en Windows/Android/Desktop.
/// - Escala a 1920x1080 o 1080x1920, transiciones xfade opcionales
/// - Mezcla voz + SFX auto + musica fondo, respeta carpetaDestino
Future<String> exportarMp4IO(VideoProject proyecto,
    {void Function(String)? onLog}) async {
  final tmp = await getTemporaryDirectory();
  final w = proyecto.formato == '9:16' ? 1080 : 1920;
  final h = proyecto.formato == '9:16' ? 1920 : 1080;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final segs = <String>[];

  for (var i = 0; i < proyecto.escenas.length; i++) {
    final e = proyecto.escenas[i];
    final seg = p.join(tmp.path, 'seg_$i.mp4');
    final dur = e.duracion.clamp(1, 30).toDouble();
    final durS = dur.toStringAsFixed(1);
    onLog?.call('Escena ${i + 1}/${proyecto.escenas.length}...');
    // Si hay clip animado (Meta manual o HF), usarlo recortado a la duracion
    String? clipSrc;
    if (e.clipBytes != null) {
      clipSrc = p.join(tmp.path, 'clip_$i.mp4');
      await File(clipSrc).writeAsBytes(e.clipBytes!, flush: true);
    } else if (e.clipPath != null && await File(e.clipPath!).exists()) {
      clipSrc = e.clipPath!;
    }
    if (clipSrc != null) {
      var vfBase =
          'scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,format=yuv420p';
      await _run(
          '-y -stream_loop -1 -i "$clipSrc" -t $durS -vf "$vfBase" -r 30 -c:v mpeg4 -q:v 3 -an "$seg"');
      segs.add(seg);
      continue;
    }
    if (e.imagenBytes == null) {
      throw Exception('Escena ${i + 1} sin imagen ni clip');
    }
    final imgPath = p.join(tmp.path, 'esc_$i.jpg');
    await File(imgPath).writeAsBytes(e.imagenBytes!, flush: true);
    // Movimiento CONTINUO toda la escena (alterna zoom-in / zoom-out + paneo)
    final frames = (dur * 30).round();
    final mov = i.isEven
        ? "zoompan=z='1+0.18*on/$frames':d=$frames:x='(iw-iw/zoom)*on/$frames':y='(ih-ih/zoom)*on/$frames':s=${w}x$h:fps=30"
        : "zoompan=z='1.18-0.18*on/$frames':d=$frames:x='(iw-iw/zoom)*(1-on/$frames)':y='(ih-ih/zoom)*(1-on/$frames)':s=${w}x$h:fps=30";
    // Subtitulos: genera SRT por escena para quemarlos (retencion + optimo Shorts/Reels)
    var vfBase = 'scale=${w * 2}:${h * 2},$mov,format=yuv420p';
    if (proyecto.subtitulos && e.narracion.trim().isNotEmpty) {
      try {
        final srt = p.join(tmp.path, 'cap_$i.srt');
        final txt = e.narracion.trim().replaceAll('\n', ' ');
        await File(srt).writeAsString(
            '1\n00:00:00,000 --> 00:00:${durS.replaceAll('.', ',')}\n$txt\n\n');
        final srtEsc = srt.replaceAll('\\', '/').replaceAll(':', '\\:');
        final vfSub =
            '$vfBase,subtitles=$srtEsc:force_style=\'FontSize=22,PrimaryColour=&HFFFFFF,OutlineColour=&H80000000,BorderStyle=1,Outline=2,MarginV=60\'';
        await _run(
            '-y -loop 1 -i "$imgPath" -t $durS -vf "$vfSub" -r 30 -c:v mpeg4 -q:v 3 "$seg"');
        segs.add(seg);
        continue;
      } catch (_) {
        // Sin libass en este FFmpeg: sigue sin subtitulos
      }
    }
    final cmd =
        '-y -loop 1 -i "$imgPath" -t $durS -vf "$vfBase" -r 30 -c:v mpeg4 -q:v 3 "$seg"';
    await _run(cmd);
    segs.add(seg);
  }

  // Video base: con o sin transiciones (variadas y visibles)
  String sinAudio = p.join(tmp.path, 'video_base_$ts.mp4');
  const td = 1.2;
  const trans = ['fadeblack', 'smoothleft', 'fade', 'fadewhite', 'smoothright'];
  if (proyecto.conTransiciones && segs.length > 1) {
    onLog?.call('Aplicando transiciones...');
    final inputs = segs.map((s) => '-i "$s"').join(' ');
    var fc = '';
    var last = '[0:v]';
    double offset = proyecto.escenas[0].duracion.clamp(1, 30).toDouble() - td;
    for (var i = 1; i < segs.length; i++) {
      final out = i == segs.length - 1 ? '[vout]' : '[x$i]';
      final tr = trans[(i - 1) % trans.length];
      fc += '$last[$i:v]xfade=transition=$tr:duration=$td:offset=${offset.toStringAsFixed(2)}$out;';
      if (i < segs.length - 1) {
        offset += proyecto.escenas[i].duracion.clamp(1, 30).toDouble() - td;
        last = out;
      }
    }
    await _run('-y $inputs -filter_complex "$fc" -map "[vout]" -r 30 -c:v mpeg4 -q:v 3 "$sinAudio"');
  } else {
    final listFile = File(p.join(tmp.path, 'concat_$ts.txt'));
    await listFile.writeAsString(segs.map((s) => "file '$s'").join('\n'));
    await _run('-y -f concat -safe 0 -i "${listFile.path}" -c copy "$sinAudio"');
  }

  // Pista voz concatenada (ajustada a duracion de escena)
  final voces = <String>[];
  for (var i = 0; i < proyecto.escenas.length; i++) {
    final e = proyecto.escenas[i];
    if (e.vozBytes != null) {
      final vp = p.join(tmp.path, 'voz_$i.wav');
      await File(vp).writeAsBytes(e.vozBytes!, flush: true);
      voces.add(vp);
    } else if (e.vozPath != null && await File(e.vozPath!).exists()) {
      voces.add(e.vozPath!);
    }
  }
  String? vozTotal;
  if (voces.isNotEmpty) {
    onLog?.call('Mezclando voz en off...');
    final vSegs = <String>[];
    for (var i = 0; i < voces.length; i++) {
      final d = proyecto.escenas[i].duracion.clamp(1, 30);
      final o = p.join(tmp.path, 'vozs_$i.m4a');
      await _run('-y -i "${voces[i]}" -t $d -af "apad,atrim=0:$d" -c:a aac "$o"');
      vSegs.add(o);
    }
    final vlist = File(p.join(tmp.path, 'vlist_$ts.txt'));
    await vlist.writeAsString(vSegs.map((s) => "file '$s'").join('\n'));
    vozTotal = p.join(tmp.path, 'voz_total_$ts.m4a');
    await _run('-y -f concat -safe 0 -i "${vlist.path}" -c copy "$vozTotal"');
  }

  // SFX automatico por escena (siempre, sin internet)
  String? sfxTotal;
  if (proyecto.sfxAuto) {
    try {
      onLog?.call('Generando efectos de sonido...');
      final sSegs = <String>[];
      for (var i = 0; i < proyecto.escenas.length; i++) {
        final o = p.join(tmp.path, 'sfx_$i.m4a');
        await _genSfx(proyecto.escenas[i].sonidoSugerido,
            proyecto.escenas[i].duracion.clamp(1, 30), o);
        sSegs.add(o);
      }
      final slist = File(p.join(tmp.path, 'slist_$ts.txt'));
      await slist.writeAsString(sSegs.map((s) => "file '$s'").join('\n'));
      sfxTotal = p.join(tmp.path, 'sfx_total_$ts.m4a');
      await _run('-y -f concat -safe 0 -i "${slist.path}" -c copy "$sfxTotal"');
    } catch (_) {
      sfxTotal = null;
    }
  }

  String? musFile;
  if (proyecto.musicaFondoBytes != null) {
    musFile = p.join(tmp.path, 'musica_bg.mp3');
    await File(musFile).writeAsBytes(proyecto.musicaFondoBytes!, flush: true);
  } else if (proyecto.musicaFondoPath != null &&
      await File(proyecto.musicaFondoPath!).exists()) {
    musFile = proyecto.musicaFondoPath!;
  }

  final nombreFinal =
      'VIDEO_${ts}_${proyecto.formato == '9:16' ? 'vertical' : 'horizontal'}.mp4';
  var conAudio = p.join(tmp.path, 'video_audio_$ts.mp4');

  // Mezcla final: video + voz? + sfx? + musica?
  final insumos = <String>['-i "$sinAudio"'];
  var filtros = <String>[];
  var idx = 1;
  String? vozIdx, sfxIdx, musIdx;
  if (vozTotal != null) {
    insumos.add('-i "$vozTotal"');
    vozIdx = '[$idx:a]';
    idx++;
  }
  if (sfxTotal != null) {
    insumos.add('-i "$sfxTotal"');
    sfxIdx = '[$idx:a]';
    idx++;
  }
  if (musFile != null) {
    insumos.add('-stream_loop -1 -i "$musFile"');
    musIdx = '[$idx:a]';
    idx++;
  }
  if (vozIdx == null && sfxIdx == null && musIdx == null) {
    await File(sinAudio).copy(conAudio);
  } else {
    final vol = proyecto.musicaVolumen.clamp(0.05, 1.0);
    var mezcla = '';
    final entradas = <String>[];
    if (vozIdx != null) {
      entradas.add(vozIdx);
    }
    if (sfxIdx != null) {
      entradas.add(sfxIdx);
    }
    if (musIdx != null) {
      filtros.add('$musIdx volume=$vol[amus]');
      entradas.add('[amus]');
    }
    if (entradas.length == 1) {
      mezcla = '${entradas.first}acopy[aout]';
    } else {
      mezcla = '${entradas.join()}amix=inputs=${entradas.length}:duration=longest[aout]';
    }
    if (filtros.isNotEmpty) {
      filtros.add(mezcla);
    } else {
      filtros = [mezcla];
    }
    onLog?.call('Mezclando musica + SFX...');
    await _run('-y ${insumos.join(' ')} -filter_complex "${filtros.join(';')}" -map 0:v -map "[aout]" -c:v copy -c:a aac -shortest "$conAudio"');
  }

  // Destino: carpeta elegida o Videos
  String destino = conAudio;
  try {
    String? carpeta = proyecto.carpetaDestino;
    if (carpeta == null || carpeta.isEmpty) {
      if (Platform.isWindows) {
        final home = Platform.environment['USERPROFILE'];
        if (home != null) {
          final vids = Directory(p.join(home, 'Videos'));
          carpeta = await vids.exists() ? vids.path : home;
        }
      } else if (Platform.isAndroid) {
        carpeta = (await getExternalStorageDirectory())?.path;
      }
    }
    if (carpeta != null && carpeta.isNotEmpty) {
      final f = File(p.join(carpeta, nombreFinal));
      await File(conAudio).copy(f.path);
      destino = f.path;
    }
  } catch (_) {}
  return destino;
}
