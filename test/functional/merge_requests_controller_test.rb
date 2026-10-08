# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MergeRequestsControllerTest < Redmine::ControllerTest
  TOKEN = 'secret'
  PROVIDERS = %w[github gitlab gitea].freeze
  GITLAB_URL = 'https://gitlab.example.com/project/merge_requests/1'
  GITHUB_URL = 'https://github.com/Codertocat/Hello-World/pull/1'
  GITEA_URL = 'https://gitea.com/Codertocat/Hello-World/pull/1'

  fixtures :issues

  def setup
    @env = PROVIDERS.map { |provider| [token_variable(provider), ENV.fetch(token_variable(provider), nil)] }
    PROVIDERS.each { |provider| ENV[token_variable(provider)] = TOKEN }
  end

  def teardown
    @env.each { |name, value| ENV[name] = value }
  end

  def test_gitlab_merge_request_event_creates_merge_request
    post_gitlab(gitlab_payload)

    assert_response :success
    merge_request = MergeRequest.find_by(url: GITLAB_URL)
    assert_equal 'open', merge_request.state
    assert_equal 'Some merge request', merge_request.title
    assert_equal 'group/project!23', merge_request.display_id
    assert_equal '@john', merge_request.author_name
    assert_equal 'gitlab', merge_request.provider
  end

  def test_maps_locked_gitlab_merge_request_to_open
    post_gitlab(gitlab_payload(state: 'locked'))

    assert_response :success
    assert_equal 'open', MergeRequest.find_by(url: GITLAB_URL).state
  end

  def test_gitlab_merge_request_event_updates_merge_request
    merge_request = MergeRequest.create!(url: GITLAB_URL, title: 'Old title', state: 'open')

    post_gitlab(gitlab_payload(title: 'New title', state: 'merged'))

    assert_response :success
    merge_request.reload
    assert_equal 'merged', merge_request.state
    assert_equal 'New title', merge_request.title
  end

  def test_does_not_update_author_field
    merge_request = MergeRequest.create!(url: GITLAB_URL, title: 'Title', state: 'open', author_name: '@jack')

    post_gitlab(gitlab_payload(state: 'merged'))

    assert_response :success
    assert_equal '@jack', merge_request.reload.author_name
  end

  def test_gitlab_system_hooks
    post_gitlab(gitlab_payload.merge(event_type: 'merge_request'), event: 'System Hook')

    assert_response :success
    merge_request = MergeRequest.find_by(url: GITLAB_URL)
    assert_equal 'open', merge_request.state
    assert_equal 'group/project!23', merge_request.display_id
    assert_equal '@john', merge_request.author_name
  end

  def test_ignores_gitlab_system_hooks_for_other_events
    post_gitlab(gitlab_payload.merge(event_type: 'push'), event: 'System Hook')

    assert_response :bad_request
  end

  def test_responds_with_forbidden_if_gitlab_token_does_not_match
    post_gitlab(gitlab_payload, token: 'wrong')

    assert_response :forbidden
    assert_nil MergeRequest.find_by(url: GITLAB_URL)
  end

  def test_github_pull_request_event_creates_merge_request
    post_github(pull_request_payload(GITHUB_URL))

    assert_response :success
    merge_request = MergeRequest.find_by(url: GITHUB_URL)
    assert_equal 'closed', merge_request.state
    assert_equal 'Some pull request', merge_request.title
    assert_equal 'group/project#12', merge_request.display_id
    assert_equal '@someuser', merge_request.author_name
    assert_equal 'github', merge_request.provider
  end

  def test_sets_state_to_merged_if_github_pr_is_closed_and_merged
    post_github(pull_request_payload(GITHUB_URL, merged: true))

    assert_response :success
    assert_equal 'merged', MergeRequest.find_by(url: GITHUB_URL).state
  end

  def test_gitea_pull_request_event_creates_merge_request
    post_gitea(pull_request_payload(GITEA_URL))

    assert_response :success
    merge_request = MergeRequest.find_by(url: GITEA_URL)
    assert_equal 'closed', merge_request.state
    assert_equal 'Some pull request', merge_request.title
    assert_equal 'group/project#12', merge_request.display_id
    assert_equal '@someuser', merge_request.author_name
    assert_equal 'gitea', merge_request.provider
  end

  def test_sets_state_to_merged_if_gitea_pr_is_closed_and_merged
    post_gitea(pull_request_payload(GITEA_URL, merged: true))

    assert_response :success
    assert_equal 'merged', MergeRequest.find_by(url: GITEA_URL).state
  end

  def test_associates_issues_mentioned_in_gitlab_mr_title
    post_gitlab(gitlab_payload(title: "Some title (##{issue.id})"))

    assert_includes MergeRequest.find_by(url: GITLAB_URL).issues, issue
  end

  def test_associates_issues_mentioned_in_gitlab_mr_description
    post_gitlab(gitlab_payload(description: "Talks about ##{issue.id}"))

    assert_includes MergeRequest.find_by(url: GITLAB_URL).issues, issue
  end

  def test_associates_issues_mentioned_in_github_pr_title
    post_github(pull_request_payload(GITHUB_URL, title: "Some title (##{issue.id})"))

    assert_includes MergeRequest.find_by(url: GITHUB_URL).issues, issue
  end

  def test_associates_issues_mentioned_in_github_pr_body
    post_github(pull_request_payload(GITHUB_URL, description: "Talks about ##{issue.id}"))

    assert_includes MergeRequest.find_by(url: GITHUB_URL).issues, issue
  end

  def test_associates_issues_mentioned_in_gitea_pr_title
    post_gitea(pull_request_payload(GITEA_URL, title: "Some title (##{issue.id})"))

    assert_includes MergeRequest.find_by(url: GITEA_URL).issues, issue
  end

  def test_associates_issues_mentioned_in_gitea_pr_body
    post_gitea(pull_request_payload(GITEA_URL, description: "Talks about ##{issue.id}"))

    assert_includes MergeRequest.find_by(url: GITEA_URL).issues, issue
  end

  def test_responds_with_bad_request_if_unknown_event
    post(:event)

    assert_response :bad_request
  end

  def test_responds_with_forbidden_if_github_signature_is_incorrect
    post_github(pull_request_payload(GITHUB_URL), signature: 'wrong')

    assert_response :forbidden
  end

  def test_responds_with_forbidden_if_gitea_signature_is_incorrect
    post_gitea(pull_request_payload(GITEA_URL), signature: 'wrong')

    assert_response :forbidden
  end

  def test_responds_with_forbidden_if_github_signature_is_missing
    post_github(pull_request_payload(GITHUB_URL), signature: nil)

    assert_response :forbidden
  end

  def test_responds_with_forbidden_if_gitea_signature_is_missing
    post_gitea(pull_request_payload(GITEA_URL), signature: nil)

    assert_response :forbidden
  end

  def test_responds_with_forbidden_if_gitlab_token_is_missing
    post_gitlab(gitlab_payload, token: nil)

    assert_response :forbidden
  end

  def test_responds_with_forbidden_if_github_token_is_not_configured
    ENV.delete(token_variable('github'))
    post_github(pull_request_payload(GITHUB_URL))

    assert_response :forbidden
  end

  def test_responds_with_forbidden_if_gitea_token_is_not_configured
    ENV.delete(token_variable('gitea'))
    post_gitea(pull_request_payload(GITEA_URL))

    assert_response :forbidden
  end

  def test_responds_with_forbidden_if_gitlab_token_is_not_configured
    ENV.delete(token_variable('gitlab'))
    post_gitlab(gitlab_payload)

    assert_response :forbidden
    assert_nil MergeRequest.find_by(url: GITLAB_URL)
  end

  private

  def issue
    Issue.last
  end

  def token_variable(provider)
    "REDMINE_MERGE_REQUEST_LINKS_#{provider.upcase}_WEBHOOK_TOKEN"
  end

  def gitlab_payload(title: 'Some merge request', description: nil, state: 'opened')
    {
      user: { username: 'john' },
      object_attributes: {
        url: GITLAB_URL,
        title: title,
        description: description,
        state: state,
        iid: 23,
        target: { path_with_namespace: 'group/project' }
      }.compact
    }
  end

  def pull_request_payload(url, title: 'Some pull request', description: nil, merged: nil)
    {
      pull_request: {
        html_url: url,
        title: title,
        body: description,
        state: 'closed',
        merged: merged,
        number: 12,
        user: { login: 'someuser' },
        base: { repo: { full_name: 'group/project' } }
      }.compact
    }
  end

  def post_gitlab(payload, event: 'Merge Request Hook', token: TOKEN)
    post_event(payload, 'X-Gitlab-Event' => event, 'X-Gitlab-Token' => token)
  end

  def post_github(payload, signature: hmac('sha1', payload, prefix: 'sha1='))
    post_event(payload, 'X-GitHub-Event' => 'pull_request', 'X-Hub-Signature' => signature)
  end

  # Gitea sends GitHub and Gogs headers as well.
  def post_gitea(payload, signature: hmac('sha256', payload))
    post_event(payload,
               'X-Gitea-Event' => 'pull_request',
               'X-GitHub-Event' => 'pull_request',
               'X-Gogs-Event' => 'pull_request',
               'X-Gitea-Signature' => signature,
               'X-Gogs-Signature' => signature)
  end

  def post_event(payload, headers)
    headers.compact.each { |name, value| request.headers[name] = value }
    post(:event, params: payload)
  end

  def hmac(digest, payload, prefix: '')
    prefix + OpenSSL::HMAC.hexdigest(digest, TOKEN, payload.to_query)
  end
end
