"""Outbound URL safety checks for user-supplied fetch targets."""

from __future__ import annotations

import ipaddress
import socket
from urllib.parse import urlparse

_ALLOWED_SCHEMES = {"http", "https"}
_METADATA_IP = ipaddress.ip_address("169.254.169.254")


def _normalize_hostname(hostname: str | None) -> str:
    if not hostname:
        raise ValueError("URL must include a hostname")

    host = hostname.strip().strip(".").lower()
    if not host:
        raise ValueError("URL must include a hostname")

    try:
        return host.encode("idna").decode("ascii")
    except UnicodeError as exc:
        raise ValueError("URL hostname is invalid") from exc


def _is_localhost_name(host: str) -> bool:
    return (
        host == "localhost"
        or host.endswith(".localhost")
        or host == "localhost.localdomain"
        or host.endswith(".localhost.localdomain")
    )


def _blocked_ip_reason(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> str | None:
    if ip == _METADATA_IP:
        return "metadata address"
    if ip.is_private:
        return "private address"
    if ip.is_loopback:
        return "loopback address"
    if ip.is_link_local:
        return "link-local address"
    if ip.is_multicast:
        return "multicast address"
    if ip.is_unspecified:
        return "unspecified address"
    if ip.is_reserved:
        return "reserved address"
    return None


def _validate_ip(ip_text: str) -> None:
    try:
        ip = ipaddress.ip_address(ip_text)
    except ValueError as exc:
        raise ValueError(f"Resolved IP address is invalid: {ip_text}") from exc

    reason = _blocked_ip_reason(ip)
    if reason:
        raise ValueError(f"URL host resolves to blocked {reason}: {ip}")


def validate_url_for_fetch(url: str) -> str:
    """Validate that a URL is safe to fetch from the API server.

    The check intentionally fails closed: a hostname must resolve, and every
    returned address must be publicly routable.
    """
    parsed = urlparse(url)
    scheme = parsed.scheme.lower()
    if scheme not in _ALLOWED_SCHEMES:
        raise ValueError("URL scheme must be http or https")

    host = _normalize_hostname(parsed.hostname)
    if _is_localhost_name(host):
        raise ValueError("URL hostname is not allowed")

    try:
        literal_ip = ipaddress.ip_address(host)
    except ValueError:
        literal_ip = None

    if literal_ip is not None:
        reason = _blocked_ip_reason(literal_ip)
        if reason:
            raise ValueError(f"URL host is blocked {reason}: {literal_ip}")
        return url

    try:
        resolved = socket.getaddrinfo(host, parsed.port, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise ValueError(f"URL hostname could not be resolved: {host}") from exc

    addresses = {info[4][0] for info in resolved}
    if not addresses:
        raise ValueError(f"URL hostname could not be resolved: {host}")

    for address in addresses:
        _validate_ip(address)

    return url
