# Video Creator AI — EXE · APK · Web

App Flutter única que genera las 3 versiones.

## Flujo
1. Escribes un **tema** → **Guion** automático en 3-10 escenas (titulo, narración, prompt imagen, SFX sugerido, duración editable).
   - Con **Gemini API Key** (gratis en https://aistudio.google.com/apikey): guion real con `gemini-2.0-flash`.
   - Sin key: plantilla local funcional.
   - OJO: tu suscripción **Plus no sirve** como API. Debes crear la key gratuita de AI Studio y pegarla en la app (se guarda local).
2. **Imágenes** por escena, 3 vías:
   - **IA Gemini** (`gemini-2.0-flash-preview-image-generation`) → fallback gratis **Pollinations.ai** sin key.
   - **Stock**: Pexels si pegas key, si no Pollinations como stock gratis.
   - **Subir** desde galería (image_picker).
3. **Voz en off** por escena:
   - **Generar con Gemini TTS** (`gemini-2.5-flash-preview-tts`, voz Kore).
   - **Escuchar** con TTS del sistema.
   - **Subir** mp3/wav propio.
4. **Música (mixto)**:
   - Subir mp3/wav + volumen ajustable.
   - Tip: descarga gratis en Pixabay Music / Freesound y súbela. Biblioteca en `assets/`.
   - **Efectos**: sugerencia automática por escena (keyword en inglés) — súbelos como voz/música o mézclalos en export.
5. **Exportar MP4**:
   - Formato **16:9 (1920x1080)** y **9:16 (1080x1920)**, 720p/1080p.
   - **Windows/Android**: MP4 real con FFmpeg (loop imagen + concat + mezcla voz + música fondo con `amix`).
   - **Web**: los navegadores no permiten FFmpeg MP4 nativo → la web crea todo y **comparte proyecto JSON** para abrir en EXE/APK y exportar MP4 allí.

## Compilar
```
build_video_creator_windows.bat  → build\windows\x64\runner\Release\video_creator_ai.exe
build_video_creator_android.bat  → build\app\outputs\flutter-apk\app-release.apk
build_video_creator_web.bat      → build\web
```

## Probar rápido sin keys
1. `cd video_creator_ai && flutter run -d chrome` (o windows)
2. Tema → Generar guion → Generar todas con IA (usa Pollinations gratis)
3. Voz → Escuchar / Subir, Música → Subir mp3
4. Exportar (en Windows genera MP4 en carpeta Videos).

## Estructura
- `lib/main.dart` — wizard 4 pasos
- `lib/models/project.dart` — VideoScene/VideoProject
- `lib/services/gemini_service.dart` — guion, imagen, stock, TTS
- `lib/services/export_io.dart` — FFmpeg Windows/Android
- `lib/services/export_web.dart` — mensaje + JSON en Web
- `lib/services/export_facade*.dart` — import condicional para que Web compile sin dart:io
