# frozen_string_literal: true

class CreateMergeRequests < ActiveRecord::Migration[4.2]
  def change
    create_table :merge_requests do |t|
      t.string :provider
      t.string :title
      t.string :url
      t.string :state
      t.string :author_name
      t.string :display_id
    end
  end
end
