class Contact < ApplicationRecord
  belongs_to :account, optional: true
  has_many :deals, dependent: :nullify
  has_many :activities, as: :activityable, dependent: :destroy
  validates :first_name, :last_name, :email, presence: true
  def full_name
    "#{first_name} #{last_name}"
  end
end
