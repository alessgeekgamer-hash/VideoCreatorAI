import 'dart:convert';
import 'dart:typed_data';

class VideoScene {
  String titulo;
  String narracion;
  String imagePrompt;
  String sonidoSugerido;
  double duracion;
  Uint8List? imagenBytes;
  String? imagenUrl;
  Uint8List? clipBytes; // clip animado (mp4/webm) manual Meta o HF
  String? clipPath;
  Uint8List? vozBytes;
  String? vozPath;
  String? musicaPath;
  Uint8List? musicaBytes;

  VideoScene({
    required this.titulo,
    required this.narracion,
    required this.imagePrompt,
    required this.sonidoSugerido,
    this.duracion = 5,
    this.imagenBytes,
    this.imagenUrl,
    this.vozBytes,
    this.vozPath,
    this.musicaPath,
    this.musicaBytes,
  });

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'narracion': narracion,
        'imagePrompt': imagePrompt,
        'sonidoSugerido': sonidoSugerido,
        'duracion': duracion,
      };

  factory VideoScene.fromJson(Map<String, dynamic> j) => VideoScene(
        titulo: (j['titulo'] ?? 'Escena').toString(),
        narracion: (j['narracion'] ?? '').toString(),
        imagePrompt: (j['imagePrompt'] ?? j['imagen'] ?? '').toString(),
        sonidoSugerido: (j['sonido'] ?? j['sonidoSugerido'] ?? 'ambiente').toString(),
        duracion: (j['duracion'] is num) ? (j['duracion'] as num).toDouble() : 5,
      );
}

class VideoProject {
  String tema;
  String formato; // '16:9' o '9:16'
  String calidad; // '720p' o '1080p'
  List<VideoScene> escenas = [];
  String? musicaFondoPath;
  Uint8List? musicaFondoBytes;
  String? musicaFondoNombre;
  double musicaVolumen = 0.15;
  String vozTipo = 'gemini'; // gemini | sistema | subida | grabada
  bool conTransiciones = true;
  bool sfxAuto = true;
  bool subtitulos = true;
  String estilo = 'Viral';
  String? carpetaDestino;

  VideoProject({required this.tema, this.formato = '9:16', this.calidad = '720p'});

  Map<String, dynamic> toJson() => {
        'tema': tema,
        'formato': formato,
        'calidad': calidad,
        'escenas': escenas.map((e) => e.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());
}
