// esca-voiced as this application sees it. vn.sparc.esca.Voice1 on the
// system bus.

import 'dart:async';
import 'dart:collection';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

class Transcript {
  const Transcript({
    required this.text,
    required this.language,
    required this.confidence,
    required this.ms,
    required this.at,
  });

  final String text;
  final String language;
  final double confidence;
  final double ms;
  final DateTime at;
}

/// What the service publishes, as plain events.
sealed class VoiceEvent {}

class PhaseChanged extends VoiceEvent {
  PhaseChanged(this.phase);
  final String phase;
}

class LevelSample extends VoiceEvent {
  LevelSample(this.db, this.floorDb);
  final double db;
  final double floorDb;
}

class SpeechBoundary extends VoiceEvent {
  SpeechBoundary({required this.started});
  final bool started;
}

class Heard extends VoiceEvent {
  Heard(this.transcript);
  final Transcript transcript;
}

class Fault extends VoiceEvent {
  Fault(this.message);
  final String message;
}

abstract interface class VoiceBackend {
  /// The phase the service is in right now.
  Future<String> phase();

  Future<void> startListening();
  Future<void> stopListening();
  Future<void> say(String text);

  Stream<VoiceEvent> get events;

  Future<void> dispose();
}

class DBusVoiceBackend implements VoiceBackend {
  DBusVoiceBackend() : _client = DBusClient.system() {
    _object =
        DBusRemoteObject(_client, name: _interface, path: DBusObjectPath('/vn/sparc/esca/Voice1'));
  }

  static const _interface = 'vn.sparc.esca.Voice1';

  // The system bus, explicitly: under Weston the default is the session bus.
  final DBusClient _client;
  late final DBusRemoteObject _object;

  @override
  Future<String> phase() async {
    final reply = await _object.callMethod(_interface, 'GetState', const [],
        replySignature: DBusSignature('(bsd)'));
    return (reply.values.first as DBusStruct).children[1].asString();
  }

  Future<void> _call(String method, [List<DBusValue> args = const []]) =>
      _object.callMethod(_interface, method, args, replySignature: DBusSignature('i'));

  @override
  Future<void> startListening() => _call('StartListening');

  @override
  Future<void> stopListening() => _call('StopListening');

  @override
  Future<void> say(String text) => _call('Say', [DBusString(text)]);

  Stream<DBusSignal> _signal(String name, String signature) => DBusRemoteObjectSignalStream(
      object: _object, interface: _interface, name: name, signature: DBusSignature(signature));

  @override
  Stream<VoiceEvent> get events {
    final controller = StreamController<VoiceEvent>();
    final subscriptions = <StreamSubscription<DBusSignal>>[
      _signal('StateChanged', 's')
          .listen((s) => controller.add(PhaseChanged(s.values[0].asString()))),
      _signal('Level', 'dd').listen(
          (s) => controller.add(LevelSample(s.values[0].asDouble(), s.values[1].asDouble()))),
      _signal('SpeechStarted', 't').listen((_) => controller.add(SpeechBoundary(started: true))),
      _signal('SpeechEnded', 'td').listen((_) => controller.add(SpeechBoundary(started: false))),
      _signal('Transcript', 'tssdd').listen((s) => controller.add(Heard(Transcript(
            text: s.values[1].asString(),
            language: s.values[2].asString(),
            confidence: s.values[3].asDouble(),
            ms: s.values[4].asDouble(),
            at: DateTime.now(),
          )))),
      _signal('FaultEvent', 'ss').listen(
          (s) => controller.add(Fault('${s.values[0].asString()}: ${s.values[1].asString()}'))),
    ];
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  @override
  Future<void> dispose() => _client.close();
}

class VoiceController extends ChangeNotifier {
  VoiceController(this._backend) {
    _events = _backend.events.listen(_onEvent, onError: (_) {});
    _loadPhase();
  }

  /// Matches esca-voiced's --wait: how long it listens for someone to start
  /// talking before giving up. Only used to draw the countdown; the service
  /// owns the decision.
  static const waitForSpeech = Duration(seconds: 20);

  /// Six seconds of the 20 Hz level stream.
  static const levelHistory = 120;

  final VoiceBackend _backend;
  late final StreamSubscription<VoiceEvent> _events;

  String _phase = 'idle';
  bool _speaking = false;
  String _error = '';
  double _floorDb = -90;
  DateTime? _listeningSince;
  final _levels = ListQueue<double>();
  final _heard = ListQueue<Transcript>();

  /// Ticks on every level sample. The waveform repaints from it on its own,
  /// so twenty samples a second do not rebuild the rest of the screen.
  final levelTick = ValueNotifier<int>(0);

  /// idle, preparing, prompting, listening or transcribing.
  String get phase => _phase;
  bool get speaking => _speaking;
  String get error => _error;
  double get floorDb => _floorDb;
  DateTime? get listeningSince => _listeningSince;
  List<double> get levels => List.unmodifiable(_levels);

  /// Newest first.
  List<Transcript> get heard => List.unmodifiable(_heard);
  Transcript? get latest => _heard.isEmpty ? null : _heard.first;

  Future<void> _loadPhase() async {
    try {
      _setPhase(await _backend.phase());
    } catch (e) {
      _error = 'Không liên lạc được esca-voiced. Dịch vụ đã được bật chưa?';
    }
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      _error = 'Không liên lạc được esca-voiced';
      notifyListeners();
    }
  }

  /// Only from idle: a press while something is in flight would queue a
  /// second session behind the first.
  Future<void> talk() async {
    if (_phase != 'idle') return;
    _error = '';
    notifyListeners();
    await _guard(_backend.startListening);
  }

  Future<void> stop() => _guard(_backend.stopListening);

  Future<void> sayBack([Transcript? transcript]) async {
    final text = (transcript ?? latest)?.text ?? '';
    if (text.isEmpty) return;
    await _guard(() => _backend.say(text));
  }

  void _setPhase(String phase) {
    if (phase == _phase) return;
    _phase = phase;
    if (phase == 'listening') {
      _levels.clear();
      _error = '';
      _listeningSince = DateTime.now();
    } else {
      _listeningSince = null;
      _speaking = false;
    }
  }

  void _onEvent(VoiceEvent event) {
    switch (event) {
      case PhaseChanged(:final phase):
        _setPhase(phase);
      case LevelSample(:final db, :final floorDb):
        _floorDb = floorDb;
        _levels.addLast(db);
        while (_levels.length > levelHistory) {
          _levels.removeFirst();
        }
        levelTick.value++;
        return; // the waveform repaints itself; nothing else changed
      case SpeechBoundary(:final started):
        _speaking = started;
      case Heard(:final transcript):
        _heard.addFirst(transcript);
        while (_heard.length > 8) {
          _heard.removeLast();
        }
      case Fault(:final message):
        _error = message;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _events.cancel();
    levelTick.dispose();
    _backend.dispose();
    super.dispose();
  }
}
