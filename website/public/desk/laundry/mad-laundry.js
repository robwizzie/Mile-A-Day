// Mile A Day laundry: runs on a Shelly Plug (Gen4) under the washer or dryer.
// Every 2 s it reads the power the machine draws and sends the readings to
// your Mile A Day server, which works out washing / spinning / drying / done
// for your desk box and your phone.
//
// It only ever SENDS watts. It never switches the plug and never reads
// anything back. The key below works for this one plug and nothing else;
// you can turn it off any time in your desk remote (Laundry -> Remove plug).
//
// Setup: the desk remote fills in KEY for you when you add a plug. Paste the
// whole script into the plug's web page -> Scripts -> Create script, save,
// turn on "Run on startup", then Start.

let CONFIG = {
  url: "https://mad.mindgoblin.tech/laundry/report",
  key: "PASTE_KEY_HERE",
  every: 2, // seconds between readings (the server expects 2)
  busyWatts: 3, // above this, send every 20 s; otherwise once a minute
  keep: 150, // offline: keep the last 5 min of readings to send later
};

let buf = [];
let sending = false;
let failures = 0;

function hasBusy() {
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] >= CONFIG.busyWatts) return true;
  }
  return false;
}

function send(on) {
  sending = true;
  let batch = buf;
  buf = [];
  Shelly.call(
    "HTTP.Request",
    {
      method: "POST",
      url: CONFIG.url,
      timeout: 10,
      headers: {
        Authorization: "Laundry " + CONFIG.key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ v: 1, dt: CONFIG.every, on: on, p: batch }),
    },
    function (res, err) {
      sending = false;
      let ok = err === 0 && res && res.code === 200;
      if (ok) {
        failures = 0;
        return;
      }
      failures++;
      if (res && res.code === 401) {
        // Key removed or replaced: stop (no point retrying). Restart the
        // script after pasting a new key.
        print("Mile A Day laundry: the server refused this plug (" + res.code + "). Stopping.");
        Timer.clear(timer);
        return;
      }
      if (res && res.code === 400) return; // readings it can't use: drop them
      // Network hiccup or a busy server: put the readings back, try again.
      buf = batch.concat(buf);
      if (buf.length > CONFIG.keep) buf = buf.slice(buf.length - CONFIG.keep);
    }
  );
}

function sample() {
  Shelly.call("Switch.GetStatus", { id: 0 }, function (st) {
    if (!st) return;
    let w = typeof st.apower === "number" && st.apower > 0 ? st.apower : 0;
    buf.push(Math.round(w * 10) / 10);
    if (buf.length > CONFIG.keep) buf = buf.slice(buf.length - CONFIG.keep);
    // Back off a little after failures (up to ~2 min between tries).
    let wait = failures > 0 ? Math.min(60, 10 * failures) : 0;
    if (sending || buf.length < 10 + wait) return;
    if (buf.length >= 30 + wait || hasBusy()) send(st.output === true);
  });
}

let timer = Timer.set(CONFIG.every * 1000, true, sample);
print("Mile A Day laundry: sending power readings every 20-60 s.");
