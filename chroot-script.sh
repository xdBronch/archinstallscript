#!bin/sh

if ! [ $timezone ]
then
  timezone="Europe/Lisbon"
fi

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
sed -i "/^#en_US.UTF-8/ cen_US.UTF-8 UTF-8" /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

if ! [ $hostname ]
then
  hostname="arch"
fi

echo $hostname >> /etc/hostname

if ! [ $editor ]
then
  editor="neovim"
fi

pacman --noconfirm -Sy efibootmgr $editor base-devel git

case $network in
  systemd-network)
    systemctl enable systemd-networkd
    ;;

  dhcpcd)
    pacman --noconfirm -S dhcpcd
    systemctl enable dhcpcd
    ;;
  
  none)
    ;;
   
  *)
    pacman --noconfirm -S networkmanager
    systemctl enable NetworkManager
    ;;
esac


if [[ $(grep 'AuthenticAMD' </proc/cpuinfo | head -n 1) ]]
then
  cpu=amd
elif [[ $(grep 'GenuineIntel' </proc/cpuinfo | head -n 1) ]]
then
  cpu=intel
fi
if [ $cpu ]
then
  pacman --noconfirm -S $cpu-ucode
fi

bootctl install
mkdir -p /boot/loader/entries /etc/pacman.d/hooks

echo "default  arch.conf 
timeout  4 
console-mode max 
editor  yes" > /boot/loader/loader.conf
 
echo "title  Arch Linux 
linux  /vmlinuz-$kernel" > /boot/loader/entries/arch.conf
if [ $cpu ]
then
  echo "initrd  /$cpu-ucode.img" >> /boot/loader/entries/arch.conf
fi
echo "initrd  /initramfs-$kernel.img
options  root=$(cat /etc/fstab | grep 'UUID' | head -n 1 - | awk '{print $1}') rw" >> /boot/loader/entries/arch.conf
 
if [ "$gpu" == "nvidia" ]
then
  echo "options  mitigations=off nvidia-drm.modeset=1" >> /boot/loader/entries/arch.conf
else
  echo "options  mitigations=off" >> /boot/loader/entries/arch.conf
fi
 
 
echo "title  Arch Linux Fallback 
linux  /vmlinuz-$kernel" > /boot/loader/entries/arch-fallback.conf
if [ $cpu ]
then
  echo "initrd  /$cpu-ucode.img" >> /boot/loader/entries/arch-fallback.conf
fi
echo "initrd  /initramfs-$kernel-fallback.img
options  root=PART$(cat /etc/fstab | grep 'UUID' | head -n 1 - | awk '{print $1}') rw" >> /boot/loader/entries/arch-fallback.conf
 
if [ "$gpu" == "nvidia" ]
then
  echo "options  mitigations=off nvidia-drm.modeset=1" >> /boot/loader/entries/arch-fallback.conf
else
  echo "options  mitigations=off" >> /boot/loader/entries/arch-fallback.conf
fi


"[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service" > /etc/pacman.d/hooks/100-systemd-boot.hook

if [ $winefi ]
then
  mount $winefi /mnt
  cp /mnt/EFI /boot/ -r
  umount /mnt
fi

if ! [ $rootpw ]
then
  rootpw="root"
fi
if ! [ $username ]
then
  username="user"
fi
if ! [ $userpw ]
then
  userpw="user"
fi

echo "root:$rootpw" | chpasswd
useradd -mg wheel $username
echo "$username:$userpw" | chpasswd
sed -i "/^# %wheel ALL=(ALL:ALL) ALL/ c%wheel ALL=(ALL:ALL) ALL" /etc/sudoers

sed -i "/^#Color/cColor" /etc/pacman.conf
sed -i "/^#ParallelDownloads/cParallelDownloads = 5" /etc/pacman.conf

if ! [ $installtype ] || [ $installtype == "minimal" ]
then
  exit
fi

sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Sy
pacman --noconfirm -S xorg noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra pipewire lib32-pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack

case $gpu in 
  nvidia)
    pacman -S --noconfirm --needed lib32-libglvnd lib32-nvidia-utils lib32-vulkan-icd-loader libglvnd nvidia-dkms nvidia-settings vulkan-icd-loader
    ;;
    
  amd)
    pacman -S --noconfirm --needed xf86-video-amdgpu mesa lib32-mesa lib32-vulkan-icd-loader lib32-vulkan-radeon vulkan-icd-loader vulkan-radeon
    ;;
  
  intel)
    pacman -S --noconfirm --needed xf86-video-intel mesa lib32-mesa lib32-vulkan-icd-loader lib32-vulkan-intel vulkan-icd-loader vulkan-intel
    ;;
      
  *)
    pacman -S --noconfirm xf86-video-amdgpu xf86-video-intel xf86-video-nouveau
    ;;
esac


if [ $installtype == "desktop" ]
then
  case $desktop in
    kde)
      pacman -S --noconfirm plasma-pa plasma-nm xdg-desktop-portal-kde kscreen kde-gtk-config breeze-gtk kdeplasma-addons ark sddm konsole dolphin systemsettings plasma-desktop plasma-workspace kinit
      systemctl enable sddm
      ;;
    
    xfce)
      pacman -S --noconfirm xfce4 xfce4-goodies lxdm
      systemctl enable lxdm
      ;;
    
    dwm)
      if ! [ $dwmrepo ]
      then
        dwmrepo="https://github.com/miguelrcborges/dwm.git"
        deps="maim rofi xterm xclip ttf-jetbrains-mono-nerd"
        curl -L "https://raw.githubusercontent.com/miguelrcborges/dotfiles/main/Xresources-desktop/.Xresources" -o /home/$username/.Xresources
        curl -L "https://raw.githubusercontent.com/miguelrcborges/archinstallscript/main/extras/basic_xinitrc" -o /home/$username/.xinitrc
      fi
      
      pacman -S --noconfirm xorg-xinit $deps
      git clone https://github.com/miguelrcborges/dwm.git /home/$username/repos/dwm
      cd /home/$username/repos/dwm
      chown -R $username /home/$username/repos
      
      if [ $dwmrefresh ]
      then
        sed -i "s/static const unsigned int refresh_rate = [0-9]\+;/static const unsigned int refresh_rate = $dwmrefresh;/g" config.h
      fi
      
      make install
      cd
      ;;
    
    *)
      pacman -S --noconfirm mutter gnome-shell gnome-session nautilus gnome-control-center gnome-tweaks xdg-desktop-portal-gnome gdm gnome-terminal 
      systemctl enable gdm
      ;;
  esac
fi
     
