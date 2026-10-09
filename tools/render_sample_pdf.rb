# 生成示例角色卡 PDF，用于检查中文字体、缩放与分页。
# 用法（在 src 目录下）：ruby ../tools/render_sample_pdf.rb [fixture.json] [out.pdf]
require 'json'
require_relative '../src/lib/pdf'
require_relative '../src/lib/data'

fixture = ARGV[0] || File.join(__dir__, 'fixtures', 'sample_charsheet.json')
out = ARGV[1] || 'sample_charsheet.pdf'
DATA = Charred::Data.new.data unless defined?(DATA)
I18N = Charred::I18n.new(ENV['CHARRED_LOCALE'] || 'zh-CN') unless defined?(I18N)
character = JSON.parse(File.read(fixture))
File.binwrite(out, CharSheet.new(character, I18N).render(nil, DATA))
puts "#{out}: #{File.size(out) / 1024} KB"
