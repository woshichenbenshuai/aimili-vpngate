import paramiko

def run_commands(host, port, username, password, commands):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print(f"Connecting to {host}:{port}...")
        client.connect(host, port=port, username=username, password=password, timeout=10)
        print("Connected successfully!\n")
        
        for cmd in commands:
            print("="*60)
            print(f"Running command: {cmd}")
            print("="*60)
            stdin, stdout, stderr = client.exec_command(cmd)
            out = stdout.read().decode('utf-8', errors='replace')
            err = stderr.read().decode('utf-8', errors='replace')
            if out:
                print(out)
            if err:
                print("stderr:")
                print(err)
            print("\n")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        client.close()

if __name__ == "__main__":
    commands = [
        "cat /opt/aimilivpn/vpngate_data/state.json",
        "curl -s http://127.0.0.1:8787/EJsW2EeBo9lY/api/nodes | python3 -c 'import sys, json; data=json.load(sys.stdin); print(json.dumps(data[\"state\"], indent=2))'",
        "curl -s http://127.0.0.1:8787/EJsW2EeBo9lY/api/nodes | python3 -c 'import sys, json; data=json.load(sys.stdin); print(\"Total nodes:\", len(data[\"nodes\"])); print(\"Active nodes:\", [n[\"id\"] for n in data[\"nodes\"] if n.get(\"active\")])'",
        "curl -s -X POST http://127.0.0.1:8787/EJsW2EeBo9lY/api/test_proxy | python3 -m json.tool"
    ]
    run_commands("107.175.230.117", 22, "root", "9Qet0EcR6P4h1n8LPg", commands)
