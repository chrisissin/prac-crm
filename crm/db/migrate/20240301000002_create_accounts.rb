class CreateAccounts < ActiveRecord::Migration[7.0]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :industry
      t.string :phone
      t.string :email
      t.text :address
      t.integer :status, default: 0

      t.timestamps
    end
  end
end
