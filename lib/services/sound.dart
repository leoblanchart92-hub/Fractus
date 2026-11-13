// Les sons de l'île. Les 28 sons de Coucou sont © Louis Raillé et ne sont pas
// repris ici : Fractus est silencieux par défaut. Pour ajouter les vôtres,
// branchez un lecteur audio (ex. le paquet `audioplayers`) dans `play` et
// déposez `greet.wav`, `approval.wav`, `finish.wav`… dans `assets/sounds/`.

class Sound {
  Sound._();

  static const List<String> names = [
    'greet', 'work', 'think', 'search', 'approval', 'question', 'error', 'finish',
    'rate', 'sleep', 'dizzy', 'slap', 'annoyed', 'allow', 'deny', 'open', 'close',
  ];

  static void Function(String name)? player;

  static void play(String name, {bool muted = false}) {
    if (muted) return;
    player?.call(name);
  }
}
