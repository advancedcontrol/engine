
module Orchestrator
    module Api
        class SystemTriggersController < ApiController
            respond_to :json
            
            # state, funcs, count and types are available to authenticated users
            before_action :check_admin,   only: [:create, :update, :destroy]
            before_action :check_support, only: [:index, :show]
            before_action :find_instance, only: [:show, :update, :destroy]


            @@elastic ||= Elastic.new(TriggerInstance)


            SYS_INCLUDE = {
                include: {
                    # include control system on logic modules so it is possible
                    # to display the inherited settings
                    control_system: {
                        only: [:name, :id],
                    }
                }
            }
            QUERY_PARAMS = [:control_system_id, :trigger_id, :as_of]
            def index
                query = @@elastic.query(params)
                safe_query = params.permit(QUERY_PARAMS)
                filter = {}

                # Filter by system ID
                if safe_query.has_key? :control_system_id
                    filter[:control_system_id] = [safe_query[:control_system_id]]
                end

                # Filter by trigger ID
                if safe_query.has_key? :trigger_id
                    filter[:trigger_id] = [safe_query[:trigger_id]]
                end

                # Filter by importance
                if params.has_key? :important
                    filter[:important] = [true]
                end

                # Filter by triggered
                if params.has_key? :triggered
                    filter[:triggered] = [true]
                end

                # That occured before a particular time
                if safe_query.has_key? :as_of
                    query.raw_filter({
                        range: {
                            updated_at: {
                                lte: safe_query[:as_of].to_i
                            }
                        }
                    })
                end

                query.filter(filter)

                # Include parent documents in the search
                query.has_parent Trigger
                results = @@elastic.search(query)
                if safe_query.has_key? :trigger_id
                    respond_with results, SYS_INCLUDE
                else
                    respond_with results
                end
            end

            def show
                respond_with @trig
            end

            def update
                @trig.assign_attributes(safe_update)
                save_and_respond(@trig)
            end

            def create
                trig = TriggerInstance.new(safe_create)
                trig.save
                render json: trig
            end

            def destroy
                @trig.delete # expires the cache in after callback
                render :nothing => true
            end


            protected


            # Better performance as don't need to create the object each time
            CREATE_PARAMS = [
                :enabled, :important, :control_system_id, :trigger_id
            ]
            def safe_create
                params.permit(CREATE_PARAMS)
            end
            
            UPDATE_PARAMS = [
                :enabled, :important
            ]
            def safe_update
                params.permit(UPDATE_PARAMS)
            end

            def find_instance
                # Find will raise a 404 (not found) if there is an error
                @trig = TriggerInstance.find(id)
            end
        end
    end
end
