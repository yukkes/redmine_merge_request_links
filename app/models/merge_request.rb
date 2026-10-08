# frozen_string_literal: true

class MergeRequest < ActiveRecord::Base
  ISSUE_ID_REGEXP = /(?:[^a-z]|\A)(?:#|REDMINE-)(\d+)/.freeze
  WEB_URL_SCHEMES = %w[http https].freeze

  has_and_belongs_to_many :issues

  # Only used to find mentioned issues, not stored.
  attr_accessor :description

  # Gitlab does not pass the author name, only the name of the user
  # performing the current action. Since (except for merge requests
  # that were created before the plugin was installed) the user
  # triggering the first webhook event is the author, we want to
  # update the author name only once.
  attr_readonly :author_name

  after_save :link_mentioned_issues

  # URL to link to, or nil if the URL received via webhook does not
  # use a web scheme (e.g. `javascript:`).
  def web_url
    url if WEB_URL_SCHEMES.include?(URI.parse(url.to_s).scheme&.downcase)
  rescue URI::InvalidURIError
    nil
  end

  private

  def link_mentioned_issues
    issue_ids = [title, description].join("\n").scan(ISSUE_ID_REGEXP).flatten
    self.issues = Issue.where(id: issue_ids).to_a
  end
end
