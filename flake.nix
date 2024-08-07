{
  description = "A flake to automate building for KSU's DAQ PAQ NAS";

  # Cache to reduce build times dont worry about it
  nixConfig = {
    extra-substituters = [ "https://raspberry-pi-nix.cachix.org" ];
    extra-trusted-public-keys = [
      "raspberry-pi-nix.cachix.org-1:WmV2rdSangxW0rZjY/tBvBDSaNFQ3DyEQsVw8EvHn9o="
    ];
  };

  # All the outside things to fetch from the internet
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    raspberry-pi-nix.url = "github:tstat/raspberry-pi-nix";
  };

  outputs = { self, nixpkgs, raspberry-pi-nix }: rec {
    # shoutout to https://github.com/tstat/raspberry-pi-nix absolute goat
    shared_config = {
      #target architecture
      nixpkgs.hostPlatform.system = "aarch64-linux";

      #NTP
      services.timesyncd.enable = true;

      # Disable signatures
      nix.settings.require-sigs = false;

      # user setup; creates user named nixos and sets up passwords
      users.users.root.initialPassword = "root";
      users.users.nixos.group = "nixos";
      users.users.nixos.password = "nixos";
      users.users.nixos.extraGroups = [ "wheel" ];
      users.users.nixos.isNormalUser = true;

      users.groups.nixos = {}; # Needed for the next bit idk
      system.activationScripts.createRecordingsDir = nixpkgs.lib.stringAfter ["users"] ''
      mkdir -p /home/nixos/raw_logs
      chown nixos:users /home/nixos/raw_logs
      '';

      # Network settings
      networking.hostName = "daq_paq";

      networking.firewall.enable = false;
      networking.useDHCP = false;

      # SSH settings
      services.openssh = { enable = true; };

      users.extraUsers.nixos.openssh.authorizedKeys.keys = [ ];

      systemd.services.sshd.wantedBy =
        nixpkgs.lib.mkOverride 40 [ "multi-user.target" ];

    };

    pi3_config = { pkgs, lib, ... }: {
      # Even more networking config
      networking = {
        interfaces.enu1u1u1.ipv4.addresses = [{ # The pi3 has a diffrent name for some reason
          address = "192.168.1.17"; # Your static IP address
          prefixLength = 24; # Netmask, 24 for 255.255.255.0
        }];
        defaultGateway = "192.168.1.1";
      };
    };

    nixosConfigurations.rpi = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        (
          { pkgs, ... }: {
            config = {
              # Utils and other apps you want
              environment.systemPackages = with pkgs; [
                rsync
                sshpass
              ];

              # Settings for the image that is generated
              sdImage.compressImage = false;
              raspberry-pi-nix.uboot.enable = false;

              systemd.services.start-rsync = {
                description = "Init the rsync command on a directory";
                wantedBy = [ "multi-user.target" ];
                after = [ "network-setup.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${pkgs.sshpass}/bin/sshpass -p nixos ${pkgs.rsync}/bin/rsync  -r nixos@192.168.1.7:/home/nixos/recordings/ /home/nixos/raw_logs/";
                  RemainAfterExit = true;
                };
              };
            };
          }
        )

        # Getting the RPi firmware
        raspberry-pi-nix.nixosModules.raspberry-pi

        # Running the configs made earlier
        shared_config
        pi3_config
      ];
    };

    # Defineing the build commands for the terminal
    images.rpi_sd = nixosConfigurations.rpi.config.system.build.sdImage;
    images.rpi_top = nixosConfigurations.rpi.config.system.build.toplevel;
  };
}
