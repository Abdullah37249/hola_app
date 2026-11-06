import 'dart:async';

/// The `type` of every HOLA push this phone receives (on screen or tapped),
/// so the open screens can fetch the change straight away instead of waiting
/// for the next poll.
final pushEvents = StreamController<String>.broadcast();
