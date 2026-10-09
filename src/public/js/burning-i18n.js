/*
 * 汉化：前端翻译函数与 Angular 过滤器。
 * 对照表由服务器在 /i18n.js 中注入（window.CHARRED_I18N），规则与 src/lib/i18n.rb 一致：
 *   精确匹配（界面 → 数据名称 → 忽略大小写） → “X-wise”→“X通晓” → “X Setting/Subsetting”
 *   → 以“, ”连接的组合文字逐段翻译 → 都没有就原样返回英文。
 * 永远不会返回 undefined/空串（除非原文本就是空），也不会抛出异常。
 * 内部数据保持英文，因此导出的 .char 与上游英文版完全兼容。
 */
(function(){
  var I18N = window.CHARRED_I18N || {ui: {}, terms: {}, traitSummaries: {}};
  var ui = I18N.ui || {};
  var terms = I18N.terms || {};
  var summaries = I18N.traitSummaries || {};
  var termsLower = {};
  for (var k in terms) {
    if (terms.hasOwnProperty(k) && !termsLower.hasOwnProperty(k.toLowerCase())) termsLower[k.toLowerCase()] = terms[k];
  }
  var WISE = ui['-wise'] || '通晓';

  function keepWs(original, translated){
    var lead = original.match(/^\s*/)[0];
    var trail = original.match(/\s*$/)[0];
    return lead + translated + trail;
  }

  function lookup(s){
    var key = s.trim();
    if (!key) return null;
    var hit = ui.hasOwnProperty(key) ? ui[key] : (terms.hasOwnProperty(key) ? terms[key] : termsLower[key.toLowerCase()]);
    if (hit) return keepWs(s, hit);

    if (/-wise$/i.test(key) && key.length > 5){
      var b = lookup(key.slice(0, -5));
      if (b) return keepWs(s, b.trim() + WISE);
    }
    var suffixes = [[' Subsetting', '子背景'], [' Setting', '背景']];
    for (var i = 0; i < suffixes.length; i++){
      var suf = suffixes[i][0];
      if (key.length > suf.length && key.slice(-suf.length) === suf){
        var bz = lookup(key.slice(0, -suf.length));
        if (bz) return keepWs(s, bz.trim() + suffixes[i][1]);
      }
    }
    if (key.indexOf(', ') >= 0){
      var parts = key.split(', ');
      var any = false;
      var out = parts.map(function(p){ var z = lookup(p); if (z) { any = true; return z.trim(); } return p; });
      if (any) return keepWs(s, out.join('，'));
    }
    return null;
  }

  // 翻译任意显示值；数组按“、”连接。
  window.tr = function(text){
    try {
      if (text === null || text === undefined) return '';
      if (angular.isArray(text)) return text.map(function(x){ return window.tr(x); }).join('、');
      var s = String(text);
      if (!s.trim()) return s;
      var z = lookup(s);
      return z === null ? s : z;
    } catch (e) {
      return text === null || text === undefined ? '' : String(text);
    }
  };

  // 带 {占位符} 的句子：先翻译模板，再代入参数（参数需调用方自行 tr）。
  window.trf = function(template, params){
    var out = window.tr(template);
    params = params || {};
    for (var p in params){
      if (params.hasOwnProperty(p)) out = out.split('{' + p + '}').join(params[p]);
    }
    return out;
  };

  // 特质说明：中文摘要 → 英文原文 → 空串。
  window.trTraitDesc = function(name, englishDesc){
    if (name && summaries.hasOwnProperty(name)) return summaries[name];
    return englishDesc || '';
  };

  window.trHasTraitSummary = function(name){
    return !!(name && summaries.hasOwnProperty(name));
  };

  var app = angular.module('burning');
  app.filter('tr', function(){ return function(v){ return window.tr(v); }; });
  // “特质名: 1pt” 形式的下拉选项（值保持英文，供 addLifepathTrait 解析）
  app.filter('trLifepathTrait', function(){
    return function(v){
      var m = /^(.*): (\d+)pt$/.exec(String(v));
      return m ? window.trf('{name}: {n} pt', {name: window.tr(m[1]), n: m[2]}) : window.tr(v);
    };
  });
  app.filter('trTraitDesc', function(){ return function(name, englishDesc){ return window.trTraitDesc(name, englishDesc); }; });
})();
