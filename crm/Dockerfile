# Override with: docker build --build-arg RUBY_IMAGE=ruby:3.2.3-alpine .
ARG RUBY_IMAGE=ruby:3.2-alpine
FROM ${RUBY_IMAGE} AS builder

RUN apk add --no-cache build-base mariadb-dev yaml-dev

WORKDIR /app

COPY Gemfile* ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install -j4

COPY . .
RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile 2>/dev/null || \
    echo "Skipping assets (none configured)"

# Production image
FROM ${RUBY_IMAGE}

RUN apk add --no-cache mariadb-client tzdata yaml

WORKDIR /app

COPY --from=builder /app /app

ENV BUNDLE_PATH=/app/vendor/bundle
ENV RAILS_ENV=production
ENV RAILS_SERVE_STATIC_FILES=true
EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
