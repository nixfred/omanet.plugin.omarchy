const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const ctx={Qt:{rgba:(r,g,b,a)=>[r,g,b,a]}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync(path.join(__dirname,'..','Model.js'),'utf8').replace('.pragma library',''),ctx);

const wifi={warm:true,online:true,connectivity:'full',iface:{kind:'wifi',name:'wlp2s0',speed:null,connection:'ILoveMyWifi',addrs4:['10.0.0.22/24'],addrs6:[]},
  rates:{rx:1500000,tx:250000},wifi:{ssid:'ILoveMyWifi',signal:-46,quality:83,freq:5805,channel:161},ping:{internet:11.2,gateway:1.8,loss:0}};
const wired={warm:true,online:true,connectivity:'full',iface:{kind:'ethernet',name:'enp3s0',speed:1000,connection:'Wired',addrs4:['192.168.1.5/24'],addrs6:[]},
  rates:{rx:12000000,tx:900000},wifi:{},ping:{internet:4.1,gateway:0.9,loss:0}};

// Readouts, one per bar mode.
assert.equal(ctx.readout(wifi,0),'↓ 1.5M');
assert.equal(ctx.modeTag(wifi,0),'↑ 250K');
assert.equal(ctx.readout(wifi,1),'-46 dBm');
assert.equal(ctx.readout(wired,1),'1 Gbit/s');
assert.equal(ctx.readout(wifi,2),'11 ms');
assert.equal(ctx.readout(wifi,3),'ILoveMyWifi');
assert.equal(ctx.readout(wired,3),'Wired');
assert.equal(ctx.readout(wifi,4),'10.0.0.22');
assert.equal(ctx.modeTag(wifi,3),'5 GHz · CH 161');
assert.equal(ctx.modeTag(wired,1),'LINK SPEED');

// Cold and offline telemetry never reads as a real number.
assert.equal(ctx.readout({},0),'—');
assert.equal(ctx.readout({warm:false},0),'—');
assert.equal(ctx.readout({warm:true,online:false},0),'offline');
assert.equal(ctx.ms(null),'—');
assert.equal(ctx.ms(-1),'timeout');
assert.equal(ctx.ms(4.06),'4.1 ms');
assert.equal(ctx.ms(11.2),'11 ms');
assert.equal(ctx.dbm(null),'—');
assert.equal(ctx.mbit(0),'—');

// Decimal units, the way link rates are quoted.
assert.equal(ctx.rate(1500000),'1.5 MB/s');
assert.equal(ctx.rate(999),'999 B/s');
assert.equal(ctx.size(31240000000),'31.24 GB');
assert.equal(ctx.mbit(400),'400 Mbit/s');
assert.equal(ctx.mbit(2500),'2.5 Gbit/s');
assert.equal(ctx.count(15419),'15.4k');
assert.equal(ctx.ago(3680),'1h 1m');
assert.equal(ctx.band(5805),'5 GHz');
assert.equal(ctx.security('WPA2 802.1X'),'Enterprise');
assert.equal(ctx.security(''),'Open');

// Health drives the colour: a clear path is green, a dead one dark red.
assert.equal(ctx.health(wifi),100);
assert.equal(ctx.health({warm:true,online:false}),0);
assert.ok(ctx.health({warm:true,online:true,connectivity:'portal',ping:{},wifi:{}})<=40);
assert.ok(ctx.health({warm:true,online:true,connectivity:'full',ping:{internet:-1,loss:100},wifi:{}})<20);
assert.equal(ctx.healthLabel({warm:true,online:true,connectivity:'portal',ping:{},wifi:{}}),'CAPTIVE PORTAL AHEAD');
assert.equal(ctx.healthLabel({warm:true,online:false}),'NO ROUTE TO THE INTERNET');
assert.equal(ctx.healthLabel(wifi),'CLEAR PATH TO THE INTERNET');

// Red at no health, yellow at half, green when clear.
for(const [p,c] of [[0,[133,13,41]],[50,[239,204,69]],[100,[67,242,161]]]){
  const result=ctx.ramp(p);c.forEach((v,i)=>assert.equal(Math.round(result[i]*255),v));
}

// Graph ceilings step 1-2-5 and never magnify a quiet link.
assert.equal(ctx.niceMax(0),10000);
assert.equal(ctx.niceMax(1500000),2000000);
assert.equal(ctx.niceMax(1800000),5000000);
assert.equal(ctx.niceMs(0),20);
assert.equal(ctx.niceMs(43),50);

// A partial snapshot must not throw on a key it happens to be missing.
for (const mode of [0,1,2,3,4]) {
  assert.doesNotThrow(()=>ctx.readout({warm:true,online:true},mode));
  assert.doesNotThrow(()=>ctx.modeTag({warm:true,online:true},mode));
}
assert.equal(ctx.readout({warm:true,online:true},4),'no address');
assert.equal(ctx.bare('100.101.176.48/32'),'100.101.176.48');

// Usage pacing: a short window is a rate, a long one is a daily figure, and
// neither invents time the collector was not running for.
assert.equal(ctx.pace(1e9, 60), '—');
assert.equal(ctx.pace(48e9, 3600), '13.3 MB/s average');
assert.equal(ctx.pace(72e9, 72*3600), '24.00 GB a day');
assert.equal(ctx.shortSize(0), '0B');
assert.equal(ctx.shortSize(2.4e9), '2.4G');
assert.equal(ctx.rangeName(0), 'All time');
assert.equal(ctx.coverage(3600, 3600), 'fully recorded');
assert.equal(ctx.coverage(0, 86400), 'nothing recorded yet');

// The bar strip formats throughput to three significant figures and one unit
// letter. Every reading must fit five characters, or the reservation that keeps
// the widget from resizing has to grow to cover a sixth.
for (const bps of [0, 1, 512, 999, 999.6, 9900, 43400, 254200, 999400, 999500,
                   1200000, 14700000, 99950000, 999900000, 1e10, 99.95e9, 5e12]) {
  assert.ok(ctx.tight(bps).length <= 5, bps + ' formats as ' + ctx.tight(bps));
}
// Tier boundaries roll up rather than rounding into a sixth character.
assert.equal(ctx.tight(999.6), '1.0K');
assert.equal(ctx.tight(999500), '1.0M');
assert.equal(ctx.tight(999400), '999K');
assert.equal(ctx.tight(99950000), '100M');
// The dashboard and the tooltip keep the long form; only the strip is tight.
assert.equal(ctx.rate(254200), '254.2 KB/s');
assert.equal(ctx.tight(254200), '254K');

// Bar width reservations. Modes that change every sample reserve a floor;
// the name and address modes reserve nothing, because they cannot flicker.
for (const mode of [0,1,2]) {
  assert.ok(ctx.widestReadout(wifi,mode).length>0, 'mode '+mode+' reserves no readout');
  assert.ok(ctx.widestTag(wifi,mode).length>0, 'mode '+mode+' reserves no tag');
}
for (const mode of [3,4]) {
  assert.equal(ctx.widestReadout(wifi,mode),'');
  assert.equal(ctx.widestTag(wifi,mode),'');
}
// Nothing a mode can actually render may out-run its reservation.
const busy={...wifi, rates:{rx:999900000,tx:999900000}};
assert.equal(ctx.readout(busy,0),'\u2193 1.0G');
assert.ok(ctx.readout(busy,0).length<=ctx.widestReadout(busy,0).length);
assert.ok(ctx.modeTag(busy,0).length<=ctx.widestTag(busy,0).length);
assert.ok(ctx.readout(wifi,2).length<=ctx.widestReadout(wifi,2).length);
assert.ok(ctx.modeTag(wifi,2).length<=ctx.widestTag(wifi,2).length);
assert.ok(ctx.modeTag(wifi,1).length<=ctx.widestTag(wifi,1).length);
for (const speed of [100,1000,2500,10000]) {
  const link={...wired, iface:{...wired.iface, speed:speed}};
  assert.ok(ctx.readout(link,1).length<=ctx.widestReadout(link,1).length, speed+' out-runs its reservation');
}


// ---- Theme ramp ------------------------------------------------------------
// The link ramp carries meaning rather than style, so it follows the theme's
// own red, yellow and green and must stay readable in every one of them.

// A palette named directly, or given as terminal colour slots. The named key
// wins where a theme defines both.
const named=`red = "#FF5964"\nyellow = "#F6C84D"\ngreen = "#8BCB68"\n`;
assert.deepEqual({...ctx.parsePalette(`color1 = "#FF5964"\ncolor2='#8BCB68'\ncolor3 = #F6C84D\n`)},
  {red:'#FF5964',yellow:'#F6C84D',green:'#8BCB68'});
assert.equal(ctx.parsePalette(named+`color1 = "#000000"\n`).red,'#FF5964');

// Stops are built inside the script realm, so they carry a different Array
// prototype and are spread out of it, outer array included, before any strict
// deep comparison.
const plain=s=>[...s].map(stop=>[...stop]);

// A stop already above the chroma floor passes through untouched.
const namedStops=ctx.rampStops(named);
assert.deepEqual(plain(namedStops)[0],[255,89,100]);
assert.deepEqual(plain(namedStops)[1],[246,200,77]);

// A muted palette of genuinely different hues is lifted, not rejected.
// 2-haxorz's three sit 14, 85 and 178 degrees apart; only its chroma is thin.
const lifted=ctx.rampStops(`red = "#b9968f"\nyellow = "#7b8768"\ngreen = "#708c8b"\n`);
assert.notEqual(lifted,ctx.DEFAULT_STOPS);
assert.deepEqual(plain(lifted),[[214,131,114],[134,185,54],[57,195,190]]);
assert.ok(ctx.separation(lifted[0],lifted[1])>=80);
assert.ok(ctx.separation(lifted[1],lifted[2])>=80);

// Stops that are really one colour stay rejected: no saturation pulls
// blue-red-4k-warm's yellow and green apart.
assert.equal(ctx.rampStops(`red = "#b88485"\nyellow = "#e99b8c"\ngreen = "#ea9b8c"\n`),ctx.DEFAULT_STOPS);
// A partial palette is not a palette, and neither is no palette.
assert.equal(ctx.rampStops(`red = "#FF5964"\ngreen = "#8BCB68"\n`),ctx.DEFAULT_STOPS);
assert.equal(ctx.rampStops(''),ctx.DEFAULT_STOPS);
// Stops are only honoured as a complete set of three.
assert.deepEqual(ctx.ramp(0,[[1,2,3]]),ctx.ramp(0));

// Every installed theme, the user's own and Omarchy's, must yield three
// well-formed stops. Checking one directory misses more than half of them.
let checked=0;
for(const dir of [path.join(process.env.HOME,'.config/omarchy/themes'),'/usr/share/omarchy/themes']){
  if(!fs.existsSync(dir)) continue;
  for(const name of fs.readdirSync(dir)){
    const file=path.join(dir,name,'colors.toml');
    if(!fs.existsSync(file)) continue;
    const stops=ctx.rampStops(fs.readFileSync(file,'utf8'));
    assert.equal(stops.length,3,name);
    for(const stop of stops){
      assert.equal(stop.length,3,name);
      stop.forEach(v=>assert.ok(Number.isInteger(v)&&v>=0&&v<=255,name+' '+v));
    }
    assert.ok(ctx.separation(stops[0],stops[1])>=80,name);
    assert.ok(ctx.separation(stops[1],stops[2])>=80,name);
    checked++;
  }
}

// The panel must re-read the palette on a theme switch, not just on a file
// edit: the shell loads colors.toml once and is pushed later themes over IPC.
const panel=fs.readFileSync(path.join(__dirname,'..','Panel.qml'),'utf8');
assert.match(panel,/onThemeSignatureChanged:\s*paletteFile\.reload\(\)/);

console.log('Readouts, offline and cold telemetry, decimal units, health scoring, graph ceilings'
  +' and the theme ramp pass ('+checked+' installed themes checked).');
