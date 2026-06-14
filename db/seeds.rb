User.destroy_all

User.create!(
  email: "admin@example.com",
  password: "12345678",
  password_confirmation: "12345678",
  nickname: "超级管理员",
  role: "super_admin"
)