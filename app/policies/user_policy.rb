class UserPolicy < ApplicationPolicy
  def show?
    user == record || user&.is_admin?
  end

  def edit?
    user == record || user&.is_admin?
  end

  def update?
    user == record || user&.is_admin?
  end

  def update_password?
    user == record
  end

  def favorites?
    user == record
  end

  def index?
    user&.is_admin?
  end

  def destroy?
    user&.is_super_admin? && user != record
  end

  def promote_to_admin?
    user&.is_super_admin?
  end

  def manage_membership?
    user&.is_admin?
  end

  class Scope < Scope
    def resolve
      if user&.is_admin?
        scope.all
      else
        scope.where(id: user.id)
      end
    end
  end
end
