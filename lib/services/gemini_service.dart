import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/project.dart';

class GeminiService {
  final String apiKey;
  GeminiService(this.apiKey);

  bool get tieneKey => apiKey.trim().isNotEmpty;

  static String plantillaGuion(String tema, int nEscenas) {
    return '''Crea un guion para video sobre "$tema" en $nEscenas escenas.
Devuelve SOLO un JSON valido, sin markdown, con este formato:
[{"titulo":"...","narracion":"texto voz en off 30-40 palabras","imagePrompt":"prompt imagen en ingles, cinematico","sonido":"keyword efecto sonido en ingles","duracion":5}]''';
  }

  Future<List<VideoScene>> generarGuion(String tema,
      {int nEscenas = 5,
      String tono = 'divulgativo emocionante',
      String hfToken = '',
      String hfChatModel = 'meta-llama/Meta-Llama-3.1-8B-Instruct'}) async {
    // 1. Gemini API (mejor calidad)
    if (tieneKey) {
      try {
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');
        final prompt =
            'Tema: $tema. Tono: $tono. ${plantillaGuion(tema, nEscenas)}';
        final r = await http
            .post(url,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'contents': [
                    {
                      'parts': [
                        {'text': prompt}
                      ]
                    }
                  ],
                  'generationConfig': {'temperature': 0.8}
                }))
            .timeout(const Duration(seconds: 60));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          String txt = '';
          try {
            txt = (data['candidates'][0]['content']['parts'] as List)
                .map((p) => p['text'] ?? '')
                .join();
          } catch (_) {}
          final esc = parseGuionPegado(txt);
          if (esc.isNotEmpty) {
            return esc;
          }
        }
      } catch (_) {}
    }
    // 2. Hugging Face con token (IA real, modelos abiertos)
    if (hfToken.trim().isNotEmpty) {
      final esc = await _guionHF(tema, nEscenas, tono,
          token: hfToken, model: hfChatModel);
      if (esc.isNotEmpty) {
        return esc;
      }
    }
    // 3. Pollinations texto gratis sin key (IA real con limite)
    final escP = await _guionPollinations(tema, nEscenas, tono);
    if (escP.isNotEmpty) {
      return escP;
    }
    // 4. Plantilla local enriquecida (siempre funciona)
    return _guionLocal(tema, nEscenas);
  }

  /// Hugging Face Inference API: guion con modelo de chat abierto.
  Future<List<VideoScene>> _guionHF(String tema, int n, String tono,
      {required String token, required String model}) async {
    try {
      final url = Uri.parse('https://api-inference.huggingface.co/models/$model');
      final prompt =
          'Tema: $tema. Tono: $tono. ${plantillaGuion(tema, n)}';
      final r = await http
          .post(url,
              headers: {
                'Authorization': 'Bearer ${token.trim()}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'inputs': prompt,
                'parameters': {'max_new_tokens': 1500, 'temperature': 0.8, 'return_full_text': false}
              }))
          .timeout(const Duration(seconds: 120));
      if (r.statusCode != 200) {
        return [];
      }
      String txt = '';
      try {
        final d = jsonDecode(r.body);
        if (d is List && d.isNotEmpty) {
          txt = (d[0]['generated_text'] ?? '').toString();
        } else if (d is Map) {
          txt = (d['generated_text'] ?? d['choices'].toString()).toString();
        }
      } catch (_) {
        txt = r.body;
      }
      return parseGuionPegado(txt);
    } catch (_) {
      return [];
    }
  }

  /// Pollinations texto gratis sin key.
  Future<List<VideoScene>> _guionPollinations(
      String tema, int n, String tono) async {
    try {
      final prompt =
          'Tema: $tema. Tono: $tono. ${plantillaGuion(tema, n)} Responde SOLO el JSON.';
      final u = Uri.parse(
          'https://text.pollinations.ai/${Uri.encodeComponent(prompt)}?model=openai');
      final r = await http.get(u).timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) {
        return [];
      }
      return parseGuionPegado(r.body);
    } catch (_) {
      return [];
    }
  }

  /// Prompt optimizado para generar imagen ANIMADA en Meta AI (manual).
  /// Devuelve texto listo para pegar en meta.ai (Imagine + Animate).
  static String promptMetaAnimado(VideoScene e, String estilo) {
    return '''${e.imagePrompt}, estilo $estilo, cinematografico vertical.
ANIMACION: movimiento de camara lento push-in, ${e.sonidoSugerido}, duracion 5 segundos, loop suave, alta calidad.
EN: animate this image, slow cinematic push-in, subtle motion, 5s seamless loop.''';
  }

  /// Hugging Face Inference: imagen (y video si el modelo lo soporta).
  /// Requiere token gratis de huggingface.co/settings/tokens.
  Future<Uint8List?> generarClipHF(String prompt,
      {required String token,
      String model = 'black-forest-labs/FLUX.1-schnell'}) async {
    if (token.trim().isEmpty) {
      return null;
    }
    try {
      final url =
          Uri.parse('https://api-inference.huggingface.co/models/$model');
      final r = await http
          .post(url,
              headers: {
                'Authorization': 'Bearer ${token.trim()}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'inputs': prompt}))
          .timeout(const Duration(seconds: 120));
      final ct = r.headers['content-type'] ?? '';
      if (r.statusCode == 200 &&
          (ct.contains('image') || ct.contains('video') || ct.contains('octet')) &&
          r.bodyBytes.length > 5000) {
        return r.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Parsea un JSON pegado desde Gemini web (sin API).
  static List<VideoScene> parseGuionPegado(String texto, {int defN = 5}) {
    try {
      var t = texto.replaceAll('```json', '').replaceAll('```', '').trim();
      final ini = t.indexOf('[');
      final fin = t.lastIndexOf(']');
      if (ini < 0 || fin < 0) return [];
      final arr = jsonDecode(t.substring(ini, fin + 1)) as List;
      return arr.map((e) => VideoScene.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  List<VideoScene> _guionLocal(String tema, int n) {
    // Estructura narrativa desarrollada: gancho, contexto, mecanismo,
    // ejemplo, error comun, dato curioso, aplicacion, futuro, resumen, CTA.
    final beats = [
      ('El dato que nadie te cuenta sobre $tema',
          'Para de scrollear: el noventa por ciento de lo que crees saber sobre $tema esta incompleto. Hoy te revelo el dato que cambia todo, explicado paso a paso y con ejemplos que si se entienden. Quedate, porque el final te va a sorprender.',
          'cinematic hook mysterious about $tema, dramatic light', 'intro whoosh'),
      ('De donde viene $tema realmente',
          'Para entender $tema hay que viajar al origen. Nacio de una necesidad concreta, evoluciono con errores y aciertos, y lo que ves hoy es solo la punta del iceberg. Te cuento el contexto justo para que todo lo demas tenga sentido.',
          'vintage origin story of $tema, documentary style', 'soft ambient pad'),
      ('Como funciona $tema, sin tecnicismos',
          'Aqui esta la clave: $tema funciona en tres pasos simples. Primero detecta lo importante, luego lo procesa, y al final te entrega un resultado util. Entender este mecanismo te pone por delante del noventa por ciento de la gente.',
          'diagram mechanism of $tema glowing, educational', 'subtle riser'),
      ('Ejemplo real que lo deja clarisimo',
          'Vamos a lo concreto con un ejemplo de la vida real. Imagina que aplicas $tema a tu dia a dia: el cambio se nota en cuestion de dias. Te muestro exactamente como se ve, para que puedas replicarlo hoy mismo sin complicaciones.',
          'real life example of $tema, relatable scene', 'pop success'),
      ('El error que todos cometen con $tema',
          'Cuidado: casi todos fallan en $tema por el mismo error, y es evitable. Te explico cual es, por que pasa, y el ajuste de treinta segundos que lo corrige. Si evitas esto, tus resultados se multiplican.',
          'warning mistake red alert about $tema', 'tension riser'),
      ('El dato curioso que pocos conocen',
          'Dato curioso: hay un detalle de $tema que casi nadie menciona y lo cambia todo. Cuando lo descubrieron, los expertos tuvieron que reescribir lo que creian. Te lo revelo con numeros claros y sin humo.',
          'surprising curious fact about $tema, wow moment', 'ding pop'),
      ('Como aplicarlo hoy mismo, paso a paso',
          'Pasemos a la accion con $tema. Paso uno: define tu objetivo en una frase. Paso dos: aplica la tecnica principal durante cinco minutos. Paso tres: mide el resultado y ajusta. Simple, rapido y efectivo desde hoy.',
          'hands applying $tema step by step, tutorial', 'click pop'),
      ('Lo que viene: el futuro de $tema',
          'Y esto apenas empieza: $tema va a cambiar mucho mas en los proximos meses. Te adelanto las tres tendencias que ya se ven venir, para que llegues preparado mientras otros aun ni se enteran.',
          'futuristic vision of $tema, neon tomorrow', 'epic riser'),
      ('Resumen en 20 segundos',
          'Recapitulemos: $tema se entiende por su origen, su mecanismo simple y su aplicacion practica. Evita el error comun, aplica los tres pasos, y mira al futuro con ventaja. Todo lo importante, en veinte segundos.',
          'summary recap collage of $tema', 'soft ambient pad'),
      ('Tu turno: actua ahora',
          'Si este video sobre $tema te sirvio, guardalo y compartelo con alguien que lo necesite. Escribeme en comentarios que tema quieres que explique despues, y suscribete para no perderte el proximo. Nos vemos ahi.',
          'call to action subscribe about $tema, energetic', 'outro whoosh'),
    ];
    return List.generate(n, (i) {
      final b = beats[i % beats.length];
      return VideoScene(
        titulo: b.$1,
        narracion: b.$2,
        imagePrompt: '${b.$3}, ultra detailed, 16k',
        sonidoSugerido: b.$4,
        duracion: 5,
      );
    });
  }

  /// Imagen con Gemini, luego HF con token (IA real gratis), luego Commons/picsum.
  Future<Uint8List?> generarImagenIA(String prompt,
      {int w = 1024, int h = 1024, String hfToken = '', String hfModel = ''}) async {
    if (tieneKey) {
      try {
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-preview-image-generation:generateContent?key=$apiKey');
        final r = await http
            .post(url,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'contents': [
                    {
                      'parts': [
                        {'text': 'Generate image: $prompt, high quality'}
                      ]
                    }
                  ],
                  'generationConfig': {
                    'responseModalities': ['TEXT', 'IMAGE']
                  }
                }))
            .timeout(const Duration(seconds: 90));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          final parts =
              data['candidates'][0]['content']['parts'] as List<dynamic>;
          for (final p in parts) {
            if (p is Map && p['inlineData'] != null) {
              final b64 = p['inlineData']['data'] as String;
              return base64Decode(b64);
            }
          }
        }
      } catch (_) {}
    }
    // Hugging Face con token: IA real gratis (FLUX/SDXL)
    if (hfToken.trim().isNotEmpty && hfModel.trim().isNotEmpty) {
      final b = await generarClipHF(prompt, token: hfToken, model: hfModel);
      if (b != null && b.length > 5000) {
        return b;
      }
    }
    // Fallback Pollinations (gratis con limite) -> Commons tematico -> picsum
    try {
      final enc = Uri.encodeComponent(prompt);
      final u = Uri.parse(
          'https://image.pollinations.ai/prompt/$enc?width=$w&height=$h&nologo=true&seed=${DateTime.now().millisecondsSinceEpoch % 100000}');
      final r = await http.get(u).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200 && r.bodyBytes.length > 5000) {
        return r.bodyBytes;
      }
    } catch (_) {}
    try {
      final cu = await _stockCommons(prompt, 1);
      if (cu.isNotEmpty) {
        final b = await descargarUrl(cu.first);
        if (b != null && b.length > 5000) {
          return b;
        }
      }
    } catch (_) {}
    try {
      final u = Uri.parse(
          'https://picsum.photos/seed/${prompt.hashCode.abs() % 100000}/$w/$h');
      final r = await http.get(u).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200 && r.bodyBytes.length > 5000) {
        return r.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Stock gratis via Pollinations/Unsplash source como alternativa sin key.
  /// Si hay pexelsKey, usa Pexels API.
  Future<List<String>> buscarStock(String query,
      {String pexelsKey = '', int n = 4}) async {
    if (pexelsKey.trim().isNotEmpty) {
      try {
        final u = Uri.parse(
            'https://api.pexels.com/v1/search?query=${Uri.encodeComponent(query)}&per_page=$n&orientation=landscape');
        final r = await http.get(u, headers: {'Authorization': pexelsKey});
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          final photos = d['photos'] as List;
          final out = photos
              .map((p) => (p['src']['large'] ?? '') as String)
              .where((s) => s.isNotEmpty)
              .toList();
          if (out.isNotEmpty) {
            return out;
          }
        }
      } catch (_) {}
    }
    // Wikimedia Commons: tematico y gratis sin key
    final commons = await _stockCommons(query, n);
    if (commons.isNotEmpty) {
      return commons;
    }
    // Sin key: genera URLs Pollinations variadas (con limite) + picsum
    return List.generate(
        n,
        (i) => i.isEven
            ? 'https://image.pollinations.ai/prompt/${Uri.encodeComponent('$query cinematic photo $i')}?width=1024&height=1024&nologo=true&seed=$i'
            : 'https://picsum.photos/seed/${'$query $i'.hashCode.abs() % 100000}/1024/1024');
  }

  /// Busca imagenes tematicas en Wikimedia Commons (gratis, sin key).
  Future<List<String>> _stockCommons(String query, int n) async {
    try {
      final u = Uri.parse(
          'https://commons.wikimedia.org/w/api.php?action=query&format=json'
          '&generator=search&gsrsearch=${Uri.encodeComponent(query)}&gsrnamespace=6&gsrlimit=20'
          '&prop=imageinfo&iiprop=url|size&iiurlwidth=1024&origin=*');
      final r = await http.get(u,
          headers: {'User-Agent': 'VideoCreatorAI/1.0'}).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) {
        return [];
      }
      final d = jsonDecode(r.body);
      final pages = (d['query']?['pages'] as Map?) ?? {};
      final out = <String>[];
      for (final pg in pages.values) {
        final t = ((pg as Map)['title'] ?? '').toString().toLowerCase();
        if (t.endsWith('.pdf') ||
            t.endsWith('.svg') ||
            t.endsWith('.gif') ||
            t.endsWith('.tif') ||
            t.endsWith('.tiff') ||
            t.endsWith('.webp') ||
            t.endsWith('.ogg') ||
            t.endsWith('.webm')) {
          continue;
        }
        for (final ii in ((pg['imageinfo'] as List?) ?? [])) {
          if (((ii as Map)['width'] ?? 0) is int && (ii['width'] as int) < 500) {
            continue;
          }
          final url = (ii['thumburl'] ?? ii['url'] ?? '').toString();
          if (url.isNotEmpty && !url.contains('.pdf')) {
            out.add(url);
          }
          if (out.length >= n) {
            return out;
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> descargarUrl(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) return r.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// Voz en off con Gemini TTS. Devuelve WAV bytes o null.
  Future<Uint8List?> generarVoz(String texto,
      {String voz = 'Kore', String lang = 'es'}) async {
    if (!tieneKey) return null;
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$apiKey');
      final r = await http
          .post(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': texto}
                    ]
                  }
                ],
                'generationConfig': {
                  'responseModalities': ['AUDIO'],
                  'speechConfig': {
                    'voiceConfig': {
                      'prebuiltVoiceConfig': {'voiceName': voz}
                    }
                  }
                }
              }))
          .timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      final parts = data['candidates'][0]['content']['parts'] as List;
      for (final p in parts) {
        if (p is Map && p['inlineData'] != null) {
          return base64Decode(p['inlineData']['data'] as String);
        }
      }
    } catch (_) {}
    return null;
  }
}
