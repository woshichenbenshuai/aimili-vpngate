import paramiko
import sys
import os

def deploy(host, port, username, password, files_to_upload):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print(f"Connecting to {host}:{port}...")
        ssh.connect(host, port=port, username=username, password=password, timeout=10)
        print("Connected successfully!")

        # SFTP transfer
        sftp = ssh.open_sftp()
        for local_path, remote_path in files_to_upload:
            print(f"Uploading {local_path} to {remote_path} (with CRLF->LF conversion)...")
            with open(local_path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
            content_lf = content.replace('\r\n', '\n')
            with sftp.open(remote_path, 'wb') as remote_file:
                remote_file.write(content_lf.encode('utf-8'))
        sftp.close()
        print("Uploads complete!")

        # Run installation / upgrade commands
        commands = [
            "systemctl stop aimilivpn || true",
            "pkill -f openvpn || true",
            "ip rule del table 100 2>/dev/null || true",
            "ip route flush table 100 2>/dev/null || true",
            "cd /opt/aimilivpn && bash install.sh baoweise-bot aimili-vpngate",
            "sleep 3",
            "systemctl status aimilivpn",
            "ls -la /usr/bin/ml",
            "ml status"
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
        [
            (r"c:\Users\Hmily\Desktop\AimiliVPN-OpenSource\vpngate_manager.py", "/opt/aimilivpn/vpngate_manager.py"),
            (r"c:\Users\Hmily\Desktop\AimiliVPN-OpenSource\install.sh", "/opt/aimilivpn/install.sh")
        ]
    )
