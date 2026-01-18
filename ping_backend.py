import urllib.request
import urllib.error
import time

url = "http://localhost:8080/api/health"
print(f"🔍 Pinging {url}...")

start = time.time()
try:
    with urllib.request.urlopen(url, timeout=5) as response:
        duration = time.time() - start
        print(f"✅ Status: {response.getcode()}")
        print(f"⏱️ Time: {duration:.2f}s")
        print(f"📄 Response: {response.read().decode('utf-8')[:100]}")
except Exception as e:
    print(f"💥 Failed: {e}")

print("\n------------------------------")
print("Si ce script réussit, le serveur backend va bien.")
print("Si l'app mobile timeout, c'est probablement car 'localhost' n'est pas accessible depuis l'émulateur (utiliser 10.0.2.2) ou le device.")
print("------------------------------")
