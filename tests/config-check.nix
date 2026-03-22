(import ./lib.nix) {
  name = "neomutt-gmail-config-check";

  nodes = {
    machine = { self, pkgs, config, ... }: {
      imports = [
        self.inputs.home-manager.nixosModules.home-manager
      ];

      users.users.testuser = {
        isNormalUser = true;
        uid = 1000;
      };

      home-manager.users.testuser = {
        imports = [ self.homeManagerModules.default ];

        home.stateVersion = "23.11";

        accounts.email.accounts.gmail = {
          address = "test@gmail.com";
          userName = "test@gmail.com";
          flavor = "gmail.com";
          passwordCommand = "echo 'test'";
          realName = "Test User";
          primary = true;
          maildir.path = "gmail";
        };
      };
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    # Check neomutt global config
    output = machine.succeed("cat /home/testuser/.config/neomutt/neomuttrc")

    # Muttdown as sendmail
    assert "muttdown --sendmail-passthru --force-markdown" in output, "muttdown not configured as sendmail"

    # Structured binds are present
    assert "next-entry" in output, "vim j bind not found"
    assert "sidebar-prev" in output, "sidebar bind not found"

    # Gmail macros are present
    assert "modify-tags-then-hide" in output, "archive macro not found"
    assert "change-vfolder" in output, "virtual folder navigation macro not found"

    # General settings
    assert "set sleep_time" in output, "general settings not found"
    assert "virtual_spoolfile" in output, "virtual_spoolfile not set"

    # Contact completion
    assert "query-contacts" in output, "query_command not set to query-contacts"
    assert "goobook add" in output, "goobook add macro not found"

    # Colors are present
    assert "color index yellow default" in output, "colors not found"

    # mutt-wizard.muttrc must NOT exist
    machine.succeed("test ! -f /home/testuser/.config/neomutt/mutt-wizard.muttrc")

    # msmtp must NOT be configured
    machine.succeed("test ! -f /home/testuser/.config/msmtp/config")

    # .muttdown.yaml generated with gmi send
    muttdown = machine.succeed("cat /home/testuser/.muttdown.yaml")
    assert "gmi send" in muttdown, ".muttdown.yaml not generated with gmi send"

    # Per-account config has virtual mailboxes
    account_output = machine.succeed("find /home/testuser/.config/neomutt/ -name 'gmail' -exec cat {} \\;")
    assert "Inbox" in account_output, "Inbox virtual mailbox not found in account config"

    print("All config checks passed!")
  '';
}
