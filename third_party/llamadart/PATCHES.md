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
