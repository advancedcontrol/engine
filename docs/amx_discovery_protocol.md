# AMX Discovery Protocol


* Multicast address 239.255.250.250
* UDP port 9131

Device will broadcast messages that look like:

```ruby

"AMXB <-SDKClass=VideoProjector> <-UUID=DEADBEEF> <-Make=Epson> <-Model=EB-4950WU>\r"

```

## Field Names

* Device-SDKClass
* -SDKClass
* Device-UUID
* -UUID 
* Device-Make
* -Make
* Device-Model
* -Model
* Device-Revision
* -Revision
* Bundle-Version


## Class Names

* Amplifier
* AudioProcessor
* DigitalMediaServer
* DiscDevice
* HVAC
* LightSystem
* PoolSpa
* SecuritySystem
* VideoProcessor
* VolumeController
* AudioConferencer
* AudioTunerDevice
* DigitalSatelliteSystem
* DocumentCamera
* Keypad
* Monitor
* PreAmpSurroundSoundProcessor
* SensorDevice
* Switcher
* VideoProjector
* Weather
* AudioMixer
* Camera
* DigitalVideoRecorder
* Light
* Motor
* Receiver
* SettopBox
* TV
* VideoConferencer
* VideoWall


## Example Code

```ruby

# ------------------
# Server (listening)
# ------------------
require 'libuv'

loop = Libuv::Loop.default
loop.run do
    udp = loop.udp
    udp.progress do |data, ip, port|
        puts "received #{data.chomp} from #{ip}:#{port}"
    end
    udp.bind('0.0.0.0', 9131)
    udp.join('239.255.250.250', '0.0.0.0')
    udp.start_read

    loop.signal :INT do
        loop.stop
    end
end


# --------------
# Example Client
# --------------
require 'libuv'

loop = Libuv::Loop.default
loop.run do
    udp = loop.udp
    udp.progress do |data, ip, port|
        puts "received #{data} from #{ip}:#{port}"
    end
    udp.bind('0.0.0.0', 0)
    udp.enable_broadcast
    udp.send('239.255.250.250', 9131, "AMXB <-SDKClass=VideoProjector> <-UUID=DEADBEEF> <-Make=Epson> <-Model=EB-4950WU>\r")
end

```

