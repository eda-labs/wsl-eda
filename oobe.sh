#!/bin/bash

function ensure_interop {
    # https://github.com/microsoft/WSL/issues/8843
    if [ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
        echo ":WSLInterop:M::MZ::/init:P" | sudo tee /proc/sys/fs/binfmt_misc/register >/dev/null 2>&1
    fi
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

    # Ask user for their region
    echo -e "\nPlease select your region:"
    echo "  1) EU   (Europe)"
    echo "  2) US   (Americas)"
    echo "  3) APAC (Asia-Pacific)"
    read -p "Enter choice [1-3]: " -n 1 -r REGION_CHOICE
    echo

    case $REGION_CHOICE in
        1)
            PROXY_HOST="fihel1d-proxy.emea.nsn-net.net"
            echo -e "Using EU proxy: $PROXY_HOST"
            ;;
        2)
            PROXY_HOST="usdal1a-proxy.americas.nsn-net.net"
            echo -e "Using US proxy: $PROXY_HOST"
            ;;
        3)
            PROXY_HOST="sgsinaa-proxyfw001.apac.nsn-net.net"
            echo -e "Using APAC proxy: $PROXY_HOST"
            ;;
        *)
            echo -e "\033[33mInvalid choice. Defaulting to EU proxy.\033[0m"
            PROXY_HOST="fihel1d-proxy.emea.nsn-net.net"
            ;;
    esac

    # Build proxy URL and NO_PROXY list
    PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
    NO_PROXY="localhost,127.0.0.1,::1,.nokia.net,.nokia.com,.int.nokia.com,.nsn-net.net,.nsn-intra.net,.inside.nsn.com,.noklab.net,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

    # Write proxy configuration
    echo "HTTP_PROXY=$PROXY_URL" | sudo tee /etc/proxy.conf > /dev/null
    echo "HTTPS_PROXY=$PROXY_URL" | sudo tee -a /etc/proxy.conf > /dev/null
    echo "NO_PROXY=$NO_PROXY" | sudo tee -a /etc/proxy.conf > /dev/null

    # Configure system-wide proxy silently (answer 'y' to Docker restart prompt)
    yes y | sudo SUDO_USER=eda SUDO_UID=1000 SUDO_GID=1000 proxyman set > /dev/null 2>&1
    eval "$(sudo /usr/local/bin/proxyman export)"

    echo -e "\033[32mProxy configured\033[0m"
    return 0
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

    TMP_CERT_DIR=$(mktemp -d)
    WIN_TMP_CERT_DIR=$(powershell.exe -NoProfile -Command '
        $outDir = "$env:TEMP\wsl_certs"
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        $certs = Get-ChildItem -Path Cert:\CurrentUser\Root, Cert:\CurrentUser\CA | Where-Object { $_.Subject -like "*Zscaler Root*" }
        foreach ($cert in $certs) {
            $derPath = "$outDir\" + $cert.Thumbprint + ".der"
            $pemPath = "$outDir\" + $cert.Thumbprint + ".crt"
            $cert | Export-Certificate -Type CERT -FilePath $derPath | Out-Null
            certutil -encode $derPath $pemPath | Out-Null
            Remove-Item $derPath
        }
        Write-Host $outDir -NoNewline
    ')

    WIN_TMP_DIR_WSL_PATH=$(wslpath "$WIN_TMP_CERT_DIR")
    cp "$WIN_TMP_DIR_WSL_PATH"/*.crt "$TMP_CERT_DIR/" 2>/dev/null
    rm -rf "$WIN_TMP_DIR_WSL_PATH"

    CERT_COUNT=0
    for cert in "$TMP_CERT_DIR"/*.crt; do
        if [ -f "$cert" ]; then
            CERT_NAME=$(basename "$cert")
            sudo cp "$cert" "/usr/local/share/ca-certificates/${CERT_NAME}"
            ((CERT_COUNT++))
        fi
    done

    rm -rf "$TMP_CERT_DIR"

    if [ $CERT_COUNT -gt 0 ]; then
        sudo update-ca-certificates --fresh > /dev/null 2>&1
        echo -e "\033[32mImported $CERT_COUNT corporate certificate(s).\033[0m"
    else
        echo -e "\033[33mNo Zscaler/corporate certificates found to import.\033[0m"
        echo -e "If you have SSL inspection, manually export certificates and run:"
        echo -e "  sudo cp your-cert.crt /usr/local/share/ca-certificates/"
        echo -e "  sudo update-ca-certificates"
    fi
}

function install_fonts {
    echo -e "\033[34mInstalling Nerd Fonts...\033[0m"

    WIN_TEMP=$(powershell.exe -NoProfile -Command 'Write-Host $env:TEMP -NoNewline' 2>/dev/null)
    WIN_TEMP_WSL=$(wslpath "$WIN_TEMP")
    TMP_DIR="$WIN_TEMP_WSL/EDA_Fonts_$$"

    # Install each font
    for font in "JetBrainsMono" "FiraCode"; do
        # Check if font is already installed (user or system)
        FONT_CHECK=$(powershell.exe -NoProfile -Command '
            $userFonts = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
            if (Test-Path "$userFonts\'"$font"'NerdFont*.ttf") { "yes" }
            elseif (Test-Path "$env:WINDIR\Fonts\'"$font"'NerdFont*.ttf") { "yes" }
            else { "no" }
        ' 2>/dev/null)

        if [[ "$FONT_CHECK" =~ "yes" ]]; then
            echo -e "  $font Nerd Font already installed."
        else
            echo -e "  Installing $font Nerd Font..."
            mkdir -p "$TMP_DIR"

            curl -fsSL -o "$TMP_DIR/$font.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.zip"
            unzip -q "$TMP_DIR/$font.zip" -d "$TMP_DIR/${font}NF"

            # Silent per-user font installation (no admin, no UI)
            powershell.exe -NoProfile -Command '
                $fontSource = "'"$WIN_TEMP"'\EDA_Fonts_'"$$"'\'"${font}"'NF"
                $userFonts = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
                New-Item -ItemType Directory -Force -Path $userFonts | Out-Null

                $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

                Get-ChildItem -Path $fontSource -Filter "*.ttf" | ForEach-Object {
                    $fontPath = "$userFonts\$($_.Name)"
                    Copy-Item $_.FullName -Destination $fontPath -Force

                    # Register font in registry
                    $fontName = $_.BaseName -replace "NerdFont", " Nerd Font" -replace "-", " "
                    New-ItemProperty -Path $regPath -Name "$fontName (TrueType)" -Value $fontPath -PropertyType String -Force | Out-Null
                }
            ' 2>/dev/null

            rm -rf "$TMP_DIR"
        fi
    done

    echo -e "\033[32mNerd Fonts installed.\033[0m"
}

function import_ssh_keys {
    KEY_CHECK=$(powershell.exe -NoProfile -Command '
        $key_types = @("rsa", "ecdsa", "ed25519")
        foreach ( $type in $key_types ) {
            if( Test-Path $env:userprofile\.ssh\id_$type.pub ) {
                return $type
            }
        }
        Write-Output False
    ')

    mkdir -p /home/eda/.ssh

    case $KEY_CHECK in
        rsa*)
            KEY=$(powershell.exe -NoProfile -Command 'Get-Content $env:userprofile\.ssh\id_rsa.pub')
            echo $KEY | tee -a /home/eda/.ssh/authorized_keys > /dev/null
            ;;
        ecdsa*)
            KEY=$(powershell.exe -NoProfile -Command 'Get-Content $env:userprofile\.ssh\id_ecdsa.pub')
            echo $KEY | tee -a /home/eda/.ssh/authorized_keys > /dev/null
            ;;
        ed25519*)
            KEY=$(powershell.exe -NoProfile -Command 'Get-Content $env:userprofile\.ssh\id_ed25519.pub')
            echo $KEY | tee -a /home/eda/.ssh/authorized_keys > /dev/null
            ;;
        False*)
            SSH_CMD="ssh-keygen -t rsa -b 4096 -f \$env:USERPROFILE\.ssh\id_rsa -N '\"\"'"
            powershell.exe -Command $SSH_CMD
            KEY=$(powershell.exe -NoProfile -Command 'Get-Content $env:userprofile\.ssh\id_rsa.pub')
            echo $KEY | tee -a /home/eda/.ssh/authorized_keys > /dev/null
            ;;
        *)
            echo -e "\033[34m\nSSH: Could not detect key type. Please check or create a key.\033[0m"
    esac

    echo -e "\033[32mSSH keys configured. You can SSH with: 'ssh eda@localhost -p 2222'\033[0m"
}

# --- Start OOBE ---
clear
printf "
       \033[38;2;255;124;88m⢀\033[38;2;255;218;152m⢀\033[38;2;255;115;123m⡄\033[38;2;255;197;123m⣠\033[38;2;255;179;106m⣦\033[38;2;252;111;48m⣴\033[38;2;255;195;123m⣎\033[38;2;255;197;129m⣤\033[38;2;255;197;128m⠖\033[38;2;255;170;142m⢀\033[38;2;255;136;135m⡀\033[0m     \033[0m
     \033[38;2;255;167;7m⢠\033[38;2;252;185;65m⣤\033[38;2;253;143;93m⣿\033[38;2;252;195;143m⣿\033[38;2;246;128;79m⣿\033[38;2;229;121;83m⣿\033[38;2;244;150;123m⣿\033[38;2;244;164;137m⣿\033[38;2;243;170;132m⣿\033[38;2;253;183;152m⣶\033[38;2;255;162;126m⣿\033[38;2;255;81;63m⣯\033[38;2;255;131;41m⣴\033[38;2;254;122;52m⡶\033[38;2;255;75;14m⠂\033[0m   \033[0m
     \033[38;2;249;168;21m⣼\033[38;2;238;76;97m⣿\033[38;2;246;198;130m⣿\033[38;2;216;171;144m⣿\033[38;2;225;181;79m⣿\033[38;2;232;145;43m⣿\033[38;2;218;95;66m⣿\033[38;2;221;179;132m⣿\033[38;2;239;203;163m⣿\033[38;2;228;143;121m⣿\033[38;2;252;193;144m⣿\033[38;2;251;202;165m⣿\033[38;2;251;164;159m⣿\033[38;2;252;150;151m⣿\033[38;2;253;140;132m⣟\033[38;2;253;147;108m⣁\033[38;2;255;89;1m⡀\033[0m \033[0m        \033[38;2;128;20;216m⢸\033[38;2;124;23;217m⣿\033[38;2;121;26;218m⣿\033[38;2;118;30;219m⣿\033[38;2;114;33;220m⣿\033[38;2;111;37;221m⣿\033[38;2;108;40;222m⣿\033[38;2;104;43;223m⣿\033[0m   \033[38;2;91;57;227m⣿\033[38;2;88;60;228m⣿\033[38;2;84;64;229m⣿\033[38;2;81;67;230m⣿\033[38;2;78;70;231m⣿\033[38;2;74;74;232m⣿\033[38;2;71;77;233m⣶\033[38;2;68;80;234m⣦\033[38;2;64;84;235m⣄\033[0m     \033[38;2;44;104;241m⣼\033[38;2;41;107;242m⣿\033[38;2;38;111;243m⣿\033[38;2;34;114;244m⣿\033[38;2;31;117;245m⡆\033[0m         \033[0m
     \033[38;2;197;102;56m⣿\033[38;2;207;125;120m⣿\033[38;2;180;125;117m⣿\033[38;2;201;136;38m⣿\033[38;2;193;106;54m⣿\033[38;2;182;86;90m⣿\033[38;2;171;121;83m⣿\033[38;2;170;111;44m⣿\033[38;2;176;101;32m⣿\033[38;2;185;112;62m⣿\033[38;2;214;111;104m⣿\033[38;2;203;96;113m⣿\033[38;2;194;85;115m⣿\033[38;2;229;115;109m⣿\033[38;2;253;150;101m⣿\033[38;2;254;162;87m⣿\033[38;2;255;213;58m⣦\033[38;2;255;208;68m⡀\033[0m        \033[38;2;128;20;216m⢸\033[38;2;124;23;217m⣿\033[38;2;121;26;218m⣿\033[0m        \033[38;2;91;57;227m⣿\033[38;2;88;60;228m⣿\033[38;2;84;64;229m⡇\033[0m  \033[38;2;74;74;232m⠈\033[38;2;71;77;233m⠻\033[38;2;68;80;234m⣿\033[38;2;64;84;235m⣿\033[38;2;61;87;236m⣦\033[0m   \033[38;2;48;101;240m⣰\033[38;2;44;104;241m⣿\033[38;2;41;107;242m⣿\033[38;2;38;111;243m⢻\033[38;2;34;114;244m⣿\033[38;2;31;117;245m⣿\033[38;2;28;121;246m⡀\033[0m        \033[0m
     \033[38;2;170;74;77m⢻\033[38;2;98;44;105m⣿\033[38;2;164;169;186m⣿\033[38;2;194;206;228m⣿\033[38;2;178;180;222m⣿\033[38;2;163;167;212m⣿\033[38;2;126;69;136m⣿\033[38;2;83;27;100m⣿\033[38;2;78;29;102m⣿\033[38;2;117;19;97m⣿\033[38;2;119;38;111m⣿\033[38;2;160;59;91m⣿\033[38;2;146;51;121m⣿\033[38;2;180;30;96m⣿\033[38;2;211;28;83m⣿\033[38;2;219;17;71m⣿\033[38;2;245;1;64m⣦\033[38;2;255;0;43m⡀\033[0m        \033[38;2;128;20;216m⢸\033[38;2;124;23;217m⣿\033[38;2;121;26;218m⣿\033[38;2;118;30;219m⣶\033[38;2;114;33;220m⣶\033[38;2;111;37;221m⣶\033[38;2;108;40;222m⣶\033[38;2;104;43;223m⡆\033[0m   \033[38;2;91;57;227m⣿\033[38;2;88;60;228m⣿\033[38;2;84;64;229m⡇\033[0m    \033[38;2;68;80;234m⣿\033[38;2;64;84;235m⣿\033[38;2;61;87;236m⣿\033[0m  \033[38;2;51;97;239m⢠\033[38;2;48;101;240m⣿\033[38;2;44;104;241m⣿\033[38;2;41;107;242m⠇\033[0m \033[38;2;34;114;244m⢿\033[38;2;31;117;245m⣿\033[38;2;28;121;246m⣧\033[0m        \033[0m
     \033[38;2;160;194;230m⣸\033[38;2;201;216;234m⣿\033[38;2;168;190;223m⡿\033[38;2;174;197;222m⠿\033[38;2;186;196;217m⠿\033[38;2;84;95;111m⢿\033[38;2;73;84;100m⣿\033[38;2;24;34;48m⣿\033[38;2;40;50;120m⣿\033[38;2;109;61;131m⣿\033[38;2;205;4;55m⣿\033[38;2;147;39;63m⣿\033[38;2;247;66;57m⣿\033[38;2;223;27;71m⣿\033[38;2;216;96;96m⣿\033[38;2;244;53;97m⣿\033[38;2;202;9;103m⢧\033[38;2;218;4;70m⡉\033[0m        \033[38;2;128;20;216m⢸\033[38;2;124;23;217m⣿\033[38;2;121;26;218m⣿\033[38;2;118;30;219m⠉\033[38;2;114;33;220m⠉\033[38;2;111;37;221m⠉\033[38;2;108;40;222m⠉\033[38;2;104;43;223m⠁\033[0m   \033[38;2;91;57;227m⣿\033[38;2;88;60;228m⣿\033[38;2;84;64;229m⡇\033[0m   \033[38;2;71;77;233m⢀\033[38;2;68;80;234m⣿\033[38;2;64;84;235m⣿\033[38;2;61;87;236m⣿\033[0m  \033[38;2;51;97;239m⣾\033[38;2;48;101;240m⣿\033[38;2;44;104;241m⣿\033[38;2;41;107;242m⣤\033[38;2;38;111;243m⣤\033[38;2;34;114;244m⣼\033[38;2;31;117;245m⣿\033[38;2;28;121;246m⣿\033[38;2;24;124;247m⣇\033[0m       \033[0m
   \033[38;2;146;185;216m⣴\033[38;2;161;196;235m⡾\033[38;2;61;94;140m⠛\033[38;2;17;29;52m⠁\033[0m   \033[38;2;4;225;255m⢀\033[38;2;3;111;152m⣿\033[38;2;19;41;69m⣿\033[38;2;1;54;134m⣿\033[38;2;17;59;134m⣿\033[38;2;191;12;63m⣿\033[38;2;213;68;78m⣿\033[38;2;186;8;96m⣿\033[38;2;243;17;84m⣿\033[38;2;227;6;50m⣿\033[38;2;143;12;78m⣟\033[38;2;15;0;27m⠧\033[0m \033[0m        \033[38;2;128;20;216m⢸\033[38;2;124;23;217m⣿\033[38;2;121;26;218m⣿\033[38;2;118;30;219m⣤\033[38;2;114;33;220m⣤\033[38;2;111;37;221m⣤\033[38;2;108;40;222m⣤\033[38;2;104;43;223m⣤\033[0m   \033[38;2;91;57;227m⣿\033[38;2;88;60;228m⣿\033[38;2;84;64;229m⣧\033[38;2;81;67;230m⣤\033[38;2;78;70;231m⣤\033[38;2;74;74;232m⣴\033[38;2;71;77;233m⣿\033[38;2;68;80;234m⣿\033[38;2;64;84;235m⠿\033[38;2;61;87;236m⠁\033[0m \033[38;2;54;94;238m⣼\033[38;2;51;97;239m⣿\033[38;2;48;101;240m⣿\033[38;2;44;104;241m⠛\033[38;2;41;107;242m⠛\033[38;2;38;111;243m⠛\033[38;2;34;114;244m⠛\033[38;2;31;117;245m⠻\033[38;2;28;121;246m⣿\033[38;2;24;124;247m⣿\033[38;2;21;128;248m⡄\033[0m      \033[0m
         \033[38;2;115;238;254m⣠\033[38;2;28;174;254m⣾\033[38;2;0;148;238m⣿\033[38;2;0;95;235m⣿\033[38;2;0;101;222m⣿\033[38;2;15;90;194m⣿\033[38;2;111;20;86m⣿\033[38;2;219;18;51m⣿\033[38;2;45;37;95m⣿\033[38;2;158;0;69m⣿\033[38;2;15;0;29m⣿\033[38;2;36;35;100m⠙\033[0m  \033[0m        \033[38;2;128;20;216m⠘\033[38;2;124;23;217m⠛\033[38;2;121;26;218m⠛\033[38;2;118;30;219m⠛\033[38;2;114;33;220m⠛\033[38;2;111;37;221m⠛\033[38;2;108;40;222m⠛\033[38;2;104;43;223m⠛\033[0m   \033[38;2;91;57;227m⠛\033[38;2;88;60;228m⠛\033[38;2;84;64;229m⠛\033[38;2;81;67;230m⠛\033[38;2;78;70;231m⠛\033[38;2;74;74;232m⠛\033[38;2;71;77;233m⠉\033[38;2;68;80;234m⠁\033[0m  \033[38;2;58;91;237m⠐\033[38;2;54;94;238m⠛\033[38;2;51;97;239m⠛\033[38;2;48;101;240m⠃\033[0m     \033[38;2;28;121;246m⠛\033[38;2;24;124;247m⠛\033[38;2;21;128;248m⠛\033[0m      \033[0m
        \033[38;2;136;239;251m⠭\033[38;2;98;228;253m⢿\033[38;2;40;200;254m⣿\033[38;2;52;178;245m⣿\033[38;2;6;82;178m⣿\033[38;2;26;44;115m⣿\033[38;2;50;37;110m⣿\033[38;2;30;4;41m⣿\033[38;2;133;11;57m⣿\033[38;2;12;20;68m⠋\033[38;2;17;0;32m⡏\033[38;2;16;0;30m⠈\033[0m   \033[0m
         \033[38;2;109;240;255m⠉\033[38;2;105;231;245m⠛\033[38;2;24;75;129m⠉\033[38;2;44;12;58m⠙\033[38;2;55;26;87m⠋\033[38;2;15;0;29m⠘\033[38;2;16;0;31m⠁\033[38;2;16;0;29m⠉\033[0m      \033[0m

"
echo -e "\033[32m  Welcome to EDA WSL\033[0m\n"

ensure_interop

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

# Install fonts
install_fonts

# Import SSH keys
import_ssh_keys

# Pre-clone and configure EDA playground
echo -e "\033[34m\nSetting up EDA playground...\033[0m"
eda-up --setup-only
chown -R eda:eda /home/eda/playground 2>/dev/null || true

echo -e "\n\033[32mSetup complete! Please restart the terminal.\033[0m"
exit 0
