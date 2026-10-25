# Build stage: compile native gem extensions (thin -> eventmachine).
FROM ruby:3.3-bookworm AS build

ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=test

WORKDIR /app

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libssl-dev && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf /usr/local/bundle/cache

# Runtime stage.
FROM ruby:3.3-slim-bookworm

ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=test \
    RACK_ENV=production \
    PORT=8080

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock ./
COPY app.rb ablegrade.rb als_converter.rb ./
COPY public ./public
COPY views ./views

RUN useradd --create-home --uid 1000 app && chown -R app:app /app
USER app

EXPOSE 8080

CMD ["bundle", "exec", "ruby", "./app.rb"]
