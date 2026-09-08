const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const ctx={Qt:{rgba:(r,g,b,a)=>[r,g,b,a]}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync(path.join(__dirname,'..','Model.js'),'utf8').replace('.pragma library',''),ctx);

const wifi={warm:true,online:true,connectivity:'full',iface:{kind:'wifi',name:'wlp2s0',speed:null,connection:'ILoveMyWifi',addrs4:['10.0.0.22/24'],addrs6:[]},
  rates:{rx:1500000,tx:250000},wifi:{ssid:'ILoveMyWifi',signal:-46,quality:83,freq:5805,channel:161},ping:{internet:11.2,gateway:1.8,loss:0}};
const wired={warm:true,online:true,connectivity:'full',iface:{kind:'ethernet',name:'enp3s0',speed:1000,connection:'Wired',addrs4:['192.168.1.5/24'],addrs6:[]},
  rates:{rx:12000000,tx:900000},wifi:{},ping:{internet:4.1,gateway:0.9,loss:0}};

// Readouts, one per bar mode.
assert.equal(ctx.readout(wifi,0),'↓ 1.5 MB/s');
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

console.log('Readouts, offline and cold telemetry, decimal units, health scoring and graph ceilings pass.');
