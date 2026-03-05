class CreateDeals < ActiveRecord::Migration[7.0]
  def change
    create_table :deals do |t|
      t.references :account, foreign_key: true
      t.references :contact, foreign_key: true
      t.string :name, null: false
      t.decimal :value, precision: 12, scale: 2, default: 0
      t.integer :stage, default: 0
      t.date :expected_close_date
      t.text :notes

      t.timestamps
    end
  end
end
