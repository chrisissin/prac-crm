class DashboardController < ApplicationController
  before_action :require_login

  def index
    @accounts_count = Account.count
    @contacts_count = Contact.count
    @deals_count = Deal.count
    @leads_count = Lead.count
    @deals_value = Deal.sum(:value)
  end
end
