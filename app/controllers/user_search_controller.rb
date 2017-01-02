class UserSearchController < ApplicationController
	def show
		email = params[:email]
		users = User.search(email)
		render :json => users.to_json
	end
end