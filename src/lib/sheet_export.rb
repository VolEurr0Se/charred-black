require 'zlib'
require 'time'
require_relative 'i18n'

# 角色卡导出：HTML（.htm）与 Word（.docx）。
# 两种格式共用同一份“卡片模型”，只依赖 Ruby 标准库（docx 由内置的 MiniZip 打包），
# 不需要额外的 gem。所有用户输入都会做 HTML / XML 转义。
class SheetExport
  STAT_KEYS = %w[will perception power forte agility speed].freeze
  STAT_NAMES = {
    'will' => 'Will', 'perception' => 'Perception', 'power' => 'Power',
    'forte' => 'Forte', 'agility' => 'Agility', 'speed' => 'Speed'
  }.freeze
  ATTR_ORDER = ['health', 'steel', 'circles', 'resources', 'reflexes', 'mortal wound', 'hesitation', 'stride',
                'greed', 'grief', 'spite', 'hatred', 'faith', 'ancestral taint'].freeze
  ATTR_NAMES = {
    'health' => 'Health', 'steel' => 'Steel', 'circles' => 'Circles', 'resources' => 'Resources',
    'reflexes' => 'Reflexes', 'mortal wound' => 'Mortal Wound', 'hesitation' => 'Hesitation', 'stride' => 'Stride',
    'greed' => 'Greed', 'grief' => 'Grief', 'spite' => 'Spite', 'hatred' => 'Hatred', 'faith' => 'Faith',
    'ancestral taint' => 'Ancestral Taint'
  }.freeze
  PTGS = [%w[su Su], %w[li Li], %w[mi Mi], %w[se Se], %w[tr Tr], %w[mo Mo]].freeze
  TRAIT_TYPE = { 'character' => 'character', 'call_on' => 'call-on', 'die' => 'die' }.freeze

  def initialize(character, i18n, data)
    @c = character || {}
    @i18n = i18n
    @data = data || {}
  end

  def t(s)
    @i18n.t(s)
  end

  # 中文语境下列表用“、”，纯英文时保留英文逗号
  def join_list(items)
    items = items.map(&:to_s).reject(&:empty?)
    items.any? { |i| i =~ /\p{Han}/ } ? items.join('、') : items.join(', ')
  end

  def shade_exp(pair)
    return '' unless pair.is_a?(Array)
    "#{pair[0]}#{pair[1]}"
  end

  # ---------- 卡片模型 ----------

  def model
    @model ||= begin
      stats = @c['stats'] || {}
      attrs = @c['attributes'] || {}
      skills = Array(@c['skills'])
      traits = Array(@c['traits']).sort_by { |tr| tr[0].to_s }
      {
        title: t('Character Sheet'),
        name: @c['name'].to_s,
        index: [
          [t('Name'), @c['name'].to_s],
          [t('Stock'), t(@c['stock'].to_s)],
          [t('Age'), @c['age'].to_s],
          [t('Lifepaths'), join_list(Array(@c['lifepaths']).map { |lp| t(lp) })]
        ],
        stats: STAT_KEYS.select { |k| stats[k] }.map do |k|
          [t(STAT_NAMES[k]), shade_exp(stats[k]), (10 - stats[k][1].to_i).to_s]
        end,
        attributes: ATTR_ORDER.select { |k| attrs[k] }.map do |k|
          v = attrs[k]
          value = %w[hesitation stride].include?(k) ? v[1].to_s : shade_exp(v)
          [t(ATTR_NAMES[k]), value]
        end,
        ptgs: PTGS.map { |key, label| [t(label), "B#{(@c['ptgs'] || {})[key]}"] },
        skills: skills.map do |s|
          name, shade, exp, training = s
          [t(name), training ? '—' : "#{shade}#{exp}", training ? t('Training skill') : '']
        end,
        traits: traits.map do |name, type|
          info = (@data[:traits] || {})[name] || {}
          ttype = TRAIT_TYPE[type.to_s] || TRAIT_TYPE[info['type'].to_s] || 'character'
          [t(name), t(ttype), @i18n.trait_desc(name, info['desc'])]
        end,
        gear: Array(@c['gear']).map { |g| t(g) },
        property: Array(@c['property']).map { |g| t(g) },
        relationships: Array(@c['relationships']).map { |r| t(r) },
        reputations: Array(@c['reputations']).map { |r| dice_suffix(r) },
        affiliations: Array(@c['affiliations']).map { |r| dice_suffix(r) },
        questions: (@c['attr_mod_questions'] || {}).map do |attr, qs|
          [t(attr), Array(qs).map { |q| [t(q['question']), q['answer'] ? t('Yes') : t('No')] }]
        end
      }
    end
  end

  def dice_suffix(r)
    m = r.to_s.match(/\A(.*) (\d+D)\z/)
    m ? "#{t(m[1])} #{m[2]}" : t(r)
  end

  def note_text
    t('(trait summary)')
  end

  # ---------- HTML ----------

  def h(s)
    s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("'", '&#39;')
  end

  def html_table(headers, rows, cls = nil)
    return "<p class='empty'>#{h(t('(none)'))}</p>" if rows.empty?
    out = +"<table#{cls ? " class='#{cls}'" : ''}>"
    out << '<thead><tr>' << headers.map { |x| "<th>#{h(x)}</th>" }.join << '</tr></thead>' if headers
    out << '<tbody>'
    rows.each { |r| out << '<tr>' << r.map { |x| "<td>#{h(x)}</td>" }.join << '</tr>' }
    out << '</tbody></table>'
  end

  def html_list(items)
    return "<p class='empty'>#{h(t('(none)'))}</p>" if items.empty?
    '<ul>' + items.map { |i| "<li>#{h(i)}</li>" }.join + '</ul>'
  end

  def blank_lines(labels)
    labels.map { |l| "<div class='blank'><span>#{h(l)}</span><i></i></div>" }.join
  end

  def to_html
    m = model
    title = [m[:name], m[:title]].reject(&:empty?).join(' · ')
    <<~HTML
      <!DOCTYPE html>
      <html lang="zh-CN">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{h(title)}</title>
      <style>
        :root { --ink:#1f1b16; --muted:#6b6257; --line:#cfc6b8; --head:#f3eee6; --accent:#7a2e1f; }
        * { box-sizing: border-box; }
        body { margin: 0; background: #faf8f4; color: var(--ink);
               font: 14px/1.6 "Noto Sans SC","Source Han Sans SC","PingFang SC","Microsoft YaHei","Helvetica Neue",Arial,sans-serif; }
        .sheet { max-width: 880px; margin: 24px auto; background: #fff; padding: 32px 40px; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
        h1 { margin: 0 0 4px; font-size: 26px; color: var(--accent); letter-spacing: 1px; }
        .sub { color: var(--muted); margin-bottom: 20px; }
        h2 { font-size: 17px; color: var(--accent); border-bottom: 2px solid var(--accent); padding-bottom: 2px; margin: 26px 0 10px; }
        h3 { font-size: 15px; margin: 14px 0 6px; }
        table { width: 100%; border-collapse: collapse; margin: 6px 0 4px; }
        th, td { border: 1px solid var(--line); padding: 4px 8px; text-align: left; vertical-align: top; }
        th { background: var(--head); font-weight: 600; white-space: nowrap; }
        table.kv td:first-child { width: 7em; background: var(--head); font-weight: 600; white-space: nowrap; }
        table.ptgs th, table.ptgs td { text-align: center; }
        .cols { display: grid; grid-template-columns: 1fr 1fr; gap: 0 28px; }
        ul { margin: 4px 0; padding-left: 1.4em; }
        .empty { color: var(--muted); margin: 4px 0; }
        .blank { display: flex; align-items: flex-end; gap: 8px; margin: 10px 0; }
        .blank span { white-space: nowrap; font-weight: 600; }
        .blank i { flex: 1; border-bottom: 1px solid var(--line); height: 1.2em; }
        .note { color: var(--muted); font-size: 12px; }
        footer { margin-top: 28px; color: var(--muted); font-size: 12px; border-top: 1px solid var(--line); padding-top: 8px; }
        @media (max-width: 640px) { .sheet { padding: 20px 16px; margin: 0; } .cols { grid-template-columns: 1fr; } }
        @media print { body { background: #fff; } .sheet { box-shadow: none; margin: 0; max-width: none; padding: 0; }
                       h2 { break-after: avoid; } tr, .blank { break-inside: avoid; } }
      </style>
      </head>
      <body>
      <div class="sheet">
        <h1>#{h(m[:name].empty? ? m[:title] : m[:name])}</h1>
        <div class="sub">#{h(t('Burning Wheel Gold'))} · #{h(m[:title])}</div>

        <h2>#{h(t('Character Index'))}</h2>
        #{html_table(nil, m[:index], 'kv')}

        <h2>#{h(t('Beliefs'))}</h2>
        #{blank_lines([t('Belief 1'), t('Belief 2'), t('Belief 3'), t('Belief Special')])}
        <h2>#{h(t('Instincts'))}</h2>
        #{blank_lines([t('Instinct 1'), t('Instinct 2'), t('Instinct 3')])}

        <div class="cols">
          <div>
            <h2>#{h(t('Stats'))}</h2>
            #{html_table([t('Stat'), t('Shade and Exponent'), t('Aptitude')], m[:stats])}
          </div>
          <div>
            <h2>#{h(t('Attributes'))}</h2>
            #{html_table([t('Attribute'), t('Value')], m[:attributes])}
          </div>
        </div>

        <h2>#{h(t('Physical Tolerances Grayscale'))}</h2>
        <table class="ptgs"><thead><tr>#{m[:ptgs].map { |l, _| "<th>#{h(l)}</th>" }.join}</tr></thead>
        <tbody><tr>#{m[:ptgs].map { |_, v| "<td>#{h(v)}</td>" }.join}</tr></tbody></table>

        <h2>#{h(t('Skills'))}</h2>
        #{html_table([t('Skill'), t('Shade and Exponent'), t('Notes')], m[:skills])}

        <h2>#{h(t('Traits'))}</h2>
        #{html_table([t('Trait'), t('Type'), t('Description')], m[:traits])}
        <p class="note">#{h(note_text)}</p>

        <h2>#{h(t('Resources'))}</h2>
        <div class="cols">
          <div><h3>#{h(t('Gear'))}</h3>#{html_list(m[:gear])}</div>
          <div><h3>#{h(t('Property'))}</h3>#{html_list(m[:property])}</div>
          <div><h3>#{h(t('Relationships'))}</h3>#{html_list(m[:relationships])}</div>
          <div><h3>#{h(t('Reputations'))} / #{h(t('Affiliations'))}</h3>#{html_list(m[:reputations] + m[:affiliations])}</div>
        </div>

        #{m[:questions].empty? ? '' : "<h2>#{h(t('Attribute Questions'))}</h2>" + m[:questions].map { |attr, qs| "<h3>#{h(attr)}</h3>" + html_table([t('Question'), t('Answer')], qs) }.join}

        <footer>#{h(t('Generated by Charred'))} · #{h(Time.now.strftime('%Y-%m-%d'))}</footer>
      </div>
      </body>
      </html>
    HTML
  end

  # ---------- DOCX ----------

  XML_INVALID = /[^\u0009\u000A\u000D -퟿-�\u{10000}-\u{10FFFF}]/

  def x(s)
    s.to_s.gsub(XML_INVALID, '').gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def w_run(text, bold: false, color: nil, size: nil)
    rpr = +''
    rpr << '<w:b/>' if bold
    rpr << "<w:color w:val=\"#{color}\"/>" if color
    rpr << "<w:sz w:val=\"#{size}\"/><w:szCs w:val=\"#{size}\"/>" if size
    "<w:r>#{rpr.empty? ? '' : "<w:rPr>#{rpr}</w:rPr>"}<w:t xml:space=\"preserve\">#{x(text)}</w:t></w:r>"
  end

  def w_p(text = '', style: nil, bold: false, color: nil, size: nil, keep_next: false)
    ppr = +''
    ppr << "<w:pStyle w:val=\"#{style}\"/>" if style
    ppr << '<w:keepNext/>' if keep_next
    "<w:p>#{ppr.empty? ? '' : "<w:pPr>#{ppr}</w:pPr>"}#{text.to_s.empty? ? '' : w_run(text, bold: bold, color: color, size: size)}</w:p>"
  end

  def w_cell(text, width, shade: false, bold: false, center: false)
    shd = shade ? '<w:shd w:val="clear" w:color="auto" w:fill="F3EEE6"/>' : ''
    jc = center ? '<w:jc w:val="center"/>' : ''
    "<w:tc><w:tcPr><w:tcW w:w=\"#{width}\" w:type=\"dxa\"/>#{shd}</w:tcPr>" \
      "<w:p><w:pPr><w:spacing w:before=\"20\" w:after=\"20\"/>#{jc}</w:pPr>#{w_run(text, bold: bold)}</w:p></w:tc>"
  end

  TEXT_WIDTH = 9638 # A4，左右各 2cm 页边距

  def w_table(headers, rows, widths, kv: false, center: false)
    return w_p(t('(none)'), color: '6B6257') if rows.empty?
    grid = widths.map { |w| "<w:gridCol w:w=\"#{w}\"/>" }.join
    out = +"<w:tbl><w:tblPr><w:tblStyle w:val=\"SheetTable\"/><w:tblW w:w=\"#{widths.sum}\" w:type=\"dxa\"/>" \
           '<w:tblLayout w:type="fixed"/></w:tblPr>' \
           "<w:tblGrid>#{grid}</w:tblGrid>"
    if headers
      out << '<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>'
      headers.each_with_index { |hd, i| out << w_cell(hd, widths[i], shade: true, bold: true, center: center) }
      out << '</w:tr>'
    end
    rows.each do |r|
      out << '<w:tr><w:trPr><w:cantSplit/></w:trPr>'
      r.each_with_index { |v, i| out << w_cell(v, widths[i], shade: kv && i.zero?, bold: kv && i.zero?, center: center) }
      out << '</w:tr>'
    end
    out << '</w:tbl>' << w_p('')
  end

  def w_list(items)
    return w_p(t('(none)'), color: '6B6257') if items.empty?
    items.map { |i| w_p("• #{i}") }.join
  end

  def w_blank(label)
    "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"1\" w:color=\"CFC6B8\"/></w:pBdr>" \
      "<w:spacing w:before=\"160\" w:after=\"60\"/></w:pPr>#{w_run("#{label}：", bold: true)}</w:p>"
  end

  def document_xml
    m = model
    tw = TEXT_WIDTH
    b = +''
    b << w_p(m[:name].empty? ? m[:title] : m[:name], style: 'Title')
    b << w_p("#{t('Burning Wheel Gold')} · #{m[:title]}", color: '6B6257')
    b << w_p(t('Character Index'), style: 'Heading1')
    b << w_table(nil, m[:index], [1800, tw - 1800], kv: true)
    b << w_p(t('Beliefs'), style: 'Heading1')
    [t('Belief 1'), t('Belief 2'), t('Belief 3'), t('Belief Special')].each { |l| b << w_blank(l) }
    b << w_p(t('Instincts'), style: 'Heading1')
    [t('Instinct 1'), t('Instinct 2'), t('Instinct 3')].each { |l| b << w_blank(l) }
    b << w_p(t('Stats'), style: 'Heading1')
    b << w_table([t('Stat'), t('Shade and Exponent'), t('Aptitude')], m[:stats], [3212, 3213, 3213])
    b << w_p(t('Attributes'), style: 'Heading1')
    b << w_table([t('Attribute'), t('Value')], m[:attributes], [4819, 4819])
    b << w_p(t('Physical Tolerances Grayscale'), style: 'Heading1')
    b << w_table(m[:ptgs].map(&:first), [m[:ptgs].map(&:last)], Array.new(6, tw / 6), center: true)
    b << w_p(t('Skills'), style: 'Heading1')
    b << w_table([t('Skill'), t('Shade and Exponent'), t('Notes')], m[:skills], [4400, 2400, tw - 6800])
    b << w_p(t('Traits'), style: 'Heading1')
    b << w_table([t('Trait'), t('Type'), t('Description')], m[:traits], [2400, 1100, tw - 3500])
    b << w_p(note_text, color: '6B6257', size: 18)
    b << w_p(t('Resources'), style: 'Heading1')
    [[t('Gear'), m[:gear]], [t('Property'), m[:property]], [t('Relationships'), m[:relationships]],
     ["#{t('Reputations')} / #{t('Affiliations')}", m[:reputations] + m[:affiliations]]].each do |label, items|
      b << w_p(label, style: 'Heading2')
      b << w_list(items)
    end
    unless m[:questions].empty?
      b << w_p(t('Attribute Questions'), style: 'Heading1')
      m[:questions].each do |attr, qs|
        b << w_p(attr, style: 'Heading2')
        b << w_table([t('Question'), t('Answer')], qs, [tw - 1400, 1400])
      end
    end
    b << w_p("#{t('Generated by Charred')} · #{Time.now.strftime('%Y-%m-%d')}", color: '6B6257', size: 18)
    <<~XML.delete("\n")
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <w:body>#{b}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/></w:sectPr></w:body></w:document>
    XML
  end

  def styles_xml
    font = '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei" w:cs="Calibri"/>'
    <<~XML.delete("\n")
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:docDefaults><w:rPrDefault><w:rPr>#{font}<w:sz w:val="21"/><w:szCs w:val="21"/><w:lang w:val="en-US" w:eastAsia="zh-CN"/></w:rPr></w:rPrDefault>
      <w:pPrDefault><w:pPr><w:spacing w:after="60" w:line="288" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
      <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
      <w:pPr><w:spacing w:after="40"/></w:pPr><w:rPr><w:b/><w:color w:val="7A2E1F"/><w:sz w:val="44"/><w:szCs w:val="44"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
      <w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:pBdr><w:bottom w:val="single" w:sz="8" w:space="1" w:color="7A2E1F"/></w:pBdr><w:outlineLvl w:val="0"/></w:pPr>
      <w:rPr><w:b/><w:color w:val="7A2E1F"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
      <w:pPr><w:keepNext/><w:spacing w:before="120" w:after="40"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style>
      <w:style w:type="table" w:styleId="SheetTable"><w:name w:val="Sheet Table"/><w:tblPr><w:tblBorders>
      <w:top w:val="single" w:sz="4" w:space="0" w:color="CFC6B8"/><w:left w:val="single" w:sz="4" w:space="0" w:color="CFC6B8"/>
      <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CFC6B8"/><w:right w:val="single" w:sz="4" w:space="0" w:color="CFC6B8"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="CFC6B8"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="CFC6B8"/>
      </w:tblBorders><w:tblCellMar><w:left w:w="100" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
      </w:styles>
    XML
  end

  def to_docx
    now = Time.now.utc.iso8601
    title = x([model[:name], model[:title]].reject(&:empty?).join(' '))
    files = {
      '[Content_Types].xml' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' \
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
        '<Default Extension="xml" ContentType="application/xml"/>' \
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' \
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' \
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' \
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>' \
        '</Types>',
      '_rels/.rels' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' \
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>' \
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>' \
        '</Relationships>',
      'word/_rels/document.xml.rels' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' \
        '</Relationships>',
      'word/document.xml' => document_xml,
      'word/styles.xml' => styles_xml,
      'docProps/core.xml' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ' \
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" ' \
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' \
        "<dc:title>#{title}</dc:title><dc:creator>Charred</dc:creator>" \
        "<dcterms:created xsi:type=\"dcterms:W3CDTF\">#{now}</dcterms:created>" \
        "<dcterms:modified xsi:type=\"dcterms:W3CDTF\">#{now}</dcterms:modified></cp:coreProperties>",
      'docProps/app.xml' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">' \
        '<Application>Charred</Application></Properties>'
    }
    MiniZip.build(files)
  end

  # 最小 ZIP 打包器（deflate），足够生成 Office 可读的 .docx。
  module MiniZip
    module_function

    def build(files)
      out = String.new(encoding: Encoding::BINARY)
      central = String.new(encoding: Encoding::BINARY)
      dos_time, dos_date = dos_timestamp(Time.now)
      files.each do |name, content|
        data = content.to_s.dup.force_encoding(Encoding::BINARY)
        name_b = name.dup.force_encoding(Encoding::BINARY)
        crc = Zlib.crc32(data)
        deflater = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
        comp = deflater.deflate(data, Zlib::FINISH)
        deflater.close
        offset = out.bytesize
        out << [0x04034b50, 20, 0x0800, 8, dos_time, dos_date, crc, comp.bytesize, data.bytesize,
                name_b.bytesize, 0].pack('VvvvvvVVVvv') << name_b << comp
        central << [0x02014b50, 20, 20, 0x0800, 8, dos_time, dos_date, crc, comp.bytesize, data.bytesize,
                    name_b.bytesize, 0, 0, 0, 0, 0, offset].pack('VvvvvvvVVVvvvvvVV') << name_b
      end
      cd_offset = out.bytesize
      out << central
      out << [0x06054b50, 0, 0, files.size, files.size, central.bytesize, cd_offset, 0].pack('VvvvvVVv')
      out
    end

    def dos_timestamp(time)
      [(time.hour << 11) | (time.min << 5) | (time.sec / 2),
       ((time.year - 1980) << 9) | (time.month << 5) | time.day]
    end
  end
end
