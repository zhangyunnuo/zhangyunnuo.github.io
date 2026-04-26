#!/bin/bash
# ============================================
# rb - 远程浏览器代理 (短文件名版)
# 无需 sudo | apt 系 | py3.6+ | 60000 端口
# ============================================
set -e

D="$HOME/.rb"
V="$D/v"
B="$HOME/.local/bin"
S="$D/r.py"
L="$B/rb"

echo "== rb 安装 =="

# ---------- 找 Python ----------
P=""
for c in python3.6 python3.7 python3.8 python3; do
    if command -v $c &>/dev/null; then
        v=$($c --version 2>&1 | grep -oP '3\.[6-9]\.\d+' || true)
        [ -n "$v" ] && { P=$c; echo "python: $v ($P)"; break; }
    fi
done
[ -z "$P" ] && { echo "错误: 需要 python3.6+"; exit 1; }

# ---------- 检测系统依赖 ----------
echo "检测系统依赖..."
MISSING=""
has() { command -v "$1" &>/dev/null; }
has xvfb-run || has Xvfb || MISSING+=" xvfb"
has chromium-browser || has chromium || has google-chrome || MISSING+=" chromium"

if [ -n "$MISSING" ]; then
    echo "缺失: $MISSING"
    echo "请让管理员执行:"
    echo "  sudo apt-get update && sudo apt-get install -y \\"
    echo "    python3-venv xvfb chromium-browser \\"
    echo "    libnss3 libatk-bridge2.0-0 libxss1 libgtk-3-0 \\"
    echo "    libgbm1 libasound2 fonts-liberation \\"
    echo "    fonts-wqy-zenhei fonts-wqy-microhei"
    read -p "已装好? (y/N) " c
    [ "$c" != "y" ] && [ "$c" != "Y" ] && exit 1
fi

# ---------- 创建 venv ----------
echo "创建虚拟环境..."
mkdir -p "$D" "$B"
$P -m venv "$V" 2>/dev/null || {
    echo "错误: 无法创建 venv，可能需要 python3-venv"
    exit 1
}
VP="$V/bin/python"
VIP="$V/bin/pip"

# ---------- 安装依赖 (清华源) ----------
echo "安装依赖..."
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
$VIP install -q --upgrade pip
$VIP install -q pyppeteer==0.0.25 tornado==6.1 pyvirtualdisplay==2.2 Pillow==8.4.0

# ---------- 写入主程序 ----------
echo "写入 r.py..."
cat > "$S" << 'PYEOF'
#!/usr/bin/env python3
"""rb - remote browser proxy"""
import os, sys, json, base64, asyncio, logging
from typing import Optional, Set

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("rb")

from tornado.platform.asyncio import AsyncIOMainLoop
AsyncIOMainLoop().install()
from tornado.web import Application, RequestHandler
from tornado.websocket import WebSocketHandler
from tornado.ioloop import IOLoop, PeriodicCallback

W, H, PORT = 1280, 720, 60000
INTERVAL = 350

HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>rb</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0d1117;color:#c9d1d9;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;overflow:hidden}
#t{height:48px;background:#161b22;border-bottom:1px solid #30363d;display:flex;align-items:center;padding:0 12px;gap:10px}
#u{flex:1;padding:8px 12px;border:1px solid #30363d;border-radius:6px;background:#0d1117;color:#c9d1d9;font-size:14px;outline:none}
#u:focus{border-color:#58a6ff}
#g{padding:8px 18px;background:#238636;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:14px;font-weight:500}
#g:hover{background:#2ea043}
#i{font-size:12px;color:#8b949e;min-width:120px;text-align:right;white-space:nowrap}
#m{display:flex;flex-direction:column;height:100vh}
#v{flex:1;position:relative;display:flex;justify-content:center;align-items:center;background:#000;overflow:hidden}
#s{max-width:100%;max-height:100%;object-fit:contain;user-select:none;-webkit-user-drag:none;cursor:crosshair}
#st{position:absolute;top:12px;right:12px;background:rgba(13,17,23,.92);border:1px solid #30363d;padding:6px 12px;border-radius:6px;font-size:12px;color:#8b949e}
#st.ok{color:#3fb950;border-color:#238636}
#st.err{color:#f85149;border-color:#da3633}
#f{position:absolute;top:12px;left:12px;background:rgba(13,17,23,.92);border:1px solid #30363d;padding:4px 10px;border-radius:6px;font-size:11px;color:#8b949e;font-family:monospace}
#cu{position:absolute;width:14px;height:14px;border:2px solid #f0883e;border-radius:50%;pointer-events:none;transform:translate(-50%,-50%);transition:top .05s,left .05s;z-index:10;display:none;box-shadow:0 0 4px rgba(240,136,62,.5)}
#ld{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);font-size:14px;color:#8b949e;display:none}
</style>
</head>
<body>
<div id="m">
<div id="t">
  <input type="text" id="u" value="https://web.sunlogin.com" autocomplete="off" spellcheck="false">
  <button id="g">访问</button>
  <span id="i">连接中...</span>
</div>
<div id="v">
  <img id="s" src="" alt="screen">
  <div id="cu"></div>
  <div id="ld">加载中...</div>
  <div id="f">-- FPS</div>
  <div id="st">未连接</div>
</div>
</div>
<script>
(function(){
const ws=new WebSocket("ws://"+location.host+"/ws");
const s=document.getElementById("s"),u=document.getElementById("u"),g=document.getElementById("g");
const i=document.getElementById("i"),st=document.getElementById("st"),f=document.getElementById("f");
const ld=document.getElementById("ld"),cu=document.getElementById("cu");
let ok=false,W=1280,H=720,fc=0,lt=performance.now();
function gc(e){
  const r=s.getBoundingClientRect(),ir=W/H,rr=r.width/r.height;
  let rw,rh,ox=0,oy=0;
  if(rr>ir){rh=r.height;rw=rh*ir;ox=(r.width-rw)/2}
  else{rw=r.width;rh=rw/ir;oy=(r.height-rh)/2}
  let x=(e.clientX-r.left-ox)*(W/rw),y=(e.clientY-r.top-oy)*(H/rh);
  return{x:Math.max(0,Math.min(W,Math.round(x))),y:Math.max(0,Math.min(H,Math.round(y)))}
}
function send(a,o){if(!ok)return;ws.send(JSON.stringify(Object.assign({action:a},o)))}
ws.onopen=()=>{ok=true;st.textContent="已连接";st.className="ok";i.textContent="就绪";
  let url=u.value.trim();if(!url.startsWith("http"))url="https://"+url;send("navigate",{url:url})};
ws.onclose=()=>{ok=false;st.textContent="断开";st.className="err";i.textContent="刷新重连";cu.style.display="none"};
ws.onerror=()=>{i.textContent="错误"};
ws.onmessage=e=>{
  const d=JSON.parse(e.data);
  if(d.type==="screenshot"){s.src=d.data;fc++}
  else if(d.type==="status"){i.textContent=d.msg;ld.style.display=d.msg.includes("加载")?"block":"none"}
  else if(d.type==="cursor"){
    const r=s.getBoundingClientRect(),ir=W/H,rr=r.width/r.height;
    let rw,rh,ox=0,oy=0;
    if(rr>ir){rh=r.height;rw=rh*ir;ox=(r.width-rw)/2}else{rw=r.width;rh=rw/ir;oy=(r.height-rh)/2}
    cu.style.left=(ox+(d.x/W)*rw)+"px";cu.style.top=(oy+(d.y/H)*rh)+"px";cu.style.display="block";
  }
};
setInterval(()=>{const n=performance.now();f.textContent=Math.round(fc*1000/(n-lt))+" FPS";fc=0;lt=n},2000);
s.addEventListener("mousemove",e=>{const c=gc(e);send("mousemove",{x:c.x,y:c.y})});
s.addEventListener("mousedown",e=>{const c=gc(e);send("mousedown",{x:c.x,y:c.y,button:e.button})});
s.addEventListener("mouseup",e=>{const c=gc(e);send("mouseup",{x:c.x,y:c.y,button:e.button})});
s.addEventListener("click",e=>{const c=gc(e);send("click",{x:c.x,y:c.y,button:e.button})});
s.addEventListener("dblclick",e=>{const c=gc(e);send("dblclick",{x:c.x,y:c.y,button:e.button})});
s.addEventListener("contextmenu",e=>{e.preventDefault();const c=gc(e);send("click",{x:c.x,y:c.y,button:2})});
s.addEventListener("wheel",e=>{e.preventDefault();send("wheel",{deltaX:e.deltaX,deltaY:e.deltaY})},{passive:false});
const pk=new Set();
window.addEventListener("keydown",e=>{if(e.target===u)return;e.preventDefault();const k=e.key.length===1?e.key:e.code;if(!pk.has(k)){pk.add(k);send("keydown",{key:k,code:e.code,ctrl:e.ctrlKey,alt:e.altKey,shift:e.shiftKey,meta:e.metaKey})}});
window.addEventListener("keyup",e=>{if(e.target===u)return;e.preventDefault();const k=e.key.length===1?e.key:e.code;pk.delete(k);send("keyup",{key:k,code:e.code,ctrl:e.ctrlKey,alt:e.altKey,shift:e.shiftKey,meta:e.metaKey})});
g.addEventListener("click",()=>{if(!ok)return;let url=u.value.trim();if(!url)return;if(!url.startsWith("http"))url="https://"+url;ld.style.display="block";send("navigate",{url:url})});
u.addEventListener("keypress",e=>{if(e.key==="Enter")g.click()});
u.addEventListener("focus",()=>u.select());
window.addEventListener("dragover",e=>e.preventDefault());
window.addEventListener("drop",e=>e.preventDefault());
})();
</script>
</body>
</html>"""

class M:
    def __init__(s):
        s.d=None;s.b=None;s.p=None;s.c=set();s.t=None;s.o={"x":0,"y":0}
    def _f(s):
        import shutil
        for p in ["/usr/bin/chromium-browser","/usr/bin/chromium","/usr/bin/google-chrome-stable","/usr/bin/google-chrome"]:
            if os.path.exists(p):return p
        for n in ("chromium-browser","chromium","google-chrome-stable","google-chrome"):
            p=shutil.which(n); 
            if p:return p
        return None
    async def start(s):
        from pyvirtualdisplay import Display
        logger.info("Xvfb %dx%d",W,H)
        s.d=Display(visible=0,size=(W,H));s.d.start()
        cp=s._f();a=["--no-sandbox","--disable-setuid-sandbox","--disable-dev-shm-usage","--disable-gpu","--disable-web-security","--disable-features=IsolateOrigins,site-per-process","--disable-blink-features=AutomationControlled","--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.0"]
        from pyppeteer import launch
        if cp:
            logger.info("Chromium: %s",cp)
            s.b=await launch(headless=False,executablePath=cp,args=a,defaultViewport={"width":W,"height":H},handleSIGINT=False,handleSIGTERM=False,handleSIGHUP=False)
        else:
            logger.info("下载 Chromium...")
            s.b=await launch(headless=False,args=a,defaultViewport={"width":W,"height":H},handleSIGINT=False,handleSIGTERM=False,handleSIGHUP=False)
        s.p=await s.b.newPage()
        await s.p._client.send("Page.setDownloadBehavior",{"behavior":"allow","downloadPath":"/tmp"})
        logger.info("就绪")
    async def nav(s,url):
        if s.p:
            logger.info("-> %s",url)
            try:await s.p.goto(url,waitUntil="networkidle2",timeout=45000)
            except Exception as e:logger.warning("nav: %s",e)
    async def mm(s,x,y):
        if s.p:
            s.o={"x":x,"y":y};await s.p.mouse.move(x,y);await s._bc()
    async def mc(s,x,y,b="left",n=1):
        if s.p:await s.p.mouse.click(x,y,{"button":b,"clickCount":n})
    async def md(s,x,y,b="left"):
        if s.p:await s.p.mouse.move(x,y);await s.p.mouse.down({"button":b})
    async def mu(s,x,y,b="left"):
        if s.p:await s.p.mouse.move(x,y);await s.p.mouse.up({"button":b})
    async def mw(s,dx,dy):
        if s.p:await s.p.evaluate("window.scrollBy(%d,%d)"%(dx,dy))
    async def kd(s,k,c="",ctrl=False,alt=False,shift=False,meta=False):
        if not s.p or not k:return
        try:await s.p.keyboard.down(k,options={"text":k if len(k)==1 else ""})
        except Exception as e:logger.debug("kd: %s",e)
    async def ku(s,k,c="",ctrl=False,alt=False,shift=False,meta=False):
        if not s.p or not k:return
        try:await s.p.keyboard.up(k)
        except Exception as e:logger.debug("ku: %s",e)
    async def ss(s):
        if not s.p:return None
        try:
            d=await s.p.screenshot(type="jpeg",quality=70,fullPage=False)
            return base64.b64encode(d).decode()
        except Exception as e:logger.error("ss: %s",e);return None
    async def _bc(s):
        m=json.dumps({"type":"cursor",**s.o})
        dead=set()
        for c in list(s.c):
            try:c.write_message(m)
            except Exception:dead.add(c)
        for c in dead:s.c.discard(c)
    def add(s,c):
        s.c.add(c)
        if len(s.c)==1:
            s.t=PeriodicCallback(s._sl,INTERVAL);s.t.start()
    def rm(s,c):
        s.c.discard(c)
        if not s.c and s.t:s.t.stop();s.t=None
    async def _sl(s):
        try:
            b=await s.ss()
            if b and s.c:
                m=json.dumps({"type":"screenshot","data":"data:image/jpeg;base64,"+b})
                dead=set()
                for c in list(s.c):
                    try:c.write_message(m)
                    except Exception:dead.add(c)
                for c in dead:s.c.discard(c)
        except Exception as e:logger.error("sl: %s",e)
    async def close(s):
        logger.info("关闭...")
        if s.t:s.t.stop()
        if s.b:await s.b.close()
        if s.d:s.d.stop()
        logger.info("已关闭")

mgr=M()

class H(RequestHandler):
    def get(s):
        s.set_header("Content-Type","text/html; charset=utf-8")
        s.write(HTML)

class WS(WebSocketHandler):
    async def open(s):
        logger.info("接入: %s",s.request.remote_ip)
        if not mgr.b:
            try:await mgr.start()
            except Exception as e:
                logger.error("启动失败: %s",e)
                s.write_message(json.dumps({"type":"status","msg":"启动失败: "+str(e)}))
                s.close(1011,"fail");return
        mgr.add(s)
        s.write_message(json.dumps({"type":"status","msg":"已连接"}))
    async def on_message(s,m):
        try:
            d=json.loads(m);a=d.get("action")
            bm={0:"left",1:"middle",2:"right"}
            if a=="navigate":await mgr.nav(d.get("url","about:blank"))
            elif a=="mousemove":await mgr.mm(d.get("x",0),d.get("y",0))
            elif a=="click":await mgr.mc(d.get("x",0),d.get("y",0),bm.get(d.get("button",0),"left"),1)
            elif a=="dblclick":await mgr.mc(d.get("x",0),d.get("y",0),bm.get(d.get("button",0),"left"),2)
            elif a=="mousedown":await mgr.md(d.get("x",0),d.get("y",0),bm.get(d.get("button",0),"left"))
            elif a=="mouseup":await mgr.mu(d.get("x",0),d.get("y",0),bm.get(d.get("button",0),"left"))
            elif a=="wheel":await mgr.mw(d.get("deltaX",0),d.get("deltaY",0))
            elif a=="keydown":await mgr.kd(d.get("key",""),d.get("code",""),d.get("ctrl",False),d.get("alt",False),d.get("shift",False),d.get("meta",False))
            elif a=="keyup":await mgr.ku(d.get("key",""),d.get("code",""),d.get("ctrl",False),d.get("alt",False),d.get("shift",False),d.get("meta",False))
        except Exception as e:logger.error("msg: %s",e)
    def on_close(s):
        logger.info("断开")
        mgr.rm(s)

if __name__=="__main__":
    try:
        Application([(r"/",H),(r"/ws",WS)]).listen(PORT,address="0.0.0.0")
        logger.info("="*40)
        logger.info("rb @ http://0.0.0.0:%d",PORT)
        logger.info("="*40)
        IOLoop.current().start()
    except KeyboardInterrupt:
        logger.info("退出...")
        asyncio.get_event_loop().run_until_complete(mgr.close())
        sys.exit(0)
PYEOF

# ---------- 写入启动脚本 ----------
cat > "$L" << EOF
#!/bin/bash
export PYPPETEER_DOWNLOAD_HOST=https://npm.taobao.org/mirrors
export DISPLAY=:99
cd "$D"
exec "$VP" "$S" "\$@"
EOF
chmod +x "$L"

# ---------- 加入 PATH ----------
if [[ ":$PATH:" != *":$B:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "[提示] 已加入 PATH，重新登录后可直接运行 rb"
fi

echo ""
echo "== 完成 =="
echo "启动: $L"
echo "或:   rb"
echo "访问: http://<IP>:60000"
echo ""
echo "依赖安装命令 (给管理员):"
echo "  sudo apt-get install -y python3-venv xvfb chromium-browser \\"
echo "    libnss3 libatk-bridge2.0-0 libxss1 libgtk-3-0 \\"
echo "    libgbm1 libasound2 fonts-liberation \\"
echo "    fonts-wqy-zenhei fonts-wqy-microhei"
echo ""
echo "【阿里云安全组】放行 TCP 60000"
