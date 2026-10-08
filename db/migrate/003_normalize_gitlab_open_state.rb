class NormalizeGitlabOpenState < Rails.version < '5.1' ? ActiveRecord::Migration : ActiveRecord::Migration[4.2]
  def up
    execute("UPDATE merge_requests SET state = 'open' WHERE state IN ('opened', 'locked')")
  end

  def down
    execute("UPDATE merge_requests SET state = 'opened' WHERE state = 'open' AND provider = 'gitlab'")
  end
end
