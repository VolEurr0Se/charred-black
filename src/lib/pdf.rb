require 'prawn'
require 'prawn/templates'
require_relative 'i18n'

class CharSheet
  # 汉化：中文字体（SIL OFL 1.1，见 data/fonts/OFL-NotoSansSC.txt）。Prawn 对 TTF 默认子集嵌入，
  # 只写入实际用到的字形，所以生成的 PDF 只增加几十 KB。
  CJK_FONT = 'NotoSansSC'.freeze
  CJK_FONT_PATH = 'data/fonts/NotoSansSC-Regular.ttf'.freeze
  CJK_RE = /[\u2E80-\u2FFF\u3000-\u303F\u3040-\u30FF\u3100-\u312F\u3200-\u9FFF\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFFEF]/
  # 可在其后断行的字符：汉字与中文句末/句中标点；后面紧跟“不能出现在行首”的标点时不断行（避头尾）
  CJK_BREAK_AFTER_RE = /([\u2E80-\u2FFF\u3040-\u30FF\u3100-\u312F\u3200-\u9FFF\uF900-\uFAFF，。；：、！？）」』”’〉》】])(?![，。；：、！？）」』”’〉》】,.;:!?)\]])/
  ZWSP = "\u200B".freeze

  def initialize(character, i18n = nil)
    @character = character
    @i18n = i18n || (defined?(I18N) ? I18N : Charred::I18n.new)
    @t1 = 16
    @t2 = 12
    @t2b = 10
    @t3 = 10
    @t3b = 8
    @caliban = 'data/caliban.ttf'
    @bauerbodoni = 'data/bauerbodoni.ttf'
    @mediaeval = 'public/fonts/post-mediaeval.ttf'
  end

  def t(text)
    @i18n.t(text)
  end

  def cjk?(text)
    !!(text.to_s =~ CJK_RE)
  end

  # 含中文的文字一律用中文字体；纯英文/数字保持原字体。
  def font_for(text, default)
    cjk?(text) ? CJK_FONT : default
  end

  # 在汉字之间插入零宽空格，让 Prawn 可以在任意两个汉字之间换行（零宽空格不会被绘制）。
  def breakable(text)
    text.to_s.gsub(CJK_BREAK_AFTER_RE, "\\1#{ZWSP}").sub(/#{ZWSP}\z/, '')
  end

  def register_fonts(pdf)
    pdf.font_families.update(
      CJK_FONT => { :normal => CJK_FONT_PATH, :bold => CJK_FONT_PATH,
                    :italic => CJK_FONT_PATH, :bold_italic => CJK_FONT_PATH }
    )
    # 英文字体里没有的字形（例如中文标点、少见符号）自动回退到中文字体
    pdf.fallback_fonts [CJK_FONT]
  end

  # 固定格子里的单行/多行文字：自动缩小字号，保证不溢出、不与相邻格子重叠。
  # at 为基线位置时传 baseline: true（与原 draw_text 坐标兼容）。
  def fit_text(pdf, text, at:, width:, height: nil, size:, font:, baseline: false, valign: :bottom, min_size: 4, single_line: true)
    text = text.to_s
    return if text.strip.empty?
    x, y = at
    height ||= size + 2
    y = y + size if baseline
    content = single_line ? text : breakable(text)
    pdf.font(font_for(text, font)) do
      pdf.text_box content, :at => [x, y], :width => width, :height => height,
                   :overflow => :shrink_to_fit, :min_font_size => min_size,
                   :size => size, :valign => valign, :single_line => single_line,
                   :leading => (single_line ? 0 : 1),
                   :disable_wrap_by_char => false
    end
  end

  def render_skill(pdf, skilldef, at)
    skill, shade, exponent = skilldef
    x, y = at

    self.fit_text(pdf, t(skill), :at => [x, y + 10], :width => 95, :height => 15, :size => @t1, :font => @caliban)

    self.render_shade_exponent(pdf, shade, exponent, [x+101.5, y-0.8], 13.5, -0.2)
  end

  def render_shade_exponent(pdf, shade, exponent, at, xs = 13, ys = 0.5) 
    x, y = at
    pdf.draw_text shade, :at => [x, y], :size => @t2
    pdf.draw_text (exponent.to_s), :at => [x+xs, y+ys], :size => @t2
  end

  def render_trait(pdf, name, trait)
    trait_type = {
      "die" => "Die",
      "call_on" => "Call-on",
      "character" => "Character"
    }[trait["type"]]
    trait_type_zh = { "die" => t("die"), "call_on" => t("call-on"), "character" => t("character") }[trait["type"]] || trait_type.to_s

    trait_desc = @i18n.trait_desc(name, trait["desc"])
    display_name = t(name)

    pdf.font font_for(display_name, @mediaeval)
    pdf.text breakable(display_name), :size => @t2
    pdf.move_down 5

    pdf.font font_for(trait_type_zh, @bauerbodoni)
    pdf.text "#{trait_type_zh}", :size => @t3b

    if trait_desc && !trait_desc.empty?
      pdf.move_down 5
      pdf.font font_for(trait_desc, @bauerbodoni)
      pdf.text breakable(trait_desc), :size => @t2b, :leading => 2
    end

    pdf.move_down 10
  end

  def render_questions(pdf, name, questions)
    title = t(name)
    pdf.font font_for(title, @mediaeval)
    pdf.text "#{title}", :size => @t2

    questions.each do |q|
      pdf.move_down 5
      yes = q["answer"]
      line = "#{t(q["question"])} #{yes ? t("Yes.") : t("No.")}"
      pdf.font font_for(line, @bauerbodoni)
      pdf.text breakable(line), :size => @t2b, :leading => 2
    end

    pdf.move_down 10
  end

  def render(logger, data)
    # 中文模板与原模板版面完全一致（仅标签为中文），坐标通用；缺失时回退英文模板
    template = (@i18n.locale.to_s.start_with?('zh') && File.exist?('data/gold_zh.pdf')) ? 'data/gold_zh.pdf' : 'data/gold.pdf'
    pdf = Prawn::Document.new(:template => template)
    register_fonts(pdf)
    pdf.font @caliban
    pdf.default_leading -4

    # logger.info @character
   
    <<-GRID
    (0...40).each do |x|
      (0...30).each do |y|
        if x % 5 == 0 && y % 5 == 0
          pdf.stroke_color "ff0000"
        else
          pdf.stroke_color "cccccc"
        end
        pdf.stroke_circle [x * 20, y * 20], 1
      end
    end

    pdf.go_to_page(2)

    (0...40).each do |x|
      (0...30).each do |y|
        if x % 5 == 0 && y % 5 == 0
          pdf.stroke_color "ff0000"
        else
          pdf.stroke_color "cccccc"
        end
        pdf.stroke_circle [x * 20, y * 20], 1
      end
    end
    GRID

    # 姓名为玩家输入，不翻译；族裔、人生历程等按对照表翻译
    self.fit_text(pdf, @character['name'], :at => [5, 490], :width => 76, :size => @t1, :font => @caliban, :baseline => true)
    stock = @character['stock'].to_s
    self.fit_text(pdf, t(stock) == stock ? stock.capitalize : t(stock), :at => [84, 490], :width => 78, :size => @t1, :font => @caliban, :baseline => true)
    self.fit_text(pdf, @character['age'], :at => [165, 490], :width => 76, :size => @t1, :font => @caliban, :baseline => true)
    lifepaths = (@character['lifepaths'] || []).map { |lp| t(lp) }
    lp_sep = lifepaths.any? { |lp| cjk?(lp) } ? '、' : ', '
    self.fit_text(pdf, lifepaths.join(lp_sep), :at => [245, 499], :width => 100, :height => 26, :size => @t2, :font => @caliban, :valign => :top, :single_line => false)

    character_traits = @character['traits'].select {|t| t[1] == 'character'}.map {|t| t[0] }
    die_traits = @character['traits'].select {|t| t[1] == 'die'}.map {|t| t[0] }
    call_on_traits = @character['traits'].select {|t| t[1] == 'call_on'}.map {|t| t[0] }

    # 原代码此处拼写为 :shring_to_fit（不会缩小），已统一改为自动缩小
    list_join = lambda { |items| items.any? { |i| cjk?(i) } ? items.join('、') : items.join(', ') }
    self.fit_text(pdf, list_join.call(character_traits.map { |n| t(n) }), :at => [5, 214], :width => 110, :height => 50, :size => @t2, :font => @caliban, :valign => :top, :single_line => false)
    self.fit_text(pdf, list_join.call(die_traits.map { |n| t(n) }), :at => [122, 214], :width => 110, :height => 50, :size => @t2, :font => @caliban, :valign => :top, :single_line => false)
    self.fit_text(pdf, list_join.call(call_on_traits.map { |n| t(n) }), :at => [241, 207], :width => 110, :height => 40, :size => @t2, :font => @caliban, :valign => :top, :single_line => false)

    gear = (@character['gear'] + @character['property']).map { |g| t(g) }
    self.fit_text(pdf, list_join.call(gear), :at => [30, 55], :width => 280, :height => 42, :size => @t2, :font => @caliban, :valign => :top, :single_line => false)

    # 名声/从属的格式为 "描述 2D"：只翻译描述部分
    dice_suffix = lambda { |r| (m = r.to_s.match(/\A(.*) (\d+D)\z/)) ? "#{t(m[1])} #{m[2]}" : t(r) }
    relationships = @character['relationships'].map { |r| t(r) } +
                    @character['reputations'].map(&dice_suffix) +
                    @character['affiliations'].map(&dice_suffix)
    self.fit_text(pdf, relationships.join("\n"), :at => [5, 136], :width => 80, :height => 60, :size => @t2, :font => @caliban, :valign => :top, :single_line => false)

    per_apt = 10 - @character['stats']['perception'][1]
    wil_apt = 10 - @character['stats']['will'][1]
    agi_apt = 10 - @character['stats']['agility'][1]
    spd_apt = 10 - @character['stats']['speed'][1]
    pow_apt = 10 - @character['stats']['power'][1]
    for_apt = 10 - @character['stats']['forte'][1]

    pdf.draw_text per_apt, :at => [433, 207], :size => @t2
    pdf.draw_text wil_apt, :at => [482, 207], :size => @t2
    pdf.draw_text agi_apt, :at => [539, 207], :size => @t2
    pdf.draw_text spd_apt, :at => [593, 207], :size => @t2
    pdf.draw_text pow_apt, :at => [647, 207], :size => @t2
    pdf.draw_text for_apt, :at => [699, 207], :size => @t2

    pdf.go_to_page(2)

    wil_stat = @character['stats']['will']
    per_stat = @character['stats']['perception']
    pow_stat = @character['stats']['power']
    for_stat = @character['stats']['forte']
    agi_stat = @character['stats']['agility']
    spd_stat = @character['stats']['speed']

    self.render_shade_exponent(pdf, wil_stat[0], wil_stat[1], [54, 501])
    self.render_shade_exponent(pdf, per_stat[0], per_stat[1], [54, 462])
    self.render_shade_exponent(pdf, pow_stat[0], pow_stat[1], [166, 501])
    self.render_shade_exponent(pdf, for_stat[0], for_stat[1], [166, 462])
    self.render_shade_exponent(pdf, agi_stat[0], agi_stat[1], [276.5, 501])
    self.render_shade_exponent(pdf, spd_stat[0], spd_stat[1], [276.5, 462])

    hlt_attr = @character['attributes']['health']
    stl_attr = @character['attributes']['steel']
    cir_attr = @character['attributes']['circles']
    res_attr = @character['attributes']['resources']
    ref_attr = @character['attributes']['reflexes']
    mor_attr = @character['attributes']['mortal wound']
    str_attr = @character['attributes']['stride']
    hes_attr = @character['attributes']['hesitation']

    self.render_shade_exponent(pdf, hlt_attr[0], hlt_attr[1], [52, 396.5])
    self.render_shade_exponent(pdf, stl_attr[0], stl_attr[1], [52, 351.5])
    self.render_shade_exponent(pdf, cir_attr[0], cir_attr[1], [54, 296])
    self.render_shade_exponent(pdf, res_attr[0], res_attr[1], [54, 249.5])
    self.render_shade_exponent(pdf, ref_attr[0], ref_attr[1], [279, 396.5])
    self.render_shade_exponent(pdf, mor_attr[0], mor_attr[1], [278.5, 346])

    emo_name = ''
    emo_attr = nil

    ['Spite', 'Grief', 'Greed', 'Faith', 'Hatred', 'Ancestral Taint'].each do |emo|
      if not @character['attributes'][emo.downcase].nil?
        emo_name = emo
        emo_attr = @character['attributes'][emo.downcase]
        emo_name = 'Taint' if emo_name == 'Ancestral Taint' # two words is too big
        emo_name = t(emo_name)
        break
      end
    end

    if not emo_attr.nil?
      self.fit_text(pdf, emo_name, :at => [127, 398], :width => 36, :size => @t2, :font => @caliban, :baseline => true)
      self.render_shade_exponent(pdf, emo_attr[0], emo_attr[1], [164.5, 398.3])
    end

    ptgs = @character['ptgs']
    ["Su", "Li", "Mi", "Se", "Tr", "Mo"].each do |tol|
      tol_c = ptgs[tol.downcase]
      self.fit_text(pdf, t(tol), :at => [29 + (19.5 * tol_c), 190], :width => 18, :size => @t2, :font => @caliban, :baseline => true)
    end

    pdf.draw_text str_attr[1], :at => [264, 428], :size => @t2
    pdf.draw_text hes_attr[1], :at => [53, 318], :size => @t2

    skills_left = @character['skills'][0...13]
    skills_right = @character['skills'][13...26]

    if skills_left
      skills_left.each_with_index do |s, i|
        self.render_skill(pdf, s, [372, 495 - (i*20.3)])
      end
    end

    if skills_right
      skills_right.each_with_index do |s, i|
        self.render_skill(pdf, s, [551, 495 - (i*20.3)])
      end
    end

    options = {
      :page_layout => :landscape,
      :margin => 0
    }

    pdf.start_new_page(:layout => :landscape, :margin => 36)
    pdf.default_leading = 0

    pdf.column_box([0, pdf.cursor], :columns => 3, :width => pdf.bounds.width) do
      traits_title = t("Traits")
      pdf.font font_for(traits_title, @mediaeval)
      pdf.text traits_title, :size => @t1
      pdf.move_down 4
      note = t("(trait summary)")
      if cjk?(note)
        pdf.font CJK_FONT
        pdf.text note, :size => @t3b, :color => '555555'
      end
      pdf.move_down 6

      trait_list = @character['traits'].sort { |a, b| a <=> b }
      trait_list.each_with_index do |t, i|
        name = t[0]
        trait = DATA[:traits][name]

        if trait.nil?
          trait = {
            "type" => "character"
          }
        end

        self.render_trait(pdf, name, trait)
      end

      pdf.move_down 10
      aq_title = t("Attribute Questions")
      pdf.font font_for(aq_title, @mediaeval)
      pdf.text aq_title, :size => @t1
      pdf.move_down 10

      attr_mods = @character['attr_mod_questions']

      attr_mods.each do |name, questions|
        self.render_questions(pdf, name, questions)
      end
    end

    pdf.render
  end
end
