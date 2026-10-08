# frozen_string_literal: true

module RedmineMergeRequestLinks
  # Merge request webhooks of the supported platforms. A provider knows
  # how to detect its events, how to authenticate them with the token
  # from `REDMINE_MERGE_REQUEST_LINKS_<NAME>_WEBHOOK_TOKEN` and how to
  # map the payload to MergeRequest attributes.
  module Webhook
    Provider = Struct.new(:name, :event, :signature_header, :sign, :parse, keyword_init: true) do
      def matches?(request)
        event.call(request)
      end

      def authentic?(request)
        token = ENV.fetch("REDMINE_MERGE_REQUEST_LINKS_#{name.upcase}_WEBHOOK_TOKEN", nil)
        signature = request.headers[signature_header]
        return false if token.blank? || signature.blank?

        Rack::Utils.secure_compare(sign.call(token, request.raw_post), signature)
      end

      def attributes(params)
        parse.call(params).merge(provider: name)
      end
    end

    # GitLab reports open merge requests as "opened" and uses the
    # short-lived "locked" state while merging. Both are stored as the
    # "open" state used by the other providers and the issue filter.
    GITLAB_STATES = { 'opened' => 'open', 'locked' => 'open' }.freeze

    # GitHub and Gitea send pull requests in the same format.
    def self.pull_request_attributes(params)
      pull_request = params.require(:pull_request)
                           .permit(:state, :merged, :html_url, :title, :body, :number,
                                   user: :login, base: { repo: :full_name })
      state = pull_request[:state]

      {
        url: pull_request[:html_url],
        title: pull_request[:title],
        description: pull_request[:body],
        state: state == 'closed' && pull_request[:merged] ? 'merged' : state,
        author_name: "@#{pull_request.dig(:user, :login)}",
        display_id: "#{pull_request.dig(:base, :repo, :full_name)}##{pull_request[:number]}"
      }
    end

    # GitLab only sends the user who triggered the event. See the
    # comment on MergeRequest#author_name.
    def self.merge_request_attributes(params)
      merge_request = params.require(:object_attributes)
                            .permit(:state, :url, :title, :description, :iid, target: :path_with_namespace)
      state = merge_request[:state]

      {
        url: merge_request[:url],
        title: merge_request[:title],
        description: merge_request[:description],
        state: GITLAB_STATES.fetch(state, state),
        author_name: "@#{params.require(:user).fetch(:username)}",
        display_id: "#{merge_request.dig(:target, :path_with_namespace)}!#{merge_request[:iid]}"
      }
    end

    PROVIDERS = [
      # Gitea also sends `X-GitHub-Event`, so it has to be detected first.
      Provider.new(
        name: 'gitea',
        event: ->(request) { request.headers['X-Gitea-Event'] == 'pull_request' },
        signature_header: 'X-Gitea-Signature',
        sign: ->(token, body) { OpenSSL::HMAC.hexdigest('SHA256', token, body) },
        parse: method(:pull_request_attributes)
      ),
      Provider.new(
        name: 'github',
        event: ->(request) { request.headers['X-GitHub-Event'] == 'pull_request' },
        signature_header: 'X-Hub-Signature',
        sign: ->(token, body) { "sha1=#{OpenSSL::HMAC.hexdigest('SHA1', token, body)}" },
        parse: method(:pull_request_attributes)
      ),
      Provider.new(
        name: 'gitlab',
        event: lambda do |request|
          case request.headers['X-Gitlab-Event']
          when 'Merge Request Hook' then true
          when 'System Hook' then request.request_parameters['event_type'] == 'merge_request'
          else false
          end
        end,
        signature_header: 'X-Gitlab-Token',
        sign: ->(token, _body) { token },
        parse: method(:merge_request_attributes)
      )
    ].freeze

    def self.provider_for(request)
      PROVIDERS.find { |provider| provider.matches?(request) }
    end
  end
end
