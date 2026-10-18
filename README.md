# ESCA Voice — the application

Press to talk, watch the waveform, read back what was heard.

A Wayland client of `libesca-ui`, talking to `esca-voiced` over D-Bus.
Flutter would have been the nicer toolkit; its engine has to be built from
source and does not fit on the disk this image is built on, which is why
the camera viewer was written this way first and why this follows it.

## The button does not become a waveform until it is real

The screen shows **PRESS TO TALK** until `esca-voiced` reports
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

**SAY IT BACK** sends the last transcript to `Say()`, which fetches WAV
from the server and plays it. It is the shortest honest test of the whole
round trip, and it exercises text to speech without needing a keyboard.

## Layout

    src/main.cpp        the loop, the drawing, the D-Bus calls
    data/appinfo.json   what esca-appmanager reads to launch this

Launch: `esca-appctl launch vn.sparc.esca.voiceapp`, or by hand with
`XDG_RUNTIME_DIR=/run WAYLAND_DISPLAY=wayland-0 esca-voiceapp`.
`--scale N` makes everything larger on a small panel.
