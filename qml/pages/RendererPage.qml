/**
 * Donnie. Copyright (C) 2017 Willem-Jan de Hoog
 *
 * License: MIT
 */


import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Media 1.0               // for MediaKey
import QtMultimedia 5.5
import org.nemomobile.policy 1.0        // for Permissions
import org.nemomobile.configuration 1.0 // for ConfigurationValue

import "../UPnP.js" as UPnP

Page {
    id: rendererPage

    property bool rendererPageActive: !app.useBuiltInPlayer
    property string defaultImageSource : "image://theme/icon-l-music"
    property string imageItemSource : defaultImageSource
    property string playIconSource : "image://theme/icon-l-play"
    property int currentItem: -1
    property bool metaShown : false

    property string trackMetaText1 : ""
    property string trackMetaText2 : ""

    property string timeSliderLabel : ""
    property int timeSliderValue : 0
    property int timeSliderMaximumValue : 0
    property string timeSliderValueText : ""

    property string prevTrackURI: ""
    property int prevTrackDuration: -1
    property int prevTrackTime: -1
    property int prevAbsTime: -1

    property int volumeSliderValue
    property string muteIconSource : "image://theme/icon-m-speaker"

    property bool useNextURI : use_setnexturi.value
    property bool hasTracks : listView.model.count > 0

    property bool canNext: hasTracks && (currentItem < (listView.model.count - 1))
    property bool canPrevious: hasTracks && (currentItem > 0)
    property bool canPlay: hasTracks && transportState != 1
    property bool canPause: transportState == 1


    property bool playing : false
    property bool rendererConnected: false
    property int requestedAudioPosition : -1
    property int requestedAudioPositionRetryCount : -1

    // -1 initial, 1 playing, 2 paused, 3 stopped the rest inactive
    property int transportState : -1

    function refreshTransportState(tstate) {
        var newState;
        if(tstate === "Playing")
            newState = 1;
        else if(tstate === "PausedPlayback")
            newState = 2;
        else if(tstate === "Stopped")
            newState = 3
        else
            newState = -1;
        transportState = newState;
        //console.log("RTS: count:" + trackListModel.count+", currentItem"+currentItem+", hasTracks: "+hasTracks+", canNext: "+canNext)
        app.notifyTransportState(transportState);
    }

    function getMediaInfo() {
        var mediaInfoJson = upnp.getMediaInfoJson();
        try {
            return JSON.parse(mediaInfoJson);
        } catch(err) {
            app.error("Exception in getMediaInfo: "+err);
            app.error("json: " + mediaInfoJson);
        }
    }

    function next() {
        if(currentItem >= (trackListModel.count-1))
            return
        currentItem++
        loadTrack()
    }

    function prev() {
        if(currentItem <= 0)
            return
        currentItem--
        loadTrack()
    }

    function pause() {
        if(transportState == 1) {
            var r
            if((r = upnp.pause()) !== 0) {
                app.showErrorDialog(qsTr("Failed to Pause the Renderer"))
                return;
            }
            playIconSource =  "image://theme/icon-l-play"
            cover.updatePlayIcon("image://theme/icon-cover-play")
            app.last_playing_position.value = timeSliderValue
        } else {
            play()
        }
    }

    function play() {
        var r;
        if((r = upnp.play()) !== 0) {
            // rygel: 701 means not "Stopped" nor "Paused" so assume already playing
            if(r !== 701) {
                app.showErrorDialog(qsTr("Failed to Start the Renderer"))
                return;
            }
        }
        rendererConnected = true
        playing = true
        playIconSource = "image://theme/icon-l-pause"
        cover.updatePlayIcon("image://theme/icon-cover-pause")
    }

    function stop() {
        var r
        if((r = upnp.stop()) !== 0) {
            app.showErrorDialog(qsTr("Failed to Stop the Renderer"))
            //return
        }
        playing = false
        playIconSource =  "image://theme/icon-l-play"
        cover.updatePlayIcon("image://theme/icon-cover-play")
        app.last_playing_position.value = timeSliderValue
    }

    function reset() {
        playing = false
        transportState = -1
        playIconSource =  "image://theme/icon-l-play"
        cover.updatePlayIcon("image://theme/icon-cover-play")
    }

    function setVolume(volume) {
        var r
        if((r = upnp.setVolume(volume)) !== 0) {
            app.showErrorDialog(qsTr("Failed to set volume on Renderer"))
        }
    }

    function setMute(mute) {
        var r
        if((r = upnp.setMute(mute)) !== 0) {
            app.showErrorDialog(qsTr("Failed to mute/unmute Renderer"))
        }
    }

    property int prevVolume;
    function toggleMute() {
        var mute = !upnp.getMute()
        if(mute)
            prevVolume = upnp.getVolume()
        setMute(mute)
        if(mute)
            muteIconSource =  "image://theme/icon-m-speaker-mute"
        else {
            setVolume(prevVolume)
            muteIconSource =  "image://theme/icon-m-speaker"
        }
    }

    function updateUIForTrack(track) {
        imageItemSource = track.albumArtURI ? track.albumArtURI : defaultImageSource
        cover.updateDisplayData(track.albumArtURI, track.titleText, track.upnpclass)

        trackMetaText1 = track.titleText
        trackMetaText2 = track.metaText
    }

    // update mpris with track info from media server
    function updateMprisForTrack(track) {
        var meta = {}
        meta.Title = trackMetaText1
        meta.Artist = trackMetaText2
        meta.Album = track.album
        meta.Length = track.duration * 1000000 // s -> us
        meta.ArtUrl = track.albumArtURI
        meta.TrackNumber = currentItem
        app.updateMprisMetaData(meta)
    }

    // update mpris with track info from stream
    function updateMprisForTrackMetaData(track) {
        var meta = {}
        meta.Title = trackMetaText1
        meta.Artist = trackMetaText2
        meta.Album = track.album
        meta.Length = 0
        meta.ArtUrl = track.albumArtURI
        meta.TrackNumber = currentItem
        app.updateMprisMetaData(meta)
    }

    function onChangedTrack(trackIndex) {
        currentItem = trackIndex
        var track = trackListModel.get(currentItem)
        updateUIForTrack(track)
        updateMprisForTrack(track)

        // When available set next track
        if(trackListModel.count > (currentItem+1)) {
            track = trackListModel.get(currentItem+1)
            console.log("onChangedTrack setNextTrack "+track.uri)
            setNextTrack(track)
        }
        console.log("onChangedTrack: index="+trackIndex)
    }

    function loadTrack() {
        var track = trackListModel.get(currentItem)
        console.log("loadTrack trying item " + currentItem + ": "+track.uri)
        rendererBusy = true
        upnp.setTrackAsync(track.uri, track.didl)
    }

    function setNextTrack(track) {
        if(!useNextURI || UPnP.isBroadcast(track))
            return
        rendererBusy = true
        upnp.setNextTrackAsync(track.uri, track.didl)
    }

    function clearList() {
        //rendererPageActive = false;
        stop()
        listView.model.clear()
        trackMetaText1 = ""
        trackMetaText2 = ""
        currentItem = -1
        transportState = -1
        imageItemSource = defaultImageSource
        cover.resetDisplayData()
    }

    SilicaListView {

        id: listView
        model: trackListModel
        width: parent.width
        anchors.fill: parent
        anchors {
            topMargin: 0
            bottomMargin: 0
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Add Stream")
                //visible: false
                onClicked: {
                    app.showEditURIDialog(qsTr("Add Stream"), "", "", UPnP.AudioItemType.AudioBroadcast, function(title, uri, streamType) {
                        if(uri === "")
                            return
                        var track = UPnP.createUserAddedTrack(uri, title, streamType)
                        if(track !== null) {
                            trackListModel.append(track)
                            currentItem = trackListModel.count-1
                            loadTrack(track)
                        }
                    })
                }
            }
            MenuItem {
                text: qsTr("Empty List")
                onClicked: {
                    clearList()
                }
            }
        }

        header: Column {
            id: headerColumn

            width: parent.width - 2*Theme.paddingMedium
            x: Theme.paddingMedium

            Rectangle {
                width: parent.width
                height:Theme.paddingLarge
                opacity: 0
            }

            Row {

                width: parent.width

                Rectangle {
                    width: Theme.paddingLarge
                    height: parent.height
                    opacity: 0
                }

                Image {
                    id: imageItem
                    source: imageItemSource
                    width: parent.width / 2
                    height: width
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                  id: playerButtons

                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Theme.paddingSmall
                  width: parent.width / 2
                  //height: playIcon.height

                  IconButton {
                      anchors.horizontalCenter: parent.horizontalCenter
                      id: playIcon
                      icon.source: playIconSource
                      onClicked: pause()
                  }

                  Row {
                      anchors.horizontalCenter: parent.horizontalCenter

                      IconButton {
                          //anchors.horizontalCenter: parent.horizontalCenter
                          icon.source: "image://theme/icon-m-previous"
                          enabled: canPrevious
                          onClicked: prev()
                      }

                      IconButton {
                          //anchors.horizontalCenter: parent.horizontalCenter
                          icon.source: "image://theme/icon-m-next"
                          enabled: canNext
                          onClicked: next()
                      }
                  }

                  IconButton {
                      anchors.horizontalCenter: parent.horizontalCenter
                      icon.source: "image://donnie-icons/icon-m-stop"
                      onClicked: stop()
                  }

                }
            }

            Slider {
                id: timeSlider
                property int position: timeSliderValue
                property string positionText: timeSliderValueText

                enabled: !UPnP.isBroadcast(getCurrentTrack())
                anchors.left: parent.left
                anchors.right: parent.right
                handleVisible: false;

                label: timeSliderLabel
                maximumValue: timeSliderMaximumValue

                onPositionChanged: {
                    if (!pressed)
                        value = position
                }

                onPositionTextChanged: {
                    if (!pressed)
                        valueText = positionText
                }

                onReleased: {
                    console.log("calling seek with " + sliderValue);
                    positionInfo = undefined
                    skipNextPositionInfo = 3
                    upnp.seek(sliderValue);
                    updateSlidersProgress(sliderValue);
                    upnp.getPositionInfoJsonAsync()
                }
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right

                //spacing: Theme.paddingSmall
                Slider {
                    id: volumeSlider
                    enabled: true
                    handleVisible: false;
                    width: parent.width - leftMargin - muteIcon.width
                    //label: "Volume"
                    maximumValue: 100
                    value: volumeSliderValue
                    //valueText:

                    onReleased: {
                        console.log("setVolume "+sliderValue);
                        setVolume(sliderValue);
                    }
                }
                IconButton {
                    id: muteIcon
                    anchors.rightMargin: Theme.paddingLarge
                    icon.source: muteIconSource
                    onClicked: toggleMute();
                }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right

                Text {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeMedium
                    color:  Theme.highlightColor
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    text: trackMetaText1
                }
                Text {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.secondaryHighlightColor
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    text: trackMetaText2
                }
            }

            Separator {
                anchors.left: parent.left
                anchors.right: parent.right
                color: "white"
            }
        }

        VerticalScrollDecorator {}

        ListModel {
            id: trackListModel
        }

        delegate: ListItem {
            id: delegate

            width: parent.width - 2*Theme.paddingMedium
            x: Theme.paddingMedium

            Column {
                width: parent.width

                Item {
                    width: parent.width
                    height: tt.height

                    Label {
                        id: tt
                        color: currentItem === index ? Theme.highlightColor : Theme.primaryColor
                        textFormat: Text.StyledText
                        truncationMode: TruncationMode.Fade
                        width: parent.width - dt.width
                        text: titleText
                    }

                    Label {
                        id: dt
                        anchors.right: parent.right
                        color: currentItem === index ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        text: durationText
                    }
                }

                Label {
                    color: currentItem === index ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    textFormat: Text.StyledText
                    truncationMode: TruncationMode.Fade
                    width: parent.width
                    visible: metaText ? metaText.length > 0 : false
                    text: metaText
                }

            }

            menu: contextMenu

            Component {
                id: contextMenu
                ContextMenu {
                    MenuItem {
                        text: qsTr("Remove")
                        onClicked: {
                            var saveIndex = index;
                            trackListModel.remove(index);
                            if(currentItem === saveIndex) {
                                currentItem--;
                                next();
                            } else if(currentItem > saveIndex)
                                currentItem--;
                        }
                    }
                }
            }

            onClicked: {
                currentItem = index;
                loadTrack();
            }
        }

    }

    property var transportInfo
    property var mediaInfo
    property var positionInfo
    property int skipNextPositionInfo: 0 // after seek
    property string skipNextPositionInfoForURI: "" // after loadTrack

    Connections {
        target: upnp

        // {"curspeed":"1","tpstate":"Playing","tpstatus":"OK"}
        onTransportInfo: {
            //console.log("onTransportInfo: " + transportInfoJson)
            if(error === 0) {
                rendererConnected = true
                try {
                    transportInfo = JSON.parse(transportInfoJson)
                    refreshTransportState(transportInfo["tpstate"])
                } catch(err) {
                    app.error("Exception in onTransportInfo: "+err)
                    app.error("json: " + transportInfoJson)
                }
            } else {
                console.log("onTransportInfo: error=" + error + ", " + transportInfoJson)
                refreshTransportState("")
            }
            refreshState = 2
        }

        // On receiving position info parse and set the data
        // It seems that a renderer can send position 0 after a seek
        // this position info is then ignored
        //
        // {"abscount":"9080364","abstime":"27",
        //  "relcount":"9080364","reltime":"27",
        //  "trackduration":"378","trackuri":"http....."}
        onPositionInfo: {            
            //console.log("OnPositionInfo: refreshState:" + refreshState + ", json:" + positionInfoJson)
            var pInfo

            // error?
            if(error !== 0) {
                console.log("onPositionInfo: error=" + error + ", " + positionInfoJson)
                refreshState = 4
                return
            }
            rendererConnected = true

            // ignore positionInfo after a seek
            if(skipNextPositionInfo > 1) {
                skipNextPositionInfo--
                upnp.getPositionInfoJsonAsync()
                return
            }

            // parse received position info
            try {
                pInfo = JSON.parse(positionInfoJson)
            } catch(err) {
                app.error("Exception in onPositionInfo: "+err)
                app.error("json: " + positionInfoJson)
            }

            // wait for valid one
            if(skipNextPositionInfo == 1) {
                // ignore positionInfo after a seek having abs/reltime == 0
                // the value is useless and it would make the slider jump back and forth
                if(pInfo.reltime == 0
                   && pInfo.abstime == 0
                   && pInfo.trackuri === prevTrackURI) {
                    upnp.getPositionInfoJsonAsync()
                    return
                } else
                    skipNextPositionInfo = 0
            }

            // ignore after loadTrack
            if(pInfo.trackuri === skipNextPositionInfoForURI) {
                upnp.getPositionInfoJsonAsync()
                return;
            }
            skipNextPositionInfoForURI = ""

            positionInfo = pInfo
            refreshState = 4
        }


        // "nrtracks" "mduration" "cururi" "curmeta" "nexturi" "nextmeta"
        // currently no used
        onMediaInfo: {
            //console.log("onMediaInfo: " + mediaInfoJson)
            if(error === 0) {
                rendererConnected = true
                try {
                    mediaInfo = JSON.parse(mediaInfoJson)
                } catch(err) {
                    app.error("Exception in onMediaInfo: "+err)
                    app.error("json: " + mediaInfoJson)
                }
            } else
                console.log("onMediaInfo: error=" + error + ', ' + mediaInfoJson)
        }

        onTrackSet: {
            rendererBusy = false
            console.log("RenderPage::onTrackSet error=" + error + ", uri=" + uri)

            var trackIndex = getTrackIndexForURI(uri)
            if(trackIndex < 0) // unknown track
                return
            var track = trackListModel.get(trackIndex)

            if(error > 0) {
                var errMsg = UPnP.getUPNPErrorString(error)
                if(errMsg.length > 0)
                    errMsg = qsTr("Failed to set track to play on Renderer:")
                             + "\n\n" + error + ": " + errMsg
                             + "\n\n" +  track.title
                             + "\n\n" +  track.uri
                else
                    errMsg = qsTr("Failed to set track to play on Renderer")
                             + "\n\nError code: " + error
                             + "\n\n" +  track.title
                             + "\n\n" +  track.uri

                // don't know how to make modal behaviour
                // var choice = app.showErrorDialog(errMsg, true, cancelAll)
                console.log(errMsg)
                app.showErrorDialog(errMsg)
            } else {

                // there will be a notification of a postion of the previous URI
                // we want to skip that one
                skipNextPositionInfoForURI = prevTrackURI

                // used to detect uri change by the renderer itself
                prevTrackURI = ""
                prevTrackDuration = -1
                prevTrackTime = -1

                // used to display information
                trackMetaText1 = track.titleText
                trackMetaText2 = track.metaText

                rendererConnected = true
                updateUIForTrack(track)
                updateMprisForTrack(track)

                if(!playing) {
                    play()
                    if(requestedAudioPosition != -1) {
                        var r = upnp.seek(requestedAudioPosition)
                        if(r === 0) // rygel returns 711 (needs time to start playing?)
                            requestedAudioPosition = -1
                    }
                }
                app.saveLastPlayingJSON(track, trackListModel)

                // When available set next track but not for internet radio streams
                if(trackListModel.count > (currentItem+1)) {
                    track = trackListModel.get(currentItem+1)
                    console.log("loadTrack setNextTrack "+track.uri)
                    setNextTrack(track)
                }
            }
        }

        onNextTrackSet : {
            rendererBusy = false;
            console.log("RenderPage::onNextTrackSet error=" + error + ", uri=" + uri)
            if(error === 0)  // success
                return

            var trackIndex = getTrackIndexForURI(uri)
            if(trackIndex < 0) // unknown track
                return
            var track = trackListModel.get(trackIndex)

            var errMsg = UPnP.getUPNPErrorString(error)
            if(errMsg.length > 0)
                errMsg = qsTr("Failed to set next track to play on Renderer:")
                         + "\n\n" + error + ": " + errMsg
                         + "\n\n" +  track.title
                         + "\n\n" +  track.uri
            else
                errMsg = qsTr("Failed to set next track to play on Renderer")
                         + "\n\nError code: " + error
                         + "\n\n" +  track.title
                         + "\n\n" +  track.uri
            console.log(errMsg)
            app.showErrorDialog(errMsg)
        }

        onError: {
            console.log("RenderPage::onError: " + msg)
       }
    }

    function increaseVolume() {
        // max is 100
        if(volumeSliderValue <= 95)
            volumeSliderValue = volumeSliderValue + 5;
        else
            volumeSliderValue = 100;
        setVolume(volumeSliderValue);
    }

    function decreaseVolume() {
        // max is 100
        if(volumeSliderValue >= 5)
            volumeSliderValue = volumeSliderValue - 5;
        else
            volumeSliderValue = 0;
        setVolume(volumeSliderValue);
    }

    MediaKey {
        enabled: rendererPageActive && hasCurrentRenderer()
        key: Qt.Key_ToggleCallHangup
        onReleased: pause()
    }

    // needed for Volume Keys and maybe also Key_ToggleCallHangup
    Permissions {
        enabled: true
        autoRelease: true
        applicationClass: "player"

        Resource {
            id: volumeKeysResource
            //type: Resource.ScaleButton
            type: Resource.HeadsetButtons
            optional: true
        }
    }

    function addTracksNoStart(tracks) {
        var i;
        for(i=0;i<tracks.length;i++)
            trackListModel.append(tracks[i])
    }

    function openTrack(track) {
        addTracksNoStart([track])
        currentItem = trackListModel.count - 1
        loadTrack()
    }

    function addTracks(tracks) {
        var wasAtLastTrack = currentItem == (trackListModel.count-1);
        addTracksNoStart(tracks)
        if(currentItem == -1 && trackListModel.count > 0) {
            // start playing
            if(arguments.length >= 2 && arguments[1] > -1) // is index passed?
                currentItem = arguments[1]
            else
                currentItem = 0
            if(arguments.length >= 3) { // is position passed?
                requestedAudioPosition = arguments[2]
                requestedAudioPositionRetryCount = 5
            }
            loadTrack()
        } else if(wasAtLastTrack) {
            // if the last track is playing there is no nexturi
            // but now new ones have been added it can be set
            var track = trackListModel.get(currentItem+1)
            setNextTrack(track)
        }
    }

    onStatusChanged: {
        if(status == PageStatus.Active) {
            if(app.hasCurrentRenderer()) {
                volumeSliderValue = upnp.getVolume()
                console.log("onStatusChanged initial renderer volume=" + volumeSliderValue)
            }

            if(!hasTracks) {
                var minfo = getMediaInfo()
                if(minfo !== undefined) {
                    var track
                    if(minfo["curmeta"] !== undefined
                       && minfo["curmeta"].id !== "") {
                        track = UPnP.createListItem(minfo["curmeta"])
                        addTracksNoStart([track])
                        updateUIForTrack(track)
                        updateMprisForTrack(track)
                    }
                    if(minfo["nextmeta"] !== undefined
                            && minfo["nextmeta"].id !== "") {
                        track = UPnP.createListItem(minfo["nextmeta"])
                        addTracksNoStart([track])
                    }
                }
            }

        }
    }

    function getTrackIndexForURI(uri) {
        var i;
        for(i=0;i<trackListModel.count;i++) {
            var track = trackListModel.get(i);
            if(track.uri === uri)
                return i;
        }
        return -1;
    }

    function updateSlidersProgress(value) {
        //console.log("updateSlidersProgress value:"+value)
        timeSliderValue = value
        timeSliderValueText = UPnP.formatDuration(value)
    }

    function updateCoverProgress(position, duration) {
        // VISIT
        //if(trackClass !== UPnP.AudioItemType.AudioBroadcast) {
        //}
        var pLabel
        if(currentItem > -1)
          pLabel = (currentItem+1) + " of " + trackListModel.count + " - " + timeSliderValueText
        else
          pLabel = timeSliderValueText
        cover.updateProgressBar(position, duration, pLabel)
    }

    function getCurrentTrack() {
        if(currentItem < 0 || currentItem >= trackListModel.count)
            return undefined
        return trackListModel.get(currentItem)
    }

    //   0 - inactive
    //   1 - transportInfo requested
    //   2 - transportInfo received
    //   3 - positionInfo requested
    //   4 - positionInfo received
    property int refreshState: 0

    Timer {
        id: fetchRendererInfo
        interval: 1000;
        running: handleRendererInfo.running && rendererConnected
        repeat: true
        onTriggered: {

            // for Resume
            if(requestedAudioPosition != -1) {
                var r = upnp.seek(requestedAudioPosition)
                if(r === 0) {
                    requestedAudioPosition = -1
                    requestedAudioPositionRetryCount = -1
                } else {
                    requestedAudioPositionRetryCount--
                    if(requestedAudioPositionRetryCount == 0) {
                        requestedAudioPosition = -1
                        requestedAudioPositionRetryCount = -1
                    }
                }
            }

            // check and trigger update of transport state and position info
            switch(refreshState) {
            case 0:
            case 4:
                upnp.getTransportInfoJsonAsync()
                refreshState = 1
                break
            case 2:
                upnp.getPositionInfoJsonAsync()
                refreshState = 3
                break
            case 1:
            case 3:
                // do nothing
                break
            }

        }
    }

    property int failedAttempts: 0
    property int stoppedPlayingDetection: 0
    property bool rendererBusy: false
    Timer {
        id: handleRendererInfo
        interval: 1000;
        running: app.hasCurrentRenderer() && !useBuiltInPlayer
        repeat: true
        onTriggered: {

            if(rendererBusy) // some actions make the renderer unreachable
                return;

            // detect renderer has stopped unexpectedly
            if(playing && transportState == 3) {
                stoppedPlayingDetection++
                if(stoppedPlayingDetection > 3) {
                    reset()
                    stoppedPlayingDetection = 0
                    // for now stopped at the last track is considered normal
                    if(currentItem < (trackListModel.count-1))
                        app.showErrorDialog(qsTr("The renderer has stopped playing unexpectedly."))
                    return
                }
            } else
                stoppedPlayingDetection = 0

            // handle position info
            var pinfo = positionInfo
            positionInfo = undefined   // use it only once
            if(pinfo === undefined) {  // if no new info

                // pretend progress
                if(transportState === 1 && timeSliderValue > 0) {
                    updateSlidersProgress(timeSliderValue + 1)
                    updateCoverProgress(timeSliderValue + 1, timeSliderMaximumValue)
                }

                // if positionInfo is skipped on purpose
                if(skipNextPositionInfo > 0)
                    return

                // detect lost connection
                if(rendererConnected) {
                    if(failedAttempts <= 4)
                        failedAttempts++
                    if(failedAttempts == 4) {
                        rendererConnected = false
                        reset()
                        var errTxt = qsTr("Lost connection with Renderer.")
                        app.error(errTxt)
                        app.showErrorDialog(errTxt)
                    }
                }

                return

            } else
                failedAttempts = 0

            // update ui and detect track changes

            var trackuri = pinfo["trackuri"]
            var trackduration = parseInt(pinfo["trackduration"])
            var tracktime = parseInt(pinfo["reltime"])
            var abstime = parseInt(pinfo["abstime"])

            // update track meta data. for now only when playing internet radio
            var currentTrack = getCurrentTrack()
            if(currentTrack !== undefined) {
                if(skipNextPositionInfoForURI === "" && UPnP.isBroadcast(currentTrack)) {
                    if(pinfo.trackmeta
                       && pinfo.trackmeta.title
                       && pinfo.trackmeta.title.length > 0)
                        trackMetaText1 = pinfo.trackmeta.title
                    if(pinfo.trackmeta
                       && pinfo.trackmeta.properties["upnp:artist"]
                       && pinfo.trackmeta.properties["upnp:artist"].length > 0)
                        trackMetaText2 = pinfo.trackmeta.properties["upnp:artist"]
                    updateMprisForTrackMetaData(currentTrack)
                }
            }

            // track duration
            timeSliderLabel = UPnP.formatDuration(trackduration)
            //console.log("setting timeSliderLabel to "+timeSliderLabel + " based on " + trackduration);

            if(timeSliderMaximumValue != trackduration && trackduration > -1)
                timeSliderMaximumValue = trackduration

            updateSlidersProgress(tracktime)
            updateCoverProgress(tracktime, trackduration)

            // how to detect track change? uri will mostly work
            // but not when a track appears twice and next to each other.
            // upplay has a nifty solution but I am too lazy now.
            // (maybe we should start using upplay's avtransport_qo.h etc.)
            if(playing) {

                if(prevTrackURI !== "" && prevTrackURI !== trackuri) {

                    // track changed?
                    console.log("uri changed from ["+prevTrackURI + "] to [" + trackuri + "]");
                    var trackIndex = getTrackIndexForURI(trackuri)
                    if(trackIndex >= 0                // known track
                       && trackIndex !== currentItem) // changed externally
                        onChangedTrack(trackIndex)
                    else if(trackuri === "") { // no setNextAVTransportURI support?
                        if(transportInfo["tpstate"] === "Stopped")
                           next();
                    }

                } else if(tracktime === 0
                          && abstime === prevAbsTime
                          && prevTrackTime > 0) {

                    // stopped playing so load next track
                    if(transportInfo["tpstate"] === "Stopped")
                       next();

                }

            }

            // save to detect changes
            prevTrackURI = trackuri
            prevTrackDuration = trackduration
            prevTrackTime = tracktime
            prevAbsTime = abstime
        }
    }

    ConfigurationValue {
            id: use_setnexturi
            key: "/donnie/use_setnexturi"
            defaultValue: "false"
    }
}
