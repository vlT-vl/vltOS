#!/usr/bin/env bash
set -euo pipefail
echo
echo "vltOS | Debian13 + Gnome | deploy"
echo "----------------------------------------------"
echo "ultimo update 10/04/2026"
echo "developed by Veronesi Lorenzo"
echo "-----------------------------------------------"
echo

export DEBIAN_FRONTEND=noninteractive
USER_NAME="${SUDO_USER:-$(id -un)}"

# ---- LOGGING COMPLETO --------------------------------------------------------
SCRIPT_BASENAME="$(basename "$0" .sh)"
DATE_TAG="$(date +%d%m%Y)"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6 || true)"
USER_HOME="${USER_HOME:-/home/$USER_NAME}"
LOG_DIR="${USER_HOME}/.log"
LOG_FILE="${LOG_DIR}/${DATE_TAG}-${SCRIPT_BASENAME}.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
chown -R "$USER_NAME":"$USER_NAME" "$LOG_DIR" || true
echo "== $(date -Is) | Logging su: $LOG_FILE =="

# ---- contatore step dinamico -------------------------------------------------
# base: update, install base, sanitize interfaces, purge ifupdown,
# flatpak, install flathub apps, enable svcs, xdg dirs, set theme, cleanup
TOTAL=18
STEP=0
step() { STEP=$((STEP+1)); echo "[$STEP/$TOTAL] $*"; }

# ---- esecuzione --------------------------------------------------------------
step "Configuro repository Debian (contrib / non-free / non-free-firmware)…"

# Backup di sicurezza, ma NON blocca lo script se fallisce
cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%F-%T) 2>/dev/null || true

# Se nei repo non ci sono ancora contrib/non-free/non-free-firmware,
# prova ad aggiungerli sia al vecchio sources.list sia ai file deb822 .sources.
if [[ -f /etc/apt/sources.list ]] && { ! grep -q "contrib" /etc/apt/sources.list || ! grep -q "non-free-firmware" /etc/apt/sources.list; }; then
  sed -i -E \
    's/^(deb .*trixie[^ ]* +main)(.*)$/\1 contrib non-free non-free-firmware/' \
    /etc/apt/sources.list 2>/dev/null || true

  sed -i -E \
    's/^(deb .*trixie-security[^ ]* +main)(.*)$/\1 contrib non-free non-free-firmware/' \
    /etc/apt/sources.list 2>/dev/null || true

  sed -i -E \
    's/^(deb .*trixie-updates[^ ]* +main)(.*)$/\1 contrib non-free non-free-firmware/' \
    /etc/apt/sources.list 2>/dev/null || true
fi

for SOURCE_FILE in /etc/apt/sources.list.d/*.sources; do
  [[ -f "$SOURCE_FILE" ]] || continue
  cp "$SOURCE_FILE" "${SOURCE_FILE}.bak.$(date +%F-%T)" 2>/dev/null || true
  sed -i -E '/^Components:/ {
    /(^| )contrib( |$)/! s/$/ contrib/
    /(^| )non-free( |$)/! s/$/ non-free/
    /(^| )non-free-firmware( |$)/! s/$/ non-free-firmware/
  }' "$SOURCE_FILE" 2>/dev/null || true
done

step "Aggiorno indici APT…"
apt-get update
apt update && apt upgrade -y

step "Installo firmware e supporto hardware di base…"
# Firmware Wi-Fi/GPU, diagnostica hardware, energia, impronta digitale e stack grafico Mesa/Vulkan.
apt-get install -y --no-install-recommends \
  firmware-linux firmware-misc-nonfree \
  firmware-iwlwifi firmware-realtek firmware-atheros firmware-brcm80211 \
  wpasupplicant rfkill \
  pciutils usbutils lshw lm-sensors smartmontools \
  fwupd acpi powertop \
  fprintd libpam-fprintd \
  mesa-utils mesa-vulkan-drivers || true

step "Installo microcode CPU (Intel/AMD)…"
# Microcode CPU: aggiornamenti firmware runtime specifici per processori Intel o AMD.
if grep -qi "GenuineIntel" /proc/cpuinfo; then
  apt-get install -y intel-microcode || true
elif grep -qi "AuthenticAMD" /proc/cpuinfo; then
  apt-get install -y amd64-microcode || true
else
  echo "CPU non Intel/AMD, salto installazione microcode."
fi

step "Installazione pacchetti GNOME minimi (senza Recommends)…"
# GNOME base: login/sessione, impostazioni, file manager, terminale, editor, monitor sistema ed estensioni.
# Desktop integration: font, directory utente, NetworkManager, GVFS, PipeWire/WirePlumber, XWayland e schemi GSettings.
# Utility: tema icone, dconf, archivi, Bluetooth, visualizzatori, thumbnailer, dischi, browser, gdebi e curl.
apt-get install -y --no-install-recommends \
  gdm3 \
  gnome-shell \
  gnome-session \
  gnome-control-center \
  gnome-settings-daemon \
  nautilus \
  gnome-terminal \
  gnome-text-editor \
  gnome-system-monitor \
  gnome-shell-extension-manager \
  fonts-cantarell \
  xdg-user-dirs \
  network-manager \
  network-manager-gnome \
  gvfs-backends \
  gvfs-fuse \
  pipewire-audio \
  wireplumber \
  xwayland \
  glib-networking \
  gsettings-desktop-schemas \
  yaru-theme-icon \
  dconf-cli \
  rsync \
  7zip \
  bluez \
  bluez-obexd \
  gnome-bluetooth-3-common \
  nano \
  eog \
  gnome-tweaks \
  gnome-sushi \
  webp-pixbuf-loader \
  ffmpegthumbnailer \
  udisks2 \
  exfatprogs \
  ntfs-3g \
  libgdk-pixbuf2.0-bin \
  evince \
  tumbler \
  openssl \
  openssh-server \
  gnome-disk-utility \
  fastfetch \
  chromium \
  chromium-l10n \
  gdebi \
  curl || true

step "Installo Firewall UFW e abilito di default la porta ssh (22/tcp)"
# Firewall semplice: abilita UFW e lascia raggiungibile SSH.
if ! command -v ufw >/dev/null 2>&1; then
  apt-get install -y ufw || true
fi
yes | ufw enable || true
ufw status verbose || true
ufw allow 22/tcp || true

step "Installo Flatpak…"
# Runtime app sandboxed; Bazaar verra' installato da Flathub a livello system-wide.
apt-get install -y --no-install-recommends flatpak

step "Aggiungo il remote Flathub (system-wide, se non presente)…"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

step "Aggiungo il remote Flathub (user, se non presente)…"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  sudo -u "$SUDO_USER" flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
  sudo -u "$SUDO_USER" flatpak --user update --appstream -y || true
else
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
  flatpak --user update --appstream -y || true
fi

step "Aggiorno la cache AppStream (system e user)…"
flatpak --system update --appstream -y || true
flatpak --user update --appstream -y || true

step "Installo Bazaar da Flathub…"
flatpak install --system -y --noninteractive flathub io.github.kolunmi.Bazaar || true

step "Imposto sistema e Abilito servizi principali (GDM, NetworkManager, Bluetooth)…"
systemctl enable gdm.service
systemctl enable NetworkManager.service
systemctl enable bluetooth.service
systemctl enable ssh
swapoff -a || true
sysctl -w vm.dirty_bytes=50331648
sysctl -w vm.dirty_background_bytes=16777216

step "Genero cartelle utente standard (Documenti, Download, ecc.)…"
sudo -u "$USER_NAME" xdg-user-dirs-update || true

step "Imposto Yaru come tema icone (default di sistema + utente corrente)…"
mkdir -p /etc/dconf/db/local.d
cat >/etc/dconf/db/local.d/00-icons-theme <<'EOF'
[org/gnome/desktop/interface]
icon-theme='Yaru-dark'
EOF
dconf update
USER_NAME="${USER_NAME:-$(whoami)}"  # Usa l'utente corrente se $USER_NAME non è definito
sudo -u "$USER_NAME" gsettings set org.gnome.desktop.interface icon-theme 'Yaru-dark' || true
dconf update

step "Pulizia e rimozioni…"
apt-get -y purge vim vim-common vim-runtime vim-tiny vim-gtk3 vim-nox vim-athena vim-gui-common || true
apt-get -y autoremove --purge
apt-get -y clean
apt-get -y purge fortune-mod || true
apt-get -y purge debian-reference-common || true
apt-get -y autoremove --purge || true

step "Impostazione del GRUB"
cp -a /etc/default/grub /etc/default/grub.bak-$(date +%Y%m%d-%H%M%S)
sed -i -E -e 's/^#?GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' -e 's/^#?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
if grep -q '^GRUB_RECORDFAIL_TIMEOUT=' /etc/default/grub; then sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=0/' /etc/default/grub; else echo 'GRUB_RECORDFAIL_TIMEOUT=0' >> /etc/default/grub; fi
update-grub

step "Backup e sanitizzazione configurazioni di rete legacy (/etc/network)…"
TS="$(date +%Y%m%d-%H%M%S)"
if [[ -f /etc/network/interfaces ]]; then
  cp -a /etc/network/interfaces "/etc/network/interfaces.bak-${TS}"
fi
cat >/etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback
EOF
if [[ -d /etc/network/interfaces.d ]]; then
  tar czf "/etc/network/interfaces.d.bak-${TS}.tgz" -C /etc/network interfaces.d || true
  mv /etc/network/interfaces.d /etc/network/interfaces.d.disabled || true
fi

step "Rimuovo ifupdown/ifupdown2 per evitare conflitti con NetworkManager…"
apt-get -y purge ifupdown ifupdown2 || true

echo "Installazione completata!"
echo "Log salvato in: $LOG_FILE"
echo "Il sistema si riavvierà tra 5 secondi… (Ctrl+C per annullare)"
echo " "
reboot
