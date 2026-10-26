import 'dart:js_interop';

import 'model.dart';

@JS('__dampedState')
external set stateReader(JSFunction value);
void installBridge(OscillatorState Function() read) {
  stateReader = (() => read().toJson().jsify()).toJS;
}
