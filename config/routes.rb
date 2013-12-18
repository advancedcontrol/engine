Orchestrator::Engine.routes.draw do

    # Trusted Sessions - Create Trust (returns id), Update Session and Destroy Trust
    resources :trusts

    # Restful access to services
    namespace :api do
        resources :systems do                    # systems have settings and define what zone they are in
            post 'start',   on: :member
            post 'stop',    on: :member
            post 'request', on: :member
            get  'status',  on: :member

            resources :modules, shallow: true do # modules have settings
                post 'start',   on: :member
                post 'stop',    on: :member
                get  'status',  on: :member
            end
        end
        resources :dependencies     # dependencies have settings
        resources :groups           # users define the groups they are in
        resources :zones            # zones define what groups can access them
    end

    # These are non-restful endpoints
    # Websockets and Eventsources
    get 'websocket', to: 'persistence#websocket', via: :all
end
