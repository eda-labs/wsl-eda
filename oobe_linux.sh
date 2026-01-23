#!/bin/bash

function find_working_proxies {
    local proxies=("$@")
    local tmpdir=$(mktemp -d)
    local port="8080"

    # Test all proxies in parallel via curl (actually verify HTTP works)
    for ip in "${proxies[@]}"; do
        (
            # Measure time to curl through proxy (use HTTPS to verify full proxy functionality)
            result=$(curl -x "http://${ip}:${port}" -s -o /dev/null -w "%{time_total}" --connect-timeout 3 --max-time 5 https://github.com 2>/dev/null)
            # Only record if curl succeeded and we got a time
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                echo "$result $ip" > "$tmpdir/$ip"
            fi
        ) &
    done
    wait

    # Return all working proxies sorted by speed (fastest first)
    cat "$tmpdir"/* 2>/dev/null | sort -n | awk '{print $2}'
    rm -rf "$tmpdir"
}

function select_proxy_region {
    PROXY_PORT="8080"

    # Ask user for their region
    echo -e "\nPlease select your region:"
    echo "  1) EU   (Europe)"
    echo "  2) NAM  (North America)"
    echo "  3) APJ  (Asia-Pacific & Japan)"
    echo "  4) IN   (India)"
    echo "  5) LAT  (Latin America)"
    echo "  6) MEA  (Middle East & Africa)"
    echo "  7) CN   (Greater China)"
    read -p "Enter choice [1-7]: " -n 1 -r REGION_CHOICE
    echo

    # Define proxy lists per region (from proxy_list.txt)
    EU_PROXIES=(10.158.100.1 10.158.100.2 10.158.100.49 10.158.100.51 10.158.100.57 10.158.100.62 10.158.100.63 10.158.100.66 10.158.100.67 10.158.100.72 10.158.100.78 10.158.100.82 10.158.100.95 10.158.100.100 10.158.100.108 10.158.100.112 10.158.100.114 10.158.100.115 10.158.100.120 10.158.100.133 10.158.100.149 10.158.100.153 10.158.100.154 10.158.100.160 10.158.100.167 10.158.100.168 10.158.100.175 10.158.100.179 10.158.100.181 10.158.100.194 10.158.100.202)
    NAM_PROXIES=(10.158.100.3 10.158.100.4 10.158.100.34 10.158.100.44 10.158.100.58 10.158.100.124 10.158.100.140 10.158.100.173 10.158.100.190)
    APJ_PROXIES=(10.158.100.9 10.158.101.1 10.158.100.105 10.158.100.111 10.158.100.113 10.158.100.117 10.158.100.118 10.158.100.132 10.158.100.134 10.158.100.136 10.158.100.144 10.158.100.204)
    IN_PROXIES=(10.158.100.6 10.158.100.7 10.158.100.21 10.158.100.22 10.158.100.23 10.158.100.35 10.158.100.74 10.158.100.80 10.158.100.81 10.158.100.83 10.158.100.89 10.158.100.91 10.158.100.92 10.158.100.99 10.158.100.106 10.158.100.107 10.158.100.121 10.158.100.151 10.158.100.171 10.158.100.174 10.158.100.184 10.158.100.195 10.158.100.196 10.158.100.197)
    LAT_PROXIES=(10.158.100.5 10.158.100.39 10.158.100.46 10.158.100.98 10.158.100.122 10.158.100.128 10.158.100.129 10.158.100.131 10.158.100.166 10.158.100.180 10.158.100.187)
    MEA_PROXIES=(10.158.100.60 10.158.100.64 10.158.100.68 10.158.100.69 10.158.100.109 10.158.100.110 10.158.100.123 10.158.100.141 10.158.100.142 10.158.100.150 10.158.100.159 10.158.100.169 10.158.100.201 10.158.100.203)
    CN_PROXIES=(10.158.100.8 10.158.100.85 10.158.100.101 10.158.100.103 10.158.100.156 10.158.100.157 10.158.100.165)

    local region_name=""
    local fallback=""
    local -a proxy_list

    case $REGION_CHOICE in
        1) region_name="EU"; fallback="10.158.100.2"; proxy_list=("${EU_PROXIES[@]}") ;;
        2) region_name="NAM"; fallback="10.158.100.4"; proxy_list=("${NAM_PROXIES[@]}") ;;
        3) region_name="APJ"; fallback="10.158.101.1"; proxy_list=("${APJ_PROXIES[@]}") ;;
        4) region_name="India"; fallback="10.158.100.6"; proxy_list=("${IN_PROXIES[@]}") ;;
        5) region_name="LAT"; fallback="10.158.100.5"; proxy_list=("${LAT_PROXIES[@]}") ;;
        6) region_name="MEA"; fallback="10.158.100.110"; proxy_list=("${MEA_PROXIES[@]}") ;;
        7) region_name="CN"; fallback="10.158.100.8"; proxy_list=("${CN_PROXIES[@]}") ;;
        *)
            echo -e "\033[33mInvalid choice. Defaulting to EU.\033[0m"
            region_name="EU"; fallback="10.158.100.2"; proxy_list=("${EU_PROXIES[@]}")
            ;;
    esac

    echo -n "Finding working ${region_name} proxies... "
    local working_proxies
    working_proxies=$(find_working_proxies "${proxy_list[@]}")

    if [ -z "$working_proxies" ]; then
        echo -e "\033[33mnone found, using fallback\033[0m"
        PROXY_HOST="$fallback"
    else
        # Try each working proxy in order (fastest first)
        local first=true
        for proxy in $working_proxies; do
            if $first; then
                echo -e "\033[32m$proxy\033[0m"
                first=false
            else
                echo -e "\033[33mTrying next proxy...\033[0m $proxy"
            fi

            PROXY_HOST="$proxy"

            # Configure and test this proxy
            PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
            NO_PROXY="localhost,127.0.0.1,::1,.nokia.net,.nokia.com,.int.nokia.com,.nsn-net.net,.nsn-intra.net,.inside.nsn.com,.noklab.net,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

            echo "HTTP_PROXY=$PROXY_URL" | sudo tee /etc/proxy.conf > /dev/null
            echo "HTTPS_PROXY=$PROXY_URL" | sudo tee -a /etc/proxy.conf > /dev/null
            echo "NO_PROXY=$NO_PROXY" | sudo tee -a /etc/proxy.conf > /dev/null

            yes y | sudo SUDO_USER=eda SUDO_UID=1000 SUDO_GID=1000 proxyman set > /dev/null 2>&1
            eval "$(sudo /usr/local/bin/proxyman export)"

            # Verify it actually works
            if curl -fsSL --connect-timeout 5 https://github.com >/dev/null 2>&1; then
                echo -e "\033[32mProxy configured: $PROXY_HOST\033[0m"
                return 0
            fi
        done

        # All proxies failed, try fallback
        echo -e "\033[33mAll proxies failed, trying fallback...\033[0m"
        PROXY_HOST="$fallback"
    fi

    # Configure fallback proxy
    PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
    NO_PROXY="localhost,127.0.0.1,::1,.nokia.net,.nokia.com,.int.nokia.com,.nsn-net.net,.nsn-intra.net,.inside.nsn.com,.noklab.net,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

    echo "HTTP_PROXY=$PROXY_URL" | sudo tee /etc/proxy.conf > /dev/null
    echo "HTTPS_PROXY=$PROXY_URL" | sudo tee -a /etc/proxy.conf > /dev/null
    echo "NO_PROXY=$NO_PROXY" | sudo tee -a /etc/proxy.conf > /dev/null

    yes y | sudo SUDO_USER=eda SUDO_UID=1000 SUDO_GID=1000 proxyman set > /dev/null 2>&1
    eval "$(sudo /usr/local/bin/proxyman export)"

    echo -e "\033[32mProxy configured: $PROXY_HOST\033[0m"
    return 0
}

function auto_configure_proxy {
    PROXY_HOST="globalproxy.glb.nokia.com"
    PROXY_PORT="8080"

    echo -n "Detecting proxy... "

    # Check if the proxy hostname resolves
    if ! dig +short "$PROXY_HOST" | grep -q .; then
        echo -e "\033[33mnot found\033[0m"
        return 1
    fi

    # Test if the proxy is reachable
    if ! curl -x "http://${PROXY_HOST}:${PROXY_PORT}" -s -o /dev/null --connect-timeout 5 http://www.github.com 2>/dev/null; then
        echo -e "\033[33mfailed\033[0m"
        return 1
    fi

    echo -e "\033[32mdetected\033[0m"

    select_proxy_region
    return $?
}

function prompt_proxy {
    read -p "Are you behind a proxy that you want to configure now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "\nPlease provide your HTTP_PROXY URL (e.g. http://proxy.example.com:8080):"
        read -r HTTP_PROXY
        echo -e "\nPlease provide your HTTPS_PROXY URL (often the same as HTTP_PROXY):"
        read -r HTTPS_PROXY
        echo -e "\nPlease provide your NO_PROXY list (default: localhost,127.0.0.1,::1):"
        read -r NO_PROXY
        [ -z "$NO_PROXY" ] && NO_PROXY="localhost,127.0.0.1,::1"

        echo -e "\nWriting proxy configuration to /etc/proxy.conf..."
        echo "HTTP_PROXY=$HTTP_PROXY" | sudo tee /etc/proxy.conf > /dev/null
        echo "HTTPS_PROXY=$HTTPS_PROXY" | sudo tee -a /etc/proxy.conf > /dev/null
        echo "NO_PROXY=$NO_PROXY" | sudo tee -a /etc/proxy.conf > /dev/null

        echo -e "\nConfiguring system-wide proxy using proxyman..."
        yes y | sudo SUDO_USER=eda SUDO_UID=1000 SUDO_GID=1000 proxyman set > /dev/null 2>&1
        echo -e "\nProxy has been set. You can run 'sudo proxyman unset' to remove it."
        eval "$(sudo /usr/local/bin/proxyman export)"
    else
        echo -e "\nSkipping proxy configuration.\n"
    fi
}

function import_corporate_certs {
    echo -e "\033[34m\nImporting corporate/Zscaler certificates...\033[0m"

    # Check for certificates in common locations
    CERT_COUNT=0
    CERT_DIRS=("/etc/ssl/corporate" "/usr/local/share/corporate-certs" "/opt/certs")

    for dir in "${CERT_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            for cert in "$dir"/*.crt "$dir"/*.pem; do
                if [ -f "$cert" ]; then
                    CERT_NAME=$(basename "$cert")
                    sudo cp "$cert" "/usr/local/share/ca-certificates/${CERT_NAME%.pem}.crt"
                    ((CERT_COUNT++))
                fi
            done
        fi
    done

    # Also check if certs were mounted via Docker volume
    if [ -d "/certs" ]; then
        for cert in /certs/*.crt /certs/*.pem; do
            if [ -f "$cert" ]; then
                CERT_NAME=$(basename "$cert")
                sudo cp "$cert" "/usr/local/share/ca-certificates/${CERT_NAME%.pem}.crt"
                ((CERT_COUNT++))
            fi
        done
    fi

    if [ $CERT_COUNT -gt 0 ]; then
        sudo update-ca-certificates --fresh > /dev/null 2>&1
        echo -e "\033[32mImported $CERT_COUNT corporate certificate(s).\033[0m"
    else
        echo -e "\033[33mNo corporate certificates found to import.\033[0m"
        echo -e "To add certificates, mount them to /certs or place them in:"
        echo -e "  /etc/ssl/corporate, /usr/local/share/corporate-certs, or /opt/certs"
        echo -e "Then run: sudo update-ca-certificates"
    fi
}

function install_shell_config {
    echo -e "\033[34mInstalling shell configuration...\033[0m"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create directories
    mkdir -p /home/eda/.local/bin
    mkdir -p /home/eda/.zsh/completions
    mkdir -p /home/eda/.config/k9s/skins

    # Install scripts
    cp "$SCRIPT_DIR/zsh/scripts/"* /home/eda/.local/bin/
    chmod +x /home/eda/.local/bin/edactl /home/eda/.local/bin/node-shell /home/eda/.local/bin/node-ssh

    # Install completions
    cp "$SCRIPT_DIR/zsh/completions/"* /home/eda/.zsh/completions/

    # Install k9s theme
    cp "$SCRIPT_DIR/k9s/dracula.yaml" /home/eda/.config/k9s/skins/

    # Install zshrc and starship config
    cp "$SCRIPT_DIR/zsh/.zshrc" /home/eda/.zshrc
    cp "$SCRIPT_DIR/zsh/starship.toml" /home/eda/.config/starship.toml

    # Fix ownership
    chown -R eda:eda /home/eda/.local /home/eda/.zsh /home/eda/.config /home/eda/.zshrc

    echo -e "\033[32mShell configuration installed.\033[0m"
}

function setup_ssh_keys {
    echo -e "\033[34mSetting up SSH...\033[0m"

    mkdir -p /home/eda/.ssh
    chmod 700 /home/eda/.ssh

    # Check if SSH keys were mounted
    if [ -f "/home/eda/.ssh/authorized_keys" ]; then
        chmod 600 /home/eda/.ssh/authorized_keys
        echo -e "\033[32mSSH authorized_keys found.\033[0m"
    elif [ -f "/ssh-keys/authorized_keys" ]; then
        cp /ssh-keys/authorized_keys /home/eda/.ssh/authorized_keys
        chmod 600 /home/eda/.ssh/authorized_keys
        echo -e "\033[32mSSH keys imported from /ssh-keys.\033[0m"
    else
        echo -e "\033[33mNo SSH keys found.\033[0m"
        echo -e "To enable SSH access, mount authorized_keys to /ssh-keys/authorized_keys"
    fi

    chown -R eda:eda /home/eda/.ssh
}

# --- Handle command line arguments ---
if [ "$1" = "--proxy" ] || [ "$1" = "-p" ]; then
    select_proxy_region
    exit $?
fi

# --- Start OOBE ---
clear
printf "
       \033[38;2;255;124;88m\342\242\200\033[38;2;255;218;152m\342\242\200\033[38;2;255;115;123m\342\241\204\033[38;2;255;197;123m\342\243\240\033[38;2;255;179;106m\342\243\246\033[38;2;252;111;48m\342\243\264\033[38;2;255;195;123m\342\243\216\033[38;2;255;197;129m\342\243\244\033[38;2;255;197;128m\342\240\226\033[38;2;255;170;142m\342\242\200\033[38;2;255;136;135m\342\241\200\033[0m     \033[0m
     \033[38;2;255;167;7m\342\242\240\033[38;2;252;185;65m\342\243\244\033[38;2;253;143;93m\342\243\277\033[38;2;252;195;143m\342\243\277\033[38;2;246;128;79m\342\243\277\033[38;2;229;121;83m\342\243\277\033[38;2;244;150;123m\342\243\277\033[38;2;244;164;137m\342\243\277\033[38;2;243;170;132m\342\243\277\033[38;2;253;183;152m\342\243\266\033[38;2;255;162;126m\342\243\277\033[38;2;255;81;63m\342\243\257\033[38;2;255;131;41m\342\243\264\033[38;2;254;122;52m\342\241\266\033[38;2;255;75;14m\342\240\202\033[0m   \033[0m
     \033[38;2;249;168;21m\342\243\274\033[38;2;238;76;97m\342\243\277\033[38;2;246;198;130m\342\243\277\033[38;2;216;171;144m\342\243\277\033[38;2;225;181;79m\342\243\277\033[38;2;232;145;43m\342\243\277\033[38;2;218;95;66m\342\243\277\033[38;2;221;179;132m\342\243\277\033[38;2;239;203;163m\342\243\277\033[38;2;228;143;121m\342\243\277\033[38;2;252;193;144m\342\243\277\033[38;2;251;202;165m\342\243\277\033[38;2;251;164;159m\342\243\277\033[38;2;252;150;151m\342\243\277\033[38;2;253;140;132m\342\243\237\033[38;2;253;147;108m\342\243\201\033[38;2;255;89;1m\342\241\200\033[0m \033[0m        \033[38;2;128;20;216m\342\242\270\033[38;2;124;23;217m\342\243\277\033[38;2;121;26;218m\342\243\277\033[38;2;118;30;219m\342\243\277\033[38;2;114;33;220m\342\243\277\033[38;2;111;37;221m\342\243\277\033[38;2;108;40;222m\342\243\277\033[38;2;104;43;223m\342\243\277\033[0m   \033[38;2;91;57;227m\342\243\277\033[38;2;88;60;228m\342\243\277\033[38;2;84;64;229m\342\243\277\033[38;2;81;67;230m\342\243\277\033[38;2;78;70;231m\342\243\277\033[38;2;74;74;232m\342\243\277\033[38;2;71;77;233m\342\243\266\033[38;2;68;80;234m\342\243\246\033[38;2;64;84;235m\342\243\204\033[0m     \033[38;2;44;104;241m\342\243\274\033[38;2;41;107;242m\342\243\277\033[38;2;38;111;243m\342\243\277\033[38;2;34;114;244m\342\243\277\033[38;2;31;117;245m\342\241\206\033[0m         \033[0m
     \033[38;2;197;102;56m\342\243\277\033[38;2;207;125;120m\342\243\277\033[38;2;180;125;117m\342\243\277\033[38;2;201;136;38m\342\243\277\033[38;2;193;106;54m\342\243\277\033[38;2;182;86;90m\342\243\277\033[38;2;171;121;83m\342\243\277\033[38;2;170;111;44m\342\243\277\033[38;2;176;101;32m\342\243\277\033[38;2;185;112;62m\342\243\277\033[38;2;214;111;104m\342\243\277\033[38;2;203;96;113m\342\243\277\033[38;2;194;85;115m\342\243\277\033[38;2;229;115;109m\342\243\277\033[38;2;253;150;101m\342\243\277\033[38;2;254;162;87m\342\243\277\033[38;2;255;213;58m\342\243\246\033[38;2;255;208;68m\342\241\200\033[0m        \033[38;2;128;20;216m\342\242\270\033[38;2;124;23;217m\342\243\277\033[38;2;121;26;218m\342\243\277\033[0m        \033[38;2;91;57;227m\342\243\277\033[38;2;88;60;228m\342\243\277\033[38;2;84;64;229m\342\241\207\033[0m  \033[38;2;74;74;232m\342\240\210\033[38;2;71;77;233m\342\240\273\033[38;2;68;80;234m\342\243\277\033[38;2;64;84;235m\342\243\277\033[38;2;61;87;236m\342\243\246\033[0m   \033[38;2;48;101;240m\342\243\260\033[38;2;44;104;241m\342\243\277\033[38;2;41;107;242m\342\243\277\033[38;2;38;111;243m\342\242\273\033[38;2;34;114;244m\342\243\277\033[38;2;31;117;245m\342\243\277\033[38;2;28;121;246m\342\241\200\033[0m        \033[0m
     \033[38;2;170;74;77m\342\242\273\033[38;2;98;44;105m\342\243\277\033[38;2;164;169;186m\342\243\277\033[38;2;194;206;228m\342\243\277\033[38;2;178;180;222m\342\243\277\033[38;2;163;167;212m\342\243\277\033[38;2;126;69;136m\342\243\277\033[38;2;83;27;100m\342\243\277\033[38;2;78;29;102m\342\243\277\033[38;2;117;19;97m\342\243\277\033[38;2;119;38;111m\342\243\277\033[38;2;160;59;91m\342\243\277\033[38;2;146;51;121m\342\243\277\033[38;2;180;30;96m\342\243\277\033[38;2;211;28;83m\342\243\277\033[38;2;219;17;71m\342\243\277\033[38;2;245;1;64m\342\243\246\033[38;2;255;0;43m\342\241\200\033[0m        \033[38;2;128;20;216m\342\242\270\033[38;2;124;23;217m\342\243\277\033[38;2;121;26;218m\342\243\277\033[38;2;118;30;219m\342\243\266\033[38;2;114;33;220m\342\243\266\033[38;2;111;37;221m\342\243\266\033[38;2;108;40;222m\342\243\266\033[38;2;104;43;223m\342\241\206\033[0m   \033[38;2;91;57;227m\342\243\277\033[38;2;88;60;228m\342\243\277\033[38;2;84;64;229m\342\241\207\033[0m    \033[38;2;68;80;234m\342\243\277\033[38;2;64;84;235m\342\243\277\033[38;2;61;87;236m\342\243\277\033[0m  \033[38;2;51;97;239m\342\242\240\033[38;2;48;101;240m\342\243\277\033[38;2;44;104;241m\342\243\277\033[38;2;41;107;242m\342\240\207\033[0m \033[38;2;34;114;244m\342\242\277\033[38;2;31;117;245m\342\243\277\033[38;2;28;121;246m\342\243\247\033[0m        \033[0m
     \033[38;2;160;194;230m\342\243\270\033[38;2;201;216;234m\342\243\277\033[38;2;168;190;223m\342\241\277\033[38;2;174;197;222m\342\240\277\033[38;2;186;196;217m\342\240\277\033[38;2;84;95;111m\342\242\277\033[38;2;73;84;100m\342\243\277\033[38;2;24;34;48m\342\243\277\033[38;2;40;50;120m\342\243\277\033[38;2;109;61;131m\342\243\277\033[38;2;205;4;55m\342\243\277\033[38;2;147;39;63m\342\243\277\033[38;2;247;66;57m\342\243\277\033[38;2;223;27;71m\342\243\277\033[38;2;216;96;96m\342\243\277\033[38;2;244;53;97m\342\243\277\033[38;2;202;9;103m\342\242\247\033[38;2;218;4;70m\342\241\211\033[0m        \033[38;2;128;20;216m\342\242\270\033[38;2;124;23;217m\342\243\277\033[38;2;121;26;218m\342\243\277\033[38;2;118;30;219m\342\240\211\033[38;2;114;33;220m\342\240\211\033[38;2;111;37;221m\342\240\211\033[38;2;108;40;222m\342\240\211\033[38;2;104;43;223m\342\240\201\033[0m   \033[38;2;91;57;227m\342\243\277\033[38;2;88;60;228m\342\243\277\033[38;2;84;64;229m\342\241\207\033[0m   \033[38;2;71;77;233m\342\242\200\033[38;2;68;80;234m\342\243\277\033[38;2;64;84;235m\342\243\277\033[38;2;61;87;236m\342\243\277\033[0m  \033[38;2;51;97;239m\342\243\276\033[38;2;48;101;240m\342\243\277\033[38;2;44;104;241m\342\243\277\033[38;2;41;107;242m\342\243\244\033[38;2;38;111;243m\342\243\244\033[38;2;34;114;244m\342\243\274\033[38;2;31;117;245m\342\243\277\033[38;2;28;121;246m\342\243\277\033[38;2;24;124;247m\342\243\207\033[0m       \033[0m
   \033[38;2;146;185;216m\342\243\264\033[38;2;161;196;235m\342\241\276\033[38;2;61;94;140m\342\240\233\033[38;2;17;29;52m\342\240\201\033[0m   \033[38;2;4;225;255m\342\242\200\033[38;2;3;111;152m\342\243\277\033[38;2;19;41;69m\342\243\277\033[38;2;1;54;134m\342\243\277\033[38;2;17;59;134m\342\243\277\033[38;2;191;12;63m\342\243\277\033[38;2;213;68;78m\342\243\277\033[38;2;186;8;96m\342\243\277\033[38;2;243;17;84m\342\243\277\033[38;2;227;6;50m\342\243\277\033[38;2;143;12;78m\342\243\237\033[38;2;15;0;27m\342\240\247\033[0m \033[0m        \033[38;2;128;20;216m\342\242\270\033[38;2;124;23;217m\342\243\277\033[38;2;121;26;218m\342\243\277\033[38;2;118;30;219m\342\243\244\033[38;2;114;33;220m\342\243\244\033[38;2;111;37;221m\342\243\244\033[38;2;108;40;222m\342\243\244\033[38;2;104;43;223m\342\243\244\033[0m   \033[38;2;91;57;227m\342\243\277\033[38;2;88;60;228m\342\243\277\033[38;2;84;64;229m\342\243\247\033[38;2;81;67;230m\342\243\244\033[38;2;78;70;231m\342\243\244\033[38;2;74;74;232m\342\243\264\033[38;2;71;77;233m\342\243\277\033[38;2;68;80;234m\342\243\277\033[38;2;64;84;235m\342\240\277\033[38;2;61;87;236m\342\240\201\033[0m \033[38;2;54;94;238m\342\243\274\033[38;2;51;97;239m\342\243\277\033[38;2;48;101;240m\342\243\277\033[38;2;44;104;241m\342\240\233\033[38;2;41;107;242m\342\240\233\033[38;2;38;111;243m\342\240\233\033[38;2;34;114;244m\342\240\233\033[38;2;31;117;245m\342\240\273\033[38;2;28;121;246m\342\243\277\033[38;2;24;124;247m\342\243\277\033[38;2;21;128;248m\342\241\204\033[0m      \033[0m
         \033[38;2;115;238;254m\342\243\240\033[38;2;28;174;254m\342\243\276\033[38;2;0;148;238m\342\243\277\033[38;2;0;95;235m\342\243\277\033[38;2;0;101;222m\342\243\277\033[38;2;15;90;194m\342\243\277\033[38;2;111;20;86m\342\243\277\033[38;2;219;18;51m\342\243\277\033[38;2;45;37;95m\342\243\277\033[38;2;158;0;69m\342\243\277\033[38;2;15;0;29m\342\243\277\033[38;2;36;35;100m\342\240\231\033[0m  \033[0m        \033[38;2;128;20;216m\342\240\230\033[38;2;124;23;217m\342\240\233\033[38;2;121;26;218m\342\240\233\033[38;2;118;30;219m\342\240\233\033[38;2;114;33;220m\342\240\233\033[38;2;111;37;221m\342\240\233\033[38;2;108;40;222m\342\240\233\033[38;2;104;43;223m\342\240\233\033[0m   \033[38;2;91;57;227m\342\240\233\033[38;2;88;60;228m\342\240\233\033[38;2;84;64;229m\342\240\233\033[38;2;81;67;230m\342\240\233\033[38;2;78;70;231m\342\240\233\033[38;2;74;74;232m\342\240\233\033[38;2;71;77;233m\342\240\211\033[38;2;68;80;234m\342\240\201\033[0m  \033[38;2;58;91;237m\342\240\220\033[38;2;54;94;238m\342\240\233\033[38;2;51;97;239m\342\240\233\033[38;2;48;101;240m\342\240\203\033[0m     \033[38;2;28;121;246m\342\240\233\033[38;2;24;124;247m\342\240\233\033[38;2;21;128;248m\342\240\233\033[0m      \033[0m
        \033[38;2;136;239;251m\342\240\255\033[38;2;98;228;253m\342\242\277\033[38;2;40;200;254m\342\243\277\033[38;2;52;178;245m\342\243\277\033[38;2;6;82;178m\342\243\277\033[38;2;26;44;115m\342\243\277\033[38;2;50;37;110m\342\243\277\033[38;2;30;4;41m\342\243\277\033[38;2;133;11;57m\342\243\277\033[38;2;12;20;68m\342\240\213\033[38;2;17;0;32m\342\241\217\033[38;2;16;0;30m\342\240\210\033[0m   \033[0m
         \033[38;2;109;240;255m\342\240\211\033[38;2;105;231;245m\342\240\233\033[38;2;24;75;129m\342\240\211\033[38;2;44;12;58m\342\240\231\033[38;2;55;26;87m\342\240\213\033[38;2;15;0;29m\342\240\230\033[38;2;16;0;31m\342\240\201\033[38;2;16;0;29m\342\240\211\033[0m      \033[0m

"
echo -e "\033[32m  Welcome to EDA (Linux/DIND)\033[0m\n"

# Check connectivity before anything else
if ! curl -fsSL --connect-timeout 5 https://github.com >/dev/null 2>&1; then
    # Try auto-configuring proxy from Nokia PAC file
    if auto_configure_proxy; then
        # Verify connectivity now works
        if ! curl -fsSL --connect-timeout 5 https://github.com >/dev/null 2>&1; then
            echo -e "\033[33mAuto-configured proxy didn't work. Please configure manually.\033[0m"
            prompt_proxy
        fi
    else
        # PAC not available, fall back to manual prompt
        echo -e "\nIt seems we couldn't connect to the internet directly. You might be behind a proxy."
        prompt_proxy
    fi
fi

# Import corporate certificates if present
import_corporate_certs

# Install shell configuration (zsh, completions, scripts, k9s theme)
install_shell_config

# Setup SSH keys
setup_ssh_keys

# Pre-clone and configure EDA playground
echo -e "\033[34m\nSetting up EDA playground...\033[0m"
eda-up --setup-only

# Download tools (kubectl, kind, etc.)
echo -e "\033[34mDownloading tools...\033[0m"
cd /home/eda/playground && bash -c 'make download-tools'

chown -R eda:eda /home/eda/playground 2>/dev/null || true

echo -e "\n\033[32mSetup complete!\033[0m"
exit 0
