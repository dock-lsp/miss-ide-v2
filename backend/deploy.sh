#!/bin/bash
# Miss IDE 后端一键部署脚本
# 在阿里云服务器上执行此脚本

set -e

echo "=== Miss IDE Build Server 部署 ==="

# 配置
SERVER_IP="47.92.220.102"
BUILD_DIR="/opt/build-server"
FLUTTER_PATH="/opt/flutter/bin/flutter"
ANDROID_HOME="/opt/android-sdk"

# 1. 检查 Flutter 环境
echo "[1/6] 检查 Flutter 环境..."
if [ ! -f "$FLUTTER_PATH" ]; then
    echo "错误: Flutter 未安装"
    echo "请先安装 Flutter: "
    echo "  cd /opt && git clone https://github.com/flutter/flutter.git -b stable"
    echo "  export PATH=\"\$PATH:/opt/flutter/bin\""
    echo "  flutter doctor"
    exit 1
fi

$FLUTTER_PATH --version
echo "Flutter 环境正常 ✓"

# 2. 创建目录
echo "[2/6] 创建目录..."
mkdir -p $BUILD_DIR/{builds,workspace,logs}
mkdir -p $BUILD_DIR

# 3. 安装 Python 依赖
echo "[3/6] 安装 Python 依赖..."
pip3 install flask flask-cors -q

# 4. 创建构建服务文件
echo "[4/6] 创建构建服务..."
cat > $BUILD_DIR/build_api.py << 'PYTHONEOF'
#!/usr/bin/env python3
import os
import uuid
import shutil
import subprocess
from datetime import datetime
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import threading
import zipfile
import glob

app = Flask(__name__)
CORS(app)

BUILD_DIR = '/opt/build-server/builds'
WORK_DIR = '/opt/build-server/workspace'
FLUTTER_PATH = '/opt/flutter/bin/flutter'
ANDROID_HOME = '/opt/android-sdk'

os.makedirs(BUILD_DIR, exist_ok=True)
os.makedirs(WORK_DIR, exist_ok=True)

build_status = {}

@app.route('/api/build/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'ok',
        'service': 'Miss IDE Build Server',
        'flutter': os.path.exists(FLUTTER_PATH)
    })

@app.route('/api/build/upload', methods=['POST'])
def upload_project():
    try:
        build_id = str(uuid.uuid4())[:8]
        project_dir = os.path.join(WORK_DIR, build_id)
        os.makedirs(project_dir, exist_ok=True)
        
        if 'project' in request.files:
            file = request.files['project']
            if file.filename.endswith('.zip'):
                zip_path = os.path.join(project_dir, 'project.zip')
                file.save(zip_path)
                with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                    zip_ref.extractall(project_dir)
                os.remove(zip_path)
        
        build_type = request.form.get('type', 'debug')
        
        build_status[build_id] = {
            'id': build_id,
            'status': 'pending',
            'type': build_type,
            'project_path': project_dir,
            'created_at': str(datetime.now()),
            'logs': []
        }
        
        threading.Thread(target=build_apk, args=(build_id, project_dir, build_type)).start()
        
        return jsonify({
            'build_id': build_id,
            'status': 'pending',
            'message': '构建已启动'
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/build/status/<build_id>', methods=['GET'])
def get_status(build_id):
    if build_id not in build_status:
        return jsonify({'error': 'Build not found'}), 404
    
    status = build_status[build_id].copy()
    status['apk_url'] = f'/api/build/download/{build_id}' if status.get('status') == 'success' else None
    return jsonify(status)

@app.route('/api/build/download/<build_id>', methods=['GET'])
def download_apk(build_id):
    apk_path = os.path.join(BUILD_DIR, f'{build_id}.apk')
    if os.path.exists(apk_path):
        return send_file(apk_path, as_attachment=True)
    return jsonify({'error': 'APK not found'}), 404

def build_apk(build_id, project_dir, build_type):
    status = build_status[build_id]
    
    try:
        status['status'] = 'running'
        status['logs'].append('正在分析项目...')
        
        flutter_project = find_flutter_project(project_dir)
        
        if not flutter_project:
            status['logs'].append('创建 Flutter 项目...')
            flutter_project = create_flutter_wrapper(project_dir)
        
        env = {
            **os.environ,
            'ANDROID_HOME': ANDROID_HOME,
            'PATH': f"{os.environ.get('PATH', '')}:{FLUTTER_PATH.replace('/flutter', '')}:{ANDROID_HOME}/cmdline-tools/latest/bin"
        }
        
        status['logs'].append('获取依赖...')
        subprocess.run([FLUTTER_PATH, 'pub', 'get'], cwd=flutter_project, capture_output=True, env=env, timeout=300)
        
        status['logs'].append(f'构建 APK ({build_type})...')
        cmd = [FLUTTER_PATH, 'build', 'apk', '--debug' if build_type == 'debug' else '--release']
        result = subprocess.run(cmd, cwd=flutter_project, capture_output=True, env=env, timeout=600)
        
        if result.returncode == 0:
            apks = glob.glob(os.path.join(flutter_project, 'build', 'app', 'outputs', 'flutter-apk', '*.apk'))
            if apks:
                shutil.copy(apks[0], os.path.join(BUILD_DIR, f'{build_id}.apk'))
                status['status'] = 'success'
                status['apk_url'] = f'/api/build/download/{build_id}'
                status['logs'].append(f'构建成功！')
            else:
                status['status'] = 'failure'
                status['error'] = 'APK 未找到'
        else:
            status['status'] = 'failure'
            status['error'] = result.stderr.decode()[:500]
    
    except Exception as e:
        status['status'] = 'failure'
        status['error'] = str(e)
    
    status['completed_at'] = str(datetime.now())

def find_flutter_project(directory):
    for root, dirs, files in os.walk(directory):
        if 'pubspec.yaml' in files and 'flutter_wrapper' not in root:
            return root
    return None

def create_flutter_wrapper(directory):
    wrapper_dir = os.path.join(directory, 'flutter_wrapper')
    os.makedirs(wrapper_dir + '/lib', exist_ok=True)
    
    with open(os.path.join(wrapper_dir, 'pubspec.yaml'), 'w') as f:
        f.write('name: app\nversion: 1.0.0\n\nenvironment:\n  sdk: ">=3.0.0"\n\ndependencies:\n  flutter:\n    sdk: flutter\n\nflutter:\n  uses-material-design: true\n')
    
    with open(os.path.join(wrapper_dir, 'lib', 'main.dart'), 'w') as f:
        f.write("import 'package:flutter/material.dart';\nvoid main() => runApp(MaterialApp(home: Scaffold(body: Center(child: Text('Hello from Miss IDE')))));")
    
    return wrapper_dir

if __name__ == '__main__':
    print('Miss IDE Build Server starting on port 8080...')
    app.run(host='0.0.0.0', port=8080, threaded=True)
PYTHONEOF

chmod +x $BUILD_DIR/build_api.py

# 5. 创建 systemd 服务
echo "[5/6] 创建系统服务..."
cat > /etc/systemd/system/miss-ide-build.service << 'SVCEOF'
[Unit]
Description=Miss IDE Build Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/build-server
ExecStart=/usr/bin/python3 /opt/build-server/build_api.py
Restart=always
RestartSec=10
Environment=ANDROID_HOME=/opt/android-sdk
Environment=PATH=/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SVCEOF

# 6. 启动服务
echo "[6/6] 启动服务..."
systemctl daemon-reload
systemctl enable miss-ide-build
systemctl restart miss-ide-build

sleep 3

echo ""
echo "=== 部署完成 ==="
echo ""
systemctl status miss-ide-build --no-pager

echo ""
echo "验证 API..."
curl -s http://localhost:8080/api/build/health

echo ""
echo ""
echo "✓ 服务已启动"
echo "API 地址: http://$SERVER_IP:8080"
echo ""
echo "常用命令:"
echo "  查看状态: systemctl status miss-ide-build"
echo "  查看日志: journalctl -u miss-ide-build -f"
echo "  重启服务: systemctl restart miss-ide-build"
