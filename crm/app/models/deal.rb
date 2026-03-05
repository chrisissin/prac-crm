class Deal < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :contact, optional: true
  has_many :activities, as: :activityable, dependent: :destroy
  enum stage: { qualification: 0, proposal: 1, negotiation: 2, closed_won: 3, closed_lost: 4 }
  validates :name, presence: true
  validates :value, numericality: { greater_than_or_equal_to: 0 }
end
