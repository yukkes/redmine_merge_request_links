# frozen_string_literal: true

module RedmineMergeRequestLinks
  module EventHandlers
    class Github
      def initialize(token:)
        @token = token
      end

      def matches?(request)
        request.headers[event_header] == 'pull_request'
      end

      def verify(request)
        signature = request.headers[signature_header]
        return false if @token.blank? || signature.blank?

        Rack::Utils.secure_compare(expected_signature(request.raw_post), signature)
      end

      def parse_params(params)
        params
          .require(:pull_request)
          .permit(:state, :merged, :html_url, :title, :body, :number,
                  user: :login,
                  base: { repo: :full_name }).tap do |attributes|
          merged = attributes.delete(:merged)
          user = attributes.delete(:user) || {}
          repo = (attributes.delete(:base) || {}).fetch(:repo, {})

          attributes[:state] = 'merged' if attributes[:state] == 'closed' && merged
          attributes[:provider] = provider
          attributes[:url] = attributes.delete(:html_url)
          attributes[:description] = attributes.delete(:body)
          attributes[:author_name] = "@#{user[:login]}"
          attributes[:display_id] = "#{repo[:full_name]}##{attributes.delete(:number)}"
        end
      end

      private

      def provider
        'github'
      end

      def event_header
        'X-GitHub-Event'
      end

      def signature_header
        'X-Hub-Signature'
      end

      def expected_signature(payload)
        "sha1=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), @token, payload)}"
      end
    end
  end
end
