ARG REDMINE_VERSION=7.0
FROM redmine:${REDMINE_VERSION}

# Official images exclude the test group via bundler config. `bundle
# install --with` has been removed in Bundler 4, so override the
# setting instead. A temporary database.yml makes Bundler resolve the
# sqlite3 adapter used by bin/test, so that the entrypoint does not
# need to re-resolve dependencies as the unprivileged redmine user.
RUN apt-get update \
    && apt-get install -y build-essential \
    && bundle config --local without development \
    && printf 'test:\n  adapter: sqlite3\n  database: sqlite/redmine.db\n' > config/database.yml \
    && bundle install \
    && rm config/database.yml \
    && rm -rf /home/redmine/.bundle \
    && chown redmine:redmine Gemfile.lock
