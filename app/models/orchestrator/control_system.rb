require 'set'
require 'addressable/uri'


module Orchestrator
    class ControlSystem < Couchbase::Model
        design_document :sys
        include ::CouchbaseId::Generator
        
        # Allows us to lookup systems by names
        before_save     :update_name
        after_save      :expire_cache

        before_delete   :cleanup_modules
        after_delete    :expire_cache


        attribute :name
        define_attribute_methods :name  # dirty attributes for name!

        attribute :description

        attribute :zones,       default: lambda { [] }
        attribute :modules,     default: lambda { [] }
        attribute :settings,    default: lambda { {} }

        attribute :created_at,  default: lambda { Time.now.to_i }

        # Provide a field for simplifying support
        attribute :support_url


        # Used in triggers::manager for accssing a system proxy
        def control_system_id
            self.id
        end


        def self.find_by_name(name)
            id = ControlSystem.bucket.get("sysname-#{self.name.downcase}", {quiet: true})
            ControlSystem.find_by_id(id) if id
        end


        def name=(new_name)
            new_name.strip!
            write_attribute(:name, new_name)
        end

        def expire_cache(noUpdate = nil)
            ::Orchestrator::System.expire(self.id || @old_id)
            ctrl = ::Orchestrator::Control.instance

            # If not deleted and control is running
            # then we want to trigger updates on the logic modules
            if !@old_id && noUpdate.nil? && ctrl.ready
                # Start the triggers if not already running (must occur on the same thread)
                cs = self
                ctrl.loop.schedule do
                    ctrl.load_triggers_for(cs)
                end

                # Reload the running modules
                (::Orchestrator::Module.find_by_id(self.modules) || []).each do |mod|
                    if mod.control_system_id
                        manager = ctrl.loaded? mod.id
                        manager.reloaded(mod) if manager
                    end
                end
            end
        end


        def self.all
            all(stale: false)
        end
        view :all

        def self.using_module(mod_id)
            by_modules({key: mod_id, stale: false})
        end
        view :by_modules

        def self.in_zone(zone_id)
            by_zones({key: zone_id, stale: false})
        end
        view :by_zones


        # Methods for obtaining the modules and zones as objects
        def module_data
            (::Orchestrator::Module.find_by_id(modules) || []).collect do |mod| 
                mod.as_json({
                    include: {
                        dependency: {
                            only: [:name, :module_name]
                        }
                    }
                })
            end
        end

        def zone_data
            ::Orchestrator::Zone.find_by_id(zones) || []
        end


        # Triggers
        def triggers
            TriggerInstance.for(self.id)
        end


        protected


        # Zones and settings are only required for confident coding
        validates :name,        presence: true
        validates :zones,       presence: true

        validate  :support_link

        def support_link
            if self.support_url.nil? || self.support_url.empty?
                self.support_url = nil
            else
                begin
                    url = Addressable::URI.parse(self.support_url)
                    url.scheme && url.host && url
                rescue
                    errors.add(:support_url, 'is an invalid URI')
                end
            end
        end

        validate  :name_unique

        def name_unique
            return false if self.name.blank?

            result = ControlSystem.bucket.get("sysname-#{name.downcase}", {quiet: true})
            if result != nil && result != self.id
                errors.add(:name, 'has already been taken')
            end
        end

        def update_name
            if self.name_changed?
                old_name = self.name_was
                old_name.downcase! if old_name
            elsif not self.exists?
                old_name = false
            else
                return
            end

            current_name = self.name.downcase

            if old_name != current_name
                bucket = ControlSystem.bucket
                bucket.delete("sysname-#{old_name}", {quiet: true}) if old_name
                bucket.set("sysname-#{current_name}", self.id)
            end
        end

        # 1. Find systems that have each of the modules specified
        # 2. If this is the last system we remove the modules
        def cleanup_modules
            ControlSystem.bucket.delete("sysname-#{self.name.downcase}", {quiet: true})
            ctrl = ::Orchestrator::Control.instance

            self.modules.each do |mod_id|
                systems = ControlSystem.using_module(mod_id).fetch_all

                if systems.length <= 1
                    # We don't use the model's delete method as it looks up control systems
                    ctrl.unload(mod_id)
                    ::Orchestrator::Module.bucket.delete(mod_id, {quiet: true})
                end
            end
            
            # Unload the triggers
            ctrl.unload(self.id)

            # delete all the trigger instances (remove directly as before_delete is not required)
            bucket = ::Orchestrator::TriggerInstance.bucket
            TriggerInstance.for(sys_id).each do |trig|
                bucket.delete(trig.id)
            end

            # Prevents reload for the cache expiry
            @old_id = self.id
        end
    end
end
