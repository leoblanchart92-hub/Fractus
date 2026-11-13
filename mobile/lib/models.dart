// Ce que le PC renvoie (GET /api/status, flux /api/events).

class PcStep {
  PcStep.fromJson(Map j)
      : kind = '${j['kind'] ?? 'note'}',
        text = '${j['text'] ?? ''}',
        detail = j['detail'] as String?,
        at = DateTime.tryParse('${j['at'] ?? ''}') ?? DateTime.now();
  final String kind, text;
  final String? detail;
  final DateTime at;
}

class PcSession {
  PcSession.fromJson(Map j)
      : id = '${j['id'] ?? ''}',
        project = '${j['project'] ?? ''}',
        agent = '${j['agent'] ?? ''}',
        state = '${j['state'] ?? 'idle'}',
        active = j['active'] == true,
        lastStep = j['lastStep'] as String?,
        lastMessage = j['lastMessage'] as String?,
        prompt = j['prompt'] as String?,
        steps = ((j['steps'] as List?) ?? const []).whereType<Map>().map(PcStep.fromJson).toList();

  final String id, project, agent, state;
  final bool active;
  final String? lastStep, lastMessage, prompt;
  final List<PcStep> steps;
}

class PcJournalEntry {
  PcJournalEntry.fromJson(Map j)
      : id = '${j['id'] ?? ''}',
        kind = '${j['kind'] ?? 'action'}',
        label = '${j['label'] ?? ''}',
        detail = j['detail'] as String?,
        path = j['path'] as String?,
        canUndo = j['canUndo'] == true,
        undone = j['undone'] == true,
        at = DateTime.tryParse('${j['at'] ?? ''}') ?? DateTime.now();
  final String id, kind, label;
  final String? detail, path;
  final bool canUndo, undone;
  final DateTime at;
}

class PcConversationMeta {
  PcConversationMeta.fromJson(Map j)
      : id = '${j['id'] ?? ''}',
        title = '${j['title'] ?? ''}',
        count = (j['count'] is num) ? (j['count'] as num).toInt() : 0,
        updated = DateTime.tryParse('${j['updated'] ?? ''}') ?? DateTime.now();
  final String id, title;
  final int count;
  final DateTime updated;
}

class PcSettings {
  PcSettings.fromJson(Map j)
      : model = '${j['model'] ?? ''}',
        effectiveModel = '${j['effectiveModel'] ?? ''}',
        models = ((j['models'] as List?) ?? const []).map((m) => '$m').toList(),
        workspace = '${j['workspace'] ?? ''}',
        baseDir = '${j['baseDir'] ?? ''}',
        webSearch = j['webSearch'] == true,
        muted = j['muted'] == true,
        configured = j['configured'] == true,
        alwaysAllow = ((j['alwaysAllow'] as List?) ?? const []).map((m) => '$m').toList();
  final String model, effectiveModel, workspace, baseDir;
  final List<String> models, alwaysAllow;
  final bool webSearch, muted, configured;
}

class PcQuestion {
  PcQuestion.fromJson(Map j)
      : question = '${j['question'] ?? ''}',
        options = ((j['options'] as List?) ?? const []).map((o) => '$o').toList(),
        header = j['header'] as String?,
        multi = j['multi'] == true;
  final String question;
  final List<String> options;
  final String? header;
  final bool multi;
}

class PcPending {
  PcPending.fromJson(Map j)
      : requestId = '${j['requestId'] ?? ''}',
        project = '${j['project'] ?? ''}',
        tool = '${j['tool'] ?? ''}',
        summary = '${j['summary'] ?? ''}',
        label = '${j['label'] ?? ''}',
        isQuestion = j['isQuestion'] == true,
        preview = j['preview'] as String?,
        questions = ((j['questions'] as List?) ?? const []).whereType<Map>().map(PcQuestion.fromJson).toList();
  final String requestId, project, tool, summary, label;
  final bool isQuestion;
  final String? preview;
  final List<PcQuestion> questions;
}

class PcMessage {
  PcMessage.fromJson(Map j)
      : role = '${j['role'] ?? ''}',
        text = '${j['text'] ?? ''}',
        at = DateTime.tryParse('${j['at'] ?? ''}') ?? DateTime.now();
  final String role, text;
  final DateTime at;
}

class PcStatus {
  PcStatus.fromJson(Map j)
      : version = '${j['version'] ?? ''}',
        host = '${j['host'] ?? ''}',
        botState = '${j['botState'] ?? 'idle'}',
        chatBusy = j['chatBusy'] == true,
        queue = (j['queue'] is num) ? (j['queue'] as num).toInt() : 0,
        sessions = ((j['sessions'] as List?) ?? const []).whereType<Map>().map(PcSession.fromJson).toList(),
        pending = j['pending'] is Map ? PcPending.fromJson(j['pending'] as Map) : null,
        conversationId = '${(j['conversation'] as Map?)?['id'] ?? ''}',
        conversationTitle = '${(j['conversation'] as Map?)?['title'] ?? ''}',
        messages = (((j['conversation'] as Map?)?['messages'] as List?) ?? const []).whereType<Map>().map(PcMessage.fromJson).toList(),
        quickActions = ((j['quickActions'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
        journal = ((j['journal'] as List?) ?? const []).whereType<Map>().map(PcJournalEntry.fromJson).toList(),
        conversations = ((j['conversations'] as List?) ?? const []).whereType<Map>().map(PcConversationMeta.fromJson).toList(),
        settings = j['settings'] is Map ? PcSettings.fromJson(j['settings'] as Map) : null;

  final String version, host, botState;
  final bool chatBusy;
  final int queue;
  final List<PcSession> sessions;
  final PcPending? pending;
  final String conversationId, conversationTitle;
  final List<PcMessage> messages;
  final Map<String, String> quickActions;
  final List<PcJournalEntry> journal;
  final List<PcConversationMeta> conversations;
  final PcSettings? settings;

  /// La session « Fractus » (le chat) s'il y en a une.
  PcSession? get fractus => sessions.where((s) => s.id == 'fractus').firstOrNull;

  String get lastReply {
    for (final m in messages.reversed) {
      if (m.role == 'assistant' && m.text.trim().isNotEmpty && m.text != '…') return m.text;
    }
    return '';
  }
}

/// Libellé et couleur d'un état de Fractus.
String stateLabel(String s) => switch (s) {
      'working' => 'travaille',
      'thinking' => 'réfléchit',
      'searching' => 'cherche',
      'approval' => 'attend ton accord',
      'question' => 'te pose une question',
      'error' => 'a rencontré une erreur',
      'finished' => 'a terminé',
      'ratelimit' => 'attend (quota)',
      'sleeping' => 'dort',
      _ => 'au repos',
    };

int stateColor(String s) => switch (s) {
      'working' => 0xFF3B9EFF,
      'thinking' => 0xFFA78BFA,
      'searching' => 0xFF6366F1,
      'approval' || 'question' => 0xFFF5A524,
      'error' => 0xFFF4505E,
      'finished' => 0xFF34D399,
      'ratelimit' => 0xFFF59E0B,
      _ => 0xFF9398A1,
    };
