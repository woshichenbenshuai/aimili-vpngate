import paramiko
import sys
import os

def deploy(host, port, username, password, local_path, remote_path):
    # Establish SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print(f"Connecting to {host}:{port}...")
        ssh.connect(host, port=port, username=username, password=password, timeout=10)
        print("Connected successfully!")

        # SFTP transfer
        print(f"Uploading {local_path} to {remote_path}...")
        sftp = ssh.open_sftp()
        sftp.put(local_path, remote_path)
        sftp.close()
        print("Upload complete!")

        # Run post-deployment commands using systemctl
        commands = [
            "systemctl stop aimilivpn || echo 'Failed to stop aimilivpn'",
            "pkill -f vpngate_manager.py || echo 'vpngate_manager.py was not running'",
            "pkill -f openvpn || echo 'openvpn was not running'",
            "ip rule del table 100 2>/dev/null || true",
            "ip route flush table 100 2>/dev/null || true",
            "systemctl start aimilivpn || echo 'Failed to start aimilivpn'",
            "sleep 3",
            "systemctl status aimilivpn",
            "ps aux | grep vpngate_manager.py"
        ]
        
        for cmd in commands:
            print("="*60)
            print(f"Running command: {cmd}")
            print("="*60)
            stdin, stdout, stderr = ssh.exec_command(cmd)
            out = stdout.read().decode('utf-8', errors='replace')
            err = stderr.read().decode('utf-8', errors='replace')
            if out:
                print(out)
            if err:
                print("stderr:")
                print(err)
            print("\n")

    except Exception as e:
        print(f"Deployment error: {e}")
    finally:
        ssh.close()

if __name__ == "__main__":
    deploy(
        "107.175.230.117", 
        22, 
        "root", 
        "9Qet0EcR6P4h1n8LPg", 
        r"c:\Users\Hmily\Desktop\AimiliVPN-OpenSource\vpngate_manager.py", 
        "/opt/aimilivpn/vpngate_manager.py"
    )
