#!/bin/bash

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
        SUDO_USER=eda SUDO_UID=1000 SUDO_GID=1000 sudo proxyman set > /dev/null 2>&1
        echo -e "\nProxy has been set. You can run 'sudo proxyman unset' to remove it."
        eval "$(sudo /usr/local/bin/proxyman export)"
    else
        echo -e "\nSkipping proxy configuration.\n"
    fi
}

function import_corporate_certs {
    echo -e "\033[34m\nImporting corporate/Zscaler certificates...\033[0m"

    # Export Windows root certificates that might be from Zscaler/corporate CA
    TMP_CERT_DIR=$(mktemp -d)

    # Export certificates from Windows cert store (Root and CA stores)
    powershell.exe -NoProfile -Command '
        $certs = Get-ChildItem -Path Cert:\LocalMachine\Root, Cert:\LocalMachine\CA |
            Where-Object { $_.Subject -match "Zscaler|ZPA|Corporate|Enterprise" -or $_.Issuer -match "Zscaler|ZPA" }
        foreach ($cert in $certs) {
            $fileName = $cert.Thumbprint + ".crt"
            $certPath = "'"$TMP_CERT_DIR"'\" + $fileName
            $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            [System.IO.File]::WriteAllBytes($certPath, $certBytes)
            Write-Host "Exported: $($cert.Subject)"
        }
    ' 2>/dev/null

    # Convert paths and install certificates
    CERT_COUNT=0
    for cert in "$TMP_CERT_DIR"/*.crt; do
        if [ -f "$cert" ]; then
            # Convert DER to PEM if needed and copy to system store
            CERT_NAME=$(basename "$cert")
            if openssl x509 -in "$cert" -inform DER -out "/tmp/${CERT_NAME}.pem" 2>/dev/null; then
                sudo cp "/tmp/${CERT_NAME}.pem" "/usr/local/share/ca-certificates/${CERT_NAME}"
                rm "/tmp/${CERT_NAME}.pem"
            else
                # Already PEM format
                sudo cp "$cert" "/usr/local/share/ca-certificates/${CERT_NAME}"
            fi
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
    echo -e "\033[34m\nInstalling Nerd Font...\033[0m"

    FONT_NAME_PATTERN='FiraCode Nerd Font*'

    FONT_CHECK=$(powershell.exe -NoProfile -Command '
        Add-Type -AssemblyName System.Drawing
        $fonts = [System.Drawing.Text.InstalledFontCollection]::new().Families
        $fontNamePattern = "'"$FONT_NAME_PATTERN"'"
        $found = $fonts | Where-Object { $_.Name -like $fontNamePattern } | Select-Object -First 1
        if ($found) { "yes" } else { "no" }
    ')

    if [[ "$FONT_CHECK" =~ "yes" ]]; then
        echo -e "\033[33mFiraCode Nerd Font is already installed. Skipping.\033[0m"
    else
        echo "Downloading FiraCode Nerd Font..."
        TMP_DIR=$(mktemp -d)
        cd "$TMP_DIR"
        curl -fLo "FiraCode.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip

        unzip -q FiraCode.zip -d FiraCodeNF
        FONTS_PATH=$(wslpath -w "$TMP_DIR/FiraCodeNF")

        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
            $fontFiles = Get-ChildItem -Path "'"$FONTS_PATH"'" -Filter "*.ttf"
            foreach ($fontFile in $fontFiles) {
                $shellApp = New-Object -ComObject Shell.Application
                $fontsFolder = $shellApp.NameSpace(0x14)
                $fontsFolder.CopyHere($fontFile.FullName, 16)
            }
        '

        cd ~
        rm -rf "$TMP_DIR"

        echo -e "\033[32mFiraCode Nerd Font installed successfully.\033[0m"
        echo -e "\033[33mNote: You may need to restart Windows Terminal to see the new fonts.\033[0m"
    fi
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

# Check connectivity and handle proxy/certificates
if ! curl -fsSL --connect-timeout 5 https://www.google.com -o /dev/null 2>&1; then
    echo -e "\nIt seems we couldn't connect to the internet directly."
    echo -e "This could be due to a proxy or SSL inspection (e.g., Zscaler).\n"

    read -p "Would you like to import corporate/Zscaler certificates? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        import_corporate_certs
    fi

    prompt_proxy
fi

# Apply sysctl settings
echo -e "\n\033[34mApplying system settings...\033[0m"
if sudo mkdir -p /etc/sysctl.d > /dev/null 2>&1 && \
   echo -e "fs.inotify.max_user_watches=1048576\nfs.inotify.max_user_instances=512" | sudo tee /etc/sysctl.d/90-wsl-inotify.conf > /dev/null 2>&1 && \
   sudo sysctl --system > /dev/null 2>&1; then
    echo -e "\033[32mSystem settings applied.\033[0m"
else
    echo -e "\033[31mWarning: Failed to apply some settings.\033[0m"
fi

# Install fonts
read -p "Would you like to install FiraCode Nerd Font for better terminal display? (Y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    install_fonts
fi

# Import SSH keys
import_ssh_keys

echo -e "\n\033[32mSetup complete! Please restart the terminal.\033[0m"
exit 0
