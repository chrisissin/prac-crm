class Lead < ApplicationRecord
  enum status: { new_lead: 0, contacted: 1, qualified: 2, converted: 3, lost: 4 }
  enum source: { website: 0, referral: 1, cold_call: 2, event: 3, other: 4 }
  validates :first_name, :last_name, :email, presence: true
  def full_name
    "#{first_name} #{last_name}"
  end
end
