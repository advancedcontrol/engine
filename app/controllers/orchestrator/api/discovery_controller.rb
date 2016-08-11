
module Orchestrator
    module Api
        class DiscoveryController < ApiController
            respond_to :json
            before_action :check_admin


            @@elastic ||= Elastic.new(Discovery)


            # Get a list of the available drivers
            def index
                query = @@elastic.query(params)
                query.sort = NAME_SORT_ASC
                query.search_field 'doc.name'

                respond_with @@elastic.search(query)
            end

            # This is really here for API consistency
            def show
                disc = Discovery.find(id)
                respond_with disc
            end


            # Build and/or update the list of available drivers
            DiscoverCommand = 'bundle exec rake discover:drivers'.freeze
            def scan
                time = Time.now.to_i
                @@last_spawn ||= 0

                if @@last_spawn < time
                    @@last_spawn = time + 10
                    spawn(DiscoverCommand)
                end

                head :ok
            end
        end
    end
end
