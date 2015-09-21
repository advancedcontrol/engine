
module Orchestrator
    module Api
        class UsersController < ApiController
            respond_to :json
            before_action :check_authorization, only: [:update]
            before_action :check_admin, only: [:index, :destroy]


            before_action :doorkeeper_authorize!


            # deal with live reload   filter
            @@elastic ||= Elastic.new(User)

             # Admins can see a little more of the users data
            ADMIN_DATA = User::PUBLIC_DATA.dup
            ADMIN_DATA[:only] += [:support, :sys_admin, :email]


            def index
                query = @@elastic.query(params)
                query.not({deleted: [true]})
                results = @@elastic.search(query) do |user|
                    user.as_json(ADMIN_DATA)
                end
                respond_with results
            end

            def show
                user = User.find(id)

                # We only want to provide limited 'public' information
                if current_user.sys_admin
                    respond_with user, ADMIN_DATA
                else
                    respond_with user, User::PUBLIC_DATA
                end
            end

            def current
                respond_with current_user
            end


            ##
            # Requests requiring authorization have already loaded the model
            def update
                @user.assign_attributes(safe_params)
                @user.save
                respond_with @user
            end

            # Make this available when there is a clean up option
            def destroy
                @user = User.find(id)

                if defined?(::UserCleanup)
                    @user.destroy
                    render nothing: true
                else
                    ::Auth::Authentication.for_user(@user.id).each do |auth|
                        auth.delete
                    end
                    @user.delete
                end
            end


            protected


            def safe_params
                if current_user.sys_admin
                    params.require(:user).permit(:name, :email, :nickname, :sys_admin, :support)
                else
                    params.require(:user).permit(:name, :email, :nickname)
                end
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @user = User.find(id)
                user = current_user

                # Does the current user have permission to perform the current action
                head(:forbidden) unless @user.id == user.id || user.sys_admin
            end
        end
    end
end
