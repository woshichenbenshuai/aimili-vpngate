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
        "grep -n -C 5 \"def active_node_pinger\" /opt/aimilivpn/vpngate_manager.py"
    ]
    import json
    import os
    config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "服务器连接配置_不要上传到GITHUB.json")
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    run_commands(config["host"], config["port"], config["username"], config["password"], commands)
