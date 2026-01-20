
print("starting debug")
try:
    with open("debug_out.txt", "w") as f:
        f.write("DEBUG WORKED\n")
    print("wrote file")
except Exception as e:
    print(f"Error: {e}")
