# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class IssuesControllerTest < Redmine::ControllerTest
  fixtures :projects,
           :users,
           :roles,
           :members,
           :member_roles,
           :issues,
           :issue_statuses,
           :versions,
           :trackers,
           :projects_trackers,
           :issue_categories,
           :enabled_modules,
           :enumerations,
           :attachments,
           :workflows,
           :custom_fields,
           :custom_values,
           :custom_fields_projects,
           :custom_fields_trackers,
           :time_entries,
           :journals,
           :journal_details,
           :queries

  def test_renders_issue_merge_requests
    merge_request = create_merge_request

    show_issue(user_with_permission)

    assert_select "#history > #issue-merge-requests:first-child #merge-request-#{merge_request.id}"
    assert_select 'div.issue #issue-merge-requests', count: 0
  end

  def test_does_not_link_merge_request_url_without_web_scheme
    merge_request = create_merge_request(url: 'javascript:alert(1)')

    show_issue(user_with_permission)

    assert_select "#merge-request-#{merge_request.id}", text: /Some merge request/
    assert_select 'a[href^="javascript"]', count: 0
  end

  def test_requires_merge_request_links_module_to_be_enabled
    issue.project.enabled_module_names -= ['merge_request_links']
    merge_request = create_merge_request

    show_issue(user_with_permission)

    assert_select "#merge-request-#{merge_request.id}", count: 0
  end

  def test_requires_permission
    merge_request = create_merge_request

    show_issue(user_without_permission)

    assert_select "#merge-request-#{merge_request.id}", count: 0
  end

  def test_merge_request_filter_any
    create_merge_request

    list_issues(user_with_permission, operator: '*')

    assert_equal [issue], issues_in_list
  end

  def test_merge_request_filter_none
    create_merge_request

    list_issues(user_with_permission, operator: '!*')

    assert_not_includes issues_in_list, issue
  end

  def test_merge_request_filter_open
    create_merge_request

    list_issues(user_with_permission, operator: '=', values: ['open'])

    assert_equal [issue], issues_in_list
  end

  def test_merge_request_filter_merged
    create_merge_request

    list_issues(user_with_permission, operator: '=', values: ['merged'])

    assert_not_includes issues_in_list, issue
  end

  def test_merge_request_filter_not_merged
    create_merge_request

    list_issues(user_with_permission, operator: '!', values: ['merged'])

    assert_equal [issue], issues_in_list
  end

  def test_merge_requests_column
    create_merge_request(display_id: 'mr_id')

    list_issues(user_with_permission, operator: '*', columns: ['merge_requests'])

    assert_includes columns_in_issues_list, 'Merge requests'
    assert_match 'mr_id', css_select('td.merge_requests').first.text
  end

  def test_merge_request_filter_no_permission
    create_merge_request

    list_issues(user_without_permission, operator: '*')

    assert issues_in_list.length > 1
  end

  def test_merge_requests_column_no_permission
    sign_in(user_without_permission)
    get(:index, params: { project_id: issue.project_id, c: ['merge_requests'] })

    assert_response :success
    assert_not_includes columns_in_issues_list, 'Merge requests'
  end

  private

  def create_merge_request(**attributes)
    MergeRequest.create!(title: 'Some merge request', state: 'open', **attributes).tap do |merge_request|
      merge_request.issues << issue
    end
  end

  def show_issue(user)
    sign_in(user)
    get(:show, params: { id: issue.id })
    assert_response :success
  end

  def list_issues(user, operator:, values: nil, columns: nil)
    sign_in(user)
    get(:index,
        params: {
          project_id: issue.project_id,
          set_filter: 1,
          f: ['merge_request'],
          op: { 'merge_request' => operator },
          v: values && { 'merge_request' => values },
          c: columns
        }.compact)
    assert_response :success
  end

  def sign_in(user)
    @request.session[:user_id] = user.id
  end

  def user_with_permission
    user_without_permission.tap do |user|
      member = Member.where(user: user, project_id: issue.project_id).first

      role = member.roles.first
      role.permissions << :view_associated_merge_requests
      role.save!
    end
  end

  def user_without_permission
    User.find(3)
  end

  def issue
    @issue ||= Issue.find(1).tap do |issue|
      issue.project.enabled_module_names += ['merge_request_links']
    end
  end
end
