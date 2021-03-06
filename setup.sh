#!/bin/bash
if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

apt-get -y install git build-essential autoconf automake libtool pkg-config libupnp-dev libgstreamer1.0-dev \
             gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
             gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
             gstreamer1.0-libav gstreamer1.0-alsa bluez alsa-base alsa-utils bluealsa bluez-tools python-alsaaudio lirc mplayer

echo "Cloning UPNP Renderer Code..."
git clone https://github.com/TheHeroCraft1579/gmrender-resurrect.git
echo "Building UPNP Renderer..."
cd gmrender-resurrect
./autogen.sh
./configure
make
echo "Copying Binaries..."
mkdir ../bin
cp src/gmediarender ../bin/gmediarender

echo "Downloading Raspotify..."
curl -sL https://dtcooper.github.io/raspotify/install.sh | sh

echo "Creating Config..."
cat <<EOF > /etc/default/raspotify
DEVICE_NAME="WebRadio"
BITRATE="320"
VOLUME_ARGS="--linear-volume --initial-volume=100"
EOF

if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

echo
echo -n "Do you want to install Bluetooth Audio (BlueALSA)? [y/N] "
read REPLY
if [[ ! "$REPLY" =~ ^(yes|y|Y)$ ]]; then exit 0; fi

apt install -y --no-install-recommends alsa-base alsa-utils bluealsa bluez-tools

# Bluetooth settings
cat <<'EOF' > /etc/bluetooth/main.conf
[General]
Class = 0x200414
DiscoverableTimeout = 0
[Policy]
AutoEnable=true
EOF

# Make Bluetooth discoverable after initialisation
mkdir -p /etc/systemd/system/bthelper@.service.d
cat <<'EOF' > /etc/systemd/system/bthelper@.service.d/override.conf
[Service]
Type=oneshot
ExecStartPost=/usr/bin/bluetoothctl discoverable on
ExecStartPost=/bin/hciconfig %I piscan
ExecStartPost=/bin/hciconfig %I sspmode 1
EOF

cat <<'EOF' > /etc/systemd/system/bt-agent.service
[Unit]
Description=Bluetooth Agent
Requires=bluetooth.service
After=bluetooth.service
[Service]
ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput
RestartSec=5
Restart=always
KillSignal=SIGUSR1
[Install]
WantedBy=multi-user.target
EOF
systemctl enable bt-agent.service

# ALSA settings
sed -i.orig 's/^options snd-usb-audio index=-2$/#options snd-usb-audio index=-2/' /lib/modprobe.d/aliases.conf

# BlueALSA
mkdir -p /etc/systemd/system/bluealsa.service.d
cat <<'EOF' > /etc/systemd/system/bluealsa.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/bluealsa -i hci0 -p a2dp-sink
RestartSec=5
Restart=always
EOF

cat <<'EOF' > /etc/systemd/system/bluealsa-aplay.service
[Unit]
Description=BlueALSA aplay
Requires=bluealsa.service
After=bluealsa.service sound.target
[Service]
Type=simple
User=root
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/bluealsa-aplay --pcm-buffer-time=250000 00:00:00:00:00:00
RestartSec=5
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable bluealsa-aplay

# Bluetooth udev script
cat <<'EOF' > /usr/local/bin/bluetooth-udev
#!/bin/bash
if [[ ! $NAME =~ ^\"([0-9A-F]{2}[:-]){5}([0-9A-F]{2})\"$ ]]; then exit 0; fi
action=$(expr "$ACTION" : "\([a-zA-Z]\+\).*")
if [ "$action" = "add" ]; then
    bluetoothctl discoverable off
    # disconnect wifi to prevent dropouts
    #ifconfig wlan0 down &
fi
if [ "$action" = "remove" ]; then
    # reenable wifi
    #ifconfig wlan0 up &
    bluetoothctl discoverable on
fi
EOF
chmod 755 /usr/local/bin/bluetooth-udev

cat <<'EOF' > /etc/udev/rules.d/99-bluetooth-udev.rules
SUBSYSTEM=="input", GROUP="input", MODE="0660"
KERNEL=="input[0-9]*", RUN+="/usr/local/bin/bluetooth-udev"
EOF

pip install newsapi-python requests