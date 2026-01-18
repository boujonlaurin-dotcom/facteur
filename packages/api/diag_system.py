import socket
import os
import subprocess
import json

def check_port(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('localhost', port)) == 0

def get_processes():
    try:
        # ps aux is better on Mac
        return subprocess.check_output(['ps', 'aux']).decode()
    except Exception as e:
        return f"Failed to get processes: {e}"

if __name__ == "__main__":
    results = {
        "port_8000": check_port(8000),
        "port_8080": check_port(8080),
        "user": os.environ.get('USER'),
        "pwd": os.getcwd(),
        "python_path": subprocess.check_output(['which', 'python3']).decode().strip(),
        "processes": get_processes()
    }
    with open("diag_results.json", "w") as f:
        json.dump(results, f, indent=4)
