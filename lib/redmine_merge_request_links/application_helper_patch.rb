# frozen_string_literal: true

module RedmineMergeRequestLinks
  # Renders the merge request box between issue details and history.
  # Redmine has no view hook there, but the history consists of the
  # tabs rendered by this method only.
  module ApplicationHelperPatch
    def render_tabs(tabs, selected = params[:tab])
      return super unless controller_name == 'issues' && action_name == 'show'

      render(partial: 'merge_request_links/box') + super
    end
  end
end
