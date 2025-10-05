{
  description = "Neomutt for Gmail - Pre-configured setup for Gmail with lieer, notmuch, and neomutt";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    muttdown.url = "github:jevy/muttdown";
  };

  outputs = { self, nixpkgs, home-manager, muttdown }: {
    homeManagerModules.default = { config, lib, pkgs, ... }:
    let
      muttdownPkg = muttdown.packages.${pkgs.system}.default;
    in {
      options.accounts.email.accounts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
          config = {
            lieer = {
              enable = lib.mkDefault true;
              sync.enable = lib.mkDefault true;
              settings = {
                drop_non_existing_label = lib.mkDefault true;
                ignore_remote_labels = lib.mkDefault [ "important" ];
              };
            };
            notmuch.enable = lib.mkDefault true;
            msmtp.enable = lib.mkDefault true;
            neomutt.enable = lib.mkDefault true;
          };
        }));
      };

      config = {
        home.packages = [ muttdownPkg ];
        
        programs.lieer.enable = lib.mkDefault true;
        programs.notmuch.enable = lib.mkDefault true;
        programs.msmtp.enable = lib.mkDefault true;
        programs.neomutt.enable = lib.mkDefault true;
        
        services.lieer.enable = lib.mkDefault true;
        
        programs.notmuch.new.ignore = [ "/.*[.](json|lock|bak)$/" ];

        home.activation.lieerInit = lib.hm.dag.entryAfter ["writeBoundary"] ''
          ${lib.concatMapStringsSep "\n" (account: ''
            if [ ! -f "${account.maildir.absPath}/.gmailieer.json" ]; then
              $DRY_RUN_CMD mkdir -p "${account.maildir.absPath}"
              $DRY_RUN_CMD ${pkgs.lieer}/bin/gmi -C "${account.maildir.absPath}" init "${account.address}" || true
            fi
          '') (lib.filter (a: a.lieer.enable or false) (lib.attrValues config.accounts.email.accounts))}
        '';

        programs.neomutt = {
          vimKeys = lib.mkDefault true;
          sidebar = {
            enable = lib.mkDefault true;
            shortPath = lib.mkDefault true;
            width = lib.mkDefault 20;
          };
          settings = {
            sendmail = "${muttdownPkg}/bin/muttdown --sendmail-passthru --force-markdown";
            virtual_spoolfile = "yes";
            nm_default_url = "notmuch://$HOME/Mail";
            nm_query_type = "threads";
            sort = "threads";
            sort_aux = "reverse-last-date-received";
            index_format = "%4C %Z %{%b %d} %-15.15L (%?l?%4l&%4c?) %s";
            pager_index_lines = "10";
            pager_context = "3";
            pager_stop = "yes";
            menu_scroll = "yes";
            markers = "no";
            auto_tag = "yes";
          };
          binds = [
            { map = [ "index" "pager" ]; key = "g"; action = "noop"; }
            { map = [ "index" "pager" ]; key = "gi"; action = "<change-vfolder>?"; }
            { map = [ "index" "pager" ]; key = "ga"; action = "<entire-thread>"; }
            { map = [ "index" ]; key = "\\\\"; action = "<vfolder-from-query>"; }
            { map = [ "index" ]; key = "L"; action = "<limit>"; }
          ];
          macros = [
            { map = [ "index" "pager" ]; key = "S"; action = "<modify-labels>+spam -inbox<enter>"; }
            { map = [ "index" "pager" ]; key = "A"; action = "<modify-labels>+archive -inbox<enter>"; }
            { map = [ "index" "pager" ]; key = "I"; action = "<modify-labels>+inbox<enter>"; }
          ];
          extraConfig = ''
            virtual-mailboxes "Inbox" "notmuch://?query=tag:inbox"
            virtual-mailboxes "Unread" "notmuch://?query=tag:unread"
            virtual-mailboxes "Starred" "notmuch://?query=tag:starred"
            virtual-mailboxes "Sent" "notmuch://?query=tag:sent"
            virtual-mailboxes "Drafts" "notmuch://?query=tag:draft"
            virtual-mailboxes "All Mail" "notmuch://?query=*"
          '';
        };
      };
    };

    homeConfigurations.example = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      
      modules = [
        self.homeManagerModules.default
        {
          home.username = "user";
          home.homeDirectory = "/home/user";
          home.stateVersion = "25.05";
          
          programs.home-manager.enable = true;
          
          services.lieer.enable = true;
          
          accounts.email.accounts.gmail = {
            address = "your-email@gmail.com";
            userName = "your-email@gmail.com";
            flavor = "gmail.com";
            passwordCommand = "echo 'change-me'";
            realName = "Your Name";
            primary = true;
            maildir.path = "gmail";
          };
        }
      ];
    };

    checks = let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in forAllSystems (system: let
      checkArgs = {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit self;
      };
    in {
      config-check = import ./tests/config-check.nix checkArgs;
    });
  };
}