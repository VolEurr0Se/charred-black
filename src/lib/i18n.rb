require 'json'

module Charred
  # 汉化对照表。内部数据（.char、生命历程要求、技能名等）一律保持英文，
  # 只在显示时查表；查不到就原样返回英文，绝不返回空串、绝不抛异常。
  #
  # 对照表位于 data/i18n/<locale>/：
  #   ui.json               界面文字（ERB 模板、前端提示）
  #   terms.json            游戏数据名称与要求文字（背景、人生历程、技能、特质、资源……）
  #   trait_summaries.json  特质效果摘要（原创简述，非规则书译文）
  # 前端 public/js/burning-i18n.js 用同一套规则实现 tr()，两边结果一致。
  class I18n
    WISE_SUFFIX = '-wise'.freeze

    attr_reader :locale, :ui, :terms, :summaries

    def initialize(locale = 'zh-CN', dir = File.join(__dir__, '..', 'data', 'i18n'))
      @locale = locale
      base = File.join(dir, locale)
      @ui = load_json(File.join(base, 'ui.json'))
      @terms = load_json(File.join(base, 'terms.json'))
      @summaries = load_json(File.join(base, 'trait_summaries.json'))
      @terms_ci = {}
      @terms.each { |k, v| @terms_ci[k.downcase] ||= v }
      @wise = @ui['-wise'] || '通晓'
    end

    # 翻译任意显示文字。nil/非字符串也安全处理。
    def t(text)
      return '' if text.nil?
      return text.map { |x| t(x) }.join('、') if text.is_a?(Array)
      s = text.to_s
      return s if s.strip.empty?
      lookup(s) || s
    rescue StandardError
      text.to_s
    end

    # 带 {name} 占位符的句子：先翻译模板，再代入（参数由调用方决定是否翻译）。
    def tf(template, params = {})
      out = t(template)
      params.each { |k, v| out = out.gsub("{#{k}}", v.to_s) }
      out
    end

    # 特质说明：优先中文摘要，其次英文原文，最后空串。
    def trait_desc(name, english = nil)
      @summaries[name.to_s] || english.to_s
    end

    def payload
      { 'locale' => @locale, 'ui' => @ui, 'terms' => @terms, 'traitSummaries' => @summaries }
    end

    def to_js
      "window.CHARRED_I18N = #{JSON.generate(payload)};\n"
    end

    private

    def load_json(path)
      return {} unless File.exist?(path)
      JSON.parse(File.read(path, encoding: 'utf-8'))
    rescue JSON::ParserError => e
      warn "i18n: failed to parse #{path}: #{e.message}"
      {}
    end

    def lookup(s)
      key = s.strip
      hit = @ui[key] || @terms[key] || @terms_ci[key.downcase]
      return keep_ws(s, hit) if hit

      # X-wise → X通晓（自定义通晓技能）
      if key.downcase.end_with?(WISE_SUFFIX) && key.length > WISE_SUFFIX.length
        base = key[0...-WISE_SUFFIX.length]
        bz = lookup(base)
        return keep_ws(s, "#{bz}#{@wise}") if bz
      end

      # "X Setting" / "X Subsetting"
      [[' Subsetting', '子背景'], [' Setting', '背景']].each do |suffix, zh|
        if key.end_with?(suffix)
          bz = lookup(key[0...-suffix.length])
          return keep_ws(s, "#{bz}#{zh}") if bz
        end
      end

      # 资源描述等以 ", " 连接的组合文字：逐段翻译
      if key.include?(', ')
        parts = key.split(', ')
        zh = parts.map { |p| lookup(p) }
        return keep_ws(s, parts.each_with_index.map { |p, i| zh[i] || p }.join('，')) if zh.any?
      end
      nil
    end

    def keep_ws(original, translated)
      lead = original[/\A\s*/]
      trail = original[/\s*\z/]
      "#{lead}#{translated}#{trail}"
    end
  end
end
