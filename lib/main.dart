import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/project.dart';
import 'services/gemini_service.dart';
import 'services/export_facade.dart';
import 'services/export_web.dart' as webmsg;

void main() => runApp(const VideoCreatorApp());

class VideoCreatorApp extends StatelessWidget {
  const VideoCreatorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Creator AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final temaCtrl = TextEditingController(text: 'La historia de la inteligencia artificial');
  final geminiKeyCtrl = TextEditingController();
  final pexelsKeyCtrl = TextEditingController();
  final hfKeyCtrl = TextEditingController();
  String hfModel = 'black-forest-labs/FLUX.1-schnell';
  String hfChatModel = 'meta-llama/Meta-Llama-3.1-8B-Instruct';
  final tonoCtrl = TextEditingController(text: 'divulgativo emocionante');
  final pegarCtrl = TextEditingController();
  int paso = 0;
  bool busy = false;
  bool modoFacil = true;
  String estilo = 'Viral';
  String durPreset = 'Ideal 30s';
  String log = 'Modo Facil: escribe el tema y pulsa Crear mi video. Sin keys usa plantilla narrativa; con token HF gratis genera guion IA real.';
  VideoProject proyecto = VideoProject(tema: '');
  GeminiService gemini = GeminiService('');
  final tts = FlutterTts();
  int nEscenas = 5;

  static const estilos = {
    'Viral': 'ritmo rapido, gancho en 3 segundos, frases cortas, emocionante',
    'Educativo': 'claro y didactico, ejemplos simples, tono amable',
    'Historia': 'narrativo cinematografico, suspenso y emocion',
    'Publicidad': 'persuasivo, beneficios claros, llamada a la accion fuerte',
  };

  void _aplicarPreset() {
    if (durPreset == 'Corto 15s') {
      nEscenas = 3;
      for (final e in proyecto.escenas) {
        e.duracion = 5;
      }
    } else if (durPreset == 'Ideal 30s') {
      nEscenas = 5;
      for (final e in proyecto.escenas) {
        e.duracion = 5;
      }
    } else {
      nEscenas = 7;
      for (final e in proyecto.escenas) {
        e.duracion = 6;
      }
    }
    tonoCtrl.text = estilos[estilo] ?? tonoCtrl.text;
    proyecto.estilo = estilo;
    proyecto.formato = '9:16'; // optimo Shorts/Reels/TikTok por defecto
    proyecto.conTransiciones = true;
    proyecto.sfxAuto = true;
    proyecto.subtitulos = true;
    proyecto.musicaVolumen = 0.15;
  }

  int get nImgOk => proyecto.escenas.where((e) => e.imagenBytes != null).length;
  int get nVozOk => proyecto.escenas
      .where((e) => e.vozBytes != null || e.vozPath != null)
      .length;
  bool get listoExportar =>
      proyecto.escenas.isNotEmpty &&
      proyecto.escenas.every((e) =>
          e.imagenBytes != null || e.clipBytes != null || e.clipPath != null);
  double get progreso {
    if (proyecto.escenas.isEmpty) return 0;
    var p = 0.3; // guion
    p += 0.4 * (nImgOk / proyecto.escenas.length);
    p += 0.2 * (nVozOk / proyecto.escenas.length);
    if (proyecto.musicaFondoBytes != null || proyecto.musicaFondoPath != null) p += 0.1;
    return p.clamp(0, 1);
  }

  String get faltaMsg {
    if (proyecto.escenas.isEmpty) return 'Falta el guion. Pulsa Crear mi video.';
    if (nImgOk < proyecto.escenas.length) {
      return 'Faltan ${proyecto.escenas.length - nImgOk} imagenes. Pulsa Completar lo que falta.';
    }
    if (nVozOk < proyecto.escenas.length) {
      return 'Sin voz en ${proyecto.escenas.length - nVozOk} escenas (opcional: genera o sube, o exporta solo con musica+SFX).';
    }
    return 'Listo para exportar en ${proyecto.formato}.';
  }

  /// Un boton lo hace todo: guion + imagenes + voz (si hay key) + SFX/transiciones.
  Future<void> _crearAutomatico() async {
    if (temaCtrl.text.trim().isEmpty) {
      setState(() => log = 'Escribe primero el tema del video.');
      return;
    }
    _aplicarPreset();
    setState(() { busy = true; log = 'Creando tu video sobre "${temaCtrl.text.trim()}"...'; });
    final esc = await gemini.generarGuion(temaCtrl.text.trim(),
        nEscenas: nEscenas,
        tono: tonoCtrl.text,
        hfToken: hfKeyCtrl.text.trim(),
        hfChatModel: hfChatModel);
    final keep = proyecto;
    proyecto = VideoProject(
        tema: temaCtrl.text.trim(), formato: keep.formato, calidad: keep.calidad)
      ..escenas = esc
      ..estilo = estilo
      ..musicaFondoBytes = keep.musicaFondoBytes
      ..musicaFondoPath = keep.musicaFondoPath
      ..musicaFondoNombre = keep.musicaFondoNombre
      ..conTransiciones = true
      ..sfxAuto = true
      ..subtitulos = keep.subtitulos
      ..carpetaDestino = keep.carpetaDestino;
    // Aplica estilo al prompt de imagen para resultado optimo
    for (final e in proyecto.escenas) {
      e.imagePrompt = '${e.imagePrompt}, estilo $estilo, vertical cinematografico, alta retencion';
      if (durPreset == 'Largo 60s') {
        e.duracion = 6;
      } else {
        e.duracion = 5;
      }
    }
    setState(() => log = 'Guion listo (${esc.length} escenas). Generando imagenes 0/${esc.length}...');
    for (var i = 0; i < proyecto.escenas.length; i++) {
      setState(() => log = 'Guion listo. Generando imagen ${i + 1}/${proyecto.escenas.length}... (puede tardar ~30s c/u)');
      await _genImagenEscena(i, silencioso: true);
      setState(() {});
    }
    if (gemini.tieneKey) {
      setState(() => log = 'Imagenes listas. Generando voces...');
      for (var i = 0; i < proyecto.escenas.length; i++) {
        final b = await gemini.generarVoz(proyecto.escenas[i].narracion);
        if (b != null) {
          proyecto.escenas[i].vozBytes = b;
        }
      }
    } else {
      setState(() => log = 'Imagenes listas. Sin API Key no auto-genero voz: subela o usa Escuchar. SFX y transiciones ya activos.');
    }
    await _guardarDefaults();
    setState(() { busy = false; log = 'Video preparado. $faltaMsg Revisa la vista previa.'; modoFacil = true; });
  }

  Future<void> _completarFaltante() async {
    if (proyecto.escenas.isEmpty) { await _crearAutomatico(); return; }
    setState(() { busy = true; log = 'Completando lo que falta...'; });
    for (var i = 0; i < proyecto.escenas.length; i++) {
      if (proyecto.escenas[i].imagenBytes == null) {
        await _genImagenEscena(i, silencioso: true);
      }
    }
    if (gemini.tieneKey) {
      for (var i = 0; i < proyecto.escenas.length; i++) {
        final e = proyecto.escenas[i];
        if (e.vozBytes == null && e.vozPath == null) {
          final b = await gemini.generarVoz(e.narracion);
          if (b != null) e.vozBytes = b;
        }
      }
    }
    setState(() { busy = false; log = faltaMsg; });
  }

  @override
  void initState() {
    super.initState();
    _cargarKeys();
  }

  Future<void> _cargarKeys() async {
    final sp = await SharedPreferences.getInstance();
    geminiKeyCtrl.text = sp.getString('gemini_key') ?? '';
    pexelsKeyCtrl.text = sp.getString('pexels_key') ?? '';
    hfKeyCtrl.text = sp.getString('hf_key') ?? '';
    estilo = sp.getString('ultimo_estilo') ?? estilo;
    durPreset = sp.getString('ultimo_dur') ?? durPreset;
    final lf = sp.getString('ultimo_formato');
    if (lf == '16:9' || lf == '9:16') {
      proyecto.formato = lf!;
    }
    gemini = GeminiService(geminiKeyCtrl.text);
    if (mounted) setState(() {});
  }

  Future<void> _guardarKeys() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('gemini_key', geminiKeyCtrl.text.trim());
    await sp.setString('pexels_key', pexelsKeyCtrl.text.trim());
    await sp.setString('hf_key', hfKeyCtrl.text.trim());
    gemini = GeminiService(geminiKeyCtrl.text.trim());
    setState(() => log = gemini.tieneKey
        ? 'Claves guardadas. Gemini OK.'
        : 'Sin Gemini: usa token HF para guion IA, o plantilla narrativa desarrollada.');
  }

  /// Manual Meta: copia prompt animado + abre meta.ai con tu cuenta.
  Future<void> _promptMeta(int i) async {
    final p = GeminiService.promptMetaAnimado(proyecto.escenas[i], estilo);
    await Clipboard.setData(ClipboardData(text: p));
    final uri = Uri.parse('https://www.meta.ai/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    setState(() => log = 'Prompt animado escena ${i + 1} copiado. Genera y anima en Meta AI, descarga el clip y pulsa Subir clip.');
  }

  Future<void> _subirClip(int i) async {
    final files = await FilePicker.pickFiles(type: FileType.video);
    if (files.isEmpty) {
      return;
    }
    final f = files.first;
    final b = await f.readAsBytes();
    setState(() {
      proyecto.escenas[i].clipBytes = b;
      proyecto.escenas[i].clipPath = f.path;
      log = 'Clip animado escena ${i + 1}: ${f.name}';
    });
  }

  Future<void> _clipHF(int i) async {
    if (hfKeyCtrl.text.trim().isEmpty) {
      setState(() => log = 'Pega tu token HF (gratis en huggingface.co/settings/tokens) y pulsa Guardar.');
      return;
    }
    setState(() { busy = true; log = 'Generando con Hugging Face escena ${i + 1}...'; });
    final e = proyecto.escenas[i];
    final b = await gemini.generarClipHF(e.imagePrompt.isEmpty ? e.titulo : e.imagePrompt,
        token: hfKeyCtrl.text.trim(), model: hfModel);
    setState(() => busy = false);
    if (b != null) {
      setState(() {
        e.clipBytes = b;
        e.clipPath = null;
        log = 'Clip HF escena ${i + 1} OK (${(b.length / 1024).toStringAsFixed(0)} KB)';
      });
    } else {
      setState(() => log = 'HF no devolvio clip (modelo sin API o token invalido). Usa Prompt Meta + Subir clip.');
    }
  }

  Future<void> _generarGuion() async {
    if (temaCtrl.text.trim().isEmpty) {
      setState(() => log = 'Escribe primero el tema del video.');
      return;
    }
    setState(() { busy = true; log = 'Generando guion (Gemini > HuggingFace > plantilla)...'; });
    final esc = await gemini.generarGuion(temaCtrl.text.trim(),
        nEscenas: nEscenas,
        tono: tonoCtrl.text,
        hfToken: hfKeyCtrl.text.trim(),
        hfChatModel: hfChatModel);
    if (esc.isEmpty) {
      setState(() { busy = false; log = 'No pude generar guion. Revisa tu conexion e intentalo de nuevo.'; });
      return;
    }
    final keep = proyecto;
    proyecto = VideoProject(
        tema: temaCtrl.text.trim(), formato: keep.formato, calidad: keep.calidad)
      ..escenas = esc
      ..musicaFondoBytes = keep.musicaFondoBytes
      ..musicaFondoPath = keep.musicaFondoPath
      ..musicaFondoNombre = keep.musicaFondoNombre
      ..conTransiciones = keep.conTransiciones
      ..sfxAuto = keep.sfxAuto
      ..subtitulos = keep.subtitulos
      ..estilo = estilo
      ..carpetaDestino = keep.carpetaDestino;
    setState(() {
      busy = false;
      log = gemini.tieneKey
          ? 'Guion IA listo: ${esc.length} escenas. Ahora genera las imagenes.'
          : 'Guion plantilla listo (${esc.length} escenas, sin API Key). Para guion IA real: pega key arriba o usa Abrir Gemini. Ahora: Generar todas con IA.';
      paso = 1;
      modoFacil = true; // quedarse en Facil para ver la vista previa
    });
  }

  /// Opcion B sin API: abre Gemini web con tu cuenta y prompt listo.
  Future<void> _abrirGeminiWeb() async {
    final prompt = GeminiService.plantillaGuion(temaCtrl.text.trim().isEmpty ? 'mi tema' : temaCtrl.text.trim(), nEscenas);
    await Clipboard.setData(ClipboardData(text: prompt));
    final uri = Uri.parse('https://gemini.google.com/');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    setState(() => log = 'Prompt copiado. Pegalo en Gemini (con tu cuenta), copia el JSON y pegalo abajo en "Pegar guion".');
  }

  void _usarGuionPegado() {
    final esc = GeminiService.parseGuionPegado(pegarCtrl.text);
    if (esc.isEmpty) {
      setState(() => log = 'No detecto JSON valido. Pide a Gemini: "devuelve SOLO el JSON".');
      return;
    }
    final keep = proyecto;
    proyecto = VideoProject(
        tema: temaCtrl.text.trim(), formato: keep.formato, calidad: keep.calidad)
      ..escenas = esc
      ..musicaFondoBytes = keep.musicaFondoBytes
      ..musicaFondoPath = keep.musicaFondoPath
      ..musicaFondoNombre = keep.musicaFondoNombre
      ..conTransiciones = keep.conTransiciones
      ..sfxAuto = keep.sfxAuto
      ..carpetaDestino = keep.carpetaDestino;
    setState(() { log = 'Guion importado de Gemini web: ${esc.length} escenas.'; paso = 1; });
  }

  Future<void> _elegirCarpeta() async {
    if (kIsWeb) {
      setState(() => log = 'En Web no se puede elegir carpeta: descarga el JSON y exporta en EXE/APK.');
      return;
    }
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Elige carpeta de exportacion');
    if (dir != null) setState(() { proyecto.carpetaDestino = dir; log = 'Carpeta: $dir'; });
  }

  Future<void> _genImagenEscena(int i, {bool silencioso = false}) async {
    if (!silencioso) {
      setState(() { busy = true; log = 'Generando imagen escena ${i + 1} (Gemini > HF > Commons)...'; });
    }
    final e = proyecto.escenas[i];
    final bytes = await gemini.generarImagenIA(
        e.imagePrompt.isEmpty ? e.titulo : e.imagePrompt,
        w: proyecto.formato == '9:16' ? 768 : 1024,
        h: proyecto.formato == '9:16' ? 1280 : 768,
        hfToken: hfKeyCtrl.text.trim(),
        hfModel: hfModel);
    if (!silencioso) {
      setState(() => busy = false);
    }
    if (bytes != null) {
      setState(() {
        e.imagenBytes = bytes;
        e.imagenUrl = null;
        log = 'Imagen ${i + 1} OK (${(bytes.length / 1024).toStringAsFixed(0)} KB)';
      });
    } else {
      setState(() => log = 'Fallo imagen ${i + 1}. Prueba Stock o Subir.');
    }
  }

  Future<void> _genTodasImagenes() async {
    for (var i = 0; i < proyecto.escenas.length; i++) {
      if (proyecto.escenas[i].imagenBytes == null) {
        // ignore: use_build_context_synchronously
        await _genImagenEscena(i);
      }
    }
  }

  Future<void> _subirImagen(int i) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() {
      proyecto.escenas[i].imagenBytes = b;
      proyecto.escenas[i].imagenUrl = null;
    });
  }

  Future<void> _stockImagen(int i) async {
    setState(() { busy = true; log = 'Buscando stock tematico (Pexels > Commons)...'; });
    final e = proyecto.escenas[i];
    final q = e.imagePrompt.isNotEmpty ? e.imagePrompt : '${proyecto.tema} ${e.titulo}';
    final urls = await gemini.buscarStock(q,
        pexelsKey: pexelsKeyCtrl.text.trim());
    setState(() => busy = false);
    if (urls.isEmpty) {
      setState(() => log = 'Sin stock para escena ${i + 1}. Prueba IA o Subir.');
      return;
    }
    final b = await gemini.descargarUrl(urls.first);
    if (b != null) {
      setState(() {
        proyecto.escenas[i].imagenBytes = b;
        log = 'Stock aplicado escena ${i + 1}';
      });
    }
  }

  /// Guarda tema/estilo/formato para reutilizar al crear otro video.
  Future<void> _guardarDefaults() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('ultimo_tema', temaCtrl.text.trim());
    await sp.setString('ultimo_estilo', estilo);
    await sp.setString('ultimo_formato', proyecto.formato);
    await sp.setString('ultimo_dur', durPreset);
  }

  /// Limpia escenas para empezar otro video conservando claves y ajustes.
  void _nuevoVideo() {
    final keep = proyecto;
    proyecto = VideoProject(tema: '', formato: keep.formato, calidad: keep.calidad)
      ..musicaFondoBytes = keep.musicaFondoBytes
      ..musicaFondoPath = keep.musicaFondoPath
      ..musicaFondoNombre = keep.musicaFondoNombre
      ..conTransiciones = keep.conTransiciones
      ..sfxAuto = keep.sfxAuto
      ..subtitulos = keep.subtitulos
      ..estilo = keep.estilo
      ..carpetaDestino = keep.carpetaDestino;
    temaCtrl.clear();
    pegarCtrl.clear();
    setState(() {
      paso = 0;
      modoFacil = true;
      log = 'Listo para otro video: escribe el tema. Claves y ajustes conservados.';
    });
  }

  Future<void> _generarVoz(int i) async {
    final e = proyecto.escenas[i];
    setState(() { busy = true; log = 'Generando voz escena ${i + 1}...'; });
    final b = await gemini.generarVoz(e.narracion);
    setState(() => busy = false);
    if (b != null) {
      setState(() {
        e.vozBytes = b;
        e.vozPath = null;
        log = 'Voz ${i + 1} OK con Gemini TTS';
      });
    } else {
      await tts.setLanguage('es-ES');
      await tts.speak(e.narracion);
      setState(() => log =
          'Sin key Gemini o fallo TTS: previsualizo con voz del sistema. Puedes SUBIR un audio como voz off.');
    }
  }

  Future<void> _subirVoz(int i) async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return;
    final f = files.first;
    final b = await f.readAsBytes();
    setState(() {
      proyecto.escenas[i].vozBytes = b;
      proyecto.escenas[i].vozPath = f.path;
      log = 'Voz subida escena ${i + 1}: ${f.name}';
    });
  }

  Future<void> _escuchar(int i) async {
    await tts.setLanguage('es-ES');
    await tts.speak(proyecto.escenas[i].narracion);
  }

  Future<void> _subirMusica() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return;
    final f = files.first;
    final b = await f.readAsBytes();
    setState(() {
      proyecto.musicaFondoBytes = b;
      proyecto.musicaFondoPath = f.path;
      proyecto.musicaFondoNombre = f.name;
      log = 'Musica fondo: ${f.name}';
    });
  }

  Future<void> _exportar() async {
    if (proyecto.escenas.isEmpty) {
      setState(() => log = 'Primero genera el guion.');
      return;
    }
    if (proyecto.escenas.any((e) =>
        e.imagenBytes == null && e.clipBytes == null && e.clipPath == null)) {
      setState(() => log = 'Falta imagen o clip en alguna escena (usa IA, HF, Meta o Subir).');
      return;
    }
    if (kIsWeb) {
      final j = proyecto.toJsonString();
      final bytes = Uint8List.fromList(utf8.encode(j));
      await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(bytes, name: 'proyecto_video.json', mimeType: 'application/json')],
          text: 'Proyecto Video Creator AI'));
      setState(() => log = webmsg.mensajeWeb());
      return;
    }
    setState(() { busy = true; log = 'Exportando MP4... 1-3 min'; });
    try {
      final out =
          await exportarVideo(proyecto, onLog: (m) => setState(() => log = m));
      setState(() { busy = false; log = 'VIDEO LISTO:\n$out'; });
      await SharePlus.instance
          .share(ShareParams(files: [XFile(out)], text: 'Mi video ${proyecto.tema}'));
    } catch (e) {
      setState(() { busy = false; log = 'Error export: $e'; });
    }
  }

  Future<void> _editarEscena(int i) async {
    final e = proyecto.escenas[i];
    final t = TextEditingController(text: e.titulo);
    final n = TextEditingController(text: e.narracion);
    await showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: Text('Editar escena ${i + 1}'),
              content: SingleChildScrollView(
                  child: Column(children: [
                TextField(controller: t, decoration: const InputDecoration(labelText: 'Titulo')),
                TextField(controller: n, decoration: const InputDecoration(labelText: 'Narracion'), maxLines: 5),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
                ElevatedButton(
                    onPressed: () {
                      setState(() { e.titulo = t.text; e.narracion = n.text; });
                      Navigator.pop(c);
                    },
                    child: const Text('Guardar')),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Creator AI'),
        actions: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Facil'), icon: Icon(Icons.bolt)),
              ButtonSegment(value: false, label: Text('Avanzado'), icon: Icon(Icons.tune)),
            ],
            selected: {modoFacil},
            onSelectionChanged: (s) => setState(() => modoFacil = s.first),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        if (busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: LinearProgressIndicator(value: progreso, minHeight: 8, borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(width: 8),
            Text('${(progreso * 100).toStringAsFixed(0)}%'),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(listoExportar ? Icons.check_circle : Icons.info_outline,
                color: listoExportar ? Colors.green : Colors.orange, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(faltaMsg, style: const TextStyle(fontSize: 12))),
          ]),
        ),
        Expanded(child: modoFacil ? _modoFacil() : _contenido()),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(log, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy
            ? null
            : (modoFacil && !listoExportar ? _completarFaltante : _exportar),
        icon: Icon(modoFacil && !listoExportar ? Icons.auto_fix_high : Icons.movie),
        label: Text(modoFacil && !listoExportar
            ? 'Completar lo que falta'
            : (kIsWeb ? 'Compartir proyecto' : 'Exportar MP4')),
      ),
    );
  }

  Widget _modoFacil() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('¿De que quieres tu video?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: temaCtrl,
          decoration: const InputDecoration(
            labelText: 'Ej: historia de los dinosaurios para niños',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lightbulb),
          ),
          minLines: 1,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        const Text('Estilo (optimiza tono + imagenes)', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8,
          children: estilos.keys.map((e) => ChoiceChip(
            label: Text(e),
            selected: estilo == e,
            onSelected: (_) => setState(() => estilo = e),
          )).toList(),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Formato', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(children: [
                ChoiceChip(label: const Text('📱 9:16 Viral'), selected: proyecto.formato == '9:16', onSelected: (_) => setState(() => proyecto.formato = '9:16')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('🖥 16:9 YouTube'), selected: proyecto.formato == '16:9', onSelected: (_) => setState(() => proyecto.formato = '16:9')),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Corto 15s', 'Ideal 30s', 'Largo 60s'].map((d) => ChoiceChip(
            label: Text(d),
            selected: durPreset == d,
            onSelected: (_) => setState(() => durPreset = d),
          )).toList(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: busy ? null : _crearAutomatico,
            icon: const Icon(Icons.auto_awesome, size: 28),
            label: const Text('CREAR MI VIDEO AUTOMATICO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _generarGuion,
          icon: const Icon(Icons.description),
          label: const Text('Solo generar guion (instantaneo, gratis)'),
        ),
        const SizedBox(height: 4),
        const Text('Hace guion + imagenes + voz (si hay API Key) + SFX + transiciones + subtitulos. Luego solo pulsa Exportar.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        if (proyecto.escenas.isNotEmpty) ...[
          Row(children: [
            const Text('Vista previa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('$nImgOk/${proyecto.escenas.length} imgs · $nVozOk/${proyecto.escenas.length} voces'),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            child: PageView.builder(
              itemCount: proyecto.escenas.length,
              itemBuilder: (c, i) {
                final e = proyecto.escenas[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    if (e.imagenBytes != null)
                      Image.memory(e.imagenBytes!, fit: BoxFit.cover)
                    else
                      Container(color: Colors.grey.shade300, child: const Icon(Icons.image, size: 64)),
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)])),
                        child: Text('${i + 1}/${proyecto.escenas.length} ${e.titulo}\n${e.narracion}',
                            maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _completarFaltante, icon: const Icon(Icons.auto_fix_high), label: const Text('Completar faltante')),
            OutlinedButton.icon(onPressed: _subirMusica, icon: const Icon(Icons.music_note), label: Text(proyecto.musicaFondoNombre ?? 'Añadir musica')),
            OutlinedButton.icon(onPressed: () => setState(() => modoFacil = false), icon: const Icon(Icons.tune), label: const Text('Ajuste fino')),
            OutlinedButton.icon(onPressed: _nuevoVideo, icon: const Icon(Icons.add), label: const Text('Nuevo video')),
          ]),
        ] else ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aun no hay video. Escribe el tema arriba y pulsa CREAR MI VIDEO AUTOMATICO.\n\nOptimo por defecto: 9:16 vertical, 5 escenas x 5s (30s ideal), subtitulos + transiciones + SFX automaticos, musica suave al 15%.'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _contenido() {
    return Stepper(
      currentStep: paso,
      onStepTapped: (i) => setState(() => paso = i),
      onStepContinue: () => setState(() => paso = (paso + 1).clamp(0, 3)),
      onStepCancel: () => setState(() => paso = (paso - 1).clamp(0, 3)),
      steps: [
        Step(
          title: const Text('1. Tema + Guion (API o Web)'),
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: temaCtrl, decoration: const InputDecoration(labelText: 'Tema del video', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: geminiKeyCtrl, decoration: const InputDecoration(labelText: 'Gemini API Key (opcional, auto)', border: OutlineInputBorder(), helperText: 'Gratis en aistudio.google.com/apikey. Si la pegas, todo es automatico.')),
            const SizedBox(height: 8),
            TextField(controller: pexelsKeyCtrl, decoration: const InputDecoration(labelText: 'Pexels Key (opcional, stock)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: hfKeyCtrl, decoration: const InputDecoration(labelText: 'Hugging Face token (opcional, guion + clips)', border: OutlineInputBorder(), helperText: 'Gratis en huggingface.co/settings/tokens. Sin ninguna key igual genera con IA gratis.')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton(onPressed: _guardarKeys, child: const Text('Guardar')),
              DropdownButton<String>(
                  value: hfChatModel,
                  items: const [
                    DropdownMenuItem(value: 'meta-llama/Meta-Llama-3.1-8B-Instruct', child: Text('Llama 3.1 guion')),
                    DropdownMenuItem(value: 'mistralai/Mistral-7B-Instruct-v0.3', child: Text('Mistral guion')),
                    DropdownMenuItem(value: 'Qwen/Qwen2.5-7B-Instruct', child: Text('Qwen guion')),
                  ],
                  onChanged: (v) => setState(() => hfChatModel = v ?? hfChatModel)),
              DropdownButton<String>(
                  value: hfModel,
                  items: const [
                    DropdownMenuItem(value: 'black-forest-labs/FLUX.1-schnell', child: Text('FLUX imagen')),
                    DropdownMenuItem(value: 'stabilityai/stable-diffusion-xl-base-1.0', child: Text('SDXL imagen')),
                  ],
                  onChanged: (v) => setState(() => hfModel = v ?? hfModel)),
              DropdownButton<int>(
                  value: nEscenas,
                  items: [3, 5, 7, 10].map((n) => DropdownMenuItem(value: n, child: Text('$n escenas'))).toList(),
                  onChanged: (v) => setState(() => nEscenas = v ?? 5)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: tonoCtrl, decoration: const InputDecoration(labelText: 'Tono'))),
              const SizedBox(width: 8),
              ElevatedButton.icon(onPressed: busy ? null : _generarGuion, icon: const Icon(Icons.auto_awesome), label: const Text('Guion API')),
            ]),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(color: Colors.deepPurple), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Sin API: usa Gemini con tu cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('1. Abre gemini.google.com (login normal) 2. Pega el prompt copiado 3. Copia el JSON y pegalo abajo', style: TextStyle(fontSize: 12)),
                Row(children: [
                  ElevatedButton.icon(onPressed: _abrirGeminiWeb, icon: const Icon(Icons.open_in_browser), label: const Text('Abrir Gemini')),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Copia prompt auto', style: TextStyle(fontSize: 12))),
                ]),
                TextField(controller: pegarCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Pega aqui el JSON de Gemini web', border: OutlineInputBorder())),
                ElevatedButton(onPressed: _usarGuionPegado, child: const Text('Importar guion pegado')),
              ])),
            const SizedBox(height: 8),
            for (var i = 0; i < proyecto.escenas.length; i++)
              Card(
                  child: ListTile(
                title: Text('${i + 1}. ${proyecto.escenas[i].titulo}'),
                subtitle: Text(proyecto.escenas[i].narracion, maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editarEscena(i)),
              )),
          ]),
        ),
        Step(
          title: const Text('2. Imagenes IA / Stock / Subir'),
          content: Column(children: [
            Row(children: [
              ElevatedButton(onPressed: busy ? null : _genTodasImagenes, child: const Text('Generar todas con IA')),
              const SizedBox(width: 8),
              DropdownButton<String>(
                  value: proyecto.formato,
                  items: const [
                    DropdownMenuItem(value: '16:9', child: Text('16:9 YouTube')),
                    DropdownMenuItem(value: '9:16', child: Text('9:16 TikTok/Reels'))
                  ],
                  onChanged: (v) => setState(() => proyecto.formato = v!)),
            ]),
            for (var i = 0; i < proyecto.escenas.length; i++)
              Card(
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${i + 1}. ${proyecto.escenas[i].titulo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (proyecto.escenas[i].clipBytes != null || proyecto.escenas[i].clipPath != null)
                        const Chip(label: Text('Clip animado OK'), avatar: Icon(Icons.movie, size: 18))
                      else if (proyecto.escenas[i].imagenBytes != null)
                        Image.memory(proyecto.escenas[i].imagenBytes!, height: 160, fit: BoxFit.cover)
                      else
                        const Text('Sin imagen ni clip'),
                      TextField(
                          controller: TextEditingController(text: proyecto.escenas[i].imagePrompt),
                          decoration: const InputDecoration(labelText: 'Prompt imagen'),
                          onChanged: (v) => proyecto.escenas[i].imagePrompt = v,
                          maxLines: 2),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        ElevatedButton(onPressed: busy ? null : () => _genImagenEscena(i), child: const Text('IA')),
                        OutlinedButton(onPressed: busy ? null : () => _stockImagen(i), child: const Text('Stock')),
                        OutlinedButton(onPressed: () => _subirImagen(i), child: const Text('Subir')),
                        OutlinedButton.icon(onPressed: () => _promptMeta(i), icon: const Icon(Icons.open_in_browser, size: 16), label: const Text('Prompt Meta')),
                        OutlinedButton.icon(onPressed: () => _subirClip(i), icon: const Icon(Icons.upload_file, size: 16), label: const Text('Subir clip')),
                        OutlinedButton.icon(onPressed: busy ? null : () => _clipHF(i), icon: const Icon(Icons.smart_toy, size: 16), label: const Text('Clip HF')),
                      ]),
                    ])),
              ),
          ]),
        ),
        Step(
          title: const Text('3. Voz off + Musica + SFX'),
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Musica de fondo (mixto)', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(proyecto.musicaFondoNombre ?? 'Sin musica (puedes subir mp3)'),
                      Row(children: [
                        ElevatedButton(onPressed: _subirMusica, child: const Text('Subir mp3/wav')),
                        Expanded(
                            child: Slider(
                                value: proyecto.musicaVolumen,
                                min: 0.05,
                                max: 1,
                                divisions: 10,
                                label: proyecto.musicaVolumen.toStringAsFixed(2),
                                onChanged: (v) => setState(() => proyecto.musicaVolumen = v))),
                      ]),
                      const Text('Tip: descarga gratis en Pixabay Music / Freesound y subela aqui.', style: TextStyle(fontSize: 12)),
                    ]))),
            for (var i = 0; i < proyecto.escenas.length; i++)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${i + 1}. Voz: ${proyecto.escenas[i].vozBytes != null || proyecto.escenas[i].vozPath != null ? "OK" : "pendiente"} · SFX: ${proyecto.escenas[i].sonidoSugerido}'),
                        TextField(
                            controller: TextEditingController(text: proyecto.escenas[i].narracion),
                            maxLines: 3,
                            decoration: const InputDecoration(labelText: 'Narracion', border: OutlineInputBorder()),
                            onChanged: (v) => proyecto.escenas[i].narracion = v),
                        Wrap(spacing: 6, children: [
                          ElevatedButton(onPressed: busy ? null : () => _generarVoz(i), child: const Text('Voz Gemini')),
                          OutlinedButton(onPressed: () => _escuchar(i), child: const Text('Escuchar')),
                          OutlinedButton(onPressed: () => _subirVoz(i), child: const Text('Subir voz')),
                        ]),
                        Row(children: [
                          const Text('Duracion: '),
                          Expanded(
                              child: Slider(
                                  value: proyecto.escenas[i].duracion,
                                  min: 2,
                                  max: 15,
                                  divisions: 13,
                                  label: '${proyecto.escenas[i].duracion.toStringAsFixed(0)}s',
                                  onChanged: (v) => setState(() => proyecto.escenas[i].duracion = v))),
                        ]),
                      ]))),
          ]),
        ),
        Step(
          title: const Text('4. Exportar MP4 9:16/16:9'),
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tema: ${proyecto.tema} · ${proyecto.escenas.length} escenas · ${proyecto.formato}'),
            Row(children: [
              DropdownButton<String>(
                  value: proyecto.formato,
                  items: const [
                    DropdownMenuItem(value: '16:9', child: Text('16:9 YouTube')),
                    DropdownMenuItem(value: '9:16', child: Text('9:16 TikTok/Reels'))
                  ],
                  onChanged: (v) => setState(() => proyecto.formato = v!)),
              const SizedBox(width: 12),
              DropdownButton<String>(
                  value: proyecto.calidad,
                  items: const [
                    DropdownMenuItem(value: '720p', child: Text('720p rapido')),
                    DropdownMenuItem(value: '1080p', child: Text('1080p Full HD'))
                  ],
                  onChanged: (v) => setState(() => proyecto.calidad = v!)),
            ]),
            SwitchListTile(value: proyecto.conTransiciones, onChanged: (v) => setState(() => proyecto.conTransiciones = v), title: const Text('Transiciones fundido entre escenas')),
            SwitchListTile(value: proyecto.sfxAuto, onChanged: (v) => setState(() => proyecto.sfxAuto = v), title: const Text('SFX automaticos (la app los agrega sola)')),
            Row(children: [
              Expanded(child: Text(proyecto.carpetaDestino ?? 'Carpeta: Videos por defecto', maxLines: 2, overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: _elegirCarpeta, child: const Text('Elegir carpeta')),
            ]),
            const SizedBox(height: 8),
            const Text('Flujo final: imagenes descargadas + unidas + transiciones + voz (subida o IA) + musica (subida) + SFX auto → MP4. Windows/Android: MP4 real. Web: comparte JSON.'),
          ]),
        ),
      ],
    );
  }
}
