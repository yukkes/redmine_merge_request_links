# frozen_string_literal: true

module RedmineMergeRequestLinks
  module Patches
    module IssueQueryPatch
      def initialize_available_filters
        super
        return unless User.current.allowed_to?(:view_associated_merge_requests, project, global: true)

        add_available_filter('merge_request',
                             type: :list_optional, values: %w[open merged closed])
      end

      def available_columns
        return @available_columns if @available_columns

        @available_columns = super
        if User.current.allowed_to?(:view_associated_merge_requests, project, global: true)
          @available_columns << QueryColumn.new(:merge_requests)
        end
        @available_columns
      end

      def issues(options = {})
        (options[:include] ||= []) << :merge_requests if has_column?(:merge_requests)
        super
      end

      def sql_for_merge_request_field(_field, operator, value, _options = {})
        join_table = Issue.reflections['merge_requests'].join_table
        condition =
          case operator
          when '*', '!*'
            "#{operator == '*' ? 'EXISTS' : 'NOT EXISTS'} (" \
            "SELECT 1 FROM #{join_table} " \
            "WHERE #{join_table}.issue_id = #{Issue.table_name}.id)"
          when '=', '!'
            states = value.map { |state| self.class.connection.quote(state) }.join(',')
            "EXISTS (SELECT 1 FROM #{join_table} " \
              "JOIN #{MergeRequest.table_name} ON #{MergeRequest.table_name}.id = #{join_table}.merge_request_id " \
              "WHERE #{join_table}.issue_id = #{Issue.table_name}.id " \
              "AND #{MergeRequest.table_name}.state #{operator == '=' ? 'IN' : 'NOT IN'} (#{states}))"
          end
        return unless condition

        "#{condition} AND #{Project.allowed_to_condition(User.current, :view_associated_merge_requests)}"
      end
    end
  end
end

unless IssueQuery.included_modules.include?(RedmineMergeRequestLinks::Patches::IssueQueryPatch)
  IssueQuery.prepend(RedmineMergeRequestLinks::Patches::IssueQueryPatch)
end
