# ESCA Voice — the application

Press to talk, watch the waveform, read back what was heard.

A Flutter application, talking to `esca-voiced` over D-Bus.

## The button does not become a waveform until it is real

The screen shows **Press to talk** until `esca-voiced` reports
`listening` — microphone open, server answering. Only then does the top
half become a waveform and invite someone to speak.

That is the whole reason the service has a `preparing` state. A dead link
found while nobody is talking is a line of red text; found afterwards, it
is a sentence spoken into nothing and a silence where the answer should be.

```
PRESS TO TALK   →  PREPARING...  →  [waveform]  →  TRANSCRIBING...  →  text
     idle            checking         listening        sending
```

The waveform is drawn between the noise floor the service is tracking and
0 dBFS, not from silence, so a loud room does not peg it full. Bars go
blue once the level clears the floor by the margin that counts as speech,
which makes the detector's own decision visible rather than hidden.

**Read back** sends the last transcript to `Say()`, which fetches WAV
from the server and plays it. It is the shortest honest test of the whole
round trip, and it exercises text to speech without needing a keyboard.

## Layout

    lib/voice.dart          the service over D-Bus, and the screen's state
    lib/voice_screen.dart   the microphone, the waveform, what was heard
    lib/kit/                the shared ESCA look
    data/appinfo.json       what esca-appmanager reads to launch this

Launch: `esca-appctl launch vn.sparc.esca.voiceapp`, or press its tile in
ESCA Home. Leaving mid-session stops listening first.

The `Level` signal arrives twenty times a second and repaints the waveform
alone; the rest of the screen rebuilds only when something else changes.

## Building and testing on the development host

    flutter pub get
    flutter analyze
    flutter test

The tests drive the screen against a fake service, so they need neither the
board nor the bus. `pubspec.lock` is committed: the Yocto build resolves the
same package versions the tests ran against.

On the board the bundle is built by its recipe in `meta-sparc-esca`
(`esca-flutter-app.inc`), run by `ivi-homescreen` inside the Weston session,
and started by `esca-appmanagerd` through the launcher in `/usr/bin`.

`lib/kit/` is the shared ESCA look, copied identically into every
application. Change one copy, copy it to the others.
