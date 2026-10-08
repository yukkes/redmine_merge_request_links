# frozen_string_literal: true

class MergeRequestsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required

  def event
    provider = RedmineMergeRequestLinks::Webhook.provider_for(request)
    return head :bad_request unless provider
    return head :forbidden unless provider.authentic?(request)

    attributes = provider.attributes(params)
    MergeRequest.find_or_initialize_by(url: attributes[:url]).update!(attributes)

    head :ok
  end
end
