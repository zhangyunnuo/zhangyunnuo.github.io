#!/bin/bash
# =============================================================================
# 向日葵网页版代理网关 - 安装脚本
# 系统要求: 阿里云CLI (CentOS/Alibaba Cloud Linux) + Python 3.6
# 功能: 
#   1. 自动安装系统依赖与Python库
#   2. 部署反向代理脚本至 /opt/sunflower_proxy/
#   3. 监听60000端口，代理转发向日葵网页版(sunlogin.oray.com)全部流量
#   4. 提供可视化悬浮面板，实时显示代理状态
# 测试标准: 浏览器访问 http://<服务器IP>:60000/ 可打开向日葵网页版并正常操作
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[INFO] 向日葵网页版代理网关 - 安装程序${NC}"
echo "================================================"

# ---------------------------
# 1. 检查并安装系统依赖
# ---------------------------
echo -e "${YELLOW}[STEP 1/4] 正在检查并安装系统依赖...${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] 请使用 root 权限运行本脚本 (sudo ./install.sh)${NC}"
    exit 1
fi

# 适配 yum/dnf
PKG_MGR="yum"
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
fi

$PKG_MGR install -y python3 python3-pip gcc python3-devel openssl-devel curl || {
    echo -e "${RED}[ERROR] 系统依赖安装失败${NC}"
    exit 1
}

PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
if [[ "$PY_VER" != "3.6" ]]; then
    echo -e "${YELLOW}[WARN] 当前Python版本为 $PY_VER，尝试寻找 python3.6...${NC}"
    $PKG_MGR install -y python36 python36-pip || true
    if command -v python3.6 &> /dev/null; then
        PYTHON_BIN="python3.6"
        PIP_BIN="pip3.6"
    else
        PYTHON_BIN="python3"
        PIP_BIN="pip3"
    fi
else
    PYTHON_BIN="python3"
    PIP_BIN="pip3"
fi

echo -e "${GREEN}[OK] 使用Python: $PYTHON_BIN${NC}"

# ---------------------------
# 2. 安装Python依赖 (兼容py3.6)
# ---------------------------
echo -e "${YELLOW}[STEP 2/4] 正在安装Python依赖 (aiohttp 3.7.4)...${NC}"
$PIP_BIN install --no-cache-dir aiohttp==3.7.4 || {
    echo -e "${RED}[ERROR] aiohttp 安装失败，请检查网络或pip源${NC}"
    exit 1
}
echo -e "${GREEN}[OK] Python依赖安装完成${NC}"

# ---------------------------
# 3. 创建代理脚本
# ---------------------------
INSTALL_DIR="/opt/sunflower_proxy"
mkdir -p $INSTALL_DIR

echo -e "${YELLOW}[STEP 3/4] 正在创建代理脚本...${NC}"

cat > $INSTALL_DIR/sunflower_proxy.py << 'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
向日葵网页版反向代理网关 (Python 3.6 Compatible)
监听 0.0.0.0:60000，将所有流量代理至 https://sunlogin.oray.com
特性:
  - HTTP/HTTPS/WebSocket 全协议代理
  - 响应内容URL重写 (HTML/CSS/JS)
  - 浏览器端 fetch/XHR/WebSocket 拦截注入
  - 可视化悬浮状态面板 (实时流量/连接数/运行时长)
  - 内部状态API: /proxy-status (JSON) 与 /proxy-status-ws (WebSocket)
"""

import asyncio
import aiohttp
from aiohttp import web, WSMsgType
import re
import time
import json

# =============================================================================
# 配置区
# =============================================================================
LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 60000
TARGET_SCHEME = 'https'
TARGET_HOST = 'sunlogin.oray.com'
TARGET_BASE = '{}://{}'.format(TARGET_SCHEME, TARGET_HOST)

# 若服务器位于NAT后(如阿里云ECS)，请填写公网IP:端口，否则留空自动识别
PUBLIC_HOST = ''

# =============================================================================
# 全局统计
# =============================================================================
stats = {
    'requests_total': 0,
    'bytes_in': 0,
    'bytes_out': 0,
    'connections_active': 0,
    'start_time': time.time(),
}

# =============================================================================
# 可视化面板与JS拦截代码 (注入到每个HTML页面)
# =============================================================================
INJECT_HTML = '''
<div id="sf-proxy-panel" style="position:fixed;top:12px;right:12px;z-index:2147483647;
background:rgba(20,30,40,0.92);color:#00ff88;padding:14px;border-radius:8px;
font-family:'Microsoft YaHei',monospace;font-size:13px;max-width:320px;
box-shadow:0 4px 20px rgba(0,0,0,0.5);border:1px solid #00ff88;line-height:1.6;">
  <div style="font-weight:bold;font-size:15px;margin-bottom:8px;color:#fff;">
    🌻 向日葵代理网关
    <span style="float:right;cursor:pointer;color:#ff5555;" 
          onclick="document.getElementById('sf-proxy-panel').style.display='none'">[关闭]</span>
  </div>
  <div>目标站点: <span style="color:#fff;">sunlogin.oray.com</span></div>
  <div>代理状态: <span id="sf-stat" style="color:#00ff88;font-weight:bold;">● 在线</span></div>
  <div>总请求数: <span id="sf-req" style="color:#fff;">0</span></div>
  <div>活跃连接: <span id="sf-conn" style="color:#fff;">0</span></div>
  <div>下行流量: <span id="sf-in" style="color:#fff;">0 KB</span></div>
  <div>上行流量: <span id="sf-out" style="color:#fff;">0 KB</span></div>
  <div>运行时长: <span id="sf-up" style="color:#fff;">0s</span></div>
  <div style="margin-top:8px;font-size:11px;color:#888;">
    提示: 所有流量已强制走本端口
  </div>
</div>
<script>
(function() {
    var host = location.host;
    // 拦截 fetch
    if (window.fetch) {
        const _f = window.fetch;
        window.fetch = function(input, init) {
            if (typeof input === 'string') {
                input = input.replace(/https?:\/\/sunlogin\.oray\.com/g, location.origin.replace(/^https/, 'http'));
                input = input.replace(/wss?:\/\/sunlogin\.oray\.com/g, 'ws://' + host);
            }
            return _f(input, init);
        };
    }
    // 拦截 XMLHttpRequest
    if (window.XMLHttpRequest) {
        const _o = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(m, url, a, u, p) {
            if (typeof url === 'string') {
                url = url.replace(/https?:\/\/sunlogin\.oray\.com/g, location.origin.replace(/^https/, 'http'));
                url = url.replace(/wss?:\/\/sunlogin\.oray\.com/g, 'ws://' + host);
            }
            return _o.call(this, m, url, a, u, p);
        };
    }
    // 拦截 WebSocket
    if (window.WebSocket) {
        const _ws = window.WebSocket;
        window.WebSocket = function(url, protos) {
            if (typeof url === 'string') {
                if (url.indexOf('/proxy-status-ws') === -1) {
                    url = url.replace(/wss?:\/\/sunlogin\.oray\.com/g, 'ws://' + host);
                }
            }
            return protos ? new _ws(url, protos) : new _ws(url);
        };
        window.WebSocket.prototype = _ws.prototype;
    }
    // 状态面板实时更新
    function fmtBytes(b){return (b/1024).toFixed(1)+' KB';}
    function fmtTime(s){var m=Math.floor(s/60);return m+'m'+(s%60)+'s';}
    var ws = new WebSocket('ws://' + host + '/proxy-status-ws');
    ws.onmessage = function(e) {
        var d = JSON.parse(e.data);
        document.getElementById('sf-req').textContent = d.requests_total;
        document.getElementById('sf-in').textContent = fmtBytes(d.bytes_in);
        document.getElementById('sf-out').textContent = fmtBytes(d.bytes_out);
        document.getElementById('sf-conn').textContent = d.connections_active;
        document.getElementById('sf-up').textContent = fmtTime(d.uptime);
    };
    ws.onerror = function() {
        document.getElementById('sf-stat').innerHTML = '<span style="color:#ff5555;">● 断开</span>';
    };
})();
</script>
'''

# =============================================================================
# 工具函数
# =============================================================================
def rewrite_text(text, server_host):
    """重写文本中的绝对URL指向代理服务器"""
    reps = [
        ('https://{}'.format(TARGET_HOST), 'http://{}'.format(server_host)),
        ('http://{}'.format(TARGET_HOST),  'http://{}'.format(server_host)),
        ('//{}'.format(TARGET_HOST),       '//{}'.format(server_host)),
        ('wss://{}'.format(TARGET_HOST),   'ws://{}'.format(server_host)),
        ('ws://{}'.format(TARGET_HOST),    'ws://{}'.format(server_host)),
    ]
    for old, new in reps:
        text = text.replace(old, new)
    return text


def inject_panel(data, server_host):
    """向HTML中注入可视化面板与拦截脚本"""
    html = INJECT_HTML.replace('{{SERVER_HOST}}', server_host).encode('utf-8')
    if b'</head>' in data:
        return data.replace(b'</head>', html + b'</head>')
    elif b'</body>' in data:
        return data.replace(b'</body>', html + b'</body>')
    else:
        return data + html


# =============================================================================
# 核心代理处理器
# =============================================================================
async def http_proxy(request):
    """HTTP/HTTPS 请求反向代理"""
    stats['requests_total'] += 1
    stats['connections_active'] += 1

    try:
        server_host = PUBLIC_HOST or request.headers.get('Host', request.host)
        target_url = '{}{}'.format(TARGET_BASE, request.path_qs)

        # 构建转发头
        fwd_headers = {}
        skip_headers = {'host', 'connection', 'keep-alive', 'proxy-authenticate',
                        'proxy-authorization', 'te', 'trailers', 'transfer-encoding', 'upgrade'}
        for k, v in request.headers.items():
            if k.lower() in skip_headers:
                continue
            fwd_headers[k] = v

        fwd_headers['Host'] = TARGET_HOST

        # 修正 Origin / Referer (让向日葵服务器认为是官方站点访问)
        if 'Origin' in fwd_headers:
            fwd_headers['Origin'] = fwd_headers['Origin'].replace(
                'http://{}'.format(server_host), TARGET_BASE)
        if 'Referer' in fwd_headers:
            fwd_headers['Referer'] = fwd_headers['Referer'].replace(
                'http://{}'.format(server_host), TARGET_BASE)

        # 读取请求体
        body = None
        if request.can_read_body:
            body = await request.read()
            stats['bytes_in'] += len(body)

        session = request.app['session']
        timeout = aiohttp.ClientTimeout(total=60)

        async with session.request(
            method=request.method,
            url=target_url,
            headers=fwd_headers,
            data=body,
            allow_redirects=False,
            ssl=True,
            timeout=timeout
        ) as resp:

            # 读取响应体
            data = await resp.read()
            stats['bytes_out'] += len(data)

            # 构造返回头
            resp_headers = {}
            for k, v in resp.headers.items():
                kl = k.lower()
                # 移除安全/传输相关头，避免浏览器拒绝
                if kl in ('content-encoding', 'content-length', 'transfer-encoding',
                          'strict-transport-security', 'content-security-policy',
                          'x-frame-options', 'x-content-type-options'):
                    continue
                if kl == 'set-cookie':
                    # 抹除Domain与Secure标志，确保Cookie在代理域生效
                    v = re.sub(r';\s*Domain=[^;]+', '', v, flags=re.IGNORECASE)
                    v = re.sub(r';\s*Secure', '', v, flags=re.IGNORECASE)
                if kl == 'location':
                    v = rewrite_text(v, server_host)
                resp_headers[k] = v

            # 内容重写与注入 (仅处理文本内容)
            ct = resp.headers.get('Content-Type', '')
            if 'text/html' in ct:
                try:
                    text = data.decode('utf-8', errors='replace')
                    text = rewrite_text(text, server_host)
                    data = inject_panel(text.encode('utf-8'), server_host)
                except Exception:
                    pass
            elif 'text/css' in ct or 'javascript' in ct or 'json' in ct:
                try:
                    text = data.decode('utf-8', errors='replace')
                    text = rewrite_text(text, server_host)
                    data = text.encode('utf-8')
                except Exception:
                    pass

            return web.Response(status=resp.status, headers=resp_headers, body=data)

    except aiohttp.ClientConnectorError as e:
        return web.Response(status=502, text='[代理网关] 无法连接到向日葵服务器: {}'.format(e))
    except asyncio.TimeoutError:
        return web.Response(status=504, text='[代理网关] 连接向日葵服务器超时')
    except Exception as e:
        return web.Response(status=500, text='[代理网关] 内部错误: {}'.format(e))
    finally:
        stats['connections_active'] -= 1


async def websocket_proxy(request):
    """WebSocket 双向代理 (浏览器 <-> 向日葵服务器)"""
    server_host = PUBLIC_HOST or request.headers.get('Host', request.host)
    target_ws = 'wss://{}{}'.format(TARGET_HOST, request.path_qs)

    ws_server = web.WebSocketResponse(autoping=True, heartbeat=30.0)
    await ws_server.prepare(request)

    # 转发头
    ws_headers = {}
    for k, v in request.headers.items():
        kl = k.lower()
        if kl in ('host', 'upgrade', 'connection', 'sec-websocket-key',
                  'sec-websocket-version', 'sec-websocket-extensions',
                  'sec-websocket-accept', 'content-length'):
            continue
        ws_headers[k] = v
    ws_headers['Host'] = TARGET_HOST
    ws_headers['Origin'] = TARGET_BASE

    try:
        session = request.app['session']
        async with session.ws_connect(
            target_ws,
            headers=ws_headers,
            ssl=True,
            autoping=True,
            heartbeat=30.0
        ) as ws_client:

            async def browser_to_target():
                async for msg in ws_server:
                    if msg.type == WSMsgType.TEXT:
                        await ws_client.send_str(msg.data)
                    elif msg.type == WSMsgType.BINARY:
                        await ws_client.send_bytes(msg.data)
                    elif msg.type == WSMsgType.PING:
                        await ws_client.ping(msg.data)
                    elif msg.type == WSMsgType.PONG:
                        await ws_client.pong(msg.data)
                    elif msg.type == WSMsgType.CLOSE:
                        await ws_client.close(code=msg.data, message=msg.extra)

            async def target_to_browser():
                async for msg in ws_client:
                    if msg.type == WSMsgType.TEXT:
                        await ws_server.send_str(msg.data)
                    elif msg.type == WSMsgType.BINARY:
                        await ws_server.send_bytes(msg.data)
                    elif msg.type == WSMsgType.PING:
                        await ws_server.ping(msg.data)
                    elif msg.type == WSMsgType.PONG:
                        await ws_server.pong(msg.data)
                    elif msg.type == WSMsgType.CLOSE:
                        await ws_server.close(code=msg.data, message=msg.extra)

            await asyncio.gather(browser_to_target(), target_to_browser())

    except Exception as e:
        print('[WebSocket代理错误]', e)
    finally:
        if not ws_server.closed:
            await ws_server.close()

    return ws_server


async def status_ws(request):
    """内部API: WebSocket实时状态推送"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    try:
        while not ws.closed:
            payload = {
                'requests_total': stats['requests_total'],
                'bytes_in': stats['bytes_in'],
                'bytes_out': stats['bytes_out'],
                'connections_active': stats['connections_active'],
                'uptime': int(time.time() - stats['start_time']),
            }
            await ws.send_str(json.dumps(payload))
            await asyncio.sleep(2)
    except Exception:
        pass
    finally:
        await ws.close()
    return ws


async def status_json(request):
    """内部API: JSON状态查询"""
    return web.json_response({
        'requests_total': stats['requests_total'],
        'bytes_in': stats['bytes_in'],
        'bytes_out': stats['bytes_out'],
        'connections_active': stats['connections_active'],
        'uptime': int(time.time() - stats['start_time']),
        'target': TARGET_BASE,
        'listen': '{}:{}'.format(LISTEN_HOST, LISTEN_PORT),
    })


# =============================================================================
# 统一路由入口
# =============================================================================
async def handle_all(request):
    """统一请求分发器"""
    # 内部状态API (不走代理)
    if request.path == '/proxy-status':
        return await status_json(request)
    if request.path == '/proxy-status-ws':
        if request.headers.get('Upgrade', '').lower() == 'websocket':
            return await status_ws(request)
        return web.json_response({'error': 'WebSocket Upgrade required'}, status=400)

    # WebSocket代理
    if request.headers.get('Upgrade', '').lower() == 'websocket':
        return await websocket_proxy(request)

    # HTTP反向代理
    return await http_proxy(request)


# =============================================================================
# 应用启动
# =============================================================================
async def on_startup(app):
    app['session'] = aiohttp.ClientSession(
        connector=aiohttp.TCPConnector(limit=200, limit_per_host=50, ssl=True)
    )


async def on_cleanup(app):
    await app['session'].close()


def main():
    app = web.Application()
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    # 捕获所有方法的所有路径
    app.router.add_route('*', '/{path_info:.*}', handle_all)

    print('=' * 60)
    print('🌻 向日葵网页版代理网关已启动')
    print('监听地址: http://{}:{}'.format(LISTEN_HOST, LISTEN_PORT))
    print('目标站点: {}'.format(TARGET_BASE))
    print('可视化面板: 访问任意页面后右上角悬浮窗')
    print('状态API: http://<IP>:{}/proxy-status'.format(LISTEN_PORT))
    print('=' * 60)
    print('提示: 请确保阿里云安全组已放行 TCP {} 端口'.format(LISTEN_PORT))
    print('      浏览器访问 http://<服务器公网IP>:{} 即可使用向日葵网页版'.format(LISTEN_PORT))
    print('=' * 60)

    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None)


if __name__ == '__main__':
    main()

PYEOF

chmod +x $INSTALL_DIR/sunflower_proxy.py
echo -e "${GREEN}[OK] 代理脚本已创建: $INSTALL_DIR/sunflower_proxy.py${NC}"

# ---------------------------
# 4. 防火墙/安全组提示
# ---------------------------
echo -e "${YELLOW}[STEP 4/4] 正在配置本地防火墙...${NC}"
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=60000/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi
iptables -I INPUT -p tcp --dport 60000 -j ACCEPT 2>/dev/null || true

# ---------------------------
# 5. 运行
# ---------------------------
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  安装完成！正在启动代理网关...${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}【重要提醒】${NC}"
echo -e "1. 请在 ${RED}阿里云控制台 -> 安全组${NC} 中放行 ${GREEN}TCP 60000${NC} 端口"
echo -e "2. 浏览器访问: ${GREEN}http://<服务器公网IP>:60000/${NC}"
echo -e "3. 代理状态API: ${GREEN}http://<服务器公网IP>:60000/proxy-status${NC}"
echo -e "4. 日志/停止: 直接 Ctrl+C 停止前台进程"
echo ""
echo -e "${GREEN}正在启动...${NC}"

# 使用nohup后台运行并输出日志
nohup $PYTHON_BIN $INSTALL_DIR/sunflower_proxy.py > /var/log/sunflower_proxy.log 2>&1 &
PID=$!
echo $PID > /var/run/sunflower_proxy.pid
sleep 2

if ps -p $PID > /dev/null 2>&1; then
    echo -e "${GREEN}[OK] 代理网关已在后台运行，PID: $PID${NC}"
    echo -e "${GREEN}日志查看: tail -f /var/log/sunflower_proxy.log${NC}"
else
    echo -e "${RED}[ERROR] 启动失败，查看日志:${NC}"
    tail -n 20 /var/log/sunflower_proxy.log 2>/dev/null || true
    exit 1
fi
