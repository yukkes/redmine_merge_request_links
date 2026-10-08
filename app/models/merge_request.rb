# frozen_string_literal: true

class MergeRequest < ActiveRecord::Base
  ISSUE_ID_REGEXP = /(?:[^a-z]|\A)(?:#|REDMINE-)(\d+)/.freeze
  WEB_URL_SCHEMES = %w[http https].freeze

  has_and_belongs_to_many :issues

  attr_accessor :description

  # Gitlab does not pass the author name, only the name of the user
  # performing the current action. Since (except for merge requests
  # that were created before the plugin was installed) the user
  # triggering the first webhook event is the author, we want to
  # update the author name only once.
  attr_readonly :author_name

  after_save :scan_description_for_issue_ids

  def self.find_all_by_issue(issue)
    joins(:issues).where(issues: { id: issue.id })
  end

  # URL to link to, or nil if the URL received via webhook does not
  # use a web scheme (e.g. `javascript:`).
  def web_url
    url if WEB_URL_SCHEMES.include?(URI.parse(url.to_s).scheme&.downcase)
  rescue URI::InvalidURIError
    nil
  end

  private

  def scan_description_for_issue_ids
    self.issues = Issue.where(id: mentioned_issue_ids).to_a
  end

  def mentioned_issue_ids
    [description, title].flat_map do |value|
      (value || '').scan(ISSUE_ID_REGEXP).flatten
    end.uniq
  end
end
