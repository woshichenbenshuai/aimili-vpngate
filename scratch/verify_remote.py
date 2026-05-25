import paramiko
import time

def run_verification(host, port, username, password):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print(f"Connecting to {host}:{port}...")
        client.connect(host, port=port, username=username, password=password, timeout=10)
        print("Connected successfully!\n")

        commands = [
            # Check current daemon state (should be disconnected, since we just restarted it)
            "curl -s http://127.0.0.1:8787/EJsW2EeBo9lY/api/nodes | python3 -c 'import sys, json; data=json.load(sys.stdin); print(json.dumps(data[\"state\"], indent=2))'",
            
            # Trigger manual update/refresh of nodes
            "curl -s -X POST http://127.0.0.1:8787/EJsW2EeBo9lY/api/refresh_nodes",
            
            # Wait a few seconds for the background fetch to initiate
            "sleep 3",
            
            # Query state again to see if state is updated (valid_nodes and last_check_message should change)
            "curl -s http://127.0.0.1:8787/EJsW2EeBo9lY/api/nodes | python3 -c 'import sys, json; data=json.load(sys.stdin); print(json.dumps(data[\"state\"], indent=2))'",
            
            # Check syslog to see if there are any [警告] tun0 warnings (there should be none, since we are disconnected but active_openvpn_node_id is empty)
            "tail -n 30 /var/log/syslog | grep -E 'vpngate_manager|python3' || echo 'No vpngate syslog entries found'"
        ]

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
    run_verification("107.175.230.117", 22, "root", "9Qet0EcR6P4h1n8LPg")
