// When each translation request runs, so the phone stays responsive.

// Dart imports:
import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// How soon a request is needed.
enum TranslationPriority {
  /// A paragraph on screen.
  visible,

  /// A paragraph the reader is about to reach.
  ahead,

  /// A library book, translated while nobody waits for it.
  background,
}

/// Thrown into a request whose generation was stopped to make room; the
/// scheduler puts the request back in its queue.
class TranslationYielded implements Exception {
  const TranslationYielded();
}

/// Set when the request running now should stop as soon as it can.
class YieldToken {
  bool _yielded = false;
  bool get yielded => _yielded;

  /// Throws [TranslationYielded] once the request has been asked to stop.
  void check() {
    if (_yielded) throw const TranslationYielded();
  }
}

class _Request<T> {
  _Request(this.work, this.priority, this.enqueued);
  final Future<T> Function(YieldToken token) work;
  final TranslationPriority priority;
  final DateTime enqueued;
  final Completer<T> result = Completer<T>();
}

/// Runs one request at a time, most urgent first, with room left for the
/// rest of the phone:
/// - after a request the reader only *might* need soon ([TranslationPriority.ahead])
///   it rests for [aheadRest] times as long as that request took, so the
///   GPU/CPU is busy at most 2/3 of the time while reading;
/// - while the user scrolls or turns pages ([noteInteraction]) nothing new
///   starts until they stop ([interactionQuiet]), so the animation gets the
///   whole GPU; a paragraph on screen waits at most [maxVisibleHold];
/// - a background request in progress is stopped (and queued again) as
///   soon as the reader needs the engine.
///
/// Background requests are paced by their caller, which knows the
/// battery and temperature.
class TranslationScheduler<T> {
  TranslationScheduler({
    this.onYield,
    DateTime Function()? clock,
    this.aheadRest = 0.5,
    this.interactionQuiet = const Duration(milliseconds: 350),
    this.maxVisibleHold = const Duration(seconds: 1),
    this.tick = const Duration(milliseconds: 40),
  }) : _clock = clock ?? DateTime.now;

  /// Stops the generation in progress (the engine's cancel).
  final void Function()? onYield;
  final double aheadRest;
  final Duration interactionQuiet;
  final Duration maxVisibleHold;
  final Duration tick;
  final DateTime Function() _clock;

  final Map<TranslationPriority, Queue<_Request<T>>> _queues = {
    for (final p in TranslationPriority.values) p: Queue<_Request<T>>(),
  };
  bool _working = false;
  bool _closed = false;
  _Request<T>? _current;
  YieldToken? _currentToken;
  DateTime _quietFrom = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _restUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Completer<void>? _wake;

  bool get isIdle => !_working && _queues.values.every((q) => q.isEmpty);

  /// The priority of the request running now, if any.
  TranslationPriority? get running => _current?.priority;

  Future<T> submit(
      Future<T> Function(YieldToken token) work, TranslationPriority priority) {
    if (_closed) return Future.error(StateError('Translator disposed'));
    final request = _Request<T>(work, priority, _clock());
    _queues[priority]!.add(request);
    if (priority != TranslationPriority.background) yieldBackground();
    _wakeUp();
    unawaited(_drain());
    return request.result.future;
  }

  /// The user is scrolling or turning a page.
  void noteInteraction() {
    _quietFrom = _clock().add(interactionQuiet);
    yieldBackground();
  }

  /// Stops a background request in progress; it runs again later.
  void yieldBackground() {
    if (_current?.priority != TranslationPriority.background) return;
    final token = _currentToken;
    if (token == null || token._yielded) return;
    token._yielded = true;
    onYield?.call();
  }

  void _wakeUp() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  _Request<T>? _next() {
    for (final p in TranslationPriority.values) {
      if (_queues[p]!.isNotEmpty) return _queues[p]!.first;
    }
    return null;
  }

  /// When [request] may start: after the interaction pause and, unless it
  /// is on screen, after the rest earned by the last request.
  DateTime _startAt(_Request<T> request) {
    var at = _quietFrom;
    if (request.priority == TranslationPriority.visible) {
      final latest = request.enqueued.add(maxVisibleHold);
      if (at.isAfter(latest)) at = latest;
    } else if (_restUntil.isAfter(at)) {
      at = _restUntil;
    }
    return at;
  }

  Future<void> _drain() async {
    if (_working) return;
    _working = true;
    try {
      while (!_closed) {
        var request = _next();
        if (request == null) break;
        // Wait for its turn; a more urgent request arriving meanwhile
        // goes first.
        while (true) {
          final wait = _startAt(request!).difference(_clock());
          if (wait <= Duration.zero || _closed) break;
          _wake = Completer<void>();
          await Future.any([
            _wake!.future,
            Future<void>.delayed(wait < tick ? wait : tick),
          ]);
          request = _next();
          if (request == null) break;
        }
        if (request == null || _closed) break;
        _queues[request.priority]!.removeFirst();

        final token = YieldToken();
        _current = request;
        _currentToken = token;
        final started = _clock();
        try {
          final value = await request.work(token);
          if (token.yielded) throw const TranslationYielded();
          request.result.complete(value);
        } on TranslationYielded {
          // Back to the front of its queue, to run when there is room.
          _queues[request.priority]!.addFirst(request);
        } catch (e, st) {
          request.result.completeError(e, st);
        } finally {
          _current = null;
          _currentToken = null;
        }
        final took = _clock().difference(started);
        _restUntil = request.priority == TranslationPriority.ahead
            ? _clock().add(took * aheadRest)
            : _clock();
      }
    } finally {
      _working = false;
    }
    // A request submitted while the loop was finishing.
    if (!_closed && _next() != null) unawaited(_drain());
  }

  /// Fails everything queued; the request in progress finishes.
  void close() {
    _closed = true;
    for (final q in _queues.values) {
      for (final r in q) {
        r.result.completeError(StateError('Translator disposed'));
      }
      q.clear();
    }
    _wakeUp();
  }
}

/// CPU threads for the model: the big cores only, leaving the rest for the
/// UI and the system (all cores made the phone stutter). Desktop keeps the
/// runtime's own choice.
int recommendedThreads({int? cores, bool? mobile}) {
  final n = cores ?? Platform.numberOfProcessors;
  final isMobile = mobile ?? (Platform.isAndroid || Platform.isIOS);
  if (!isMobile) return 0;
  if (n >= 8) return 4;
  if (n >= 6) return 3;
  return n >= 4 ? 2 : 1;
}
