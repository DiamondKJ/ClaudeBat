# D3 Model Identity Decision

Decision: use the API model ID as SwiftUI row identity; use a deterministic offset/name fallback only when the API omits an ID. Legacy Opus/Sonnet rows receive fixed legacy IDs.

Reason: `ForEach(..., id: \.label)` collapses duplicate display labels and can retain the wrong row during reorder/account changes. Display text is not identity.

Evidence: `weeklyModelBreakdown_duplicateLabelsKeepStableModelIdentity` constructs two `Fable` rows with IDs `model-a` and `model-b`, reverses them, and verifies both identities remain distinct and follow the API rows.
