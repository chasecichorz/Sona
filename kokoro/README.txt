Kokoro neural voices for Sona Linux

Kokoro-82M (the voice model) and kokoro-onnx are Apache-2.0 licensed, so the
Sona ISO includes them, ready to use with no internet. OpenEVV stays the
default voice; Kokoro is an extra Speech Dispatcher synthesizer named
"kokoro-generic". Choose it in Orca Preferences, Voice, Speech synthesizer,
or try it with:

    spd-say -o kokoro-generic -y af_heart "Hello from Kokoro"

Main voices: af_heart, af_bella, am_michael, am_fenrir (US); bf_emma,
bm_george (UK). The first words after login take a few seconds while the
model loads; a helper then stays loaded until 20 minutes of silence.

    sona-kokoro-setup    set up or repair (as root)

Files: /opt/kokoro-speechd (model, Python packages, helper),
/usr/local/bin/kokoro-speak, /etc/speech-dispatcher/modules/kokoro-generic.conf.
