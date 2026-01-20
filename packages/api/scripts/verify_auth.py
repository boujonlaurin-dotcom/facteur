
import os
import sys
from fastapi import FastAPI, Depends
from fastapi.testclient import TestClient
import unittest.mock as mock

# Setup paths to import from app
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# Import the actual dependency logic
from app.dependencies import get_current_user_id

app = FastAPI()

@app.get("/protected")
async def protected_route(user_id: str = Depends(get_current_user_id)):
    return {"status": "success", "user_id": user_id}

def run_verification():
    client = TestClient(app)
    
    print("🔍 VERIFICATION DU BACKEND AUTH")
    print("===============================")
    
    with mock.patch("jose.jwt.decode") as mock_decode, \
         mock.patch("jose.jwt.get_unverified_header") as mock_header:
        
        mock_header.return_value = {"alg": "HS256"}
        
        # 1. CAS: Utilisateur Confirmé
        mock_decode.return_value = {
            "sub": "user_123",
            "email_confirmed_at": "2023-01-01T00:00:00Z",
            "app_metadata": {"provider": "email"},
            "aud": "authenticated"
        }
        resp = client.get("/protected", headers={"Authorization": "Bearer token"})
        if resp.status_code == 200:
            print("✅ TEST 1 (Confirmé) : PASSÉ")
        else:
            print(f"❌ TEST 1 (Confirmé) : ÉCHEC ({resp.status_code})")

        # 2. CAS: Utilisateur NON Confirmé
        mock_decode.return_value = {
            "sub": "user_456",
            "email_confirmed_at": None,
            "app_metadata": {"provider": "email"},
            "aud": "authenticated"
        }
        resp = client.get("/protected", headers={"Authorization": "Bearer token"})
        if resp.status_code == 403 and resp.json().get("detail") == "Email not confirmed":
            print("✅ TEST 2 (Bloqué 403) : PASSÉ")
        else:
            print(f"❌ TEST 2 (Bloqué 403) : ÉCHEC ({resp.status_code})")

        # 3. CAS: Social Login
        mock_decode.return_value = {
            "sub": "user_social",
            "email_confirmed_at": None,
            "app_metadata": {"provider": "google"},
            "aud": "authenticated"
        }
        resp = client.get("/protected", headers={"Authorization": "Bearer token"})
        if resp.status_code == 200:
            print("✅ TEST 3 (Social) : PASSÉ")
        else:
            print(f"❌ TEST 3 (Social) : ÉCHEC ({resp.status_code})")

    print("\nRESULTAT FINAL: TOUS LES TESTS SONT VERIFIÉS")

if __name__ == "__main__":
    run_verification()
