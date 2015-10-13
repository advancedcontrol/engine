
module Orchestrator
    module Triggers
        class Module
            include ::Orchestrator::Constants
            include ::Orchestrator::Logic::Mixin

            def on_load
                @triggers = {}      # Trigger instance objects by id
                @trigger_names = {}
                @conditions = {}    # State objects by trigger id
                @debounce = {}
                @subscriptions = {} # Reference to each subscription
                @updating = Mutex.new

                # In case an update occurs while writing the database
                @pending = {}
                @writing = {}

                reload_all
            end

            def reload_all
                return if @reloading
                @reloading = true

                sys_id = system.id
                result = task {
                    triggers = TriggerInstance.for(sys_id).to_a
                    triggers.each(&:name) # Load the parent model
                    triggers
                }
                result.then method(:load_all)
                result.catch do |e|
                    logger.print_error(e, 'error loading system triggers - retrying...')

                    # Random period retry so we don't overwhelm the database
                    schedule.in(3000 + (1 + rand(2500))) do
                        @reloading = false
                        reload_all
                    end
                end
            end

            def reload_id(id)
                thread.work(proc {
                    @updating.synchronize {
                        model = ::Orchestrator::TriggerInstance.find id
                        model.name  # Load the parent model
                        model
                    }
                }).then(proc { |model|
                    # Update the model if it was updated
                    reload(model)
                }, proc { |e|
                    # report any errors updating the model
                    logger.print_error(e, "error loading trigger #{id}")
                })
            end

            def reload(trig)
                # Unload any previous trigger with the same ID
                old = @triggers[trig.id]
                remove(old.id) if old

                # Check trigger belongs to this system (this should always be true)
                if system.id == trig.control_system_id.to_sym
                    logger.debug { "loading trigger: #{trig.name} (#{trig.id})" }

                    # Load the new trigger
                    @triggers[trig.id] = trig
                    @trigger_names[trig.name] = trig

                    state = State.new(trig, schedule, method(:callback))
                    @conditions[trig.id] = state

                    subs = []
                    sys_proxy = system
                    sub_callback = state.method(:set_value)
                    state.subscriptions.each do |sub|
                        subs << sys_proxy.subscribe(sub[:mod], sub[:index], sub[:status], sub_callback)
                    end
                    @subscriptions[trig.id] = subs

                    # enable the triggers
                    state.enabled(trig.enabled)
                else
                    logger.info "not loading trigger #{trig.name} (#{trig.id}) due to system mismatch: #{system.id} != #{trig.control_system_id}"
                end
            end

            def remove(trig_id)
                trig = @triggers[trig_id]

                if trig
                    logger.debug { "removing trigger: #{trig.name} (#{trig_id})" }

                    @trigger_names.delete(trig.name)
                    @subscriptions[trig_id].each do |sub|
                        unsubscribe sub
                    end
                    @conditions[trig_id].destroy

                    timer = @debounce[trig_id]
                    timer.cancel if timer

                    @triggers.delete(trig_id)
                end
            end

            def run_trigger_action(name)
                trig = @triggers[name] || @trigger_names[name]
                perform_trigger_actions(trig.id)
            end


            protected


            def load_all(triggers)
                @triggers = {}
                @trigger_names = {}

                # unsubscribe
                @subscriptions.each_value do |subs|
                    subs.each do |sub|
                        unsubscribe sub
                    end
                end
                @subscriptions = {}

                # stop any schedules
                @conditions.each_value(&:destroy)
                @conditions = {}

                # stop and debounce timers
                @debounce.each_value(&:cancel)

                # create new trigger objects
                # with current status values
                sys_proxy = system
                callback = method(:callback)
                triggers.each do |trig|
                    @triggers[trig.id] = trig
                    @trigger_names[trig.name] = trig

                    state = State.new(trig, schedule, callback)
                    @conditions[trig.id] = state

                    # subscribe to status variables and
                    # map any existing status into the triggers
                    subs = []
                    sub_callback = state.method(:set_value)

                    state.subscriptions.each do |sub|
                        subs << sys_proxy.subscribe(sub[:mod], sub[:index], sub[:status], sub_callback)
                    end
                    @subscriptions[trig.id] = subs

                    # enable the triggers
                    state.enabled(trig.enabled)
                end

                @reloading = false
            end

            # Function called when the trigger state is updated
            def callback(id, state)
                trig = @triggers[id]
                if trig.debounce_period > 0
                    existing = @debounce[id]
                    existing.cancel if existing
                    @debounce[id] = schedule.in(trig.debounce_period * 1000) do
                        @debounce.delete(id)
                        update_model(id, state)
                    end
                else
                    update_model(id, state)
                end
            end

            def update_model(id, state)
                # Ensure that updates don't build queues and 
                if @writing[id]
                    @pending[id] = state
                else
                    perform_update_model(id, state)
                end
            end

            CAS = 'cas'.freeze
            def perform_update_model(id, state)
                # Access the database in a non-blocking fashion
                @writing[id] = true

                thread.work(proc {
                    @updating.synchronize {
                        model = ::Orchestrator::TriggerInstance.find_by_id id

                        if model
                            model.ignore_update
                            model.triggered = state
                            model.save!(CAS => model.meta[CAS])
                            model.name  # Load the parent model
                            model
                        else
                            nil
                        end
                    }
                }).then(proc { |model|
                    # Update the model if it was updated
                    if model
                        @triggers[id] = model
                        @trigger_names[model.name] = model
                        self[model.binding] = state
                        logger.info "trigger model updated: #{model.name} (#{model.id}) -> #{state}"
                    else
                        model = @triggers[id]
                        model.triggered = state
                        logger.warn "trigger #{model.id} not found: (#{model.name})"
                    end
                }, proc { |e|
                    # report any errors updating the model
                    logger.print_error(e, 'error updating triggered state in database model')
                }).finally do
                    perform_trigger_actions(id) if state

                    # If an update occured while we were processing
                    # This means there is no more than a queue of 1 (good for memory)
                    if @pending[id].nil?
                        @writing.delete(id)
                    else
                        new_state = @pending.delete(id)
                        perform_update_model(id, new_state) if new_state != state
                    end
                end
            end

            def perform_trigger_actions(id)
                model = @triggers[id]

                logger.debug "running trigger actions for #{model.name} (#{model.id})"

                model.actions.each do |act|
                    begin
                        case act[:type].to_sym
                        when :exec
                            # Execute the action
                            logger.debug { "executing action #{act[:mod]}_#{act[:index]}.#{act[:func]}(#{act[:args].join(', ')})" }
                            system.get(act[:mod], act[:index]).method_missing(act[:func], *act[:args])
                        when :email
                            logger.debug { "sending email to: #{act[:to]}" }
                            # TODO:: provide hooks into action mailer
                        end
                    rescue => e
                        logger.print_error(e, "error performing trigger action #{act} for trigger #{model.id}: #{model.name}")
                    end
                end
            end
        end
    end
end
