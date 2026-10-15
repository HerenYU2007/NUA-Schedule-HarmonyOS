(function () {
  function academicPath(doc) {
    var host = doc.location.hostname.toLowerCase(), path = doc.location.pathname || '/';
    if (host === 'jwnew.nua.edu.cn') return path;
    if (host !== 'v.nua.edu.cn' || doc.location.protocol !== 'https:'
        || (doc.location.port && doc.location.port !== '443')
        || /%|\\|\/\/|\/\.{1,2}(?:\/|$)/.test(path)) return null;
    var route = path.match(/^\/https\/[A-Za-z0-9_=-]{24,512}(\/jsxsd\/[A-Za-z0-9_./-]*)$/);
    return route ? route[1] : null;
  }
  function trusted(doc) {
    try {
      var host = doc.location.hostname.toLowerCase();
      return doc.location.protocol === 'https:' && (host === 'nua.edu.cn' || host.endsWith('.nua.edu.cn'))
        && !/^\/jsxsd\/grsz\//i.test(academicPath(doc) || '')
        && host !== 'c.nua.edu.cn' && !/\/cas\/(login|logout)/i.test(doc.location.pathname || '')
        && !doc.querySelector('input[type=password]');
    } catch (e) { return false; }
  }
  function docs(win, result, depth) {
    if (depth > 5) return;
    try {
      if (!trusted(win.document)) return;
      result.push(win.document);
      for (var i = 0; i < win.frames.length; i++) {
        try {
          var frame = win.frames[i].frameElement;
          if (frame) {
            var rects = frame.getClientRects();
            if (!rects.length || rects[0].width === 0 || rects[0].height === 0) continue;
            var frameWin = frame.ownerDocument && frame.ownerDocument.defaultView;
            if (frameWin && frameWin.getComputedStyle) {
              var style = frameWin.getComputedStyle(frame);
              if (style.visibility === 'hidden' || style.visibility === 'collapse' || style.display === 'none') continue;
            }
          }
          docs(win.frames[i], result, depth + 1);
        } catch (e) {}
      }
    } catch (e) {}
  }
  function text(cell) { return (cell.innerText || '').replace(/\u00a0/g, ' ').trim(); }
  function cells(row) { return Array.from(row.children).filter(function (c) { return /^(TD|TH)$/.test(c.tagName); }).map(text); }
  function rows(table) { return Array.from(table.rows).filter(function (r) { return r.closest('table') === table; }); }
  function dayOf(cell) {
    var match = text(cell).replace(/\s+/g, '').match(/^(星期|周)([一二三四五六日天])$/);
    return match ? '一二三四五六日'.indexOf(match[2].replace('天', '日')) + 1 : 0;
  }
  function gridLayout(table) {
    var occupied = [], result = [], trs = rows(table);
    for (var r = 0; r < trs.length; r++) {
      var entries = [], column = 0;
      var children = Array.from(trs[r].children).filter(function (c) { return /^(TD|TH)$/.test(c.tagName); });
      for (var c = 0; c < children.length; c++) {
        while ((occupied[column] || 0) > r) column++;
        var cell = children[c], width = Math.max(1, Number(cell.colSpan) || 1);
        var height = cell.rowSpan === 0 ? trs.length - r : Math.max(1, Number(cell.rowSpan) || 1);
        if (width > 50 || height > 1000 || column > 50) return [];
        entries.push({cell: cell, column: column, width: width});
        for (var k = column; k < column + width; k++) occupied[k] = r + height;
        column += width;
      }
      result.push(entries);
    }
    return result;
  }
  function courseMetadata(prefix) {
    var lines = prefix.split(/\r?\n/).map(function (v) { return v.trim(); }).filter(Boolean);
    var college = -1;
    for (var i = 0; i < lines.length; i++) if (/学院$|体育部$/.test(lines[i].replace(/\s+/g, ''))) college = i;
    if (college < 0) return null; // The screenshots show an explicit department before each course.
    var fields = lines.slice(college + 1);
    if (fields.length < 2) return null;
    var teacher = fields.pop().replace(/^(授课教师|教师)\s*[:：]\s*/, '').trim();
    if (!teacher || /[\[\]]|\d+[周节]|^[（(]|学院$|体育部$/.test(teacher) || teacher.length > 80) return null;
    var course = fields.join('').trim();
    // Strip a teaching-class annotation, but retain course qualifiers such as English (文产).
    course = course.replace(/[（(][^()（）]*(?:\d+班|混合班|教学班)[^()（）]*[)）]/g, '').trim();
    if (!course || course.length > 160) return null;
    return {course: course, teacher: teacher};
  }
  function parseGridCell(value, day, data, warnings) {
    var pattern = /([0-9][0-9\s,，、\-—–~至]*)\s*[（(]\s*周\s*([单双])?\s*[)）]\s*(?:[（(]\s*([单双])(?:周)?\s*[)）])?\s*\[\s*([0-9\s,，、\-—–至]+)\s*节\s*\]/g;
    var matches = [], match;
    while ((match = pattern.exec(value))) matches.push(match);
    if (!matches.length) {
      if (/\d\s*[（(]周|\[.*节/.test(value)) warnings.add('部分周视图课程的周次/节次格式未识别，该课程块未导入。');
      return;
    }
    var previous = null, previousRoom = '', previousEnd = 0;
    for (var m = 0; m < matches.length; m++) {
      match = matches[m];
      var prefix = value.slice(previousEnd, match.index);
      var metadata = courseMetadata(prefix);
      if (!metadata && previous && prefix.replace(/\s+/g, '') === previousRoom.replace(/\s+/g, '')) metadata = previous;
      var end = match.index + match[0].length;
      var after = value.slice(end, m + 1 < matches.length ? matches[m + 1].index : value.length);
      var room = after.split(/[-—─]{3,}/)[0].split(/\r?\n/).map(function (v) { return v.trim(); }).filter(Boolean)[0] || '';
      if (!room || /学院$|体育部$/.test(room) || room.length > 100) {
        room = '地点待核对';
        warnings.add('部分周视图课程未能对应教室，显示“地点待核对”。');
      }
      previousEnd = end;
      previous = metadata;
      previousRoom = room;
      if (!metadata) {
        warnings.add('部分周视图课程的学院/课程/教师分行结构未识别，该课程块未导入。');
        continue;
      }
      var weeks = match[1].replace(/\s+/g, '');
      if (!/^\d+(?:[-—–~至]\d+)?(?:[,，、]\d+(?:[-—–~至]\d+)?)*$/.test(weeks)) {
        warnings.add('部分周视图周次未识别，该时间段未导入。');
        continue;
      }
      var periodText = match[4].replace(/\s+/g, ''), numbers;
      if (/^\d+至\d+$/.test(periodText)) {
        var range = periodText.split('至').map(Number);
        numbers = [];
        if (range[0] <= range[1] && range[1] <= 12) for (var p = range[0]; p <= range[1]; p++) numbers.push(p);
      } else numbers = periodText.split(/[-—–,，、]/).map(Number);
      numbers = Array.from(new Set(numbers)).sort(function (a, b) { return a - b; });
      if (!numbers.length || numbers.some(function (p) { return p < 1 || p > 12 || !Number.isInteger(p); })) {
        warnings.add('部分周视图节次超出支持范围，该时间段未导入。');
        continue;
      }
      var groups = [], first = numbers[0], last = first;
      for (var p = 1; p <= numbers.length; p++) {
        if (p < numbers.length && numbers[p] === last + 1) { last = numbers[p]; continue; }
        groups.push([first, last]);
        first = last = numbers[p];
      }
      if (groups.length > 1) warnings.add('有不连续节次，按页面明确列出的节次分别导入，请核对。');
      var parity = match[2] || match[3] || '';
      var times = groups.map(function (group) {
        return weeks + '周' + (parity ? '(' + parity + ')' : '') + ',周' + '一二三四五六日'[day - 1]
          + ',第' + group[0] + (group[0] === group[1] ? '' : '-' + group[1]) + '节';
      });
      data.push([metadata.course, times.join(';'), room, metadata.teacher]);
    }
  }
  function gridCourses(doc) {
    if (academicPath(doc) === null
        || !/个人课表|我的课表|学期(?:理论)?课表/.test(doc.title + (doc.body ? doc.body.innerText : ''))) return null;
    var data = [], warnings = new Set(), detected = false;
    var tables = Array.from(doc.querySelectorAll('table'));
    for (var t = 0; t < tables.length; t++) {
      var table = tables[t];
      if (table.getClientRects && !table.getClientRects().length) continue;
      var layout = gridLayout(table), days = null, header = -1;
      for (var r = 0; r < Math.min(layout.length, 10); r++) {
        var candidate = Object.create(null), unique = new Set();
        for (var c = 0; c < layout[r].length; c++) {
          var entry = layout[r][c], day = dayOf(entry.cell);
          if (day && entry.width === 1) { candidate[entry.column] = day; unique.add(day); }
        }
        if (unique.size === 7) { days = candidate; header = r; break; }
      }
      if (!days) continue;
      detected = true;
      for (var r = header + 1; r < layout.length; r++) {
        for (var c = 0; c < layout[r].length; c++) {
          var entry = layout[r][c], value = text(entry.cell);
          if (!days[entry.column] || !value) continue;
          if (entry.width !== 1) {
            if (/\d\s*[（(]周|\[.*节/.test(value)) warnings.add('有课程格跨多个星期列，无法确定星期，未导入该格。');
            continue;
          }
          parseGridCell(value, days[entry.column], data, warnings);
        }
      }
    }
    if (!detected) return null;
    var seen = new Set();
    data = data.filter(function (row) { var key = JSON.stringify(row); if (seen.has(key)) return false; seen.add(key); return true; });
    warnings.add('从学期周视图读取：请核对页面包含全学期、所有课程，而非单周或筛选结果。');
    warnings.add('周视图未提供理论/实践周次，按页面显示的周次、节次和教室导入。');
    var body = doc.body ? doc.body.innerText : '';
    var semester = body.match(/20\d{2}[—\-至/]20\d{2}\s*学年[^\n]{0,20}/);
    return {headers: ['课程名称', '实际上课时间', '实际上课教室', '授课教师'], rows: data,
      title: doc.title, format: 'semester-grid', semester: semester ? semester[0] : '', warnings: Array.from(warnings)};
  }
  var documents = [];
  docs(window, documents, 0);
  for (var d = 0; d < documents.length; d++) {
    var doc = documents[d];
    var tables = Array.from(doc.querySelectorAll('table'));
    for (var t = 0; t < tables.length; t++) {
      var trs = rows(tables[t]);
      for (var h = 0; h < Math.min(trs.length, 6); h++) {
        var headers = cells(trs[h]).map(function (v) { return v.replace(/\s+/g, ''); });
        if (!headers.some(function (v) { return /^(课程名称|课程名)$/.test(v); })
            || !headers.some(function (v) { return /^(实际上课时间|上课时间)$/.test(v); })) continue;
        var body = doc.body ? doc.body.innerText : '';
        if (!/个人课表|我的课表|学期(?:理论)?课表|学生课表|课表查询/.test(doc.title + body) && !headers.includes('实际上课时间')) continue;
        var candidates = trs.slice(h + 1).map(cells);
        var data = candidates.filter(function (r) { return r.length === headers.length; });
        // Some grid implementations put their header and body in adjacent tables.
        if (!data.length && tables[t + 1]) {
          candidates = rows(tables[t + 1]).map(cells);
          data = candidates.filter(function (r) { return r.length === headers.length; });
        }
        if (!data.length) continue;
        var warnings = [];
        if (candidates.some(function (r) { return r.length && r.length !== headers.length; }))
          warnings.push('部分行列数与表头不同，未读取。请核对课程是否齐全。');
        if (/共\s*\d+\s*页|下一页|下页/.test(body)) warnings.push('页面可能有分页，请先显示全部课程；仅当前表格内的课程会被导入。');
        var semester = body.match(/20\d{2}[—\-至/]20\d{2}\s*学年[^\n]{0,20}/);
        return JSON.stringify({headers: headers, rows: data, title: doc.title,
          semester: semester ? semester[0] : '', warnings: warnings});
      }
    }
  }
  for (var d = 0; d < documents.length; d++) {
    var grid = gridCourses(documents[d]);
    if (grid) return JSON.stringify(grid);
  }
  return '';
})();
