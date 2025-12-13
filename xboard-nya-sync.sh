#!/bin/bash

# ==========================================
# 配置与基础变量
# ==========================================

# 获取脚本真实物理路径
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
BASE_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# 脚本文件名与相关配置
SCRIPT_NAME=$(basename "$SOURCE")
CONFIG_FILE="$BASE_DIR/config.conf"
PID_FILE="$BASE_DIR/ip-sync.pid"
SERVICE_NAME="ip-sync"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LINK_PATH="/usr/bin/ip-sync"

# 检查依赖
for cmd in jq curl ping; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 未找到 $cmd 命令。请先安装它 (例如: apt-get install $cmd)"
        exit 1
    fi
done

# 加载配置函数
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        if [ "$1" == "force" ]; then
             echo "错误: 找不到配置文件 $CONFIG_FILE"
             exit 1
        fi
    fi
}

# 日志函数
log() {
    local msg="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_target="${Log_File:-$BASE_DIR/ip-sync.log}"
    echo "[$timestamp] $msg" >> "$log_target"
}

# 日志清理函数：保留最近 N 行
clean_log() {
    local log_target="${Log_File:-$BASE_DIR/ip-sync.log}"
    local max_lines="${Log_Max_Lines:-0}" 

    if [[ "$max_lines" -gt 0 ]] && [ -f "$log_target" ]; then
        local current_lines=$(wc -l < "$log_target")
        if [ "$current_lines" -gt "$max_lines" ]; then
            tail -n "$max_lines" "$log_target" > "$log_target.tmp" && mv "$log_target.tmp" "$log_target"
        fi
    fi
}

# 判断字符串是否为 IP 地址
is_ip() {
    if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取域名的当前解析 IP (使用 ping - 本地 DNS)
# 作为 CF API 失败时的备用方案
get_domain_ip() {
    local domain=$1
    # 尝试 ping 1 次，超时 2 秒
    local ping_res=$(ping -c 1 -W 2 "$domain" 2>/dev/null | head -n 1)
    # 提取括号内的 IP
    local ip=$(echo "$ping_res" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    echo "$ip"
}

# ==========================================
# Cloudflare API 相关逻辑
# ==========================================

# 递归查找 Zone ID
# 输入: a.b.example.com -> 尝试查找 a.b.example.com -> b.example.com -> example.com
get_cf_zone_id() {
    local domain=$1
    local token=$2
    local current_domain=$domain
    
    while [[ "$current_domain" == *"."* ]]; do
        local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$current_domain" \
              -H "Authorization: Bearer $token" \
              -H "Content-Type: application/json")
        
        local zone_id=$(echo "$response" | jq -r '.result[0].id // empty')
        
        if [ -n "$zone_id" ]; then
            echo "$zone_id"
            return 0
        fi
        
        # 去掉最左边的一段，继续尝试
        current_domain=${current_domain#*.}
    done
    
    return 1
}

# 直接从 Cloudflare API 获取域名配置的 IP
# 避免 DNS 传播延迟导致的获取旧 IP 问题
get_cf_record_ip() {
    local domain=$1
    local token=$2

    if [ -z "$token" ]; then
        return 1
    fi

    # 1. 获取 Zone ID (复用现有函数)
    local zone_id=$(get_cf_zone_id "$domain" "$token")
    if [ -z "$zone_id" ]; then
        # 找不到 Zone ID，说明该域名不在此 CF 账号下
        return 1
    fi

    # 2. 获取 A 记录的 Content (IP)
    local record_res=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$domain&type=A" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json")
    
    local ip=$(echo "$record_res" | jq -r '.result[0].content // empty')
    
    echo "$ip"
}

# 更新 Cloudflare DNS (核心修改部分)
update_cf_dns() {
    local domain=$1
    local new_ip=$2 # 这里的 new_ip 应当是转发的入口IP
    
    if [ -z "$CF_Token" ]; then
        log "Error: 检测到域名 [$domain] 需要更新，但未配置 CF_Token"
        return 1
    fi

    # 1. 获取 Zone ID
    local zone_id=$(get_cf_zone_id "$domain" "$CF_Token")
    if [ -z "$zone_id" ]; then
        log "Error: 无法在 Cloudflare 找到域名 [$domain] 对应的 Zone ID，请检查 Token 权限或域名归属。"
        return 1
    fi

    # 2. 获取 DNS 记录 ID (只查找 A 记录)
    local record_res=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$domain&type=A" \
        -H "Authorization: Bearer $CF_Token" \
        -H "Content-Type: application/json")
    
    local record_id=$(echo "$record_res" | jq -r '.result[0].id // empty')
    
    # 获取当前的代理状态，如果记录不存在，默认为 false
    local current_proxied=$(echo "$record_res" | jq -r '.result[0].proxied // false')

    if [ -z "$record_id" ]; then
        # ==========================================
        # 记录不存在，执行创建逻辑 (POST)
        # ==========================================
        log "Info: CF 记录不存在，正在创建: [$domain] -> [$new_ip]"
        
        # 新建记录强制不走代理 (proxied: false)，除非你有特殊需求改为 true
        local create_res=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
            -H "Authorization: Bearer $CF_Token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$new_ip\",\"ttl\":1,\"proxied\":false}")
        
        if [[ $(echo "$create_res" | jq -r '.success') == "true" ]]; then
            log "Success: Cloudflare 记录 [$domain] 创建成功 -> $new_ip"
        else
            log "Fail: Cloudflare 创建失败 - $(echo "$create_res" | jq -r '.errors[0].message')"
        fi
    else
        # ==========================================
        # 记录存在，执行更新逻辑 (PUT)
        # ==========================================
        local update_res=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
            -H "Authorization: Bearer $CF_Token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$new_ip\",\"ttl\":1,\"proxied\":$current_proxied}")
            
        if [[ $(echo "$update_res" | jq -r '.success') == "true" ]]; then
            log "Success: Cloudflare 记录 [$domain] 更新成功 -> $new_ip (Zone: $zone_id)"
        else
            log "Fail: Cloudflare 更新失败 - $(echo "$update_res" | jq -r '.errors[0].message')"
        fi
    fi
}

# ==========================================
# 核心业务逻辑
# ==========================================

# 1. 机场登录
login_airport() {
    local response=$(curl -s -X POST "${Airport_Url}/api/v1/passport/auth/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "email=${Airport_Email}" \
        --data-urlencode "password=${Airport_Pass}" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

    AIRPORT_TOKEN=$(echo "$response" | jq -r '.data.auth_data // empty')
    
    if [ -z "$AIRPORT_TOKEN" ]; then
        log "Error: 机场登录失败 - $(echo "$response" | jq -r '.message')"
        return 1
    fi
    return 0
}

# 2. 转发服务登录
login_forward() {
    local response=$(curl -s -X POST "${Forward_Url}/api/v1/auth/login" \
        -H "Content-Type: text/plain;charset=UTF-8" \
        --data-raw "{\"username\":\"${Forward_User}\",\"password\":\"${Forward_Pass}\"}" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

    FORWARD_TOKEN=$(echo "$response" | jq -r '.data // empty')

    if [ -z "$FORWARD_TOKEN" ] || [ "$FORWARD_TOKEN" == "null" ]; then
        log "Error: 转发登录失败 - $(echo "$response" | jq -r '.msg')"
        return 1
    fi
    return 0
}

# 3. 获取转发入口IP映射
get_forward_groups() {
    # 这一步获取的是转发服务器的入口地址(connect_host)
    local response=$(curl -s "${Forward_Url}/api/v1/user/devicegroup" \
        -H "Authorization: ${FORWARD_TOKEN}")
    
    echo "$response" | jq -r '
        .data[] 
        | select(.connect_host != null) 
        | "\(.id)=\(.connect_host | split("\n")[0] | split("\\n")[0])"
    ' > "$BASE_DIR/forward_groups.map"
}

# 4. 更新机场节点 (仅 IP 变更或端口变更时使用)
update_airport_node() {
    local node_json="$1"
    local new_host="$2"
    local new_port="$3"
    
    local id=$(echo "$node_json" | jq -r '.id')
    local name=$(echo "$node_json" | jq -r '.name')
    local cipher=$(echo "$node_json" | jq -r '.cipher')
    local rate=$(echo "$node_json" | jq -r '.rate')
    local server_port=$(echo "$node_json" | jq -r '.server_port')
    local sort=$(echo "$node_json" | jq -r '.sort')
    local show=$(echo "$node_json" | jq -r '.show')
    local created_at=$(echo "$node_json" | jq -r '.created_at // empty')
    local updated_at=$(echo "$node_json" | jq -r '.updated_at // empty')
    local type=$(echo "$node_json" | jq -r '.type')
    local obfs_host=$(echo "$node_json" | jq -r '.obfs_settings.host // empty')
    
    local group_data=""
    local g_idx=0
    for gid in $(echo "$node_json" | jq -r '.group_id[] // empty'); do
        group_data="${group_data}&group_id[${g_idx}]=${gid}"
        ((g_idx++))
    done

    if [ -z "$group_data" ]; then
        log "Error: 节点 [$name] 的 group_id 为空，跳过更新。"
        return 1
    fi

    local update_res=$(curl -s -X POST "${Airport_Url}/api/v1/sysadmin/server/shadowsocks/save" \
        -H "Authorization: ${AIRPORT_TOKEN}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        --data-urlencode "id=${id}" \
        --data "route_id=&parent_id=&tags=&excludes=&ips=${group_data}" \
        --data-urlencode "name=${name}" \
        --data-urlencode "rate=${rate}" \
        --data-urlencode "host=${new_host}" \
        --data-urlencode "port=${new_port}" \
        --data-urlencode "server_port=${server_port}" \
        --data-urlencode "cipher=${cipher}" \
        --data-urlencode "obfs=" \
        --data-urlencode "obfs_settings[host]=${obfs_host}" \
        --data-urlencode "show=${show}" \
        --data-urlencode "sort=${sort}" \
        --data-urlencode "created_at=${created_at}" \
        --data-urlencode "updated_at=${updated_at}" \
        --data-urlencode "type=${type}" \
        --data "online=1&available_status=1")
    
    local status=$(echo "$update_res" | jq -r '.status // "fail"')
    if [ "$status" == "success" ]; then
        log "Success: 节点 [$name] (ID:$id) 已推送到机场 -> Host: $new_host, Port: $new_port"
    else
        log "Fail: 节点 [$name] 更新失败 - $(echo "$update_res" | jq -r '.message')"
    fi
}

# 5. 执行同步检查
do_sync_task() {
    log "开始同步检查..."

    login_airport || return
    login_forward || return

    get_forward_groups
    declare -A GROUP_IP_MAP
    if [ -f "$BASE_DIR/forward_groups.map" ]; then
        while IFS='=' read -r key val; do
            GROUP_IP_MAP[$key]=$val
        done < "$BASE_DIR/forward_groups.map"
    fi

    local forward_rules_json=$(curl -s "${Forward_Url}/api/v1/user/forward?page=1&size=100" \
        -H "Authorization: ${FORWARD_TOKEN}")
    
    local airport_nodes_json=$(curl -s "${Airport_Url}/api/v1/sysadmin/server/manage/getNodes" \
        -H "Authorization: ${AIRPORT_TOKEN}")

    echo "$airport_nodes_json" | jq -c '.data[]' | while read -r node; do
        local node_name=$(echo "$node" | jq -r '.name')
        local node_host=$(echo "$node" | jq -r '.host')
        local node_port=$(echo "$node" | jq -r '.port')
        local node_type=$(echo "$node" | jq -r '.type')

        # 只处理 Shadowsocks 类型
        if [ "$node_type" != "shadowsocks" ]; then
            continue
        fi

        # 匹配规则：通过节点名称包含关系查找转发规则
        local matched_rule=$(echo "$forward_rules_json" | jq -c --arg nname "$node_name" '.data[] | select(.name | contains($nname))' | head -n 1)

        if [ -n "$matched_rule" ]; then
            local rule_name=$(echo "$matched_rule" | jq -r '.name')
            local group_in=$(echo "$matched_rule" | jq -r '.device_group_in')
            local listen_port=$(echo "$matched_rule" | jq -r '.listen_port')
            
            # forward_ip 是转发入口IP（中转机的IP），这就是我们要做对比和同步的标准IP
            local forward_ip="${GROUP_IP_MAP[$group_in]}"

            if [ -z "$forward_ip" ]; then
                log "Warning: 找到规则 [$rule_name] 但无法解析入口组 ID [$group_in] 的 IP"
                continue
            fi

            # ==== 核心逻辑分叉 ====
            if is_ip "$node_host"; then
                # 场景 A: 机场节点地址是 IP
                # 逻辑：直接对比 IP 是否一致，不一致则把机场节点的 Host 改为 forward_ip
                if [ "$node_host" != "$forward_ip" ] || [ "$node_port" != "$listen_port" ]; then
                    log "变更检测(IP模式): 节点 [$node_name] ($node_host) -> 转发 ($forward_ip)"
                    update_airport_node "$node" "$forward_ip" "$listen_port"
                fi
            else
                # 场景 B: 机场节点地址是域名
                local current_domain_ip=""
                
                # 逻辑 1: 优先尝试从 Cloudflare API 获取真实的 A 记录 IP
                if [ -n "$CF_Token" ]; then
                    current_domain_ip=$(get_cf_record_ip "$node_host" "$CF_Token")
                fi

                # 逻辑 2: 如果 CF 获取失败（域名不在 CF 或 Token 错误），回退到本地 Ping 解析
                if [ -z "$current_domain_ip" ]; then
                    current_domain_ip=$(get_domain_ip "$node_host")
                fi
                
                # 逻辑 3: 检查端口是否变更 (端口必须同步)
                if [ "$node_port" != "$listen_port" ]; then
                    log "变更检测(域名模式-端口): 节点 [$node_name] 端口 $node_port -> $listen_port"
                    # 注意：这里第二个参数传入 "$node_host"，即保持原来的域名字符串不变，只更新端口
                    update_airport_node "$node" "$node_host" "$listen_port"
                fi

                # 逻辑 4: 检查域名解析 IP 是否与转发入口 IP (forward_ip) 一致
                if [ -z "$current_domain_ip" ]; then
                    # 关键修改：如果解析不到 IP，说明记录不存在或解析失效，直接调用 CF 更新(创建)
                    log "Info: 域名 [$node_host] 未解析到 IP (记录可能不存在)，正在请求创建并指向 [$forward_ip]..."
                    update_cf_dns "$node_host" "$forward_ip"
                elif [ "$current_domain_ip" != "$forward_ip" ]; then
                    log "变更检测(域名模式-DNS): 域名 [$node_host] 当前解析($current_domain_ip) != 转发入口($forward_ip)"
                    # 修改 Cloudflare DNS，将域名指向转发入口 IP
                    update_cf_dns "$node_host" "$forward_ip"
                else
                    # IP 一致，无需操作
                    :
                fi
            fi
        fi
    done
    
    log "同步检查完成。"
}

# ==========================================
# 进程与菜单控制逻辑
# ==========================================

run_loop() {
    load_config "force"
    log "服务启动，PID: $$"
    while true; do
        load_config
        
        # 执行同步任务
        do_sync_task
        
        # 检查并清理日志
        clean_log

        sleep "${Check_Interval:-60}"
    done
}

start() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "\033[32m服务正在运行中 (PID: $pid)\033[0m"
            return
        else
            rm "$PID_FILE"
        fi
    fi

    echo "正在启动 ip-sync 服务..."
    nohup "$BASE_DIR/$SCRIPT_NAME" run_loop > /dev/null 2>&1 &
    local new_pid=$!
    echo $new_pid > "$PID_FILE"
    echo -e "\033[32m启动成功 (PID: $new_pid)\033[0m"
}

stop() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        echo "正在停止服务 (PID: $pid)..."
        kill "$pid" 2>/dev/null
        rm "$PID_FILE"
        echo -e "\033[31m服务已停止。\033[0m"
    else
        echo "服务未运行。"
    fi
}

reload() {
    echo "正在重新加载服务..."
    stop
    sleep 1
    start
}

edit_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "配置文件不存在，正在创建空文件..."
        touch "$CONFIG_FILE"
    fi
    vi "$CONFIG_FILE"
    echo -e "\033[33m配置编辑已退出。\033[0m"
    read -p "是否立即重载服务以应用更改？(y/n) [y]: " confirm
    confirm=${confirm:-y}
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        reload
    else
        echo "未重载，更改将在下次重启后生效。"
    fi
}

view_logs() {
    load_config
    local log_target="${Log_File:-$BASE_DIR/ip-sync.log}"
    
    if [ ! -f "$log_target" ]; then
        echo -e "\033[31m错误：日志文件不存在 ($log_target)\033[0m"
        echo "可能是服务尚未运行，或未生成日志。"
        return
    fi
    
    echo -e "\033[32m正在实时查看日志 (最后 50 行)... 按 Ctrl+C 退出查看\033[0m"
    echo "日志路径: $log_target"
    echo -e "\033[36m--------------------------------------------------\033[0m"
    tail -f -n 50 "$log_target"
}

install_app() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "\033[31m错误：安装服务需要 root 权限，请使用 sudo 运行脚本。\033[0m"
        exit 1
    fi

    chmod +x "$BASE_DIR/$SCRIPT_NAME"

    echo "正在创建 Systemd 服务..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=IP Sync Automation Service
After=network.target

[Service]
Type=forking
ExecStart=$BASE_DIR/$SCRIPT_NAME start
ExecStop=$BASE_DIR/$SCRIPT_NAME stop
PIDFile=$PID_FILE
Restart=on-failure
User=root
WorkingDirectory=$BASE_DIR

[Install]
WantedBy=multi-user.target
EOF

    echo "正在创建全局命令链接: $LINK_PATH ..."
    ln -sf "$BASE_DIR/$SCRIPT_NAME" "$LINK_PATH"

    echo "正在重载系统服务配置..."
    systemctl daemon-reload
    echo "正在设置开机自启..."
    systemctl enable "$SERVICE_NAME"
    
    echo -e "\033[32m安装完成！\033[0m"
    echo -e "您现在可以在任何目录下输入 \033[36mip-sync\033[0m 来管理服务。"
    
    read -p "是否立即启动服务？(y/n) [y]: " run_now
    run_now=${run_now:-y}
    if [[ "$run_now" == "y" || "$run_now" == "Y" ]]; then
        reload
    fi
}

uninstall_app() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "\033[31m错误：卸载服务需要 root 权限，请使用 sudo 运行脚本。\033[0m"
        exit 1
    fi

    echo "正在停止服务并禁用开机自启..."
    stop
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    if [ -f "$SERVICE_FILE" ]; then
        rm "$SERVICE_FILE"
        echo "服务文件已移除。"
    fi
    
    if [ -L "$LINK_PATH" ]; then
        rm "$LINK_PATH"
        echo "全局命令链接已移除。"
    fi

    systemctl daemon-reload
    echo -e "\033[32m卸载完成。\033[0m"
}

check_status() {
    local pid_status="\033[31m未运行\033[0m"
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            pid_status="\033[32m运行中 (PID: $pid)\033[0m"
        fi
    fi

    local boot_status="\033[31m未开启\033[0m"
    if command -v systemctl &> /dev/null; then
        if systemctl is-enabled "$SERVICE_NAME" &> /dev/null; then
             boot_status="\033[32m已开启\033[0m"
        fi
    else
        boot_status="\033[33m无法检测(systemctl)\033[0m"
    fi
    
    echo -e "当前状态: [运行: ${pid_status}]  [开机自启: ${boot_status}]"
    echo -e "程序目录: $BASE_DIR"
}

show_menu() {
    clear
    echo -e "\n\033[36m================ IP Sync 管理菜单 ================\033[0m"
    check_status
    echo -e "\033[36m--------------------------------------------------\033[0m"
    echo -e " 1. \033[32m启动服务\033[0m (Start)"
    echo -e " 2. \033[31m停止服务\033[0m (Stop)"
    echo -e " 3. \033[33m重启服务\033[0m (Reload)"
    echo -e " 4. \033[34m安装服务\033[0m (注册 Systemd & 全局命令)"
    echo -e " 5. \033[35m卸载服务\033[0m (清理 Systemd & 全局命令)"
    echo -e " 6. \033[37m编辑配置\033[0m (使用 vi 编辑 config.conf)"
    echo -e " 7. \033[36m运行日志\033[0m (实时查看 tail -f)"
    echo -e " 0. \033[37m退出菜单\033[0m"
    echo -e "\033[36m==================================================\033[0m"
    
    read -p "请输入选项 [0-7]: " choice
    case "$choice" in
        1) start ;;
        2) stop ;;
        3) reload ;;
        4) install_app ;;
        5) uninstall_app ;;
        6) edit_config ;;
        7) view_logs ;;
        0) exit 0 ;;
        *) echo "无效选项，请重试。" ;;
    esac
    
    if [ "$choice" != "0" ]; then
        echo ""
        read -p "按回车键返回菜单..."
        show_menu
    fi
}

if [ $# -gt 0 ]; then
    case "$1" in
        start) start ;;
        stop) stop ;;
        reload) reload ;;
        run_loop) run_loop ;;
        install) install_app ;;
        uninstall) uninstall_app ;;
        status) check_status ;;
        logs) view_logs ;;
        *) echo "用法: $0 {start|stop|reload|install|uninstall|status|logs}" ; exit 1 ;;
    esac
else
    show_menu
fi