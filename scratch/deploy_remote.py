import paramiko
import sys
import os

def deploy(host, port, username, password, files_to_upload):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print(f"Connecting to {host}:{port}...")
        ssh.connect(host, port=port, username=username, password=password, timeout=10, look_for_keys=False, allow_agent=False)
        print("Connected successfully!")

        # Ensure dir and dev mode file exist
        print("Ensuring /opt/aimilivpn directory and local dev mode exist on VPS...")
        stdin, stdout, stderr = ssh.exec_command("mkdir -p /opt/aimilivpn && touch /opt/aimilivpn/.local_dev")
        stdout.read() # block until command finishes

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
            "systemctl stop unattended-upgrades || true",
            "killall -9 apt apt-get dpkg unattended-upgr 2>/dev/null || true",
            "rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock 2>/dev/null || true",
            "dpkg --configure -a || true",
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
    import json
    config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "服务器连接配置_不要上传到GITHUB.json")
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    
    deploy(
        config["host"], 
        config["port"], 
        config["username"], 
        config["password"], 
        [
            (os.path.join(os.path.dirname(os.path.dirname(__file__)), "vpngate_manager.py"), "/opt/aimilivpn/vpngate_manager.py"),
            (os.path.join(os.path.dirname(os.path.dirname(__file__)), "vpn_utils.py"), "/opt/aimilivpn/vpn_utils.py"),
            (os.path.join(os.path.dirname(os.path.dirname(__file__)), "install.sh"), "/opt/aimilivpn/install.sh")
        ]
    )
