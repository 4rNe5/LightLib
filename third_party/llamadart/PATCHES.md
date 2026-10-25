# Local changes to llamadart 0.15.6

LightLib uses this copy (see `dependency_overrides` in the app's
pubspec.yaml) for one change:

- **Reused system message (LiteRT-LM).** A greedy request whose system
  message, template and sampler match the previous one starts from a clone
  (`litert_lm_conversation_clone`) of a conversation kept unsent with that
  system message, instead of a new conversation that reads it again.
  `lib/src/backends/litert_lm/litert_lm_runtime.dart`
  (`keepConversationAsBase`, `useBaseConversation`, `conversationClone`) and
  `lib/src/backends/litert_lm/litert_lm_service.dart` (`createConversation`
  in the native chat path).

Everything else is the published package, unchanged.

- **Timings for LightLib's generation log (LiteRT-LM).** The performance
  context of a native chat request reports, in fields LiteRT-LM leaves
  unused: `loadMs` the time to the first token, `sampleMs` how long the
  conversation took to make or clone, and `reusedGraphs` how it was made
  (0 new, 1 cloned, 2 base made then cloned). `litert_lm_service.dart`.
  (A cloned conversation's prefill turn counts the cloned tokens too, at a
  rate that reflects the time it really took.)
