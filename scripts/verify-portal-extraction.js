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
// A timetable grid has no course-name header: positions carry the weekday.
const grid = table([['节次', '星期一', '星期二'], ['1-2', '网络\n1-16周\n第1-2节', '']]);
const payload = extract(document([grid], [], '导航与个人资料'));
assert.ok(payload.startsWith('__KEBIAO_GRID__'), 'Weekday grid must retain cell coordinates instead of falling back to page text');
const cells = JSON.parse(payload.slice('__KEBIAO_GRID__'.length));
assert.equal(cells[0].weekday, '星期一');
assert.equal(cells[0].section, '1-2');
assert.equal(cells[0].text, '网络\n1-16周\n第1-2节');
const merged = table([['时段', '节次', '星期一', '星期二'],
  ['上午', '1', '网络\n1-16周', '算法\n2-16周(双)'],
  ['2', '英语\n1-16周'], ['下午', '5-6', '', '实验\n3-12周']]);
merged.rows[1].cells[0].rowSpan = 2;
merged.rows[1].cells[2].rowSpan = 2;
const mergedCells = JSON.parse(extract(document([merged])).slice('__KEBIAO_GRID__'.length));
assert.deepEqual(JSON.parse(JSON.stringify(mergedCells)), [
  {weekday: '星期一', section: '1-2', text: '网络\n1-16周'},
  {weekday: '星期二', section: '1-1', text: '算法\n2-16周(双)'},
  {weekday: '星期二', section: '2-2', text: '英语\n1-16周'},
  {weekday: '星期二', section: '5-6', text: '实验\n3-12周'},
]);
const columnSpan = table([['学期课程表'], ['節', '星期一', '星期二'], ['3-4', '实验\n1-8周']]);
columnSpan.rows[0].cells[0].colSpan = 3;
columnSpan.rows[2].cells[1].colSpan = 2;
const spanCells = JSON.parse(extract(document([columnSpan])).slice('__KEBIAO_GRID__'.length));
assert.equal(spanCells.length, 2);
assert.equal(spanCells[0].weekday, '星期一');
assert.equal(spanCells[1].weekday, '星期二');
assert.equal(spanCells[1].section, '3-4');
console.log('Portal extraction: 8 regression cases passed.');
