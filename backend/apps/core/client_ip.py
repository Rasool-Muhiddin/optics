"""
Real client IP behind reverse proxies (nginx locally, Cloudflare in front of it).

Forwarding headers are trusted only when they were added by a proxy listed in
`settings.TRUSTED_PROXIES` (IPs or CIDRs). With no trusted proxies (development, or a
client talking straight to gunicorn) the headers are ignored, so a client cannot spoof
its IP to dodge the auth throttle.

Order of preference once the direct peer is trusted:
1. `CF-Connecting-IP`, but only if the hop that reached our proxy is itself trusted
   (a Cloudflare edge address) — otherwise anyone could send that header.
2. `X-Forwarded-For`, walked right-to-left skipping trusted hops; the first untrusted
   address is the client.
"""

import ipaddress
from functools import lru_cache

from django.conf import settings


@lru_cache(maxsize=8)
def _networks(entries):
    return tuple(ipaddress.ip_network(entry.strip(), strict=False) for entry in entries if entry.strip())


def _parse(value):
    try:
        return ipaddress.ip_address((value or "").strip())
    except ValueError:
        return None


def _is_trusted(address, networks):
    return address is not None and any(address in net for net in networks)


def get_client_ip(request):
    """The originating client's IP as a string (falls back to `REMOTE_ADDR`)."""
    meta = request.META
    remote = meta.get("REMOTE_ADDR", "")
    networks = _networks(tuple(getattr(settings, "TRUSTED_PROXIES", ()) or ()))
    if not networks or not _is_trusted(_parse(remote), networks):
        return remote

    forwarded = [part.strip() for part in meta.get("HTTP_X_FORWARDED_FOR", "").split(",") if part.strip()]
    chain = [_parse(part) for part in forwarded]

    cf_ip = _parse(meta.get("HTTP_CF_CONNECTING_IP"))
    if cf_ip is not None:
        # The peer of our local proxy is the last X-Forwarded-For entry (or the peer itself
        # when the edge talks to gunicorn directly). It must be trusted (Cloudflare range).
        upstream = chain[-1] if chain else _parse(remote)
        if _is_trusted(upstream, networks):
            return str(cf_ip)

    for address in reversed(chain):
        if address is None:
            break  # garbage in the header: stop trusting anything further left
        if not _is_trusted(address, networks):
            return str(address)
    # Every hop is a trusted proxy: the left-most valid one is the best we know.
    for address in chain:
        if address is not None:
            return str(address)
    return remote
