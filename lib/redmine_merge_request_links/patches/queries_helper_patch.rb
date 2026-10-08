# frozen_string_literal: true

module RedmineMergeRequestLinks
  module Patches
    module QueriesHelperPatch
      def column_value(column, item, value)
        if column.name == :merge_requests
          if User.current.allowed_to?(:view_associated_merge_requests, item.project)
            render partial: 'merge_request_links/column', locals: { merge_requests: value }
          else
            ''
          end
        else
          super
        end
      end
    end
  end
end

unless QueriesHelper.included_modules.include?(RedmineMergeRequestLinks::Patches::QueriesHelperPatch)
  QueriesHelper.prepend(RedmineMergeRequestLinks::Patches::QueriesHelperPatch)
end
