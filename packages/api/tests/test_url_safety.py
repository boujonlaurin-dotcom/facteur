import socket

import pytest

from app.utils.url_safety import validate_url_for_fetch


def _addrinfo(address: str):
    return [
        (
            socket.AF_INET6 if ":" in address else socket.AF_INET,
            socket.SOCK_STREAM,
            6,
            "",
            (address, 443),
        )
    ]


@pytest.mark.parametrize(
    "url",
    [
        "http://localhost/feed",
        "http://localhost.localdomain/feed",
        "http://127.0.0.1/feed",
        "http://[::1]/feed",
        "http://10.0.0.1/feed",
        "http://172.16.0.1/feed",
        "http://192.168.0.1/feed",
        "http://169.254.169.254/latest/meta-data",
        "http://0.0.0.0/feed",
        "ftp://example.com/feed",
        "file:///etc/passwd",
    ],
)
def test_validate_url_for_fetch_rejects_internal_and_non_http(url):
    with pytest.raises(ValueError):
        validate_url_for_fetch(url)


def test_validate_url_for_fetch_rejects_hostname_resolving_private(monkeypatch):
    def private_addrinfo(host, port, family=0, type=0, proto=0, flags=0):
        return _addrinfo("10.1.2.3")

    monkeypatch.setattr(socket, "getaddrinfo", private_addrinfo)

    with pytest.raises(ValueError, match="blocked"):
        validate_url_for_fetch("https://feeds.example.com/rss.xml")


@pytest.mark.parametrize(
    "url",
    [
        "https://www.example.com/feed",
        "https://vert.eco",
    ],
)
def test_validate_url_for_fetch_allows_public_hosts(monkeypatch, url):
    def public_addrinfo(host, port, family=0, type=0, proto=0, flags=0):
        return _addrinfo("93.184.216.34")

    monkeypatch.setattr(socket, "getaddrinfo", public_addrinfo)

    assert validate_url_for_fetch(url) == url
