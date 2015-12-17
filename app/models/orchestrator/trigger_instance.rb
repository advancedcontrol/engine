
module Orchestrator
    class TriggerInstance < Couchbase::Model
        design_document :trig
        include ::CouchbaseId::Generator

        belongs_to :control_system, :class_name => "Orchestrator::ControlSystem".freeze
        belongs_to :trigger, :class_name => "Orchestrator::Trigger".freeze

        attribute :created_at, default: lambda { Time.now.to_i }
        attribute :updated_at, default: lambda { Time.now.to_i }
        
        attribute :enabled,    default: true
        attribute :triggered,  default: false
        attribute :important,  default: false

        attribute :override,   default: lambda { {} }


        before_delete :unload
        after_save    :load


        # ----------------
        # PARENT ACCESSORS
        # ----------------
        def name
            trigger.name
        end

        def description
            trigger.description
        end

        def conditions
            trigger.conditions
        end

        def actions
            trigger.actions
        end

        def debounce_period
            trigger.debounce_period
        end

        def binding
            return @binding if @binding || self.id.nil?
            chars = self.id.split('_'.freeze, 2)[1]
            @binding = 't'
            chars.each_byte do |byte|
                @binding << byte.to_s(16)
            end
            @binding
        end


        # ------------
        # VIEWS ACCESS
        # ------------
        # Finds all the instances belonging to a particular system
        def self.for(sys_id)
            by_system_id({key: sys_id, stale: false})
        end
        view :by_system_id


        # Finds all the instances belonging to a particular trigger
        def self.of(trig_id)
            by_trigger_id({key: trig_id, stale: false})
        end
        view :by_trigger_id


        # ---------------
        # JSON SERIALISER
        # ---------------
        DEFAULT_JSON_METHODS = [
            :name,
            :description,
            :conditions,
            :actions,
            :binding
        ].freeze
        def serializable_hash(options = {})
            options = options || {}
            options[:methods] = DEFAULT_JSON_METHODS
            super
        end


        # --------------------
        # START / STOP HELPERS
        # --------------------
        def load
            if @ignore_update == true
                @ignore_update = false
            else
                mod_man = get_module_manager
                mod = mod_man.instance if mod_man

                if mod_man && mod
                    trig = self
                    mod_man.thread.schedule do
                        mod.reload trig
                    end
                end
            end
        end

        def ignore_update
            @ignore_update = true
        end

        def unload
            mod_man = get_module_manager
            mod = mod_man.instance if mod_man

            if mod_man && mod
                trig = self
                old_id = trig.id # This is removed once delete has completed
                mod_man.thread.schedule do
                    mod.remove old_id
                end
            end
        end


        protected


        def get_module_manager
            ::Orchestrator::Control.instance.loaded?(self.control_system_id)
        end


        # -----------
        # VALIDATIONS
        # -----------
        # Ensure the models exist in the database
        validates :control_system, presence: true
        validates :trigger,        presence: true
    end
end
