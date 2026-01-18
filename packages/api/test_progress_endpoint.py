import urllib.request
import urllib.error
import time

ports_to_test = [8080, 8000]

print("\n🔍 Testing backend connectivity...\n")

server_found = False

for port in ports_to_test:
    base_url = f"http://localhost:{port}"
    print(f"--- Checking Port {port} ---")
    
    # Just check health first
    health_url = f"{base_url}/api/health"
    try:
        req = urllib.request.Request(health_url)
        with urllib.request.urlopen(req, timeout=1) as response:
            print(f"✅ Backend FOUND on port {port} (Status: {response.getcode()})")
            server_found = True
            
            # Now check progress endpoint on this port
            progress_url = f"{base_url}/api/progress/"
            print(f"👉 Testing {progress_url}...")
            try:
                req_prog = urllib.request.Request(progress_url)
                # Add a dummy auth header to potentially provoke a 401 instead of 403 if needed, 
                # but standard check is enough.
                with urllib.request.urlopen(req_prog, timeout=1) as resp_prog:
                    print(f"   ✅ Route EXISTS (Status: {resp_prog.getcode()})")
            except urllib.error.HTTPError as e:
                if e.code == 404:
                     print(f"   ❌ Route MISSING (Status: 404) - Backend runs but route is not registered.")
                elif e.code in (401, 403):
                     print(f"   ✅ Route EXISTS but requires Auth (Status: {e.code}) - Success!")
                else:
                     print(f"   ⚠️ Unexpected Status: {e.code}")
            except Exception as e:
                print(f"   ⚠️ Error checking progress: {e}")
                
            break # Stop checking other ports if found
            
    except urllib.error.URLError as e:
        print(f"❌ Nothing on port {port} (Connection Refused)")
    except Exception as e:
        print(f"❌ Error on port {port}: {e}")

print("\n-------------------------------------------")
if not server_found:
    print("💥 ALERTE: Aucun serveur backend détecté !")
    print("👉 Vous devez lancer 'uvicorn' dans un AUTRE terminal et le laisser tourner.")
else:
    print("Analyze terminée.")
print("-------------------------------------------")
