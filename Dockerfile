# Charred Black 中文版
# 构建：docker build -t charred-black-zh .
# 运行：docker run -d --name charred -p 7878:7878 --restart unless-stopped charred-black-zh
FROM ruby:2.6.10

ENV HOST=0.0.0.0 \
    PORT=7878 \
    RACK_ENV=production \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CHARRED_LOCALE=zh-CN

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1 && bundle config --global without development

WORKDIR /app

# to generate Gemfile.lock, run this in service dir:
# $ docker run --rm -v "$PWD":/app -w /app ruby:2.6.10 bundle install
COPY Gemfile Gemfile.lock /app/
RUN bundle install

COPY . /app

WORKDIR /app/src

EXPOSE 7878

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:7878/i18n.js")).is_a?(Net::HTTPSuccess) ? 0 : 1)'

CMD ["ruby", "./app.rb"]
