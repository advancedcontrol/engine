
module Orchestrator
    class UdpService < ::UV::DatagramConnection
        def initialize(*args)
            super(*args)

            @callbacks = {
                # ip => port => callback
            }
        end
        
        def attach(ip, port, callback)
            @loop.schedule do
                ports = @callbacks[ip.to_sym] ||= {}
                ports[port.to_i] = callback
            end
        end

        def detach(ip_raw, port)
            @loop.schedule do
                ip = ip_raw.to_sym
                ip_ports = @callbacks[ip]
                if ip_ports
                    ip_ports.delete(port.to_i)
                    @callbacks.delete(ip) if ip_ports.empty?
                end
            end
        end

        def on_read(data, ip, port, transport)
            ip_ports = @callbacks[ip.to_sym]
            if ip_ports
                callback = ip_ports[port.to_i]
                if callback
                    callback.call(data)
                end
            end
        end

        def send(ip, port, data)
            @loop.schedule do 
                send_datagram(data, ip, port)
            end
        end
    end


    class UdpBroadcast < ::UV::DatagramConnection
        def post_init
            @transport.enable_broadcast
        end

        def send(ip, port, data)
            @loop.schedule do
                send_datagram(data, ip, port)
            end
        end
    end
end


module Libuv
    class Loop
        def udp_service
            if @udp_service.nil?
                CRITICAL.synchronize {
                    return @udp_service if @udp_service

                    if defined? @@udp_service
                        @udp_service = @@udp_service
                    else # define a class variable at the specified port
                        bind_port = Rails.configuration.orchestrator.datagram_port || 0
                        @udp_service = ::UV.open_datagram_socket(::Orchestrator::UdpService, '0.0.0.0', bind_port)
                        @@udp_service = @udp_service if bind_port != 0
                    end
                }
            end
            
            @udp_service
        end

        def udp_broadcast(data, port = 9, ip = nil)
            ip = ip || '255.255.255.255'

            if @udp_broadcast.nil?
                CRITICAL.synchronize {
                    return @udp_broadcast.send(ip, port, data) if @udp_broadcast
                    
                    if defined? @@udp_broadcast
                        @udp_broadcast = @@udp_broadcast
                    else
                        bind_port = Rails.configuration.orchestrator.broadcast_port || 0
                        @udp_broadcast = ::UV.open_datagram_socket(::Orchestrator::UdpBroadcast, '0.0.0.0', bind_port)
                        @@udp_broadcast = @udp_broadcast if bind_port != 0
                    end
                }
            end

            @udp_broadcast.send(ip, port, data)
        end

        def wake_device(mac, ip = nil)
            ip = ip || '255.255.255.255'
            mac = mac.gsub(/(0x|[^0-9A-Fa-f])*/, "").scan(/.{2}/).pack("H*H*H*H*H*H*")
            magicpacket = (0xff.chr) * 6 + mac * 16
            udp_broadcast(magicpacket, 9, ip)
        end
    end
end
