import paramiko

def run_commands(host, port, username, password):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(host, port=port, username=username, password=password, timeout=10)
        
        commands = [
            "tail -n 60 /opt/aimilivpn/vpngate_data/vpngate.log",
            "ls -la /opt/aimilivpn/vpngate_data/logs/",
            "tail -n 30 /opt/aimilivpn/vpngate_data/logs/$(date +%Y-%m-%d).json 2>/dev/null || echo 'No logs for today'"
        ]
        for cmd in commands:
            print("="*60)
            print(f"Running command: {cmd}")
            print("="*60)
            stdin, stdout, stderr = client.exec_command(cmd)
            print(stdout.read().decode('utf-8', errors='replace'))
    finally:
        client.close()

if __name__ == "__main__":
    run_commands("107.175.230.117", 22, "root", "9Qet0EcR6P4h1n8LPg")
