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
  function academic(doc) { return academicPath(doc) !== null; }
  var academicLogin = false, academicHome = false, frameErrors = 0, hiddenFrames = 0, exportControls = 0;
  function answer(kind, action, url) {
    var tableCount = 0, courseHeader = false, timeHeader = false;
    for (var d = 0; d < documents.length; d++) {
      var doc = documents[d], body = doc.body ? doc.body.innerText : '';
      tableCount += doc.querySelectorAll('table').length;
      courseHeader = courseHeader || /课程名称|课程名/.test(body);
      timeHeader = timeHeader || /实际上课时间|上课时间/.test(body);
    }
    return JSON.stringify({kind: kind, action: action || '', url: url || '', academicHome: academicHome,
      structure: {documents: documents.length, frameErrors: frameErrors, tables: tableCount,
        courseHeader: courseHeader, timeHeader: timeHeader, hiddenFrames: hiddenFrames,
        exportControls: exportControls}});
  }
  function trusted(doc) {
    try {
      var host = doc.location.hostname.toLowerCase();
      return doc.location.protocol === 'https:' && (host === 'nua.edu.cn' || host.endsWith('.nua.edu.cn'))
        && host !== 'c.nua.edu.cn' && !/\/cas\/(login|logout)/i.test(doc.location.pathname || '')
        && !doc.querySelector('input[type=password]');
    } catch (e) { return false; }
  }
  function docs(win, result, depth) {
    if (depth > 5) return;
    try {
      var doc = win.document;
      // The user's screenshot confirms this is a profile-edit page, not a course source.
      if (/^\/jsxsd\/grsz\//i.test(academicPath(doc) || '')) return;
      // Only inspect the presence of a password control; never read or submit its value.
      if (doc.location.protocol === 'https:' && /^\/jsxsd\//.test(academicPath(doc) || '')
          && Array.from(doc.querySelectorAll('input[type=password]')).some(function (input) {
            return visible(input);
          })) {
        academicLogin = true;
        return;
      }
      if (!trusted(win.document)) return;
      result.push(win.document);
      if (academicPath(doc) === '/jsxsd/framework/xsMain.jsp') {
        // The address alone isn't proof of login; require visible academic navigation as well.
        var menu = Array.from(doc.querySelectorAll('a,button,[role=button],span,div,input[type=button]'));
        academicHome = academicHome || menu.some(function (node) {
          return visible(node) && /^(退出|注销|退出登录|个人课表|我的课表|学期课表|学生个人课表|教学查询|培养管理|学生课表查询)$/.test(menuText(node));
        });
      }
      for (var i = 0; i < win.frames.length; i++) {
        try {
          var frame = win.frames[i].frameElement;
          if (frame && !frameVisible(frame)) { hiddenFrames++; continue; }
          docs(win.frames[i], result, depth + 1);
        } catch (e) { frameErrors++; }
      }
    } catch (e) { frameErrors++; }
  }
  function clean(v) { return (v || '').replace(/\s+/g, '').trim(); }
  function menuText(node) {
    // Strip only decorative edge arrows, not arbitrary words or embedded labels.
    return clean(node.innerText || node.textContent || node.value)
      .replace(/^[•·●›»‹«▶▸▹▼▾▽▲▴△+−]+|[•·●›»‹«▶▸▹▼▾▽▲▴△+−]+$/g, '');
  }
  function matchesMenu(node, label) {
    if (menuText(node) === label) return true;
    return !!node.getAttribute && (clean(node.getAttribute('title')) === label
      || clean(node.getAttribute('aria-label')) === label);
  }
  function visible(node) { return node.getClientRects().length && !node.disabled; }
  function frameVisible(frame) {
    var rects = frame.getClientRects();
    if (!rects.length || rects[0].width === 0 || rects[0].height === 0) return false;
    var win = frame.ownerDocument && frame.ownerDocument.defaultView;
    if (win && win.getComputedStyle) {
      var style = win.getComputedStyle(frame);
      if (style.visibility === 'hidden' || style.visibility === 'collapse' || style.display === 'none') return false;
    }
    return true;
  }
  function academicShell(doc) {
    return academicPath(doc) === '/jsxsd/framework/xsMain.jsp';
  }
  function hasWeekGrid(doc) {
    return Array.from(doc.querySelectorAll('table')).some(function (table) {
      if (!table.rows) return false;
      var foundHeader = false, foundCourse = false;
      for (var r = 0; r < table.rows.length; r++) {
        var labels = new Set();
        for (var c = 0; c < table.rows[r].children.length; c++) {
          var value = table.rows[r].children[c].innerText || '';
          var label = clean(value);
          if (/^(星期|周)[一二三四五六日天]$/.test(label)) labels.add(label.slice(-1).replace('天', '日'));
          if (/\[\s*\d[\d\s,，、\-—–至]*节\s*\]/.test(value)) foundCourse = true;
        }
        if (r < 10 && labels.size === 7) foundHeader = true;
      }
      return foundHeader && foundCourse;
    });
  }
  function personalTimetable(doc) {
    return /个人课表|我的课表|学期(?:理论)?课表/.test(doc.title + (doc.body ? doc.body.innerText : ''));
  }
  function state(doc) {
    var epoch = window.__nuaSyncEpoch || 0;
    if (!doc.__nuaSyncState || doc.__nuaSyncState.epoch !== epoch)
      doc.__nuaSyncState = {actions: Object.create(null), epoch: epoch};
    return doc.__nuaSyncState;
  }
  function once(doc, key) {
    var actions = state(doc).actions;
    if (actions[key]) return false;
    actions[key] = true;
    return true;
  }
  function clickLabel(doc, node, label) {
    // Portal cards often put the action on a containing anchor, not the decorative label.
    var target = node.closest && node.closest('a[href],button,[role=button],[onclick]') || node;
    if (!target.contains(node)) target = node;
    // Try the other rendered portal copy once if a decorative copy did not open anything.
    var key = 'click:' + label, actions = state(doc).actions, previous = actions[key];
    if (previous) {
      if (label.indexOf('教务系统') !== 0 || typeof previous !== 'object' || previous.count >= 2 || Date.now() - previous.at < 6000 || previous.target === target) return false;
      actions[key] = {count: previous.count + 1, at: Date.now(), target: target};
    } else actions[key] = {count: 1, at: Date.now(), target: target};
    target.scrollIntoView({block: 'center', inline: 'nearest'});
    target.click();
    return true;
  }
  function setValue(input, value) {
    var win = input.ownerDocument.defaultView;
    var proto = input.tagName === 'SELECT' ? win.HTMLSelectElement.prototype : win.HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto, 'value');
    if (setter && setter.set) setter.set.call(input, value); else input.value = value;
    input.dispatchEvent(new win.Event('input', {bubbles: true}));
    input.dispatchEvent(new win.Event('change', {bubbles: true}));
  }
  var documents = [];
  docs(window, documents, 0);
  if (academicLogin) return answer('sso_required', '教务会话未建立，需要从门户完成单点登录');
  if (!documents.length) return answer('login', '等待学校认证');
  // Export only the personal timetable whose table is actually present; never a home/grade export.
  for (var d = 0; d < documents.length; d++) {
    var doc = documents[d], body = doc.body ? doc.body.innerText : '';
    if (!academic(doc) || !personalTimetable(doc)) continue;
    var tables = Array.from(doc.querySelectorAll('table'));
    var list = /课程名称|课程名/.test(body) && /实际上课时间|上课时间/.test(body);
    var weekGrid = hasWeekGrid(doc);
    if (!tables.length || (!list && !weekGrid)) continue;
    var controls = Array.from(doc.querySelectorAll('a,button,[role=button],input[type=button],input[type=submit]'))
      .filter(function (control) {
        return /^(导出|导出课表(?:为(?:xls|excel))?|导出(?:为)?(?:xls|excel)|导出学期课表)$/i.test(menuText(control))
          && visible(control);
      });
    exportControls += controls.length;
    if (state(doc).actions['export-xls'] && !window.__nuaAllowPageFallback)
      return answer('export_wait', '等待学校导出 XLS');
    if (window.__nuaAllowPageFallback) continue;
    for (var e = 0; e < controls.length; e++) {
      var control = controls[e];
      // A plain submit without a handler must not fall through to an unrelated form/login POST.
      var form = control.form;
      var type = (control.type || '').toLowerCase();
      var submit = control.tagName === 'INPUT' && type === 'submit'
        || control.tagName === 'BUTTON' && (!type || type === 'submit');
      if (form && submit && /post/i.test(form.method || '') && !control.getAttribute('onclick')) continue;
      if (once(doc, 'export-xls')) {
        control.click();
        return answer('export', '导出学期课表为 XLS');
      }
    }
  }
  // Expand page size before extraction, but do not alter an arbitrary term selection.
  for (var d = 0; d < documents.length; d++) {
    var doc = documents[d];
    var body = doc.body ? doc.body.innerText : '';
    if (!personalTimetable(doc)) continue;
    if (!/课程名称|课程名/.test(body) || !/实际上课时间|上课时间/.test(body)) continue;
    var selects = doc.querySelectorAll('select');
    for (var s = 0; s < selects.length; s++) {
      var select = selects[s];
      if (!visible(select)) continue;
      var pageSizes = Array.from(select.options).some(function (option) {
        var label = clean(option.text);
        return /^\d+(条|行)?$/.test(label) && parseInt(label, 10) >= 5 && parseInt(label, 10) <= 1000;
      });
      if (!pageSizes) continue; // Don't mistake a semester/week dropdown for pagination.
      for (var o = 0; o < select.options.length; o++) {
        var option = select.options[o];
        if (/^(全部|显示全部|全部记录)$/.test(clean(option.text)) && select.value !== option.value
            && once(doc, 'all-rows')) {
          setValue(select, option.value);
          return answer('acted', '显示完整课表');
        }
      }
    }
  }
  // Don't leave a course table after it is ready.
  for (var d = 0; d < documents.length; d++) {
    var doc = documents[d];
    var body = doc.body ? doc.body.innerText : '';
    var hasRows = Array.from(doc.querySelectorAll('table')).some(function (table) { return table.rows && table.rows.length > 1; });
    if (/课程名称|课程名/.test(body) && /实际上课时间|上课时间/.test(body)
        && hasRows && /个人课表|我的课表|学期(?:理论)?课表|学生课表|课表查询|实际上课时间/.test(doc.title + body)) return answer('ready', '读取完整课表');
    if (academic(doc) && personalTimetable(doc) && hasWeekGrid(doc))
      return answer('ready', '读取学期周视图（XLS未可用）');
  }
  // Only switch a personal timetable page to a list when its observed control offers that view.
  for (var d = 0; d < documents.length; d++) {
    var doc = documents[d], body = doc.body ? doc.body.innerText : '';
    if (!personalTimetable(doc) && !/学生课表/.test(doc.title + body)) continue;
    if (/课程名称|课程名/.test(body) && /实际上课时间|上课时间/.test(body)) continue;
    if (academicShell(doc)) continue; // Sidebar text doesn't make the homepage a timetable view.
    var views = doc.querySelectorAll('a,button,[role=button],input[type=button]');
    for (var v = 0; v < views.length; v++) {
      var label = clean(views[v].innerText || views[v].value);
      if (/^(列表|列表视图|列表形式|列表模式|课表列表)$/.test(label) && visible(views[v]) && once(doc, 'list-view')) {
        views[v].click();
        return answer('acted', '切换个人课表列表视图');
      }
    }
  }
  var labels = ['进入首页', '教务系统（新）', '教务系统(新)', '学期课表', '学生个人课表', '个人课表',
    '学生课表查询', '个人课表查询', '我的课表',
    '课表查询', '教学查询', '信息查询', '培养管理', '课程安排'];
  for (var w = 0; w < labels.length; w++) {
    for (var d = 0; d < documents.length; d++) {
      var doc = documents[d];
      var pageText = doc.body ? doc.body.innerText : '';
      // On a timetable query page, don't click its own breadcrumb/menu again.
      if (/课程名称|课程名/.test(pageText) && /实际上课时间|上课时间/.test(pageText)) continue;
      var nodes = Array.from(doc.querySelectorAll('a,button,[role=button],span,div,input[type=button]'));
      var knownTermTree = academic(doc)
        && nodes.some(function (node) { return matchesMenu(node, '我的课表'); })
        && nodes.some(function (node) { return matchesMenu(node, '学期课表') || matchesMenu(node, '培养管理'); });
      if (knownTermTree) {
        // Screenshot-confirmed branch: never drift into course/class queries or electives.
        if (['学期课表', '我的课表', '培养管理'].indexOf(labels[w]) < 0) continue;
        // After requesting the leaf, preserve the expanded parents while its frame loads.
        if (labels[w] !== '学期课表' && state(doc).actions['click:学期课表']) continue;
        if (labels[w] === '培养管理' && state(doc).actions['click:我的课表']) continue;
      }
      // Click the innermost label once per document/action, not every ancestor.
      nodes.sort(function (a, b) { return (a.children ? a.children.length : 0) - (b.children ? b.children.length : 0); });
      for (var n = 0; n < nodes.length; n++) {
        var node = nodes[n];
        if (!matchesMenu(node, labels[w]) || !visible(node)) continue;
        if (!clickLabel(doc, node, labels[w])) { if (labels[w].indexOf('教务系统') === 0) continue; break; }
        return answer('acted', '点击：' + labels[w]);
      }
    }
  }
  for (var d = 0; d < documents.length; d++) {
    var doc = documents[d];
    var portal = doc.location.hostname === 'i.nua.edu.cn';
    var nodes = doc.querySelectorAll('a,button,[role=button],span,div');
    if (portal) {
      for (var n = 0; n < nodes.length; n++) {
        if (clean(nodes[n].innerText) === '办事大厅' && visible(nodes[n]) && once(doc, 'hall')) {
          nodes[n].click();
          return answer('acted', '进入办事大厅');
        }
      }
    }
    // Never replace the academic shell with one of its tab frames (e.g. personal center).
    // Outside the academic site, follow only the confirmed homepage actually embedded by the portal.
    var frames = academic(doc) ? [] : doc.querySelectorAll('iframe[src],frame[src]');
    for (var f = 0; f < frames.length; f++) {
      var url;
      try { url = new URL(frames[f].getAttribute('src'), doc.location.href); } catch (e) { continue; }
      if (url.protocol === 'https:' && url.hostname.toLowerCase() === 'jwnew.nua.edu.cn'
          && url.pathname === '/jsxsd/framework/xsMain.jsp' && !url.username && !url.password
          && (url.port === '' || url.port === '443')
          && !/[?&](ticket|token|code|password)=/i.test(url.search)
          && !Array.from(url.searchParams.keys()).some(function (key) { return /^(ticket|token|code|password)$/i.test(key); })
          && (!frames[f].getClientRects || frameVisible(frames[f]))
          && url.href !== doc.location.href && once(doc, 'frame:' + url.href)) {
        return answer('open', '进入教务课表页面', url.href);
      }
    }
    if (academicShell(doc)) continue; // Wait for the chosen academic frame, not unrelated home controls.
    var inputs = doc.querySelectorAll('input[placeholder]');
    for (var n = 0; n < inputs.length; n++) {
      var input = inputs[n];
      if (!visible(input) || !/菜单名|应用名称|应用名|关键字/.test(input.getAttribute('placeholder') || '')
          || !once(doc, 'search')) continue;
      setValue(input, portal ? '教务' : '课表');
      var win = input.ownerDocument.defaultView;
      input.dispatchEvent(new win.KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
      input.dispatchEvent(new win.KeyboardEvent('keyup', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
      return answer('acted', portal ? '查找教务系统（新）' : '查找个人课表菜单');
    }
    if (personalTimetable(doc)) {
      var buttons = doc.querySelectorAll('button,input[type=button],input[type=submit],a');
      for (var b = 0; b < buttons.length; b++) {
        if (/^(查询|检索|查看课表)$/.test(clean(buttons[b].innerText || buttons[b].value))
            && visible(buttons[b]) && once(doc, 'query')) {
          buttons[b].click();
          return answer('acted', '获取当前学期课表');
        }
      }
    }
  }
  var empty = documents.every(function (doc) {
    return !clean(doc.body ? doc.body.innerText : '')
      && !doc.querySelectorAll('form,iframe,frame,input,button,a').length;
  });
  return empty ? answer('blank', '学校页面尚未显示内容') : answer('wait', '等待学校菜单或课程数据加载');
})();
