{
  description = "VM test environment for neomutt-for-gmail";

  inputs = {
    neomutt-gmail.url = "path:..";
    nixpkgs.follows = "neomutt-gmail/nixpkgs";
    home-manager.follows = "neomutt-gmail/home-manager";
  };

  outputs = { self, nixpkgs, home-manager, neomutt-gmail }: {
    nixosConfigurations.vm-test = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
        home-manager.nixosModules.home-manager
        {
          system.stateVersion = "25.05";

          users.users.testuser = {
            isNormalUser = true;
            password = "test";
            extraGroups = [ "wheel" ];
          };

          virtualisation = {
            memorySize = 2048;
            cores = 2;
          };

          environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            git
          ];

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.testuser = {
              imports = [ neomutt-gmail.homeManagerModules.default ];

              home.username = "testuser";
              home.homeDirectory = "/home/testuser";
              home.stateVersion = "25.05";

              programs.home-manager.enable = true;
              
              services.lieer.enable = true;

              accounts.email.accounts.gmail = {
                address = "test-email@gmail.com";
                userName = "test-email@gmail.com";
                flavor = "gmail.com";
                passwordCommand = "echo 'invalid-password'";
                realName = "Test User";
                primary = true;
                maildir.path = "gmail";
                
                lieer = {
                  enable = true;
                  sync = {
                    enable = true;
                    frequency = "*:0/5";
                  };
                };
                
                notmuch.enable = true;
                msmtp.enable = true;
                neomutt.enable = true;
              };
            };
          };
        }
      ];
    };
  };
}