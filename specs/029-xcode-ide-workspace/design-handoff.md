# Design Handoff Inventory

Local plan only; no Figma files or images generated. Use source section14 for a later external handoff.

Pages: Tokens, Components, Shell, Editor, Devices, Signing, Console, Onboarding, Error States, Responsive Layouts. Source sections2.1–2.4 provide all semantic/syntax colors, typography, spacing, radii, icons, dimensions and motion. Original assets and licensed Inter/JetBrains Mono only.

Cover all22 component roles with Flutter-aligned names such as `XButton/Primary/Hover`, applicable default/hover/focus/pressed/disabled/busy/error, semantic labels and blocked-action reasons.

| Required state | Review focus |
|---|---|
| Empty workspace | Open-project action, empty panes |
| Project open, disconnected | Actual tree in runtime; explicit demo label in gallery |
| Device/environment ready | Verified checks, text and icons |
| Build in progress | Real stages, no invented percentages |
| Build succeeded | Artifact actions, no publication implication |
| Build failed | Diagnostic and repair/settings/log actions |
| Plugin unsupported | SwiftPM/override details and warning |
| API-key selected | Masking, trust notice, no real credentials |

Review at1600×900,1360×768,1100×700 plus boundaries/scaling in test-plan.md. Demo data must stay isolated from live state. Advanced debug/live layouts remain future concepts, not operational evidence.
