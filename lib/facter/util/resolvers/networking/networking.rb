# frozen_string_literal: true

require 'ipaddr'

module Facter
  module Util
    module Resolvers
      module Networking
        class << self
          # Creates a hash with IP, netmask and network. Works for IPV4 and IPV6
          # @param [String] addr The IP address
          # @param [Integer] mask_length Number of 1 bits the netmask has
          #
          # @return [Hash] Hash containing ip address, netmask and network
          def build_binding(addr, mask_length)
            return if !addr || !mask_length

            ip = IPAddr.new(addr)
            mask_helper = nil
            scope = nil
            if ip.ipv6?
              scope = get_scope(addr)
              mask_helper = 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
            else
              mask_helper = '255.255.255.255'
            end
            mask = IPAddr.new(mask_helper).mask(mask_length)

            result = { address: addr, netmask: mask.to_s, network: ip.mask(mask_length).to_s }
            result[:scope6] = scope if scope
            result
          end

          def expand_main_bindings(networking_facts)
            primary = networking_facts[:primary_interface]
            interfaces = networking_facts[:interfaces]

            expand_interfaces(interfaces) unless interfaces.nil?
            return if primary.nil? || interfaces.nil? || networking_facts.nil?

            expand_primary_interface(networking_facts, primary)
          end

          def get_scope(ip)
            require 'socket'

            scope6 = []
            addrinfo = Addrinfo.new(['AF_INET6', 0, nil, ip], :INET6)

            scope6 << 'compat,' if IPAddr.new(ip).ipv4_compat?
            scope6 << if addrinfo.ipv6_linklocal?
                        'link'
                      elsif addrinfo.ipv6_sitelocal?
                        'site'
                      elsif addrinfo.ipv6_loopback?
                        'host'
                      else 'global'
                      end
            scope6.join
          end

          def find_valid_binding(bindings)
            bindings.each do |binding|
              return binding unless ignored_ip_address(binding[:address])
            end
            bindings.empty? ? nil : bindings.first
          end

          IPV4_LINK_LOCAL_ADDR = IPAddr.new('169.254.0.0/16').freeze # RFC5735
          IPV6_LINK_LOCAL_ADDR = IPAddr.new('fe80::/10').freeze # RFC4291
          IPV6_UNIQUE_LOCAL_ADDR = IPAddr.new('fc00::/7').freeze # RFC4193

          def ignored_ip_address(addr)
            return true if addr.empty?

            ip = IPAddr.new(addr)
            return true if ip.loopback?

            [
              IPV4_LINK_LOCAL_ADDR,
              IPV6_LINK_LOCAL_ADDR,
              IPV6_UNIQUE_LOCAL_ADDR
            ].each do |range|
              return true if range.include?(ip)
            end

            false
          end

          def calculate_mask_length(netmask)
            ipaddr = IPAddr.new(netmask)

            ipaddr.to_i.to_s(2).count('1')
          end

          def format_mac_address(address)
            address.split('.').map { |e| format('%<mac_address>02s', mac_address: e) }.join(':').tr(' ', '0')
          end

          private

          def expand_interfaces(interfaces)
            interfaces.each_value do |values|
              expand_binding(values, values[:bindings]) if values[:bindings]
              expand_binding(values, values[:bindings6], false) if values[:bindings6]
            end
          end

          def expand_primary_interface(networking_facts, primary)
            networking_facts[:interfaces][primary]&.each do |key, value|
              networking_facts[key] = value unless %i[bindings bindings6].include?(key)
            end
          end

          def expand_binding(values, bindings, ipv4_type = true)
            binding = find_valid_binding(bindings)
            ip_protocol_type = ipv4_type ? '' : '6'

            values["ip#{ip_protocol_type}".to_sym] = binding[:address]
            values["netmask#{ip_protocol_type}".to_sym] = binding[:netmask]
            values["network#{ip_protocol_type}".to_sym] = binding[:network]
            values[:scope6] = get_scope(binding[:address]) unless ipv4_type
          end
        end
      end
    end
  end
end
