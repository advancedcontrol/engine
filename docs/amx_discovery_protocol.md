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
