
module Orchestrator
    module Api
        class DependenciesController < ApiController
            respond_to :json
            #doorkeeper_for :all
            before_action :check_authorization, only: [:show, :update, :destroy, :reload]


            @@elastic ||= Elastic.new(Dependency)


            def index
                role = params.permit(:role)[:role]
                query = @@elastic.query(params)

                if role && Dependency::ROLES.include?(role.to_sym)
                    query.filter({
                        role: [role]
                    })
                end

                query.sort = [{name: "asc"}]

                respond_with @@elastic.search(query)
            end

            def show
                respond_with @dep
            end

            def update
                # Must destroy and re-add to change class or module name
                @dep.update_attributes(update_params)
                save_and_respond @dep
            end

            def create
                dep = Dependency.new(safe_params)
                save_and_respond dep
            end

            def destroy
                @dep.delete
                render :nothing => true
            end


            ##
            # Additional Functions:
            ##

            def reload
                depman = ::Orchestrator::DependencyManager.instance
                depman.load(@dep, :force).then(proc {
                    @dep.modules.each do |mod|
                        manager = mod.manager
                        manager.reloaded if manager
                    end
                    env['async.callback'].call([200, {
                        'Content-Length' => 0
                    }, []])
                }, proc { |err|
                    output = err.message
                    env['async.callback'].call([500, {
                        'Content-Length' => output.bytesize,
                        'Content-Type' => 'text/plain'
                    }, [output]])
                })
                throw :async
            end


            protected


            DEP_PARAMS = [
                :name, :description, :role,
                :class_name, :module_name,
                :default
            ]
            def safe_params
                settings = params[:settings]
                {
                    settings: settings.is_a?(::Hash) ? settings : {}
                }.merge(params.permit(DEP_PARAMS))
            end

            def update_params
                params.permit(:name, :description, {settings: []})
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @dep = Dependency.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
