
module Orchestrator
    module Api
        class SystemTriggersController < ApiController
            respond_to :json
            
            # state, funcs, count and types are available to authenticated users
            before_action :check_admin,   only: [:create, :update, :destroy]
            before_action :check_support, only: [:index, :show]
            before_action :find_instance, only: [:show, :update, :destroy]


            @@elastic ||= Elastic.new(TriggerInstance)


            QUERY_PARAMS = [:system_id]
            def index
                query = @@elastic.query(params)

                # Filter by system ID
                sys_id = params.permit(QUERY_PARAMS)[:system_id]
                query.filter({
                    control_system_id: [sys_id]
                })

                # Include parent documents in the search
                query.has_parent Trigger
                respond_with @@elastic.search(query)
            end

            def show
                respond_with @trig
            end

            def update
                @trig.assign_attributes(safe_params)
                save_and_respond(@trig)
            end

            def create
                trig = TriggerInstance.new(safe_params)
                save_and_respond trig
            end

            def destroy
                @trig.delete # expires the cache in after callback
                render :nothing => true
            end


            protected


            # Better performance as don't need to create the object each time
            INSTANCE_PARAMS = [
                :enabled, :important, :control_system_id, :trigger_id
            ]
            REQUIRED_PARAMS = [
                :control_system_id, :trigger_id
            ]
            def safe_params
                params.require(REQUIRED_PARAMS)
                params.permit(INSTANCE_PARAMS)
            end

            def find_instance
                # Find will raise a 404 (not found) if there is an error
                @trig = TriggerInstance.find(id)
            end
        end
    end
end
