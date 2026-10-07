# Worked IP/CIDR/subnet examples from ip.md (run inside the container by demo.sh)
import ipaddress as ip
for cidr in ["120.27.1.0/8", "197.23.45.10/24", "192.168.10.0/26"]:
    n = ip.ip_interface(cidr).network
    first, last = n.network_address + 1, n.broadcast_address - 1
    print(f"{cidr:17} network={n.network_address} mask={n.netmask} broadcast={n.broadcast_address}")
    print(f"{'':17} network bits={n.prefixlen} host bits={32-n.prefixlen} "
          f"total=2^{32-n.prefixlen}={n.num_addresses} usable={n.num_addresses-2} "
          f"range={first}-{last}")
print()
print("Split 192.168.10.0/24 into 4 subnets (/26):")
for s in ip.ip_network("192.168.10.0/24").subnets(new_prefix=26):
    h = (s.network_address + 1, s.broadcast_address - 1)
    print(f"  {s}  hosts {h[0]} - {h[-1]}  broadcast {s.broadcast_address}")
print()
for a in ["10.20.30.40", "172.16.5.4", "192.168.1.1", "172.30.4.2", "8.8.8.8", "197.23.45.10"]:
    print(f"  {a:13} private={ip.ip_address(a).is_private}")
