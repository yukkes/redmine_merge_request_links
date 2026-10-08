# frozen_string_literal: true

module RedmineMergeRequestLinks
  module EventHandlers
    class Gitlab
      def initialize(token:)
        @token = token
      end

      def matches?(request)
        request.headers['X-Gitlab-Event'] == 'Merge Request Hook' ||
          (request.headers['X-Gitlab-Event'] == 'System Hook' &&
           request.request_parameters['event_type'] == 'merge_request')
      end

      def verify(request)
        token = request.headers['X-Gitlab-Token']
        return false if @token.blank? || token.blank?

        Rack::Utils.secure_compare(@token, token)
      end

      def parse_params(params)
        params
          .require(:object_attributes)
          .permit(:state, :url, :title, :description, :iid,
                  user: :name, target: :path_with_namespace)
          .tap do |attributes|
            target = attributes.delete(:target) || {}

            # GitLab reports open merge requests as "opened" and uses the
            # short-lived "locked" state while merging. Map both to the
            # "open" state used by the other providers and the filter.
            attributes[:state] = 'open' if %w[opened locked].include?(attributes[:state])
            attributes[:provider] = 'gitlab'
            attributes[:display_id] =
              "#{target[:path_with_namespace]}!#{attributes.delete(:iid)}"
            attributes[:author_name] = "@#{params.require(:user).fetch(:username)}"
          end
      end
    end
  end
end
