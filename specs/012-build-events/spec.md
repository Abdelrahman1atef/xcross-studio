# Feature Specification: NDJSON build events for the desktop app

**Feature Branch**: `012-build-events` | **Created**: 2026-11-01 | **Status**: Implemented

**Input**: ROADMAP 008 (the deferred half): "`--json` NDJSON event stream" with the event types step, progress, log,
warning{code,hint}, error{code,hint}, artifact, device and done. Today the GUI (feature 008) scrapes text: it can't
show which step runs, how far a download is, or where the IPA was written.

## User Story 1 - See build progress and the result in the app (P1)

A developer clicks **Build** or **Build & run** in XCross Studio. They see the current step, a download progress bar,
each finished step with its time, every warning and error with its code and fix hint, and an **Install** button for
the exact IPA the build wrote.

**Independent Test**: run `xcross flutter build --release --ipa` with `XCROSS_EVENTS=ndjson`. Every stdout line that
is a JSON object matches `contracts/events.schema.json`, and the run ends with `artifact` (ipa) and `done`.

**Acceptance Scenarios**:

1. **AC-012-1**: **Given** a `Log` with an event observer, **When** xcross reports status, trace, warnings, errors,
   steps (start, output lines, done or failed) or a progress bar, **Then** the observer receives them and the human
   output receives nothing. Without an observer the output is unchanged.
2. **AC-012-2**: **Given** `XCROSS_EVENTS=ndjson`, **Then** stdout carries one ASCII-only JSON object per line (`v`
   1). Each one matches the contract: `step`, `progress`, `log`, `warning`, `error` (with `code` and `hint` parsed
   from xcross's `[code] message` + `hint:` text), `artifact`, `device`, `check` and `done`. Text written straight to
   the output becomes a `log` event, so nothing is lost.
3. **AC-012-3**: **Given** a failing command in event mode, **Then** the failure is an `error` event and the last
   event is `done` with the exit code (0, 1, or 64 for usage errors).
4. **AC-012-4**: **Given** `flutter run` or `install`, **Then** the chosen device is reported as a `device` event
   (name, iOS version, legacy flag, connection) without its UDID.
5. **AC-012-5**: **Given** `flutter doctor`, **Then** every check is a `check` event (section, name, status, message,
   path).
6. **AC-012-6**: The GUI parses every event type, including an event that follows partial tool text on the same
   line.
7. **AC-012-7**: Build, run, install and doctor jobs set `XCROSS_EVENTS=ndjson` and fold the events into steps,
   progress, issues (code + hint), artifacts, checks, the device and the exit code. With an older CLI the text output
   is shown as before.
8. **AC-012-8**: The job view shows the running step or download percentage, the finished steps with their times,
   and the issue list. The doctor shows a checklist. **Install** uses the IPA named by the `artifact` event.
9. **AC-012-9**: Default human output is unchanged (device evidence: a GUI build and run on the iPhone X).

## Requirements

- **FR-001**: Event mode is enabled by the `XCROSS_EVENTS=ndjson` environment variable (no regenerated argument
  parsers); default output is unchanged.
- **FR-002**: The events reuse what xcross already reports (`Log` steps, coded warnings and errors, progress bars) at
  one seam, plus small hooks where artifacts, the device and doctor checks are known.
- **FR-003**: Events never contain a device UDID.

## Out of scope (later)

A `--json` flag per command; `progress` fractions for compile steps (only downloads and extractions know their
total); events for `compose` commands beyond what the shared `Log` already reports.
