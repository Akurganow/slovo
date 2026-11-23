# Contracts a reviewer checks

These are contracts of the product's code that no test and no lint rule holds.
Every reviewer of a change reads the change against them. The owner decided
that no test reads a repository file as text: «чтобы не было тестов, которые
читают исходники. Чтение исходников — это уровень линтера, а не тестирования.»
The bans a rule can name on its own are ast-grep rules under `Lint/rules/`.
Every other contract is an entry here: what must be present, ordered or
counted, and the bans that belong to one of those contracts.

An entry states behaviour a user or a maintainer observes. Where the contract
is a file's content, the entry names the file.

## Hotkey and dictation path

- First run asks macOS for each missing permission (microphone, Accessibility,
  Input Monitoring) through the system prompt. It opens the System Settings pane
  only when no prompt is available or the request is not granted. A granted
  request retries the setup.
- A hotkey tap that fails to start shows the hotkey recovery menu.
- Every key edge reaches the dictation orchestrator through one ordered
  sequencer. No edge runs on its own task, so a quick press and release cannot
  swap places.
- Retry Setup while a rebuild still runs starts no second rebuild. The new
  rebuild waits for the old key sequencer to finish.
- A press made while the previous dictation is processing is refused before the
  app marks any session active. Its release then has nothing to stop. One check
  reads the stamp that marks such a press.
- A press made before the speech model is loaded opens no microphone and starts
  no session. The check comes before any session starts.
- The release of a refused press does nothing, so it cannot overwrite the
  loading glyph.
- The recording glyph comes from one path that takes the hold's phase and reads
  the live cleanup setting once. The key-down arm and the translate-latch arm
  both paint through it, and neither reads the cleanup setting itself. A
  translate key joining mid-hold repaints the glyph, and raw wins over translate.
- During a dictation every repaint of the glyph goes through
  `RestingGlyph.derive`. A failure flash, or a notice that ended the dictation,
  owns the glyph; otherwise the glyph shows the hold's phase. The key-up and
  translate-latch arms set the phase and repaint through it; only key-down paints
  the hold glyph directly.
- The dictation gate opens only when the model load finished successfully, and
  only for the composition that is still current. The composition exposes the
  load as a task the gate awaits.
- A composition that is never gated (onboarding, a lost permission) clears the
  loading pulse it inherited. The onboarding return comes before the gate is
  entered, so nothing else would clear it.
- The key monitor is built from the saved key configuration, the push-to-talk
  key and the translate key, never from a literal.
- The key tap observes key-down events, so a key combination interrupts a hold
  on a modifier alone.
- After the key tap dies, the stop the app synthesizes carries the mode of the
  dead hold. A translate dictation is not downgraded to plain.
- A key-down that is not the trigger reports only that a key went down. The
  modifier-change case reads the key code to detect the trigger key.

## Menu and glyph

- Each menu open re-reads the fn-key assignment, the default output device and
  the input devices into the app state. The menu then shows what System Settings
  says now.
- The fn-key verdict reaches the menu only through the app state. The launch
  seed and the menu-open re-read take it from the reader, and the menu build
  passes the state's value. No code writes it as a literal.
- A transient status and a brief failure glyph clear themselves and never become
  the status line. Key-up and a silent cancel both stop, drain the pipeline, then
  settle to idle. Settling repaints the resting glyph and keeps a start-failure
  line.
- Between rebuilds, the status, fn and update rows, the mute item and the
  Microphone submenu follow the app state through listeners. A rebuild seeds them
  from the committed state. One listener writes the status row's title.
- The menu in use follows the app mode in the state. Onboarding, hotkey recovery,
  a refresh and Retry Setup each write the mode, so a setting changed during
  onboarding rebuilds the setup menu.
- Changing Mute While Dictating applies to the next dictation without rebuilding
  the pipeline. The toggle only flips the stored setting, and the menu builder
  takes its flag from its input.
- The mute item is disabled, with the reason as its tooltip, where macOS can set
  neither mute nor volume. Launch registers a listener for the default output
  device, the listener writes the state, and each rebuild renders the
  availability onto the new item.
- The Microphone submenu lists the present devices, checks the chosen one and
  follows device changes. Launch reads the devices once. A rebuild renders the
  choice onto the new item, and a row writes the saved choice.
- A brief glyph reset that a newer flash superseded does nothing when its delay
  ends. The live reset always clears the brief-status state and repaints
  through the resting decision, which during a dictation gives the glyph back to
  the hold unless a notice that ended it holds the glyph.
- An empty result flashes the brief failure glyph and returns before any status
  line is written. That branch writes no status text.
- A brief flash sets the brief-status state, so settling to idle does not wipe
  it. It paints the status glyph and schedules its own clear.
- A failure status paints through the core glyph renderer in the error tint, and
  a live state paints in the normal tint.
- A brief red flash never resets the line of a persistent failure to the idle
  hint.
- The menu is built from one input and the live rows, and the builder reads every
  value from them, never from the store. The menu cannot show a value that
  bypasses the app state. The build takes the fn verdict and the update
  indication as arguments, not from the live reader or the updater coordinator.
- The resting-glyph painter reads the update indication from the store and
  picks the glyph through the core projection.
- Every updater event repaints the resting glyph, once and under no condition,
  so a later event overwrites a failed Restart's red flash. The core glyph logic
  decides whether the repaint may run over a live dictation.

## Settings panes

- The Cleanup pane subscribes to the app store and reads cleanup availability
  from it, so it repaints on store writes.
- The Clean Up Dictation switch is disabled while the state says the toggle
  cannot change. It carries its title and its status line.
- The Cleanup status text comes from the cleanup availability, never from a
  string in the pane.
- Exactly two sections carry the availability gate: the Cleanup section and the
  spell-check hints section. The model row sits inside the Cleanup section and
  reads no key state itself, so it grays with no key like writing style and
  translate.
- Each pane control writes through the store's bindings, and an action with an
  effect outside the store goes through the settings actions seam. Only a user
  action writes the cleanup model: the picker and the custom model button. The
  Cleanup pane renders the state's model selection and derives none of its own.
- The General pane re-reads Open at Login each time it appears and after every
  change, since the setting can change outside Slovo while the window is cached.
- The General mute switch is disabled, with the reason in its row, where macOS
  can set neither mute nor volume.
- The Microphone picker lists the present devices and an absent chosen device,
  names the fallback, and writes the choice to the store.
- Each key picker shows the other picker's key as a disabled row, so the two
  cannot select the same key.
- The translate row shows the main key plus the dropdown only while the
  translate key is additional.
- The Cleanup pane's translate caption names the configured keys and the right
  gesture for an additional and a standalone translate key.
- The Vocabulary pane has a selectable list with a visible minus control. The
  control removes the selection and is disabled while nothing is selected.
- The Settings window activates the app before it shows, so it does not open
  behind other apps. The opener uses no Settings link route.
- The menu's add-key item shows the key window, and the window's Save routes
  through the app's key-save path.
- The text entry window builds a fresh view on every show, so no stale text
  lingers. Its secure field takes focus when the window opens.
- In the text entry window, Confirm sends the trimmed text to the confirm action.
  Cancel and Esc close the window without confirming, and empty text cannot be
  confirmed. The app activates before the window shows.
- Confirming closes the text entry window, so a window holding the entered secret
  does not linger and a second save is impossible.
- The Cleanup pane has a translation language picker built from the
  recognition-language catalog, with no Auto row, bound to the store.
- About Slovo opens Settings on the About pane. Settings opens the last pane,
  which a toolbar observation records in the store. Only the open that builds the
  window switches by pane. A later open switches as a toolbar click does.

## Key removal

- The Remove Key button shows only while a key is saved, and key presence alone
  gates it, from one render site. It has the destructive role and asks for
  confirmation inside the Settings window.
- The pane decides whether a key is saved from the observed cleanup availability.
  It never uses the key provider, a state field or a local copy.
- The Remove Key button only raises the confirmation. Nothing is removed before
  the user confirms, and the dialog's confirm action is the only removal call in
  the row.
- The pane removes the key through the settings actions seam. It never calls the
  key provider or the Keychain.
- A failed key save or removal flashes the failure glyph and applies no scope
  event. Key presence is read back after the failure as after a success.
- The four Remove Key strings read exactly: the button "Remove Key…", the dialog
  title "Remove the OpenRouter API key?", the confirm action "Remove Key", and the
  message "Cleanup will turn off until you add a key again."
- The real key removal calls the Keychain delete, and removing an absent key
  counts as success.

## Updates

- The Check for Updates menu action calls the update coordinator's manual check.
- The manual check runs the silent background check, only when the updater can
  check, and shows Checking at once.
- The app builds one updater directly. It uses no stock updater controller, no
  legacy updater class and no check that shows an alert.
- The saved Automatically Install Updates choice is applied before the updater
  starts, so a user who chose Off gets no first check.
- The install-on-quit answer is yes, and the handler the updater passes is kept
  for the Restart click.
- The updater delegate opts into gentle reminders, answers no to the stock
  scheduled-update alert and never prompts for check permission.
- The dictation dropdown has its own menu delegate, so the update row re-syncs on
  each open.
- The update row is one persistent menu item that is changed in place. The
  renderer builds no menu items, and the menu-open re-sync renders the row from
  state.
- Settings, General has the Automatically Install Updates switch, bound to the
  store.

## Sound cues

- One Sound Cues preference in the store drives the General pane, the menu toggle
  and the cue controller before the next dictation starts. Only the composition
  owns the controller's initial value. The orchestrator and the pipeline factory
  hold no cue preference.
- The cue controller creates a system sound id, plays it as an alert sound with a
  completion, and disposes it.
- The cue sound files, their packaging checks, their license notice and the
  README feature line stay in step. `Scripts/build_and_run.sh` checks each
  packaged cue file under verify. `THIRD-PARTY-NOTICES.md` keeps the CC0
  attribution, the source files and the conversion recipe. `README.md` lists
  Sound Cues as a feature and says cue loudness follows the system alert volume.

## Status item

- At launch the app writes the preferred menu-bar position through the injected
  defaults before it creates the status item.
- The status item's autosave name is the constant the position seed is keyed on,
  never a string literal.

## About pane

- The About pane observes the store, so its keycaps follow a key change. It reads
  the version, the build number and the dev-build marker from the bundle.
- The About pane shows the Slovo glyph, the version line and both configured keys
  as keycaps. The keys come from the configuration, never from literals.
- The About pane has an Acknowledgements action that opens the bundled
  third-party notices file.

## Speech recognition and audio capture

- Speech models download into a base under Application Support. The shared speech
  model builds the WhisperKit transcriber, and the engine's load takes its
  configurations from helpers that require that base.
- A speech session decodes with its own vocabulary terms, the loaded model's
  tokenizer and the session's own language.
- The live recognition session connects the audio bridge, the loop-exit signal,
  the tail planner, the terminal-hallucination guard and the tail decode. No test
  can build it without a real model engine.
- A late microphone callback from a stopped session is rejected. Each tap
  callback carries its session's token, and teardown rejects a stale token before
  it clears the session.
- The recorder assigns a chosen device first. It then reads the node's input
  format, validates it before it installs the tap, and taps with that input
  format.
- The recorder reads the stereo channel pair of the device the capture uses. On
  the default path that device comes from the default-input read, not from the
  audio unit.

## Cleanup wiring

- The production composition passes both hint providers, input-source language
  and spell check, to the pipeline.
- The personalization database passphrase derives from this Mac's hardware
  identity, never from a literal shared by all installs.
- The Keychain presence check runs an attributes-only query for one match and
  treats success as present. The composition computes the first-run steps and
  takes key presence from the state it is handed.
- Nothing before the hotkey starts reads the Keychain secret, so the pipeline
  works without a key and no Keychain prompt races the key tap.
- Model-scope events fire only after the hotkey monitor started, inside the
  success path, never on the failure path. The status item exists and the store
  effects start before the pipeline starts.
- The scope fetcher logs exactly five fixed events: a successful fetch with its
  count, and four failures (missing key, offline, API error, malformed answer).
- The packaged app looks for the named SlovoCore resource bundle under the app's
  resource root first. It falls back to the linked bundle, and returns nil when
  neither exists.

## Packaging and plist

- The app starts as an accessory menu-bar app. It has an Edit menu with paste
  and select all, and its status item draws an image, never a title string.
- The production composition builds the real adapters and is seeded from the
  state it is handed, never from a config reload. The recorder starts from the
  stored microphone choice, and each composition preloads the speech model it was
  handed. Launch starts the pipeline, and the sequencer hands the down, up and
  cancel edges to the orchestrator.
- `Resources/Info.plist` marks the app as a menu-bar agent. It carries the
  identifier `com.slovo.app`, the executable `slovo`, the principal class
  `NSApplication` and a microphone usage description.
- The macOS floor stamp agrees across `Resources/Info.plist`, `Package.swift`,
  `Scripts/app-bundle.sh`, the platform badge in `README.md`, and the
  requirements lines of `README.md`, `CONTRIBUTING.md` and `docs/development.md`.
- `slovo.entitlements` allows audio input and sets no app sandbox.
- `Scripts/build_and_run.sh` under verify checks that the staged app holds the
  prompt examples file, since a missing bundle would ship a cleanup prompt
  without examples.
- `Scripts/sign-and-notarize.sh` signs with the hardened runtime and
  `slovo.entitlements`, and it notarizes through the notary tool. It passes the
  cache, config and security paths and `--disable-automatic-resolution` to Swift.
  Neither it nor `Scripts/app-bundle.sh` runs `rm -rf`.
- `Scripts/app-bundle.sh` finds the SQLCipher framework through a discovery
  function and hardcodes no path to it.
- Only the app target links Sparkle, with the framework rpath. The SlovoCore
  target stays Sparkle-free, and `Package.swift` links the Sparkle product from
  exactly one target.
- No packaging script signs with `--deep`. The flag appears only on verification
  lines in `Scripts/sign-and-notarize.sh`, `Scripts/build_and_run.sh` and
  `Scripts/app-bundle.sh`.
- The dev launcher stages and signs through the shared bundle steps in
  `Scripts/app-bundle.sh`. `Scripts/build_and_run.sh` stages the bundle before it
  signs, and signs the frameworks before the app.
- `Resources/Info.plist` carries the Sparkle feed URL, the public EdDSA key,
  automatic checks and install, an hourly check interval and
  verify-before-extraction. The key never changes by accident, since a swap
  orphans every installed copy.
- `Scripts/diagnose.sh` runs the cleanup benchmark smoke script as its own stage.
  `Scripts/check-cleanup-benchmark-cli.sh` runs the built executable with the
  pass-through provider and one repetition, and sets no scratch path.

## Release automation

- The publish job in `.github/workflows/release.yml` runs on a macOS runner,
  since the stamping script uses PlistBuddy and plutil.
- `CHANGELOG.md` starts with the header text that `cliff.toml` strips, so a
  release does not write the header twice.
- `Resources/Info.plist` carries no `SlovoDevBuild` key.
- `Scripts/build_and_run.sh` writes the `SlovoDevBuild` marker into the staged
  plist copy only. That is the key's one write site.
- `Scripts/sign-and-notarize.sh`, `Scripts/app-bundle.sh` and
  `.github/workflows/release.yml` never mention the `SlovoDevBuild` marker.

## Notices

- `THIRD-PARTY-NOTICES.md` carries the copyright and permission notice of every
  bundled component and of the project, in each component's own words.
- Every external package that the shipped app target links has a section in
  `THIRD-PARTY-NOTICES.md`. Tooling-only packages are exempt, and the file
  discloses them.

## Package manifest and lint configuration

- `Package.swift` depends on the argmax package and links the WhisperKit product
  into SlovoCore.
- Every Swift target in `Package.swift` uses the strict Swift settings.
- `Package.swift` pins SwiftLint by exact version. `Scripts/lint.sh` runs it
  through the package plugin in strict mode, with network access off, and never
  skips it when it is missing. `.swiftlint.yml` sets strict mode, opts in to every
  rule, enables every analyzer rule and turns off update checks.
- `.swiftlint.yml` never disables the concurrency-annotation rule or the
  unused-import rule, in any YAML spelling.

## At most once

Each entry below has exactly one site. Zero sites is as much a defect as two.
For the first three, an ast-grep rule bans a site outside the one allowed place:
`Lint/rules/single-relaunch-call-site.yml`,
`Lint/rules/config-loaded-once-never-saved.yml` and
`Lint/rules/personalization-database-opened-once.yml`. These entries hold the
count.

- The app calls the install-and-relaunch action from exactly one place. Zero
  calls would leave no Restart path.
- The app reads the saved config exactly once, to seed the store. Only the
  store's persistence subscriber saves it.
- The personalization database opens at one site, once per launch. The opener is
  declared once and called once, and the pipeline build, the pipeline start and
  Settings never call it.
- The model-scope fetch has one call site, in the target closure that the store's
  fetch subscriber runs. The composition and the app wire the failure observer,
  and the failure feed writes no config.
- The app builds one speech model for the process and injects it into every
  composition. A composition builds no engine of its own, so a rebuild never
  starts a second download of the same model.
- The app reconfigures the running key tap from one call site, with the value
  the store's subscriber hands the hotkey target. Every key setting applies in
  place without a rebuild.

This file describes what the product's code must do. A change that alters a
contract edits its entry in the same change. A change that breaks an entry
without editing it is a finding.
