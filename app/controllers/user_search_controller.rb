class UserSearchController < ApplicationController

	skip_before_filter :authenticate_user!, only: [:show] 

	def show
		email = params[:email]
		users = User.search(email)
		render :json => users.to_json
	end
end