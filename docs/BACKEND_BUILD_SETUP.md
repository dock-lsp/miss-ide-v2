# 阿里云后端构建服务配置指南

## 1. 服务器环境准备

连接到阿里云服务器：
```bash
ssh root@47.92.220.102
```

## 2. 安装 Flutter SDK

```bash
# 安装依赖
apt update && apt install -y git curl unzip xz-utils zip libglu1-mesa

# 安装 Java 17
apt install -y openjdk-17-jdk

# 安装 Android SDK
mkdir -p /opt/android-sdk
cd /opt/android-sdk
wget https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip
unzip commandlinetools-linux-9477386_latest.zip
export ANDROID_HOME=/opt/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/bin
yes | sdkmanager --licenses
sdkmanager "platforms;android-33" "build-tools;33.0.1"

# 安装 Flutter SDK
cd /opt
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:/opt/flutter/bin"
flutter doctor

# 配置环境变量
echo 'export ANDROID_HOME=/opt/android-sdk' >> ~/.bashrc
echo 'export PATH="$PATH:/opt/flutter/bin:$ANDROID_HOME/cmdline-tools/bin:$ANDROID_HOME/platform-tools"' >> ~/.bashrc
source ~/.bashrc
```

## 3. 部署构建 API 服务

创建构建服务脚本 `/opt/build-server/build_api.py`:

```python
#!/usr/bin/env python3
import os
import json
import uuid
import shutil
import subprocess
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import threading
import zipfile

app = Flask(__name__)
CORS(app)

BUILD_DIR = '/opt/build-server/builds'
WORK_DIR = '/opt/build-server/workspace'
os.makedirs(BUILD_DIR, exist_ok=True)
os.makedirs(WORK_DIR, exist_ok=True)

build_status = {}

@app.route('/api/build/upload', methods=['POST'])
def upload_project():
    """上传项目并触发构建"""
    try:
        build_id = str(uuid.uuid4())[:8]
        project_dir = os.path.join(WORK_DIR, build_id)
        os.makedirs(project_dir, exist_ok=True)
        
        # 保存上传的项目文件
        if 'project' in request.files:
            file = request.files['project']
            if file.filename.endswith('.zip'):
                zip_path = os.path.join(project_dir, 'project.zip')
                file.save(zip_path)
                
                # 解压
                with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                    zip_ref.extractall(project_dir)
                os.remove(zip_path)
        
        build_type = request.form.get('type', 'debug')
        
        # 保存构建信息
        build_info = {
            'id': build_id,
            'status': 'pending',
            'type': build_type,
            'project_path': project_dir,
            'created_at': str(datetime.now())
        }
        build_status[build_id] = build_info
        
        # 异步构建
        threading.Thread(target=build_apk, args=(build_id, project_dir, build_type)).start()
        
        return jsonify({
            'build_id': build_id,
            'status': 'pending',
            'message': '构建已启动'
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/build/status/<build_id>', methods=['GET'])
def get_build_status(build_id):
    """获取构建状态"""
    if build_id not in build_status:
        return jsonify({'error': 'Build not found'}), 404
    
    return jsonify(build_status[build_id])

@app.route('/api/build/download/<build_id>', methods=['GET'])
def download_apk(build_id):
    """下载构建完成的 APK"""
    apk_path = os.path.join(BUILD_DIR, f'{build_id}.apk')
    if os.path.exists(apk_path):
        return send_file(apk_path, as_attachment=True)
    return jsonify({'error': 'APK not found'}), 404

def build_apk(build_id, project_dir, build_type):
    """执行 Flutter 构建"""
    global build_status
    
    build_status[build_id]['status'] = 'running'
    
    try:
        # 找到 Flutter 项目目录
        flutter_project = find_flutter_project(project_dir)
        
        if not flutter_project:
            # 如果不是 Flutter 项目，创建一个基础的
            flutter_project = create_flutter_wrapper(project_dir)
        
        # 获取依赖
        subprocess.run(
            ['/opt/flutter/bin/flutter', 'pub', 'get'],
            cwd=flutter_project,
            capture_output=True,
            env={**os.environ, 'ANDROID_HOME': '/opt/android-sdk'}
        )
        
        # 构建 APK
        cmd = ['/opt/flutter/bin/flutter', 'build', 'apk']
        if build_type == 'release':
            cmd.append('--release')
        else:
            cmd.append('--debug')
        
        result = subprocess.run(
            cmd,
            cwd=flutter_project,
            capture_output=True,
            env={**os.environ, 'ANDROID_HOME': '/opt/android-sdk'}
        )
        
        if result.returncode == 0:
            # 复制 APK
            apk_source = os.path.join(flutter_project, 'build', 'app', 'outputs', 'flutter-apk', 'app-*.apk')
            import glob
            apks = glob.glob(apk_source)
            if apks:
                shutil.copy(apks[0], os.path.join(BUILD_DIR, f'{build_id}.apk'))
                build_status[build_id]['status'] = 'success'
                build_status[build_id]['apk_url'] = f'/api/build/download/{build_id}'
            else:
                build_status[build_id]['status'] = 'failure'
                build_status[build_id]['error'] = 'APK not found after build'
        else:
            build_status[build_id]['status'] = 'failure'
            build_status[build_id]['error'] = result.stderr.decode()
    
    except Exception as e:
        build_status[build_id]['status'] = 'failure'
        build_status[build_id]['error'] = str(e)
    
    build_status[build_id]['completed_at'] = str(datetime.now())

def find_flutter_project(directory):
    """查找 Flutter 项目"""
    for root, dirs, files in os.walk(directory):
        if 'pubspec.yaml' in files:
            return root
    return None

def create_flutter_wrapper(directory):
    """为非 Flutter 项目创建包装器"""
    wrapper_dir = os.path.join(directory, 'flutter_wrapper')
    os.makedirs(wrapper_dir, exist_ok=True)
    
    # 创建基础 pubspec.yaml
    pubspec = '''
name: generated_app
description: Auto generated app
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

flutter:
  uses-material-design: true
'''
    with open(os.path.join(wrapper_dir, 'pubspec.yaml'), 'w') as f:
        f.write(pubspec)
    
    # 创建 lib 目录和 main.dart
    lib_dir = os.path.join(wrapper_dir, 'lib')
    os.makedirs(lib_dir, exist_ok=True)
    
    # 这里可以读取原始代码并包装
    main_dart = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Generated App',
      home: Scaffold(
        appBar: AppBar(title: const Text('Generated App')),
        body: const Center(child: Text('Hello World')),
      ),
    );
  }
}
'''
    with open(os.path.join(lib_dir, 'main.dart'), 'w') as f:
        f.write(main_dart)
    
    return wrapper_dir

if __name__ == '__main__':
    from datetime import datetime
    app.run(host='0.0.0.0', port=8080)
```

## 4. 启动服务

```bash
# 安装 Python 依赖
pip3 install flask flask-cors

# 创建目录
mkdir -p /opt/build-server/builds /opt/build-server/workspace

# 启动服务
cd /opt/build-server
nohup python3 build_api.py > build.log 2>&1 &

# 配置 Nginx 反向代理（可选）
# /etc/nginx/sites-available/build-api:
# server {
#     listen 80;
#     server_name 47.92.220.102;
#     
#     location /api/build/ {
#         proxy_pass http://127.0.0.1:8080;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#     }
# }
```

## 5. 验证服务

```bash
# 测试 API
curl http://localhost:8080/api/build/status/test

# 检查服务状态
ps aux | grep build_api
```

## 6. 使用 systemd 管理服务（推荐）

创建 `/etc/systemd/system/build-api.service`:

```ini
[Unit]
Description=Flutter Build API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/build-server
ExecStart=/usr/bin/python3 /opt/build-server/build_api.py
Restart=always
Environment=ANDROID_HOME=/opt/android-sdk
Environment=PATH=/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable build-api
systemctl start build-api
systemctl status build-api
```

## API 接口说明

### 上传项目构建
- POST `/api/build/upload`
- 参数：project (zip文件), type (debug/release)
- 返回：build_id, status

### 查询构建状态
- GET `/api/build/status/{build_id}`
- 返回：status, progress, apk_url

### 下载 APK
- GET `/api/build/download/{build_id}`
- 返回：APK 文件
