
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
            if @udp_service
                @udp_service
            else
                CRITICAL.synchronize {
                    return @udp_service if @udp_service

                    port = Rails.configuration.orchestrator.datagram_port || 0

                    if port == 0
                        @udp_service = ::UV.open_datagram_socket(::Orchestrator::UdpService)
                    elsif defined? @@udp_service
                        @udp_service = @@udp_service
                    else # define a class variable at the specified port
                        @udp_service = ::UV.open_datagram_socket(::Orchestrator::UdpService, '0.0.0.0', port)
                        @@udp_service = @udp_service
                    end
                }
            end
        end

        def udp_broadcast(data, port = 9, ip = '<broadcast>')
            if @udp_broadcast
                @udp_broadcast.send(ip, port, data)
            else
                CRITICAL.synchronize {
                    return @udp_broadcast.send(ip, port, data) if @udp_broadcast
                    
                    port = Rails.configuration.orchestrator.broadcast_port || 0

                    if port == 0
                        @udp_broadcast = ::UV.open_datagram_socket(::Orchestrator::UdpBroadcast)
                    elsif defined? @@udp_broadcast
                        @udp_broadcast = @@udp_broadcast
                    else # define a class variable at the specified port
                        @udp_broadcast = ::UV.open_datagram_socket(::Orchestrator::UdpBroadcast, '0.0.0.0', port)
                        @@udp_broadcast = @udp_broadcast
                    end

                    @udp_broadcast.send(ip, port, data)
                }
            end
        end

        def wake_device(mac, ip = '<broadcast>')
            mac = mac.gsub(/(0x|[^0-9A-Fa-f])*/, "").scan(/.{2}/).pack("H*H*H*H*H*H*")
            magicpacket = (0xff.chr) * 6 + mac * 16
            udp_broadcast(magicpacket, 9, ip)
        end
    end
end
