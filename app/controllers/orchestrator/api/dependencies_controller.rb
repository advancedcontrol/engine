
module Orchestrator
    module Api
        class DependenciesController < ApiController
            respond_to :json
            before_action :check_admin, except: [:index, :show]
            before_action :check_support, only: [:index, :show]
            before_action :find_dependency, only: [:show, :update, :destroy, :reload]


            @@elastic ||= Elastic.new(Dependency)


            def index
                role = params.permit(:role)[:role]
                query = @@elastic.query(params)

                if role && Dependency::ROLES.include?(role.to_sym)
                    query.filter({
                        'doc.role' => [role]
                    })
                end

                query.sort = NAME_SORT_ASC

                respond_with @@elastic.search(query)
            end

            def show
                respond_with @dep
            end

            def update
                args = safe_params
                args.delete(:role)
                args.delete(:class_name)

                # Must destroy and re-add to change class or module type
                @dep.assign_attributes(args)
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
                    content = nil

                    begin
                        updated = 0

                        @dep.modules.each do |mod|
                            manager = mod.manager
                            if manager
                                updated += 1
                                manager.reloaded(mod)
                            end
                        end

                        content = {
                            message: updated == 1 ? "#{updated} module updated" : "#{updated} modules updated"
                        }.to_json
                    rescue => e
                        # Let user know about any post reload issues
                        message = 'Warning! Reloaded successfully however some modules were not informed. '
                        message << "It is safe to reload again. Error was: #{e.message}"
                        content = {
                            message: message
                        }.to_json
                    end

                    env['async.callback'].call([200, {
                        'Content-Length' => content.bytesize,
                        'Content-Type' => 'application/json'
                    }, [content]])
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

            def find_dependency
                # Find will raise a 404 (not found) if there is an error
                @dep = Dependency.find(id)
            end
        end
    end
end
