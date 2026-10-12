import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_creator_ai/main.dart';

void main() {
  testWidgets('Generar guion gratis muestra vista previa', (tester) async {
    await tester.pumpWidget(const VideoCreatorApp());
    await tester.pumpAndSettle();
    // Modo Facil por defecto: lleva el boton a pantalla y pulsa Solo generar guion
    final btn = find.text('Solo generar guion (instantaneo, gratis)');
    expect(btn, findsOneWidget);
    await tester.dragUntilVisible(
      btn,
      find.byType(SingleChildScrollView).first,
      const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(btn, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Vista previa'), findsOneWidget);
    expect(find.textContaining('El dato que nadie'), findsWidgets);
  });
}
