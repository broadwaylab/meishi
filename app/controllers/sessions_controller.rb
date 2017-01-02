class SessionsController < Devise::SessionsController 
	prepend_before_filter :require_no_authentication, :only => [:create ]
  # include Devise::Controllers::InternalHelpers
  
  before_filter :ensure_params_exist

  respond_to :json

	def create

		puts "Running create"

    build_resource
    resource = User.find_for_database_authentication(:username=>params[:user_login][:username])
    return invalid_login_attempt unless resource

    if resource.valid_password?(params[:user_login][:password])
    	puts "Successful login"

      sign_in("user", resource)
      render :json=> {:success=>true, :auth_token=>resource.auth_token, username: resource.username, :email=>resource.email}
      return
    end
    puts "Invalid login"
    invalid_login_attempt
  end

  def destroy
    sign_out(resource_name)
  end

  protected
  def ensure_params_exist
    return unless params[:user_login].blank?
    render :json=>{:success=>false, :message=>"Missing user_login parameter."}, :status=>422
  end

  def invalid_login_attempt
    render :json=> {:success=>false, :message=>"Invalid username or password."}, :status=>401
  end
end