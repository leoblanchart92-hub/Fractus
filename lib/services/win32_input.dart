// Deux appels Win32 directs (dart:ffi, sans paquet) :
//   - savoir si un bouton de la souris est enfoncé n'importe où à l'écran
//     (un fichier en train d'être glissé depuis l'Explorateur, par exemple) ;
//   - ouvrir la boîte « Ouvrir » de Windows pour choisir des fichiers.
// Hors Windows, tout répond « non / rien ».

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

class Win32Input {
  Win32Input._();

  static DynamicLibrary? _user32;
  static int Function(int)? _getAsyncKeyState;

  static void _init() {
    if (_user32 != null || !Platform.isWindows) return;
    try {
      _user32 = DynamicLibrary.open('user32.dll');
      _getAsyncKeyState = _user32!.lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState');
    } catch (_) {
      _user32 = null;
    }
  }

  /// Un bouton de la souris (gauche ou droit) est tenu enfoncé, où que soit le curseur.
  static bool mouseButtonHeld() {
    _init();
    final f = _getAsyncKeyState;
    if (f == null) return false;
    try {
      return (f(0x01) & 0x8000) != 0 || (f(0x02) & 0x8000) != 0;
    } catch (_) {
      return false;
    }
  }

  /// La boîte « Ouvrir » de Windows (multi-sélection). Vide si annulée.
  /// Tourne dans un isolat pour ne pas figer l'île pendant qu'elle est ouverte.
  static Future<List<String>> pickFiles({String title = 'Donner des fichiers à Fractus'}) async {
    if (!Platform.isWindows) return const [];
    try {
      return await Isolate.run(() => _openFileDialog(title));
    } catch (_) {
      return const [];
    }
  }
}

// ── OPENFILENAMEW (x64) ───────────────────────────────────────────────────────

final class _OpenFileNameW extends Struct {
  @Uint32()
  external int lStructSize;
  external Pointer<Void> hwndOwner;
  external Pointer<Void> hInstance;
  external Pointer<Utf16> lpstrFilter;
  external Pointer<Utf16> lpstrCustomFilter;
  @Uint32()
  external int nMaxCustFilter;
  @Uint32()
  external int nFilterIndex;
  external Pointer<Utf16> lpstrFile;
  @Uint32()
  external int nMaxFile;
  external Pointer<Utf16> lpstrFileTitle;
  @Uint32()
  external int nMaxFileTitle;
  external Pointer<Utf16> lpstrInitialDir;
  external Pointer<Utf16> lpstrTitle;
  @Uint32()
  external int flags;
  @Uint16()
  external int nFileOffset;
  @Uint16()
  external int nFileExtension;
  external Pointer<Utf16> lpstrDefExt;
  @IntPtr()
  external int lCustData;
  external Pointer<Void> lpfnHook;
  external Pointer<Utf16> lpTemplateName;
  external Pointer<Void> pvReserved;
  @Uint32()
  external int dwReserved;
  @Uint32()
  external int flagsEx;
}

List<String> _openFileDialog(String title) {
  const ofnAllowMultiSelect = 0x200;
  const ofnExplorer = 0x80000;
  const ofnFileMustExist = 0x1000;
  const ofnPathMustExist = 0x800;
  const ofnNoChangeDir = 0x8;
  const ofnHideReadOnly = 0x4;
  const bufferChars = 64 * 1024;

  final ole32 = DynamicLibrary.open('ole32.dll');
  final coInit = ole32.lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>('CoInitializeEx');
  coInit(nullptr, 0x2); // COINIT_APARTMENTTHREADED
  final comdlg = DynamicLibrary.open('comdlg32.dll');
  final getOpenFileName =
      comdlg.lookupFunction<Int32 Function(Pointer<_OpenFileNameW>), int Function(Pointer<_OpenFileNameW>)>('GetOpenFileNameW');

  final ofn = calloc<_OpenFileNameW>();
  final file = calloc<Uint16>(bufferChars);
  final filter = 'Tous les fichiers\u0000*.*\u0000\u0000'.toNativeUtf16();
  final titleP = title.toNativeUtf16();
  try {
    ofn.ref
      ..lStructSize = sizeOf<_OpenFileNameW>()
      ..lpstrFilter = filter
      ..nFilterIndex = 1
      ..lpstrFile = file.cast()
      ..nMaxFile = bufferChars
      ..lpstrTitle = titleP
      ..flags = ofnAllowMultiSelect | ofnExplorer | ofnFileMustExist | ofnPathMustExist | ofnNoChangeDir | ofnHideReadOnly;
    if (getOpenFileName(ofn) == 0) return const [];

    // Résultat : « chemin\0 » (un fichier) ou « dossier\0nom1\0nom2\0\0 » (plusieurs).
    final parts = <String>[];
    var start = 0;
    for (var i = 0; i < bufferChars; i++) {
      if (file[i] == 0) {
        if (i == start) break;
        parts.add(String.fromCharCodes(file.asTypedList(bufferChars).sublist(start, i)));
        start = i + 1;
      }
    }
    if (parts.isEmpty) return const [];
    if (parts.length == 1) return parts;
    final dir = parts.first.endsWith('\\') ? parts.first : '${parts.first}\\';
    return [for (final n in parts.skip(1)) '$dir$n'];
  } finally {
    calloc.free(ofn);
    calloc.free(file);
    calloc.free(filter);
    calloc.free(titleP);
  }
}
