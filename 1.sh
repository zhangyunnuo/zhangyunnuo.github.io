#!/bin/bash
# =============================================================================
# 向日葵网页版代理网关 - 安装脚本 (支持 apt/yum, root/普通用户)
# 系统要求: Debian/Ubuntu/CentOS/Alibaba Cloud Linux + Python 3.6+
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}[INFO] 向日葵网页版代理网关 - 安装程序${NC}"
echo "================================================"

# ---------------------------
# 判断运行身份
# ---------------------------
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=1
    INSTALL_DIR="/opt/sunflower_proxy"
    LOG_DIR="/var/log"
    RUN_DIR="/var/run"
    PIP_FLAGS=""
    echo -e "${GREEN}[INFO] 检测到 root 权限，使用系统级安装路径: ${INSTALL_DIR}${NC}"
else
    IS_ROOT=0
    INSTALL_DIR="$HOME/sunflower_proxy"
    LOG_DIR="$INSTALL_DIR/logs"
    RUN_DIR="$INSTALL_DIR/run"
    PIP_FLAGS="--user"
    echo -e "${YELLOW}[INFO] 检测到普通用户，使用用户级安装路径: ${INSTALL_DIR}${NC}"
    echo -e "${YELLOW}        (无需 sudo，所有文件安装在当前用户目录下)${NC}"
fi

mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$RUN_DIR"

# ---------------------------
# 检测包管理器
# ---------------------------
PKG_MGR=""
if command -v apt-get &> /dev/null; then
    PKG_MGR="apt-get"
    PKG_UPDATE="apt-get update"
    PKG_INSTALL="apt-get install -y"
    PYTHON_PKG="python3"
    PIP_PKG="python3-pip"
    DEV_PKGS="python3-dev gcc libssl-dev curl"
    echo -e "${GREEN}[OK] 检测到包管理器: apt-get (Debian/Ubuntu)${NC}"
elif command -v apt &> /dev/null; then
    PKG_MGR="apt"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt install -y"
    PYTHON_PKG="python3"
    PIP_PKG="python3-pip"
    DEV_PKGS="python3-dev gcc libssl-dev curl"
    echo -e "${GREEN}[OK] 检测到包管理器: apt (Debian/Ubuntu)${NC}"
elif command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
    PKG_UPDATE=""
    PKG_INSTALL="dnf install -y"
    PYTHON_PKG="python3"
    PIP_PKG="python3-pip"
    DEV_PKGS="python3-devel gcc openssl-devel curl"
    echo -e "${GREEN}[OK] 检测到包管理器: dnf (CentOS/RHEL 8+)${NC}"
elif command -v yum &> /dev/null; then
    PKG_MGR="yum"
    PKG_UPDATE=""
    PKG_INSTALL="yum install -y"
    PYTHON_PKG="python3"
    PIP_PKG="python3-pip"
    DEV_PKGS="python3-devel gcc openssl-devel curl"
    echo -e "${GREEN}[OK] 检测到包管理器: yum (CentOS/RHEL 7)${NC}"
else
    echo -e "${RED}[ERROR] 未检测到支持的包管理器 (apt/yum/dnf)${NC}"
    exit 1
fi

# ---------------------------
# 1. 检查 Python 环境
# ---------------------------
echo -e "${YELLOW}[STEP 1/4] 正在检查 Python 环境...${NC}"

PYTHON_BIN=""
PIP_BIN=""

for py in python3.6 python36 python3 python; do
    if command -v "$py" &> /dev/null; then
        VER=$($py -c 'import sys; print(".".join(map(str, sys.version_info[:2])))' 2>/dev/null || echo "0.0")
        MAJOR=$(echo "$VER" | cut -d. -f1)
        MINOR=$(echo "$VER" | cut -d. -f2)
        if [ "$MAJOR" -eq 3 ] && [ "$MINOR" -ge 6 ]; then
            PYTHON_BIN="$py"
            break
        fi
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo -e "${RED}[ERROR] 未找到 Python 3.6+，请先安装 Python 3.6${NC}"
    if [ "$IS_ROOT" -eq 0 ]; then
        echo -e "${YELLOW}提示: 你没有 root 权限，无法自动安装系统包。${NC}"
        echo -e "      请联系管理员执行: ${PKG_INSTALL} ${PYTHON_PKG} ${PIP_PKG}${NC}"
    fi
    exit 1
fi

echo -e "${GREEN}[OK] 使用 Python: $PYTHON_BIN (版本: $($PYTHON_BIN --version 2>&1))${NC}"

for pip in pip3.6 pip36 pip3 pip; do
    if command -v "$pip" &> /dev/null; then
        PIP_PY=$($pip --version 2>/dev/null | awk '{print $6}' | tr -d '()')
        if [ -n "$PIP_PY" ] && [ "$PIP_PY" = "$PYTHON_BIN" ]; then
            PIP_BIN="$pip"
            break
        fi
    fi
done

if [ -z "$PIP_BIN" ]; then
    if $PYTHON_BIN -m pip --version &> /dev/null; then
        PIP_BIN="$PYTHON_BIN -m pip"
    else
        echo -e "${RED}[ERROR] 未找到与 $PYTHON_BIN 匹配的 pip${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}[OK] 使用 pip: $PIP_BIN${NC}"

# ---------------------------
# 2. 安装 Python 依赖
# ---------------------------
echo -e "${YELLOW}[STEP 2/4] 正在安装 Python 依赖 (aiohttp 3.7.4)...${NC}"

if $PYTHON_BIN -c "import aiohttp; print(aiohttp.__version__)" &> /dev/null; then
    echo -e "${GREEN}[OK] aiohttp 已安装，跳过${NC}"
else
    echo -e "${BLUE}正在安装 aiohttp...${NC}"
    $PIP_BIN install $PIP_FLAGS --no-cache-dir aiohttp==3.7.4 || {
        echo -e "${RED}[ERROR] aiohttp 安装失败${NC}"
        if [ "$IS_ROOT" -eq 0 ]; then
            echo -e "${YELLOW}可能原因:${NC}"
            echo -e "  1. 缺少编译工具 (gcc / python3-dev 等)，请联系管理员安装"
            echo -e "     管理员命令: ${PKG_INSTALL} ${DEV_PKGS}"
            echo -e "  2. pip 版本过旧，尝试: $PIP_BIN install --user --upgrade pip"
            echo -e "  3. 网络问题，尝试更换 pip 源:"
            echo -e "     $PIP_BIN install --user -i https://pypi.tuna.tsinghua.edu.cn/simple aiohttp==3.7.4"
        fi
        exit 1
    }
    echo -e "${GREEN}[OK] aiohttp 安装完成${NC}"
fi

$PYTHON_BIN -c "import aiohttp; assert aiohttp.__version__ >= '3.7'" || {
    echo -e "${RED}[ERROR] aiohttp 版本不兼容${NC}"
    exit 1
}

# ---------------------------
# 3. 创建代理脚本 (Base64解码)
# ---------------------------
echo -e "${YELLOW}[STEP 3/4] 正在创建代理脚本...${NC}"

echo "IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwojIC0qLSBjb2Rpbmc6IHV0Zi04IC0qLQoiIiIK5ZCR5pel6JG1572R6aG154mI5Y+N5ZCR5Luj55CG572R5YWzIChQeXRob24gMy42IENvbXBhdGlibGUpCuebkeWQrCAwLjAuMC4wOjYwMDAw77yM5bCG5omA5pyJ5rWB6YeP5Luj55CG6IezIGh0dHBzOi8vc3VubG9naW4ub3JheS5jb20KIiIiCgppbXBvcnQgYXN5bmNpbwppbXBvcnQgYWlvaHR0cApmcm9tIGFpb2h0dHAgaW1wb3J0IHdlYiwgV1NNc2dUeXBlCmltcG9ydCByZQppbXBvcnQgdGltZQppbXBvcnQganNvbgoKIyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQojIOmFjee9ruWMugojID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CkxJU1RFTl9IT1NUID0gJzAuMC4wLjAnCkxJU1RFTl9QT1JUID0gNjAwMDAKVEFSR0VUX1NDSEVNRSA9ICdodHRwcycKVEFSR0VUX0hPU1QgPSAnc3VubG9naW4ub3JheS5jb20nClRBUkdFVF9CQVNFID0gJ3t9Oi8ve30nLmZvcm1hdChUQVJHRVRfU0NIRU1FLCBUQVJHRVRfSE9TVCkKUFVCTElDX0hPU1QgPSAnJwoKIyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQojIOWFqOWxgOe7n+iuoQojID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CnN0YXRzID0gewogICAgJ3JlcXVlc3RzX3RvdGFsJzogMCwKICAgICdieXRlc19pbic6IDAsCiAgICAnYnl0ZXNfb3V0JzogMCwKICAgICdjb25uZWN0aW9uc19hY3RpdmUnOiAwLAogICAgJ3N0YXJ0X3RpbWUnOiB0aW1lLnRpbWUoKSwKfQoKIyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQojIOWPr+inhuWMlumdouadv+S4jkpT5oum5oiq5Luj56CBCiMgPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KSU5KRUNUX0hUTUwgPSAiIiIKPGRpdiBpZD0ic2YtcHJveHktcGFuZWwiIHN0eWxlPSJwb3NpdGlvbjpmaXhlZDt0b3A6MTJweDtyaWdodDoxMnB4O3otaW5kZXg6MjE0NzQ4MzY0NzsKYmFja2dyb3VuZDpyZ2JhKDIwLDMwLDQwLDAuOTIpO2NvbG9yOiMwMGZmODg7cGFkZGluZzoxNHB4O2JvcmRlci1yYWRpdXM6OHB4Owpmb250LWZhbWlseTonTWljcm9zb2Z0IFlhSGVpJyxtb25vc3BhY2U7Zm9udC1zaXplOjEzcHg7bWF4LXdpZHRoOjMyMHB4Owpib3gtc2hhZG93OjAgNHB4IDIwcHggcmdiYSgwLDAsMCwwLjUpO2JvcmRlcjoxcHggc29saWQgIzAwZmY4ODtsaW5lLWhlaWdodDoxLjY7Ij4KICA8ZGl2IHN0eWxlPSJmb250LXdlaWdodDpib2xkO2ZvbnQtc2l6ZToxNXB4O21hcmdpbi1ib3R0b206OHB4O2NvbG9yOiNmZmY7Ij4KICAgIPCfjLsg5ZCR5pel6JG15Luj55CG572R5YWzCiAgICA8c3BhbiBzdHlsZT0iZmxvYXQ6cmlnaHQ7Y3Vyc29yOnBvaW50ZXI7Y29sb3I6I2ZmNTU1NTsiIAogICAgICAgICAgb25jbGljaz0iZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3NmLXByb3h5LXBhbmVsJykuc3R5bGUuZGlzcGxheT0nbm9uZSciPlvlhbPpl61dPC9zcGFuPgogIDwvZGl2PgogIDxkaXY+55uu5qCH56uZ54K5OiA8c3BhbiBzdHlsZT0iY29sb3I6I2ZmZjsiPnN1bmxvZ2luLm9yYXkuY29tPC9zcGFuPjwvZGl2PgogIDxkaXY+5Luj55CG54q25oCBOiA8c3BhbiBpZD0ic2Ytc3RhdCIgc3R5bGU9ImNvbG9yOiMwMGZmODg7Zm9udC13ZWlnaHQ6Ym9sZDsiPuKXjyDlnKjnur88L3NwYW4+PC9kaXY+CiAgPGRpdj7mgLvor7fmsYLmlbA6IDxzcGFuIGlkPSJzZi1yZXEiIHN0eWxlPSJjb2xvcjojZmZmOyI+MDwvc3Bhbj48L2Rpdj4KICA8ZGl2Pua0u+i3g+i/nuaOpTogPHNwYW4gaWQ9InNmLWNvbm4iIHN0eWxlPSJjb2xvcjojZmZmOyI+MDwvc3Bhbj48L2Rpdj4KICA8ZGl2PuS4i+ihjOa1gemHjzogPHNwYW4gaWQ9InNmLWluIiBzdHlsZT0iY29sb3I6I2ZmZjsiPjAgS0I8L3NwYW4+PC9kaXY+CiAgPGRpdj7kuIrooYzmtYHph486IDxzcGFuIGlkPSJzZi1vdXQiIHN0eWxlPSJjb2xvcjojZmZmOyI+MCBLQjwvc3Bhbj48L2Rpdj4KICA8ZGl2Pui/kOihjOaXtumVvzogPHNwYW4gaWQ9InNmLXVwIiBzdHlsZT0iY29sb3I6I2ZmZjsiPjBzPC9zcGFuPjwvZGl2PgogIDxkaXYgc3R5bGU9Im1hcmdpbi10b3A6OHB4O2ZvbnQtc2l6ZToxMXB4O2NvbG9yOiM4ODg7Ij4KICAgIOaPkOekujog5omA5pyJ5rWB6YeP5bey5by65Yi26LWw5pys56uv5Y+jCiAgPC9kaXY+CjwvZGl2Pgo8c2NyaXB0PgooZnVuY3Rpb24oKSB7CiAgICB2YXIgaG9zdCA9IGxvY2F0aW9uLmhvc3Q7CiAgICBpZiAod2luZG93LmZldGNoKSB7CiAgICAgICAgY29uc3QgX2YgPSB3aW5kb3cuZmV0Y2g7CiAgICAgICAgd2luZG93LmZldGNoID0gZnVuY3Rpb24oaW5wdXQsIGluaXQpIHsKICAgICAgICAgICAgaWYgKHR5cGVvZiBpbnB1dCA9PT0gJ3N0cmluZycpIHsKICAgICAgICAgICAgICAgIGlucHV0ID0gaW5wdXQucmVwbGFjZSgvaHR0cHM/OlwvXC9zdW5sb2dpblwub3JheVwuY29tL2csIGxvY2F0aW9uLm9yaWdpbi5yZXBsYWNlKC9eaHR0cHMvLCAnaHR0cCcpKTsKICAgICAgICAgICAgICAgIGlucHV0ID0gaW5wdXQucmVwbGFjZSgvd3NzPzpcL1wvc3VubG9naW5cLm9yYXlcLmNvbS9nLCAnd3M6Ly8nICsgaG9zdCk7CiAgICAgICAgICAgIH0KICAgICAgICAgICAgcmV0dXJuIF9mKGlucHV0LCBpbml0KTsKICAgICAgICB9OwogICAgfQogICAgaWYgKHdpbmRvdy5YTUxIdHRwUmVxdWVzdCkgewogICAgICAgIGNvbnN0IF9vID0gWE1MSHR0cFJlcXVlc3QucHJvdG90eXBlLm9wZW47CiAgICAgICAgWE1MSHR0cFJlcXVlc3QucHJvdG90eXBlLm9wZW4gPSBmdW5jdGlvbihtLCB1cmwsIGEsIHUsIHApIHsKICAgICAgICAgICAgaWYgKHR5cGVvZiB1cmwgPT09ICdzdHJpbmcnKSB7CiAgICAgICAgICAgICAgICB1cmwgPSB1cmwucmVwbGFjZSgvaHR0cHM/OlwvXC9zdW5sb2dpblwub3JheVwuY29tL2csIGxvY2F0aW9uLm9yaWdpbi5yZXBsYWNlKC9eaHR0cHMvLCAnaHR0cCcpKTsKICAgICAgICAgICAgICAgIHVybCA9IHVybC5yZXBsYWNlKC93c3M/OlwvXC9zdW5sb2dpblwub3JheVwuY29tL2csICd3czovLycgKyBob3N0KTsKICAgICAgICAgICAgfQogICAgICAgICAgICByZXR1cm4gX28uY2FsbCh0aGlzLCBtLCB1cmwsIGEsIHUsIHApOwogICAgICAgIH07CiAgICB9CiAgICBpZiAod2luZG93LldlYlNvY2tldCkgewogICAgICAgIGNvbnN0IF93cyA9IHdpbmRvdy5XZWJTb2NrZXQ7CiAgICAgICAgd2luZG93LldlYlNvY2tldCA9IGZ1bmN0aW9uKHVybCwgcHJvdG9zKSB7CiAgICAgICAgICAgIGlmICh0eXBlb2YgdXJsID09PSAnc3RyaW5nJykgewogICAgICAgICAgICAgICAgaWYgKHVybC5pbmRleE9mKCcvcHJveHktc3RhdHVzLXdzJykgPT09IC0xKSB7CiAgICAgICAgICAgICAgICAgICAgdXJsID0gdXJsLnJlcGxhY2UoL3dzcz86XC9cL3N1bmxvZ2luXC5vcmF5XC5jb20vZywgJ3dzOi8vJyArIGhvc3QpOwogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9CiAgICAgICAgICAgIHJldHVybiBwcm90b3MgPyBuZXcgX3dzKHVybCwgcHJvdG9zKSA6IG5ldyBfd3ModXJsKTsKICAgICAgICB9OwogICAgICAgIHdpbmRvdy5XZWJTb2NrZXQucHJvdG90eXBlID0gX3dzLnByb3RvdHlwZTsKICAgIH0KICAgIGZ1bmN0aW9uIGZtdEJ5dGVzKGIpe3JldHVybiAoYi8xMDI0KS50b0ZpeGVkKDEpKycgS0InO30KICAgIGZ1bmN0aW9uIGZtdFRpbWUocyl7dmFyIG09TWF0aC5mbG9vcihzLzYwKTtyZXR1cm4gbSsnbScrKHMlNjApKydzJzt9CiAgICB2YXIgd3MgPSBuZXcgV2ViU29ja2V0KCd3czovLycgKyBob3N0ICsgJy9wcm94eS1zdGF0dXMtd3MnKTsKICAgIHdzLm9ubWVzc2FnZSA9IGZ1bmN0aW9uKGUpIHsKICAgICAgICB2YXIgZCA9IEpTT04ucGFyc2UoZS5kYXRhKTsKICAgICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc2YtcmVxJykudGV4dENvbnRlbnQgPSBkLnJlcXVlc3RzX3RvdGFsOwogICAgICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdzZi1pbicpLnRleHRDb250ZW50ID0gZm10Qnl0ZXMoZC5ieXRlc19pbik7CiAgICAgICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3NmLW91dCcpLnRleHRDb250ZW50ID0gZm10Qnl0ZXMoZC5ieXRlc19vdXQpOwogICAgICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdzZi1jb25uJykudGV4dENvbnRlbnQgPSBkLmNvbm5lY3Rpb25zX2FjdGl2ZTsKICAgICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc2YtdXAnKS50ZXh0Q29udGVudCA9IGZtdFRpbWUoZC51cHRpbWUpOwogICAgfTsKICAgIHdzLm9uZXJyb3IgPSBmdW5jdGlvbigpIHsKICAgICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc2Ytc3RhdCcpLmlubmVySFRNTCA9ICc8c3BhbiBzdHlsZT0iY29sb3I6I2ZmNTU1NTsiPuKXjyDmlq3lvIA8L3NwYW4+JzsKICAgIH07Cn0pKCk7Cjwvc2NyaXB0PgoiIiIKCmRlZiByZXdyaXRlX3RleHQodGV4dCwgc2VydmVyX2hvc3QpOgogICAgcmVwcyA9IFsKICAgICAgICAoJ2h0dHBzOi8ve30nLmZvcm1hdChUQVJHRVRfSE9TVCksICdodHRwOi8ve30nLmZvcm1hdChzZXJ2ZXJfaG9zdCkpLAogICAgICAgICgnaHR0cDovL3t9Jy5mb3JtYXQoVEFSR0VUX0hPU1QpLCAgJ2h0dHA6Ly97fScuZm9ybWF0KHNlcnZlcl9ob3N0KSksCiAgICAgICAgKCcvL3t9Jy5mb3JtYXQoVEFSR0VUX0hPU1QpLCAgICAgICAnLy97fScuZm9ybWF0KHNlcnZlcl9ob3N0KSksCiAgICAgICAgKCd3c3M6Ly97fScuZm9ybWF0KFRBUkdFVF9IT1NUKSwgICAnd3M6Ly97fScuZm9ybWF0KHNlcnZlcl9ob3N0KSksCiAgICAgICAgKCd3czovL3t9Jy5mb3JtYXQoVEFSR0VUX0hPU1QpLCAgICAnd3M6Ly97fScuZm9ybWF0KHNlcnZlcl9ob3N0KSksCiAgICBdCiAgICBmb3Igb2xkLCBuZXcgaW4gcmVwczoKICAgICAgICB0ZXh0ID0gdGV4dC5yZXBsYWNlKG9sZCwgbmV3KQogICAgcmV0dXJuIHRleHQKCmRlZiBpbmplY3RfcGFuZWwoZGF0YSwgc2VydmVyX2hvc3QpOgogICAgaHRtbCA9IElOSkVDVF9IVE1MLnJlcGxhY2UoJ3t7U0VSVkVSX0hPU1R9fScsIHNlcnZlcl9ob3N0KS5lbmNvZGUoJ3V0Zi04JykKICAgIGlmIGInPC9oZWFkPicgaW4gZGF0YToKICAgICAgICByZXR1cm4gZGF0YS5yZXBsYWNlKGInPC9oZWFkPicsIGh0bWwgKyBiJzwvaGVhZD4nKQogICAgZWxpZiBiJzwvYm9keT4nIGluIGRhdGE6CiAgICAgICAgcmV0dXJuIGRhdGEucmVwbGFjZShiJzwvYm9keT4nLCBodG1sICsgYic8L2JvZHk+JykKICAgIGVsc2U6CiAgICAgICAgcmV0dXJuIGRhdGEgKyBodG1sCgphc3luYyBkZWYgaHR0cF9wcm94eShyZXF1ZXN0KToKICAgIHN0YXRzWydyZXF1ZXN0c190b3RhbCddICs9IDEKICAgIHN0YXRzWydjb25uZWN0aW9uc19hY3RpdmUnXSArPSAxCiAgICB0cnk6CiAgICAgICAgc2VydmVyX2hvc3QgPSBQVUJMSUNfSE9TVCBvciByZXF1ZXN0LmhlYWRlcnMuZ2V0KCdIb3N0JywgcmVxdWVzdC5ob3N0KQogICAgICAgIHRhcmdldF91cmwgPSAne317fScuZm9ybWF0KFRBUkdFVF9CQVNFLCByZXF1ZXN0LnBhdGhfcXMpCiAgICAgICAgZndkX2hlYWRlcnMgPSB7fQogICAgICAgIHNraXBfaGVhZGVycyA9IHsnaG9zdCcsICdjb25uZWN0aW9uJywgJ2tlZXAtYWxpdmUnLCAncHJveHktYXV0aGVudGljYXRlJywKICAgICAgICAgICAgICAgICAgICAgICAgJ3Byb3h5LWF1dGhvcml6YXRpb24nLCAndGUnLCAndHJhaWxlcnMnLCAndHJhbnNmZXItZW5jb2RpbmcnLCAndXBncmFkZSd9CiAgICAgICAgZm9yIGssIHYgaW4gcmVxdWVzdC5oZWFkZXJzLml0ZW1zKCk6CiAgICAgICAgICAgIGlmIGsubG93ZXIoKSBpbiBza2lwX2hlYWRlcnM6CiAgICAgICAgICAgICAgICBjb250aW51ZQogICAgICAgICAgICBmd2RfaGVhZGVyc1trXSA9IHYKICAgICAgICBmd2RfaGVhZGVyc1snSG9zdCddID0gVEFSR0VUX0hPU1QKICAgICAgICBpZiAnT3JpZ2luJyBpbiBmd2RfaGVhZGVyczoKICAgICAgICAgICAgZndkX2hlYWRlcnNbJ09yaWdpbiddID0gZndkX2hlYWRlcnNbJ09yaWdpbiddLnJlcGxhY2UoCiAgICAgICAgICAgICAgICAnaHR0cDovL3t9Jy5mb3JtYXQoc2VydmVyX2hvc3QpLCBUQVJHRVRfQkFTRSkKICAgICAgICBpZiAnUmVmZXJlcicgaW4gZndkX2hlYWRlcnM6CiAgICAgICAgICAgIGZ3ZF9oZWFkZXJzWydSZWZlcmVyJ10gPSBmd2RfaGVhZGVyc1snUmVmZXJlciddLnJlcGxhY2UoCiAgICAgICAgICAgICAgICAnaHR0cDovL3t9Jy5mb3JtYXQoc2VydmVyX2hvc3QpLCBUQVJHRVRfQkFTRSkKICAgICAgICBib2R5ID0gTm9uZQogICAgICAgIGlmIHJlcXVlc3QuY2FuX3JlYWRfYm9keToKICAgICAgICAgICAgYm9keSA9IGF3YWl0IHJlcXVlc3QucmVhZCgpCiAgICAgICAgICAgIHN0YXRzWydieXRlc19pbiddICs9IGxlbihib2R5KQogICAgICAgIHNlc3Npb24gPSByZXF1ZXN0LmFwcFsnc2Vzc2lvbiddCiAgICAgICAgdGltZW91dCA9IGFpb2h0dHAuQ2xpZW50VGltZW91dCh0b3RhbD02MCkKICAgICAgICBhc3luYyB3aXRoIHNlc3Npb24ucmVxdWVzdCgKICAgICAgICAgICAgbWV0aG9kPXJlcXVlc3QubWV0aG9kLAogICAgICAgICAgICB1cmw9dGFyZ2V0X3VybCwKICAgICAgICAgICAgaGVhZGVycz1md2RfaGVhZGVycywKICAgICAgICAgICAgZGF0YT1ib2R5LAogICAgICAgICAgICBhbGxvd19yZWRpcmVjdHM9RmFsc2UsCiAgICAgICAgICAgIHNzbD1UcnVlLAogICAgICAgICAgICB0aW1lb3V0PXRpbWVvdXQKICAgICAgICApIGFzIHJlc3A6CiAgICAgICAgICAgIGRhdGEgPSBhd2FpdCByZXNwLnJlYWQoKQogICAgICAgICAgICBzdGF0c1snYnl0ZXNfb3V0J10gKz0gbGVuKGRhdGEpCiAgICAgICAgICAgIHJlc3BfaGVhZGVycyA9IHt9CiAgICAgICAgICAgIGZvciBrLCB2IGluIHJlc3AuaGVhZGVycy5pdGVtcygpOgogICAgICAgICAgICAgICAga2wgPSBrLmxvd2VyKCkKICAgICAgICAgICAgICAgIGlmIGtsIGluICgnY29udGVudC1lbmNvZGluZycsICdjb250ZW50LWxlbmd0aCcsICd0cmFuc2Zlci1lbmNvZGluZycsCiAgICAgICAgICAgICAgICAgICAgICAgICAgJ3N0cmljdC10cmFuc3BvcnQtc2VjdXJpdHknLCAnY29udGVudC1zZWN1cml0eS1wb2xpY3knLAogICAgICAgICAgICAgICAgICAgICAgICAgICd4LWZyYW1lLW9wdGlvbnMnLCAneC1jb250ZW50LXR5cGUtb3B0aW9ucycpOgogICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICBpZiBrbCA9PSAnc2V0LWNvb2tpZSc6CiAgICAgICAgICAgICAgICAgICAgdiA9IHJlLnN1YihyJztccypEb21haW49W147XSsnLCAnJywgdiwgZmxhZ3M9cmUuSUdOT1JFQ0FTRSkKICAgICAgICAgICAgICAgICAgICB2ID0gcmUuc3ViKHInO1xzKlNlY3VyZScsICcnLCB2LCBmbGFncz1yZS5JR05PUkVDQVNFKQogICAgICAgICAgICAgICAgaWYga2wgPT0gJ2xvY2F0aW9uJzoKICAgICAgICAgICAgICAgICAgICB2ID0gcmV3cml0ZV90ZXh0KHYsIHNlcnZlcl9ob3N0KQogICAgICAgICAgICAgICAgcmVzcF9oZWFkZXJzW2tdID0gdgogICAgICAgICAgICBjdCA9IHJlc3AuaGVhZGVycy5nZXQoJ0NvbnRlbnQtVHlwZScsICcnKQogICAgICAgICAgICBpZiAndGV4dC9odG1sJyBpbiBjdDoKICAgICAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgICAgICB0ZXh0ID0gZGF0YS5kZWNvZGUoJ3V0Zi04JywgZXJyb3JzPSdyZXBsYWNlJykKICAgICAgICAgICAgICAgICAgICB0ZXh0ID0gcmV3cml0ZV90ZXh0KHRleHQsIHNlcnZlcl9ob3N0KQogICAgICAgICAgICAgICAgICAgIGRhdGEgPSBpbmplY3RfcGFuZWwodGV4dC5lbmNvZGUoJ3V0Zi04JyksIHNlcnZlcl9ob3N0KQogICAgICAgICAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICAgICAgICAgICAgICBwYXNzCiAgICAgICAgICAgIGVsaWYgJ3RleHQvY3NzJyBpbiBjdCBvciAnamF2YXNjcmlwdCcgaW4gY3Qgb3IgJ2pzb24nIGluIGN0OgogICAgICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgICAgIHRleHQgPSBkYXRhLmRlY29kZSgndXRmLTgnLCBlcnJvcnM9J3JlcGxhY2UnKQogICAgICAgICAgICAgICAgICAgIHRleHQgPSByZXdyaXRlX3RleHQodGV4dCwgc2VydmVyX2hvc3QpCiAgICAgICAgICAgICAgICAgICAgZGF0YSA9IHRleHQuZW5jb2RlKCd1dGYtOCcpCiAgICAgICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgICAgICAgICAgICAgIHBhc3MKICAgICAgICAgICAgcmV0dXJuIHdlYi5SZXNwb25zZShzdGF0dXM9cmVzcC5zdGF0dXMsIGhlYWRlcnM9cmVzcF9oZWFkZXJzLCBib2R5PWRhdGEpCiAgICBleGNlcHQgYWlvaHR0cC5DbGllbnRDb25uZWN0b3JFcnJvciBhcyBlOgogICAgICAgIHJldHVybiB3ZWIuUmVzcG9uc2Uoc3RhdHVzPTUwMiwgdGV4dD0nW+S7o+eQhue9keWFs10g5peg5rOV6L+e5o6l5Yiw5ZCR5pel6JG15pyN5Yqh5ZmoOiB7fScuZm9ybWF0KGUpKQogICAgZXhjZXB0IGFzeW5jaW8uVGltZW91dEVycm9yOgogICAgICAgIHJldHVybiB3ZWIuUmVzcG9uc2Uoc3RhdHVzPTUwNCwgdGV4dD0nW+S7o+eQhue9keWFs10g6L+e5o6l5ZCR5pel6JG15pyN5Yqh5Zmo6LaF5pe2JykKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICByZXR1cm4gd2ViLlJlc3BvbnNlKHN0YXR1cz01MDAsIHRleHQ9J1vku6PnkIbnvZHlhbNdIOWGhemDqOmUmeivrzoge30nLmZvcm1hdChlKSkKICAgIGZpbmFsbHk6CiAgICAgICAgc3RhdHNbJ2Nvbm5lY3Rpb25zX2FjdGl2ZSddIC09IDEKCmFzeW5jIGRlZiB3ZWJzb2NrZXRfcHJveHkocmVxdWVzdCk6CiAgICBzZXJ2ZXJfaG9zdCA9IFBVQkxJQ19IT1NUIG9yIHJlcXVlc3QuaGVhZGVycy5nZXQoJ0hvc3QnLCByZXF1ZXN0Lmhvc3QpCiAgICB0YXJnZXRfd3MgPSAnd3NzOi8ve317fScuZm9ybWF0KFRBUkdFVF9IT1NULCByZXF1ZXN0LnBhdGhfcXMpCiAgICB3c19zZXJ2ZXIgPSB3ZWIuV2ViU29ja2V0UmVzcG9uc2UoYXV0b3Bpbmc9VHJ1ZSwgaGVhcnRiZWF0PTMwLjApCiAgICBhd2FpdCB3c19zZXJ2ZXIucHJlcGFyZShyZXF1ZXN0KQogICAgd3NfaGVhZGVycyA9IHt9CiAgICBmb3IgaywgdiBpbiByZXF1ZXN0LmhlYWRlcnMuaXRlbXMoKToKICAgICAgICBrbCA9IGsubG93ZXIoKQogICAgICAgIGlmIGtsIGluICgnaG9zdCcsICd1cGdyYWRlJywgJ2Nvbm5lY3Rpb24nLCAnc2VjLXdlYnNvY2tldC1rZXknLAogICAgICAgICAgICAgICAgICAnc2VjLXdlYnNvY2tldC12ZXJzaW9uJywgJ3NlYy13ZWJzb2NrZXQtZXh0ZW5zaW9ucycsCiAgICAgICAgICAgICAgICAgICdzZWMtd2Vic29ja2V0LWFjY2VwdCcsICdjb250ZW50LWxlbmd0aCcpOgogICAgICAgICAgICBjb250aW51ZQogICAgICAgIHdzX2hlYWRlcnNba10gPSB2CiAgICB3c19oZWFkZXJzWydIb3N0J10gPSBUQVJHRVRfSE9TVAogICAgd3NfaGVhZGVyc1snT3JpZ2luJ10gPSBUQVJHRVRfQkFTRQogICAgdHJ5OgogICAgICAgIHNlc3Npb24gPSByZXF1ZXN0LmFwcFsnc2Vzc2lvbiddCiAgICAgICAgYXN5bmMgd2l0aCBzZXNzaW9uLndzX2Nvbm5lY3QoCiAgICAgICAgICAgIHRhcmdldF93cywKICAgICAgICAgICAgaGVhZGVycz13c19oZWFkZXJzLAogICAgICAgICAgICBzc2w9VHJ1ZSwKICAgICAgICAgICAgYXV0b3Bpbmc9VHJ1ZSwKICAgICAgICAgICAgaGVhcnRiZWF0PTMwLjAKICAgICAgICApIGFzIHdzX2NsaWVudDoKICAgICAgICAgICAgYXN5bmMgZGVmIGJyb3dzZXJfdG9fdGFyZ2V0KCk6CiAgICAgICAgICAgICAgICBhc3luYyBmb3IgbXNnIGluIHdzX3NlcnZlcjoKICAgICAgICAgICAgICAgICAgICBpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuVEVYVDoKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3NfY2xpZW50LnNlbmRfc3RyKG1zZy5kYXRhKQogICAgICAgICAgICAgICAgICAgIGVsaWYgbXNnLnR5cGUgPT0gV1NNc2dUeXBlLkJJTkFSWToKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3NfY2xpZW50LnNlbmRfYnl0ZXMobXNnLmRhdGEpCiAgICAgICAgICAgICAgICAgICAgZWxpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuUElORzoKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3NfY2xpZW50LnBpbmcobXNnLmRhdGEpCiAgICAgICAgICAgICAgICAgICAgZWxpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuUE9ORzoKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3NfY2xpZW50LnBvbmcobXNnLmRhdGEpCiAgICAgICAgICAgICAgICAgICAgZWxpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuQ0xPU0U6CiAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHdzX2NsaWVudC5jbG9zZShjb2RlPW1zZy5kYXRhLCBtZXNzYWdlPW1zZy5leHRyYSkKICAgICAgICAgICAgYXN5bmMgZGVmIHRhcmdldF90b19icm93c2VyKCk6CiAgICAgICAgICAgICAgICBhc3luYyBmb3IgbXNnIGluIHdzX2NsaWVudDoKICAgICAgICAgICAgICAgICAgICBpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuVEVYVDoKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3Nfc2VydmVyLnNlbmRfc3RyKG1zZy5kYXRhKQogICAgICAgICAgICAgICAgICAgIGVsaWYgbXNnLnR5cGUgPT0gV1NNc2dUeXBlLkJJTkFSWToKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3Nfc2VydmVyLnNlbmRfYnl0ZXMobXNnLmRhdGEpCiAgICAgICAgICAgICAgICAgICAgZWxpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuUElORzoKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3Nfc2VydmVyLnBpbmcobXNnLmRhdGEpCiAgICAgICAgICAgICAgICAgICAgZWxpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuUE9ORzoKICAgICAgICAgICAgICAgICAgICAgICAgYXdhaXQgd3Nfc2VydmVyLnBvbmcobXNnLmRhdGEpCiAgICAgICAgICAgICAgICAgICAgZWxpZiBtc2cudHlwZSA9PSBXU01zZ1R5cGUuQ0xPU0U6CiAgICAgICAgICAgICAgICAgICAgICAgIGF3YWl0IHdzX3NlcnZlci5jbG9zZShjb2RlPW1zZy5kYXRhLCBtZXNzYWdlPW1zZy5leHRyYSkKICAgICAgICAgICAgYXdhaXQgYXN5bmNpby5nYXRoZXIoYnJvd3Nlcl90b190YXJnZXQoKSwgdGFyZ2V0X3RvX2Jyb3dzZXIoKSkKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICBwcmludCgnW1dlYlNvY2tldOS7o+eQhumUmeivr10nLCBlKQogICAgZmluYWxseToKICAgICAgICBpZiBub3Qgd3Nfc2VydmVyLmNsb3NlZDoKICAgICAgICAgICAgYXdhaXQgd3Nfc2VydmVyLmNsb3NlKCkKICAgIHJldHVybiB3c19zZXJ2ZXIKCmFzeW5jIGRlZiBzdGF0dXNfd3MocmVxdWVzdCk6CiAgICB3cyA9IHdlYi5XZWJTb2NrZXRSZXNwb25zZSgpCiAgICBhd2FpdCB3cy5wcmVwYXJlKHJlcXVlc3QpCiAgICB0cnk6CiAgICAgICAgd2hpbGUgbm90IHdzLmNsb3NlZDoKICAgICAgICAgICAgcGF5bG9hZCA9IHsKICAgICAgICAgICAgICAgICdyZXF1ZXN0c190b3RhbCc6IHN0YXRzWydyZXF1ZXN0c190b3RhbCddLAogICAgICAgICAgICAgICAgJ2J5dGVzX2luJzogc3RhdHNbJ2J5dGVzX2luJ10sCiAgICAgICAgICAgICAgICAnYnl0ZXNfb3V0Jzogc3RhdHNbJ2J5dGVzX291dCddLAogICAgICAgICAgICAgICAgJ2Nvbm5lY3Rpb25zX2FjdGl2ZSc6IHN0YXRzWydjb25uZWN0aW9uc19hY3RpdmUnXSwKICAgICAgICAgICAgICAgICd1cHRpbWUnOiBpbnQodGltZS50aW1lKCkgLSBzdGF0c1snc3RhcnRfdGltZSddKSwKICAgICAgICAgICAgfQogICAgICAgICAgICBhd2FpdCB3cy5zZW5kX3N0cihqc29uLmR1bXBzKHBheWxvYWQpKQogICAgICAgICAgICBhd2FpdCBhc3luY2lvLnNsZWVwKDIpCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHBhc3MKICAgIGZpbmFsbHk6CiAgICAgICAgYXdhaXQgd3MuY2xvc2UoKQogICAgcmV0dXJuIHdzCgphc3luYyBkZWYgc3RhdHVzX2pzb24ocmVxdWVzdCk6CiAgICByZXR1cm4gd2ViLmpzb25fcmVzcG9uc2UoewogICAgICAgICdyZXF1ZXN0c190b3RhbCc6IHN0YXRzWydyZXF1ZXN0c190b3RhbCddLAogICAgICAgICdieXRlc19pbic6IHN0YXRzWydieXRlc19pbiddLAogICAgICAgICdieXRlc19vdXQnOiBzdGF0c1snYnl0ZXNfb3V0J10sCiAgICAgICAgJ2Nvbm5lY3Rpb25zX2FjdGl2ZSc6IHN0YXRzWydjb25uZWN0aW9uc19hY3RpdmUnXSwKICAgICAgICAndXB0aW1lJzogaW50KHRpbWUudGltZSgpIC0gc3RhdHNbJ3N0YXJ0X3RpbWUnXSksCiAgICAgICAgJ3RhcmdldCc6IFRBUkdFVF9CQVNFLAogICAgICAgICdsaXN0ZW4nOiAne306e30nLmZvcm1hdChMSVNURU5fSE9TVCwgTElTVEVOX1BPUlQpLAogICAgfSkKCmFzeW5jIGRlZiBoYW5kbGVfYWxsKHJlcXVlc3QpOgogICAgaWYgcmVxdWVzdC5wYXRoID09ICcvcHJveHktc3RhdHVzJzoKICAgICAgICByZXR1cm4gYXdhaXQgc3RhdHVzX2pzb24ocmVxdWVzdCkKICAgIGlmIHJlcXVlc3QucGF0aCA9PSAnL3Byb3h5LXN0YXR1cy13cyc6CiAgICAgICAgaWYgcmVxdWVzdC5oZWFkZXJzLmdldCgnVXBncmFkZScsICcnKS5sb3dlcigpID09ICd3ZWJzb2NrZXQnOgogICAgICAgICAgICByZXR1cm4gYXdhaXQgc3RhdHVzX3dzKHJlcXVlc3QpCiAgICAgICAgcmV0dXJuIHdlYi5qc29uX3Jlc3BvbnNlKHsnZXJyb3InOiAnV2ViU29ja2V0IFVwZ3JhZGUgcmVxdWlyZWQnfSwgc3RhdHVzPTQwMCkKICAgIGlmIHJlcXVlc3QuaGVhZGVycy5nZXQoJ1VwZ3JhZGUnLCAnJykubG93ZXIoKSA9PSAnd2Vic29ja2V0JzoKICAgICAgICByZXR1cm4gYXdhaXQgd2Vic29ja2V0X3Byb3h5KHJlcXVlc3QpCiAgICByZXR1cm4gYXdhaXQgaHR0cF9wcm94eShyZXF1ZXN0KQoKYXN5bmMgZGVmIG9uX3N0YXJ0dXAoYXBwKToKICAgIGFwcFsnc2Vzc2lvbiddID0gYWlvaHR0cC5DbGllbnRTZXNzaW9uKAogICAgICAgIGNvbm5lY3Rvcj1haW9odHRwLlRDUENvbm5lY3RvcihsaW1pdD0yMDAsIGxpbWl0X3Blcl9ob3N0PTUwLCBzc2w9VHJ1ZSkKICAgICkKCmFzeW5jIGRlZiBvbl9jbGVhbnVwKGFwcCk6CiAgICBhd2FpdCBhcHBbJ3Nlc3Npb24nXS5jbG9zZSgpCgpkZWYgbWFpbigpOgogICAgYXBwID0gd2ViLkFwcGxpY2F0aW9uKCkKICAgIGFwcC5vbl9zdGFydHVwLmFwcGVuZChvbl9zdGFydHVwKQogICAgYXBwLm9uX2NsZWFudXAuYXBwZW5kKG9uX2NsZWFudXApCiAgICBhcHAucm91dGVyLmFkZF9yb3V0ZSgnKicsICcve3BhdGhfaW5mbzouKn0nLCBoYW5kbGVfYWxsKQogICAgcHJpbnQoJz0nICogNjApCiAgICBwcmludCgn8J+MuyDlkJHml6XokbXnvZHpobXniYjku6PnkIbnvZHlhbPlt7LlkK/liqgnKQogICAgcHJpbnQoJ+ebkeWQrOWcsOWdgDogaHR0cDovL3t9Ont9Jy5mb3JtYXQoTElTVEVOX0hPU1QsIExJU1RFTl9QT1JUKSkKICAgIHByaW50KCfnm67moIfnq5nngrk6IHt9Jy5mb3JtYXQoVEFSR0VUX0JBU0UpKQogICAgcHJpbnQoJ+WPr+inhuWMlumdouadvzog6K6/6Zeu5Lu75oSP6aG16Z2i5ZCO5Y+z5LiK6KeS5oKs5rWu56qXJykKICAgIHByaW50KCfnirbmgIFBUEk6IGh0dHA6Ly88SVA+Ont9L3Byb3h5LXN0YXR1cycuZm9ybWF0KExJU1RFTl9QT1JUKSkKICAgIHByaW50KCc9JyAqIDYwKQogICAgcHJpbnQoJ+aPkOekujog6K+356Gu5L+d6Zi/6YeM5LqR5a6J5YWo57uE5bey5pS+6KGMIFRDUCB7fSDnq6/lj6MnLmZvcm1hdChMSVNURU5fUE9SVCkpCiAgICBwcmludCgnICAgICAg5rWP6KeI5Zmo6K6/6ZeuIGh0dHA6Ly885pyN5Yqh5Zmo5YWs572RSVA+Ont9IOWNs+WPr+S9v+eUqOWQkeaXpeiRtee9kemhteeJiCcuZm9ybWF0KExJU1RFTl9QT1JUKSkKICAgIHByaW50KCc9JyAqIDYwKQogICAgd2ViLnJ1bl9hcHAoYXBwLCBob3N0PUxJU1RFTl9IT1NULCBwb3J0PUxJU1RFTl9QT1JULCBhY2Nlc3NfbG9nPU5vbmUpCgppZiBfX25hbWVfXyA9PSAnX19tYWluX18nOgogICAgbWFpbigpCg==" | base64 -d > "$INSTALL_DIR/sunflower_proxy.py"
chmod +x "$INSTALL_DIR/sunflower_proxy.py"
echo -e "${GREEN}[OK] 代理脚本已创建: $INSTALL_DIR/sunflower_proxy.py${NC}"

# ---------------------------
# 4. 防火墙配置 (仅root)
# ---------------------------
echo -e "${YELLOW}[STEP 4/4] 正在配置防火墙...${NC}"

if [ "$IS_ROOT" -eq 1 ]; then
    if command -v ufw &> /dev/null; then
        ufw allow 60000/tcp 2>/dev/null || true
        echo -e "${GREEN}[OK] ufw 已放行 60000/tcp${NC}"
    fi
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=60000/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        echo -e "${GREEN}[OK] firewall-cmd 已放行 60000/tcp${NC}"
    fi
    iptables -I INPUT -p tcp --dport 60000 -j ACCEPT 2>/dev/null || true
    echo -e "${GREEN}[OK] iptables 已放行 60000/tcp${NC}"
else
    echo -e "${YELLOW}[SKIP] 普通用户无法修改系统防火墙，跳过${NC}"
    echo -e "${YELLOW}      请确保管理员已放行 TCP 60000 端口，或安全组已配置${NC}"
fi

# ---------------------------
# 5. 启动服务
# ---------------------------
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  安装完成！正在启动代理网关...${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

if [ "$IS_ROOT" -eq 0 ]; then
    echo -e "${YELLOW}【普通用户模式提醒】${NC}"
    echo -e "  • 安装目录: ${GREEN}$INSTALL_DIR${NC}"
    echo -e "  • 日志文件: ${GREEN}$LOG_DIR/sunflower_proxy.log${NC}"
    echo -e "  • PID 文件: ${GREEN}$RUN_DIR/sunflower_proxy.pid${NC}"
    echo -e "  • Python包: ${GREEN}~/.local/lib/python*/site-packages${NC}"
    echo ""
    echo -e "  ${YELLOW}如果 pip --user 安装的命令不在 PATH 中，请执行:${NC}"
    echo -e "    export PATH="\$HOME/.local/bin:\$PATH""
    echo ""
fi

echo -e "${YELLOW}【访问信息】${NC}"
echo -e "  1. 浏览器访问: ${GREEN}http://<服务器公网IP>:60000/${NC}"
echo -e "  2. 状态API:    ${GREEN}http://<服务器公网IP>:60000/proxy-status${NC}"
echo -e "  3. 可视化面板:  页面右上角悬浮窗（可关闭）"
echo ""
echo -e "${YELLOW}【安全组/防火墙】${NC}"
echo -e "  请确保阿里云安全组已放行 ${GREEN}TCP 60000${NC} 入方向"
if [ "$IS_ROOT" -eq 0 ]; then
    echo -e "  ${RED}注意: 你当前是普通用户，如果系统防火墙未放行，请让管理员执行:${NC}"
    if [ "$PKG_MGR" = "apt-get" ] || [ "$PKG_MGR" = "apt" ]; then
        echo -e "        sudo ufw allow 60000/tcp"
    else
        echo -e "        sudo firewall-cmd --permanent --add-port=60000/tcp"
        echo -e "        sudo firewall-cmd --reload"
    fi
fi
echo ""

LOG_FILE="$LOG_DIR/sunflower_proxy.log"
PID_FILE="$RUN_DIR/sunflower_proxy.pid"

echo -e "${GREEN}正在启动...${NC}"
nohup "$PYTHON_BIN" "$INSTALL_DIR/sunflower_proxy.py" > "$LOG_FILE" 2>&1 &
PID=$!
echo $PID > "$PID_FILE"
sleep 2

if ps -p "$PID" > /dev/null 2>&1; then
    echo -e "${GREEN}[OK] 代理网关已在后台运行，PID: $PID${NC}"
    echo -e "${GREEN}日志查看: tail -f $LOG_FILE${NC}"
    echo ""
    echo -e "${BLUE}常用命令:${NC}"
    echo -e "  查看日志: tail -f $LOG_FILE"
    echo -e "  停止服务: kill \$(cat $PID_FILE)"
    echo -e "  重启服务: kill \$(cat $PID_FILE) && bash $0"
else
    echo -e "${RED}[ERROR] 启动失败，查看日志:${NC}"
    tail -n 30 "$LOG_FILE" 2>/dev/null || true
    exit 1
fi
