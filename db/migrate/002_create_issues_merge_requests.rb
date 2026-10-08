# frozen_string_literal: true

class CreateIssuesMergeRequests < ActiveRecord::Migration[4.2]
  def change
    create_join_table :issues, :merge_requests do |t|
      t.index :issue_id
    end
  end
end
