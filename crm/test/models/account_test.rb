require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "validates name presence" do
    a = Account.new
    assert_not a.valid?
  end
end
