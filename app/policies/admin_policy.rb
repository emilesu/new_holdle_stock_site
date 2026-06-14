class AdminPolicy < ApplicationPolicy
  def access?
    user&.is_admin?
  end

  def dashboard?
    user&.is_admin?
  end

  def manage_users?
    user&.is_admin?
  end

  def manage_stocks?
    user&.is_admin?
  end

  def manage_courses?
    user&.is_admin?
  end

  def manage_payments?
    user&.is_super_admin?
  end

  def system_settings?
    user&.is_super_admin?
  end

  def manage_crawlers?
    user&.is_admin?
  end

  class Scope < Scope
    def resolve
      scope.all if user&.is_admin?
    end
  end
end
