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



        def initialize(control_system)
            @system = control_system
            @controller = ::Orchestrator::Control.instance

            @modules = {}
            @zones = Set.new(Zone.find_by_id(@system.zones))
            @system.modules.each &method(:index_module)
        end

        def get(mod, index)
            @modules[mod][index]
        end

        def all(mod)
            @modules[mod]
        end

        def count(name)
            mod = @modules[name]
            mod.nil? ? 0 : mod.length
        end

        def modules
            @modules.keys
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
            mod_name = manager.settings.dependency.module_name.to_sym
            @modules[mod_name] ||= []
            @modules[mod_name] << manager
        end
    end
end
