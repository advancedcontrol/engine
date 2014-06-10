require 'thread'


module Orchestrator
    class System
        @@systems = ThreadSafe::Cache.new
        @@critical = Mutex.new

        def self.get(id)
            name = id.to_sym
            system = @@systems[name]
            if system.nil?
                system = self.load(name)
            end
            return system
        end

        def self.expire(id)
            @@systems.delete(id.to_sym)
        end

        def self.clear_cache
            @@critical.synchronize {
                @@systems = ThreadSafe::Cache.new
            }
        end


        attr_reader :zones, :config


        def initialize(control_system)
            @config = control_system
            @controller = ::Orchestrator::Control.instance

            @modules = {}
            @config.modules.each &method(:index_module)

            # Build an ordered zone cache for setting lookup
            zones = ::Orchestrator::Control.instance.zones
            @zones = []
            @config.zones.each do |zone_id|
                zone = zones[zone_id]
                @zones << zone unless zone.nil?
            end
        end

        def get(mod, index)
            mods = @modules[mod]
            if mods
                mods[index]
            else
                nil # As subscriptions can be made to modules that don't exist
            end
        end

        def all(mod)
            @modules[mod] || []
        end

        def count(name)
            mod = @modules[name]
            mod.nil? ? 0 : mod.length
        end

        def modules
            @modules.keys
        end

        def settings
            @config.settings
        end


        protected


        # looks for the system in the database
        def self.load(id)
            @@critical.synchronize {
                system = @@systems[id]
                return system unless system.nil?

                sys = ControlSystem.find_by_id(id.to_s)
                if sys.nil?
                    return nil
                else
                    system = System.new(sys)
                    @@systems[id] = system
                end
                return system
            }
        end

        def index_module(mod_id)
            manager = @controller.loaded?(mod_id)
            if manager
                mod_name = if manager.settings.custom_name.nil?
                    manager.settings.dependency.module_name.to_sym
                else
                    manager.settings.custom_name.to_sym
                end
                @modules[mod_name] ||= []
                @modules[mod_name] << manager
            end
        end
    end
end
