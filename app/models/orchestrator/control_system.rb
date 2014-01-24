require 'set'


module Orchestrator
    class ControlSystem < Couchbase::Model
        design_document :sys
        include ::CouchbaseId::Generator


        # Allows us to lookup systems by names
        after_save      :update_name
        before_delete   :cleanup_modules
        after_delete    :expire_cache


        attribute :name
        attribute :description
        attribute :disabled     # prevents load on boot

        attribute :zones,       default: lambda { [] }
        attribute :modules,     default: lambda { [] }
        attribute :settings,    default: lambda { {} }

        attribute :created_at,  default: lambda { Time.now.to_i }


        def name=(new_name)
            @old_name ||= self.attributes[:name] || true
            self.attributes[:name] = new_name
        end

        def expire_cache
            ::Orchestrator::System.expire(self.id || @old_id)
        end


        def self.using_module(mod_id)
            by_modules({key: mod_id, stale: false})
        end
        view :by_modules

        def self.in_zone(zone_id)
            by_zones({key: zone_id, stale: false})
        end
        view :by_zones


        protected


        # Zones and settings are only required for confident coding
        validates :name,        presence: true
        validates :zones,       presence: true
        validate  :name_unique

        def name_unique
            result = ControlSystem.bucket.get("sysname-#{name}", {quiet: true})
            if result != nil && result != self.id
                errors.add(:name, 'must be unique')
            end
        end

        def update_name
            System.expire(self.id) # Expire the cache as we've updated
            if @old_name && @old_name != self.name
                ControlSystem.bucket.delete("sysname-#{@old_name}", {quiet: true}) unless @old_name == true
                ControlSystem.bucket.set("sysname-#{self.name}", self.id)
            end
            @old_name = nil
        end

        # 1. Find systems that have each of the modules specified
        # 2. If this is the last system we remove the modules
        def cleanup_modules
            ControlSystem.bucket.delete("sysname-#{self.name}", {quiet: true})

            self.modules.each do |mod_id|
                systems = ControlSystem.using_module(mod_id).to_a

                if systems.length <= 1
                    # We don't use the model's delete method as it looks up control systems
                    ::Orchestrator::Control.instance.unload(mod_id)
                    ::Orchestrator::Module.bucket.delete(mod_id, {quiet: true})
                end
            end
            
            @old_id = self.id # not sure if required
        end
    end
end
