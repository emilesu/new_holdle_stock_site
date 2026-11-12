class EmailVerification < ApplicationRecord
  PURPOSES = %w[bind_email set_password reset_password].freeze

  validates :email, :purpose, :code_digest, :expires_at, presence: true
  validates :purpose, inclusion: { in: PURPOSES }

  scope :active, -> { where("expires_at > ?", Time.current) }

  def active?
    expires_at > Time.current
  end
end
