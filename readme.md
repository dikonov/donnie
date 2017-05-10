## Donnie

A UPnP Control Point and Audio Player for SailfishOS. It is written in QML and C++. For UPnP it relies on [libupnpp](https://github.com/medoc92/libupnpp).

I use it on my Oneplus One running it's SailfishOS port. For Content Server I use `minidlna` and for Renderer `mopidy/upmpdcli` on a RPi3 and a BananaPi and `rygel` on my phone.


### Features
  * Browse and Search Content Server
  * Control Renderer
  * Play with built-in Player (QT-Audio)
  * Album Art
  * Gapless (setNextAVTransportURI)
  * MPris support (Lock Screen and Gestures)

Note that it is still fresh and under development so things might not work as expected.

### Issues
  * Sometimes not all UPnP devices are discovered. A restart of the app can help.
  * Phone call's do not pause the player.
  * Donnie will probably fail if another control point interferes.
  * When the same track appears twice in the list and next to each other a
    track change will not be detected and the next track will not be started.

### Future
There are already a lot of Audio Player for Sailfish. Many of which look and work better then Donnie. It is a lot of work to come at the same level as those. Hopefully  one of those players will integrate the UPnP functionality Donnie has.


### Installation
Donnie and some libraries it needs can be installed from my [OBS repository]( http://repo.merproject.org/obs/home:/wdehoog/sailfish_latest_armv7hl/).

To add this repo:

```
devel-su ssu ar wdehoog http://repo.merproject.org/obs/home:/wdehoog/sailfish_latest_armv7hl/
```

Then install with

```
devel-su pkcon ref
devel-su pkcon install donnie
```

### Thanks
  * J.F.Dockes for upplay + libupnpp, amazing UPnP support 
  * equeim for unplayer
  * jabbounet for upnpplayer 
  * kimmoli for IconProvider and MultiItemPicker
  * Morpog for icon shape