class CreateContacts < ActiveRecord::Migration[7.0]
  def change
    create_table :contacts do |t|
      t.references :account, foreign_key: true
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :title
      t.string :email, null: false
      t.string :phone

      t.timestamps
    end
  end
end
