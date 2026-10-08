# frozen_string_literal: true

Redmine::Plugin.register :redmine_merge_request_links do
  name 'Redmine Merge Request Links'
  author 'Tim Fischbach, yukkes'
  description 'Display links to merge requests and pull requests from GitLab, GitHub, Gitea and AWS CodeCommit'
  version '2.2.0'
  url 'https://github.com/yukkes/redmine_merge_request_links'
  author_url 'https://github.com/yukkes'

  requires_redmine version_or_higher: '5.0'

  project_module :merge_request_links do
    permission :view_associated_merge_requests, {}
  end
end

RedmineMergeRequestLinks.setup
