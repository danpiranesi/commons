# Used only in the test environment to authenticate a user without SSO.
# Excluded from production routing via the Rails.env.test? guard in routes.rb.
class TestSessionsController < ActionController::Base
  def create
    session[:user_id] = params[:user_id].to_i
    head :ok
  end
end
