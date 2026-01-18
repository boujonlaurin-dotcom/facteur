import urllib.request
import urllib.error
import time
import socket

def measure(name, url):
    print(f"⏱️ Mesure {name} ({url})...")
    start = time.time()
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=12) as response:
            duration = time.time() - start
            print(f"   ✅ Succès: {duration:.2f}s (Code: {response.getcode()})")
            return duration
    except Exception as e:
        duration = time.time() - start
        print(f"   ❌ Échec après {duration:.2f}s: {e}")
        return None

print("--- DIAGNOSTIC PERFORMANCE BACKEND ---")

# 1. Test Loopback (Ultra rapide normalement)
measure("Health Check (Local)", "http://localhost:8080/api/health")

# 2. Test DNS/Remote (Supabase)
print("\n🔍 Test DNS Supabase...")
try:
    start = time.time()
    # On essaye de résoudre l'adresse de l'API de base
    # (Remplacez par votre URL supabase si différente)
    socket.gethostbyname("ykuadtelnzavrqzbfdve.supabase.co")
    print(f"   ✅ DNS Résolu en {time.time()-start:.2f}s")
except Exception as e:
    print(f"   ❌ Échec DNS: {e}")

# 3. Test latency vers Supabase Auth (utilisé par le backend pour fetch JWKS)
measure("Supabase Auth (Remote)", "https://ykuadtelnzavrqzbfdve.supabase.co/auth/v1/health")

print("\n--- ANALYSE ---")
print("1. Si 'Health Check (Local)' est lent (>1s) : Le serveur Python est saturé ou bloqué (ex: pool DB).")
print("2. Si 'Supabase Auth' est lent (>5s) : Votre connexion internet ou les serveurs Supabase rament.")
print("3. Si TOUT est rapide ici mais lent sur mobile : C'est un problème de réseau Mobile -> Mac (localhost/10.0.2.2).")
print("---------------------------------------")
