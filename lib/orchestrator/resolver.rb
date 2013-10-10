require 'celluloid' # Resolver is an Actor
require 'ipaddress' # IP address tools
require 'resolv'    # for DNS lookups 


module Orchestrator
    
    # Resolver is used to loop up hostnames in a non-blocking fashion
    class Resolver
        include Celluloid


        # Looks up a hostname and resolves a deferrable with the results
        #
        # @param deferred [::Libuv::Q::Deferred] the deferrable to be resolved once the hostname has been looked up
        # @param hostname [String] the hostname to be converted to an IP address
        def resolve(deferred, hostname)
            begin
                ip = Resolv.getaddress(hostname)
                deferred.resolve(ip)
            rescue StandardError => e
                deferred.reject(e)
            end
        end


        # Looks up a hostname and resolves a deferrable with the results
        #
        # @param deferred [::Libuv::Q::Deferred] the deferrable to be resolved once the hostname has been looked up
        # @param hostname [String] the hostname to be converted to an IP address
        def list(deferred, hostname)
            begin
                ip = Resolv.getaddresses(hostname)
                deferred.resolve(ip)
            rescue StandardError => e
                deferred.reject(e)
            end
        end
        

        # Calls resolve on the default resolver thread without blocking
        #
        # @see #Resolver
        def self.first(deferred, hostname)
            if IPAddress.valid? hostname
                deferred.resolve(hostname)
            else
                @@resolver.async.resolve(deferred, hostname)
            end
        end


        # Calls list on the default resolver thread without blocking
        #
        # @see #Resolver
        def self.lookup(deferred, hostname)
            if IPAddress.valid? hostname
                deferred.resolve([hostname])
            else
                @@resolver.async.list(deferred, hostname)
            end
        end

        # Create the default resolver
        @@resolver = Resolver.new
    end

end
