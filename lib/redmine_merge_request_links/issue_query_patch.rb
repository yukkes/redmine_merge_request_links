# frozen_string_literal: true

module RedmineMergeRequestLinks
  # Adds the "Merge request" filter and the "Merge requests" column to
  # the issue list.
  module IssueQueryPatch
    def initialize_available_filters
      super
      return unless merge_requests_visible?

      add_available_filter('merge_request', type: :list_optional, values: %w[open merged closed])
    end

    def available_columns
      return @available_columns if @available_columns

      super.tap do |columns|
        columns << QueryColumn.new(:merge_requests) if merge_requests_visible?
      end
    end

    def issues(options = {})
      (options[:include] ||= []) << :merge_requests if has_column?(:merge_requests)
      super
    end

    def sql_for_merge_request_field(_field, operator, value)
      linked_issues = Issue.joins(:merge_requests)
      linked_issues = linked_issues.where(merge_requests: { state: value }) if operator == '='
      linked_issues = linked_issues.where.not(merge_requests: { state: value }) if operator == '!'

      "#{Issue.table_name}.id #{'NOT ' if operator == '!*'}IN (#{linked_issues.select(:id).to_sql}) AND " \
        "#{Project.allowed_to_condition(User.current, :view_associated_merge_requests)}"
    end

    private

    def merge_requests_visible?
      User.current.allowed_to?(:view_associated_merge_requests, project, global: true)
    end
  end
end
