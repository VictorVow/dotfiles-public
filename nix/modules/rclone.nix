{ config, lib, ... }:

# Declarative rclone remotes via Home Manager's programs.rclone.
#
# The HM module installs ~/.config/rclone/rclone.conf on login via a systemd
# user oneshot (rclone-config.service) that renders the INI from `config` attrs
# (which land in the world-readable Nix store) and then injects each `secrets`
# value — read from a file at activation — with `rclone config update`. So:
#   - NON-sensitive fields  -> `config`  (inline below)
#   - sensitive fields      -> `secrets` (file paths from sops, never in store)
#
# Secrets live encrypted (age) in ../secrets/rclone.yaml; sops-nix decrypts them
# to runtime files at activation, and the rclone module auto-detects sops and
# orders rclone-config.service after sops-nix.service.
#
# crypt password/password2 are rclone-OBSCURED values stored verbatim: rclone
# detects an already-obscured value on inject and leaves it untouched (verified).
#
# NOTE: this REPLACES the previously hand-managed, password-encrypted
# rclone.conf with a plaintext (mode 0600) file. Encryption-at-rest for the
# config itself is dropped; the credentials inside are instead protected in-repo
# by sops. The live rclone.conf is no longer encrypted, so `rclone` no longer
# prompts for a config password.

let
  s = config.sops.secrets;

  # Every secret key present in ../secrets/rclone.yaml.
  secretNames = [
    "wasabi1_access_key_id"
    "wasabi1_secret_access_key"
    "crypt_dbtf_password"
    "crypt_dbtf_password2"
    "dropbox_user_token"
    "dropbox_tomfolder_token"
    "backblazeb2_account"
    "backblazeb2_key"
    "gdrive_client_id"
    "gdrive_client_secret"
    "gdrive_token"
    "crypt_bb2_password"
    "crypt_bb2_password2"
    "amazons3_access_key_id"
    "amazons3_secret_access_key"
    "crypt_transcend_password"
    "crypt_transcend_password2"
    "crypt_storj_password"
    "crypt_storj_password2"
    "storj1_access_key_id"
    "storj1_secret_access_key"
    "b2_account"
    "b2_key"
    "secret_password"
    "secret_password2"
  ];
in
{
  sops = {
    # Private age identity (never committed). Matches the recipient in .sops.yaml.
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../secrets/rclone.yaml;
    secrets = lib.genAttrs secretNames (_: { });
  };

  programs.rclone = {
    enable = true;

    remotes = {
      # ── Existing remotes (migrated from the encrypted rclone.conf) ──────────

      Wasabi1 = {
        config = {
          type = "s3";
          provider = "Wasabi";
          env_auth = false;
          region = "eu-central-1";
          endpoint = "s3.eu-central-1.wasabisys.com";
          acl = "private";
        };
        secrets = {
          access_key_id = s.wasabi1_access_key_id.path;
          secret_access_key = s.wasabi1_secret_access_key.path;
        };
      };

      "crypt-dbtf_dropbox-rclone1" = {
        config = {
          type = "crypt";
          remote = "Dropbox-tomfolder:dropbox-rclone1";
          filename_encryption = "standard";
          directory_name_encryption = true;
        };
        secrets = {
          password = s.crypt_dbtf_password.path;
          password2 = s.crypt_dbtf_password2.path;
        };
      };

      "Dropbox-user" = {
        config.type = "dropbox";
        secrets.token = s.dropbox_user_token.path;
      };

      "Dropbox-tomfolder" = {
        config.type = "dropbox";
        secrets.token = s.dropbox_tomfolder_token.path;
      };

      BackblazeB2 = {
        config = {
          type = "b2";
          hard_delete = false;
        };
        secrets = {
          account = s.backblazeb2_account.path;
          key = s.backblazeb2_key.path;
        };
      };

      "GDrive-user" = {
        config = {
          type = "drive";
          scope = "drive";
        };
        secrets = {
          client_id = s.gdrive_client_id.path;
          client_secret = s.gdrive_client_secret.path;
          token = s.gdrive_token.path;
        };
      };

      "crypt_BackblazeB2_backblaze-rclone1" = {
        config = {
          type = "crypt";
          remote = "BackblazeB2:backblaze-rclone1";
          filename_encryption = "standard";
          directory_name_encryption = true;
        };
        secrets = {
          password = s.crypt_bb2_password.path;
          password2 = s.crypt_bb2_password2.path;
        };
      };

      AmazonS3 = {
        config = {
          type = "s3";
          provider = "AWS";
          env_auth = false;
          region = "eu-central-1";
          location_constraint = "EU";
        };
        secrets = {
          access_key_id = s.amazons3_access_key_id.path;
          secret_access_key = s.amazons3_secret_access_key.path;
        };
      };

      "crypt-SSD-Transcend1TB-2-Rclone" = {
        config = {
          type = "crypt";
          remote = "/media/boss/Transcend/2-Rclone";
          filename_encryption = "standard";
          directory_name_encryption = true;
        };
        secrets = {
          password = s.crypt_transcend_password.path;
          password2 = s.crypt_transcend_password2.path;
        };
      };

      "crypt-Storj1_storj-s3-q4fwe6" = {
        config = {
          type = "crypt";
          remote = "Storj1:storj-s3-q4fwe6";
        };
        secrets = {
          password = s.crypt_storj_password.path;
          password2 = s.crypt_storj_password2.path;
        };
      };

      Storj1 = {
        config = {
          type = "s3";
          provider = "Storj";
          endpoint = "gateway.eu1.storjshare.io";
        };
        secrets = {
          access_key_id = s.storj1_access_key_id.path;
          secret_access_key = s.storj1_secret_access_key.path;
        };
      };

      # ── Remotes from Self-Hosted/Rclone (.env declarative definitions) ──────

      b2 = {
        config.type = "b2";
        secrets = {
          account = s.b2_account.path;
          key = s.b2_key.path;
        };
      };

      secret = {
        config = {
          type = "crypt";
          remote = "b2:rclone-lord-ubuntu/encrypted";
        };
        secrets = {
          password = s.secret_password.path;
          password2 = s.secret_password2.path;
        };
      };
    };
  };
}
