class AllowSystemCreatedInternalTasks < ActiveRecord::Migration[7.1]
  def change
    change_column_null :internal_tasks, :created_by_id, true
  end
end
