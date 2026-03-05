class Activity < ApplicationRecord
  belongs_to :activityable, polymorphic: true
  enum activity_type: { call: 0, meeting: 1, email: 2, task: 3 }
  enum status: { scheduled: 0, completed: 1, cancelled: 2 }
  validates :subject, presence: true
end
