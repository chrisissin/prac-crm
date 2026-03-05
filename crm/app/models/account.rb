class Account < ApplicationRecord
  has_many :contacts, dependent: :destroy
  has_many :deals, dependent: :nullify
  enum status: { prospect: 0, active: 1, inactive: 2 }
  validates :name, presence: true
end
