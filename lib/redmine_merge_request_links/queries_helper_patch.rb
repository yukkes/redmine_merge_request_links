# frozen_string_literal: true

module RedmineMergeRequestLinks
  # Renders the "Merge requests" column of the issue list.
  module QueriesHelperPatch
    def column_value(column, item, value)
      return super unless column.name == :merge_requests
      return '' unless User.current.allowed_to?(:view_associated_merge_requests, item.project)

      render partial: 'merge_request_links/column', locals: { merge_requests: value }
    end
  end
end
