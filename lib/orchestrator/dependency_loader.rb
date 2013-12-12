require 'thread'    # For Mutex
require 'set'


module Orchestrator
    class DependencyLoader
        include Singleton


        def initialize
            @load_mutex = Mutex.new
            @dependencies = ThreadSafe::Cache.new
            @loop = ::Libuv::Loop.default
        end


        class FileNotFound < StandardError; end


        def load(classname, force = false)
            defer = @loop.defer
            
            class_lookup = classname.to_sym
            class_object = @dependencies[class_lookup]

            if class_object && force == false
                defer.resolve(class_object)
            else
                begin
                    file = "#{classname.underscore}.rb"
                    class_object = nil

                    ::Rails.configuration.orchestrator.module_paths.each do |path|
                        if File.exists?("#{path}/#{file}")
                            @load_mutex.synchronize {
                                load "#{path}/#{file}"
                            }
                            class_object = classname.constantize
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
    end
end
