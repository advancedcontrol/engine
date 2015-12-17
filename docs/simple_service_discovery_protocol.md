# Simple Service Discovery Protocol

Based on HTTP protocol over UDP (can be multicast, broadcast or directed broadcast)

* Multicast addresses
  * 239.255.255.250
  * `[FF02::C]` (IPv6 link-local)
  * `[FF05::C]` (IPv6 site-local)
  * `[FF08::C]` (IPv6 organization-local)
  * `[FF0E::C]` (IPv6 global)

* UDP port 1900
  * IPv6 link-local 2869 (Microsoft)
  * Older implementations 5000

