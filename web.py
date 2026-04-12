#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
HTTPS代理服务器（端口60000）
- 支持HTTP/HTTPS代理（CONNECT隧道）
- 提供浏览器风格的引导页
- 自动安装依赖（仅使用标准库，无需额外包）
"""

import os
import sys
import socket
import threading
import subprocess
import urllib.parse
from datetime import datetime

# ==================== 自动安装依赖 ====================
def install_dependencies():
    """检查并安装必要的依赖（标准库无需安装，此函数仅占位兼容题目要求）"""
    # 本脚本仅使用Python标准库，无需额外依赖
    # 但在Linux环境中，确保Python3可用
    if sys.version_info < (3, 6):
        print("错误：需要Python 3.6或更高版本")
        sys.exit(1)
    print("所有依赖已就绪（使用标准库）")

# ==================== 配置常量 ====================
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 60000
BUFFER_SIZE = 8192
BACKLOG = 100

# 引导页HTML模板（类似于浏览器的起始页）
HOMEPAGE_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>代理浏览器主页</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.2);
            width: 90%;
            max-width: 800px;
            padding: 30px;
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
        }
        .url-form {
            display: flex;
            margin-bottom: 30px;
            gap: 10px;
        }
        .url-input {
            flex: 1;
            padding: 12px 20px;
            font-size: 16px;
            border: 2px solid #ddd;
            border-radius: 40px;
            outline: none;
            transition: 0.3s;
        }
        .url-input:focus {
            border-color: #667eea;
        }
        .go-btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 0 25px;
            border-radius: 40px;
            font-size: 16px;
            cursor: pointer;
            transition: 0.3s;
        }
        .go-btn:hover {
            background: #5a67d8;
        }
        .bookmarks {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 15px;
            margin-top: 20px;
        }
        .bookmark {
            background: #f8f9fa;
            border-radius: 40px;
            padding: 8px 20px;
            text-decoration: none;
            color: #333;
            font-weight: 500;
            transition: 0.3s;
        }
        .bookmark:hover {
            background: #e9ecef;
            transform: translateY(-2px);
        }
        .info {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            font-size: 14px;
            color: #888;
        }
        .back-home {
            display: inline-block;
            margin-top: 15px;
            background: #28a745;
            color: white;
            padding: 8px 20px;
            border-radius: 40px;
            text-decoration: none;
        }
        .back-home:hover {
            background: #218838;
        }
        footer {
            margin-top: 20px;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 代理浏览器</h1>
        <div class="subtitle">通过端口 60000 安全访问任何网站</div>

        <div class="url-form">
            <input type="text" id="urlInput" class="url-input" placeholder="输入网址 (例如 https://www.bilibili.com)" value="https://www.bilibili.com">
            <button onclick="navigate()" class="go-btn">前往</button>
        </div>

        <div class="bookmarks">
            <a href="https://www.bilibili.com" class="bookmark">🎬 Bilibili</a>
            <a href="https://www.baidu.com" class="bookmark">🔍 百度</a>
            <a href="https://www.google.com" class="bookmark">🌐 Google</a>
            <a href="https://github.com" class="bookmark">🐙 GitHub</a>
            <a href="https://www.youtube.com" class="bookmark">📺 YouTube</a>
        </div>

        <a href="/" class="back-home">🏠 返回主页</a>

        <div class="info">
            <p>✨ 提示：您可以将浏览器HTTP/HTTPS代理设置为 <strong>127.0.0.1:60000</strong>，然后所有流量都会经过本代理。<br>
            🔗 在任何页面，点击上方“返回主页”或直接访问 <strong>http://127.0.0.1:60000/</strong> 即可回到本引导页。</p>
        </div>
        <footer>
            <span>代理服务器运行中 | 支持 HTTPS CONNECT 隧道</span>
        </footer>
    </div>

    <script>
        function navigate() {
            let url = document.getElementById('urlInput').value.trim();
            if (!url) return;
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://' + url;
            }
            window.location.href = url;
        }
        document.getElementById('urlInput').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') navigate();
        });
    </script>
</body>
</html>
"""

# ==================== 代理核心功能 ====================

def send_response(client_sock, status_code, status_text, headers=None, body=b""):
    """发送HTTP响应到客户端"""
    response = f"HTTP/1.1 {status_code} {status_text}\r\n"
    default_headers = {
        "Content-Length": str(len(body)),
        "Connection": "close",
        "Content-Type": "text/html; charset=utf-8"
    }
    if headers:
        default_headers.update(headers)
    for k, v in default_headers.items():
        response += f"{k}: {v}\r\n"
    response += "\r\n"
    client_sock.send(response.encode())
    if body:
        client_sock.send(body)

def handle_connect_method(client_sock, target_host, target_port):
    """处理 CONNECT 方法：建立隧道透传HTTPS流量"""
    try:
        # 连接到目标服务器
        remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_sock.settimeout(15)
        remote_sock.connect((target_host, target_port))
    except Exception as e:
        print(f"[CONNECT] 连接目标失败 {target_host}:{target_port} - {e}")
        send_response(client_sock, 502, "Bad Gateway", body=b"Connect to target failed")
        client_sock.close()
        return

    # 发送 200 Connection Established
    send_response(client_sock, 200, "Connection Established", headers={"Connection": "close"}, body=b"")
    client_sock.setblocking(False)
    remote_sock.setblocking(False)

    # 双向数据转发
    def forward(src, dst):
        try:
            while True:
                data = src.recv(BUFFER_SIZE)
                if not data:
                    break
                dst.sendall(data)
        except (socket.error, BlockingIOError, ConnectionResetError):
            pass
        finally:
            for s in (src, dst):
                try:
                    s.close()
                except:
                    pass

    t1 = threading.Thread(target=forward, args=(client_sock, remote_sock))
    t2 = threading.Thread(target=forward, args=(remote_sock, client_sock))
    t1.daemon = True
    t2.daemon = True
    t1.start()
    t2.start()
    t1.join()
    t2.join()

def parse_http_request(data):
    """解析HTTP请求，返回 (method, url, headers, body)"""
    try:
        lines = data.split(b"\r\n")
        if not lines:
            return None, None, None, None
        request_line = lines[0].decode('utf-8', errors='ignore')
        parts = request_line.split(' ')
        if len(parts) < 2:
            return None, None, None, None
        method = parts[0]
        url = parts[1]
        # 解析头部
        headers = {}
        idx = 1
        while idx < len(lines) and lines[idx] != b'':
            line = lines[idx].decode('utf-8', errors='ignore')
            if ': ' in line:
                key, value = line.split(': ', 1)
                headers[key.lower()] = value
            idx += 1
        # body可能在headers之后
        body_start = data.find(b"\r\n\r\n")
        body = b""
        if body_start != -1:
            body = data[body_start + 4:]
        return method, url, headers, body
    except Exception as e:
        print(f"[解析错误] {e}")
        return None, None, None, None

def forward_http_request(client_sock, method, raw_url, headers, body):
    """转发普通HTTP请求（非CONNECT）"""
    # 解析目标URL
    if raw_url.startswith("http://") or raw_url.startswith("https://"):
        parsed = urllib.parse.urlparse(raw_url)
        target_host = parsed.hostname
        target_port = parsed.port
        if parsed.scheme == "http" and not target_port:
            target_port = 80
        elif parsed.scheme == "https" and not target_port:
            target_port = 443
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        # 重写Host头
        headers["host"] = f"{target_host}:{target_port}" if target_port not in (80,443) else target_host
    else:
        # 相对路径 -> 访问代理自身，返回引导页
        if method == "GET" and raw_url == "/":
            send_response(client_sock, 200, "OK", body=HOMEPAGE_HTML.encode('utf-8'))
        else:
            send_response(client_sock, 404, "Not Found", body=b"404 - Page not found")
        client_sock.close()
        return

    # 构建转发请求
    request_line = f"{method} {path} HTTP/1.1\r\n"
    header_str = ""
    for key, value in headers.items():
        # 过滤掉代理专用的头部
        if key not in ("proxy-connection", "proxy-authorization"):
            header_str += f"{key}: {value}\r\n"
    request = request_line + header_str + "\r\n"
    request_data = request.encode() + body

    try:
        # 连接到目标服务器
        remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_sock.settimeout(30)
        remote_sock.connect((target_host, target_port))
        remote_sock.sendall(request_data)

        # 转发响应
        remote_sock.settimeout(5)
        while True:
            data = remote_sock.recv(BUFFER_SIZE)
            if not data:
                break
            client_sock.sendall(data)
    except Exception as e:
        print(f"[HTTP转发错误] {target_host}:{target_port} - {e}")
        try:
            send_response(client_sock, 502, "Bad Gateway", body=b"Proxy error")
        except:
            pass
    finally:
        client_sock.close()
        try:
            remote_sock.close()
        except:
            pass

def handle_client(client_sock, client_addr):
    """处理单个客户端连接"""
    print(f"[连接] {client_addr}")
    try:
        # 接收初始数据
        client_sock.settimeout(10)
        data = client_sock.recv(BUFFER_SIZE)
        if not data:
            client_sock.close()
            return

        # 解析请求
        method, url, headers, body = parse_http_request(data)
        if not method:
            client_sock.close()
            return

        # CONNECT 方法（HTTPS隧道）
        if method.upper() == "CONNECT":
            # url 格式为 host:port
            host_port = url.split(":")
            target_host = host_port[0]
            target_port = int(host_port[1]) if len(host_port) > 1 else 443
            handle_connect_method(client_sock, target_host, target_port)
        else:
            # 普通HTTP请求（包括代理请求）
            forward_http_request(client_sock, method, url, headers, body)
    except socket.timeout:
        print(f"[超时] {client_addr}")
    except Exception as e:
        print(f"[错误] {client_addr} - {e}")
    finally:
        try:
            client_sock.close()
        except:
            pass

def main():
    """启动代理服务器"""
    install_dependencies()

    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind((LISTEN_HOST, LISTEN_PORT))
    server_sock.listen(BACKLOG)
    print(f"🚀 HTTPS代理服务器启动在 {LISTEN_HOST}:{LISTEN_PORT}")
    print(f"📄 引导页地址: http://127.0.0.1:{LISTEN_PORT}/")
    print(f"⚙️ 请将浏览器HTTP/HTTPS代理设置为 127.0.0.1:{LISTEN_PORT}")
    print("💡 按 Ctrl+C 停止服务器\n")

    try:
        while True:
            client_sock, client_addr = server_sock.accept()
            thread = threading.Thread(target=handle_client, args=(client_sock, client_addr))
            thread.daemon = True
            thread.start()
    except KeyboardInterrupt:
        print("\n🛑 代理服务器已停止")
    finally:
        server_sock.close()

if __name__ == "__main__":
    main()
