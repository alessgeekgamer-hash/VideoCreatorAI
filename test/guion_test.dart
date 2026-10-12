import 'package:flutter_test/flutter_test.dart';
import 'package:video_creator_ai/services/gemini_service.dart';

void main() {
  test('guion sin key usa plantilla local', () async {
    final g = GeminiService('');
    final esc = await g.generarGuion('dinosaurios para niños', nEscenas: 5);
    expect(esc.length, 5);
    expect(esc.first.narracion.isNotEmpty, true);
    // ignore: avoid_print
    print('OK guion local: ${esc.map((e) => e.titulo).toList()}');
  });

  test('parse guion pegado', () {
    const j = '[{"titulo":"A","narracion":"Hola mundo test","imagePrompt":"dino","sonido":"whoosh","duracion":5}]';
    final esc = GeminiService.parseGuionPegado(j);
    expect(esc.length, 1);
    expect(esc.first.titulo, 'A');
  });

  test('prompt Meta animado incluye animacion', () {
    final scene = (GeminiService.parseGuionPegado(
        '[{"titulo":"T","narracion":"N","imagePrompt":"robot","sonido":"whoosh","duracion":5}]')).first;
    final p = GeminiService.promptMetaAnimado(scene, 'Viral');
    expect(p.contains('ANIMACION'), true);
  });

  test('HF sin token devuelve null', () async {
    final g = GeminiService('');
    final b = await g.generarClipHF('robot', token: '');
    expect(b, null);
  });

  test('stock sin keys devuelve 4 urls sin red', () async {
    final g = GeminiService('');
    final urls = await g.buscarStock('robot');
    expect(urls.length, 4);
  });
}
