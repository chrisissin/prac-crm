# Seeds for CRM
user = User.find_or_create_by!(email: "admin@crm.local") do |u|
  u.password = "changeme"
  u.name = "Admin"
end
user.update!(password: "changeme", name: "Admin")  # Fix password if user pre-existed
