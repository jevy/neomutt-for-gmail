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

  outputs = {
    self,
    nixpkgs,
    home-manager,
    muttdown,
  }: {
    homeManagerModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      muttdownPkg = muttdown.packages.${pkgs.system}.default;
    in {
      options.accounts.email.accounts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({config, ...}: {
          config = {
            lieer = {
              enable = lib.mkDefault true;
              sync.enable = lib.mkDefault true;
              settings = {
                drop_non_existing_label = lib.mkDefault true;
                ignore_remote_labels = lib.mkDefault ["important"];
              };
            };
            notmuch.enable = lib.mkDefault true;
            notmuch.neomutt.virtualMailboxes = lib.mkDefault [
              {
                name = "Inbox";
                query = "tag:inbox";
              }
              {
                name = "Unread";
                query = "tag:unread";
              }
              {
                name = "Starred";
                query = "tag:starred";
              }
              {
                name = "Sent";
                query = "tag:sent";
              }
              {
                name = "Drafts";
                query = "tag:draft";
              }
              {
                name = "All Mail";
                query = "*";
              }
            ];
            msmtp.enable = lib.mkDefault true;
            neomutt.enable = lib.mkDefault true;
            # Override the genCommonFolderHooks to use virtual mailbox instead of maildir folder
            neomutt.showDefaultMailbox = lib.mkDefault false;
            neomutt.extraConfig = lib.mkIf (config.neomutt.enable or false) ''
              # Explicitly unset incorrect settings from Home Manager module
              unset spoolfile
              unset nm_default_uri

              # Set correct values for notmuch virtual mailboxes
              set spoolfile = "Inbox"
              set nm_default_url = "notmuch://$HOME/Maildir"

              macro index \Cr "T~U<enter><tag-prefix><clear-flag>N<untag-pattern>.<enter>" "mark all messages as read"
              macro index O "<shell-escape>mailsync<enter>" "run mailsync to sync all mail"
              macro index \Cf "<enter-command>unset wait_key<enter><shell-escape>printf 'Enter a search term to find with notmuch: '; read x; echo \$x >\"''${XDG_CACHE_HOME:-$HOME/.cache}/mutt_terms\"<enter><limit>~i \"\`notmuch search --output=messages \$(cat \"''${XDG_CACHE_HOME:-$HOME/.cache}/mutt_terms\") | head -n 600 | perl -le '@a=<>;s/\^id:// for@a;$,=\"|\";print@a' | perl -le '@a=<>; chomp@a; s/\\+/\\\\+/g for@a; s/\\$/\\\\\\$/g for@a;print@a' \`\"<enter>" "show only messages matching a notmuch pattern"
              macro index A "<limit>all\n" "show all messages (undo limit)"

            '';
          };
        }));
      };

      config = {
        home.packages = [muttdownPkg];

        programs.lieer.enable = lib.mkDefault true;
        programs.notmuch.enable = lib.mkDefault true;
        programs.msmtp.enable = lib.mkDefault true;
        programs.neomutt.enable = lib.mkDefault true;

        services.lieer.enable = lib.mkDefault true;

        programs.notmuch.new.ignore = ["/.*[.](json|lock|bak)$/"];

        home.activation.lieerInit = lib.hm.dag.entryAfter ["writeBoundary"] ''
          ${lib.concatMapStringsSep "\n" (account: ''
            if [ ! -f "${account.maildir.absPath}/.gmailieer.json" ]; then
              $DRY_RUN_CMD mkdir -p "${account.maildir.absPath}"
              $DRY_RUN_CMD ${pkgs.lieer}/bin/gmi -C "${account.maildir.absPath}" init "${account.address}" || true
            fi
          '') (lib.filter (a: a.lieer.enable or false) (lib.attrValues config.accounts.email.accounts))}
        '';

        # Copy mutt-wizard configuration file
        home.file.".config/neomutt/mutt-wizard.muttrc".source = ./mutt-wizard.muttrc;

        programs.neomutt = {
          vimKeys = lib.mkDefault true;
          sidebar = {
            enable = lib.mkDefault true;
            shortPath = lib.mkDefault true;
            width = lib.mkDefault 20;
          };
          unmailboxes = lib.mkDefault true; # Remove previous sidebar mailboxes when sourcing accounts
          extraConfig = ''
            # Include mutt-wizard custom configuration
            source ${config.home.homeDirectory}/.config/neomutt/mutt-wizard.muttrc
          '';
          settings = {
            sendmail = "\"${muttdownPkg}/bin/muttdown --sendmail-passthru --force-markdown\"";
            spoolfile = "Inbox";
            nm_default_url = "notmuch://$HOME/Maildir";
            # virtual_spool_file = "Inbox";
            # nm_query_type = "threads";
          };
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
      forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];
    in
      forAllSystems (system: let
        checkArgs = {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit self;
        };
      in {
        config-check = import ./tests/config-check.nix checkArgs;
      });
  };
}
