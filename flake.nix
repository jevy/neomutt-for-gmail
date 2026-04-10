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
      queryContactsPkg = pkgs.callPackage ./pkgs/query-contacts {};
      accounts = lib.attrValues config.accounts.email.accounts;
      primaryAccounts = lib.filter (a: a.primary or false) accounts;
      primaryAccount = if primaryAccounts != [] then lib.head primaryAccounts else null;
    in {
      # Per-account smart defaults
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
                query = "(tag:inbox -tag:promotions -tag:social) OR (tag:inbox and tag:flagged)";
              }
              {
                name = "Starred";
                query = "tag:flagged";
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
                name = "Promotions";
                query = "tag:promotions";
              }
              {
                name = "Social";
                query = "tag:social";
              }
              {
                name = "Spam";
                query = "tag:spam";
              }
              {
                name = "Trash";
                query = "tag:trash";
              }
              {
                name = "Archive";
                query = "not tag:inbox and not tag:spam and not tag:trash";
              }
              {
                name = "All Mail";
                query = "*";
              }
            ];
            msmtp.enable = lib.mkDefault false;
            neomutt.enable = lib.mkDefault true;
            neomutt.showDefaultMailbox = lib.mkDefault false;
            neomutt.extraConfig = lib.mkIf (config.neomutt.enable or false) ''
              # Override home-manager's folder-hook spoolfile (physical path)
              # with notmuch virtual mailbox name
              unset spoolfile
              set spoolfile = "Inbox"
            '';
          };
        }));
      };

      config = {
        home.packages = [muttdownPkg pkgs.urlscan pkgs.goobook queryContactsPkg pkgs.w3m pkgs.catdoc pkgs.pandoc pkgs.poppler-utils];

        programs.lieer.enable = lib.mkDefault true;
        programs.notmuch.enable = lib.mkDefault true;
        programs.msmtp.enable = lib.mkDefault false;
        programs.neomutt.enable = lib.mkDefault true;

        services.lieer.enable = lib.mkDefault true;

        # Override lieer systemd services to:
        # 1. Use --resume so interrupted full pulls continue where they left off
        # 2. Run notmuch new after sync so the index stays up to date
        # 3. Watchdog-based liveness: kill only when gmi stops producing output
        # 4. Generous burst limit to survive transient DNS/network issues
        # 5. Memory cap to prevent runaway usage
        systemd.user.services = lib.mkMerge (map (account:
          let
            name = "lieer-${account.name}";
            # Wrapper that pipes gmi output and pings the systemd watchdog on activity.
            # If gmi goes silent for WatchdogSec, systemd kills it as stuck.
            gmiWatchdog = pkgs.writeShellScript "gmi-watchdog" ''
              set -o pipefail
              ${pkgs.systemd}/bin/systemd-notify --ready
              # stdbuf -oL: force line-buffered output so dots/messages flush
              # through the pipe immediately instead of sitting in an 8KB buffer.
              # read -r line: ping watchdog once per line (sufficient for 5m window).
              ${pkgs.coreutils}/bin/stdbuf -oL \
                ${pkgs.lieer}/bin/gmi sync --resume 2>&1 |
              while IFS= read -r line; do
                ${pkgs.systemd}/bin/systemd-notify WATCHDOG=1
                printf '%s\n' "$line"
              done
            '';
          in {
            ${name} = {
              Unit = {
                After = [ "network-online.target" ];
                Wants = [ "network-online.target" ];
                StartLimitIntervalSec = 3600;
                StartLimitBurst = 10;
              };
              Service = {
                ExecStart = lib.mkForce "${gmiWatchdog}";
                ExecStartPost = "${pkgs.notmuch}/bin/notmuch --config=${config.home.homeDirectory}/.config/notmuch/default/config new";
                Type = lib.mkForce "notify";
                NotifyAccess = "all";
                WatchdogSec = "5m";
                Restart = "on-abnormal";
                RestartSec = 60;
                TimeoutStartSec = "infinity";
                MemoryMax = "2G";
              };
            };
          }
        ) (lib.filter (a: a.lieer.enable or false) (lib.attrValues config.accounts.email.accounts)));

        # new.tags must be empty with lieer — lieer manages all tags via Gmail labels.
        # Default "unread;inbox" would tag every synced message as unread inbox.
        programs.notmuch.new.tags = lib.mkDefault [];
        programs.notmuch.new.ignore = ["/.*[.](json|lock|bak)$/"];
        programs.notmuch.search.excludeTags = lib.mkDefault ["deleted" "spam"];
        programs.notmuch.maildir.synchronizeFlags = lib.mkDefault false;

        home.activation.lieerInit = lib.hm.dag.entryAfter ["writeBoundary"] ''
          ${lib.concatMapStringsSep "\n" (account: ''
            # Create the maildir structure that lieer expects (mail/{cur,new,tmp}).
            $DRY_RUN_CMD mkdir -p "${account.maildir.absPath}/mail/"{cur,new,tmp}

            # Create placeholder maildir folders for home-manager's neomutt MRA section.
            # The neomutt module generates 'set spoolfile=+INBOX' etc. assuming physical
            # IMAP folders, but with lieer+notmuch we use virtual mailboxes instead.
            # These empty dirs prevent "is not a mailbox" errors on folder changes.
            for box in INBOX Sent Drafts Trash; do
              $DRY_RUN_CMD mkdir -p "${account.maildir.absPath}/$box/"{cur,new,tmp}
            done

            if [ ! -f "${account.maildir.absPath}/.credentials.gmailieer.json" ]; then
              # No OAuth credentials yet — run gmi init to trigger the auth flow.
              $DRY_RUN_CMD ${pkgs.lieer}/bin/gmi -C "${account.maildir.absPath}" init "${account.address}" || true
            fi
          '') (lib.filter (a: a.lieer.enable or false) (lib.attrValues config.accounts.email.accounts))}

          # Initialize/update notmuch database after maildir structure exists
          $DRY_RUN_CMD ${pkgs.notmuch}/bin/notmuch --config="${config.home.homeDirectory}/.config/notmuch/default/config" new || true
        '';

        # Generate .muttdown.yaml for markdown email sending via gmi
        home.file.".muttdown.yaml" = lib.mkIf (primaryAccount != null) {
          text = lib.mkDefault "sendmail: gmi send -t -C ${primaryAccount.maildir.absPath}";
        };

        # Urlscan: vim-like keybindings, l to open URL
        xdg.configFile."urlscan/config.json".text = lib.mkDefault (builtins.toJSON {
          keys = {
            "0" = "digits";
            "1" = "digits";
            "2" = "digits";
            "3" = "digits";
            "4" = "digits";
            "5" = "digits";
            "6" = "digits";
            "7" = "digits";
            "8" = "digits";
            "9" = "digits";
            j = "down";
            k = "up";
            "ctrl d" = "page_down";
            "ctrl u" = "page_up";
            g = "top";
            G = "bottom";
            J = "next";
            K = "previous";
            l = "open_url";
            enter = "open_url";
            "/" = "search_key";
            c = "context";
            C = "clipboard";
            P = "clipboard_pri";
            d = "del_url";
            a = "add_url";
            o = "open_queue";
            O = "open_queue_win";
            s = "shorten";
            S = "all_shorten";
            u = "all_escape";
            R = "reverse";
            q = "quit";
            Q = "quit";
            p = "palette";
            f1 = "help_menu";
            H = "help_menu";
            "ctrl l" = "clear_screen";
          };
        });

        # Mailcap: GUI viewers for interactive use (view-mailcap / "l" key),
        # then inline viewers with copiousoutput for auto_view preview
        xdg.configFile."mailcap".text = lib.mkDefault ''
          text/html; firefox %s &; nametemplate=%s.html; test=test -n "$DISPLAY"
          application/pdf; zathura %s &; test=test -n "$DISPLAY"
          application/msword; xdg-open %s &; test=test -n "$DISPLAY"
          application/vnd.openxmlformats-officedocument.wordprocessingml.document; xdg-open %s &; test=test -n "$DISPLAY"
          application/vnd.oasis.opendocument.text; xdg-open %s &; test=test -n "$DISPLAY"
          text/html; ${pkgs.w3m}/bin/w3m -dump -T text/html -cols 120 -o display_borders=1 -o display_link=0 -s; nametemplate=%s.html; copiousoutput
          application/msword; ${pkgs.catdoc}/bin/catdoc %s; copiousoutput
          application/vnd.openxmlformats-officedocument.wordprocessingml.document; ${pkgs.pandoc}/bin/pandoc --from docx --to markdown %s; copiousoutput
          application/vnd.oasis.opendocument.text; ${pkgs.pandoc}/bin/pandoc --from odt --to markdown %s; copiousoutput
          application/pdf; ${pkgs.poppler-utils}/bin/pdftotext -layout %s -; copiousoutput
          application/*; xdg-open %s &; test=test -n "$DISPLAY"
          image/*; xdg-open %s &; test=test -n "$DISPLAY"
          video/*; xdg-open %s &; test=test -n "$DISPLAY"
          audio/*; xdg-open %s &; test=test -n "$DISPLAY"
        '';

        programs.neomutt = {
          vimKeys = lib.mkDefault true;
          sidebar = {
            enable = lib.mkDefault true;
            shortPath = lib.mkDefault true;
            width = lib.mkDefault 20;
          };
          unmailboxes = lib.mkDefault true;

          settings = {
            sendmail = lib.mkDefault "\"${muttdownPkg}/bin/muttdown --sendmail-passthru --force-markdown\"";
            spoolfile = lib.mkDefault "\"Inbox\"";
            nm_default_url = lib.mkDefault "\"notmuch://$HOME/Maildir\"";
            nm_db_limit = lib.mkDefault "\"5000\"";
            mailcap_path = lib.mkDefault "\"~/.config/mailcap\"";
            use_envelope_from = lib.mkDefault "yes";
            query_command = lib.mkDefault "\"query-contacts %s\"";
            # Preserve query-contacts' match-quality ordering — neomutt defaults
            # to alias_sort=alias (alphabetical), which re-sorts results and defeats
            # the fuzzy-match ranking from fzf.
            sort_alias = lib.mkDefault "unsorted";
          };

          # Vim-style keybindings (replaces mutt-wizard.muttrc binds)
          binds = [
            # Noop guards — prevent accidental moves/copies/etc
            # gT must come before gg/gi/etc to avoid alias warnings
            { map = ["index" "pager"]; key = "gT"; action = "noop"; }
            { map = ["index" "pager"]; key = "M"; action = "noop"; }
            { map = ["index" "pager"]; key = "C"; action = "noop"; }
            { map = ["index" "pager"]; key = "i"; action = "noop"; }
            { map = ["index"]; key = "\\Cf"; action = "noop"; }

            # Vim navigation
            { map = ["index"]; key = "j"; action = "next-entry"; }
            { map = ["index"]; key = "k"; action = "previous-entry"; }
            { map = ["index"]; key = "G"; action = "last-entry"; }
            { map = ["index"]; key = "gg"; action = "first-entry"; }
            { map = ["index"]; key = "l"; action = "display-message"; }
            { map = ["index"]; key = "h"; action = "noop"; }
            { map = ["index"]; key = "L"; action = "limit"; }
            { map = ["index" "query"]; key = "<space>"; action = "tag-entry"; }
            { map = ["index" "pager"]; key = "H"; action = "view-raw-message"; }
            { map = ["index" "pager"]; key = "S"; action = "sync-mailbox"; }
            { map = ["index" "pager"]; key = "R"; action = "group-reply"; }
            { map = ["index" "pager" "browser"]; key = "\\Cu"; action = "half-up"; }
            { map = ["index" "pager" "browser"]; key = "\\Cd"; action = "half-down"; }

            # Pager
            { map = ["pager" "attach"]; key = "h"; action = "exit"; }
            { map = ["pager"]; key = "j"; action = "next-line"; }
            { map = ["pager"]; key = "k"; action = "previous-line"; }
            { map = ["pager"]; key = "l"; action = "view-attachments"; }
            { map = ["pager" "browser"]; key = "gg"; action = "top-page"; }
            { map = ["pager" "browser"]; key = "G"; action = "bottom-page"; }

            # Attachments
            { map = ["attach"]; key = "<return>"; action = "view-mailcap"; }
            { map = ["attach"]; key = "l"; action = "view-mailcap"; }

            # Browser
            { map = ["browser"]; key = "l"; action = "select-entry"; }

            # Editor
            { map = ["editor"]; key = "<space>"; action = "noop"; }
            { map = ["editor"]; key = "<Tab>"; action = "complete-query"; }

            # Mouse wheel
            { map = ["index"]; key = "\\031"; action = "previous-undeleted"; }
            { map = ["index"]; key = "\\005"; action = "next-undeleted"; }
            { map = ["pager"]; key = "\\031"; action = "previous-line"; }
            { map = ["pager"]; key = "\\005"; action = "next-line"; }

            # Sidebar
            { map = ["index" "pager"]; key = "\\Ck"; action = "sidebar-prev"; }
            { map = ["index" "pager"]; key = "\\Cj"; action = "sidebar-next"; }
            { map = ["index" "pager"]; key = "\\Co"; action = "sidebar-open"; }
            { map = ["index" "pager"]; key = "\\Cp"; action = "sidebar-prev-new"; }
            { map = ["index" "pager"]; key = "\\Cn"; action = "sidebar-next-new"; }
            { map = ["index" "pager"]; key = "B"; action = "sidebar-toggle-visible"; }
          ];

          # Gmail-specific macros (using notmuch virtual mailboxes)
          macros = [
            # Compose
            { map = ["index" "pager"]; key = "c"; action = "<mail>"; }

            # Gmail tag operations
            { map = ["index" "pager"]; key = "e"; action = "<modify-tags-then-hide>-inbox -unread<enter><sync-mailbox>"; }
            { map = ["index" "pager"]; key = "E"; action = "<modify-tags>+inbox<enter>"; }

            # Virtual mailbox navigation
            { map = ["index" "pager"]; key = "gi"; action = "<change-vfolder>Inbox<enter>"; }
            { map = ["index" "pager"]; key = "gd"; action = "<change-vfolder>Drafts<enter>"; }
            { map = ["index" "pager"]; key = "gs"; action = "<change-vfolder>Sent<enter>"; }
            { map = ["index" "pager"]; key = "gt"; action = "<change-vfolder>Trash<enter>"; }
            { map = ["index" "pager"]; key = "ga"; action = "<change-vfolder>Archive<enter>"; }
            { map = ["index" "pager"]; key = "gj"; action = "<change-vfolder>Spam<enter>"; }

            # Utilities
            { map = ["index"]; key = "\\Cr"; action = "T~U<enter><tag-prefix><clear-flag>N<untag-pattern>.<enter>"; }
            { map = ["index"]; key = "O"; action = "<shell-escape>systemctl --user start lieer-${primaryAccount.name}.service<enter>"; }
            { map = ["index"]; key = "\\Cf"; action = "<vfolder-from-query>"; }
            { map = ["index"]; key = "A"; action = "<limit>all<enter>"; }

            # Contacts
            { map = ["index" "pager"]; key = "a"; action = "<pipe-message>goobook add<return>"; }

            # URL scanning
            { map = ["index" "pager"]; key = "\\cb"; action = "<pipe-message>urlscan -d -W<Enter>"; }
            { map = ["attach" "compose"]; key = "\\cb"; action = "<pipe-entry>urlscan -d -W<Enter>"; }

            # Save attachments to Downloads
            { map = ["attach"]; key = "S"; action = "<save-entry><bol>~/Downloads/<eol>"; }
            { map = ["attach"]; key = "s"; action = "<save-entry><bol>~/Downloads/<eol><enter>"; }

            # Browser
            { map = ["browser"]; key = "h"; action = "<change-dir><kill-line>..<enter>"; }
          ];

          extraConfig = ''
            # Character encoding
            set send_charset="us-ascii:utf-8"

            # Display
            set date_format="%y/%m/%d %I:%M%p"
            set index_format="%2C %Z %?X?A& ? %D %-15.15F %s (%-4.4c)"
            set rfc2047_parameters = yes
            set sleep_time = 0
            set markers = no
            set mark_old = no
            set wait_key = no
            set fast_reply
            set fcc_attach
            set forward_format = "Fwd: %s"
            set forward_quote
            set reverse_name
            set include
            set pager_stop = yes
            set abort_backspace = no

            # Sidebar
            set sidebar_next_new_wrap = yes
            set mail_check_stats
            set sidebar_format = '%D%?F? [%F]?%* %?N?%N/? %?S?%S?'

            # MIME
            set mime_forward = yes
            set mime_forward_rest = yes
            set mime_type_query_command = "file --mime-type -b %s"
            auto_view text/html
            auto_view application/pgp-encrypted
            auto_view application/msword
            auto_view application/vnd.openxmlformats-officedocument.wordprocessingml.document
            auto_view application/vnd.oasis.opendocument.text
            auto_view application/pdf
            unalternative_order *
            alternative_order text/enriched text/html text/plain
            set display_filter = "tac | sed '/\\\[-- Autoview/,+1d' | tac"

            # Notmuch
            set virtual_spoolfile
            set nm_unread_tag = "unread"

            # Colors: left to user/stylix — no defaults here
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
