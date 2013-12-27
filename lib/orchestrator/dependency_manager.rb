require 'thread'    # For Mutex
require 'set'


module Orchestrator
    class DependencyManager
        include Singleton


        def initialize
            @load_mutex = Mutex.new
            @dependencies = ThreadSafe::Cache.new
            @loop = ::Libuv::Loop.default
        end


        class FileNotFound < StandardError; end


        def load(dependency, force = false)
            defer = @loop.defer
            
            classname = dependency.class_name
            class_lookup = classname.to_sym
            class_object = @dependencies[class_lookup]

            if class_object && force == false
                defer.resolve(class_object)
            else
                # We need to ensure only one file loads at a time
                @load_mutex.synchronize {
                    perform_load(dependency, defer, classname, class_lookup, force)
                }
            end

            defer.promise
        end

        def force_load(file)
            defer = @loop.defer

            if File.exists?(file)
                begin
                    @load_mutex.synchronize {
                        load file
                    }
                    defer.resolve(file)
                rescue Exception => e
                    defer.reject(e)
                end
            else
                defer.reject(FileNotFound.new("could not find '#{file}'"))
            end

            defer.promise
        end


        protected


        # Always called from within a Mutex
        def perform_load(dependency, defer, classname, class_lookup, force)
            if force == false
                class_object = @dependencies[class_lookup]
                if class_object
                    defer.resolve(class_object)
                    return
                end
            end

            begin
                file = "#{classname.underscore}.rb"
                class_object = nil

                ::Rails.configuration.orchestrator.module_paths.each do |path|
                    if ::File.exists?("#{path}/#{file}")

                        ::Kernel.load "#{path}/#{file}"
                        class_object = classname.constantize

                        case dependency.role
                        when :device
                            include_device(class_object)
                        when :service
                            include_service(class_object)
                        else
                            include_logic(class_object)
                        end

                        @dependencies[class_lookup] = class_object
                        defer.resolve(class_object)
                        break
                    end
                end
                
                if class_object.nil?
                    defer.reject(FileNotFound.new("could not find '#{file}'"))
                end
            rescue Exception => e
                defer.reject(e)
            end
        end

        def include_logic(klass)
            klass.class_eval do
                include ::Orchestrator::Logic::Mixin
            end
        end

        def include_device(klass)
            klass.class_eval do
                include ::Orchestrator::Device::Mixin
            end
        end

        def include_service(klass)
            klass.class_eval do
                include ::Orchestrator::Service::Mixin
            end
        end
    end
end
