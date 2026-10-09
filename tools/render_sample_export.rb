# 生成示例角色卡（.htm 与 .docx），用于检查导出效果。
# 用法（在 src 目录下）：ruby ../tools/render_sample_export.rb [fixture.json] [输出前缀]
require 'json'
require_relative '../src/lib/sheet_export'
require_relative '../src/lib/data'

fixture = ARGV[0] || File.join(__dir__, 'fixtures', 'sample_charsheet.json')
prefix = ARGV[1] || 'sample_charsheet'
DATA = Charred::Data.new.data unless defined?(DATA)
I18N = Charred::I18n.new(ENV['CHARRED_LOCALE'] || 'zh-CN') unless defined?(I18N)
sheet = SheetExport.new(JSON.parse(File.read(fixture)), I18N, DATA)
File.write("#{prefix}.htm", sheet.to_html)
File.binwrite("#{prefix}.docx", sheet.to_docx)
puts "#{prefix}.htm: #{File.size("#{prefix}.htm") / 1024} KB, #{prefix}.docx: #{File.size("#{prefix}.docx") / 1024} KB"
