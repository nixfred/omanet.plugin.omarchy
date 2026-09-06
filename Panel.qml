import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: 'nixfred.net-pulse'
    ipcTarget: 'nixfred.net-pulse'
    manageIpc: false
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    readonly property string stateDir: (Quickshell.env('XDG_STATE_HOME') || Quickshell.env('HOME')+'/.local/state')+'/net-pulse'
    readonly property string helper: String(Qt.resolvedUrl('net_pulse.py')).replace(/^file:\/\//,'')
    property var net: ({})
    property var histories: ({})
    property int tab: 0
    property int page: 0
    property int wifiPage: 0
    property int range: 3600
    property bool chooseMode: false
    property string actionStatus: ''
    property real now: Date.now()/1000
    readonly property bool stale: !net.ts || now-net.ts > 12
    readonly property int mode: Model.clamp(setting('displayMode',0),0,4)
    readonly property real health: stale ? 50 : Model.health(net)
    readonly property color tint: stale ? '#71838c' : Model.ramp(health)
    readonly property string chipKind: stale || !net.online ? 'offline' : (Model.isWifi(net) ? 'wifi' : 'ethernet')
    readonly property real activity: Model.clamp(((net.rates||{}).rx||0)/8e6, 0, 1)
    readonly property var rows: (net.talkers||{}).rows || []
    readonly property var chart: histories[String(range)] || {points:[],seconds:range,now:now,bucket:15,count:0,peakRx:0,peakTx:0,peakLatency:0}
    readonly property var wifi: net.wifi || {}
    readonly property var ping: net.ping || {}
    readonly property var iface: net.iface || {}
    readonly property real openPanelIndicatorWidth: button.width-12
    readonly property var tabs: ['Overview','Wi-Fi','Interfaces','Talkers','Network lab']

    // ---- NetworkManager objects for Wi-Fi actions (passphrases never touch argv)
    readonly property bool nmAvailable: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var devices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var nmNetworks: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    property var scanDevice: null
    property string wifiSsid: ''
    property string wifiKind: ''
    property string passwordSsid: ''
    property string passwordText: ''
    property string identityText: ''
    readonly property var wifiRows: mergeWifi(net.networks || [], nmNetworks)

    function findDevice(type) {
        var fallback=null
        for (var i=0;i<devices.length;i++) { var d=devices[i]; if(!d || d.type!==type) continue; if(d.connected) return d; if(!fallback) fallback=d }
        return fallback
    }
    function netObj(ssid) {
        for (var i=0;i<nmNetworks.length;i++) if(nmNetworks[i] && nmNetworks[i].name===ssid) return nmNetworks[i]
        return null
    }
    function securityName(value) {
        try { var s=WifiSecurityType.toString(value); return s==='None'?'Open':s } catch(e) { return '' }
    }
    function mergeWifi(scan, objects) {
        var out=[], seen={}
        for (var i=0;i<scan.length;i++) {
            var r=Object.assign({}, scan[i]), o=r.hidden?null:netObj(r.ssid)
            r.known=o?!!o.known:false; r.connected=o?!!o.connected:!!r.inUse; r.changing=o?!!o.stateChanging:false; r.actionable=!!o
            out.push(r); if(!r.hidden) seen[r.ssid]=true
        }
        for (var j=0;j<objects.length;j++) {
            var n=objects[j]
            if(!n || !n.name || seen[n.name]) continue
            out.push({ssid:n.name,hidden:false,aps:1,inUse:!!n.connected,bands:[],band:'',channel:0,freq:0,rate:0,width:0,signal:Math.round((n.signalStrength||0)*100),security:securityName(n.security),known:!!n.known,connected:!!n.connected,changing:!!n.stateChanging,actionable:true})
        }
        out.sort(function(a,b){ if(a.connected!==b.connected) return a.connected?-1:1; if(a.known!==b.known) return a.known?-1:1; return b.signal-a.signal })
        return out
    }
    function needsPassphrase(row) { var s=Model.security(row.security); return s!=='Open' && s!=='Enhanced open' }
    function wifiAct(kind, ssid) {
        if(wifiKind) return
        var n=netObj(ssid)
        if(!n){ actionStatus='NetworkManager has not listed '+ssid+' yet. Give the scan a moment.'; return }
        wifiSsid=ssid; wifiKind=kind
        actionStatus=(kind==='connect'?'Connecting to ':kind==='disconnect'?'Disconnecting from ':'Forgetting ')+ssid+'…'
        if(kind==='connect') n.connect(); else if(kind==='disconnect') n.disconnect(); else n.forget()
        wifiTimeout.restart()
    }
    function wifiConnectPsk(ssid, psk) {
        if(wifiKind || !psk) return
        var n=netObj(ssid)
        if(!n){ actionStatus='NetworkManager has not listed '+ssid+' yet.'; return }
        wifiSsid=ssid; wifiKind='connect'; actionStatus='Connecting to '+ssid+'…'
        n.connectWithPsk(psk); passwordText=''
        wifiTimeout.restart()
    }
    function wifiConnectEnterprise(ssid, identity, psk) {
        if(wifiKind || !psk || !identity || eap.running) return
        wifiSsid=ssid; wifiKind='connect'; actionStatus='Connecting to '+ssid+' as '+identity+'…'
        eap.secret=psk; passwordText=''
        eap.command=['bash','-c',eap.script,'nmcli-eap',ssid,identity]
        eap.running=true
        wifiTimeout.restart()
    }
    function rowClicked(row) {
        if(!row.actionable || row.hidden || wifiKind) { if(row.hidden) actionStatus='Hidden networks need their name; add them with nmtui.'; return }
        if(row.connected){ wifiAct('disconnect',row.ssid); return }
        if(needsPassphrase(row) && !row.known){ passwordSsid=row.ssid; passwordText=''; identityText=''; return }
        wifiAct('connect',row.ssid)
    }
    function wifiDone(message) { wifiTimeout.stop(); wifiKind=''; wifiSsid=''; passwordSsid=''; actionStatus=message }
    function wifiFailed(reason) {
        var ssid=wifiSsid, row=null
        for (var i=0;i<wifiRows.length;i++) if(wifiRows[i].ssid===ssid) row=wifiRows[i]
        var secured=row?needsPassphrase(row):true
        var text=reason===ConnectionFailReason.NoSecrets&&secured?'needs a passphrase':reason===ConnectionFailReason.WifiAuthTimeout&&secured?'rejected the passphrase':reason===ConnectionFailReason.WifiNetworkLost?'went out of range':'refused the connection'
        wifiDone(ssid+' '+text+'.')
        if(secured && (reason===ConnectionFailReason.NoSecrets || reason===ConnectionFailReason.WifiAuthTimeout)) { passwordSsid=ssid; passwordText='' }
    }
    function syncScanner() {
        var want=opened && tab===1 && !chooseMode && wifiDevice
        if(want && scanDevice!==wifiDevice){ if(scanDevice) scanDevice.scannerEnabled=false; scanDevice=wifiDevice; scanDevice.scannerEnabled=true }
        else if(!want && scanDevice){ scanDevice.scannerEnabled=false; scanDevice=null }
    }
    function setMode(value) {
        root.settings=Object.assign({}, root.settings, {displayMode:Model.clamp(value,0,4)})
        if(root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName,root.settings)
    }
    function runAction(action, args, working) {
        if(actionProc.running) return
        actionStatus=working || 'Working…'
        actionProc.command=['python3',helper,action].concat(args||[])
        actionProc.running=true
    }
    // Addresses go to the clipboard as an argument, never through a shell string.
    function copy(value, what) {
        var text = String(value || '').trim()
        if (!text) return
        Quickshell.execDetached(['wl-copy', text])
        actionStatus = 'Copied ' + (what ? what + ' ' : '') + text + ' to the clipboard.'
    }
    function summon(target, payload) {
        if(root.bar && root.bar.shell) { root.close(); root.bar.shell.summon(target, JSON.stringify(payload||{})) }
    }
    function editConnection(uuid) {
        if(!root.bar || !/^[0-9a-fA-F-]{36}$/.test(uuid)) return
        root.bar.run('omarchy-launch-floating-terminal-with-presentation '+Util.shellQuote('nmtui-edit '+uuid))
        root.close()
    }
    function status() {
        return JSON.stringify({opened:opened,mode:mode,readout:Model.readout(net,mode),tint:String(tint),stale:stale,online:!!net.online,health:health,iface:iface.name||'',kind:chipKind,ssid:wifi.ssid||'',rx:(net.rates||{}).rx||0,tx:(net.rates||{}).tx||0,latency:ping.internet,samples:chart.count||0,tab:tab,chooseMode:chooseMode,networks:wifiRows.length,interfaces:(net.interfaces||[]).length,talkers:rows.length,wifiAction:wifiKind,action:actionStatus})
    }
    onOpenedChanged: { if(opened){ snapshotFile.reload(); historyFile.reload() } syncScanner() }
    onTabChanged: { page=0; wifiPage=0; syncScanner() }
    onChooseModeChanged: syncScanner()
    onWifiDeviceChanged: syncScanner()
    Component.onDestruction: if(scanDevice) scanDevice.scannerEnabled=false
    FileView {
        id:snapshotFile; path:root.stateDir+'/snapshot.json'; watchChanges:true; printErrors:false
        onFileChanged:reload()
        onLoaded:{try{var m=JSON.parse(text());if(m.ts>0)root.net=m}catch(e){}}
    }
    FileView {
        id:historyFile; path:root.stateDir+'/history.json'; watchChanges:true; printErrors:false
        onFileChanged:reload()
        onLoaded:{try{root.histories=JSON.parse(text())}catch(e){}}
    }
    Timer { interval:2000; running:true; repeat:true; onTriggered:{root.now=Date.now()/1000; if(root.stale)snapshotFile.reload()} }
    Timer {
        id:wifiPoll; interval:500; repeat:true; running:root.wifiKind!==''
        onTriggered:{
            var n=root.netObj(root.wifiSsid)
            if(!n){ if(root.wifiKind==='forget') root.wifiDone('Forgot '+root.wifiSsid+'.'); return }
            if(root.wifiKind==='connect' && n.connected) root.wifiDone('Connected to '+root.wifiSsid+'.')
            else if(root.wifiKind==='disconnect' && !n.connected && !n.stateChanging) root.wifiDone('Disconnected from '+root.wifiSsid+'.')
            else if(root.wifiKind==='forget' && !n.known && !n.stateChanging) root.wifiDone('Forgot '+root.wifiSsid+'.')
        }
    }
    // Outlasts NetworkManager's 25-second supplicant timeout so a wrong saved passphrase still reports as such.
    Timer { id:wifiTimeout; interval:30000; onTriggered:if(root.wifiKind) root.wifiDone('Timed out while '+(root.wifiKind==='connect'?'connecting to ':root.wifiKind==='disconnect'?'disconnecting from ':'forgetting ')+root.wifiSsid+'.') }
    Connections {
        target: root.wifiKind ? root.netObj(root.wifiSsid) : null
        ignoreUnknownSignals: true
        function onConnectionFailed(reason) { root.wifiFailed(reason) }
    }
    // 802.1X profiles: the password goes over stdin into nmcli's scripted editor. argv is world-readable; stdin is not.
    Process {
        id:eap
        property string secret:''
        readonly property string script: "u=$(uuidgen); IFS= read -r pw; nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\" wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity \"$2\" 802-1x.auth-timeout 8 >/dev/null && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null && nmcli connection up uuid \"$u\" || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"
        stdinEnabled:true
        onStarted:{ write(secret+'\n'); secret='' }
        onExited:function(code){ if(code!==0 && root.wifiKind==='connect') root.wifiDone('Enterprise login to '+root.wifiSsid+' was refused.') }
    }
    Process {
        id:actionProc
        stdout:StdioCollector { onStreamFinished:{try{var r=JSON.parse(text);root.actionStatus=r.error || r.message || 'Done';if(!r.error && r.message && r.message.indexOf('Focused ')===0)root.close()}catch(e){root.actionStatus='Action could not complete.'}} }
        onExited:function(code){if(code!==0 && root.actionStatus.indexOf('…')>=0)root.actionStatus='Action could not complete.'}
    }
    IpcHandler {
        target:'nixfred.net-pulse'
        function open():void {root.chooseMode=false;root.open()}
        function close():void {root.close()}
        function toggle():void {root.chooseMode=false;root.toggle()}
        function status():string {return root.status()}
        function modes():void {root.chooseMode=true;root.open()}
        function display(value:int):void {root.setMode(value)}
        function showTab(value:int):void {root.tab=Model.clamp(value,0,4);root.chooseMode=false;root.open()}
        function historyRange(value:int):void {if([3600,86400,604800].indexOf(value)>=0)root.range=value}
        function rescan():void {root.runAction('rescan',[],'Scanning…')}
        function toggleNetwork():void {if(root.nmAvailable) Networking.wifiEnabled=!Networking.wifiEnabled}
    }
    WidgetButton {
        id:button; anchors.fill:parent;bar:root.bar;labelVisible:false;hasVisualContent:true
        fixedWidth:vertical?-1:barRow.implicitWidth+12
        tooltipText:'Net Pulse · '+(root.stale?'Telemetry offline':!root.net.online?'No route to the internet':(Model.isWifi(root.net)?root.wifi.ssid+' · '+Model.whole(root.wifi.quality)+' signal':(root.iface.connection||root.iface.name)+' · '+Model.mbit(root.iface.speed))+' · ↓ '+Model.rate((root.net.rates||{}).rx)+' ↑ '+Model.rate((root.net.rates||{}).tx)+' · '+Model.ms(root.ping.internet))+'\nLeft-click: dashboard · Right-click: readout'
        onPressed:function(b){if(b===Qt.RightButton){root.chooseMode=true;root.open()}else{root.chooseMode=false;root.toggle()}}
        Row {
            id:barRow;anchors.centerIn:parent;spacing:4
            NetChip {compact:true;kind:root.chipKind;level:root.health/100;activity:root.activity;tint:root.tint;animate:!root.stale && root.setting('animated',true)}
            Column {
                anchors.verticalCenter:parent.verticalCenter
                Text {text:root.stale?'—':Model.readout(root.net,root.mode);color:root.barForeground;font.family:Style.font.family;font.pixelSize:12;font.bold:true}
                Text {text:Model.modeTag(root.net,root.mode);color:root.tint;font.pixelSize:7;font.letterSpacing:0.6}
            }
        }
    }
    component Label: Text { color:'#91a5b0';font.pixelSize:12;textFormat:Text.PlainText }
    component Heading: Text { color:'#eff7fa';font.pixelSize:15;font.bold:true;textFormat:Text.PlainText }
    component Action: Rectangle {
        id:act
        property string text:''
        property bool selected:false
        property bool enabled:true
        property color accent:root.tint
        signal clicked()
        implicitWidth:caption.implicitWidth+26;implicitHeight:34
        radius:9;color:act.selected?Qt.alpha(accent,0.18):area.containsMouse&&act.enabled?'#22333f':'#14222b'
        border.color:act.selected?accent:area.containsMouse&&act.enabled?'#536a76':'#2a3b47'
        opacity:act.enabled?1:0.45
        Behavior on color {ColorAnimation{duration:120}}
        Text{id:caption;anchors.centerIn:parent;text:act.text;color:act.selected?'#ffffff':'#c3d3dc';font.pixelSize:12;font.bold:act.selected;textFormat:Text.PlainText}
        MouseArea{id:area;anchors.fill:parent;hoverEnabled:true;cursorShape:act.enabled?Qt.PointingHandCursor:Qt.ArrowCursor;onClicked:if(act.enabled)act.clicked()}
    }
    component Stat: Rectangle {
        id:stat
        property string label:''
        property string value:''
        property string hint:''
        property string copyText:''
        property string copyWhat:''
        readonly property bool copyable: copyText !== ''
        radius:12
        color:stat.copyable&&statArea.containsMouse?'#17262f':'#111e28'
        border.color:stat.copyable&&statArea.containsMouse?Qt.alpha(root.tint,0.6):'#253744'
        Behavior on color {ColorAnimation{duration:110}}
        Column {anchors.fill:parent;anchors.margins:12;spacing:5
            Label{text:stat.label;font.pixelSize:10;font.letterSpacing:1}
            // Long addresses shrink to fit rather than losing their last octets.
            Heading{text:stat.value;font.pixelSize:20;width:parent.width;elide:Text.ElideRight
                fontSizeMode:Text.HorizontalFit;minimumPixelSize:11}
            Label{text:stat.hint;font.pixelSize:10;width:parent.width;elide:Text.ElideRight}
        }
        Text{visible:stat.copyable&&statArea.containsMouse;text:'⧉';color:root.tint;font.pixelSize:12
            anchors.right:parent.right;anchors.top:parent.top;anchors.rightMargin:8;anchors.topMargin:6}
        MouseArea{id:statArea;anchors.fill:parent;hoverEnabled:stat.copyable;enabled:stat.copyable
            cursorShape:Qt.PointingHandCursor;onClicked:root.copy(stat.copyText,stat.copyWhat)}
    }
    component Node: Rectangle {
        id:node
        property string label:''
        property string value:''
        property string hint:''
        property bool ok:true
        property string copyWhat:''
        readonly property bool copyable: Model.isAddress(node.value)
        radius:10
        color:node.copyable&&nodeArea.containsMouse?'#17262f':'#101c26'
        border.color:node.copyable&&nodeArea.containsMouse?root.tint:node.ok?Qt.alpha(root.tint,0.5):'#7a3a4a'
        Behavior on color {ColorAnimation{duration:110}}
        Column{anchors.centerIn:parent;spacing:3;width:parent.width-16
            Label{text:node.label;font.pixelSize:9;font.letterSpacing:1;horizontalAlignment:Text.AlignHCenter;width:parent.width}
            Heading{text:node.value;font.pixelSize:12;horizontalAlignment:Text.AlignHCenter;width:parent.width;elide:Text.ElideMiddle
                fontSizeMode:Text.HorizontalFit;minimumPixelSize:9}
            Label{text:node.hint;font.pixelSize:9;horizontalAlignment:Text.AlignHCenter;width:parent.width;elide:Text.ElideRight;color:node.ok?'#91a5b0':'#f0ba82'}
        }
        MouseArea{id:nodeArea;anchors.fill:parent;hoverEnabled:node.copyable;enabled:node.copyable
            cursorShape:Qt.PointingHandCursor;onClicked:root.copy(node.value,node.copyWhat)}
    }
    KeyboardPanel {
        id:panel;anchorItem:button;owner:root;bar:root.bar;open:root.opened;focusTarget:body
        contentWidth:panel.fittedContentWidth(root.chooseMode?370:740)
        contentHeight:panel.fittedContentHeight(root.chooseMode?modeColumn.implicitHeight:mainColumn.implicitHeight)
        Item {
            id:body;anchors.fill:parent;focus:true
            Keys.onEscapePressed:root.close()
            Keys.onPressed:function(event){
                if(event.key===Qt.Key_Left && !root.chooseMode){root.tab=Math.max(0,root.tab-1);event.accepted=true}
                if(event.key===Qt.Key_Right && !root.chooseMode){root.tab=Math.min(4,root.tab+1);event.accepted=true}
                if(root.chooseMode && event.key>=Qt.Key_1 && event.key<=Qt.Key_5){root.setMode(event.key-Qt.Key_1);event.accepted=true}
            }
            Rectangle {anchors.fill:parent;anchors.margins:-10;radius:14;color:'#0b141d'}
            Column {
                id:modeColumn;width:parent.width;spacing:12;visible:root.chooseMode
                Heading{text:'BAR READOUT';font.letterSpacing:1.5}
                Label{text:'Choose what lives beside the chip.'}
                Repeater {
                    model:5
                    Action {
                        required property int index
                        width:modeColumn.width;height:44;selected:root.mode===index
                        text:(index+1)+'.  '+Model.modeName(index)+'   ·   '+Model.readout(root.net,index)
                        onClicked:root.setMode(index)
                    }
                }
                Action{text:'Open network dashboard →';width:parent.width;onClicked:root.chooseMode=false}
            }
            Column {
                id:mainColumn;width:parent.width;spacing:14;visible:!root.chooseMode
                Row {
                    width:parent.width;spacing:10
                    Column {width:parent.width-250;spacing:3
                        Heading{text:'NET PULSE';font.pixelSize:19;font.letterSpacing:3}
                        Label{text:'Your connection, in motion.';font.pixelSize:11}
                    }
                    Rectangle {width:240;height:32;radius:16;color:Qt.alpha(root.tint,0.14);border.color:Qt.alpha(root.tint,0.5)
                        Row {anchors.centerIn:parent;spacing:7
                            Rectangle {width:6;height:6;radius:3;color:root.tint;anchors.verticalCenter:parent.verticalCenter
                                SequentialAnimation on opacity {running:root.opened&&!root.stale;loops:Animation.Infinite;NumberAnimation{to:0.3;duration:900}NumberAnimation{to:1;duration:900}}
                            }
                            Label{text:root.stale?'WAITING FOR TELEMETRY':Model.healthLabel(root.net);color:'#e4edf0';font.pixelSize:9;font.bold:true}
                        }
                    }
                }
                Row {spacing:8
                    Repeater {model:root.tabs
                        Action {required property int index;required property string modelData;text:modelData;selected:root.tab===index;onClicked:root.tab=index}
                    }
                }
                // ------------------------------------------------------------ Overview
                Column {
                    width:parent.width;spacing:14;visible:root.tab===0
                    height:visible?implicitHeight:0
                    Rectangle {
                        width:parent.width;height:170;radius:16;border.color:Qt.alpha(root.tint,0.45)
                        gradient:Gradient {GradientStop{position:0;color:Qt.alpha(root.tint,0.13)}GradientStop{position:1;color:'#111d27'}}
                        NetChip {x:12;y:5;width:160;height:160;kind:root.chipKind;level:root.health/100;activity:root.activity;tint:root.tint;animate:root.opened&&root.tab===0&&!root.stale&&root.setting('animated',true)}
                        Column {x:188;y:18;spacing:5;width:parent.width-330
                            Label{text:'DOWNLOAD  ·  UPLOAD';font.pixelSize:11;font.letterSpacing:2}
                            Row {spacing:14
                                Text {text:root.stale||!root.net.online?'—':Model.rate((root.net.rates||{}).rx);color:'#f4fafc';font.pixelSize:42;font.weight:Font.Light}
                                Text {text:root.stale||!root.net.online?'':'↑ '+Model.rate((root.net.rates||{}).tx);color:'#8d9dff';font.pixelSize:20;font.weight:Font.Light;anchors.bottom:parent.bottom;anchors.bottomMargin:8}
                            }
                            Label{text:root.stale?'Waiting for the net-pulse service.':!root.net.online?'No default route. Nothing is carrying traffic to the internet.':(Model.isWifi(root.net)?root.wifi.ssid+'  ·  '+(root.wifi.band||'')+(root.wifi.channel?' channel '+root.wifi.channel:''):(root.iface.connection||Model.kindName(root.iface.kind)))+'  ·  '+root.iface.name+'  ·  '+((root.iface.addrs4||[])[0]||(root.iface.addrs6||[])[0]||'no address').split('/')[0];color:'#c4d6dc';width:parent.width;elide:Text.ElideRight}
                            Label{text:root.net.online?'Gateway '+(root.iface.gateway||'—')+' · '+Model.ms(root.ping.gateway)+'    Internet 1.1.1.1 · '+Model.ms(root.ping.internet)+(Model.num(root.ping.loss)>0?'  ·  '+Model.whole(root.ping.loss)+' loss':'')+'    ·  click any address to copy it':'Pings pause until a route appears.';font.pixelSize:10}
                        }
                        Text {anchors.right:parent.right;anchors.rightMargin:20;anchors.top:parent.top;anchors.topMargin:22;horizontalAlignment:Text.AlignRight;color:Qt.alpha('#edf7fa',0.5);font.pixelSize:15
                            text:root.stale||!root.net.online?'':Model.isWifi(root.net)?Model.whole(root.wifi.quality)+'\nsignal':Model.mbit(root.iface.speed)+'\nlink'}
                    }
                    Row {width:parent.width;spacing:10
                        Stat{width:(parent.width-30)/4;height:96;label:'LATENCY';value:Model.ms(root.ping.internet);hint:'Gateway '+Model.ms(root.ping.gateway)+' · loss '+Model.whole(root.ping.loss)}
                        Stat{width:(parent.width-30)/4;height:96;label:Model.isWifi(root.net)?'SIGNAL':'LINK';value:Model.isWifi(root.net)?Model.dbm(root.wifi.signal):Model.mbit(root.iface.speed);hint:Model.isWifi(root.net)?Model.whole(root.wifi.quality)+' quality · '+(root.wifi.generation||''):(root.iface.duplex?root.iface.duplex+' duplex · ':'')+'MTU '+(root.iface.mtu||'—')}
                        Stat{width:(parent.width-30)/4;height:96;label:'THIS ADDRESS';value:Model.bare((root.iface.addrs4||[])[0]||(root.iface.addrs6||[])[0]||'—')
                            hint:'↓ '+Model.size((root.net.totals||{}).rx)+' ↑ '+Model.size((root.net.totals||{}).tx)+' on '+(root.iface.name||'—')
                            copyText:Model.bare((root.iface.addrs4||[])[0]||(root.iface.addrs6||[])[0]);copyWhat:'this address'}
                        Stat{width:(parent.width-30)/4;height:96;label:'CONNECTIVITY';value:root.net.online?String(root.net.connectivity||'unknown').replace(/^./,function(c){return c.toUpperCase()}):'Offline';hint:'DNS via '+((root.net.dns||{}).provider||'—')+' · '+String(root.net.nmState||'')}
                    }
                    Rectangle {width:parent.width;height:242;radius:14;color:'#101c26';border.color:'#273843'
                        Column {anchors.fill:parent;anchors.margins:14;spacing:9
                            Item {width:parent.width;height:30
                                Heading{anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter;text:'CONTINUOUS HISTORY';font.pixelSize:12}
                                Row{anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;spacing:7
                                    Repeater{model:[{t:'1 hour',s:3600},{t:'24 hours',s:86400},{t:'7 days',s:604800}]
                                        Action{required property var modelData;text:modelData.t;selected:root.range===modelData.s;implicitWidth:68;implicitHeight:28;onClicked:root.range=modelData.s}
                                    }
                                }
                            }
                            HistoryGraph{width:parent.width;height:139;historyData:root.chart;tint:root.tint}
                            Row{spacing:14
                                Label{text:'━ Download';color:root.tint;font.pixelSize:10}
                                Label{text:'━ Upload';color:'#8d9dff';font.pixelSize:10}
                                Label{text:'┅ Latency';color:'#f0ba82';font.pixelSize:10}
                                Label{text:'Peak ↓ '+Model.rate(root.chart.peakRx)+'  ·  ↓ '+Model.size(root.chart.totalRx)+' ↑ '+Model.size(root.chart.totalTx)+' in range  ·  '+(root.chart.count||0)+' samples';font.pixelSize:10}
                            }
                            Label{text:(root.chart.count||0)<2?'History is starting. Samples accumulate every 15 seconds.':'Recording while closed · 7-day retention · hover to inspect · faint line = download peaks';font.pixelSize:10}
                        }
                    }
                    Rectangle {width:parent.width;height:112;radius:14;color:'#121b2c';border.color:'#303a57'
                        Column{anchors.fill:parent;anchors.margins:14;spacing:9
                            Heading{text:'PATH TO THE INTERNET';font.pixelSize:12}
                            Row{width:parent.width;spacing:0
                                Node{width:(parent.width-3*22)/4;height:60;label:'THIS DEVICE';value:Model.bare((root.iface.addrs4||[])[0]||(root.iface.addrs6||[])[0]||'—');hint:root.iface.name?root.iface.name+' · '+(root.iface.mac||''):'no interface';ok:!!root.net.online;copyWhat:'this address'}
                                Label{text:'→';width:22;horizontalAlignment:Text.AlignHCenter;anchors.verticalCenter:parent.verticalCenter;color:root.tint;font.pixelSize:16}
                                Node{width:(parent.width-3*22)/4;height:60;label:'GATEWAY';value:root.iface.gateway||'—';hint:Model.ms(root.ping.gateway)+' round trip';ok:Model.num(root.ping.gateway)>=0||!Model.has(root.ping.gateway);copyWhat:'the gateway'}
                                Label{text:'→';width:22;horizontalAlignment:Text.AlignHCenter;anchors.verticalCenter:parent.verticalCenter;color:root.tint;font.pixelSize:16}
                                Node{width:(parent.width-3*22)/4;height:60;label:'DNS';value:currentDns();hint:((root.net.dns||{}).provider||'—')+' · '+dnsCount()+' servers';ok:true;copyWhat:'the resolver'}
                                Label{text:'→';width:22;horizontalAlignment:Text.AlignHCenter;anchors.verticalCenter:parent.verticalCenter;color:root.tint;font.pixelSize:16}
                                Node{width:(parent.width-3*22)/4;height:60;label:'INTERNET';value:'1.1.1.1';hint:Model.ms(root.ping.internet)+' round trip · '+String(root.net.connectivity||'unknown');ok:Model.num(root.ping.internet)>=0||!Model.has(root.ping.internet);copyWhat:'the probe target'}
                            }
                        }
                    }
                }
                // ------------------------------------------------------------ Wi-Fi
                Column {
                    width:parent.width;spacing:12;visible:root.tab===1;height:visible?implicitHeight:0
                    Item{width:parent.width;height:32
                        Heading{anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter;text:'RADIO';font.pixelSize:13}
                        Row{anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;spacing:8
                            Action{text:Networking.wifiEnabled?'Wi-Fi on':'Wi-Fi off';selected:Networking.wifiEnabled;enabled:root.nmAvailable&&!!root.wifiDevice;implicitHeight:30;onClicked:{Networking.wifiEnabled=!Networking.wifiEnabled;root.actionStatus=Networking.wifiEnabled?'Turning the radio off…':'Turning the radio on…'}}
                            Action{text:'Rescan';enabled:!!root.wifiDevice&&Networking.wifiEnabled;implicitHeight:30;onClicked:root.runAction('rescan',[],'Scanning for nearby networks…')}
                            Action{text:'Share QR';enabled:Model.isWifi(root.net);implicitHeight:30;onClicked:root.summon('omarchy.wifiqr',{iface:root.iface.name,ssid:root.wifi.ssid})}
                        }
                    }
                    Rectangle{visible:!root.wifiDevice;width:parent.width;height:visible?70:0;radius:12;color:'#111e28';border.color:'#253744'
                        Label{anchors.centerIn:parent;text:root.nmAvailable?'No Wi-Fi radio is known to NetworkManager on this machine.':'NetworkManager is not available; Wi-Fi controls are inert.'}
                    }
                    Rectangle {visible:Model.isWifi(root.net);width:parent.width;height:visible?196:0;radius:16;border.color:Qt.alpha(root.tint,0.45)
                        gradient:Gradient {GradientStop{position:0;color:Qt.alpha(root.tint,0.10)}GradientStop{position:1;color:'#111d27'}}
                        Column{anchors.fill:parent;anchors.margins:14;spacing:10
                            Row{width:parent.width
                                Column{width:parent.width-260;spacing:3
                                    Heading{text:root.wifi.ssid||'—';font.pixelSize:18;width:parent.width;elide:Text.ElideRight}
                                    Label{text:(root.wifi.bssid||'').toUpperCase()+'  ·  '+Model.security(root.wifi.security)+'  ·  '+(root.wifi.generation||'')+'  ·  '+(root.iface.driver||'');font.pixelSize:10}
                                }
                                Label{text:'connected '+Model.ago(root.wifi.connectedSeconds);width:260;horizontalAlignment:Text.AlignRight;color:'#c4d6dc'}
                            }
                            Grid{width:parent.width;columns:3;spacing:10
                                Stat{width:(parent.width-20)/3;height:62;label:'SIGNAL';value:Model.dbm(root.wifi.signal)+'  ·  '+Model.whole(root.wifi.quality);hint:'average '+Model.dbm(root.wifi.signalAvg)+' · tx power '+(Model.has(root.wifi.txPower)?root.wifi.txPower+' dBm':'—')}
                                Stat{width:(parent.width-20)/3;height:62;label:'CHANNEL';value:(root.wifi.channel?'CH '+root.wifi.channel:'—')+'  ·  '+(root.wifi.band||'');hint:(root.wifi.width?root.wifi.width+' MHz wide':'')+(root.wifi.freq?' · '+root.wifi.freq+' MHz':'')}
                                Stat{width:(parent.width-20)/3;height:62;label:'LINK RATE';value:'↑ '+Model.mbit(root.wifi.txBitrate);hint:'↓ '+Model.mbit(root.wifi.rxBitrate)+' · '+(root.wifi.txMode||'')}
                            }
                            Label{text:'Retries '+Model.count(root.wifi.retries)+'  ·  failed '+Model.count(root.wifi.failed)+'  ·  beacon loss '+Model.count(root.wifi.beaconLoss)+'  ·  ↓ '+Model.size(root.wifi.rxBytes)+' ↑ '+Model.size(root.wifi.txBytes)+' on this association';font.pixelSize:10}
                        }
                    }
                    Row{visible:!!root.wifiDevice&&((root.net.band||{}).available||[]).length>0;width:parent.width;spacing:8
                        Label{text:'WI-FI BAND';font.pixelSize:10;font.letterSpacing:1;anchors.verticalCenter:parent.verticalCenter;width:90}
                        Repeater{model:['auto'].concat(((root.net.band||{}).available||[]).filter(function(b){return ['2.4','5','6'].indexOf(b)>=0}))
                            Action{required property string modelData;text:modelData==='auto'?'Automatic':modelData+' GHz';selected:((root.net.band||{}).selected||'auto')===modelData;implicitHeight:28;enabled:Model.isWifi(root.net);onClicked:root.runAction('band',[modelData],'Pinning the band and reassociating…')}
                        }
                        Label{text:'now on '+((root.net.band||{}).band?(root.net.band.band+' GHz'):'—');font.pixelSize:10;anchors.verticalCenter:parent.verticalCenter}
                    }
                    Row{width:parent.width;visible:!!root.wifiDevice
                        Heading{text:'NEARBY NETWORKS';width:parent.width-260;font.pixelSize:13}
                        Label{text:root.wifiRows.length+' networks · scanning while this tab is open';font.pixelSize:10;width:260;horizontalAlignment:Text.AlignRight}
                    }
                    Repeater {
                        model:root.wifiRows.slice(root.wifiPage*8,root.wifiPage*8+8)
                        Rectangle {
                            id:wrow
                            required property var modelData
                            required property int index
                            readonly property bool prompting:root.passwordSsid!==''&&root.passwordSsid===modelData.ssid
                            readonly property bool busy:root.wifiKind!==''&&root.wifiSsid===modelData.ssid
                            readonly property bool enterprise:Model.security(modelData.security)==='Enterprise'
                            width:mainColumn.width;height:prompting?(enterprise?128:92):58;radius:10
                            color:wmouse.containsMouse||prompting?'#1d303b':'#111e28';border.color:modelData.connected?root.tint:wmouse.containsMouse?'#536a76':'#263844'
                            Behavior on height{NumberAnimation{duration:140}}
                            Rectangle{x:12;y:44;width:(parent.width-24)*Model.clamp(wrow.modelData.signal/100,0,1);height:2;radius:1;color:wrow.modelData.connected?root.tint:'#4d6b7a'}
                            Label{x:12;y:19;text:Model.whole(wrow.modelData.signal);font.pixelSize:12;color:wrow.modelData.connected?root.tint:'#91a5b0';width:34}
                            Column{x:52;y:9;spacing:4;width:parent.width-300
                                Heading{text:(wrow.modelData.hidden?'Hidden network':wrow.modelData.ssid)+(wrow.modelData.aps>1?'  ·  '+wrow.modelData.aps+' access points':'');font.pixelSize:13;width:parent.width;elide:Text.ElideRight;color:wrow.modelData.hidden?'#91a5b0':'#eff7fa'}
                                Label{text:Model.security(wrow.modelData.security)+(wrow.modelData.band?'  ·  '+(wrow.modelData.bands&&wrow.modelData.bands.length>1?wrow.modelData.bands.join(' + '):wrow.modelData.band):'')+(wrow.modelData.channel?'  ·  CH '+wrow.modelData.channel:'')+(wrow.modelData.rate?'  ·  up to '+Model.mbit(wrow.modelData.rate):'')+(wrow.modelData.width?'  ·  '+wrow.modelData.width+' MHz':'');font.pixelSize:10;width:parent.width;elide:Text.ElideRight}
                            }
                            Row{anchors.right:parent.right;anchors.rightMargin:12;y:12;spacing:8
                                Label{visible:wrow.modelData.known&&!wrow.modelData.connected&&!wrow.busy;text:'saved';font.pixelSize:10;anchors.verticalCenter:parent.verticalCenter}
                                Action{visible:wrow.modelData.known&&!wrow.modelData.connected&&!wrow.busy&&root.wifiKind==='';text:'Forget';implicitHeight:28;implicitWidth:66;onClicked:root.wifiAct('forget',wrow.modelData.ssid)}
                                Label{text:wrow.busy?(root.wifiKind==='connect'?'Connecting…':root.wifiKind==='disconnect'?'Disconnecting…':'Forgetting…'):wrow.modelData.connected?'Connected  ·  disconnect ⏏':wrow.modelData.hidden?'':wrow.modelData.known?'connect ↗':root.needsPassphrase(wrow.modelData)?'passphrase 🔒':'open · connect ↗';color:wrow.modelData.connected?root.tint:'#c3d3dc';font.pixelSize:11;anchors.verticalCenter:parent.verticalCenter}
                            }
                            MouseArea{id:wmouse;x:0;y:0;width:parent.width;height:58;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.rowClicked(wrow.modelData)}
                            Column{visible:wrow.prompting;x:52;y:54;width:parent.width-64;spacing:6
                                TextField{id:idField;visible:wrow.enterprise;width:parent.width-190;placeholderText:'Identity (user@domain)';font.family:Style.font.family;font.pixelSize:12;text:wrow.prompting?root.identityText:'';onTextChanged:if(wrow.prompting&&text!==root.identityText)root.identityText=text;onAccepted:pwField.forceActiveFocus();Keys.onEscapePressed:root.passwordSsid=''}
                                Row{width:parent.width;spacing:8
                                    TextField{id:pwField;width:parent.width-190;password:true;placeholderText:'Passphrase';font.family:Style.font.family;font.pixelSize:12;text:wrow.prompting?root.passwordText:'';onTextChanged:if(wrow.prompting&&text!==root.passwordText)root.passwordText=text
                                        onAccepted:if(wrow.enterprise)root.wifiConnectEnterprise(wrow.modelData.ssid,root.identityText,root.passwordText);else root.wifiConnectPsk(wrow.modelData.ssid,root.passwordText)
                                        Keys.onEscapePressed:root.passwordSsid=''
                                        onVisibleChanged:if(visible&&!wrow.enterprise)Qt.callLater(forceActiveFocus)}
                                    Action{text:'Connect';implicitHeight:30;implicitWidth:86;enabled:root.passwordText.length>=8&&(!wrow.enterprise||root.identityText.length>0);onClicked:if(wrow.enterprise)root.wifiConnectEnterprise(wrow.modelData.ssid,root.identityText,root.passwordText);else root.wifiConnectPsk(wrow.modelData.ssid,root.passwordText)}
                                    Action{text:'Cancel';implicitHeight:30;implicitWidth:80;onClicked:{root.passwordSsid='';root.passwordText=''}}
                                }
                            }
                        }
                    }
                    Row{spacing:10;visible:root.wifiRows.length>8
                        Action{text:'← Previous';opacity:root.wifiPage>0?1:0.4;onClicked:root.wifiPage=Math.max(0,root.wifiPage-1)}
                        Label{text:(root.wifiPage+1)+' / '+Math.max(1,Math.ceil(root.wifiRows.length/8));anchors.verticalCenter:parent.verticalCenter}
                        Action{text:'Next →';opacity:(root.wifiPage+1)*8<root.wifiRows.length?1:0.4;onClicked:root.wifiPage=Math.min(Math.max(0,Math.ceil(root.wifiRows.length/8)-1),root.wifiPage+1)}
                    }
                    Label{width:parent.width;wrapMode:Text.WordWrap;text:'Connect, disconnect and forget go through NetworkManager as your user. Passphrases travel over D-Bus or stdin, never on a command line, and are not stored by this plugin. Band pins reassociate and may drop the link for a few seconds.';font.pixelSize:10}
                }
                // ------------------------------------------------------------ Interfaces
                Column {
                    width:parent.width;spacing:12;visible:root.tab===2;height:visible?implicitHeight:0
                    Row{width:parent.width
                        Heading{text:'EVERY INTERFACE';width:parent.width-260;font.pixelSize:13}
                        Label{text:(root.net.interfaces||[]).length+' links · loopback hidden';font.pixelSize:10;width:260;horizontalAlignment:Text.AlignRight}
                    }
                    Rectangle{visible:!(root.net.interfaces||[]).some(function(i){return i.kind==='ethernet'});width:parent.width;height:visible?44:0;radius:10;color:'#111e28';border.color:'#253744'
                        Label{anchors.centerIn:parent;text:'No wired Ethernet adapter is present. A USB or dock adapter appears here the moment the kernel sees it.';font.pixelSize:11}
                    }
                    Repeater{
                        model:root.net.interfaces||[]
                        Rectangle{
                            id:card
                            required property var modelData
                            readonly property var s:modelData.settings||{}
                            readonly property bool managed:!!(modelData.nm&&modelData.nm.uuid)
                            readonly property bool connected:modelData.nm&&String(modelData.nm.state||'').indexOf('connected')===0
                            width:mainColumn.width;height:col.implicitHeight+28;radius:14;color:modelData.active?'#101c26':'#0f1922';border.color:modelData.active?Qt.alpha(root.tint,0.5):'#273843'
                            Column{id:col;anchors.fill:parent;anchors.margins:14;spacing:10
                                Row{width:parent.width
                                    Column{width:parent.width-250;spacing:3
                                        Heading{text:card.modelData.name+'  ·  '+Model.kindName(card.modelData.kind)+(card.modelData.active?'  ·  default route':'');font.pixelSize:14;color:card.modelData.active?'#eff7fa':'#c3d3dc'}
                                        Label{text:(card.modelData.nm&&card.modelData.nm.connection?'“'+card.modelData.nm.connection+'”  ·  ':'')+String(card.modelData.operstate||'').toUpperCase()+(card.modelData.carrier?'  ·  carrier':'  ·  no carrier')+(card.modelData.driver?'  ·  '+card.modelData.driver:'')+'  ·  '+(card.modelData.mac||'').toUpperCase();font.pixelSize:10;width:parent.width;elide:Text.ElideRight}
                                    }
                                    Label{text:'↓ '+Model.rate(card.modelData.rates.rx)+'   ↑ '+Model.rate(card.modelData.rates.tx);width:250;horizontalAlignment:Text.AlignRight;color:'#c4d6dc'}
                                }
                                Grid{width:parent.width;columns:4;spacing:8
                                    Stat{width:(parent.width-24)/4;height:66;label:'IPv4';value:((card.modelData.addrs4||[])[0]||'—')
                                        hint:(card.modelData.addrs6||[]).length?(card.modelData.addrs6.length+' IPv6 · '+Model.bare(card.modelData.addrs6[0])):'no global IPv6'
                                        copyText:Model.bare((card.modelData.addrs4||[])[0]);copyWhat:card.modelData.name+' IPv4'}
                                    Stat{width:(parent.width-24)/4;height:66;label:card.modelData.kind==='ethernet'?'LINK':'MTU · LINK';value:card.modelData.kind==='ethernet'?Model.mbit(card.modelData.speed):'MTU '+card.modelData.mtu;hint:card.modelData.kind==='ethernet'?(card.modelData.duplex?card.modelData.duplex+' duplex · ':'')+'MTU '+card.modelData.mtu:card.modelData.kind==='wifi'&&card.modelData.active?'↑ '+Model.mbit(root.wifi.txBitrate)+' radio':(card.modelData.nm&&card.modelData.nm.type)||card.modelData.kind}
                                    Stat{width:(parent.width-24)/4;height:66;label:(card.modelData.addrs6||[]).length?'IPv6':'TOTALS'
                                        value:(card.modelData.addrs6||[]).length?Model.bare(card.modelData.addrs6[0]):'↓ '+Model.size(card.modelData.stats.rx)
                                        hint:(card.modelData.addrs6||[]).length?'↓ '+Model.size(card.modelData.stats.rx)+' ↑ '+Model.size(card.modelData.stats.tx):'↑ '+Model.size(card.modelData.stats.tx)+' · '+Model.count(card.modelData.stats.rxPackets+card.modelData.stats.txPackets)+' packets'
                                        copyText:(card.modelData.addrs6||[]).length?Model.bare(card.modelData.addrs6[0]):'';copyWhat:card.modelData.name+' IPv6'}
                                    Stat{width:(parent.width-24)/4;height:66;label:'ERRORS · DROPS';value:Model.count(card.modelData.stats.rxErrors+card.modelData.stats.txErrors)+'  ·  '+Model.count(card.modelData.stats.rxDropped+card.modelData.stats.txDropped);hint:'rx '+card.modelData.stats.rxErrors+'/'+card.modelData.stats.rxDropped+' · tx '+card.modelData.stats.txErrors+'/'+card.modelData.stats.txDropped}
                                }
                                Label{visible:card.managed;width:parent.width;elide:Text.ElideRight;font.pixelSize:10;color:'#a4b9c3'
                                    text:'IPv4 '+(card.s.method4||'—')+(card.s.addresses4?' '+card.s.addresses4:'')+(card.s.gateway4?' via '+card.s.gateway4:'')+'  ·  IPv6 '+(card.s.method6||'—')+'  ·  DNS '+(card.s.dns4?card.s.dns4+(card.s.ignoreAutoDns?' (DHCP DNS ignored)':''):'from DHCP')+'  ·  autoconnect '+(card.s.autoconnect?'on':'off')+(card.s.metered&&card.s.metered!=='unknown'?'  ·  metered '+card.s.metered:'')+(card.s.wakeOnLan&&card.s.wakeOnLan!=='default'?'  ·  wake-on-LAN '+card.s.wakeOnLan:'')}
                                Row{spacing:8
                                    Action{visible:card.managed&&String(card.modelData.nm.state||'').indexOf('externally')<0;text:card.connected?'Disconnect':'Connect';implicitHeight:28;enabled:!actionProc.running&&card.modelData.kind!=='wifi'||!card.connected;onClicked:root.runAction('connection',[card.connected?'down':'up',card.modelData.nm.uuid],(card.connected?'Deactivating ':'Activating ')+card.modelData.nm.connection+'…')}
                                    Action{visible:card.managed;text:'Autoconnect '+(card.s.autoconnect?'on':'off');selected:!!card.s.autoconnect;implicitHeight:28;enabled:!actionProc.running;onClicked:root.runAction('autoconnect',[card.modelData.nm.uuid,card.s.autoconnect?'no':'yes'],'Updating autoconnect…')}
                                    Action{visible:card.managed;text:'Edit connection…';implicitHeight:28;onClicked:root.editConnection(card.modelData.nm.uuid)}
                                    Label{visible:!card.managed;text:card.modelData.nm&&card.modelData.nm.state?'Managed outside NetworkManager ('+card.modelData.nm.state+')':'Not managed by NetworkManager';font.pixelSize:10;anchors.verticalCenter:parent.verticalCenter}
                                    Label{visible:card.managed&&card.modelData.kind==='wifi'&&card.connected;text:'Wi-Fi disconnects live on the Wi-Fi tab';font.pixelSize:10;anchors.verticalCenter:parent.verticalCenter}
                                }
                            }
                        }
                    }
                    Label{width:parent.width;wrapMode:Text.WordWrap;text:'Click any address to copy it. Edit connection… opens nmtui for the full IPv4/IPv6, DNS, MTU and wake-on-LAN settings in a floating terminal. Connect and disconnect act on the saved NetworkManager profile as your user; nothing here changes system files.';font.pixelSize:10}
                }
                // ------------------------------------------------------------ Talkers
                Column {
                    width:parent.width;spacing:10;visible:root.tab===3;height:visible?implicitHeight:0
                    Row{width:parent.width
                        Heading{text:'TOP TALKERS';width:parent.width-260;font.pixelSize:13}
                        Label{text:'Ranked by open sockets · refresh 9s';font.pixelSize:10;width:260;horizontalAlignment:Text.AlignRight}
                    }
                    Label{text:'Click a row to visit its app or attached session. Background processes show details.';font.pixelSize:11}
                    Repeater {
                        model:root.rows.slice(root.page*8,root.page*8+8)
                        Rectangle {
                            id:procRow
                            required property var modelData
                            required property int index
                            width:mainColumn.width;height:65;radius:10
                            color:talkerMouse.containsMouse?'#1d303b':'#111e28';border.color:talkerMouse.containsMouse?root.tint:'#263844'
                            Rectangle{anchors.left:parent.left;anchors.bottom:parent.bottom;anchors.leftMargin:12;anchors.bottomMargin:5;width:(parent.width-24)*Model.clamp(procRow.modelData.count/Math.max(1,(root.net.talkers||{}).total||1),0,1);height:2;radius:1;color:root.tint}
                            Label{x:12;y:22;text:String(root.page*8+procRow.index+1).padStart(2,'0');font.pixelSize:12;color:root.tint}
                            Column{x:44;y:10;spacing:5;width:parent.width-232
                                Heading{text:procRow.modelData.name+'  ·  '+procRow.modelData.pid;font.pixelSize:13;width:parent.width;elide:Text.ElideRight}
                                Label{text:(procRow.modelData.target&&procRow.modelData.target.address?(procRow.modelData.target.host.kind==='herdr'?'Herdr '+procRow.modelData.target.host.pane+' · ':procRow.modelData.target.host.kind==='tmux'?'tmux '+procRow.modelData.target.host.pane+' · ':'')+procRow.modelData.target.title+'  ·  ':'')+procRow.modelData.hosts+' host'+(procRow.modelData.hosts===1?'':'s')+': '+(procRow.modelData.remotes||[]).map(function(r){return r.host+(r.count>1?' ×'+r.count:'')+' ('+r.kind+')'}).join(', ');width:parent.width;elide:Text.ElideRight;font.pixelSize:10}
                            }
                            Column{anchors.right:parent.right;anchors.rightMargin:35;y:10;spacing:5
                                Heading{text:procRow.modelData.count+' socket'+(procRow.modelData.count===1?'':'s');font.pixelSize:15;anchors.right:parent.right}
                                Label{text:procRow.modelData.tcp+' tcp · '+procRow.modelData.udp+' udp';font.pixelSize:10;anchors.right:parent.right}
                            }
                            Label{anchors.right:parent.right;anchors.rightMargin:13;y:22;text:procRow.modelData.target&&procRow.modelData.target.address?'↗':'ⓘ';color:root.tint;font.pixelSize:16}
                            MouseArea{id:talkerMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                                onClicked: {if(procRow.modelData.target&&procRow.modelData.target.address)root.runAction('focus',[String(procRow.modelData.pid),String(procRow.modelData.start)],'Finding the existing window…');else root.actionStatus=procRow.modelData.name+' · PID '+procRow.modelData.pid+' · '+procRow.modelData.count+' open sockets to '+procRow.modelData.hosts+' hosts. No existing window to focus.'}
                            }
                        }
                    }
                    Rectangle{visible:root.rows.length===0;width:parent.width;height:visible?60:0;radius:10;color:'#111e28';border.color:'#253744'
                        Label{anchors.centerIn:parent;text:root.stale?'Waiting for the net-pulse service.':'No process has an open connection right now.'}
                    }
                    Row{spacing:10
                        Action{text:'← Previous';opacity:root.page>0?1:0.4;onClicked:root.page=Math.max(0,root.page-1)}
                        Label{text:(root.page+1)+' / '+Math.max(1,Math.ceil(root.rows.length/8));anchors.verticalCenter:parent.verticalCenter}
                        Action{text:'Next →';opacity:(root.page+1)*8<root.rows.length?1:0.4;onClicked:root.page=Math.min(Math.max(0,Math.ceil(root.rows.length/8)-1),root.page+1)}
                        Label{text:((root.net.talkers||{}).total||0)+' active sockets  ·  '+((root.net.talkers||{}).listening||0)+' listening ports  ·  '+((root.net.talkers||{}).anonymous||0)+' owned by other users';font.pixelSize:10;anchors.verticalCenter:parent.verticalCenter}
                    }
                    Label{width:parent.width;wrapMode:Text.WordWrap;text:'Counts come from ss and are exact. Per-process bandwidth needs packet capture privileges, so it is not shown. Browser subprocesses lead to their browser window.';font.pixelSize:10}
                }
                // ------------------------------------------------------------ Network lab
                Column {
                    width:parent.width;spacing:12;visible:root.tab===4;height:visible?implicitHeight:0
                    Rectangle{width:parent.width;height:dnsCol.implicitHeight+28;radius:14;color:'#121b2c';border.color:'#303a57'
                        Column{id:dnsCol;anchors.fill:parent;anchors.margins:14;spacing:9
                            Item{width:parent.width;height:30
                                Heading{anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter;text:'DNS';font.pixelSize:12}
                                Row{anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;spacing:8
                                    Repeater{model:['DHCP','Cloudflare','Google']
                                        Action{required property string modelData;text:modelData;selected:((root.net.dns||{}).provider||'')===modelData;implicitHeight:28;enabled:!actionProc.running;onClicked:root.runAction('dns',[modelData],'Switching DNS to '+modelData+'…')}
                                    }
                                    Action{text:'Flush cache';implicitHeight:28;enabled:!actionProc.running;onClicked:root.runAction('flushdns',[],'Flushing the resolver cache…')}
                                }
                            }
                            Repeater{model:((root.net.dns||{}).links||[]).filter(function(l){return l.name!=='Global'})
                                Item{required property var modelData;width:dnsCol.width;height:18
                                    Label{id:dnsLine;anchors.fill:parent;elide:Text.ElideRight;font.pixelSize:11;color:dnsMouse.containsMouse?'#dfe4ff':'#b6c0fb'
                                        text:parent.modelData.name+'  ·  answering: '+(parent.modelData.current||'—')+'  ·  servers: '+(parent.modelData.servers||[]).join(', ')+(parent.modelData.domains&&parent.modelData.domains.length?'  ·  domains: '+parent.modelData.domains.join(' '):'')+(parent.modelData.defaultRoute?'  ·  default route':'')+(parent.modelData.dnssec?'  ·  DNSSEC '+parent.modelData.dnssec:'')}
                                    MouseArea{id:dnsMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                                        onClicked:root.copy(Model.bare(String(parent.modelData.current||(parent.modelData.servers||[])[0]||'').split('#')[0]),'the resolver for '+parent.modelData.name)}
                                }
                            }
                            Label{text:'Provider switches use omarchy-dns, the same privileged path as the stock widget. DHCP hands resolution back to the router.';font.pixelSize:10}
                        }
                    }
                    Rectangle{width:parent.width;height:104;radius:14;color:'#11251f';border.color:'#2c5547'
                        Column{anchors.fill:parent;anchors.margins:14;spacing:9
                            Row{width:parent.width
                                Heading{text:'PROBES';font.pixelSize:12;width:parent.width/2}
                                Label{text:'Connectivity: '+String(root.net.connectivity||'unknown')+(Networking.connectivityCheckEnabled?' · NetworkManager checks enabled':' · checks off');width:parent.width/2;horizontalAlignment:Text.AlignRight;color:'#abc4b9';font.pixelSize:11}
                            }
                            Row{spacing:8
                                Action{text:actionProc.running?'Working…':'10-ping latency burst';accent:'#63c89e';enabled:!actionProc.running&&!!root.net.online;onClicked:root.runAction('latency',[],'Sending 10 pings to the gateway and 1.1.1.1…')}
                                Action{text:'Public address';accent:'#63c89e';enabled:!actionProc.running&&!!root.net.online;onClicked:root.runAction('publicip',[],'Asking api.ipify.org for the public address…')}
                                Action{text:'Re-check connectivity';accent:'#63c89e';enabled:Networking.canCheckConnectivity;onClicked:{Networking.checkConnectivity();root.actionStatus='Asked NetworkManager to re-check connectivity.'}}
                                Action{text:'Speed test';accent:'#63c89e';enabled:!!root.net.online;onClicked:root.summon('omarchy.speedtest',{connection:Model.isWifi(root.net)?root.wifi.ssid:(root.iface.connection||'Ethernet')})}
                            }
                            Label{text:'Public address is the only probe that leaves your network beyond pings; it runs only when you press it.';font.pixelSize:10;color:'#abc4b9'}
                        }
                    }
                    Heading{text:'TRANSPORT';font.pixelSize:13}
                    Grid{width:parent.width;columns:4;spacing:8
                        Repeater{model:[
                            {l:'ESTABLISHED',v:Model.count((root.net.tcp||{}).CurrEstab),h:'TCP connections right now'},
                            {l:'RETRANSMITS',v:Model.perSec((root.net.tcpRates||{}).RetransSegs),h:Model.count((root.net.tcp||{}).RetransSegs)+' since boot'},
                            {l:'NEW CONNECTIONS',v:Model.perSec(((root.net.tcpRates||{}).ActiveOpens||0)+((root.net.tcpRates||{}).PassiveOpens||0)),h:'outbound + inbound opens'},
                            {l:'SEGMENTS',v:'↓ '+Model.perSec((root.net.tcpRates||{}).InSegs),h:'↑ '+Model.perSec((root.net.tcpRates||{}).OutSegs)},
                            {l:'TCP SOCKETS',v:Model.count((root.net.tcp||{}).tcpInuse),h:Model.count((root.net.tcp||{}).tcpTw)+' time-wait · '+Model.count((root.net.tcp||{}).tcpOrphan)+' orphan'},
                            {l:'UDP SOCKETS',v:Model.count((root.net.tcp||{}).udpInuse),h:'in use'},
                            {l:'LISTENING PORTS',v:Model.count((root.net.talkers||{}).listening),h:'TCP + UDP, all addresses'},
                            {l:'RESETS · FAILS',v:Model.count((root.net.tcp||{}).OutRsts)+'  ·  '+Model.count((root.net.tcp||{}).AttemptFails),h:'RSTs sent · connect attempts failed'},
                            {l:'IP FORWARDING',v:root.net.forwarding?'On':'Off',h:root.net.forwarding?'this machine routes packets':'kernel drops transit packets'},
                            {l:'ACTIVE MTU',v:String(root.iface.mtu||'—'),h:root.iface.name||'no interface'},
                            {l:'LINK ERRORS',v:Model.count(((root.net.totals||{}).rxErrors||0)+((root.net.totals||{}).txErrors||0)),h:Model.count(((root.net.totals||{}).rxDropped||0)+((root.net.totals||{}).txDropped||0))+' dropped'},
                            {l:'PACKET LOSS',v:Model.whole(root.ping.loss),h:'last '+(root.ping.internetSamples||[]).length+' internet pings'}
                        ]
                            Stat{required property var modelData;width:(mainColumn.width-24)/4;height:80;label:modelData.l;value:modelData.v;hint:modelData.h}
                        }
                    }
                    Heading{text:'ROUTES';font.pixelSize:13}
                    Column{width:parent.width;spacing:5
                        Repeater{model:root.net.routes||[]
                            Item{required property var modelData;width:parent.width;height:18
                                Label{anchors.fill:parent;elide:Text.ElideRight;font.pixelSize:11
                                    color:routeMouse.containsMouse&&parent.modelData.gateway?'#dfe4ff':parent.modelData.dst==='default'?'#e4edf0':'#b6c0fb'
                                    text:(parent.modelData.dst==='default'?'default':parent.modelData.dst)+(parent.modelData.gateway?'  via '+parent.modelData.gateway:'')+'  dev '+parent.modelData.dev+(parent.modelData.metric?'  metric '+parent.modelData.metric:'')+(parent.modelData.protocol?'  ·  '+parent.modelData.protocol:'')}
                                MouseArea{id:routeMouse;anchors.fill:parent;hoverEnabled:!!parent.modelData.gateway;enabled:!!parent.modelData.gateway
                                    cursorShape:Qt.PointingHandCursor;onClicked:root.copy(parent.modelData.gateway,'the gateway for '+parent.modelData.dst)}
                            }
                        }
                    }
                    Label{width:parent.width;wrapMode:Text.WordWrap;text:'Nothing here edits routes, firewall rules, sysctl or NetworkManager system files. Counters are kernel totals since boot; rates are per second over the last sample.';font.pixelSize:10}
                }
                Rectangle{width:parent.width;height:1;color:'#25343f'}
                Label{width:parent.width;wrapMode:Text.WordWrap;font.pixelSize:10;color:root.stale?'#f0ba82':'#a4b9c3';text:root.actionStatus || (root.stale?'Telemetry is offline. Check the net-pulse user service.': 'LIVE · updated '+Qt.formatTime(new Date(root.net.ts*1000),'h:mm:ss AP')+'  ·  History stays on this machine  ·  Esc closes')}
            }
        }
    }
    function currentDns() {
        var links=(net.dns||{}).links||[]
        for (var i=0;i<links.length;i++) if(links[i].name===iface.name && links[i].current) return links[i].current
        for (var j=0;j<links.length;j++) if(links[j].name!=='Global' && links[j].servers && links[j].servers.length) return links[j].servers[0]
        return '—'
    }
    function dnsCount() {
        var links=(net.dns||{}).links||[], n=0
        for (var i=0;i<links.length;i++) if(links[i].name!=='Global') n+=(links[i].servers||[]).length
        return n
    }
}
