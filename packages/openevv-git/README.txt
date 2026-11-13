OpenEVV (IBM Embedded ViaVoice, the "Eloquence" voice) for Sona Linux

Sona's default Speech Dispatcher voice. OpenEVV's own code is MIT licensed,
but its language data is IBM's (see its NOTICE file), so Sona does not ship
it prebuilt. Each Sona computer builds its own copy from
https://github.com/mudb0y/openevv with this PKGBUILD:

  sona-openevv-update            build or update now (as root); also makes
                                 OpenEVV the default voice
  sona-openevv-update --force    rebuild even if up to date
  sona-openevv-update.timer      runs it 3 minutes after boot and weekly,
                                 so an offline install gets OpenEVV once it
                                 is online, and updates arrive by themselves

Until OpenEVV is built, speech uses espeak-ng.
