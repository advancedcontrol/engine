
module Orchestrator
    module Api
        class UsersController < ApiController
            respond_to :json
            before_action :check_authorization, only: [:update]
            before_action :check_admin, only: [:logs, :destroy]


            before_action :doorkeeper_authorize!


            # deal with live reload   filter
            @@elastic ||= Elastic.new(User)
            @@elasticLogs ||= Elastic.new(::Orchestrator::AccessLog)


            def index
                query = @@elastic.query(params)
                results = @@elastic.search(query) do |user|
                    user.as_json(User::PUBLIC_DATA)
                end
                respond_with results
            end

            def logs
                query = @@elasticLogs.query(params)
                query.sort = [{
                    ended_at: "desc"
                }]
                query.filter({
                    user_id: [id]
                })

                results = @@elasticLogs.search(query) do |entry|
                    entry.as_json.tap do |json|
                        json[:systems] = ControlSystem.find_by_id(json[:systems]).as_json(only: [:id, :name])
                    end
                end
                respond_with results
            end

            def show
                user = User.find(id)

                # We only want to provide limited 'public' information
                respond_with user, User::PUBLIC_DATA
            end

            def current
                respond_with current_user
            end


            ##
            # Requests requiring authorization have already loaded the model
            def update
                @user.update_attributes(safe_params)
                @user.save
                respond_with @user
            end

            # TODO:: We should only ever disable users... Need to add this flag
            #def destroy
            #    respond_with @user.delete
            #end


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