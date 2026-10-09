# 汉化版含中文模板与对照表：强制以 UTF-8 读取文件，避免容器内 locale 为 POSIX 时出现编码错误
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'sinatra'
require 'sinatra/json'
require 'json'

require_relative 'lib/cache'
require_relative 'lib/sheet_export'
require_relative 'lib/data'
require_relative 'lib/i18n'
require 'erb'

use Rack::Logger
set :bind, ENV['HOST']
set :port, ENV['PORT']

CACHE = Mu::Cache.new :max_size => 128, :max_time => 30.0
DATA = Charred::Data.new.data
I18N = Charred::I18n.new(ENV['CHARRED_LOCALE'] || 'zh-CN')
I18N_JS = I18N.to_js
# 静态资源版本号：取 public/ 下文件最新修改时间。用于给 JS/CSS 加 ?v=，避免浏览器沿用旧缓存。
ASSET_VERSION = Dir.glob(File.join(__dir__, 'public', '**', '*')).map { |f| File.mtime(f).to_i }.max.to_s
set :static_cache_control, [:public, :no_cache]

helpers do
  def logger
    request.logger
  end

  # 界面文字翻译（找不到时回退英文原文）
  def t(text)
    I18N.t(text)
  end

  # 下载文件名：同时提供 ASCII 回退与 RFC 5987 UTF-8 文件名，避免中文名乱码
  def attachment_utf8(name)
    ext = File.extname(name)
    ascii = name.gsub(/[^\x20-\x7E]/, '').gsub('"', '').strip
    ascii = "character#{ext}" if ascii.sub(/#{Regexp.escape(ext)}\z/, '').strip.empty?
    encoded = ERB::Util.url_encode(name)
    headers['Content-Disposition'] = "attachment; filename=\"#{ascii}\"; filename*=UTF-8''#{encoded}"
  end

  def download_url(key, filename)
    "/get_file?file=#{key}&download_name=#{ERB::Util.url_encode(filename)}"
  end
end

get '/i18n.js' do
  content_type 'application/javascript', :charset => 'utf-8'
  cache_control :public, :max_age => 3600
  I18N_JS
end

get '/' do
  erb :index
end

get '/list_chars/:user' do
  "{}"
end

get /\/([\w]+)_partial/ do
  partial = params['captures'].first
  # 有本地化版本的局部模板（如 help_zh.erb）优先使用
  localized = "partials/#{partial}_zh"
  if File.exist?(File.join(settings.views, "#{localized}.erb"))
    erb localized.to_sym
  else
    erb "partials/#{partial}".to_sym
  end
end

get '/namegen/:gender' do
  if params['gender'] == 'female'
    ['Ada', 'Belle', 'Carmen', 'Desdemona', 'Edie'].sample
  elsif params['gender'] == 'male'
    ['Agamemnon', 'Beren', 'Cadwalader', 'Dro', 'Edgar'].sample
  end
end

get '/skills' do
  json DATA[:skills]
end

get '/traits' do
  json DATA[:traits]
end

get '/lifepaths/:stock' do
  if DATA[:stocks].include? params['stock']
    json DATA[:lifepaths][params['stock']]
  else
    404
  end
end

get '/starting_stat_pts/:stock' do
  if DATA[:stocks].include? params['stock']
    json DATA[:stat_pts][params['stock']]
  else
    404
  end
end

get '/resources/:stock' do
  if DATA[:stocks].include? params['stock']
    json DATA[:resources][params['stock']]
  else
    404
  end
end

# 导出角色卡：format=htm（网页，可直接打印）或 format=docx（Word）
EXPORT_FORMATS = {
  'htm'  => 'text/html; charset=utf-8',
  'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
}.freeze

# 新前端调用 /charsheet/htm 或 /charsheet/docx；保留 /charsheet?format=… 以兼容旧页面
post %r{/charsheet(?:/(htm|docx))?} do
  requested = params['captures'] && params['captures'].first
  requested ||= params['format']
  format = EXPORT_FORMATS.key?(requested) ? requested : 'htm'
  request.body.rewind
  raw = request.body.readpartial(16 * 1024)
  data = JSON.parse(raw)
  key = "char-#{Time.now.strftime('%Y%m%d%H%M%S%L')}-#{rand(1...10000)}"
  CACHE.store key, data

  download_url(key, "#{data['name']} #{t('Character Sheet')}.#{format}")
end

post '/upload_charfile' do
  data = params['charfile']['tempfile'].read
  erb '<html><body><pre><%= char %></pre></body></html>', :locals => {:char => data}
end

post '/download_charfile' do
  request.body.rewind  # in case someone already read it
  raw = request.body.readpartial(16 * 1024)
  data = JSON.parse(raw)
  key = "char-#{Time.now.strftime('%Y%m%d%H%M%S%L')}-#{rand(1...10000)}"
  CACHE.store key, data

  download_url(key, "#{data['name']} #{t('Character Sheet')}.char")
end

get '/get_file' do
  name = params['download_name'].to_s
  ext = File.extname(name).delete('.')
  data = CACHE.delete(params['file'])
  halt 404, t('This download link has expired. Please export again.') if data.nil?

  if EXPORT_FORMATS.key?(ext)
    content_type EXPORT_FORMATS[ext]
    sheet = SheetExport.new(data, I18N, DATA)
    body_data = ext == 'docx' ? sheet.to_docx : sheet.to_html
  else
    content_type 'application/octet-stream'
    body_data = JSON.dump(data)
  end
  attachment_utf8 name
  body_data
end
