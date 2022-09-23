FROM ruby:2.4-alpine
WORKDIR /var/app
RUN apk update && apk add --no-cache build-base
RUN gem install bundler -v 2.1.4
ADD Gemfile* .

RUN bundle install

ENTRYPOINT ["/var/app/_create_blog.sh"]
