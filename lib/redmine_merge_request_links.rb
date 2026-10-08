# frozen_string_literal: true

# Classes in lib/ are autoloaded by Redmine's plugin loader.
module RedmineMergeRequestLinks
  def self.setup
    Issue.has_and_belongs_to_many :merge_requests
    IssueQuery.prepend(IssueQueryPatch)
    QueriesHelper.prepend(QueriesHelperPatch)
    ApplicationHelper.prepend(ApplicationHelperPatch)
    # View listeners register themselves once they are loaded.
    Hooks
  end
end
