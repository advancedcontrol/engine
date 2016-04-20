
module Orchestrator
    module Api
        class NodesController < ApiController
            respond_to :json

            before_action :check_admin, except: [:index, :show]
            before_action :check_support, only: [:index, :show]

            before_action :find_edge, only: [:show, :update, :destroy]


            @@elastic ||= Elastic.new(EdgeControl)


            def index
                query = @@elastic.query(params)
                query.sort = NAME_SORT_ASC
                query.search_field 'doc.name'

                respond_with @@elastic.search(query)
            end

            def show
                respond_with @edge
            end

            def update
                @edge.assign_attributes(safe_params)
                save_and_respond @edge
            end

            def create
                edge = EdgeControl.new(safe_params)
                save_and_respond edge
            end

            def destroy
                # delete will update CS and zone caches
                @edge.delete
                render :nothing => true
            end


            protected


            NODE_PARAMS = [
                :name, :description, :host_origin, :settings, :admins,
                :failover, :timeout, :window_start, :window_length,
                {admins: []}
            ]
            def safe_params
                settings = params[:settings]
                {
                    settings: settings.is_a?(::Hash) ? settings : {},
                    admins: []
                }.merge(params.permit(NODE_PARAMS))
            end

            def find_edge
                # Find will raise a 404 (not found) if there is an error
                edge_id = id
                @edge = control.nodes[edge_id.to_sym] || Zone.find(edge_id)
            end
        end
    end
end
