"""Real client IP behind nginx + Cloudflare (used by the desktop auth throttle)."""

from django.core.cache import cache
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APIRequestFactory

from apps.core.client_ip import get_client_ip
from apps.core.testing import LabAPITestCase
from config.settings.proxies import CLOUDFLARE_IP_RANGES

PROD_PROXIES = ["127.0.0.1/32", "::1/128", *CLOUDFLARE_IP_RANGES]
CF_EDGE = "172.68.1.10"  # inside 172.64.0.0/13


def _request(remote="127.0.0.1", **headers):
    return APIRequestFactory().get("/", REMOTE_ADDR=remote, **headers)


class ClientIPTests(SimpleTestCase):
    @override_settings(TRUSTED_PROXIES=[])
    def test_without_trusted_proxies_headers_are_ignored(self):
        request = _request("10.0.0.5", HTTP_X_FORWARDED_FOR="1.2.3.4", HTTP_CF_CONNECTING_IP="5.6.7.8")
        self.assertEqual(get_client_ip(request), "10.0.0.5")

    @override_settings(TRUSTED_PROXIES=PROD_PROXIES)
    def test_cloudflare_then_nginx_uses_cf_connecting_ip(self):
        request = _request(HTTP_X_FORWARDED_FOR=f"9.9.9.9, {CF_EDGE}", HTTP_CF_CONNECTING_IP="9.9.9.9")
        self.assertEqual(get_client_ip(request), "9.9.9.9")

    @override_settings(TRUSTED_PROXIES=PROD_PROXIES)
    def test_spoofed_cf_header_from_non_cloudflare_peer_is_ignored(self):
        # The attacker hits nginx directly (bypassing Cloudflare) and forges both headers.
        request = _request(HTTP_X_FORWARDED_FOR="1.1.1.1, 203.0.113.7", HTTP_CF_CONNECTING_IP="1.1.1.1")
        self.assertEqual(get_client_ip(request), "203.0.113.7")

    @override_settings(TRUSTED_PROXIES=PROD_PROXIES)
    def test_x_forwarded_for_walks_past_trusted_hops(self):
        request = _request(HTTP_X_FORWARDED_FOR=f"8.8.4.4, {CF_EDGE}")
        self.assertEqual(get_client_ip(request), "8.8.4.4")

    @override_settings(TRUSTED_PROXIES=PROD_PROXIES)
    def test_untrusted_peer_cannot_inject_headers(self):
        request = _request("198.51.100.20", HTTP_X_FORWARDED_FOR="8.8.8.8", HTTP_CF_CONNECTING_IP="8.8.8.8")
        self.assertEqual(get_client_ip(request), "198.51.100.20")

    @override_settings(TRUSTED_PROXIES=PROD_PROXIES)
    def test_garbage_header_falls_back_safely(self):
        request = _request(HTTP_X_FORWARDED_FOR="not-an-ip, 203.0.113.9", HTTP_CF_CONNECTING_IP="nope")
        self.assertEqual(get_client_ip(request), "203.0.113.9")

    @override_settings(TRUSTED_PROXIES=PROD_PROXIES)
    def test_ipv6_client(self):
        request = _request(HTTP_X_FORWARDED_FOR=f"2001:db8::1, {CF_EDGE}", HTTP_CF_CONNECTING_IP="2001:db8::1")
        self.assertEqual(get_client_ip(request), "2001:db8::1")


@override_settings(TRUSTED_PROXIES=PROD_PROXIES)
class AuthThrottleByRealIPTests(LabAPITestCase):
    """Behind the proxies every request has REMOTE_ADDR=127.0.0.1; buckets must be per client."""

    def _activate(self, client_ip):
        return self.client.post(
            "/api/v1/desktop/activate/",
            {"activation_code": "NOPE", "device_id": "x"},
            REMOTE_ADDR="127.0.0.1",
            HTTP_X_FORWARDED_FOR=f"{client_ip}, {CF_EDGE}",
            HTTP_CF_CONNECTING_IP=client_ip,
        )

    def test_throttle_is_per_real_client_ip(self):
        from rest_framework.settings import api_settings
        from rest_framework.throttling import SimpleRateThrottle

        rates = {**api_settings.DEFAULT_THROTTLE_RATES, "desktop_auth": "3/min"}
        original = SimpleRateThrottle.THROTTLE_RATES
        SimpleRateThrottle.THROTTLE_RATES = rates
        self.addCleanup(setattr, SimpleRateThrottle, "THROTTLE_RATES", original)
        cache.clear()

        for _ in range(3):
            self.assertEqual(self._activate("9.9.9.9").status_code, 400)
        self.assertEqual(self._activate("9.9.9.9").status_code, 429)
        # Another customer behind the same nginx/Cloudflare is not affected.
        self.assertEqual(self._activate("8.8.8.8").status_code, 400)
