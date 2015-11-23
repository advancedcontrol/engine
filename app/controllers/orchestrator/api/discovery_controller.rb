
module Orchestrator
    module Api
        class DiscoveryController < ApiController
            respond_to :json
            before_action :check_admin


            @@elastic ||= Elastic.new(Discovery)


            def index
                query = @@elastic.query(params)
                query.sort = NAME_SORT_ASC
                query.search_field :name

                respond_with @@elastic.search(query)
            end


            # TODO::
            # Provide options to trigger the discovery process
            # In development we should have a daemon that searches for devices on the network
        end
    end
end
