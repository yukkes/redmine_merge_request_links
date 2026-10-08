# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MergeRequestTest < ActiveSupport::TestCase
  fixtures :issues

  def test_updates_issues_from_description
    assert_equal [issue], linked_issues(description: "see ##{issue.id}")
  end

  def test_updates_issues_from_title
    assert_equal [issue], linked_issues(title: "MR for ##{issue.id}")
  end

  def test_creates_one_association_even_if_mentioned_multiple_times
    assert_equal [issue], linked_issues(title: "MR for ##{issue.id}",
                                        description: "Mentions ##{issue.id} and again ##{issue.id}")
  end

  def test_removes_no_longer_mentioned_issues_on_update
    merge_request = MergeRequest.create!
    merge_request.issues << issue

    merge_request.update!(description: 'Nothing mentioned')

    assert_empty merge_request.issues
  end

  def test_ignores_issue_ids_with_project_prefix
    assert_empty linked_issues(description: "some/project##{issue.id}")
  end

  def test_ignores_issue_ids_without_hash
    assert_empty linked_issues(description: "see #{issue.id}")
  end

  def test_issue_id_can_be_wrapped_in_braces
    assert_equal [issue], linked_issues(description: "(##{issue.id})")
  end

  def test_supports_issue_id_with_redmine_prefix
    assert_equal [issue], linked_issues(description: "see REDMINE-#{issue.id}")
  end

  def test_issue_id_can_be_at_beginning_of_description
    assert_equal [issue], linked_issues(description: "##{issue.id}")
  end

  def test_issue_has_merge_requests
    merge_request = MergeRequest.create!(title: "MR for ##{issue.id}")
    MergeRequest.create!

    assert_equal [merge_request], issue.merge_requests.to_a
  end

  def test_web_url_returns_http_and_https_urls
    assert_equal('https://github.com/a/b/pull/1',
                 MergeRequest.new(url: 'https://github.com/a/b/pull/1').web_url)
    assert_equal('http://gitlab.example.com/a/b/-/merge_requests/1',
                 MergeRequest.new(url: 'http://gitlab.example.com/a/b/-/merge_requests/1').web_url)
  end

  def test_web_url_ignores_other_schemes_and_invalid_urls
    assert_nil(MergeRequest.new(url: 'javascript:alert(1)').web_url)
    assert_nil(MergeRequest.new(url: 'JavaScript:alert(1)').web_url)
    assert_nil(MergeRequest.new(url: 'http://exa mple.com').web_url)
    assert_nil(MergeRequest.new(url: nil).web_url)
  end

  private

  def issue
    Issue.last
  end

  def linked_issues(**attributes)
    merge_request = MergeRequest.create!
    merge_request.update!(**attributes)
    merge_request.issues.to_a
  end
end
