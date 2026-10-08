ARG REDMINE_VERSION=3.4
FROM redmine:${REDMINE_VERSION}
ARG PATCH_VERSION=3.4

COPY patches/view_hook_issues_show_after_details_redmine_${PATCH_VERSION}.patch \
     /view_hook_issues_show_after_details.patch

RUN git apply /view_hook_issues_show_after_details.patch

# Official images exclude the test group via bundler config. `bundle
# install --with` has been removed in Bundler 4, so override the
# setting instead. A temporary database.yml makes Bundler resolve the
# sqlite3 adapter used by bin/test, so that the entrypoint does not
# need to re-resolve dependencies as the unprivileged redmine user.
# Images based on EOL Debian releases (Redmine 3.4, 4.0) need to fetch
# packages from archive.debian.org.
RUN ((apt-get update && apt-get install -y build-essential) \
     || (sed -i -e 's#http://deb.debian.org#http://archive.debian.org#g' \
                -e 's#http://security.debian.org#http://archive.debian.org#g' \
                -e '/-updates/d' /etc/apt/sources.list \
         && apt-get update \
         && apt-get install -y build-essential)) \
    && bundle config --local without development \
    && printf 'test:\n  adapter: sqlite3\n  database: sqlite/redmine.db\n' > config/database.yml \
    && bundle install \
    && rm config/database.yml \
    && rm -rf /home/redmine/.bundle \
    && chown redmine:redmine Gemfile.lock
