const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const source = fs.readFileSync('Kebiao/SchoolPortalLoginView.swift', 'utf8');
const script = source.match(/tableExtractionScript = #"""\r?\n([\s\S]*?)\r?\n    """#/)[1];
const table = rows => ({ rows: rows.map(values => ({ cells: values.map(innerText => ({ innerText })) })) });
const courseTable = table([['课程名称', '星期', '节次'], ['网络', '周一', '第1-2节']]);
function document(tables = [], frames = [], text = '') {
  return {
    body: { innerText: text },
    defaultView: { getComputedStyle: element => element.style || ({ display: 'table', visibility: 'visible' }) },
    querySelectorAll: selector => selector === 'table' ? tables : frames,
  };
}
const extract = doc => vm.runInNewContext(script, { document: doc });
const navigation = table([['导航', '链接'], ['首页', '返回']]);
assert.equal(extract(document([navigation, courseTable])), '课程名称\t星期\t节次\n网络\t周一\t第1-2节');
assert.equal(extract(document([], [{ contentDocument: document([courseTable]) }])), extract(document([courseTable])));
const blocked = { src: 'https://school.example/timetable', get contentDocument() { throw new Error('Cross origin'); } };
assert.equal(extract(document([], [blocked])), '__KEBIAO_FRAMES__["https://school.example/timetable"]');
const hidden = table([['课程名称', '星期'], ['隐藏课程', '周二']]);
hidden.style = { display: 'none', visibility: 'visible' };
assert.equal(extract(document([hidden, courseTable])), extract(document([courseTable])));
assert.equal(extract(document([], [], '课程名：网络\n星期：周一')), '课程名：网络\n星期：周一');
console.log('Portal extraction: 5 regression cases passed.');
