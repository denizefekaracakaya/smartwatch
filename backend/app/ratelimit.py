"""Minimal in-process sliding-window rate limiter (per-instance; see DECISIONS D-012)."""

import threading
import time
from collections import defaultdict, deque

from fastapi import status

from app.errors import ApiError


class RateLimiter:
    def __init__(self, enabled: bool = True):
        self.enabled = enabled
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    @staticmethod
    def parse(rule: str) -> tuple[int, int]:
        count, seconds = rule.split("/", 1)
        return int(count), int(seconds)

    def hit(self, key: str, rule: str) -> None:
        """Record a hit for ``key``; raise 429 if the rule's limit is exceeded."""
        if not self.enabled:
            return
        limit, window = self.parse(rule)
        now = time.monotonic()
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] <= now - window:
                hits.popleft()
            if len(hits) >= limit:
                retry_after = max(1, int(hits[0] + window - now) + 1)
                raise ApiError(
                    status.HTTP_429_TOO_MANY_REQUESTS,
                    "rate_limited",
                    "Too many requests, try again later",
                    headers={"Retry-After": str(retry_after)},
                )
            hits.append(now)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()
