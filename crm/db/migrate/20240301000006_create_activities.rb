class CreateActivities < ActiveRecord::Migration[7.0]
  def change
    create_table :activities do |t|
      t.string :activityable_type, null: false
      t.bigint :activityable_id, null: false
      t.integer :activity_type, null: false
      t.string :subject, null: false
      t.text :description
      t.datetime :due_at
      t.integer :status, default: 0

      t.timestamps
    end
  end
end
