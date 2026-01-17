#!/usr/bin/env python3
"""
Serveur local pour tester CORS depuis un vrai origin HTTP.
Usage: python3 serve_test.py
Puis ouvrir http://localhost:8888/cors_test.html
"""
import http.server
import socketserver
import os

PORT = 8888
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

os.chdir(DIRECTORY)
print(f"🌐 Serving {DIRECTORY} at http://localhost:{PORT}")
print(f"📋 Open: http://localhost:{PORT}/cors_test.html")

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 Server stopped")
