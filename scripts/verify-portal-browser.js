const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const source = fs.readFileSync('Kebiao/SchoolPortalLoginView.swift', 'utf8');
const match = source.match(/browserIdentityScript = #"""\r?\n([\s\S]*?)\r?\n    """#/);
assert.ok(match, 'Portal browser compatibility must be present before navigation');
const identify = userAgent => vm.runInNewContext(match[1], { navigator: { userAgent } });

// Minimized contract from the official CQUT portal, checked on 2026-10-09:
// vendor.57c5e79c3fa915afbf2d.js detects Safari/Chrome by UA tokens; app's
// analysisTicket sends equipmentName = browser to /officeHallPageHome/uap/check.
// A default WKWebView has AppleWebKit/Mobile tokens but no Safari browser token.
function browserName(ua) {
  let browser;
  if (ua.indexOf('Safari') > -1) browser = 'Safari';
  if (ua.indexOf('Chrome') > -1 || ua.indexOf('CriOS') > -1) browser = 'Chrome';
  if (ua.indexOf('Firefox') > -1 || ua.indexOf('FxiOS') > -1) browser = 'Firefox';
  return browser;
}
function ticketCheckParameters(ua) {
  const equipmentName = browserName(ua);
  // Axios excludes undefined request parameters. No SSO ticket is needed to
  // reproduce the missing device name; authentication is outside this test.
  const parameters = new URLSearchParams();
  if (equipmentName !== undefined) parameters.set('equipmentName', equipmentName);
  return parameters;
}

const wk = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
assert.equal(ticketCheckParameters(wk).has('equipmentName'), false, 'Reproduce the original empty device name');
const compatible = identify(wk);
assert.equal(ticketCheckParameters(compatible).get('equipmentName'), 'Safari');
assert.ok(compatible.startsWith(wk + ' '), 'Retain the actual WebKit device, OS, and engine information');
assert.ok(compatible.includes(' Version/18.5 Safari/604.1'));
assert.equal(identify(compatible), compatible, 'Do not add duplicate browser tokens on refresh');

const safari = wk.replace(' Mobile/', ' Version/18.5 Mobile/') + ' Safari/604.1';
assert.equal(identify(safari), safari, 'Keep an existing Safari identity');
const chrome = wk + ' CriOS/140.0.7339.122';
assert.equal(identify(chrome), chrome, 'Keep an existing Chrome identity');
assert.equal(ticketCheckParameters(identify(chrome)).get('equipmentName'), 'Chrome');
const firefox = wk + ' FxiOS/143.0';
assert.equal(identify(firefox), firefox, 'Keep an existing Firefox identity');

const ipad = 'Mozilla/5.0 (iPad; CPU OS 26_0_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
assert.equal(ticketCheckParameters(identify(ipad)).get('equipmentName'), 'Safari');
assert.ok(identify(ipad).includes('Version/26.0'));
assert.ok(identify(ipad).startsWith(ipad + ' '));
assert.equal(identify(''), '', 'An unavailable UA must cause initialization feedback instead of fabricated device information');
console.log('Portal browser identity: 9 regression cases passed.');
