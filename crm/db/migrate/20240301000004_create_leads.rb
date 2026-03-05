class CreateLeads < ActiveRecord::Migration[7.0]
  def change
    create_table :leads do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.string :company
      t.string :phone
      t.integer :status, default: 0
      t.integer :source, default: 0
      t.text :notes

      t.timestamps
    end
  end
end
