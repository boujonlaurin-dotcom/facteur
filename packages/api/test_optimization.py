import asyncio
import os
import sys

sys.path.append(os.getcwd())

from app.services.sync_service import SyncService
from unittest.mock import MagicMock

def test_optimization():
    service = SyncService(MagicMock())
    
    # 1. Courrier International
    url_ci = "https://focus.courrierinternational.com/2026/01/09/0/0/3992/8735/644/0/60/0/ba2f037_upload.jpg"
    optimized_ci = service._optimize_thumbnail_url(url_ci)
    print(f"CI Original:  {url_ci}")
    print(f"CI Optimized: {optimized_ci}")
    assert "/1200/" in optimized_ci
    
    # 2. WordPress
    url_wp = "https://example.com/wp-content/uploads/2023/01/image-150x150.jpg"
    optimized_wp = service._optimize_thumbnail_url(url_wp)
    print(f"WP Original:  {url_wp}")
    print(f"WP Optimized: {optimized_wp}")
    assert "image.jpg" in optimized_wp
    
    # 3. Standard
    url_std = "https://example.com/photo.png"
    optimized_std = service._optimize_thumbnail_url(url_std)
    assert optimized_std == url_std
    print("Standard URL: No change (Passed)")

    print("\nALL OPTIMIZATION TESTS PASSED")

if __name__ == "__main__":
    test_optimization()
