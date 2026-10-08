# frozen_string_literal: true

module RedmineMergeRequestLinks
  module EventHandlers
    # Gitea sends pull request payloads in the same format as GitHub,
    # but uses its own headers and a SHA256 signature.
    class Gitea < Github
      private

      def provider
        'gitea'
      end

      def event_header
        'X-Gitea-Event'
      end

      def signature_header
        'X-Gitea-Signature'
      end

      def expected_signature(payload)
        OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), @token, payload)
      end
    end
  end
end
